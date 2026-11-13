pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One Bluetooth device: what it is, whether it is connected and how much battery it has,
 * the button that does the obvious thing, and underneath (on a click) trust, the address
 * and Forget.
 */
Rectangle {
    id: root

    required property var device
    property bool expanded: false

    signal toggleExpanded()

    readonly property bool paired: root.device?.paired || root.device?.bonded
    readonly property bool connected: root.device?.connected ?? false
    readonly property bool busy: root.device?.state === BluetoothDeviceState.Connecting
        || root.device?.state === BluetoothDeviceState.Disconnecting || (root.device?.pairing ?? false)
    readonly property string title: root.device?.name || root.device?.address || ""
    readonly property string symbol: {
        const icon = root.device?.icon ?? "";
        if (icon.includes("headphones") || icon.includes("headset"))
            return "headphones";
        if (icon.includes("audio-card") || icon.includes("speaker"))
            return "speaker";
        if (icon.includes("keyboard"))
            return "keyboard";
        if (icon.includes("mouse"))
            return "mouse";
        if (icon.includes("gaming") || icon.includes("joystick"))
            return "sports_esports";
        if (icon.includes("phone"))
            return "smartphone";
        if (icon.includes("computer") || icon.includes("laptop"))
            return "computer";
        if (icon.includes("watch"))
            return "watch";
        if (icon.includes("printer"))
            return "print";
        return "bluetooth";
    }
    readonly property string status: {
        if (root.device?.pairing)
            return Translation.tr("Pairing…");
        if (root.device?.state === BluetoothDeviceState.Connecting)
            return Translation.tr("Connecting…");
        if (root.device?.state === BluetoothDeviceState.Disconnecting)
            return Translation.tr("Disconnecting…");
        if (root.connected)
            return Translation.tr("Connected");
        return root.paired ? Translation.tr("Paired") : Translation.tr("Not paired");
    }

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + ClockStyle.gap * 2
    radius: ClockStyle.radiusLarge
    color: root.connected ? ClockStyle.colActiveCard : ClockStyle.colSurfaceHigh

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }
    Behavior on implicitHeight {
        enabled: !ClockStyle.reducedMotion
        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: ClockStyle.gap
        spacing: ClockStyle.gap

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gap

            Rectangle {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                radius: root.connected ? ClockStyle.radiusNormal : ClockStyle.radiusFull
                color: root.connected ? ClockStyle.colPrimary : ClockStyle.colSurfaceHigh
                Behavior on radius { NumberAnimation { duration: Appearance.dur(180) } }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.symbol
                    fill: root.connected ? 1 : 0
                    iconSize: 26
                    color: root.connected ? ClockStyle.colOnPrimary : ClockStyle.colOnSurfaceVariant
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    color: root.connected ? ClockStyle.colOnActiveCard : ClockStyle.colOnBackground
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.status
                    color: root.connected ? ClockStyle.colOnActiveCard : ClockStyle.colSubtext
                    opacity: 0.85
                    font.pixelSize: ClockStyle.textSmall
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                visible: root.device?.batteryAvailable ?? false
                spacing: 2
                MaterialSymbol {
                    text: (root.device?.battery ?? 0) < 0.2 ? "battery_alert" : "battery_full"
                    iconSize: 18
                    color: (root.device?.battery ?? 1) < 0.2 ? ClockStyle.colError
                        : root.connected ? ClockStyle.colOnActiveCard : ClockStyle.colSubtext
                }
                StyledText {
                    text: `${Math.round((root.device?.battery ?? 0) * 100)}%`
                    color: root.connected ? ClockStyle.colOnActiveCard : ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                    font.family: ClockStyle.fontNumbers
                }
            }

            ClockButton {
                variant: root.connected ? "tonal" : "filled"
                symbol: root.busy ? "hourglass_top" : root.connected ? "link_off" : root.paired ? "link" : "add_link"
                label: root.connected ? Translation.tr("Disconnect") : root.paired ? Translation.tr("Connect") : Translation.tr("Pair")
                enabled: !root.busy
                onClicked: {
                    if (root.connected)
                        root.device.disconnect();
                    else if (root.paired)
                        root.device.connect();
                    else
                        root.device.pair();
                }
            }

            ClockIconButton {
                symbol: root.expanded ? "expand_less" : "expand_more"
                tooltip: root.expanded ? Translation.tr("Fewer details") : Translation.tr("Details")
                onClicked: root.toggleExpanded()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.expanded
            spacing: ClockStyle.gapSmall

            StyledText {
                text: root.device?.address ?? ""
                color: root.connected ? ClockStyle.colOnActiveCard : ClockStyle.colSubtext
                font.family: Appearance.font.family.monospace
                font.pixelSize: ClockStyle.textSmall
            }

            ClockFormToggle {
                visible: root.paired
                symbol: "verified_user"
                label: Translation.tr("Trusted")
                description: Translation.tr("Reconnects by itself when it comes into range")
                checked: root.device?.trusted ?? false
                onToggled: value => root.device.trusted = value
            }

            RowLayout {
                spacing: ClockStyle.gapSmall
                ClockButton {
                    visible: root.paired
                    variant: "tonal"
                    danger: true
                    symbol: "delete"
                    label: Translation.tr("Forget this device")
                    onClicked: {
                        root.toggleExpanded();
                        root.device.forget();
                    }
                }
                ClockButton {
                    visible: root.device?.pairing ?? false
                    variant: "text"
                    label: Translation.tr("Cancel pairing")
                    onClicked: root.device.cancelPair()
                }
            }
        }
    }
}
