pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.modules.common

/**
 * The calculator app: its lifecycle and its ways in.
 *
 * Same shape as the clock app: the open state is GlobalStates.calculatorAppOpen, so Search's
 * shell-app list and the IPC target both end in the same flag. The window is built only while
 * it is open and destroyed on close.
 */
Scope {
    id: root

    function requestOpen(): void {
        GlobalStates.openCalculatorApp();
    }

    function requestClose(): void {
        GlobalStates.calculatorAppOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.calculatorAppOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    Loader {
        id: windowLoader
        active: GlobalStates.calculatorAppOpen
        sourceComponent: CalculatorWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "calculatorToggle"
        description: "Toggles the calculator"
        onPressed: root.requestToggle()
    }

    GlobalShortcut {
        name: "calculatorOpen"
        description: "Opens the calculator"
        onPressed: root.requestOpen()
    }

    GlobalShortcut {
        name: "calculatorClose"
        description: "Closes the calculator"
        onPressed: root.requestClose()
    }

    IpcHandler {
        target: "calculator"

        function open(): void {
            root.requestOpen();
        }

        function close(): void {
            root.requestClose();
        }

        function toggle(): void {
            root.requestToggle();
        }
    }
}
