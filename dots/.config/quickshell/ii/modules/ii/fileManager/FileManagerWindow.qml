pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

import qs
import qs.modules.ii.clock.components

FloatingWindow {
    id: root

    signal closeRequested()
    signal newWindowRequested(string path)

    /// A window opened from another one ("Open in new window"): its own folder, its own life
    property bool standalone: false
    property string startPath: ""

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii File Manager"
    implicitWidth: Math.round(Math.min(Math.max(1000, root.screenWidth * 0.66), root.screenWidth * 0.95))
    implicitHeight: Math.round(Math.min(Math.max(640, root.screenHeight * 0.8), root.screenHeight * 0.95))
    minimumSize: Qt.size(720, 520)

    color: ClockStyle.colBackground
    visible: (root.standalone || GlobalStates.fileManagerOpen) && !GlobalStates.screenLocked

    property bool wasVisible: false

    // Tiled from the first frame by the `tile = true` rule in hypr/custom/rules.lua

    onVisibleChanged: {
        if (root.visible) {
            root.wasVisible = true;
        } else if (root.wasVisible && !GlobalStates.screenLocked && root.standalone) {
            root.closeRequested();
        } else if (root.wasVisible && !GlobalStates.screenLocked && GlobalStates.fileManagerOpen) {
            GlobalStates.fileManagerOpen = false;
        }
    }

    // F3 puts a second pane beside the first; each pane has its own folder, tabs and helper
    property bool split: false

    function toggleSplit(): void {
        root.split = !root.split;
        if (!root.split)
            left.forceActiveFocus();
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        FileManagerContent {
            id: left
            Layout.fillWidth: true
            Layout.fillHeight: true
            split: root.split
            peer: paneLoader.item
            standalone: root.standalone
            initialPath: root.startPath
            onCloseRequested: root.closeRequested()
            onSplitToggleRequested: root.toggleSplit()
            onNewWindowRequested: p => root.newWindowRequested(p)
        }

        Loader {
            id: paneLoader
            active: root.split
            visible: active
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: FileManagerContent {
                secondary: true
                standalone: root.standalone
                split: true
                peer: left
                initialPath: left.path
                onCloseRequested: root.toggleSplit()
                onSplitToggleRequested: root.toggleSplit()
                onNewWindowRequested: p => root.newWindowRequested(p)
                Component.onCompleted: forceActiveFocus()
            }
        }
    }
}
