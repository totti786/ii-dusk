pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** The Monitor inside its window: top bar, rail and a page, built from the clock app's parts. */
FocusScope {
    id: root

    signal closeRequested()

    readonly property bool compact: root.width < ClockStyle.compactMax
    readonly property bool canExpandRail: root.width >= ClockStyle.railExpandMin
    property bool railExpanded: false
    readonly property bool railOpen: root.canExpandRail && root.railExpanded
    readonly property real railWidth: root.railOpen ? ClockStyle.railExpandedWidth : ClockStyle.railCollapsedWidth

    readonly property var tabs: [
        { id: "overview", icon: "monitor_heart", label: Translation.tr("Overview") },
        { id: "processes", icon: "list", label: Translation.tr("Processes") },
        { id: "network", icon: "network_ping", label: Translation.tr("Network") }
    ]
    readonly property var tabIds: root.tabs.map(tab => tab.id)

    property string currentTab: "overview"
    property bool settingsOpen: false
    readonly property bool shown: root.Window.window?.visible ?? true

    function selectTab(tabId: string): void {
        if (!root.tabIds.includes(tabId))
            return;
        root.settingsOpen = false;
        root.currentTab = tabId;
    }

    function consumePendingTab(): void {
        const pending = GlobalStates.monitorPendingTab;
        GlobalStates.monitorPendingTab = "";
        if (root.tabIds.includes(pending))
            root.selectTab(pending);
    }

    Component.onCompleted: root.consumePendingTab()

    onShownChanged: {
        if (root.shown) {
            root.consumePendingTab();
            Qt.callLater(() => root.forceActiveFocus());
        } else {
            root.settingsOpen = false;
        }
    }

    // A field that held the keys is destroyed on close; take them back
    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            if (root.Window.window && !root.Window.window.activeFocusItem)
                Qt.callLater(() => root.forceActiveFocus());
        }
    }

    readonly property bool typing: (root.Window.window?.activeFocusItem?.hasOwnProperty("cursorPosition")) ?? false

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
            MonitorService.keyboardNav = true;
        if (ctrl && event.key >= Qt.Key_1 && event.key < Qt.Key_1 + root.tabIds.length) {
            root.selectTab(root.tabIds[event.key - Qt.Key_1]);
            event.accepted = true;
        } else if (ctrl && (event.key === Qt.Key_W || event.key === Qt.Key_Q)) {
            root.closeRequested();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_Comma) {
            root.settingsOpen = !root.settingsOpen;
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_F) {
            root.selectTab("processes");
            event.accepted = true;
        } else if (!root.typing && !ctrl && event.key === Qt.Key_Slash) {
            // "/" searches the process list: on the Processes page, else on the Overview's card
            if (root.currentTab !== "processes")
                root.selectTab("overview");
            Qt.callLater(MonitorService.openProcSearch);
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.settingsOpen) {
            root.settingsOpen = false;
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && MonitorService.expandedCard !== "" && root.currentTab === "overview") {
            MonitorService.expandedCard = "";
            event.accepted = true;
        } else if (!root.typing && !ctrl && (event.key === Qt.Key_B || event.key === Qt.Key_N)) {
            // btop's keys: b is the previous network interface, n the next
            MonitorService.cycleNic(event.key === Qt.Key_B ? -1 : 1);
            event.accepted = true;
        } else if (!root.typing && !ctrl && event.key === Qt.Key_K && MonitorService.selectedPid > 0 && root.currentTab !== "network") {
            // btop's k, on the selected process: k asks it to end, Shift+K kills it outright
            MonitorService.signalProcess(MonitorService.selectedPid, (event.modifiers & Qt.ShiftModifier) ? "KILL" : "TERM");
            event.accepted = true;
        } else if (!root.typing && !ctrl && (event.key === Qt.Key_Down || event.key === Qt.Key_Up) && root.currentTab !== "network") {
            MonitorService.stepProcess(event.key === Qt.Key_Down ? 1 : -1);
            event.accepted = true;
        } else if (!root.typing && event.key === Qt.Key_Space) {
            MonitorService.paused = !MonitorService.paused;
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
            title: root.settingsOpen ? Translation.tr("Monitor settings")
                : (root.tabs.find(tab => tab.id === root.currentTab)?.label ?? "")
            subtitle: MonitorService.paused ? Translation.tr("Paused") : MonitorService.live ? MonitorService.host : Translation.tr("Starting…")
            showBack: root.settingsOpen
            showRailToggle: !root.compact && root.canExpandRail
            railExpanded: root.railOpen
            onBackRequested: root.settingsOpen = false
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
                currentTab: root.settingsOpen ? "" : root.currentTab
                expanded: root.railOpen
                settingsOpen: root.settingsOpen
                settingsTooltip: Translation.tr("Monitor settings")
                onSelected: tabId => root.selectTab(tabId)
                onSettingsRequested: root.settingsOpen = !root.settingsOpen

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

                    Loader {
                        anchors.fill: parent
                        visible: !root.settingsOpen
                        sourceComponent: root.currentTab === "overview" ? overviewComponent
                            : root.currentTab === "processes" ? processesComponent : networkComponent
                    }

                    Loader {
                        anchors.fill: parent
                        active: root.settingsOpen
                        visible: active
                        sourceComponent: MonitorSettingsPage { compact: root.compact }
                    }

                    StyledText {
                        visible: !MonitorService.live && !MonitorService.paused && !root.settingsOpen
                        anchors.centerIn: parent
                        text: Translation.tr("Reading the system…")
                        color: ClockStyle.colSubtext
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
        id: overviewComponent
        OverviewPage {
            compact: root.compact
            onOpenTab: tabId => root.selectTab(tabId)
        }
    }
    Component { id: processesComponent; ProcessesPage { compact: root.compact } }
    Component { id: networkComponent; NetworkPage { compact: root.compact } }
}
