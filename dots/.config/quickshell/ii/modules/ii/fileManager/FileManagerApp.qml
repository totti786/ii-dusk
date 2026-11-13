pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs

/**
 * The file manager: the keybind, the IPC target and the window, built only while open.
 * `qs -c ii ipc call fileManager open <path>` shows a folder (or the folder holding a file).
 */
Scope {
    id: root

    function requestToggle(): void {
        GlobalStates.fileManagerOpen = !GlobalStates.fileManagerOpen;
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
        active: root.warm || GlobalStates.fileManagerOpen
        asynchronous: !GlobalStates.fileManagerOpen
        sourceComponent: FileManagerWindow {
            onCloseRequested: GlobalStates.fileManagerOpen = false
            onNewWindowRequested: p => root.openWindow(p)
        }
    }

    // Further windows ("Open in new window"), each with its own folder and helper
    property var extraWindows: []
    property int windowSerial: 0

    function openWindow(path: string): void {
        root.windowSerial++;
        root.extraWindows = root.extraWindows.concat([{ id: root.windowSerial, path: path }]);
    }

    function closeWindow(id: int): void {
        root.extraWindows = root.extraWindows.filter(w => w.id !== id);
    }

    Instantiator {
        model: root.extraWindows
        delegate: FileManagerWindow {
            required property var modelData
            standalone: true
            startPath: modelData.path
            onCloseRequested: root.closeWindow(modelData.id)
            onNewWindowRequested: p => root.openWindow(p)
        }
    }

    GlobalShortcut {
        name: "fileManagerToggle"
        description: "Toggles the File Manager"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "fileManager"

        function open(path: string): void {
            GlobalStates.openFileManagerApp(path);
        }

        function close(): void {
            GlobalStates.fileManagerOpen = false;
        }

        function toggle(): void {
            root.requestToggle();
        }

        function isOpen(): bool {
            return GlobalStates.fileManagerOpen;
        }
    }
}
