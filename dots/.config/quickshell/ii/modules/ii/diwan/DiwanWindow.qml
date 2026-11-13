pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.modules.common

/// The poetry reader as an ordinary floating window (see hyprland/rules.lua).
FloatingWindow {
    id: root

    signal closeRequested()
    signal overlayRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii Diwan"
    implicitWidth: Math.round(Math.min(Math.max(1000, root.screenWidth * 0.62), root.screenWidth * 0.94))
    implicitHeight: Math.round(Math.min(Math.max(700, root.screenHeight * 0.86), root.screenHeight * 0.94))
    minimumSize: Qt.size(560, 480)

    color: Appearance.colors.colLayer0
    visible: GlobalStates.diwanOpen && GlobalStates.diwanWindowed && !GlobalStates.screenLocked

    property bool wasVisible: false

    onVisibleChanged: {
        if (root.visible) {
            root.wasVisible = true;
        } else if (root.wasVisible && !GlobalStates.screenLocked && GlobalStates.diwanWindowed && GlobalStates.diwanOpen) {
            GlobalStates.diwanOpen = false;
        }
    }

    DiwanReader {
        anchors.fill: parent
        focus: true
        windowed: true
        onCloseRequested: root.closeRequested()
        onOverlayRequested: root.overlayRequested()
    }
}
