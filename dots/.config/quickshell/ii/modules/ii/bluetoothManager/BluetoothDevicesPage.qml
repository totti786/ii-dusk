pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** The adapter's switch at the top, then your devices, then what is nearby. */
Rectangle {
    id: root

    property bool compact: false
    property real layoutWidth: root.width
    /// Scan only while the window is on show
    property bool active: true

    property string selected: ""

    readonly property real padding: 0
    readonly property real contentWidth: root.width
    readonly property var all: BluetoothStatus.adapter?.devices.values ?? []
    readonly property var connectedDevices: root.all.filter(d => d.connected)
    readonly property var pairedDevices: root.all.filter(d => !d.connected && (d.paired || d.bonded))
        .sort((a, b) => (a.name ?? "").localeCompare(b.name ?? ""))
    // A nearby device that never sent a name is only its address: not worth a card
    readonly property var nearbyDevices: root.all.filter(d => !d.connected && !d.paired && !d.bonded
        && (d.name ?? "") !== "" && d.name !== d.address.replace(/:/g, "-"))
        .sort((a, b) => (a.name ?? "").localeCompare(b.name ?? ""))

    color: "transparent"

    function toggleSelected(address: string): void {
        root.selected = root.selected === address ? "" : address;
    }

    onActiveChanged: {
        if (root.active && BluetoothStatus.enabled)
            BluetoothStatus.startDiscovery();
        else
            BluetoothStatus.stopDiscovery();
    }
    Component.onCompleted: if (root.active) BluetoothStatus.startDiscovery()
    Component.onDestruction: BluetoothStatus.stopDiscovery()

    // The adapter may not be there yet when the page opens, or may be switched on after
    Connections {
        target: BluetoothStatus
        function onEnabledChanged() {
            if (BluetoothStatus.enabled && root.active)
                BluetoothStatus.startDiscovery();
        }
        function onAdapterChanged() {
            if (BluetoothStatus.enabled && root.active)
                BluetoothStatus.startDiscovery();
        }
    }

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
            spacing: ClockStyle.paneGap

            // ── The adapter ──
            ClockHero {
                Layout.fillWidth: true
                compact: root.compact
                symbol: BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                shape: BluetoothStatus.discovering ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie9Sided
                title: !BluetoothStatus.available ? Translation.tr("No Bluetooth adapter")
                    : BluetoothStatus.hardBlocked ? Translation.tr("Switched off in hardware")
                    : !BluetoothStatus.enabled ? Translation.tr("Bluetooth is off")
                    : BluetoothStatus.activeDeviceCount > 0 ? Translation.tr("%1 connected").arg(BluetoothStatus.activeDeviceCount)
                    : Translation.tr("Bluetooth is on")
                text: BluetoothStatus.enabled ? (BluetoothStatus.discovering ? Translation.tr("Looking for devices…") : Translation.tr("Not scanning"))
                    : BluetoothStatus.adapterName
                trailing: [
                    ClockButton {
                        visible: BluetoothStatus.enabled
                        variant: "tonal"
                        symbol: BluetoothStatus.discovering ? "bluetooth_searching" : "radar"
                        label: BluetoothStatus.discovering ? Translation.tr("Stop") : Translation.tr("Scan")
                        onClicked: BluetoothStatus.discovering ? BluetoothStatus.stopDiscovery() : BluetoothStatus.startDiscovery()
                    },
                    ClockButton {
                        variant: BluetoothStatus.enabled ? "text" : "filled"
                        symbol: "power_settings_new"
                        label: BluetoothStatus.enabled ? Translation.tr("Turn off") : Translation.tr("Turn on")
                        enabled: BluetoothStatus.available && !BluetoothStatus.hardBlocked
                        onClicked: BluetoothStatus.toggle()
                    }
                ]
            }

            ClockPane {
                Layout.fillWidth: true
                visible: BluetoothStatus.enabled && root.connectedDevices.length > 0
                title: Translation.tr("Connected")
                symbol: "bluetooth_connected"
                shape: MaterialShape.Shape.Cookie9Sided
                count: root.connectedDevices.length
                Repeater {
                    model: BluetoothStatus.enabled ? root.connectedDevices : []
                    delegate: BluetoothDeviceCard {
                        required property var modelData
                        device: modelData
                        expanded: root.selected === modelData.address
                        onToggleExpanded: root.toggleSelected(modelData.address)
                    }
                }
            }

            ClockPane {
                Layout.fillWidth: true
                visible: BluetoothStatus.enabled && root.pairedDevices.length > 0
                title: Translation.tr("My devices")
                symbol: "devices"
                shape: MaterialShape.Shape.Clover4Leaf
                count: root.pairedDevices.length
                Repeater {
                    model: BluetoothStatus.enabled ? root.pairedDevices : []
                    delegate: BluetoothDeviceCard {
                        required property var modelData
                        device: modelData
                        expanded: root.selected === modelData.address
                        onToggleExpanded: root.toggleSelected(modelData.address)
                    }
                }
            }

            ClockPane {
                Layout.fillWidth: true
                visible: BluetoothStatus.enabled && root.nearbyDevices.length > 0
                title: Translation.tr("Nearby")
                symbol: "radar"
                shape: MaterialShape.Shape.SoftBurst
                count: root.nearbyDevices.length
                Repeater {
                    model: BluetoothStatus.enabled ? root.nearbyDevices : []
                    delegate: BluetoothDeviceCard {
                        required property var modelData
                        device: modelData
                        expanded: root.selected === modelData.address
                        onToggleExpanded: root.toggleSelected(modelData.address)
                    }
                }
            }

            ClockEmptyState {
                Layout.alignment: Qt.AlignHCenter
                visible: BluetoothStatus.enabled && root.all.length === 0
                symbol: BluetoothStatus.discovering ? "bluetooth_searching" : "bluetooth"
                title: BluetoothStatus.discovering ? Translation.tr("Looking for devices") : Translation.tr("No devices")
                subtitle: Translation.tr("Put a device in pairing mode and it will show up here")
            }
        }
    }
}
