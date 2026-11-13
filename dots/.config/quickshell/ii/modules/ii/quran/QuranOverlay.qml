pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

import qs
import qs.modules.common

/// The Quran reader as a full-screen overlay on the focused monitor.
PanelWindow {
    id: root

    signal closeRequested()
    signal windowRequested()
    required property var player

    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:quran"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Appearance.colors.colLayer0.r, Appearance.colors.colLayer0.g, Appearance.colors.colLayer0.b, 1)
    }

    QuranReader {
        player: root.player
        anchors { fill: parent; leftMargin: 16; rightMargin: 16; topMargin: 8; bottomMargin: 4 }
        onCloseRequested: root.closeRequested()
        onWindowRequested: root.windowRequested()
    }
}
