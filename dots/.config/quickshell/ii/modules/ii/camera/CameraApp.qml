pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs

/**
 * The Camera app: the keybind, the IPC target and the window, built only while open so
 * the webcam (and its light) is off whenever the window is closed.
 */
Scope {
    id: root

    function requestToggle(): void {
        GlobalStates.cameraOpen = !GlobalStates.cameraOpen;
    }

    Loader {
        active: GlobalStates.cameraOpen
        sourceComponent: CameraWindow {
            onCloseRequested: GlobalStates.cameraOpen = false
        }
    }

    GlobalShortcut {
        name: "cameraToggle"
        description: "Toggles the Camera"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "camera"

        function open(): void {
            GlobalStates.openCameraApp();
        }

        function close(): void {
            GlobalStates.cameraOpen = false;
        }

        function toggle(): void {
            root.requestToggle();
        }

        function isOpen(): bool {
            return GlobalStates.cameraOpen;
        }
    }
}
