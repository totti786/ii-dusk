pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.services
import qs.modules.common

/**
 * Bridge to scripts/ytdl/ytdl.py, the JSON front for yt-dlp. The downloads themselves run
 * in detached workers that write job files; this follows them (`ytdl.py watch`, while the
 * Downloads window is open) and sends the commands. Nothing here parses yt-dlp output.
 */
Singleton {
    id: root

    readonly property string script: `${Directories.scriptPath}/ytdl/ytdl.py`

    property var jobs: []
    /// Desktop widgets that show the live list ask for it here, like the window does
    property int watchHolders: 0
    readonly property var activeJobs: root.jobs.filter(j => ["queued", "running", "processing"].includes(j.status))
    readonly property var finishedJobs: root.jobs.filter(j => !["queued", "running", "processing"].includes(j.status))

    /// The link being looked at: {} before one, then the info the CLI found
    property var info: ({})
    property bool probing: false
    property string probeError: ""
    property string probedUrl: ""

    property string startError: ""
    property var settings: ({})
    property bool saving: false
    property string saveError: ""

    // ── On the island ────────────────────────────────────────────────────────
    // Each running download is a background job there (ProgressService), named by its
    // own id so two at once stay two. Only while the island shows jobs at all.
    property var _islandJobIds: []
    onJobsChanged: Qt.callLater(root._publishIslandJobs)
    Connections {
        target: GlobalStates
        function onIslandOwnsProgressChanged() { Qt.callLater(root._publishIslandJobs); }
    }

    function _publishIslandJobs(): void {
        const shown = new Set();
        if (GlobalStates.islandOwnsProgress) {
            for (const job of root.activeJobs) {
                const key = "ytdl:" + job.id;
                shown.add(key);
                const processing = job.status === "processing";
                const queued = job.status === "queued";
                ProgressService.reportShellJob(key, {
                    appName: Translation.tr("Downloads"),
                    icon: processing ? "transform" : "download",
                    percent: Math.max(0, Math.min(100, Math.round(job.percent ?? 0))),
                    message: processing ? Translation.tr("Finishing %1").arg(job.title || "")
                        : queued ? Translation.tr("Waiting: %1").arg(job.title || "")
                        : (job.title || Translation.tr("Downloading")),
                    speedText: processing || queued ? "" : ProgressService.formatSpeed(job.speed ?? 0),
                    etaText: processing || queued ? "" : ProgressService.shortEta(job.eta ?? 0)
                });
            }
        }
        for (const key of root._islandJobIds) {
            if (shown.has(key))
                continue;
            const job = root.jobs.find(j => "ytdl:" + j.id === key);
            if (!GlobalStates.islandOwnsProgress || !job || job.status === "cancelled")
                ProgressService.finishShellJob(key, "cleared");
            else if (job.status === "error")
                ProgressService.finishShellJob(key, "failed", Translation.tr("Download failed"));
            else
                ProgressService.finishShellJob(key, "completed", Translation.tr("Download complete"));
        }
        root._islandJobIds = Array.from(shown);
    }

    function refresh(): void {
        if (!listProc.running)
            listProc.running = true;
    }

    function probe(url: string): void {
        const u = url.trim();
        if (u.length === 0 || infoProc.running)
            return;
        root.probeError = "";
        root.info = ({});
        root.probedUrl = u;
        root.probing = true;
        infoProc.command = ["python3", "-I", root.script, "info", u];
        infoProc.running = true;
    }

    function clearProbe(): void {
        root.info = ({});
        root.probeError = "";
        root.probedUrl = "";
    }

    /// Queue what the preview shows. `opts`: {preset, playlist, subs}
    function start(opts: var): void {
        const i = root.info;
        const cmd = ["python3", "-I", root.script, "start", i.url ?? root.probedUrl,
                     "--title", i.title ?? "", "--thumb", i.thumbnail ?? ""];
        if ((i.kind ?? "") === "file")
            cmd.push("--kind", "file");   // a plain file: aria2c, not yt-dlp
        if (opts.preset)
            cmd.push("--preset", opts.preset);
        if (opts.playlist)
            cmd.push("--playlist");
        if (opts.subs)
            cmd.push("--subs");
        root.startError = "";
        startProc.command = cmd;
        startProc.running = true;
    }

    function cancel(id: string): void {
        root.act(["cancel", id]);
    }

    function remove(id: string): void {
        root.act(["remove", id]);
    }

    function clearFinished(): void {
        root.act(["clear"]);
    }

    // Actions run one after another: a busy Process keeps only the newest command it is
    // given, so removing three entries quickly would lose the middle one.
    property var actionQueue: []

    function act(args: var): void {
        root.actionQueue = root.actionQueue.concat([args]);
        if (!actionProc.running)
            root.nextAction();
    }

    function nextAction(): void {
        if (root.actionQueue.length === 0)
            return;
        actionProc.command = ["python3", "-I", root.script].concat(root.actionQueue[0]);
        root.actionQueue = root.actionQueue.slice(1);
        actionProc.running = true;
    }

    function openFolder(path: string): void {
        Quickshell.execDetached(["xdg-open", path]);
    }

    function openFile(job: var): void {
        Quickshell.execDetached(["xdg-open", job.file && job.file.length > 0 ? job.file : job.dir]);
    }

    function loadSettings(): void {
        settingsProc.command = ["python3", "-I", root.script, "config", "show"];
        settingsProc.running = true;
    }

    /// Patch travels in the environment, like mediator's, so a cookie browser or path never
    /// lands in a process listing.
    function saveSettings(patch: var): void {
        if (saveProc.running)
            return;
        root.saveError = "";
        root.saving = true;
        saveProc.environment = ({ "YTDL_CONFIG_PATCH": JSON.stringify(patch) });
        saveProc.command = ["python3", "-I", root.script, "config", "set"];
        saveProc.running = true;
    }

    function parse(text: string): var {
        try {
            return JSON.parse(text);
        } catch (e) {
            return null;
        }
    }

    Process {
        id: listProc
        command: ["python3", "-I", root.script, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const r = root.parse(text);
                if (r?.ok)
                    root.jobs = r.jobs;
            }
        }
    }

    Process {
        id: infoProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.probing = false;
                const r = root.parse(text);
                if (r?.ok)
                    root.info = r.info;
                else
                    root.probeError = r?.error ?? "Could not read that link";
            }
        }
    }

    Process {
        id: startProc
        stdout: StdioCollector {
            onStreamFinished: {
                const r = root.parse(text);
                if (r?.ok) {
                    root.clearProbe();
                    root.refresh();
                } else {
                    root.startError = r?.error ?? "Could not start the download";
                }
            }
        }
    }

    Process {
        id: actionProc
        onExited: {
            root.refresh();
            root.nextAction();
        }
    }

    Process {
        id: settingsProc
        stdout: StdioCollector {
            onStreamFinished: {
                const r = root.parse(text);
                if (r?.ok)
                    root.settings = r.settings;
            }
        }
    }

    Process {
        id: saveProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.saving = false;
                const r = root.parse(text);
                if (r?.ok)
                    root.settings = r.settings;
                else
                    root.saveError = r?.error ?? "Could not save";
            }
        }
    }

    // While the window is open, one helper streams the list as job files change (it only
    // stats them in between). Nothing outside the window shows the jobs, and the workers
    // send their own notifications, so nothing runs while it is closed.
    Process {
        id: watchProc
        command: ["python3", "-I", root.script, "watch"]
        running: GlobalStates.downloadsOpen || root.watchHolders > 0
            // A download outlives its window: the island follows it until it ends
            || (GlobalStates.islandOwnsProgress && root.activeJobs.length > 0)
        stdout: SplitParser {
            onRead: line => {
                const r = root.parse(line);
                if (r?.ok)
                    root.jobs = r.jobs;
            }
        }
    }
}
