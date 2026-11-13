pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/** The mediator as an ordinary floating window (see hyprland/rules.lua). */
FloatingWindow {
    id: root

    signal closeRequested()
    signal overlayRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii Mediator"
    implicitWidth: Math.round(Math.min(Math.max(1100, root.screenWidth * 0.8), root.screenWidth * 0.94))
    implicitHeight: Math.round(Math.min(Math.max(700, root.screenHeight * 0.84), root.screenHeight * 0.92))
    minimumSize: Qt.size(720, 520)

    color: ClockStyle.colBackground
    visible: GlobalStates.mediatorAppOpen && GlobalStates.mediatorWindowed && !GlobalStates.screenLocked

    property bool wasVisible: false

    onVisibleChanged: {
        if (root.visible) {
            root.wasVisible = true;
        } else if (root.wasVisible && !GlobalStates.screenLocked && GlobalStates.mediatorWindowed && GlobalStates.mediatorAppOpen) {
            GlobalStates.mediatorAppOpen = false;
        }
    }

    MediatorContent {
        anchors.fill: parent
        focus: true
        onCloseRequested: root.closeRequested()
        onOverlayRequested: root.overlayRequested()
    }
}
