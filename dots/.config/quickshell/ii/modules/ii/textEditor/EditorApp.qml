pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs

/**
 * The file manager: the keybind, the IPC target and the window, built only while open.
 * `qs -c ii ipc call editor open <path>` opens a file in a tab.
 */
Scope {
    id: root

    function requestToggle(): void {
        GlobalStates.editorOpen = !GlobalStates.editorOpen;
    }

    // Built a few seconds after the shell starts and kept hidden while closed, so the
    // first open does not wait for the window to compile
    property bool warm: false
    Timer {
        interval: 3000
        running: true
        onTriggered: root.warm = true
    }

    Loader {
        active: root.warm || GlobalStates.editorOpen
        asynchronous: !GlobalStates.editorOpen
        sourceComponent: EditorWindow {
            onCloseRequested: GlobalStates.editorOpen = false
        }
    }

    GlobalShortcut {
        name: "editorToggle"
        description: "Toggles the Text Editor"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "editor"

        function open(path: string): void {
            GlobalStates.openEditorApp(path, 0);
        }

        function close(): void {
            GlobalStates.editorOpen = false;
        }

        function toggle(): void {
            root.requestToggle();
        }

        function isOpen(): bool {
            return GlobalStates.editorOpen;
        }
    }
}
