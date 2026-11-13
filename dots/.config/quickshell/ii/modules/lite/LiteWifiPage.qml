import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Wi-Fi for the Lite quick settings: the radio switch, the networks in range, and for the
 * one you tap, connect / password / disconnect / forget. Scanning runs only while this page
 * is showing (the service's scan holder), so closing the panel stops the radio scanning.
 */
ColumnLayout {
    id: root

    signal back()

    /// The SSID whose action row is open
    property string selected: ""
    property string password: ""

    /// The network in use. `active` can lag behind the connection state, so the name is checked too.
    function isCurrent(ap: var): bool {
        return ap.active || (Network.wifiStatus !== "disabled" && Network.wifiStatus !== "disconnected" && Network.networkName !== "" && ap.ssid === Network.networkName && !Network.ethernet);
    }

    spacing: 10

    Component.onCompleted: Network.setWifiScanHolder("lite-quicksettings", true)
    Component.onDestruction: Network.setWifiScanHolder("lite-quicksettings", false)

    LitePageHeader {
        Layout.fillWidth: true
        title: Translation.tr("Wi-Fi")
        subtitle: Network.wifiConnecting ? Translation.tr("Connecting…")
            : Network.wifiStatus === "connected" || Network.wifiStatus === "limited" ? Network.networkName
            : Network.wifiEnabled ? (Network.wifiScanning ? Translation.tr("Scanning…") : Translation.tr("Not connected"))
            : Translation.tr("Off")
        checked: Network.wifiEnabled
        onBack: root.back()
        onSwitched: Network.toggleWifi()
    }

    StyledText {
        Layout.fillWidth: true
        visible: Network.lastWifiError !== "" && Network.wifiEnabled
        text: Network.lastWifiError
        color: Appearance.m3colors.m3error
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.Wrap
    }

    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 20
        Layout.bottomMargin: 20
        visible: !Network.wifiEnabled || list.count === 0
        horizontalAlignment: Text.AlignHCenter
        color: Appearance.colors.colSubtext
        text: !Network.wifiEnabled ? Translation.tr("Wi-Fi is off")
            : Network.wifiScanning ? Translation.tr("Looking for networks…") : Translation.tr("No networks found")
    }

    ListView {
        WheelScroll {}
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 330)
        visible: Network.wifiEnabled && count > 0
        clip: true
        spacing: 6
        boundsBehavior: Flickable.StopAtBounds
        model: Network.wifiEnabled ? Network.friendlyWifiNetworks : []
        reuseItems: true

        delegate: ColumnLayout {
            id: item
            required property var modelData
            readonly property bool open: root.selected === modelData.ssid
            width: ListView.view.width
            spacing: 6

            LiteListRow {
                Layout.fillWidth: true
                icon: item.modelData.strength > 66 ? "network_wifi" : item.modelData.strength > 33 ? "network_wifi_3_bar" : "network_wifi_1_bar"
                title: item.modelData.ssid
                subtitle: root.isCurrent(item.modelData) ? Translation.tr("Connected")
                    : [item.modelData.known ? Translation.tr("Saved") : "", item.modelData.isSecure ? item.modelData.security : Translation.tr("Open"), item.modelData.bandLabel].filter(s => s !== "").join(" · ")
                trailing: item.modelData.isSecure ? "lock" : ""
                highlighted: root.isCurrent(item.modelData)
                onClicked: {
                    root.password = "";
                    if (item.open) {
                        root.selected = "";
                    } else if (!root.isCurrent(item.modelData) && (item.modelData.known || !item.modelData.isSecure)) {
                        root.selected = "";
                        Network.connectToWifiNetwork(item.modelData);
                    } else {
                        root.selected = item.modelData.ssid;
                    }
                }
            }

            // Password entry for a network that isn't saved yet
            Rectangle {
                Layout.fillWidth: true
                visible: item.open && !root.isCurrent(item.modelData) && !item.modelData.known
                implicitHeight: 44
                radius: 16
                color: Appearance.colors.colLayer1
                border.width: pass.activeFocus ? 2 : 0
                border.color: Appearance.colors.colPrimary

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    visible: pass.text === "" && !item.modelData.enterprise
                    text: Translation.tr("Password")
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    anchors.centerIn: parent
                    visible: item.modelData.enterprise
                    text: Translation.tr("Enterprise network: connect from Settings")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                TextInput {
                    id: pass
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    enabled: !item.modelData.enterprise
                    echoMode: TextInput.Password
                    color: Appearance.colors.colOnLayer0
                    selectionColor: Appearance.colors.colPrimary
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.normal
                    clip: true
                    onTextChanged: root.password = text
                    onAccepted: if (text.length > 0) {
                        Network.connectWithPassword(item.modelData.ssid, text);
                        root.selected = "";
                    }
                    onVisibleChanged: if (visible) forceActiveFocus()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                visible: item.open
                spacing: 8
                Item { Layout.fillWidth: true }
                LiteActionButton {
                    visible: !root.isCurrent(item.modelData) && !item.modelData.known && !item.modelData.enterprise
                    primary: true
                    text: Translation.tr("Connect")
                    onClicked: if (root.password.length > 0) {
                        Network.connectWithPassword(item.modelData.ssid, root.password);
                        root.selected = "";
                    }
                }
                LiteActionButton {
                    visible: root.isCurrent(item.modelData)
                    text: Translation.tr("Disconnect")
                    onClicked: { Network.disconnectWifiNetwork(); root.selected = ""; }
                }
                LiteActionButton {
                    visible: item.modelData.known || root.isCurrent(item.modelData)
                    danger: true
                    text: Translation.tr("Forget")
                    onClicked: { Network.forgetWifiNetwork(item.modelData.ssid); root.selected = ""; }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: Network.wifiEnabled
        spacing: 8
        StyledText {
            Layout.fillWidth: true
            visible: Network.ipAddress !== ""
            text: Network.ipAddress
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        Item { Layout.fillWidth: true; visible: Network.ipAddress === "" }
        LiteActionButton {
            text: Network.wifiScanning ? Translation.tr("Scanning…") : Translation.tr("Rescan")
            onClicked: Network.rescanWifi()
        }
    }
}
