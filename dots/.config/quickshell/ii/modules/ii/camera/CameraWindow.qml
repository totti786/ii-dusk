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

    title: "ii Camera"
    implicitWidth: Math.round(Math.min(Math.max(820, root.screenWidth * 0.5), root.screenWidth * 0.9))
    implicitHeight: Math.round(Math.min(Math.max(640, root.screenHeight * 0.7), root.screenHeight * 0.9))
    minimumSize: Qt.size(520, 420)

    color: ClockStyle.colBackground
    visible: GlobalStates.cameraOpen && !GlobalStates.screenLocked

    property bool wasVisible: false

    onVisibleChanged: {
        if (root.visible) {
            root.wasVisible = true;
        } else if (root.wasVisible && !GlobalStates.screenLocked && GlobalStates.cameraOpen) {
            GlobalStates.cameraOpen = false;
        }
    }

    CameraContent {
        anchors.fill: parent
        onCloseRequested: root.closeRequested()
    }
}
