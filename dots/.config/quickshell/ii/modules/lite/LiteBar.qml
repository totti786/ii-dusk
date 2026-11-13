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
 * The Lite family's bar: three floating pills over the wallpaper. Workspaces and the window
 * title on the left, the date and clock in the middle, tray, status and power on the right.
 * The status button opens the quick settings. It is plain Items and the shell's existing
 * singletons, with no widget registry, no layout engine and no animation beyond a colour
 * fade, so it costs a few megabytes where the full bar costs well over a hundred.
 */
Scope {
    id: root

    readonly property int pillHeight: 34
    readonly property int margin: 6

    // One pill: a rounded plate that sizes itself to its row
    component Pill: Rectangle {
        default property alias content: row.data
        property int padding: 12
        property alias spacing: row.spacing
        implicitWidth: row.implicitWidth + padding * 2
        implicitHeight: root.pillHeight
        radius: height / 2
        color: Appearance.colors.colLayer0Base
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 8
        }
    }

    // A round button in a pill, lightening on hover
    component PillButton: Rectangle {
        id: btn
        default property alias content: inner.data
        signal clicked()
        property bool active: false
        readonly property alias hovered: hover.containsMouse
        implicitWidth: Math.max(root.pillHeight - 8, inner.implicitWidth + 14)
        implicitHeight: root.pillHeight - 8
        radius: height / 2
        color: active ? Appearance.colors.colSecondaryContainer : hover.pressed ? Appearance.colors.colLayer2Active : hover.containsMouse ? Appearance.colors.colLayer2 : "transparent"
        Behavior on color { enabled: !Appearance.reducedMotion; ColorAnimation { duration: Appearance.dur(120) } }

        RowLayout {
            id: inner
            anchors.centerIn: parent
            spacing: 6
        }
        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
            onWheel: wheel => btn.wheel(wheel)
        }
        signal wheel(var wheel)
    }

    Variants {
        model: GlobalStates.allowedScreens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: root.pillHeight + root.margin * 2
            exclusiveZone: root.pillHeight + root.margin * 2
            color: "transparent"
            // The session lock is transparent (xray): without this the bar floats over the password field.
            visible: !GlobalStates.screenLocked
            WlrLayershell.namespace: "quickshell:bar"

            readonly property var monitor: Hyprland.monitorFor(modelData)
            readonly property int activeWorkspace: monitor?.activeWorkspace?.id ?? 1
            // Five at least, then as many as the busiest workspace in use: an empty workspace with a
            // high id (a stray scratch one) does not stretch the row.
            readonly property int shownWorkspaces: {
                let top = Math.max(5, activeWorkspace);
                for (const ws of Hyprland.workspaces.values)
                    if (ws.id > top && ws.id < 100 && ws.lastIpcObject?.windows > 0)
                        top = ws.id;
                return top;
            }

            // The corner dot of the bell: the unread count, capped
            readonly property string unreadText: Notifications.unread > 9 ? "9+" : String(Notifications.unread)

            /// Weekday, full date, ISO week and zone, for the clock's tooltip
            function dateDetail(): string {
                const now = new Date();
                const day = (now.getDay() + 6) % 7;
                const thursday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - day + 3);
                const week = 1 + Math.round(((thursday - new Date(thursday.getFullYear(), 0, 4)) / 86400000 - 3 + (new Date(thursday.getFullYear(), 0, 4).getDay() + 6) % 7) / 7);
                const zone = Qt.formatDateTime(now, "t");
                return Qt.locale().toString(now, "dddd, d MMMM yyyy") + "\n" + Translation.tr("Week %1").arg(week) + (zone ? " · " + zone : "");
            }

            function occupied(id: int): bool {
                return Hyprland.workspaces.values.some(ws => ws.id === id && ws.lastIpcObject?.windows > 0);
            }

            // ── left: workspaces and the focused window ──
            Pill {
                id: leftPill
                anchors.left: parent.left
                anchors.leftMargin: root.margin
                anchors.verticalCenter: parent.verticalCenter
                padding: 6
                spacing: 2

                // Scrolling over the dots steps through the workspaces
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => Hyprland.dispatch("hl.dsp.focus({ workspace = '" + (event.angleDelta.y < 0 ? "e+1" : "e-1") + "' })")
                }

                Repeater {
                    model: bar.shownWorkspaces
                    delegate: Item {
                        id: ws
                        required property int index
                        readonly property int wsId: index + 1
                        readonly property bool active: bar.activeWorkspace === wsId
                        readonly property bool busy: bar.occupied(wsId)
                        implicitWidth: active ? 30 : 24
                        implicitHeight: 26
                        Behavior on implicitWidth { enabled: !Appearance.reducedMotion; NumberAnimation { duration: Appearance.dur(140); easing.type: Easing.OutCubic } }

                        Rectangle {
                            anchors.centerIn: parent
                            width: ws.active ? 30 : ws.busy ? 24 : 10
                            height: ws.active || ws.busy ? 24 : 10
                            radius: height / 2
                            color: ws.active ? Appearance.colors.colPrimary
                                : ws.busy ? Appearance.colors.colSecondaryContainer
                                : wsArea.containsMouse ? Appearance.colors.colSubtext : Appearance.colors.colLayer2
                            Behavior on color { enabled: !Appearance.reducedMotion; ColorAnimation { duration: Appearance.dur(120) } }
                            Behavior on width { enabled: !Appearance.reducedMotion; NumberAnimation { duration: Appearance.dur(140); easing.type: Easing.OutCubic } }
                            Behavior on height { enabled: !Appearance.reducedMotion; NumberAnimation { duration: Appearance.dur(140); easing.type: Easing.OutCubic } }

                            StyledText {
                                anchors.centerIn: parent
                                visible: ws.active || ws.busy
                                text: ws.wsId
                                color: ws.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                            }
                        }
                        MouseArea {
                            id: wsArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = '" + ws.wsId + "' })")
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 16
                    Layout.leftMargin: 6
                    Layout.rightMargin: 4
                    color: Appearance.colors.colLayer0Border
                }
                StyledText {
                    id: titleText
                    Layout.maximumWidth: Math.max(120, bar.width * 0.22)
                    Layout.rightMargin: 8
                    text: (ToplevelManager.activeToplevel?.title ?? "") !== "" ? ToplevelManager.activeToplevel.title : Translation.tr("Desktop")
                    opacity: (ToplevelManager.activeToplevel?.title ?? "") !== "" ? 1 : 0.55
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    elide: Text.ElideRight
                }
            }

            // ── middle: date and clock, centred on the screen; opens the notification shade ──
            Pill {
                id: centerPill
                anchors.centerIn: parent
                spacing: 10
                color: GlobalStates.liteNotificationsOpen ? Appearance.colors.colSecondaryContainer
                    : centerArea.containsMouse ? Appearance.colors.colLayer1 : Appearance.colors.colLayer0Base
                Behavior on color { enabled: !Appearance.reducedMotion; ColorAnimation { duration: Appearance.dur(120) } }
                StyledText {
                    text: DateTime.dayNameShort + " " + DateTime.dayOfMonth + " " + DateTime.monthNameShort
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
                StyledText {
                    text: DateTime.time
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                }
                // Bell: a dot while there are unread notifications, a slash in do-not-disturb
                Item {
                    implicitWidth: 18
                    implicitHeight: 18
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: Notifications.effectiveSilent ? "notifications_paused" : "notifications"
                        iconSize: 18
                        color: Appearance.colors.colSubtext
                    }
                    Rectangle {
                        visible: Notifications.unread > 0 && !Notifications.effectiveSilent
                        implicitWidth: Math.max(12, badge.implicitWidth + 6)
                        implicitHeight: 12
                        radius: 6
                        anchors.left: parent.horizontalCenter
                        anchors.bottom: parent.verticalCenter
                        anchors.leftMargin: 1
                        anchors.bottomMargin: 1
                        color: Appearance.colors.colPrimary
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Base
                        StyledText {
                            id: badge
                            anchors.centerIn: parent
                            text: bar.unreadText
                            color: Appearance.colors.colOnPrimary
                            font.pixelSize: 9
                            font.weight: Font.Bold
                        }
                    }
                }
            }
            LiteTip {
                target: centerPill
                barWindow: bar
                hovered: centerArea.containsMouse
                // Built when the hover starts, so it reads the date at that moment
                text: centerArea.containsMouse ? bar.dateDetail() : ""
            }
            MouseArea {
                id: centerArea
                anchors.fill: centerPill
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    GlobalStates.dashboardPanelOpen = false;
                    GlobalStates.liteNotificationsOpen = !GlobalStates.liteNotificationsOpen;
                }
            }

            // ── right: tray, status, power ──
            Pill {
                anchors.right: parent.right
                anchors.rightMargin: root.margin
                anchors.verticalCenter: parent.verticalCenter
                padding: 6
                spacing: 6

                // Mic, camera and screen share in use: the apps behind them are in the tooltip
                Item {
                    id: privacyDot
                    visible: Privacy.active && (Config.options.lite.bar.privacy ?? true)
                    Layout.leftMargin: 6
                    implicitWidth: privacyRow.implicitWidth
                    implicitHeight: 20
                    RowLayout {
                        id: privacyRow
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: Privacy.activeKinds
                            delegate: MaterialSymbol {
                                required property string modelData
                                text: Privacy.iconFor(modelData)
                                iconSize: 16
                                fill: 1
                                color: Appearance.m3colors.m3error
                            }
                        }
                    }
                    MouseArea {
                        id: privacyArea
                        anchors.fill: parent
                        hoverEnabled: true
                    }
                    LiteTip {
                        target: privacyDot
                        barWindow: bar
                        hovered: privacyArea.containsMouse
                        text: [...new Set(Privacy.activeItems.map(i => String(i.app || "").trim() !== "" ? i.app + " · " + Privacy.iconFor(i.kind).replace("_", " ") : Privacy.iconFor(i.kind).replace("_", " ")))].join("\n")
                    }
                }

                // Keyboard layout, when there is more than one: a click goes to the next
                PillButton {
                    id: layoutButton
                    visible: (Config.options.lite.bar.keyboardLayout ?? true) && HyprlandXkb.layoutCodes.length > 1
                    onClicked: Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"])
                    StyledText {
                        text: (HyprlandXkb.currentLayoutCode || "").toUpperCase()
                        color: Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                    }
                    LiteTip {
                        target: layoutButton
                        barWindow: bar
                        hovered: layoutButton.hovered
                        text: HyprlandXkb.descriptionFor(HyprlandXkb.activeLayoutIndex)
                    }
                }

                LiteTray {
                    Layout.leftMargin: 6
                    Layout.rightMargin: 4
                    barWindow: bar
                }

                PillButton {
                    active: GlobalStates.dashboardPanelOpen
                    onClicked: GlobalStates.dashboardPanelOpen = !GlobalStates.dashboardPanelOpen
                    onWheel: wheel => wheel.angleDelta.y > 0 ? Audio.incrementVolume() : Audio.decrementVolume()

                    MaterialSymbol {
                        text: Network.ethernet ? "lan" : Network.wifi ? "wifi" : "wifi_off"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer0
                    }
                    MaterialSymbol {
                        visible: BluetoothStatus.enabled
                        text: BluetoothStatus.connected ? "bluetooth_connected" : "bluetooth"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer0
                    }
                    MaterialSymbol {
                        text: Audio.muted ? "volume_off" : Audio.value < 0.4 ? "volume_down" : "volume_up"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer0
                    }
                }

                // The battery has its own button: it opens the quick settings on the battery page
                PillButton {
                    id: batteryButton
                    visible: Battery.available
                    onClicked: {
                        GlobalStates.liteNotificationsOpen = false;
                        GlobalStates.liteQuickSettingsPage = "battery";
                        GlobalStates.dashboardPanelOpen = true;
                    }
                    MaterialSymbol {
                        text: Battery.isCharging ? "battery_charging_full" : GlobalStates.liteAutoSaverActive ? "battery_saver"
                            : Battery.percent <= 20 ? "battery_alert" : "battery_full"
                        iconSize: 18
                        color: Battery.percent <= 15 && !Battery.isPluggedIn ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        text: Battery.percent
                        color: Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                    }
                    LiteTip {
                        target: batteryButton
                        barWindow: bar
                        hovered: batteryButton.hovered
                        text: {
                            const left = Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty;
                            const h = Math.floor(left / 3600);
                            const m = Math.round(left % 3600 / 60);
                            const time = left > 0 ? (h > 0 ? h + " h " + m + " min" : m + " min") : "";
                            const state = Battery.isCharging ? Translation.tr("Charging") : Battery.isFullyCharged ? Translation.tr("Full")
                                : Battery.isPluggedIn ? Translation.tr("Plugged in") : Translation.tr("On battery");
                            return Battery.percent + "% · " + state + (time !== "" ? "\n" + time + (Battery.isCharging ? " " + Translation.tr("to full") : " " + Translation.tr("left")) : "")
                                + (GlobalStates.liteAutoSaverActive ? "\n" + Translation.tr("Power saver on") : "");
                        }
                    }
                }

                PillButton {
                    onClicked: GlobalStates.sessionOpen = true
                    MaterialSymbol {
                        text: "power_settings_new"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }
        }
    }
}
