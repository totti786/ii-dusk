pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs

/**
 * The image viewer: the keybind, the IPC target and the window, built only while open.
 * `qs -c ii ipc call imageViewer open <path>` opens a file (and the folder around it).
 */
Scope {
    id: root

    function requestToggle(): void {
        GlobalStates.imageViewerOpen = !GlobalStates.imageViewerOpen;
    }

    // Built a few seconds after the shell starts and kept (hidden while closed): compiling
    // the window and its content on the first double-click was most of the wait
    property bool warm: false
    Timer {
        interval: 4000
        running: true
        onTriggered: root.warm = true
    }

    Loader {
        active: root.warm || GlobalStates.imageViewerOpen
        asynchronous: !GlobalStates.imageViewerOpen
        sourceComponent: ImageViewerWindow {
            onCloseRequested: GlobalStates.imageViewerOpen = false
        }
    }

    GlobalShortcut {
        name: "imageViewerToggle"
        description: "Toggles the Image Viewer"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "imageViewer"

        function open(path: string): void {
            GlobalStates.openImageViewerApp(path);
        }

        function close(): void {
            GlobalStates.imageViewerOpen = false;
        }

        function toggle(): void {
            root.requestToggle();
        }

        function isOpen(): bool {
            return GlobalStates.imageViewerOpen;
        }
    }
}
