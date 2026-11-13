pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/** YouTube as an ordinary floating window. */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii YouTube"
    implicitWidth: Math.round(Math.min(Math.max(1080, root.screenWidth * 0.8), root.screenWidth * 0.95))
    implicitHeight: Math.round(Math.min(Math.max(720, root.screenHeight * 0.82), root.screenHeight * 0.94))
    minimumSize: Qt.size(760, 520)

    color: ClockStyle.colBackground
    visible: GlobalStates.youtubeOpen && !GlobalStates.screenLocked

    property bool wasVisible: false

    onVisibleChanged: {
        if (root.visible) {
            root.wasVisible = true;
        } else if (root.wasVisible) {
            if (!GlobalStates.screenLocked && GlobalStates.youtubeOpen)
                GlobalStates.youtubeOpen = false;
        }
    }

    Component.onDestruction: YouTubeService.clear()

    YouTubeContent {
        anchors.fill: parent
        onCloseRequested: root.closeRequested()
    }
}
