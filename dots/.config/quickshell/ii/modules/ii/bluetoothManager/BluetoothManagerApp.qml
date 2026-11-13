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
 * The Bluetooth manager in the shell: the keybind, the IPC target and the app window, a native
 * stand-in for blueman. Same shape as the Downloads app: the window is built when the
 * app opens and kept hidden for 30 s after it closes. Nothing depends on it, the devices
 * live in BlueZ.
 */
Scope {
    id: root

    readonly property var tabIds: ["devices", "settings"]

    function requestOpen(tab = ""): void {
        GlobalStates.openBluetoothManagerApp(root.tabIds.includes(tab) ? tab : "");
    }

    function requestClose(): void {
        GlobalStates.bluetoothManagerOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.bluetoothManagerOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    RetainedLoader {
        requested: GlobalStates.bluetoothManagerOpen
        retainFor: 30000
        sourceComponent: BluetoothManagerWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "bluetoothManagerToggle"
        description: "Toggles the Bluetooth manager"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "bluetoothManager"

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
