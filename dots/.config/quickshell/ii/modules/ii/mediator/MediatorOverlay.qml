pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common

/** The mediator browser as a full-screen overlay on the focused monitor. */
PanelWindow {
    id: root

    signal closeRequested()
    signal windowRequested()

    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:mediator"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Appearance.colors.colLayer0.r, Appearance.colors.colLayer0.g, Appearance.colors.colLayer0.b, 0.9)
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity {
            NumberAnimation { duration: Appearance.dur(180) }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }
    }

    // Swallows clicks on the empty parts of the browser, so only the margin around it dismisses.
    MouseArea {
        anchors { fill: parent; leftMargin: parent.width * 0.06; rightMargin: parent.width * 0.06; topMargin: 56; bottomMargin: 40 }
    }

    MediatorBrowser {
        anchors { fill: parent; leftMargin: parent.width * 0.06; rightMargin: parent.width * 0.06; topMargin: 56; bottomMargin: 40 }
        overlay: true
        onCloseRequested: root.closeRequested()
        onWindowRequested: root.windowRequested()
    }
}
