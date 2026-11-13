pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.modules.common

/// The Quran reader as an ordinary floating window (see hyprland/rules.lua).
FloatingWindow {
    id: root

    signal closeRequested()
    signal overlayRequested()
    required property var player

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii Quran"
    implicitWidth: Math.round(Math.min(Math.max(1200, root.screenWidth * 0.72), root.screenWidth * 0.94))
    implicitHeight: Math.round(Math.min(Math.max(760, root.screenHeight * 0.88), root.screenHeight * 0.94))
    minimumSize: Qt.size(760, 520)

    color: Appearance.colors.colLayer0
    visible: GlobalStates.quranOpen && GlobalStates.quranWindowed && !GlobalStates.screenLocked

    property bool wasVisible: false

    onVisibleChanged: {
        if (root.visible) {
            root.wasVisible = true;
        } else if (root.wasVisible && !GlobalStates.screenLocked && GlobalStates.quranWindowed && GlobalStates.quranOpen) {
            GlobalStates.quranOpen = false;
        }
    }

    QuranReader {
        player: root.player
        anchors { fill: parent; leftMargin: 16; rightMargin: 16; topMargin: 8; bottomMargin: 4 }
        focus: true
        windowed: true
        onCloseRequested: root.closeRequested()
        onOverlayRequested: root.overlayRequested()
    }
}
