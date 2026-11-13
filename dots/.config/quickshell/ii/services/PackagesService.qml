pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.modules.common

/**
 * Bridge to scripts/packages/pkgs.py (read-only pacman and yay queries, answered as JSON)
 * and the one place the Packages app changes the system.
 *
 * Repository changes run as `pkexec pacman ...` so the shell's polkit prompt asks for the
 * password, and their output is streamed into `taskLog`. AUR changes build code from the
 * network, so they run in a terminal where the PKGBUILD can be read and yay can ask; they
 * are never run unattended. Every command is an argument list, never a shell string.
 */
Singleton {
    id: root

    readonly property string script: `${Directories.scriptPath}/packages/pkgs.py`

    // ── Updates ───────────────────────────────────────────────────────────
    property var repoUpdates: []
    property var aurUpdates: []
    property bool checking: false
    property string checkError: ""
    property double lastChecked: 0
    readonly property int updateCount: root.repoUpdates.length + root.aurUpdates.length

    // ── Installed ─────────────────────────────────────────────────────────
    property var installed: []
    property bool loadingInstalled: false
    property string installedError: ""

    // ── Browse ────────────────────────────────────────────────────────────
    property var results: []
    property bool searching: false
    property string searchedQuery: ""
    property bool resultsTruncated: false

    // ── One package's details ─────────────────────────────────────────────
    property var detail: ({})
    property bool loadingDetail: false

    // ── Maintenance ───────────────────────────────────────────────────────
    property var orphans: ({ "names": [], "size": 0 })
    property var cache: ({ "size": 0, "files": 0, "reclaimable": 0 })

    // ── The running change ────────────────────────────────────────────────
    property bool taskRunning: false
    property string taskTitle: ""
    property var taskLog: []
    /// -1 while it runs or before one has, then pacman's exit status
    property int taskExit: -1
    readonly property bool taskShown: root.taskRunning || root.taskExit !== -1

    function parse(text) {
        try {
            return JSON.parse(text);
        } catch (e) {
            return null;
        }
    }

    function checkUpdates(): void {
        if (updatesProc.running)
            return;
        root.checking = true;
        root.checkError = "";
        updatesProc.running = true;
    }

    function loadInstalled(): void {
        if (installedProc.running)
            return;
        root.loadingInstalled = true;
        root.installedError = "";
        installedProc.running = true;
    }

    function search(query: string, includeAur: bool): void {
        const q = String(query ?? "").trim();
        if (q.length < 2) {
            root.results = [];
            root.searchedQuery = "";
            return;
        }
        searchProc.running = false;
        root.searching = true;
        root.searchedQuery = q;
        // "--" keeps a query that starts with a dash from being read as an option
        searchProc.command = ["python3", "-I", root.script, "search"].concat(includeAur ? ["--aur"] : []).concat(["--", q]);
        searchProc.running = true;
    }

    function loadDetail(name: string): void {
        infoProc.running = false;
        root.loadingDetail = true;
        root.detail = { "name": name };
        infoProc.command = ["python3", "-I", root.script, "info", name];
        infoProc.running = true;
    }

    function loadMaintenance(): void {
        if (!orphansProc.running)
            orphansProc.running = true;
        if (!cacheProc.running)
            cacheProc.running = true;
    }

    function dismissTask(): void {
        if (root.taskRunning)
            return;
        root.taskExit = -1;
        root.taskLog = [];
        root.taskTitle = "";
    }

    // pacman refuses a package name that is not one, but the names come from our own
    // lists; this keeps anything odd from ever reaching the command line.
    function validName(name): bool {
        return /^[a-z0-9@_+][a-z0-9@._+-]*$/i.test(String(name));
    }

    function runPrivileged(title: string, args: var): bool {
        if (root.taskRunning || !args.every(arg => !String(arg).startsWith("-") || root.knownFlags.includes(arg)))
            return false;
        root.taskTitle = title;
        root.taskLog = [];
        root.taskExit = -1;
        root.taskRunning = true;
        taskProc.command = ["pkexec", "pacman"].concat(args);
        taskProc.running = true;
        return true;
    }

    readonly property var knownFlags: ["-Syu", "-S", "-Rs", "-Rns", "--needed", "--noconfirm"]

    /// Upgrade everything in the repositories, as one transaction
    function upgradeRepo(): bool {
        return root.runPrivileged(Translation.tr("Updating the system"), ["-Syu", "--noconfirm"]);
    }

    function installRepo(names: var): bool {
        if (!names.length || !names.every(root.validName))
            return false;
        return root.runPrivileged(Translation.tr("Installing %1").arg(names.join(", ")),
            ["-S", "--needed", "--noconfirm"].concat(names));
    }

    function remove(names: var): bool {
        if (!names.length || !names.every(root.validName))
            return false;
        return root.runPrivileged(Translation.tr("Removing %1").arg(names.length > 3 ? Translation.tr("%1 packages").arg(names.length) : names.join(", ")),
            ["-Rs", "--noconfirm"].concat(names));
    }

    function removeOrphans(): bool {
        return root.orphans.names.length > 0 && root.remove(root.orphans.names);
    }

    /// Keep this many versions of each package in the cache (paccache), or none of the
    /// ones that are uninstalled
    function cleanCache(keep: int, uninstalledOnly: bool): bool {
        if (root.taskRunning)
            return false;
        root.taskTitle = Translation.tr("Cleaning the package cache");
        root.taskLog = [];
        root.taskExit = -1;
        root.taskRunning = true;
        taskProc.command = uninstalledOnly ? ["pkexec", "paccache", "-ruk0"] : ["pkexec", "paccache", "-rk" + Math.max(1, keep)];
        taskProc.running = true;
        return true;
    }

    /// AUR packages: build in a terminal so the PKGBUILD is read and yay can ask
    function aurInTerminal(args: var): void {
        const terminal = String(Config.options.apps?.terminal ?? "kitty -1").split(" ").filter(part => part.length > 0);
        // The arguments are positional parameters of the inner shell, never part of its text
        Quickshell.execDetached(terminal.concat(["-e", "bash", "-c",
            "yay \"$@\"; echo; read -n1 -r -p 'Done. Press any key to close.'", "yay-session"]).concat(args));
    }

    function installAur(name: string): void {
        if (root.validName(name))
            root.aurInTerminal(["-S", "--", name]);
    }

    function updateAur(): void {
        root.aurInTerminal(["-Sua"]);
    }

    Process {
        id: updatesProc
        command: ["python3", "-I", root.script, "updates"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.checking = false;
                const r = root.parse(text);
                if (!r) {
                    root.checkError = Translation.tr("Could not read the update list");
                    return;
                }
                root.repoUpdates = r.repo ?? [];
                root.aurUpdates = r.aur ?? [];
                root.checkError = (r.errors ?? []).join("\n");
                root.lastChecked = Date.now();
            }
        }
    }

    Process {
        id: installedProc
        command: ["python3", "-I", root.script, "installed"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loadingInstalled = false;
                const r = root.parse(text);
                if (r?.packages)
                    root.installed = r.packages;
                else
                    root.installedError = r?.error ?? Translation.tr("Could not read the installed packages");
            }
        }
    }

    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.searching = false;
                const r = root.parse(text);
                root.results = r?.results ?? [];
                root.resultsTruncated = r?.truncated ?? false;
            }
        }
    }

    Process {
        id: infoProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.loadingDetail = false;
                const r = root.parse(text);
                if (r)
                    root.detail = r;
            }
        }
    }

    Process {
        id: orphansProc
        command: ["python3", "-I", root.script, "orphans"]
        stdout: StdioCollector {
            onStreamFinished: {
                const r = root.parse(text);
                if (r)
                    root.orphans = r;
            }
        }
    }

    Process {
        id: cacheProc
        command: ["python3", "-I", root.script, "cache"]
        stdout: StdioCollector {
            onStreamFinished: {
                const r = root.parse(text);
                if (r)
                    root.cache = r;
            }
        }
    }

    Process {
        id: taskProc
        stdout: SplitParser {
            onRead: line => root.taskLog = root.taskLog.concat([line]).slice(-400)
        }
        stderr: SplitParser {
            onRead: line => root.taskLog = root.taskLog.concat([line]).slice(-400)
        }
        onExited: (code, status) => {
            root.taskRunning = false;
            root.taskExit = code;
            // 126 and 127 are pkexec's own "not authorised" and "dismissed"
            if (code === 0) {
                root.checkUpdates();
                root.loadInstalled();
                root.loadMaintenance();
            }
        }
    }
}
