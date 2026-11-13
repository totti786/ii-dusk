pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * Bridge to scripts/soundscapes/soundscapes.py, the ambient mixer's detached playback daemon.
 *
 * The daemon owns the mix (one mpv per sound, volumes, the sleep timer, saved mixes) so
 * sound goes on when the window closes or the shell reloads. While something holds the
 * service (`retain` / `release`, the window does) this keeps a socket to it open and the
 * daemon pushes its state down it; with nothing holding it a command is a one-shot `ctl`.
 *
 *   catalog.sounds[]  { id, name, group, groupId, tags, silence, icon, clips[], credits[] }
 *   mix[id]           { on, vol, spacing }
 */
Singleton {
    id: root

    readonly property string script: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/soundscapes/soundscapes.py`
    readonly property string libraryDir: String(Config.options.soundscapes?.libraryDir ?? "~/.local/share/soundscapes")
    readonly property string sockPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/soundscapes.sock`

    // ── the library ──
    property var catalog: ({ groups: [], sounds: [], presets: [] })
    property var byId: ({})
    property bool catalogLoaded: false
    property string catalogError: ""
    readonly property var sounds: root.catalog.sounds ?? []
    /// No manifest at all: the library has to be downloaded before anything can be listed.
    property bool needsDownload: false
    property int missingClips: 0
    property int totalClips: 0

    // ── downloading what is missing ──
    property bool downloading: false
    property int downloadDone: 0
    property int downloadTotal: 0
    property string downloadSound: ""
    property string downloadError: ""
    readonly property real downloadProgress: root.downloadTotal > 0 ? root.downloadDone / root.downloadTotal : 0

    function download(): void {
        if (root.downloading)
            return;
        root.downloadError = "";
        root.downloadDone = 0;
        root.downloadTotal = 0;
        root.downloadSound = "";
        root.downloading = true;
        downloadProc.running = true;
    }

    Process {
        id: downloadProc
        command: ["python3", "-I", root.script, "--lib", root.libraryDir, "download"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const m = JSON.parse(line);
                    if (m.event === "start") {
                        root.downloadTotal = m.total ?? 0;
                    } else if (m.event === "progress") {
                        root.downloadDone = m.done ?? 0;
                        root.downloadTotal = m.total ?? root.downloadTotal;
                        root.downloadSound = m.sound ?? "";
                    } else if (m.event === "done") {
                        if (!m.ok)
                            root.downloadError = m.error ?? Translation.tr("%1 files could not be downloaded").arg(m.failed ?? 0);
                    }
                } catch (e) {}
            }
        }
        onExited: (code, status) => {
            root.downloading = false;
            if (code !== 0 && root.downloadError.length === 0)
                root.downloadError = Translation.tr("The download stopped unexpectedly");
            root.loadCatalog();
            // A daemon that is already running read the library before the new files came
            if (root.linked)
                root.send({ cmd: "reload_catalog" });
            else
                root.runOnce(["reload_catalog"]);
        }
    }
    readonly property var groups: root.catalog.groups ?? []

    // ── the mix, as the daemon reports it ──
    property bool linked: false
    property var active: []
    property var mix: ({})
    property bool playing: false
    property bool paused: false
    property real master: 0.8
    property real timerEnd: 0
    property real timerTotal: 0
    property real timerFade: 30
    property real clockSkew: 0           // daemon clock minus ours, so a countdown does not drift
    property string preset: ""
    property var userPresets: []
    readonly property var presets: (root.catalog.presets ?? []).concat(root.userPresets)
    readonly property int activeCount: root.active.length
    readonly property bool hasMix: root.active.length > 0

    function sound(id: string): var {
        return root.byId[id] ?? null;
    }

    function stateOf(id: string): var {
        return root.mix[id] ?? { on: false, vol: 0.6, spacing: 0.1 };
    }

    function isOn(id: string): bool {
        return root.mix[id]?.on === true;
    }

    /// Seconds until the sleep timer ends; 0 when none is running. Re-evaluated on `tick`.
    property real tick: 0
    readonly property real timerLeft: {
        root.tick;
        return root.timerEnd > 0 ? Math.max(0, root.timerEnd - (Date.now() / 1000 + root.clockSkew)) : 0;
    }
    readonly property bool timerRunning: root.timerEnd > 0

    Timer {
        interval: 1000
        repeat: true
        running: root.timerEnd > 0 && root.listening
        onTriggered: root.tick++
    }

    // ── holding the service ──
    property int holders: 0
    readonly property bool wanted: root.holders > 0
    function retain(): void { root.holders++; }
    function release(): void { root.holders = Math.max(0, root.holders - 1); }

    // ── watching without owning ──
    // The island shows a bubble while a mix plays. It only *looks*: it never starts the daemon
    // (an idle one exits on its own after a quiet spell) and, being a passive subscriber, it does
    // not keep it from doing so. With the daemon away it just checks for its socket now and then.
    property int watchers: 0
    readonly property bool listening: root.wanted || root.watchers > 0
    function watch(): void { root.watchers++; }
    function unwatch(): void { root.watchers = Math.max(0, root.watchers - 1); }

    onWatchersChanged: {
        if (root.wanted)
            return;
        if (root.watchers > 0) {
            // Look straight away: a daemon that is already up should not be waited for
            if (!root.linked)
                probeProc.running = true;
        } else {
            root.dropLink();
        }
    }

    /// Nothing is looking any more: let go of the daemon and forget what it said.
    function dropLink(): void {
        probe.stop();
        probeProc.running = false;
        retry.stop();
        sock.connected = false;
        root.outbox = [];
        root.forgetMix();
    }

    function forgetMix(): void {
        root.mix = {};
        root.active = [];
        root.playing = false;
        root.paused = false;
        root.timerEnd = 0;
        root.timerTotal = 0;
        root.preset = "";
    }

    function subscribeAs(passive: bool): void {
        sock.write(JSON.stringify({ cmd: "subscribe", passive: passive }) + "\n");
        sock.flush();
    }

    // Is there a daemon to look at? A missing socket makes a connect fail loudly, so ask the
    // filesystem first.
    Timer {
        id: probe
        interval: 5000
        repeat: false
        onTriggered: if (!root.wanted && root.watchers > 0 && !root.linked) probeProc.running = true
    }
    Process {
        id: probeProc
        command: ["test", "-S", root.sockPath]
        onExited: (code, status) => {
            if (root.wanted || root.watchers === 0 || root.linked)
                return;
            if (code === 0) {
                // A failed connect leaves `connected` as it was, and setting true over true does
                // nothing: go through false so that every attempt really is one.
                sock.connected = false;
                sock.connected = true;
            } else
                probe.restart();
        }
    }

    onWantedChanged: {
        if (root.wanted) {
            probe.stop();
            if (!root.catalogLoaded)
                root.loadCatalog();
            if (root.linked)
                root.subscribeAs(false);        // from watching to holding the daemon up
            else
                root.connectDaemon();
        } else if (root.watchers > 0) {
            retry.stop();
            root.outbox = [];
            if (root.linked)
                root.subscribeAs(true);         // back to just watching
            else
                probe.restart();
        } else {
            root.dropLink();
        }
    }
    onLibraryDirChanged: {
        root.catalogLoaded = false;
        if (root.wanted) {
            // A daemon started with the old library keeps it: ask it to go, the next call restarts it.
            root.runOnce(["quit"]);
            root.loadCatalog();
        } else if (root.linked) {
            root.loadCatalog();
        }
    }

    function loadCatalog(): void {
        catalogProc.running = false;
        catalogProc.running = true;
    }

    Process {
        id: catalogProc
        command: ["python3", "-I", root.script, "--lib", root.libraryDir, "catalog"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const c = JSON.parse(text);
                    const byId = {};
                    for (const s of c.sounds ?? [])
                        byId[s.id] = s;
                    root.byId = byId;
                    root.catalog = c;
                    root.catalogError = c.error ?? "";
                    root.needsDownload = c.needsDownload === true;
                    root.missingClips = c.missingClips ?? 0;
                    root.totalClips = c.totalClips ?? 0;
                    root.catalogLoaded = true;
                    if (root.wanted)
                        root.connectDaemon();
                } catch (e) {
                    root.catalogError = Translation.tr("The sound library could not be read");
                    root.catalogLoaded = true;
                }
            }
        }
    }

    // ── talking to the daemon ──
    property var outbox: []

    function send(msg: var): void {
        if (root.linked) {
            sock.write(JSON.stringify(msg) + "\n");
            sock.flush();
            return;
        }
        if (!root.wanted) {
            // No window: one `ctl` call, which starts the daemon if it is not up
            const argv = ["python3", "-I", root.script, "--lib", root.libraryDir, "ctl", msg.cmd];
            for (const k of Object.keys(msg)) {
                if (k !== "cmd")
                    argv.push(`${k}=${msg[k]}`);
            }
            Quickshell.execDetached(argv);
            return;
        }
        root.outbox.push(msg);
        root.connectDaemon();
    }

    function runOnce(argv: var): void {
        Quickshell.execDetached(["python3", "-I", root.script, "--lib", root.libraryDir, "ctl"].concat(argv));
    }

    function connectDaemon(): void {
        // The daemon reads the library when it starts, so it waits for one to exist
        if (root.linked || ensureProc.running || !root.catalogLoaded || root.sounds.length === 0)
            return;
        ensureProc.running = true;
    }

    Socket {
        id: sock
        path: root.sockPath
        connected: false
        parser: SplitParser {
            onRead: line => {
                try {
                    const msg = JSON.parse(line);
                    if (msg.event === "state")
                        root.applyState(msg);
                } catch (e) {}
            }
        }
        onConnectedChanged: {
            root.linked = sock.connected;
            if (sock.connected) {
                if (!root.listening) {
                    // Everyone let go while this was connecting.
                    sock.connected = false;
                    return;
                }
                sock.write(JSON.stringify({ cmd: "subscribe", passive: !root.wanted }) + "\n");
                for (const m of root.outbox)
                    sock.write(JSON.stringify(m) + "\n");
                root.outbox = [];
                sock.flush();
                // Names and pictograms for what is playing, read now that there is something to read about
                if (!root.catalogLoaded)
                    root.loadCatalog();
            } else if (root.wanted) {
                retry.restart();
            } else if (root.watchers > 0) {
                // The daemon went away (it left after a quiet spell, or was told to quit)
                root.forgetMix();
                probe.restart();
            }
        }
        // A failed connect never flips `connected`, so it has to be retried from here
        onError: {
            if (root.wanted)
                retry.restart();
            else if (root.watchers > 0)
                probe.restart();
        }
    }

    // `ctl state` starts the daemon when it is not up; the socket follows
    Process {
        id: ensureProc
        command: ["python3", "-I", root.script, "--lib", root.libraryDir, "ctl", "state"]
        onExited: if (root.wanted) sock.connected = true
    }

    Timer {
        id: retry
        interval: 2000
        onTriggered: if (root.wanted && !root.linked) {
            sock.connected = false;
            root.connectDaemon();
        }
    }

    function applyState(s: var): void {
        root.mix = s.sounds ?? {};
        root.active = s.active ?? [];
        root.playing = s.playing === true;
        root.paused = s.paused === true;
        root.master = s.master ?? 0.8;
        root.timerEnd = s.timerEnd ?? 0;
        root.timerTotal = s.timerTotal ?? 0;
        root.timerFade = s.timerFade ?? 30;
        root.preset = s.preset ?? "";
        root.userPresets = s.userPresets ?? [];
        if (s.now)
            root.clockSkew = s.now - Date.now() / 1000;
        root.tick++;
    }

    // ── what the app does ──
    function toggle(id: string): void { root.send({ cmd: "toggle", id: id }); }
    function setVolume(id: string, vol: real): void { root.send({ cmd: "set", id: id, vol: vol }); }
    function setSpacing(id: string, spacing: real): void { root.send({ cmd: "set", id: id, spacing: spacing }); }
    function setMaster(vol: real): void { root.send({ cmd: "master", vol: vol }); }
    function play(): void { root.send({ cmd: "play" }); }
    function pause(): void { root.send({ cmd: "pause" }); }
    function togglePlay(): void { root.send({ cmd: "toggle_play" }); }
    function stopAll(): void { root.send({ cmd: "stop" }); }
    function surprise(): void { root.send({ cmd: "random" }); }
    function setTimer(minutes: real): void { root.send({ cmd: "timer", minutes: minutes }); }
    function setTimerFade(seconds: real): void { root.send({ cmd: "timer_fade", fade: seconds }); }
    function loadPreset(id: string): void { root.send({ cmd: "preset_load", id: id }); }
    function savePreset(name: string): void { root.send({ cmd: "preset_save", name: name }); }
    function deletePreset(id: string): void { root.send({ cmd: "preset_delete", id: id }); }

    // Group → tone: three container families, so the library reads as colourful without
    // leaving the theme (the hues all come from the wallpaper's palette)
    readonly property var groupStyle: ({
        "weather": { tone: 0, shape: "Cookie9Sided", symbol: "thunderstorm" },
        "places": { tone: 2, shape: "Clover4Leaf", symbol: "location_city" },
        "life": { tone: 1, shape: "SoftBurst", symbol: "pets" },
        "travel": { tone: 0, shape: "Cookie12Sided", symbol: "flight" },
        "things": { tone: 2, shape: "Pentagon", symbol: "alarm" },
        "raw_noise": { tone: 1, shape: "Sunny", symbol: "graphic_eq" }
    })
    function styleOf(groupId: string): var {
        return root.groupStyle[groupId] ?? { tone: 0, shape: "Cookie9Sided", symbol: "music_note" };
    }

    function countLabel(n: int): string {
        return n === 1 ? Translation.tr("1 sound") : Translation.tr("%1 sounds").arg(n);
    }

    function formatTime(seconds: real): string {
        const s = Math.max(0, Math.round(seconds));
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const ss = s % 60;
        const two = n => (n < 10 ? "0" : "") + n;
        return h > 0 ? `${h}:${two(m)}:${two(ss)}` : `${m}:${two(ss)}`;
    }
}
