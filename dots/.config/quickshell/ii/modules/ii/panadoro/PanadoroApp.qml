pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Panadoro's lifecycle, kept out of the window like the clock's: a keybind, an open
 * state, and a window built only while somebody is looking at it. Focus sessions
 * keep running in PanadoroService after the window is gone.
 */
Scope {
    id: root

    readonly property var tabIds: ["today", "tasks", "focus", "stats", "ranks"]

    function requestOpen(tab = ""): void {
        GlobalStates.openPanadoroApp(root.tabIds.includes(tab) ? tab : "");
    }

    function requestClose(): void {
        GlobalStates.panadoroAppOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.panadoroAppOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    RetainedLoader {
        id: windowLoader
        requested: GlobalStates.panadoroAppOpen
        // A closed Panadoro stays warm for a quick reopen, then goes entirely.
        retainFor: 30000
        sourceComponent: PanadoroAppWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "panadoroToggle"
        description: "Toggles Panadoro, the habit tracker and focus timer"
        onPressed: root.requestToggle()
    }

    GlobalShortcut {
        name: "panadoroOpen"
        description: "Opens Panadoro"
        onPressed: root.requestOpen()
    }

    GlobalShortcut {
        name: "panadoroClose"
        description: "Closes Panadoro"
        onPressed: root.requestClose()
    }
}
