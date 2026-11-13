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
 * Monitor in the shell: the keybind, the IPC target and the app window. Same shape as the
 * Music and Downloads apps. The sampler only runs while the window is open.
 */
Scope {
    id: root

    readonly property var tabIds: ["overview", "processes", "network"]

    function requestOpen(tab = "", overlay = false): void {
        GlobalStates.openMonitorApp(root.tabIds.includes(tab) ? tab : "", overlay);
    }

    function requestClose(): void {
        GlobalStates.monitorOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.monitorOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    RetainedLoader {
        requested: GlobalStates.monitorOpen && !GlobalStates.monitorOverlay
        retainFor: 30000
        sourceComponent: MonitorWindow {
            onCloseRequested: root.requestClose()
        }
    }

    // The full-screen presentation, built only while it is open
    Loader {
        active: GlobalStates.monitorOpen && GlobalStates.monitorOverlay
        sourceComponent: MonitorOverlay {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "monitorOverlayToggle"
        description: "Toggles the system overview overlay"
        onPressed: {
            if (GlobalStates.monitorOpen)
                root.requestClose();
            else
                root.requestOpen("", true);
        }
    }

    GlobalShortcut {
        name: "monitorToggle"
        description: "Toggles the Monitor app"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "monitor"

        function toggle(): void {
            root.requestToggle();
        }

        function open(tab: string): void {
            root.requestOpen(tab);
        }

        /// Pick a process in the overview's list (-1 clears it)
        function process(pid: int): void {
            MonitorService.selectedPid = pid;
        }

        /// The full-screen overview
        function overlay(): void {
            if (GlobalStates.monitorOpen)
                root.requestClose();
            else
                root.requestOpen("", true);
        }

        function close(): void {
            root.requestClose();
        }
    }
}
