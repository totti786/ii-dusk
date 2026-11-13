pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.modules.common
import qs.modules.ii.clock.components

/** Floating shell window; closing it leaves Discordo Voice running. */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii Discordo Voice"
    implicitWidth: Math.round(Math.min(Math.max(820, root.screenWidth * 0.62), root.screenWidth * 0.88))
    implicitHeight: Math.round(Math.min(Math.max(560, root.screenHeight * 0.62), root.screenHeight * 0.84))
    minimumSize: Qt.size(680, 520)
    color: ClockStyle.colBackground
    visible: GlobalStates.discordoVoiceOpen && !GlobalStates.screenLocked

    property bool wasVisible: false

    onVisibleChanged: {
        if (root.visible) {
            root.wasVisible = true;
        } else if (root.wasVisible && GlobalStates.discordoVoiceOpen && !GlobalStates.screenLocked) {
            GlobalStates.discordoVoiceOpen = false;
        }
    }

    DiscordoVoiceContent {
        anchors.fill: parent
        onCloseRequested: root.closeRequested()
    }
}
