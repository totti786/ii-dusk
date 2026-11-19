pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs
import qs.modules.ii.clock.components

FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii Editor"
    implicitWidth: Math.round(Math.min(Math.max(900, root.screenWidth * 0.55), root.screenWidth * 0.95))
    implicitHeight: Math.round(Math.min(Math.max(600, root.screenHeight * 0.75), root.screenHeight * 0.95))
    minimumSize: Qt.size(560, 400)

    color: ClockStyle.colBackground
    visible: GlobalStates.editorOpen && !GlobalStates.screenLocked

    property bool wasVisible: false

    // Hyprland floats this kind of window; the editor is meant to tile like any other app
    Timer {
        id: tileTimer
        interval: 60
        onTriggered: Hyprland.dispatch("hl.dsp.window.float({ action = 'disable', window = 'title:^(ii Editor)$' })")
    }

    onVisibleChanged: {
        if (root.visible) {
            tileTimer.restart();
            root.wasVisible = true;
        } else if (root.wasVisible && !GlobalStates.screenLocked && GlobalStates.editorOpen) {
            GlobalStates.editorOpen = false;
        }
    }

    EditorContent {
        anchors.fill: parent
        onCloseRequested: root.closeRequested()
    }
}
