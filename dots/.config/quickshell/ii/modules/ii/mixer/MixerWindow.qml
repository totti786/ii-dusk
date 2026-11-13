pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/**
 * The mixer as an ordinary floating window (see hyprland/rules.lua), at the size the
 * other apps open at.
 */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii Mixer"
    implicitWidth: Math.round(Math.min(Math.max(900, root.screenWidth * 0.6), root.screenWidth * 0.95))
    implicitHeight: Math.round(Math.min(Math.max(560, root.screenHeight * 0.72), root.screenHeight * 0.85))
    minimumSize: Qt.size(ClockStyle.windowMinWidth, ClockStyle.windowMinHeight)

    color: ClockStyle.colBackground
    visible: GlobalStates.mixerOpen && !GlobalStates.screenLocked

    onVisibleChanged: {
        if (!visible && !GlobalStates.screenLocked && GlobalStates.mixerOpen)
            GlobalStates.mixerOpen = false;
    }

    MixerContent {
        anchors.fill: parent
        focus: true
        onCloseRequested: root.closeRequested()
    }
}
