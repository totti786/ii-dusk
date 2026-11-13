pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.modules.common

/**
 * The connection to scripts/files/fm_helper.py: one long-lived process, JSON lines both ways.
 * `request()` takes handlers for the reply: `done(msg)`, `error(text)`, `progress(msg)`,
 * `partial(msg)` and `conflict(msg)`; the helper does the work off this thread.
 */
Item {
    id: root

    property bool ready: false
    /// A window of its own keeps its helper alive whatever the main window does
    property bool forceRun: false
    readonly property bool wanted: GlobalStates.fileManagerOpen || root.forceRun
    property string home: ""
    property int serial: 0
    property var pending: ({})

    /// A watched folder changed (debounced by the helper)
    signal changed(string watchId)

    property var opNames: ({})

    function request(op: string, payload: var, handlers: var): int {
        root.serial++;
        const id = root.serial;
        if (handlers)
            root.pending[id] = handlers;
        root.opNames[id] = op;
        const msg = Object.assign({}, payload ?? {}, { id: id, op: op });
        proc.write(JSON.stringify(msg) + "\n");
        return id;
    }

    function cancel(id: int): void {
        proc.write(JSON.stringify({ op: "cancel", target: id }) + "\n");
    }

    function resolve(id: int, action: string, all: bool, name: string): void {
        proc.write(JSON.stringify({ op: "resolve", target: id, action: action, all: all, name: name }) + "\n");
    }

    function handle(line: string): void {
        let m;
        try {
            m = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (m.id === undefined) {
            if (m.event === "ready") {
                root.home = m.home;
                root.ready = true;
            } else if (m.event === "changed") {
                root.changed(String(m.watchId));
            }
            return;
        }
        const h = root.pending[m.id];
        if (!h)
            return;
        if (m.event === "result") {
            delete root.pending[m.id];
            if (h.done)
                h.done(m);
        } else if (m.event === "error") {
            console.warn(`[FileManager] ${root.opNames[m.id] ?? "?"} failed: ${m.message}`);
            delete root.pending[m.id];
            if (h.error)
                h.error(String(m.message ?? ""));
        } else if (m.event === "progress" && h.progress) {
            h.progress(m);
        } else if (m.event === "partial" && h.partial) {
            h.partial(m);
        } else if (m.event === "conflict" && h.conflict) {
            h.conflict(m);
        }
    }

    Process {
        id: proc
        command: ["/bin/sh", Directories.scriptPath + "/files/fm_helper_run.sh"]
        // The window is built ahead of the first open, but the helper (the Rust fm-helper, about 2 MB;
        // fm_helper.py is the fallback) only lives while the window is shown.
        running: root.wanted
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => root.handle(line)
        }
        onExited: {
            root.ready = false;
            const stale = root.pending;
            root.pending = ({});
            for (const k in stale)
                if (stale[k].error)
                    stale[k].error("The file helper stopped");
            if (root.wanted)
                restart.start();
        }
    }

    Connections {
        target: GlobalStates
        function onFileManagerOpenChanged() {
            proc.running = root.wanted;
        }
    }

    Timer {
        id: restart
        interval: 1000
        onTriggered: proc.running = root.wanted
    }
}
