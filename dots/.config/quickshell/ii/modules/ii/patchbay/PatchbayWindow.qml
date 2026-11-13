pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/**
 * The Patchbay as an ordinary floating window (see hyprland/rules.lua), at the size the
 * other apps open at.
 */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii Patchbay"
    implicitWidth: Math.round(Math.min(Math.max(1100, root.screenWidth * 0.8), root.screenWidth * 0.95))
    implicitHeight: Math.round(Math.min(Math.max(640, root.screenHeight * 0.8), root.screenHeight * 0.85))
    minimumSize: Qt.size(ClockStyle.windowMinWidth, ClockStyle.windowMinHeight)

    color: ClockStyle.colBackground
    visible: GlobalStates.patchbayOpen && !GlobalStates.screenLocked

    onVisibleChanged: {
        if (!visible && !GlobalStates.screenLocked && GlobalStates.patchbayOpen)
            GlobalStates.patchbayOpen = false;
    }

    PatchbayContent {
        anchors.fill: parent
        focus: true
        onCloseRequested: root.closeRequested()
    }
}
