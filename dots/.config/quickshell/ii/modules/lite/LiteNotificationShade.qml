pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The Lite family's notification shade: the notification history dropped from the date and
 * clock in the middle of the bar. The window exists only while it is open, and a click
 * outside it or Esc closes it.
 */
Scope {
    id: root

    function close(): void {
        GlobalStates.liteNotificationsOpen = false;
    }

    LazyLoader {
        active: GlobalStates.liteNotificationsOpen

        PanelWindow {
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "quickshell:lite-notifications"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }

            FocusScope {
                id: panel
                focus: true
                anchors.horizontalCenter: parent.horizontalCenter
                y: 56
                width: Math.min(400, parent.width - 20)
                height: column.implicitHeight + 32

                Keys.onEscapePressed: root.close()

                Rectangle {
                    anchors.fill: parent
                    radius: 22
                    color: Appearance.colors.colLayer0Base
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                }
                MouseArea { anchors.fill: parent }  // swallow clicks

                ColumnLayout {
                    id: column
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    LiteShadeHeader {
                        Layout.fillWidth: true
                    }
                    LiteNotificationsPage {
                        id: page
                        Layout.fillWidth: true
                        onBack: root.close()
                    }
                }
            }
        }
    }
}
