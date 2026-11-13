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
 * The Downloads app inside its window, built from the clock app's parts so it reads as
 * one of the family: top bar, rail on the left (Settings at its foot) and the page.
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
        { id: "download", icon: "download", label: Translation.tr("Download") },
        { id: "queue", icon: "downloading", label: Translation.tr("Queue") },
        { id: "history", icon: "history", label: Translation.tr("History") }
    ]
    readonly property var tabIds: root.tabs.map(tab => tab.id)
    readonly property var badges: ({
        download: "",
        queue: DownloadsService.activeJobs.length > 0 ? String(DownloadsService.activeJobs.length) : "",
        history: ""
    })

    property string currentTab: "download"
    property bool settingsOpen: false
    readonly property bool shown: root.Window.window?.visible ?? true

    function selectTab(tabId: string): void {
        if (!root.tabIds.includes(tabId))
            return;
        root.settingsOpen = false;
        root.currentTab = tabId;
    }

    function consumePendingTab(): void {
        const pending = GlobalStates.downloadsPendingTab;
        GlobalStates.downloadsPendingTab = "";
        if (root.tabIds.includes(pending))
            root.selectTab(pending);
    }

    Component.onCompleted: {
        root.consumePendingTab();
        DownloadsService.loadSettings();
    }

    onShownChanged: {
        if (root.shown) {
            root.consumePendingTab();
            DownloadsService.loadSettings();
            Qt.callLater(() => root.forceActiveFocus());
        } else {
            root.settingsOpen = false;
        }
    }

    Connections {
        target: GlobalStates
        function onDownloadsPendingTabChanged() {
            if (GlobalStates.downloadsPendingTab.length > 0)
                root.consumePendingTab();
        }
    }

    // A field that held the keys is destroyed or hidden on close; take them back
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
        } else if (ctrl && event.key === Qt.Key_Comma) {
            root.settingsOpen = !root.settingsOpen;
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.settingsOpen) {
            root.settingsOpen = false;
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
            title: root.settingsOpen ? Translation.tr("Download settings")
                : (root.tabs.find(tab => tab.id === root.currentTab)?.label ?? "")
            subtitle: root.settingsOpen ? "" : (root.currentTab === "download" ? Translation.tr("Paste a link to a video, a song or any file")
                : root.currentTab === "queue" ? Translation.tr("%1 in progress").arg(DownloadsService.activeJobs.length)
                : Translation.tr("%1 finished").arg(DownloadsService.finishedJobs.length))
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
                currentTab: root.currentTab
                expanded: root.railOpen
                settingsOpen: root.settingsOpen
                settingsTooltip: Translation.tr("Download settings")
                badges: root.badges
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
                    clip: true

                    Loader {
                        anchors.fill: parent
                        visible: !root.settingsOpen
                        sourceComponent: root.currentTab === "download" ? downloadComponent
                            : root.currentTab === "queue" ? queueComponent : historyComponent
                    }

                    Loader {
                        anchors.fill: parent
                        active: root.settingsOpen
                        visible: active
                        sourceComponent: DownloadsSettingsPage {
                            compact: root.compact
                            layoutWidth: root.pageLayoutWidth
                        }
                    }
                }

                ClockNavigation {
                    Layout.fillWidth: true
                    visible: root.compact && root.tabs.length > 1
                    tabs: root.tabs
                    currentTab: root.currentTab
                    onSelected: tabId => root.selectTab(tabId)
                }
            }
        }
    }

    Component {
        id: downloadComponent
        DownloadPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            onQueued: root.selectTab("queue")
        }
    }

    Component {
        id: queueComponent
        JobsPage {
            finished: false
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
        }
    }

    Component {
        id: historyComponent
        JobsPage {
            finished: true
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
        }
    }
}
