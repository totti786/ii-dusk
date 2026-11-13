pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.modules.common
import qs.modules.common.functions

/**
 * Bridge to scripts/pipewire/graph.py: the PipeWire graph as it changes (nodes with their
 * ports, and the links between ports), and the two things the Patchbay app does to it,
 * connecting two ports and removing a link. Quickshell's own PipeWire module does not list
 * ports, so the graph is read from pw-dump. The script runs only while `watching` is set,
 * which the app does while its window is on show.
 */
Singleton {
    id: root

    readonly property string script: `${Directories.scriptPath}/pipewire/graph.py`

    property bool watching: false
    property var graph: ({ "nodes": [], "links": [] })
    /// Where each node was dragged to, by node name, kept between sessions
    property var positions: ({})
    property string lastError: ""

    function setPosition(name: string, x: real, y: real): void {
        const next = Object.assign({}, root.positions);
        next[name] = { "x": Math.round(x), "y": Math.round(y) };
        root.positions = next;
        saveDebounce.restart();
    }

    function arrange(): void {
        root.positions = ({});
        saveDebounce.restart();
    }

    // The layout is saved a moment after the last drag, and read once when the shell starts
    Timer {
        id: saveDebounce
        interval: 800
        onTriggered: positionsFile.setText(JSON.stringify(root.positions))
    }

    FileView {
        id: positionsFile
        path: FileUtils.trimFileProtocol(`${Directories.state}/user/patchbay_positions.json`)
        onLoaded: {
            try {
                const saved = JSON.parse(positionsFile.text());
                if (saved && typeof saved === "object")
                    root.positions = saved;
            } catch (e) {
                // A damaged file: start from the tidy layout
            }
        }
    }

    function connectPorts(outPort: int, inPort: int): void {
        root.lastError = "";
        linkProc.command = ["python3", "-I", root.script, "link", String(outPort), String(inPort)];
        linkProc.running = true;
    }

    function disconnectLink(linkId: int): void {
        root.lastError = "";
        unlinkProc.command = ["python3", "-I", root.script, "unlink", String(linkId)];
        unlinkProc.running = true;
    }

    Process {
        id: watchProc
        command: ["python3", "-I", root.script, "watch"]
        running: root.watching
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.graph = JSON.parse(line);
                } catch (e) {
                    // A half line at shutdown: the next snapshot is whole
                }
            }
        }
        // The graph can come back as soon as the sound server does
        onExited: if (root.watching) restart.start()
    }

    Timer {
        id: restart
        interval: 2000
        // Qt.binding, not `true`: a plain assignment would drop the `running: root.watching` binding for good
        onTriggered: if (root.watching) watchProc.running = Qt.binding(() => root.watching)
    }

    Process {
        id: linkProc
        stderr: StdioCollector {
            onStreamFinished: if (text.trim().length > 0) root.lastError = text.trim()
        }
    }

    Process {
        id: unlinkProc
        stderr: StdioCollector {
            onStreamFinished: if (text.trim().length > 0) root.lastError = text.trim()
        }
    }
}
