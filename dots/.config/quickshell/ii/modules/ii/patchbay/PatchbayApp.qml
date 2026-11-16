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
 * The Patchbay in the shell: the keybind, the IPC target and the app window, a native
 * stand-in for qpwgraph. Same shape as the Downloads app: the window is built when the
 * app opens and kept hidden for 30 s after it closes. Nothing depends on it, the links
 * live in PipeWire.
 */
Scope {
    id: root

    function requestOpen(): void {
        GlobalStates.patchbayOpen = true;
    }

    function requestClose(): void {
        GlobalStates.patchbayOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.patchbayOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    RetainedLoader {
        id: deferredWindowLoader
        requested: GlobalStates.patchbayOpen
        retainFor: 30000
        source: "PatchbayWindow.qml"

        Connections {
            target: deferredWindowLoader.item
            function onCloseRequested() { root.requestClose() }
        }
    }

    GlobalShortcut {
        name: "patchbayToggle"
        description: "Toggles the Patchbay"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "patchbay"

        function toggle(): void {
            root.requestToggle();
        }

        function open(): void {
            root.requestOpen();
        }

        function close(): void {
            root.requestClose();
        }
    }
}
