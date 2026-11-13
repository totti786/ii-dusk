pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.modules.common

/**
 * Bridge to scripts/anki/anki_backend.py, an adapter over upstream's anki_daemon.py
 * (Anki's own scheduler, renderer and AnkiWeb sync).
 *
 * The process is started only while the Anki app window is open. It owns the collection
 * for that lifetime, so Anki desktop must be closed while the app is visible. The
 * collection is the user's default Anki profile unless Settings names another.
 */
Singleton {
    id: root

    readonly property string script: `${Directories.scriptPath}/anki/anki_backend.py`

    property string phase: "closed" // closed | starting | loading | question | answer | done | error
    property bool busy: false
    property bool closing: false

    property var decks: null
    property real currentDeckId: 0
    property var counts: ({ "new": 0, "learn": 0, "review": 0 })
    property var card: null
    property var answer: null
    property var profiles: []
    property string profile: ""
    property string version: ""
    property string collectionPath: ""
    property string mediaPath: ""
    /// Test/development override; the app leaves this empty.
    property string collectionOverride: ""

    // Session facts from the backend.
    property int totalCards: 0
    property bool loggedIn: false
    property string username: ""
    property bool mathjax: false
    property var studiedToday: ({ "cards": 0, "seconds": 0 })
    property var noteTypes: []

    // AnkiWeb sync. `syncConflict` means both sides changed: the user must pick a direction.
    property bool syncing: false
    property string syncStage: "" // "", collection, upload, download, media
    property string syncMessage: ""
    property string syncError: ""
    property bool syncConflict: false
    property bool lastSyncOk: false
    /// A stop or retry asked for during a sync waits for it: the backend answers one request
    /// at a time, and killing it inside a full download would leave the collection half-written.
    property bool stopAfterSync: false

    // The engine: a private venv with a pinned `anki` (scripts/anki/install_engine.sh).
    // Until it is installed the backend answers `anki_missing` and the app offers to install it.
    readonly property string engineInstaller: `${Directories.scriptPath}/anki/install_engine.sh`
    property bool installingEngine: false
    property string installStep: ""
    property string installError: ""

    property string errorCode: ""
    property string errorMessage: ""
    property string errorDetail: ""
    property string lastStderr: ""

    signal opened()

    property int _nextId: 0
    property var _pending: ({})
    property int _pendingCount: 0
    // Bumped on every start and exit, so a late callback of an earlier helper can be told apart.
    property int _generation: 0

    function clearError(): void {
        root.errorCode = "";
        root.errorMessage = "";
        root.errorDetail = "";
    }

    function fail(code, message, detail = "") {
        root.errorCode = code;
        root.errorMessage = message;
        root.errorDetail = detail;
        root.phase = "error";
        root.busy = false;
    }

    function _writePending(id: string, callback, timeoutMs: int, fatal: bool): void {
        root._pending[id] = {
            "callback": callback,
            "deadline": Date.now() + timeoutMs,
            "fatal": fatal
        };
        root._pendingCount = Object.keys(root._pending).length;
    }

    function _takePending(id: string): var {
        const entry = root._pending[id];
        if (entry === undefined)
            return null;
        delete root._pending[id];
        root._pendingCount = Object.keys(root._pending).length;
        return entry;
    }

    /// Nothing the old helper was asked can be answered any more: answer it with an error so
    /// no timeout fires into the next session.
    function _dropPending(): void {
        const stale = root._pending;
        root._pending = ({});
        root._pendingCount = 0;
        for (const id of Object.keys(stale)) {
            if (stale[id].callback)
                stale[id].callback(null, { "code": "not_running", "message": "The Anki helper stopped." });
        }
    }

    function call(cmd, args, callback, timeoutMs = 10000, fatal = true) {
        if (!process.running) {
            if (callback)
                callback(null, { "code": "not_running", "message": "The Anki helper is not running." });
            return;
        }
        const id = String(++root._nextId);
        root._writePending(id, callback, timeoutMs, fatal);
        process.write(JSON.stringify({ "id": id, "cmd": cmd, "args": args ?? {} }) + "\n");
    }

    function _handleLine(line: string): void {
        let response;
        try {
            response = JSON.parse(line);
        } catch (e) {
            console.warn("[AnkiService] malformed helper output:", line);
            return;
        }
        if (response.event !== undefined) {
            if (response.event === "sync")
                root.syncStage = response.stage ?? "";
            return;
        }
        const entry = root._takePending(String(response.id));
        if (entry === null)
            return;
        if (!response.ok) {
            const error = response.error ?? { "code": "internal", "message": "Unknown helper error." };
            if (entry.fatal && !["nothing_to_undo", "no_card", "answer_not_ready", "bad_request", "stale_card"].includes(error.code))
                root.fail(error.code ?? "internal", error.message ?? "Unknown helper error.", error.detail ?? "");
            if (entry.callback)
                entry.callback(null, error);
            return;
        }
        if (entry.callback)
            entry.callback(response.data ?? {}, null);
    }

    function _checkTimeouts(): void {
        const now = Date.now();
        const expired = [];
        for (const id in root._pending) {
            if (now >= root._pending[id].deadline)
                expired.push(id);
        }
        for (const id of expired) {
            const entry = root._takePending(id);
            if (entry && entry.callback)
                entry.callback(null, { "code": "timeout", "message": "The Anki helper did not answer in time." });
            if (entry && entry.fatal && root.phase !== "closed")
                root.fail("timeout", "The Anki helper did not answer in time.");
        }
    }

    function start(): void {
        if (process.running) {
            // A stop is still in flight: start again once the helper has gone.
            if (root.closing)
                restartTimer.restart();
            else if (root.phase === "error")
                root.retry();
            return;
        }
        // A stop that was still counting down must not kill the helper started now.
        root.stopAfterSync = false;
        forceStop.stop();
        root.closing = false;
        root._generation++;
        root._dropPending();
        root.clearError();
        root.lastStderr = "";
        root.phase = "starting";
        root.busy = true;
        process.command = ["python3", "-I", root.script];
        process.running = true;
    }

    function stop(): void {
        if (process.running && root.syncing) {
            root.stopAfterSync = true;
            return;
        }
        if (!process.running) {
            root.phase = "closed";
            root.busy = false;
            return;
        }
        root.closing = true;
        const generation = root._generation;
        root.call("close", {}, () => {
            // A start() since then owns the helper now; leave it alone.
            if (generation !== root._generation || !root.closing)
                return;
            process.running = false;
            root.phase = "closed";
            root.busy = false;
        }, 1500, false);
        forceStop.restart();
    }

    function retry(): void {
        if (root.syncing)
            return;
        root.closing = true;
        process.running = false;
        root.phase = "closed";
        root.clearError();
        restartTimer.restart();
    }

    function _openCollection(): void {
        const args = {};
        if (root.collectionOverride.length > 0)
            args.collectionPath = root.collectionOverride;
        else if (Config.options.anki?.collectionPath)
            args.collectionPath = Config.options.anki.collectionPath;
        if (Config.options.anki?.profile)
            args.profile = Config.options.anki.profile;
        args.theme = root.cardTheme();
        root.call("open", args, (data, error) => {
            if (error) {
                root.fail(error.code ?? "internal", error.message ?? "Could not open the collection.", error.detail ?? "");
                return;
            }
            root.version = data.version ?? "";
            root.profile = data.profile ?? "";
            root.collectionPath = data.collectionPath ?? "";
            root.mediaPath = data.mediaPath ?? "";
            root.decks = data.decks ?? null;
            root.currentDeckId = data.currentDeckId ?? 0;
            root.counts = data.counts ?? { "new": 0, "learn": 0, "review": 0 };
            root._applySession(data);
            root.refreshProfiles();
            root.opened();
        }, 20000);
    }

    /// What the backend needs to reshape card HTML for this window: text colour, size, width.
    function cardTheme() {
        return {
            "color": String(Appearance.m3colors.m3onSurface),
            "fontPx": 28,
            "maxWidth": 700,
            "dark": Appearance.m3colors.darkmode
        };
    }

    function _applySession(data): void {
        root.totalCards = data.cards ?? root.totalCards;
        root.loggedIn = data.loggedIn ?? root.loggedIn;
        root.username = data.username ?? root.username;
        root.mathjax = data.mathjax ?? root.mathjax;
        root.studiedToday = data.studiedToday ?? root.studiedToday;
    }

    function requestCard(): void {
        if (root.syncing)
            return;
        if (!process.running || root.closing)
            return;
        root.busy = true;
        root.call("card", {}, (data, error) => {
            root.busy = false;
            if (error)
                return;
            root._applyCard(data);
        }, 10000);
    }

    function _applyCard(data): void {
        root.counts = data.counts ?? root.counts;
        if (data.done) {
            root.card = null;
            root.answer = null;
            root.phase = "done";
            return;
        }
        root.card = data.card ?? null;
        root.answer = null;
        if (root.card) {
            root.currentDeckId = root.card.deckId ?? root.currentDeckId;
            root.phase = "question";
        } else {
            root.phase = "done";
        }
    }

    function selectDeck(deckId) {
        if (root.syncing)
            return;
        root.busy = true;
        root.call("selectDeck", { "deckId": deckId }, (data, error) => {
            root.busy = false;
            if (error)
                return;
            if (data.currentDeckId !== undefined)
                root.currentDeckId = data.currentDeckId;
            root._applyCard(data);
            root.refreshDecks();
        }, 10000);
    }

    function reveal(typed = "") {
        if (root.syncing)
            return;
        if (root.phase !== "question" || root.busy)
            return;
        root.busy = true;
        root.call("reveal", { "typed": typed }, (data, error) => {
            root.busy = false;
            if (error)
                return;
            root.answer = data;
            root.counts = data.counts ?? root.counts;
            root.phase = "answer";
        }, 10000);
    }

    function submitAnswer(rating) {
        if (root.syncing)
            return;
        if (root.phase !== "answer" || root.busy)
            return;
        root.busy = true;
        root.call("answer", { "rating": rating }, (data, error) => {
            root.busy = false;
            if (error)
                return;
            root._applyCard(data);
            root.refreshDecks();
        }, 10000);
    }

    function undo(): void {
        if (root.syncing)
            return;
        if (root.busy)
            return;
        root.busy = true;
        root.call("undo", {}, (data, error) => {
            root.busy = false;
            if (error)
                return;
            root._applyCard(data);
            root.refreshDecks();
        }, 10000);
    }

    /// mark | flag (with a flag number) | suspend | suspendNote | bury | buryNote
    function cardAction(action: string, flag = 0): void {
        if (root.syncing)
            return;
        if ((root.phase !== "question" && root.phase !== "answer") || root.busy)
            return;
        root.busy = true;
        root.call("cardAction", { "action": action, "flag": flag }, (data, error) => {
            root.busy = false;
            if (error)
                return;
            if (action === "mark" || action === "flag") {
                root.card = Object.assign({}, root.card, { "marked": data.marked, "flag": data.flag });
                return;
            }
            root._applyCard(data);
            root.refreshDecks();
        }, 10000);
    }

    // ------------------------------------------------------------------ the engine

    function installEngine(): void {
        if (root.installingEngine)
            return;
        root.installingEngine = true;
        root.installError = "";
        root.installStep = "Starting";
        installer.running = true;
    }

    // ---------------------------------------------------------------- AnkiWeb sync

    function login(username: string, password: string, callback): void {
        root.syncError = "";
        root.call("login", { "username": username, "password": password }, (data, error) => {
            if (!error) {
                root.loggedIn = true;
                root.username = data.username ?? username;
            } else {
                root.syncError = error.message ?? "Sign-in failed.";
            }
            if (callback)
                callback(error === null);
        }, 30000, false);
    }

    function logout(): void {
        root.call("logout", {}, () => {
            root.loggedIn = false;
            root.username = "";
            root.syncConflict = false;
        }, 5000, false);
    }

    /// Normal sync. A result of `conflict` leaves the choice to the user (`fullSync`).
    function sync(): void {
        if (root.syncing || !root.loggedIn)
            return;
        root.syncing = true;
        root.syncError = "";
        root.syncMessage = "";
        root.syncStage = "collection";
        root.call("sync", {}, (data, error) => root._syncDone(data, error), 900000, false);
    }

    /// Replace one side with the other. `upload` true overwrites AnkiWeb with this collection.
    function fullSync(upload: bool): void {
        if (root.syncing)
            return;
        root.syncing = true;
        root.syncConflict = false;
        root.syncError = "";
        root.call("fullSync", { "upload": upload }, (data, error) => root._syncDone(data, error), 1800000, false);
    }

    function _syncDone(data, error): void {
        root.syncing = false;
        root.syncStage = "";
        if (root.stopAfterSync) {
            root.stopAfterSync = false;
            root.stop();
            return;
        }
        if (error) {
            root.syncError = error.message ?? "Sync failed.";
            root.lastSyncOk = false;
            return;
        }
        if (data.conflict) {
            root.syncConflict = true;
            root.syncMessage = data.message ?? "";
            return;
        }
        root.lastSyncOk = true;
        root.syncMessage = data.message ?? "";
        // The collection may have changed under the queue: start from a fresh card.
        root.refreshDecks();
        if (root.phase === "question" || root.phase === "answer" || root.phase === "done")
            root.requestCard();
    }

    // ------------------------------------------------------------- adding and importing

    function loadNoteTypes(): void {
        root.call("noteTypes", {}, (data, error) => {
            if (!error)
                root.noteTypes = data ?? [];
        }, 5000, false);
    }

    /// callback(ok, message)
    function addNote(deckId, noteTypeId, fields, tags: string, callback): void {
        root.call("addNote", { "deckId": deckId, "noteTypeId": noteTypeId, "fields": fields, "tags": tags }, (data, error) => {
            if (!error)
                root.refreshDecks();
            if (callback)
                callback(error === null, error ? (error.message ?? "") : "");
        }, 10000, false);
    }

    function createDeck(name: string, callback): void {
        root.call("createDeck", { "name": name }, (data, error) => {
            if (!error)
                root.refreshDecks();
            if (callback)
                callback(error === null, error ? (error.message ?? "") : "", data ? data.id : 0);
        }, 10000, false);
    }

    /// callback(ok, message): message is "N new, M updated" on success.
    function importPackage(path: string, callback): void {
        root.call("importApkg", { "path": path }, (data, error) => {
            if (!error) {
                root.refreshDecks();
                if (root.phase === "done")
                    root.requestCard();
            }
            if (callback)
                callback(error === null, error ? (error.message ?? "") : `${data.new} new, ${data.updated} updated, ${data.duplicate} already there`);
        }, 300000, false);
    }

    function refreshDecks() {
        if (!process.running || root.closing)
            return;
        root.call("decks", {}, (data, error) => {
            if (error)
                return;
            if (data.decks !== undefined)
                root.decks = data.decks;
            if (data.currentDeckId !== undefined)
                root.currentDeckId = data.currentDeckId;
            if (data.counts !== undefined)
                root.counts = data.counts;
            root._applySession(data);
        }, 5000, false);
    }

    function refreshProfiles(): void {
        if (!process.running)
            return;
        root.call("profiles", {}, (data, error) => {
            if (error)
                return;
            root.profiles = data.profiles ?? [];
        }, 5000, false);
    }

    onPhaseChanged: {
        if (root.phase === "error")
            root.busy = false;
    }

    Process {
        id: process
        stdinEnabled: true
        running: false
        onStarted: root._openCollection()
        onExited: {
            root._generation++;
            root._dropPending();
            if (root.closing) {
                root.phase = "closed";
                root.busy = false;
                return;
            }
            root.fail("helper_exited", "The Anki helper exited.", root.lastStderr.trim());
        }
        stdout: SplitParser {
            onRead: line => root._handleLine(line)
        }
        stderr: SplitParser {
            onRead: line => {
                root.lastStderr = (root.lastStderr + line + "\n").slice(-6000);
            }
        }
    }

    Timer {
        interval: 500
        repeat: true
        running: root._pendingCount > 0
        onTriggered: root._checkTimeouts()
    }

    Process {
        id: installer
        command: ["bash", root.engineInstaller]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("STEP "))
                    root.installStep = line.replace(/^STEP \S+ /, "");
            }
        }
        stderr: SplitParser {
            onRead: line => {
                if (line.trim().length > 0)
                    root.installError = line.trim();
            }
        }
        onExited: code => {
            root.installingEngine = false;
            if (code === 0) {
                root.installError = "";
                root.retry();
            } else if (root.installError.length === 0) {
                root.installError = `The installer stopped (code ${code})`;
            }
        }
    }

    Timer {
        id: forceStop
        interval: 2000
        onTriggered: {
            if (process.running)
                process.running = false;
            root.phase = "closed";
            root.busy = false;
        }
    }

    Timer {
        id: restartTimer
        interval: 150
        onTriggered: root.start()
    }
}
