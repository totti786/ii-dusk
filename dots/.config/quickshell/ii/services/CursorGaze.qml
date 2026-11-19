pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The pointer's position in the compositor's layout space, for things that look at it
 * (the AI bubble's creature). Quickshell cannot read the pointer outside its own
 * windows, so this asks Hyprland, and only while something is watching: each watcher
 * calls `watch()` and `unwatch()`, and the poll runs while there is at least one.
 * `idleMs` is how long the pointer has been still.
 */
Singleton {
    id: root

    property real x: 0
    property real y: 0
    property double lastMoved: Date.now()
    /** Bumps on every poll that saw movement, so watchers can react without binding to x and y. */
    property int moves: 0

    /** The pointer has been still for a while: poll less often. */
    property bool slow: false
    property int watchers: 0
    function watch() { root.watchers++; }
    function unwatch() { root.watchers = Math.max(0, root.watchers - 1); }

    Timer {
        interval: root.slow ? 250 : 70
        repeat: true
        running: root.watchers > 0
        triggeredOnStart: true
        onTriggered: if (!probe.running) probe.running = true
    }

    Process {
        id: probe
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = String(text).trim().split(",");
                const px = Number(parts[0]);
                const py = Number(parts[1]);
                if (isNaN(px) || isNaN(py))
                    return;
                if (px === root.x && py === root.y) {
                    root.slow = Date.now() - root.lastMoved > 5000;
                    return;
                }
                root.slow = false;
                root.x = px;
                root.y = py;
                root.lastMoved = Date.now();
                root.moves++;
            }
        }
    }
}
