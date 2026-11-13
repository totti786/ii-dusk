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
 * The Packages app in the shell: the keybind, the IPC target and the app window, a front
 * for pacman and yay. Same shape as the Downloads app: the window is built when the app
 * opens and kept hidden for 30 s after it closes. A running pacman task lives in
 * PackagesService, so closing the window does not stop it.
 */
Scope {
    id: root

    readonly property var tabIds: ["updates", "installed", "browse", "maintenance"]

    function requestOpen(tab = ""): void {
        GlobalStates.openPackagesApp(root.tabIds.includes(tab) ? tab : "");
    }

    function requestClose(): void {
        GlobalStates.packagesOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.packagesOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    RetainedLoader {
        requested: GlobalStates.packagesOpen
        retainFor: 30000
        sourceComponent: PackagesWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "packagesToggle"
        description: "Toggles the Packages app"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "packages"

        function toggle(): void {
            root.requestToggle();
        }

        function open(tab: string): void {
            root.requestOpen(tab);
        }

        function close(): void {
            root.requestClose();
        }
    }
}
