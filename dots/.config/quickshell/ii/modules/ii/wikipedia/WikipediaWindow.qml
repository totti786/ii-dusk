pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/** Wikipedia as an ordinary floating window. */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii Wikipedia"
    implicitWidth: Math.round(Math.min(Math.max(1050, root.screenWidth * 0.78), root.screenWidth * 0.95))
    implicitHeight: Math.round(Math.min(Math.max(720, root.screenHeight * 0.82), root.screenHeight * 0.94))
    minimumSize: Qt.size(760, 520)

    color: ClockStyle.colBackground
    visible: GlobalStates.wikipediaOpen && !GlobalStates.screenLocked

    property bool wasVisible: false

    onVisibleChanged: {
        if (root.visible) {
            root.wasVisible = true;
        } else if (root.wasVisible) {
            if (!GlobalStates.screenLocked && GlobalStates.wikipediaOpen)
                GlobalStates.wikipediaOpen = false;
        }
    }

    Component.onDestruction: WikipediaService.clear()

    WikipediaContent {
        anchors.fill: parent
        onCloseRequested: root.closeRequested()
    }
}
