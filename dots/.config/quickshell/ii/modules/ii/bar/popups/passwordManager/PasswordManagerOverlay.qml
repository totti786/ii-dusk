import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The Passwords popup without a bar widget: `qs -c ii ipc call passwordManager
 * toggle` opens it as a centred overlay on the focused monitor, with the same
 * content the widget popup uses. When a Passwords widget is in the bar the
 * widget's own popup answers the IPC instead (GlobalStates.passwordWidgetCount),
 * so the two never show together. Built only while open.
 */
Scope {
    id: root

    readonly property bool wanted: GlobalStates.passwordWidgetCount === 0
        && GlobalStates.openBarPopups["passwords"] === true

    function close(): void {
        GlobalStates.closeBarPopup("passwords");
    }

    LazyLoader {
        active: root.wanted

        component: PanelWindow {
            id: win
            color: "transparent"
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null

            WlrLayershell.namespace: "quickshell:passwordManager"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            anchors { top: true; bottom: true; left: true; right: true }

            // Type-to-search binds bare letters on an empty workspace; they win over any surface.
            Component.onCompleted: GlobalStates.barPopupTypingOpen = true
            Component.onDestruction: GlobalStates.barPopupTypingOpen = false

            // A click outside the card dismisses it.
            MouseArea {
                anchors.fill: parent
                onPressed: root.close()
            }

            StyledRectangularShadow {
                target: card
            }
            Rectangle {
                id: card
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(parent.height * 0.18)
                width: content.implicitWidth + 28
                height: content.implicitHeight + 28
                radius: Appearance.rounding.verylarge
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                // Swallow clicks on the card so they do not reach the dismiss area.
                MouseArea { anchors.fill: parent }

                PasswordManagerPopupContent {
                    id: content
                    anchors.centerIn: parent
                    opened: true
                    onRequestClose: root.close()
                }
            }
        }
    }
}
