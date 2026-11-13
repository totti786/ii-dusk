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
import qs.modules.common.models.quickToggles

/**
 * The Lite family's quick settings: volume and brightness sliders, eight toggles and a
 * battery line, in one small panel under the bar. It opens on the right-sidebar key
 * (Super+N), which the shell already routes to `GlobalStates.dashboardPanelOpen`, and from the
 * bar's status button. The toggles are the shell's own models, so each does exactly what its
 * tile in the full sidebar does. The window exists only while it is open.
 */
Scope {
    id: root

    readonly property bool open: GlobalStates.dashboardPanelOpen

    // One drop-down at a time
    onOpenChanged: if (open) GlobalStates.liteNotificationsOpen = false

    function close(): void {
        GlobalStates.dashboardPanelOpen = false;
    }

    LazyLoader {
        active: root.open

        PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "quickshell:sidebarRight"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            readonly property var monitor: Brightness.getTargetMonitor()

            /// "main", "wifi", "bluetooth" or "battery". The pages exist only while shown. The
            /// panel can be opened straight onto one (the bar's battery button), once.
            property string page: "main"
            function takeRequestedPage(): void {
                if (GlobalStates.liteQuickSettingsPage === "main")
                    return;
                win.page = GlobalStates.liteQuickSettingsPage;
                GlobalStates.liteQuickSettingsPage = "main";
            }
            Component.onCompleted: win.takeRequestedPage()
            Connections {
                target: GlobalStates
                function onLiteQuickSettingsPageChanged() { win.takeRequestedPage(); }
            }

            // A click anywhere else closes the panel
            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }

            NetworkToggle { id: tNetwork }
            BluetoothToggle { id: tBluetooth }
            NotificationToggle { id: tNotify }
            DarkModeToggle { id: tDark }
            NightLightToggle { id: tNight }
            IdleInhibitorToggle { id: tAwake }
            MicToggle { id: tMic }
            PowerSavingToggle { id: tSaver }

            FocusScope {
                id: panel
                focus: true
                x: parent.width - width - 10
                y: 56
                width: Math.min(380, parent.width - 20)
                height: (win.page === "main" ? content.implicitHeight : pageLoader.implicitHeight) + 32

                Keys.onEscapePressed: root.close()

                Rectangle {
                    anchors.fill: parent
                    radius: 22
                    color: Appearance.colors.colLayer0Base
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                }
                MouseArea { anchors.fill: parent }  // swallow clicks

                Loader {
                    id: pageLoader
                    anchors.fill: parent
                    anchors.margins: 16
                    active: win.page !== "main"
                    sourceComponent: win.page === "wifi" ? wifiPage : win.page === "battery" ? batteryPage : btPage
                    readonly property real implicitHeight: item ? item.implicitHeight : 0
                }
                Component {
                    id: wifiPage
                    LiteWifiPage { onBack: win.page = "main" }
                }
                Component {
                    id: batteryPage
                    LiteBatteryPage { onBack: win.page = "main" }
                }
                Component {
                    id: btPage
                    LiteBluetoothPage { onBack: win.page = "main" }
                }

                ColumnLayout {
                    id: content
                    visible: win.page === "main"
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // ── header: battery (opens the battery page) and the three system buttons ──
                    RowLayout {
                        id: headerRow
                        Layout.fillWidth: true
                        spacing: 10
                        Item {
                            id: batteryGroup
                            visible: Battery.available
                            implicitWidth: batteryRow.implicitWidth
                            implicitHeight: batteryRow.implicitHeight
                            RowLayout {
                                id: batteryRow
                                spacing: 10
                                MaterialSymbol {
                                    text: Battery.isCharging ? "battery_charging_full" : "battery_full"
                                    iconSize: 22
                                    color: Battery.percent <= 15 && !Battery.isPluggedIn ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
                                }
                                ColumnLayout {
                                    spacing: 0
                                    StyledText {
                                        text: Battery.percent + "%"
                                        color: Appearance.colors.colOnLayer0
                                        font.weight: Font.Medium
                                    }
                                    StyledText {
                                        text: Battery.isCharging ? Translation.tr("Charging") : Battery.isFullyCharged ? Translation.tr("Full")
                                            : Battery.isPluggedIn ? Translation.tr("Plugged in") : Translation.tr("On battery")
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }
                                }
                                MaterialSymbol {
                                    text: "chevron_right"
                                    iconSize: 18
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.page = "battery"
                            }
                        }
                        StyledText {
                            visible: !Battery.available
                            text: Translation.tr("Quick settings")
                            color: Appearance.colors.colOnLayer0
                            font.weight: Font.Medium
                        }
                        Item { Layout.fillWidth: true }
                        Repeater {
                            model: [
                                { icon: "settings", tip: "Settings", act: "settings" },
                                { icon: "lock", tip: "Lock", act: "lock" },
                                { icon: "power_settings_new", tip: "Power", act: "power" }
                            ]
                            delegate: Rectangle {
                                id: sys
                                required property var modelData
                                implicitWidth: 38
                                implicitHeight: 38
                                radius: 19
                                color: sysArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: sys.modelData.icon
                                    iconSize: 20
                                    color: Appearance.colors.colOnLayer0
                                }
                                MouseArea {
                                    id: sysArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.close();
                                        if (sys.modelData.act === "settings")
                                            GlobalStates.openSettings();
                                        else if (sys.modelData.act === "lock")
                                            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "lock", "activate"]);
                                        else
                                            GlobalStates.sessionOpen = true;
                                    }
                                }
                            }
                        }
                    }

                    // ── sliders ──
                    LiteSlider {
                        Layout.fillWidth: true
                        icon: Audio.muted ? "volume_off" : Audio.value < 0.4 ? "volume_down" : "volume_up"
                        value: Audio.value
                        dimmed: Audio.muted
                        onMoved: v => { if (Audio.sink?.audio) Audio.sink.audio.volume = v; }
                        onIconClicked: Audio.toggleMute()
                    }
                    LiteSlider {
                        Layout.fillWidth: true
                        visible: win.monitor !== null && win.monitor !== undefined
                        icon: "brightness_6"
                        value: win.monitor?.brightness ?? 0
                        onMoved: v => win.monitor?.setBrightness(v)
                    }

                    // ── toggles ──
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 8
                        rowSpacing: 8

                        Repeater {
                            model: [tNetwork, tBluetooth, tNotify, tDark, tNight, tAwake, tMic, tSaver].filter(t => t.available)
                            delegate: Rectangle {
                                id: tile
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                implicitHeight: 58
                                radius: 18
                                color: modelData.toggled ? Appearance.colors.colPrimaryContainer
                                    : tileArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                                Behavior on color { enabled: !Appearance.reducedMotion; ColorAnimation { duration: Appearance.dur(120) } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: tile.subPage !== "" ? 34 : 12
                                    spacing: 10
                                    MaterialSymbol {
                                        text: tile.modelData.icon
                                        iconSize: 24
                                        fill: tile.modelData.toggled ? 1 : 0
                                        color: tile.modelData.toggled ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: tile.modelData.name
                                            color: tile.modelData.toggled ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer0
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: Font.Medium
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            visible: tile.modelData.hasStatusText && text !== ""
                                            text: tile.modelData.statusText
                                            color: tile.modelData.toggled ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                                            opacity: 0.8
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                                readonly property string subPage: modelData === tNetwork ? "wifi" : modelData === tBluetooth ? "bluetooth" : modelData === tNotify ? "notifications" : ""

                                // Wi-Fi and Bluetooth have a page here; notifications live in the bar's shade
                                function openSub(): void {
                                    if (tile.subPage === "notifications") {
                                        root.close();
                                        GlobalStates.liteNotificationsOpen = true;
                                    } else {
                                        win.page = tile.subPage;
                                    }
                                }

                                // Chevron: opens the Wi-Fi, Bluetooth or notifications view
                                Rectangle {
                                    visible: tile.subPage !== ""
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 38
                                    radius: tile.radius
                                    color: chevArea.containsMouse ? Qt.rgba(0, 0, 0, 0.12) : "transparent"
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "chevron_right"
                                        iconSize: 22
                                        color: tile.modelData.toggled ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                                    }
                                    MouseArea {
                                        id: chevArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: tile.openSub()
                                    }
                                    z: 2
                                }

                                MouseArea {
                                    id: tileArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.RightButton && tile.subPage !== "")
                                            tile.openSub();
                                        else if (mouse.button === Qt.RightButton && tile.modelData.altAction)
                                            tile.modelData.altAction();
                                        else
                                            tile.modelData.mainAction();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
