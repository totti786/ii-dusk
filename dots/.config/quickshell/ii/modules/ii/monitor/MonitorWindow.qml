pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/** Monitor as an ordinary floating window (see hyprland/rules.lua). */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii Monitor"
    implicitWidth: Math.round(Math.min(Math.max(1040, root.screenWidth * 0.66), root.screenWidth * 0.95))
    implicitHeight: Math.round(Math.min(Math.max(660, root.screenHeight * 0.8), root.screenHeight * 0.92))
    minimumSize: Qt.size(ClockStyle.windowMinWidth, ClockStyle.windowMinHeight)

    color: ClockStyle.colBackground
    // A window kept alive after closing must stay hidden while the overlay is the one open
    visible: GlobalStates.monitorOpen && !GlobalStates.monitorOverlay && !GlobalStates.screenLocked

    onVisibleChanged: {
        if (!visible && !GlobalStates.screenLocked && GlobalStates.monitorOpen && !GlobalStates.monitorOverlay)
            GlobalStates.monitorOpen = false;
    }

    MonitorContent {
        anchors.fill: parent
        focus: true
        onCloseRequested: root.closeRequested()
    }
}
