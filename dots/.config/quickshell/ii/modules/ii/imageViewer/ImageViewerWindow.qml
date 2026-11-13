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

    title: "ii Image Viewer"
    implicitWidth: Math.round(Math.min(Math.max(900, root.screenWidth * 0.6), root.screenWidth * 0.95))
    implicitHeight: Math.round(Math.min(Math.max(640, root.screenHeight * 0.75), root.screenHeight * 0.95))
    minimumSize: Qt.size(480, 360)

    color: ClockStyle.colBackground
    visible: GlobalStates.imageViewerOpen && !GlobalStates.screenLocked

    property bool wasVisible: false

    onVisibleChanged: {
        if (root.visible) {
            root.wasVisible = true;
        } else if (root.wasVisible && !GlobalStates.screenLocked && GlobalStates.imageViewerOpen) {
            GlobalStates.imageViewerOpen = false;
        }
    }

    ImageViewerContent {
        anchors.fill: parent
        onCloseRequested: root.closeRequested()
    }
}
