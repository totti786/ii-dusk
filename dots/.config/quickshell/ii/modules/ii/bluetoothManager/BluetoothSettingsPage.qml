pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** How this computer shows itself to other devices. */
Rectangle {
    id: root

    property bool compact: false
    property real layoutWidth: root.width

    readonly property var adapter: BluetoothStatus.adapter
    readonly property real padding: 0
    readonly property real contentWidth: root.width

    color: "transparent"

    Flickable {
        WheelScroll {}
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + root.padding * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            x: Math.max(root.padding, (flick.width - root.contentWidth) / 2)
            y: root.padding
            width: root.contentWidth
            spacing: ClockStyle.gapSmall

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: identity.implicitHeight + ClockStyle.gapLarge * 2
                radius: ClockStyle.radiusExtraLarge
                color: ClockStyle.colPane
                ColumnLayout {
                    id: identity
                    anchors.fill: parent
                    anchors.margins: ClockStyle.gapLarge
                    spacing: 2
                    StyledText {
                        text: BluetoothStatus.adapterName || Translation.tr("No adapter")
                        color: ClockStyle.colOnBackground
                        font.pixelSize: ClockStyle.textLarge
                        font.weight: Font.DemiBold
                    }
                    StyledText {
                        visible: BluetoothStatus.adapterAddress !== ""
                        text: BluetoothStatus.adapterAddress
                        color: ClockStyle.colSubtext
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: ClockStyle.textSmall
                    }
                    StyledText {
                        text: Translation.tr("The name other devices see when they look for this computer")
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                    }
                }
            }

            ClockFormToggle {
                symbol: "visibility"
                label: Translation.tr("Visible to other devices")
                description: Translation.tr("Lets a phone or a laptop find this computer. Turns itself off after a while.")
                checked: root.adapter?.discoverable ?? false
                enabled: BluetoothStatus.enabled
                onToggled: value => root.adapter.discoverable = value
            }
            ClockFormToggle {
                symbol: "link"
                label: Translation.tr("Accept pairing requests")
                description: Translation.tr("Lets a device that finds this computer start pairing")
                checked: root.adapter?.pairable ?? false
                enabled: BluetoothStatus.enabled
                onToggled: value => root.adapter.pairable = value
            }

            StyledText {
                Layout.topMargin: ClockStyle.gap
                Layout.fillWidth: true
                text: Translation.tr("Pairing asks for a code on the screen, so keep this computer in sight while a new device connects. Devices you mark Trusted reconnect by themselves.")
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
                wrapMode: Text.WordWrap
            }
        }
    }
}
