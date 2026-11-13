pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/** The Books library as an ordinary floating window. */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii Books"
    implicitWidth: Math.round(Math.min(Math.max(1100, root.screenWidth * 0.8), root.screenWidth * 0.94))
    implicitHeight: Math.round(Math.min(Math.max(700, root.screenHeight * 0.84), root.screenHeight * 0.92))
    minimumSize: Qt.size(720, 520)

    color: ClockStyle.colBackground
    visible: GlobalStates.booksOpen && !GlobalStates.screenLocked

    // A window under construction reports "not visible" before it is first shown.
    property bool wasVisible: false

    onVisibleChanged: {
        if (root.visible) {
            root.wasVisible = true;
        } else if (root.wasVisible) {
            BooksService.stopCovers();
            if (!GlobalStates.screenLocked && GlobalStates.booksOpen)
                GlobalStates.booksOpen = false;
        }
    }

    Component.onDestruction: BooksService.stopCovers()

    BooksContent {
        anchors.fill: parent
        onCloseRequested: root.closeRequested()
    }
}
