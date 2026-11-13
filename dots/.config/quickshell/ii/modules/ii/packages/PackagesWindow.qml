pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/**
 * The Packages app as an ordinary floating window (see hyprland/rules.lua), at the size the
 * other apps open at.
 */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii Packages"
    implicitWidth: Math.round(Math.min(Math.max(1000, root.screenWidth * 0.72), root.screenWidth * 0.95))
    implicitHeight: Math.round(Math.min(Math.max(640, root.screenHeight * 0.8), root.screenHeight * 0.9))
    minimumSize: Qt.size(ClockStyle.windowMinWidth, ClockStyle.windowMinHeight)

    color: ClockStyle.colBackground
    visible: GlobalStates.packagesOpen && !GlobalStates.screenLocked

    onVisibleChanged: {
        if (!visible && !GlobalStates.screenLocked && GlobalStates.packagesOpen)
            GlobalStates.packagesOpen = false;
    }

    PackagesContent {
        anchors.fill: parent
        focus: true
        onCloseRequested: root.closeRequested()
    }
}
