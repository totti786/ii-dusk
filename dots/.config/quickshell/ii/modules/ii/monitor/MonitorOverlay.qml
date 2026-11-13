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
import qs.modules.ii.clock.components
import "MonitorFormat.js" as Fmt

/**
 * The system overview as a full-screen overlay on the focused monitor: a large surface over a
 * dimmed screen, the overview page filling it. Esc, the close button or a click outside closes it.
 */
PanelWindow {
    id: root

    signal closeRequested()

    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:monitorOverlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    visible: !GlobalStates.screenLocked

    onVisibleChanged: if (!visible && !GlobalStates.screenLocked)
        root.closeRequested()

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity {
            enabled: !ClockStyle.reducedMotion
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }

        // A click anywhere outside the surface closes
        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }
    }

    FocusScope {
        id: surface
        anchors.centerIn: parent
        width: Math.min(root.width - 48, Math.max(900, root.width * 0.9))
        height: Math.min(root.height - 48, Math.max(640, root.height * 0.9))
        focus: true
        scale: 0.97
        opacity: 0
        Component.onCompleted: {
            scale = 1;
            opacity = 1;
            surface.forceActiveFocus();
        }
        Behavior on scale {
            enabled: !ClockStyle.reducedMotion
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        Behavior on opacity {
            enabled: !ClockStyle.reducedMotion
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }

        // Esc steps back: the search, then the picked process, then the overlay
        Keys.onEscapePressed: event => {
            if (MonitorService.procSearchOpen)
                MonitorService.procSearchOpen = false;
            else if (MonitorService.selectedPid > 0)
                MonitorService.selectedPid = -1;
            else if (MonitorService.expandedCard !== "")
                MonitorService.expandedCard = "";
            else
                root.closeRequested();
            event.accepted = true;
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
                MonitorService.keyboardNav = true;
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
                MonitorService.procSearchOpen = !MonitorService.procSearchOpen;
                event.accepted = true;
            } else if (event.key === Qt.Key_Slash && !(event.modifiers & Qt.ControlModifier)) {
                MonitorService.openProcSearch();
                event.accepted = true;
            } else if (event.key === Qt.Key_Space) {
                MonitorService.paused = !MonitorService.paused;
                event.accepted = true;
            }
        }

        // Swallows clicks so the surface itself does not close the overlay
        MouseArea { anchors.fill: parent }

        Rectangle {
            anchors.fill: parent
            radius: ClockStyle.radiusExtraLarge
            color: ClockStyle.colBackground
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            anchors.topMargin: 12
            spacing: 16

            ClockTopBar {
                Layout.fillWidth: true
                title: Translation.tr("System")
                subtitle: MonitorService.paused ? Translation.tr("Paused  ·  press Space to resume")
                    : MonitorService.live ? `${MonitorService.host}  ·  ${MonitorService.kernel}  ·  ${Translation.tr("up %1").arg(Fmt.duration(MonitorService.uptime))}`
                    : Translation.tr("Starting…")
                onCloseRequested: root.closeRequested()
            }

            OverviewPage {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacious: true
                onOpenTab: tabId => {
                    GlobalStates.openMonitorApp(tabId, false);
                }
            }
        }

        BatteryChip {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 24
            anchors.rightMargin: 84
        }

        StyledText {
            visible: !MonitorService.live && !MonitorService.paused
            anchors.centerIn: parent
            text: Translation.tr("Reading the system…")
            color: ClockStyle.colSubtext
        }
    }
}
