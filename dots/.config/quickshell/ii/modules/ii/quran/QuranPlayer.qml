pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.services
import qs.modules.common
import "QuranCore.js" as Core

/**
 * Streams one MP3 per surah from the MP3Quran v4 API and follows it with the ayah and word
 * timings: it seeks to the ayah's start, lets the file play, and moves the highlight by
 * binary-searching the timing arrays. It never cuts audio at ayah boundaries, and it carries on
 * into the next surah when the file ends. Playback is an mpv process over its JSON IPC socket:
 * Qt's own media backend cannot seek far into an HTTP stream, mpv uses range requests.
 */
Item {
    id: root
    visible: false

    property string recitation: Config.options.quran.recitation
    property real volume: Config.options.quran.volume
    /// Playback speed; mpv keeps the pitch (the highlight runs on media time, so it is unaffected)
    property real speed: Config.options.quran.speed
    /// Returns the local words of an ayah on screen, for aligning the API's words to the text.
    property var localWordsFor: null

    readonly property bool playing: fileLoaded && !paused
    readonly property bool active: currentKey !== "" || loading
    property bool loading: false
    property string error: ""
    /// "surah:ayah" being recited, "" when idle
    property string currentKey: ""
    /// "surah:ayah:wordIndex" in the local text, "" without word timings
    property string activeWordKey: ""
    /// 1-based position of the recited word in the API's own word list (media-card highlight)
    property int apiWordPos: -1
    /// Loop the ayah in `repeatKey` instead of rolling on to the next one
    property bool repeatAyah: false
    property string repeatKey: ""
    /// Ayahs in the surah being played, 0 when unknown
    readonly property int surahAyahCount: root.entry ? root.entry.ayahTimings.length : 0
    property real positionMs: 0
    property real durationMs: 0
    property bool paused: true
    property bool fileLoaded: false

    signal ayahStarted(int surah, int ayah)

    readonly property string apiBase: "https://api-staging.mp3quran.net"
    property var cache: ({})
    property var alignCache: ({})
    property var entry: null
    property var pending: null
    property string loadedUrl: ""
    readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quran-mpv.sock"
    property var mpvSocket: null

    function get(path: string, cb: var): void {
        const x = new XMLHttpRequest();
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE)
                return;
            if (x.status !== 200) {
                cb(null);
                return;
            }
            try {
                cb(JSON.parse(x.responseText).data);
            } catch (e) {
                cb(null);
            }
        };
        x.open("GET", root.apiBase + path);
        x.setRequestHeader("Accept", "application/json");
        x.send();
    }

    /// The surah's file url and its ayah and word timings, cached per recitation.
    function loadSurah(surah: int, cb: var): void {
        const code = root.recitation;
        const ck = code + "|" + surah;
        if (root.cache[ck]) {
            cb(root.cache[ck]);
            return;
        }
        const base = "/v4/recitations/" + code + "/surahs/" + surah;
        root.get(base, item => {
            if (!item || !item.files) {
                cb(null);
                return;
            }
            const f = item.files;
            const url = (f.mp3_64 && f.mp3_64.url) || (f.original && f.original.url) || (f.opus_48 && f.opus_48.url) || "";
            const e = { url: url, surah: surah, ayahTimings: [], words: [], wordText: {} };
            const timings = item.timings || [];
            let left = 1 + (timings.indexOf("word") >= 0 ? 1 : 0);
            const done = () => {
                left -= 1;
                if (left > 0)
                    return;
                if (e.url === "" || e.ayahTimings.length === 0) {
                    cb(null);
                    return;
                }
                root.cache[ck] = e;
                cb(e);
            };
            root.get(base + "/ayah-timings", t => {
                e.ayahTimings = t && t.ayahs ? t.ayahs : [];
                done();
            });
            if (timings.indexOf("word") >= 0) {
                root.get(base + "/word-timings?include=text", w => {
                    e.words = w && w.words ? w.words : [];
                    if (w && w.text && w.text.ayahs)
                        for (const a of w.text.ayahs)
                            e.wordText[a[0]] = a[1].map(x => x[1]);
                    done();
                });
            }
        });
    }

    function startOf(e: var, ayah: int): real {
        for (const t of e.ayahTimings)
            if (t[0] === ayah)
                return t[1];
        return 0;
    }

    function playFrom(surah: int, ayah: int): void {
        root.pending = { surah: surah, ayah: ayah };
        root.loading = true;
        root.error = "";
        root.loadSurah(surah, e => {
            if (!root.pending || root.pending.surah !== surah || root.pending.ayah !== ayah)
                return;
            root.loading = false;
            if (!e) {
                root.error = Translation.tr("Could not load this recitation");
                return;
            }
            root.pending = null;
            root.entry = e;
            root.activeWordKey = "";
            const seek = root.startOf(e, ayah) / 1000;
            root.setKey(surah, ayah);
            if (root.repeatAyah)
                root.repeatKey = surah + ":" + ayah;
            root.start(e.url, seek);
        });
    }

    function setKey(surah: int, ayah: int): void {
        const key = surah + ":" + ayah;
        if (key === root.currentKey)
            return;
        root.currentKey = key;
        root.ayahStarted(surah, ayah);
    }

    function toggle(): void {
        if (root.fileLoaded)
            root.command(["set_property", "pause", !root.paused]);
    }

    function stop(): void {
        root.pending = null;
        root.loading = false;
        // Ending mpv also removes its media-player entry from the desktop; the next start respawns it
        root.queued = [];
        root.command(["quit"]);
        root.mpvQuitting = mpvProc.running;
        mpvProc.running = false;
        root.fileLoaded = false;
        root.loadedUrl = "";
        root.currentKey = "";
        root.activeWordKey = "";
    }

    function step(delta: int): void {
        const parts = root.currentKey.split(":");
        if (parts.length !== 2)
            return;
        const next = Core.stepAyah(+parts[0], +parts[1], delta);
        if (next)
            root.playFrom(next.surah, next.ayah);
    }

    function setRepeat(on: bool): void {
        root.repeatAyah = on;
        root.repeatKey = on ? root.currentKey : "";
    }

    function seekFraction(f: real): void {
        if (root.durationMs > 0)
            root.command(["seek", Math.max(0, Math.min(1, f)) * root.durationMs / 1000, "absolute"]);
    }

    // Changing the reciter restarts the current ayah with the new voice
    onRecitationChanged: {
        root.pushMpris();
        root.alignCache = ({});
        if (root.currentKey !== "") {
            const p = root.currentKey.split(":");
            root.playFrom(+p[0], +p[1]);
        }
    }

    function alignedIndex(key: string, ayah: int, apiPos: int): int {
        let map = root.alignCache[key];
        if (map === undefined) {
            const local = root.localWordsFor ? root.localWordsFor(key) : null;
            const api = root.entry ? root.entry.wordText[ayah] : null;
            map = local && api ? Core.alignWordIndexes(local, api) : null;
            if (local)  // not cached while the reader is hidden, there is nothing to align to
                root.alignCache[key] = map;
        }
        if (!map)
            return -1;
        const i = map[apiPos - 1];
        return i === undefined ? -1 : i;
    }

    function tick(): void {
        const e = root.entry;
        if (!e || root.pending)
            return;
        const pos = root.positionMs;
        const t = Core.findAyahAt(e.ayahTimings, pos);
        if (t && root.repeatAyah && root.repeatKey !== "" && e.surah + ":" + t[0] !== root.repeatKey) {
            const rp = root.repeatKey.split(":");
            if (+rp[0] === e.surah) {
                root.command(["seek", root.startOf(e, +rp[1]) / 1000, "absolute"]);
                return;
            }
        }
        if (t)
            root.setKey(e.surah, t[0]);
        const w = e.words.length > 0 ? Core.findWordAt(e.words, pos) : null;
        root.apiWordPos = w ? w[1] : -1;
        if (w) {
            const key = e.surah + ":" + w[0];
            const idx = root.alignedIndex(key, w[0], w[1]);
            root.activeWordKey = idx >= 0 ? key + ":" + idx : "";
        } else {
            root.activeWordKey = "";
        }
    }

    // ── mpv ──
    // Commands queued until the socket is up; a Socket that fails to connect does not retry,
    // so the player waits for the socket file and only then creates a fresh Socket.
    property var queued: []

    function command(args: var): void {
        const socket = root.mpvSocket;
        if (!socket || !socket.connected) {
            if (args[0] !== "stop" && args[0] !== "quit")
                root.queued.push(args);
            return;
        }
        socket.write(JSON.stringify({ command: args }) + "\n");
        socket.flush();
    }

    /// Play `url` from `seconds`; the same file only seeks.
    function start(url: string, seconds: real): void {
        root.ensureMpv();
        root.paused = false;
        if (url === root.loadedUrl && root.fileLoaded) {
            root.command(["seek", seconds, "absolute"]);
            root.command(["set_property", "pause", false]);
            return;
        }
        root.loadedUrl = url;
        root.fileLoaded = false;
        root.command(["loadfile", url, "replace", -1, "start=" + seconds.toFixed(3)]);
        root.command(["set_property", "pause", false]);
    }

    /// Set while a stopped mpv is still exiting; a start in that window respawns it once it is gone
    property bool mpvQuitting: false
    property bool mpvRespawn: false

    function ensureMpv(): void {
        if (root.mpvQuitting)
            root.mpvRespawn = true;
        else if (!mpvProc.running)
            mpvProc.running = true;
    }

    function onMpvMessage(line: string): void {
        let m;
        try {
            m = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (m.event === "property-change") {
            if (m.name === "time-pos" && m.data !== null && m.data !== undefined) {
                root.positionMs = m.data * 1000;
                root.tick();
            } else if (m.name === "pause") {
                root.paused = m.data === true;
            } else if (m.name === "duration" && m.data) {
                root.durationMs = m.data * 1000;
            }
        } else if (m.event === "file-loaded") {
            root.fileLoaded = true;
        } else if (m.event === "end-file") {
            root.fileLoaded = false;
            if (m.reason === "eof" && root.entry) {
                if (root.entry.surah < 114)
                    root.playFrom(root.entry.surah + 1, 1);
                else
                    root.stop();
            } else if (m.reason === "error") {
                root.error = Translation.tr("Could not play this recitation");
                root.loading = false;
            }
        }
    }

    Component {
        id: socketComponent
        Socket {
            parser: SplitParser {
                onRead: data => root.onMpvMessage(String(data))
            }
            onError: {
                // Refused: the file was not mpv's yet. Start over with a fresh Socket.
                if (root.mpvSocket === this) {
                    const dead = this;
                    root.mpvSocket = null;
                    Qt.callLater(() => dead.destroy());
                }
            }
            onConnectedChanged: {
                if (!connected)
                    return;
                write(JSON.stringify({ command: ["observe_property", 1, "time-pos"] }) + "\n");
                write(JSON.stringify({ command: ["observe_property", 2, "pause"] }) + "\n");
                write(JSON.stringify({ command: ["observe_property", 3, "duration"] }) + "\n");
                flush();
                // Straight to this socket: the player has not stored it yet, so command() would
                // queue them again
                const q = root.queued;
                root.queued = [];
                for (const c of q)
                    write(JSON.stringify({ command: c }) + "\n");
                flush();
            }
        }
    }

    Timer {
        id: socketRetry
        interval: 150
        repeat: true
        running: mpvProc.running && root.mpvSocket === null
        onTriggered: if (!socketProbe.running) socketProbe.running = true
    }

    Process {
        id: socketProbe
        command: ["test", "-S", root.socketPath]
        onExited: exitCode => {
            if (exitCode === 0 && root.mpvSocket === null && mpvProc.running)
                root.mpvSocket = socketComponent.createObject(root, { path: root.socketPath, connected: true });
        }
    }

    /// A recitation left paused with the reader closed does not linger forever
    Timer {
        interval: 30 * 60 * 1000
        running: root.active && root.paused && !GlobalStates.quranOpen
        onTriggered: root.stop()
    }

    // ── MPRIS: the desktop's media widgets see a player called "Quran", with cover art ──
    readonly property string coverUrl: "file://" + Quickshell.shellPath("assets/quran/cover.png")

    function pushMpris(): void {
        if (!mprisProc.running)
            return;
        const p = root.currentKey.split(":");
        const rec = Core.RECITATIONS.find(r => r.code === root.recitation);
        const title = p.length === 2 ? "سورة " + Core.SURAH_NAMES_AR[+p[0]] + " · الآية " + Core.toArabicDigits(+p[1]) : "القرآن الكريم";
        mprisProc.write(JSON.stringify({
            title: title,
            artist: rec ? rec.nameAr : root.recitation,
            album: "القرآن الكريم",
            artUrl: root.coverUrl,
            lengthUs: Math.round(root.durationMs * 1000),
            positionUs: Math.round(root.positionMs * 1000),
            playing: root.playing,
            rate: root.speed,
            volume: root.volume,
            active: root.active
        }) + "\n");
    }

    onCurrentKeyChanged: root.pushMpris()
    onPlayingChanged: root.pushMpris()
    onDurationMsChanged: root.pushMpris()

    Timer {
        interval: 1000
        repeat: true
        running: mprisProc.running
        onTriggered: root.pushMpris()
    }

    Process {
        id: mprisProc
        running: root.active
        stdinEnabled: true
        command: ["python3", Quickshell.shellPath("scripts/quran/mpris.py")]
        onRunningChanged: if (running) Qt.callLater(root.pushMpris)
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                switch (m.cmd) {
                case "PlayPause": root.toggle(); break;
                case "Play": if (!root.playing) root.toggle(); break;
                case "Pause": if (root.playing) root.toggle(); break;
                case "Next": root.step(1); break;
                case "Previous": root.step(-1); break;
                case "Stop": root.stop(); break;
                case "Seek": root.command(["seek", m.value / 1e6, "relative"]); break;
                case "SetPosition": root.command(["seek", m.value / 1e6, "absolute"]); break;
                case "SetVolume": Config.options.quran.volume = Math.max(0, Math.min(1, m.value)); break;
                case "SetRate": Config.options.quran.speed = Math.max(0.5, Math.min(2, m.value)); break;
                }
            }
        }
    }

    Process {
        id: mpvProc
        // A socket left by an earlier mpv would be probed before the new one replaces it
        command: ["sh", "-c", "rm -f \"$1\"; shift; exec \"$@\"", "sh", root.socketPath,
                  "mpv", "--no-video", "--idle=yes", "--no-terminal", "--really-quiet", "--no-config",
                  "--force-window=no", "--cache=yes", "--demuxer-readahead-secs=20",
                  "--volume=" + Math.round(root.volume * 100), "--speed=" + root.speed, "--input-ipc-server=" + root.socketPath]
        onRunningChanged: {
            if (!running) {
                if (root.mpvSocket)
                    root.mpvSocket.destroy();
                root.mpvSocket = null;
                root.fileLoaded = false;
                root.paused = true;
                root.mpvQuitting = false;
                if (root.mpvRespawn) {
                    root.mpvRespawn = false;
                    mpvProc.running = true;
                }
            }
        }
    }

    onVolumeChanged: root.command(["set_property", "volume", Math.round(root.volume * 100)])
    onSpeedChanged: {
        root.command(["set_property", "speed", root.speed]);
        root.pushMpris();
    }

    Component.onDestruction: {
        if (root.mpvSocket && root.mpvSocket.connected) {
            root.mpvSocket.write(JSON.stringify({ command: ["quit"] }) + "\n");
            root.mpvSocket.flush();
        }
        mpvProc.running = false;
    }
}
