pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.modules.ii.clock.components

FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii Audio Player"
    implicitWidth: Math.round(Math.min(Math.max(980, root.screenWidth * 0.62), root.screenWidth * 0.95))
    implicitHeight: Math.round(Math.min(Math.max(660, root.screenHeight * 0.78), root.screenHeight * 0.95))
    minimumSize: Qt.size(720, 520)

    color: ClockStyle.colBackground
    visible: GlobalStates.audioPlayerOpen && !GlobalStates.screenLocked

    property bool wasVisible: false

    onVisibleChanged: {
        if (root.visible) {
            root.wasVisible = true;
        } else if (root.wasVisible && !GlobalStates.screenLocked && GlobalStates.audioPlayerOpen) {
            GlobalStates.audioPlayerOpen = false;
        }
    }

    AudioPlayerContent {
        anchors.fill: parent
        onCloseRequested: root.closeRequested()
    }
}
