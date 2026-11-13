pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.services
import qs.modules.common

/**
 * Bridge to scripts/torrents/qb.py, which talks to qBittorrent's web API: the torrent list
 * and speeds as they change, and what the Torrents app does with them (pause, resume,
 * remove, add, limits). The script runs only while `watching` is set, which the app does
 * while its window is on show.
 */
Singleton {
    id: root

    readonly property string script: `${Directories.scriptPath}/torrents/qb.py`

    property bool watching: false
    /// Desktop widgets that show the live list ask for it here, like the window does
    property int watchHolders: 0
    readonly property bool watchWanted: root.watching || root.watchHolders > 0
        // A download outlives its window: the island follows it until it finishes. Once
        // the list has shown one, this keeps itself alive; with none, nothing runs.
        || (GlobalStates.islandOwnsProgress && root.pendingDownloads.length > 0)
    /// "unknown" until the first answer, then "up", "down" (not running) or "denied" (login needed)
    property string state: "unknown"
    property string address: ""
    property var torrents: []
    property var transfer: ({})
    property string lastError: ""
    property var detail: ({ "hash": "", "files": [], "trackers": [], "peers": [], "props": {}, "ok": true })
    property real downLimit: 0
    property real upLimit: 0

    readonly property int downloadingCount: root.torrents.filter(t => ["downloading", "forcedDL", "metaDL", "forcedMetaDL", "stalledDL", "queuedDL", "checkingDL", "allocating"].includes(t.state)).length
    readonly property int seedingCount: root.torrents.filter(t => ["uploading", "forcedUP", "stalledUP", "queuedUP", "checkingUP"].includes(t.state)).length
    readonly property int pausedCount: root.torrents.filter(t => t.state.startsWith("stopped") || t.state.startsWith("paused")).length
    readonly property int erroredCount: root.torrents.filter(t => t.state === "error" || t.state === "missingFiles").length

    /// Everything still to download, stalled or queued included: the list keeps being followed
    /// so a torrent that picks up again is noticed. Only the ones moving become island jobs.
    readonly property var pendingDownloads: root.torrents.filter(t => ["downloading", "forcedDL", "metaDL", "forcedMetaDL", "allocating", "stalledDL", "queuedDL", "checkingDL"].includes(t.state))
    // Hashes just told to stop: they leave the active list at once instead of when the next
    // poll reports them stopped, so a Pause feels immediate.
    property var _stopping: ({})
    readonly property var activeDownloads: root.torrents.filter(t => !root._stopping[t.hash]
        && ["downloading", "forcedDL", "metaDL", "forcedMetaDL", "allocating"].includes(t.state))

    // ── On the island ────────────────────────────────────────────────────────
    // Torrents that are actually pulling data are background jobs there. Seeding is not:
    // it is days long and has no end to show.
    property var _islandJobIds: []
    onTorrentsChanged: {
        // Forget a stop once the poll agrees (or the torrent is gone)
        const live = new Set(root.torrents.filter(t => ["downloading", "forcedDL", "metaDL", "forcedMetaDL", "allocating"].includes(t.state)).map(t => t.hash));
        const keep = {};
        for (const h of Object.keys(root._stopping))
            if (live.has(h))
                keep[h] = true;
        if (Object.keys(keep).length !== Object.keys(root._stopping).length)
            root._stopping = keep;
        Qt.callLater(root._publishIslandJobs);
    }
    Timer {
        // Safety net: a stop that never took must not hide a download for good
        id: stoppingExpiry
        interval: 6000
        onTriggered: root._stopping = ({})
    }
    Connections {
        target: GlobalStates
        function onIslandOwnsProgressChanged() { Qt.callLater(root._publishIslandJobs); }
    }

    function _publishIslandJobs(): void {
        const shown = new Set();
        if (GlobalStates.islandOwnsProgress) {
            for (const t of root.activeDownloads) {
                const key = "qb:" + t.hash;
                shown.add(key);
                const meta = t.state === "metaDL" || t.state === "forcedMetaDL";
                ProgressService.reportShellJob(key, {
                    appName: Translation.tr("Torrents"),
                    icon: "downloading",
                    percent: Math.round((t.progress ?? 0) * 100),
                    message: meta ? Translation.tr("Fetching metadata: %1").arg(t.name) : t.name,
                    speedText: ProgressService.formatSpeed(t.dlspeed ?? 0),
                    etaText: (t.dlspeed ?? 0) > 0 ? ProgressService.shortEta(t.eta ?? 0) : ""
                });
            }
        }
        for (const key of root._islandJobIds) {
            if (shown.has(key))
                continue;
            const t = root.torrents.find(x => "qb:" + x.hash === key);
            if (!GlobalStates.islandOwnsProgress || !t)
                ProgressService.finishShellJob(key, "cleared");
            else if (t.state === "error" || t.state === "missingFiles")
                ProgressService.finishShellJob(key, "failed", Translation.tr("Torrent failed"));
            else if (t.progress >= 1)
                ProgressService.finishShellJob(key, "completed", Translation.tr("Torrent complete"));
            else if (root._stopping[t.hash] || ["pausedDL", "stoppedDL", "pausedUP", "stoppedUP"].includes(t.state))
                ProgressService.finishShellJob(key, "paused", Translation.tr("Paused"));   // stays a minute, with Resume
            else
                ProgressService.finishShellJob(key, "cleared");
        }
        root._islandJobIds = Array.from(shown);
        // A paused row is kept for a minute so it can be resumed; once qBittorrent is gone, or
        // the torrent was removed or went back to work, it has nothing left to offer.
        for (const job of ProgressService.jobs) {
            if (job.source !== "shell" || job.state !== "paused" || !String(job.id).startsWith("qb:"))
                continue;
            const t = root.state === "up" ? root.torrents.find(x => "qb:" + x.hash === job.id) : null;
            if (!t || !(root._stopping[t.hash] || ["pausedDL", "stoppedDL", "pausedUP", "stoppedUP"].includes(t.state)))
                ProgressService.finishShellJob(job.id, "cleared");
        }
    }

    property var categories: []
    property bool altSpeed: false
    property var prefs: ({})

    // Search through qBittorrent's own search plugins
    property var searchPlugins: []
    property var searchResults: []
    /// "idle", "running", "done" or "error"
    property string searchState: "idle"
    property string searchError: ""
    property string searchQuery: ""
    property string searchWanted: ""
    property string searchWantedPlugins: ""

    // Every change goes through one queue, so two quick clicks never overwrite each other
    property var pending: []

    function run(args: var, after: var): void {
        root.pending = root.pending.concat([{ "args": args, "after": after ?? "" }]);
        if (!doer.running)
            root.next();
    }

    function next(): void {
        if (root.pending.length === 0)
            return;
        const item = root.pending[0];
        root.pending = root.pending.slice(1);
        doer.after = item.after;
        doer.command = ["python3", "-I", root.script].concat(item.args);
        doer.running = true;
    }

    /// Shows a start or stop at once; the next poll replaces it with what qBittorrent says.
    function patchState(action: string, hashes: var): void {
        if (action === "recheck") {
            // Shows "checking" at once; a stopped torrent stays stopped when the check ends
            root.torrents = root.torrents.map(t => hashes.includes(t.hash)
                ? Object.assign({}, t, { state: (t.progress ?? 0) >= 1 ? "checkingUP" : "checkingDL" }) : t);
            return;
        }
        const stopping = action === "stop" || action === "pause";
        const starting = action === "start" || action === "resume";
        if (!stopping && !starting)
            return;
        const wasStopped = ["stoppedDL", "stoppedUP", "pausedDL", "pausedUP"];
        root.torrents = root.torrents.map(t => {
            if (!hashes.includes(t.hash))
                return t;
            if (stopping && !wasStopped.includes(t.state))
                return Object.assign({}, t, { state: (t.progress ?? 0) >= 1 ? "stoppedUP" : "stoppedDL", dlspeed: 0, upspeed: 0, eta: 8640000 });
            if (starting && wasStopped.includes(t.state))
                return Object.assign({}, t, { state: (t.progress ?? 0) >= 1 ? "stalledUP" : "stalledDL" });
            return t;
        });
    }

    /// Asks the watcher for a fresh look now and several in the next seconds.
    function nudge(): void {
        if (watchProc.running)
            watchProc.write("r\n");
    }

    function act(action: string, hashes: var): void {
        if (hashes.length === 0)
            return;
        root.lastError = "";
        if (action === "start" || action === "resume") {
            const next = Object.assign({}, root._stopping);
            for (const h of hashes)
                delete next[h];
            root._stopping = next;
        }
        if (action === "stop" || action === "pause") {
            const next = Object.assign({}, root._stopping);
            for (const h of hashes)
                next[h] = true;
            root._stopping = next;
            stoppingExpiry.restart();
            Qt.callLater(root._publishIslandJobs);
        }
        root.patchState(action, hashes);
        root.run(["action", action].concat(hashes), "nudge");
    }

    function queueMove(move: string, hashes: var): void {
        root.lastError = "";
        root.run(["queue", move].concat(hashes));
    }

    function op(name: string, hashes: var, value: var): void {
        root.lastError = "";
        root.run(["op", name].concat(hashes).concat(["--value", String(value ?? "")]));
    }

    /// opts: dir, category, paused, sequential, skipCheck
    function addUrl(url: string, opts: var): void {
        root.lastError = "";
        root.run(["add-url", url].concat(root.addArgs(opts)));
    }

    function addFile(path: string, opts: var): void {
        root.lastError = "";
        root.run(["add-file", path].concat(root.addArgs(opts)));
    }

    function addArgs(o: var): var {
        const out = [];
        if (o?.dir)
            out.push("--dir", o.dir);
        if (o?.category)
            out.push("--category", o.category);
        if (o?.paused)
            out.push("--paused");
        if (o?.sequential)
            out.push("--sequential");
        if (o?.skipCheck)
            out.push("--skip-check");
        return out;
    }

    function setFilePriority(hash: string, prio: int, indexes: var): void {
        if (indexes.length === 0)
            return;
        root.lastError = "";
        root.run(["file-prio", hash, String(prio)].concat(indexes.map(i => String(i))), "detail:" + hash);
    }

    function categoryAdd(name: string, dir: string): void {
        root.run(dir.length > 0 ? ["category", "add", name, "--dir", dir] : ["category", "add", name]);
    }

    function categoryRemove(name: string): void {
        root.run(["category", "remove", name]);
    }

    function loadDetail(hash: string): void {
        if (detailProc.running)
            return;
        detailProc.command = ["python3", "-I", root.script, "detail", hash];
        detailProc.running = true;
    }

    function loadLimits(): void {
        limitsProc.command = ["python3", "-I", root.script, "limits"];
        limitsProc.running = true;
    }

    function setLimits(down: real, up: real): void {
        limitsProc.command = ["python3", "-I", root.script, "limits", "--down", String(Math.round(down)), "--up", String(Math.round(up))];
        limitsProc.running = true;
    }

    function loadPrefs(): void {
        prefsProc.command = ["python3", "-I", root.script, "prefs"];
        prefsProc.running = true;
    }

    function setPrefs(changes: var): void {
        root.lastError = "";
        root.run(["set-prefs", JSON.stringify(changes)], "prefs");
    }

    function loadSearchPlugins(): void {
        if (pluginsProc.running)
            return;
        pluginsProc.command = ["python3", "-I", root.script, "search-plugins"];
        pluginsProc.running = true;
    }

    function setSearchPlugin(name: string, on: bool): void {
        root.run(["search-plugin", name, on ? "on" : "off"], "plugins");
    }

    function updateSearchPlugins(): void {
        root.run(["search-update"], "plugins");
    }

    /// plugins: "" for every enabled one, else a comma list of plugin names
    function search(query: string, plugins: string): void {
        const q = query.trim();
        if (q.length === 0)
            return;
        root.searchResults = [];
        root.searchError = "";
        root.searchQuery = q;
        root.searchState = "running";
        root.searchWanted = q;
        root.searchWantedPlugins = plugins;
        if (searchProc.running)
            searchProc.running = false;  // onExited starts the wanted one
        else
            root.launchSearch();
    }

    function stopSearch(): void {
        root.searchWanted = "";
        if (searchProc.running)
            searchProc.running = false;
        if (root.searchState === "running")
            root.searchState = "done";
    }

    function launchSearch(): void {
        if (root.searchWanted === "")
            return;
        const cmd = ["python3", "-I", root.script, "search", root.searchWanted];
        if (root.searchWantedPlugins.length > 0)
            cmd.push("--plugins", root.searchWantedPlugins);
        root.searchWanted = "";
        searchProc.command = cmd;
        searchProc.running = true;
    }

    function toggleAltSpeed(): void {
        root.run(["alt-speed"]);
    }

    function startService(): void {
        root.lastError = "";
        startProc.running = true;
    }

    function shutdownService(): void {
        shutdownProc.running = true;
    }

    Process {
        id: watchProc
        command: ["python3", "-I", root.script, "watch"]
        running: root.watchWanted
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const d = JSON.parse(line);
                    root.state = d.state;
                    root.address = d.base ?? "";
                    if (d.state === "up") {
                        root.torrents = d.torrents;
                        root.transfer = d.transfer;
                        root.categories = d.categories ?? [];
                        root.altSpeed = d.alt ?? false;
                    } else {
                        root.torrents = [];
                        root.transfer = ({});
                    }
                } catch (e) {
                    // A half line at shutdown: the next one is whole
                }
            }
        }
        onExited: if (root.watchWanted) restart.start()
    }

    Timer {
        id: restart
        interval: 2000
        // Qt.binding, not `true`: a plain assignment would drop the `running: root.watchWanted` binding for good
        onTriggered: if (root.watchWanted) watchProc.running = Qt.binding(() => root.watchWanted)
    }

    Process {
        id: doer
        property string after: ""
        stderr: StdioCollector {
            onStreamFinished: if (text.trim().length > 0) root.lastError = text.trim()
        }
        onExited: {
            if (doer.after === "nudge")
                root.nudge();
            else if (doer.after.startsWith("detail:"))
                root.loadDetail(doer.after.substring(7));
            else if (doer.after === "prefs")
                root.loadPrefs();
            else if (doer.after === "plugins")
                root.loadSearchPlugins();
            root.next();
        }
    }

    component Doer: Process {
        stderr: StdioCollector {
            onStreamFinished: if (text.trim().length > 0) root.lastError = text.trim()
        }
    }

    Doer { id: startProc; command: ["python3", "-I", root.script, "start-service"] }
    Doer { id: shutdownProc; command: ["python3", "-I", root.script, "shutdown"] }

    Process {
        id: prefsProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (d.ok)
                        root.prefs = d.prefs;
                } catch (e) {
                }
            }
        }
    }

    Process {
        id: detailProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.detail = JSON.parse(text);
                } catch (e) {
                    root.detail = ({ "hash": "", "files": [], "trackers": [], "peers": [], "props": {}, "ok": false });
                }
            }
        }
    }

    Process {
        id: limitsProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (d.ok) {
                        root.downLimit = d.down;
                        root.upLimit = d.up;
                    }
                } catch (e) {
                }
            }
        }
    }

    Process {
        id: pluginsProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (d.ok)
                        root.searchPlugins = d.plugins;
                } catch (e) {
                }
            }
        }
    }

    Process {
        id: searchProc
        stdout: SplitParser {
            onRead: line => {
                try {
                    const d = JSON.parse(line);
                    if (!d.ok) {
                        root.searchError = d.error ?? "";
                        root.searchState = "error";
                        return;
                    }
                    if (d.rows.length > 0)
                        root.searchResults = root.searchResults.concat(d.rows);
                    if (d.done)
                        root.searchState = "done";
                } catch (e) {
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim().length > 0) {
                root.searchError = text.trim();
                root.searchState = "error";
            }
        }
        onExited: {
            if (root.searchWanted !== "")
                root.launchSearch();
            else if (root.searchState === "running")
                root.searchState = "done";
        }
    }
}
