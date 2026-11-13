import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Bluetooth for the Lite quick settings: the radio switch, your paired devices first and
 * whatever is nearby after them. Tap a paired device to connect or disconnect, a new one to
 * pair; Forget removes a pairing. Discovery runs only while this page is showing.
 */
ColumnLayout {
    id: root

    signal back()

    property string selected: ""

    spacing: 10

    readonly property var devices: {
        const all = Bluetooth.defaultAdapter?.devices.values ?? [];
        // Nearby devices that never sent a name are just their address: not worth a row
        return all.filter(d => d.paired || d.connected || (d.name ?? "") !== "" && d.name !== d.address.replace(/:/g, "-"))
            .sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || (a.name ?? "").localeCompare(b.name ?? ""));
    }

    Component.onCompleted: BluetoothStatus.startDiscovery()
    Component.onDestruction: BluetoothStatus.stopDiscovery()
    Connections {
        target: BluetoothStatus
        function onEnabledChanged() {
            if (BluetoothStatus.enabled)
                BluetoothStatus.startDiscovery();
        }
    }

    LitePageHeader {
        Layout.fillWidth: true
        title: Translation.tr("Bluetooth")
        subtitle: !BluetoothStatus.enabled ? Translation.tr("Off")
            : BluetoothStatus.activeDeviceCount > 0 ? Translation.tr("%1 connected").arg(BluetoothStatus.activeDeviceCount)
            : BluetoothStatus.discovering ? Translation.tr("Searching…") : Translation.tr("Not connected")
        checked: BluetoothStatus.enabled
        onBack: root.back()
        onSwitched: BluetoothStatus.toggle()
    }

    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 20
        Layout.bottomMargin: 20
        visible: !BluetoothStatus.available || !BluetoothStatus.enabled || list.count === 0
        horizontalAlignment: Text.AlignHCenter
        color: Appearance.colors.colSubtext
        text: !BluetoothStatus.available ? Translation.tr("No Bluetooth adapter")
            : BluetoothStatus.hardBlocked ? Translation.tr("Bluetooth is switched off in hardware")
            : !BluetoothStatus.enabled ? Translation.tr("Bluetooth is off")
            : BluetoothStatus.discovering ? Translation.tr("Looking for devices…") : Translation.tr("No devices found")
    }

    ListView {
        WheelScroll {}
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 330)
        visible: BluetoothStatus.enabled && count > 0
        clip: true
        spacing: 6
        boundsBehavior: Flickable.StopAtBounds
        model: BluetoothStatus.enabled ? root.devices : []

        delegate: ColumnLayout {
            id: item
            required property var modelData
            readonly property bool open: root.selected === modelData.address
            readonly property bool isPaired: modelData.paired || modelData.bonded
            width: ListView.view.width
            spacing: 6

            LiteListRow {
                Layout.fillWidth: true
                icon: Icons.getBluetoothDeviceMaterialSymbol(item.modelData.icon || "")
                title: item.modelData.name || item.modelData.address
                subtitle: item.modelData.pairing ? Translation.tr("Pairing…")
                    : item.modelData.state === BluetoothDeviceState.Connecting ? Translation.tr("Connecting…")
                    : item.modelData.connected
                        ? (item.modelData.batteryAvailable ? Translation.tr("Connected · %1%").arg(Math.round(item.modelData.battery * 100)) : Translation.tr("Connected"))
                    : item.isPaired ? Translation.tr("Paired") : Translation.tr("Available")
                trailing: item.isPaired ? "more_horiz" : "add"
                highlighted: item.modelData.connected
                onClicked: {
                    if (item.open) {
                        root.selected = "";
                    } else if (item.isPaired) {
                        root.selected = item.modelData.address;
                        if (item.modelData.connected)
                            return;
                        item.modelData.connect();
                    } else {
                        item.modelData.pair();
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                visible: item.open
                spacing: 8
                Item { Layout.fillWidth: true }
                LiteActionButton {
                    primary: !item.modelData.connected
                    text: item.modelData.connected ? Translation.tr("Disconnect") : Translation.tr("Connect")
                    onClicked: {
                        if (item.modelData.connected)
                            item.modelData.disconnect();
                        else
                            item.modelData.connect();
                        root.selected = "";
                    }
                }
                LiteActionButton {
                    danger: true
                    text: Translation.tr("Forget")
                    onClicked: { item.modelData.forget(); root.selected = ""; }
                }
            }
        }
    }
}
