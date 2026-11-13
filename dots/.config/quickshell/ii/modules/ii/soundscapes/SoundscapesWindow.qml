pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/**
 * The Soundscapes app as an ordinary floating window: an xdg toplevel the compositor
 * floats and centres (see hyprland/rules.lua).
 */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii Soundscapes"
    implicitWidth: Math.round(Math.min(1320, Math.max(920, root.screenWidth * 0.74)))
    implicitHeight: Math.round(Math.min(900, Math.max(620, root.screenHeight * 0.82)))
    minimumSize: Qt.size(ClockStyle.windowMinWidth, ClockStyle.windowMinHeight)

    color: ClockStyle.colBackground
    visible: GlobalStates.soundscapesOpen && !GlobalStates.screenLocked

    onVisibleChanged: {
        if (!visible && !GlobalStates.screenLocked && GlobalStates.soundscapesOpen)
            GlobalStates.soundscapesOpen = false;
    }

    SoundscapesContent {
        anchors.fill: parent
        focus: true
        onCloseRequested: root.closeRequested()
    }
}
