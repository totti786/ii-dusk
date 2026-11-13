pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The Bluetooth manager inside its window, built from the clock app's parts so it reads as
 * one of the family: top bar, rail on the left and the page.
 */
FocusScope {
    id: root

    signal closeRequested()

    readonly property bool compact: root.width < ClockStyle.compactMax
    readonly property bool canExpandRail: root.width >= ClockStyle.railExpandMin
    property bool railExpanded: true
    readonly property bool railOpen: root.canExpandRail && root.railExpanded
    readonly property real railWidth: root.railOpen ? ClockStyle.railExpandedWidth : ClockStyle.railCollapsedWidth
    readonly property real pageLayoutWidth: Math.max(0, root.width - ClockStyle.paneGap * 2
        - (root.compact ? 0 : root.railWidth + ClockStyle.paneGap))

    readonly property var tabs: [
        { id: "devices", icon: "bluetooth", label: Translation.tr("Devices") },
        { id: "settings", icon: "tune", label: Translation.tr("Settings") }
    ]
    readonly property var tabIds: root.tabs.map(tab => tab.id)
    readonly property var badges: ({
        devices: BluetoothStatus.activeDeviceCount > 0 ? String(BluetoothStatus.activeDeviceCount) : "",
        settings: ""
    })

    property string currentTab: "devices"
    readonly property bool shown: root.Window.window?.visible ?? true

    function selectTab(tabId: string): void {
        if (root.tabIds.includes(tabId))
            root.currentTab = tabId;
    }

    function consumePendingTab(): void {
        const pending = GlobalStates.bluetoothManagerPendingTab;
        GlobalStates.bluetoothManagerPendingTab = "";
        if (root.tabIds.includes(pending))
            root.selectTab(pending);
    }

    Component.onCompleted: root.consumePendingTab()

    onShownChanged: {
        if (root.shown) {
            root.consumePendingTab();
            Qt.callLater(() => root.forceActiveFocus());
        }
    }

    Connections {
        target: GlobalStates
        function onBluetoothManagerPendingTabChanged() {
            if (GlobalStates.bluetoothManagerPendingTab.length > 0)
                root.consumePendingTab();
        }
    }

    // A control that held the keys is destroyed or hidden on close; take them back
    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            if (root.Window.window && !root.Window.window.activeFocusItem)
                Qt.callLater(() => root.forceActiveFocus());
        }
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (ctrl && event.key >= Qt.Key_1 && event.key < Qt.Key_1 + root.tabIds.length) {
            root.selectTab(root.tabIds[event.key - Qt.Key_1]);
            event.accepted = true;
        } else if (ctrl && (event.key === Qt.Key_W || event.key === Qt.Key_Q)) {
            root.closeRequested();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: ClockStyle.colBackground
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.paneGap
        anchors.topMargin: ClockStyle.gapTiny
        spacing: ClockStyle.gapTiny

        ClockTopBar {
            Layout.fillWidth: true
            title: root.tabs.find(tab => tab.id === root.currentTab)?.label ?? ""
            subtitle: root.currentTab === "devices" ? Translation.tr("Connect, pair and forget devices")
                : Translation.tr("How this computer shows itself to other devices")
            showRailToggle: !root.compact && root.canExpandRail
            railExpanded: root.railOpen
            onRailToggled: root.railExpanded = !root.railExpanded
            onCloseRequested: root.closeRequested()
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            ClockRail {
                Layout.fillHeight: true
                Layout.preferredWidth: root.railWidth
                Layout.rightMargin: ClockStyle.paneGap
                visible: !root.compact
                tabs: root.tabs
                currentTab: root.currentTab
                expanded: root.railOpen
                showSettings: false
                badges: root.badges
                onSelected: tabId => root.selectTab(tabId)

                Behavior on Layout.preferredWidth {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: ClockStyle.paneGap

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Loader {
                        anchors.fill: parent
                        sourceComponent: root.currentTab === "devices" ? devicesComponent : settingsComponent
                    }
                }

                ClockNavigation {
                    Layout.fillWidth: true
                    visible: root.compact
                    tabs: root.tabs
                    currentTab: root.currentTab
                    onSelected: tabId => root.selectTab(tabId)
                }
            }
        }
    }

    Component {
        id: devicesComponent
        BluetoothDevicesPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            active: root.shown
        }
    }

    Component {
        id: settingsComponent
        BluetoothSettingsPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
        }
    }
}
