pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/**
 * The Bluetooth manager as an ordinary floating window (see hyprland/rules.lua), at the size the
 * other apps open at.
 */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii Bluetooth"
    implicitWidth: Math.round(Math.min(Math.max(900, root.screenWidth * 0.55), root.screenWidth * 0.95))
    implicitHeight: Math.round(Math.min(Math.max(560, root.screenHeight * 0.72), root.screenHeight * 0.85))
    minimumSize: Qt.size(ClockStyle.windowMinWidth, ClockStyle.windowMinHeight)

    color: ClockStyle.colBackground
    visible: GlobalStates.bluetoothManagerOpen && !GlobalStates.screenLocked

    onVisibleChanged: {
        if (!visible && !GlobalStates.screenLocked && GlobalStates.bluetoothManagerOpen)
            GlobalStates.bluetoothManagerOpen = false;
    }

    BluetoothManagerContent {
        anchors.fill: parent
        focus: true
        onCloseRequested: root.closeRequested()
    }
}
