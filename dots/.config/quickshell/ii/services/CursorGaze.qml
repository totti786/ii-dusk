pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * The pointer's position in the compositor's layout space, for things that look at it
 * (the AI bubble's creature). Quickshell cannot read the pointer outside its own
 * windows, so this asks Hyprland over its request socket (a program per question
 * cost more than everything it was for), and only while something is watching: each
 * watcher calls `watch()` and `unwatch()`, and the poll runs while there is at least
 * one. The longer the pointer has been still, the less often it asks.
 * `idleMs` is how long the pointer has been still.
 */
Singleton {
    id: root

    property real x: 0
    property real y: 0
    property double lastMoved: Date.now()
    /** Bumps on every poll that saw movement, so watchers can react without binding to x and y. */
    property int moves: 0

    /** Time between questions: quick while the pointer moves, slower once it has been still. */
    property int interval: 100
    property int watchers: 0
    function watch() {
        // Whoever starts watching sees movement at once.
        if (root.watchers === 0) root.interval = 100;
        root.watchers++;
    }
    function unwatch() { root.watchers = Math.max(0, root.watchers - 1); }

    Timer {
        interval: root.interval
        repeat: true
        running: root.watchers > 0
        triggeredOnStart: true
        onTriggered: if (!probe.connected) probe.connected = true
    }

    Socket {
        id: probe
        path: Hyprland.requestSocketPath
        onConnectionStateChanged: if (connected) { write("cursorpos"); flush(); }
        onError: probe.connected = false
        parser: SplitParser {
            splitMarker: ""
            onRead: data => {
                // Hang up first: the compositor closes next, which would count as an error.
                probe.connected = false;
                root.take(String(data));
            }
        }
    }

    function take(reply: string): void {
        const parts = reply.trim().split(",");
        const px = Number(parts[0]);
        const py = Number(parts[1]);
        if (isNaN(px) || isNaN(py))
            return;
        if (px === root.x && py === root.y) {
            const still = Date.now() - root.lastMoved;
            root.interval = still > 60000 ? 1000 : still > 5000 ? 250 : 100;
            return;
        }
        root.interval = 100;
        root.x = px;
        root.y = py;
        root.lastMoved = Date.now();
        root.moves++;
    }
}
