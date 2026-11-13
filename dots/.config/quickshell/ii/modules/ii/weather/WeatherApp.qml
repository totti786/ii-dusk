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
 * The weather app's lifecycle and its ways in.
 *
 * Only this Scope lives with the shell — a keybind and an IPC target. The window is
 * built on demand and retained for a quick reopen, then collected with its page tree.
 * The multi-provider service is separate from the bar's Weather singleton.
 */
Scope {
    id: root

    readonly property var tabIds: ["overview", "hourly", "daily", "details", "settings"]

    function requestOpen(tab = ""): void {
        GlobalStates.openWeatherApp(root.tabIds.includes(tab) ? tab : "");
    }

    function requestClose(): void {
        GlobalStates.weatherAppOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.weatherAppOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    RetainedLoader {
        id: windowLoader
        requested: GlobalStates.weatherAppOpen
        retainFor: 30000
        sourceComponent: WeatherAppWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "weatherToggle"
        description: "Toggles the weather app"
        onPressed: root.requestToggle()
    }

    GlobalShortcut {
        name: "weatherOpen"
        description: "Opens the weather app"
        onPressed: root.requestOpen()
    }

    GlobalShortcut {
        name: "weatherClose"
        description: "Closes the weather app"
        onPressed: root.requestClose()
    }

    IpcHandler {
        target: "weather"

        function open(): void {
            root.requestOpen();
        }

        function close(): void {
            root.requestClose();
        }

        function toggle(): void {
            root.requestToggle();
        }

        /// overview | hourly | daily | details | settings
        function openTab(tab: string): void {
            root.requestOpen(String(tab ?? ""));
        }
    }
}
