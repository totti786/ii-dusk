pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/**
 * The Anki reviewer as an ordinary floating window. Closing it releases the collection.
 */
FloatingWindow {
    id: root

    signal closeRequested()

    /// Test/development hook passed to the content.
    property string collectionOverride: ""

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii Anki"
    implicitWidth: Math.round(Math.min(Math.max(1080, root.screenWidth * 0.78), root.screenWidth * 0.94))
    implicitHeight: Math.round(Math.min(Math.max(680, root.screenHeight * 0.82), root.screenHeight * 0.92))
    minimumSize: Qt.size(900, 600)

    color: ClockStyle.colBackground
    visible: GlobalStates.ankiOpen && !GlobalStates.screenLocked

    // A window under construction reports "not visible" before it is first shown; that is not a close.
    property bool wasVisible: false

    onVisibleChanged: {
        if (root.visible) {
            root.wasVisible = true;
        } else if (root.wasVisible) {
            AnkiService.stop();
            if (!GlobalStates.screenLocked && GlobalStates.ankiOpen)
                GlobalStates.ankiOpen = false;
        }
    }

    Component.onDestruction: AnkiService.stop()

    AnkiContent {
        anchors.fill: parent
        collectionOverride: root.collectionOverride
        onCloseRequested: root.closeRequested()
    }
}
