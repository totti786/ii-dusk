pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii Audio Recorder"
    implicitWidth: Math.round(Math.min(Math.max(820, root.screenWidth * 0.6), root.screenWidth * 0.9))
    implicitHeight: Math.round(Math.min(Math.max(600, root.screenHeight * 0.7), root.screenHeight * 0.9))
    minimumSize: Qt.size(640, 480)

    color: ClockStyle.colBackground
    visible: GlobalStates.audioRecorderOpen && !GlobalStates.screenLocked

    property bool wasVisible: false

    onVisibleChanged: {
        if (root.visible) {
            root.wasVisible = true;
        } else if (root.wasVisible) {
            if (!GlobalStates.screenLocked && GlobalStates.audioRecorderOpen)
                GlobalStates.audioRecorderOpen = false;
        }
    }

    AudioRecorderContent {
        anchors.fill: parent
        onCloseRequested: root.closeRequested()
    }
}
