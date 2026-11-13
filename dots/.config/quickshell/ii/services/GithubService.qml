pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * The GitHub tab's data, read through `gh` by scripts/github/github_dash.py (the token never
 * leaves gh). The last answer is on disk, so the tab opens filled and then refreshes; while
 * something holds the service it refreshes every few minutes.
 */
Singleton {
    id: root

    readonly property string script: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/github/github_dash.py`

    property var data: ({})
    property bool loaded: false
    property bool refreshing: false
    property string error: ""
    property string errorKind: ""
    readonly property bool hasData: root.data.user !== undefined
    readonly property var user: root.data.user ?? ({})
    readonly property var contrib: root.data.contrib ?? ({ total: 0, weeks: [], dates: [] })
    readonly property var repos: root.data.repos ?? []
    readonly property var languages: root.data.languages ?? []
    readonly property var pullRequests: root.data.pullRequests ?? ({ count: 0, items: [] })
    readonly property var issues: root.data.issues ?? ({ count: 0, items: [] })
    readonly property var reviews: root.data.reviews ?? ({ count: 0, items: [] })
    readonly property var notifications: root.data.notifications ?? []
    readonly property var feed: root.data.feed ?? []
    readonly property int unread: root.notifications.filter(n => n.unread).length

    property int holders: 0
    function retain(): void {
        root.holders++;
        if (root.holders === 1) {
            if (!root.loaded)
                cacheProc.running = true;
            else if (root.stale)
                root.refresh();
        }
    }
    function release(): void { root.holders = Math.max(0, root.holders - 1); }

    property real fetchedAt: 0
    readonly property bool stale: Date.now() - root.fetchedAt > 120000

    function refresh(): void {
        if (root.refreshing)
            return;
        root.refreshing = true;
        fetchProc.running = true;
    }

    function apply(text: string, fromCache: bool): void {
        let d;
        try {
            d = JSON.parse(text);
        } catch (e) {
            return;
        }
        if (d.ok === false) {
            root.error = d.error ?? "";
            root.errorKind = d.kind ?? "network";
            return;
        }
        if (d.user === undefined)
            return;
        root.error = "";
        root.errorKind = "";
        root.data = d;
        root.loaded = true;
        if (!fromCache)
            root.fetchedAt = Date.now();
    }

    Process {
        id: cacheProc
        command: ["python3", "-I", root.script, "--cached"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.apply(text, true);
                root.loaded = true;
                root.refresh();
            }
        }
    }

    Process {
        id: fetchProc
        command: ["python3", "-I", root.script]
        stdout: StdioCollector {
            onStreamFinished: root.apply(text, false)
        }
        onExited: root.refreshing = false
    }

    Timer {
        interval: 300000
        repeat: true
        running: root.holders > 0
        onTriggered: root.refresh()
    }

    /// Marks every notification read, then asks for the list again
    function markAllRead(): void {
        if (markProc.running)
            return;
        root.data = Object.assign({}, root.data, { notifications: root.notifications.map(n => Object.assign({}, n, { unread: false })) });
        markProc.running = true;
    }

    Process {
        id: markProc
        command: ["gh", "api", "-X", "PUT", "notifications", "-f", `last_read_at=${new Date().toISOString()}`]
        onExited: root.refresh()
    }

    function open(url: string): void {
        if (url && url.startsWith("https://"))
            Qt.openUrlExternally(url);
    }

    /// "3 h ago", "2 d ago" from an ISO time
    function ago(iso: string): string {
        const t = Date.parse(iso);
        if (isNaN(t))
            return "";
        const s = Math.max(0, (Date.now() - t) / 1000);
        if (s < 60) return Translation.tr("now");
        if (s < 3600) return Translation.tr("%1 min ago").arg(Math.floor(s / 60));
        if (s < 86400) return Translation.tr("%1 h ago").arg(Math.floor(s / 3600));
        if (s < 86400 * 30) return Translation.tr("%1 d ago").arg(Math.floor(s / 86400));
        if (s < 86400 * 365) return Translation.tr("%1 mo ago").arg(Math.floor(s / 86400 / 30));
        return Translation.tr("%1 y ago").arg(Math.floor(s / 86400 / 365));
    }
}
