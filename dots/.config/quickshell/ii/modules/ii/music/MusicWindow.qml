pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/** Music as an ordinary floating window (see hyprland/rules.lua). */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii Music"
    implicitWidth: Math.round(Math.min(Math.max(980, root.screenWidth * 0.62), root.screenWidth * 0.95))
    implicitHeight: Math.round(Math.min(Math.max(640, root.screenHeight * 0.78), root.screenHeight * 0.92))
    minimumSize: Qt.size(ClockStyle.windowMinWidth, ClockStyle.windowMinHeight)

    color: ClockStyle.colBackground
    visible: GlobalStates.musicOpen && !GlobalStates.screenLocked

    onVisibleChanged: {
        if (!visible && !GlobalStates.screenLocked && GlobalStates.musicOpen)
            GlobalStates.musicOpen = false;
    }

    MusicContent {
        anchors.fill: parent
        focus: true
        onCloseRequested: root.closeRequested()
    }
}
