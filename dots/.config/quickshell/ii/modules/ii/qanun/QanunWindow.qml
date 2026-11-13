pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/**
 * The Qanun window: a regular floating toplevel like the clock and Grit, large
 * enough for the landscape tuner and metronome layouts.
 */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii Qanun"
    implicitWidth: Math.round(Math.min(Math.max(1080, root.screenWidth * 0.86), root.screenWidth * 0.96))
    implicitHeight: Math.round(Math.min(Math.max(700, root.screenHeight * 0.78), root.screenHeight * 0.92))
    minimumSize: Qt.size(760, 600)

    color: ClockStyle.colBackground
    visible: GlobalStates.qanunOpen && !GlobalStates.screenLocked

    onVisibleChanged: {
        if (!visible) {
            QanunStore.stopAllAudio();
            if (!GlobalStates.screenLocked && GlobalStates.qanunOpen)
                GlobalStates.qanunOpen = false;
        }
    }

    QanunContent {
        anchors.fill: parent
        focus: true
        onCloseRequested: root.closeRequested()
    }
}
