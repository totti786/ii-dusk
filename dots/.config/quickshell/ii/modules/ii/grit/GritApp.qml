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
 * Grit's lifecycle, kept out of the window like the clock's: a keybind, an open
 * state, and a window built only while somebody is looking at it. Focus sessions
 * keep running in GritService after the window is gone.
 */
Scope {
    id: root

    readonly property var tabIds: ["today", "tasks", "focus", "stats"]

    function requestOpen(tab = ""): void {
        GlobalStates.openGritApp(root.tabIds.includes(tab) ? tab : "");
    }

    function requestClose(): void {
        GlobalStates.gritAppOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.gritAppOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    RetainedLoader {
        id: windowLoader
        requested: GlobalStates.gritAppOpen
        // A closed Grit stays warm for a quick reopen, then goes entirely.
        retainFor: 30000
        sourceComponent: GritAppWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "gritToggle"
        description: "Toggles Grit, the habit tracker and focus timer"
        onPressed: root.requestToggle()
    }

    GlobalShortcut {
        name: "gritOpen"
        description: "Opens Grit"
        onPressed: root.requestOpen()
    }

    GlobalShortcut {
        name: "gritClose"
        description: "Closes Grit"
        onPressed: root.requestClose()
    }
}
