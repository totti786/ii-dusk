pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.modules.common

/**
 * Syncplay behind the Syncplay app.
 *
 * The real work happens in `scripts/syncplay/syncplay_bridge.py`: a detached session that
 * runs Syncplay's own client (protocol, mpv control, drift correction) headless and talks
 * JSON lines on $XDG_RUNTIME_DIR/ii-syncplay.sock. It is detached on purpose, so a shell
 * reload never ends the call or kills the player. This service only connects to that
 * socket, mirrors its state, and sends commands.
 *
 * The server password goes to `start` on stdin (never argv) and is not kept here.
 */
Singleton {
    id: root

    readonly property string script: `${Directories.scriptPath}/syncplay/syncplay_bridge.py`
    readonly property string sockPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/ii-syncplay.sock`
    // The app, or anything that watches (the island): attached while either is there.
    property int watchers: 0
    readonly property bool wanted: GlobalStates.syncplayAppOpen || root.watchers > 0

    // Passive: never starts a session, only attaches to one that exists.
    function watch(): void { root.watchers++; }
    function unwatch(): void { root.watchers = Math.max(0, root.watchers - 1); }

    // ── Link ─────────────────────────────────────────────────────────────────
    property bool linked: false          // the shell is attached to a running session
    property bool starting: false
    property bool checked: false         // `status` has answered once
    property string errorText: ""        // start failures and the last session error

    // ── Room state (mirrors the bridge's snapshot) ───────────────────────────
    property bool connected: false       // logged in to the Syncplay server
    property string host: ""
    property int port: 0
    property string name: ""
    property string room: ""
    property var users: []
    property var playlistItems: []
    property int playlistIndex: -1
    property var playlistMissing: []     // indexes this machine cannot find in its media folders
    property string owner: ""            // "mediator": Mediator's queue is the room's list
    readonly property bool mediatorOwned: root.owner === "mediator"
    property bool sharedPlaylist: false
    property bool canUndo: false
    property var file: null              // { name, duration, size } of what this client plays
    property bool ready: false
    property bool controller: false
    property bool controlledRoom: false
    property string motd: ""
    property bool paused: true
    property bool globalPaused: true
    property real position: 0
    property real basePosition: 0
    property real baseStamp: 0
    property var messages: []            // recent chat / system / error lines, oldest first
    property int messageSerial: 0

    // What the connect screen starts from: the user's own syncplay.ini
    property var defaults: ({})
    property bool defaultsLoaded: false

    readonly property var otherUsers: root.users.filter(u => !u.me)
    readonly property var roomUsers: root.users.filter(u => u.inRoom)
    readonly property real duration: root.file?.duration ?? 0
    readonly property string currentName: root.file?.name ?? ""

    // ── Remembered choices (not secrets) ─────────────────────────────────────
    readonly property var cfg: Config.options?.syncplay ?? null

    // ── Mediator ─────────────────────────────────────────────────────────────
    // Mediator plays "Watch Together" through a `syncplay` binary it spawns and owns. This
    // makes that binary the bridge's `compat` entry, so Mediator keeps its mpv socket and
    // process while this app shows the room. Host, name and room are the remembered ones
    // (else syncplay.ini). A server password is not passed: it would show up in argv.
    function shq(v: string): string { return "'" + String(v).replace(/'/g, "'\\''") + "'"; }
    readonly property var mediatorCommandPrefix: {
        const c = root.cfg;
        let words = ["python3", "-I", root.script, "compat"];
        const d = root.defaults ?? {};
        const host = String(c?.host || d.host || "");
        const name = String(c?.name || d.name || "");
        if (host !== "" && name !== "") {
            words = words.concat([`--host=${host}`, `--port=${c?.port || d.port || 8999}`,
                `--name=${name}`, `--room=${c?.room || d.room || ""}`]);
        }
        // The control socket lets Mediator add each next episode's link to the room's playlist
        return ["env", "MEDIATOR_SYNCPLAY=" + words.map(w => root.shq(w)).join(" "),
            "MEDIATOR_SYNCPLAY_CONTROL=" + root.sockPath];
    }
    // Whether there is enough to join without asking
    readonly property bool configured: String(root.cfg?.host || root.defaults?.host || "") !== ""
        && String(root.cfg?.name || root.defaults?.name || "") !== ""

    // ── Commands ─────────────────────────────────────────────────────────────
    property var outbox: []

    function send(message: var): void {
        const line = JSON.stringify(message) + "\n";
        if (sock.connected) {
            sock.write(line);
            sock.flush();
        } else if (root.outbox.length < 20) {
            root.outbox = root.outbox.concat([message]);
        }
    }

    function setReady(value: bool): void { root.send({ cmd: "ready", value: value }); }
    function setPaused(value: bool): void {
        root.paused = value;
        root.basePosition = root.position;
        root.baseStamp = Date.now();
        root.send({ cmd: "pause", value: value });
    }
    function togglePause(): void { root.setPaused(!root.paused); }
    function seek(seconds: real): void {
        root.position = seconds;
        root.basePosition = seconds;
        root.baseStamp = Date.now();
        root.send({ cmd: "seek", position: seconds });
    }
    function chat(text: string): void {
        const t = text.trim();
        if (t.length > 0)
            root.send({ cmd: "chat", text: t });
    }
    function changeRoom(name: string): void {
        const n = name.trim();
        if (n.length > 0)
            root.send({ cmd: "room", name: n });
    }
    function openFile(path: string): void { root.send({ cmd: "open", path: path }); }
    function playlistAdd(item: string): void { root.send({ cmd: "playlist-add", item: item }); }
    function playlistRemove(index: int): void { root.send({ cmd: "playlist-remove", index: index }); }
    function playlistPlay(index: int): void { root.send({ cmd: "playlist-play", index: index }); }
    function playlistSet(items: var): void { root.send({ cmd: "playlist-set", items: items }); }
    function undoPlaylist(): void { root.send({ cmd: "undo" }); }
    function shufflePlaylist(): void { root.send({ cmd: "shuffle" }); }
    function identifyAsController(password: string): void { root.send({ cmd: "identify", password: password }); }

    // Begins a session and attaches to it. `password` is sent on stdin only.
    function start(host: string, port: int, name: string, room: string, password: string): void {
        if (root.starting || startProc.running)
            return;
        root.errorText = "";
        root.starting = true;
        root.messages = [];
        startProc.pendingStdin = String(password ?? "") + "\n";
        startProc.rememberHost = host;
        startProc.rememberPort = port;
        startProc.rememberName = name;
        startProc.rememberRoom = room;
        startProc.command = ["python3", "-I", root.script, "start",
            `--host=${host}`, `--port=${port}`, `--name=${name}`, `--room=${room}`];
        startProc.running = true;
    }

    function leave(): void {
        root.send({ cmd: "quit" });
        root.resetState();
    }

    function resetState(): void {
        root.connected = false;
        root.users = [];
        root.playlistItems = [];
        root.playlistIndex = -1;
        root.playlistMissing = [];
        root.owner = "";
        root.file = null;
        root.ready = false;
        root.controller = false;
        root.paused = true;
        root.position = 0;
        root.motd = "";
    }

    function attach(): void {
        if (!sock.connected)
            sock.connected = true;
    }

    // ── State from the session ───────────────────────────────────────────────
    function applyState(s: var): void {
        root.connected = s.connected === true;
        root.host = s.host ?? root.host;
        root.port = s.port ?? root.port;
        root.name = s.name ?? root.name;
        root.room = s.room ?? "";
        root.users = s.users ?? [];
        root.playlistItems = s.playlist?.items ?? [];
        root.playlistIndex = s.playlist?.index ?? -1;
        root.playlistMissing = s.playlist?.missing ?? [];
        root.owner = s.owner ?? "";
        root.sharedPlaylist = s.sharedPlaylist === true;
        root.canUndo = s.canUndo === true;
        root.file = s.file ?? null;
        root.ready = s.ready === true;
        root.controller = s.controller === true;
        root.controlledRoom = s.controlledRoom === true;
        root.motd = s.motd ?? "";
        if (s.error && s.error.length > 0)
            root.errorText = s.error;
        else if (root.connected)
            root.errorText = "";
        root.applyTick(s);
    }

    function applyTick(s: var): void {
        if (s.position === undefined)
            return;
        root.paused = s.paused === true;
        root.globalPaused = s.globalPaused === true;
        root.basePosition = s.position;
        root.baseStamp = Date.now();
        root.position = s.position;
    }

    function pushMessage(m: var): void {
        const list = root.messages.concat([m]);
        root.messages = list.length > 300 ? list.slice(list.length - 300) : list;
        root.messageSerial++;
        if (m.kind === "error" && m.text)
            root.errorText = m.text;
    }

    Socket {
        id: sock
        path: root.sockPath
        connected: false
        parser: SplitParser {
            onRead: line => {
                let msg = null;
                try {
                    msg = JSON.parse(line);
                } catch (e) {
                    return;
                }
                switch (msg.type) {
                case "state": root.applyState(msg); break;
                case "tick": root.applyTick(msg); break;
                case "msg": root.pushMessage(msg); break;
                case "ended":
                    root.resetState();
                    break;
                }
            }
        }
        onConnectedChanged: {
            root.linked = sock.connected;
            if (sock.connected) {
                for (const m of root.outbox)
                    sock.write(JSON.stringify(m) + "\n");
                root.outbox = [];
                sock.flush();
            } else {
                // The session ended (Leave, or it died): nothing in the room is current any more.
                root.resetState();
            }
        }
        onError: root.linked = false
    }

    // ── One-shot calls ───────────────────────────────────────────────────────
    Process {
        id: startProc
        property string pendingStdin: ""
        property string rememberHost: ""
        property int rememberPort: 0
        property string rememberName: ""
        property string rememberRoom: ""
        stdinEnabled: true
        stdout: StdioCollector { id: startOut }
        onStarted: {
            startProc.write(startProc.pendingStdin);
            startProc.pendingStdin = "";
            startProc.stdinEnabled = false;
        }
        onExited: {
            root.starting = false;
            startProc.stdinEnabled = true;
            let out = {};
            try {
                out = JSON.parse(startOut.text.trim().split("\n").pop());
            } catch (e) {
                out = { ok: false, error: Translation.tr("Syncplay did not start") };
            }
            if (out.ok || out.code === "running") {
                if (root.cfg) {
                    root.cfg.host = startProc.rememberHost;
                    root.cfg.port = startProc.rememberPort;
                    root.cfg.name = startProc.rememberName;
                    root.cfg.room = startProc.rememberRoom;
                }
                root.attach();
            } else {
                root.errorText = String(out.error ?? Translation.tr("Syncplay did not start"));
            }
        }
    }

    Process {
        id: statusProc
        command: ["python3", "-I", root.script, "status"]
        stdout: StdioCollector { id: statusOut }
        onExited: {
            root.checked = true;
            try {
                if (JSON.parse(statusOut.text).running === true)
                    root.attach();
            } catch (e) {}
        }
    }

    Process {
        id: defaultsProc
        command: ["python3", "-I", root.script, "defaults"]
        stdout: StdioCollector { id: defaultsOut }
        onExited: {
            try {
                root.defaults = JSON.parse(defaultsOut.text);
            } catch (e) {
                root.defaults = {};
            }
            root.defaultsLoaded = true;
        }
    }

    // A session left running keeps its state; the app only attaches to it. Each open checks
    // once, and a closed app detaches (the session itself carries on).
    onWantedChanged: {
        if (root.wanted) {
            root.checked = false;
            if (!statusProc.running)
                statusProc.running = true;
            if (GlobalStates.syncplayAppOpen && !root.defaultsLoaded && !defaultsProc.running)
                defaultsProc.running = true;
            detachTimer.stop();
        } else {
            // Bubbles and cards come and go as media changes; letting go the moment the last
            // watcher left made the room flicker away and take seconds to come back.
            detachTimer.restart();
        }
    }

    Timer {
        id: detachTimer
        interval: 30000
        onTriggered: {
            if (!root.wanted) {
                sock.connected = false;
                root.outbox = [];
            }
        }
    }

    Connections {
        target: GlobalStates
        function onSyncplayAppOpenChanged(): void {
            if (GlobalStates.syncplayAppOpen && !root.defaultsLoaded && !defaultsProc.running)
                defaultsProc.running = true;
        }
    }

    // A session can also start without this window (Mediator's Watch Together): while the
    // app is open and unlinked, look again every couple of seconds.
    Timer {
        interval: 4000
        repeat: true
        running: root.wanted && !root.linked && !root.starting
        onTriggered: if (!probeProc.running) probeProc.running = true
    }

    Process {
        id: probeProc
        command: ["test", "-S", root.sockPath]
        onExited: code => {
            if (code === 0 && !sock.connected)
                root.attach();
        }
    }

    // Position between the session's once-a-second ticks, so the bar moves smoothly
    Timer {
        interval: 250
        repeat: true
        running: root.wanted && root.connected && !root.paused && root.duration > 0
        onTriggered: root.position = Math.min(root.duration,
            root.basePosition + (Date.now() - root.baseStamp) / 1000)
    }
}
