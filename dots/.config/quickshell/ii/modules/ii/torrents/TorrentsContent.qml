pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "TorrentsFormat.js" as Fmt

/**
 * The torrents inside its window, built from the clock app's parts so it reads as one of the
 * family: top bar, rail on the left and the page.
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
        { id: "torrents", icon: "downloading", label: Translation.tr("Torrents") },
        { id: "search", icon: "travel_explore", label: Translation.tr("Search") },
        { id: "add", icon: "add_link", label: Translation.tr("Add") },
        { id: "settings", icon: "tune", label: Translation.tr("Settings") }
    ]
    readonly property var tabIds: root.tabs.map(tab => tab.id)
    readonly property var badges: ({
        torrents: TorrentsService.torrents.length > 0 ? String(TorrentsService.torrents.length) : "",
        search: "",
        add: "",
        settings: ""
    })

    property string currentTab: "torrents"
    /// The torrent whose page is open over the list
    property string detailHash: ""
    readonly property bool shown: root.Window.window?.visible ?? true

    function selectTab(tabId: string): void {
        if (root.tabIds.includes(tabId)) {
            root.detailHash = "";
            root.currentTab = tabId;
        }
    }

    function consumePendingTab(): void {
        const pending = GlobalStates.torrentsPendingTab;
        GlobalStates.torrentsPendingTab = "";
        if (root.tabIds.includes(pending))
            root.selectTab(pending);
    }

    function subtitleFor(tabId: string): string {
        if (tabId === "torrents") {
            if (TorrentsService.state !== "up")
                return Translation.tr("qBittorrent is not running");
            return Translation.tr("%1 down  ·  %2 up").arg(Fmt.speed(TorrentsService.transfer.dl_info_speed))
                .arg(Fmt.speed(TorrentsService.transfer.up_info_speed));
        }
        if (tabId === "search")
            return Translation.tr("Find torrents on the sites qBittorrent searches");
        return tabId === "add" ? Translation.tr("Add a magnet link, a web link or a .torrent file")
            : Translation.tr("Speed limits and the qBittorrent service");
    }

    Binding {
        target: TorrentsService
        property: "watching"
        value: root.shown
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
        function onTorrentsPendingTabChanged() {
            if (GlobalStates.torrentsPendingTab.length > 0)
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
        } else if (event.key === Qt.Key_Escape && root.detailHash !== "") {
            root.detailHash = "";
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
            title: root.detailHash !== "" ? (TorrentsService.torrents.find(t => t.hash === root.detailHash)?.name ?? "")
                : (root.tabs.find(tab => tab.id === root.currentTab)?.label ?? "")
            subtitle: root.detailHash !== "" ? "" : root.subtitleFor(root.currentTab)
            showBack: root.detailHash !== ""
            onBackRequested: root.detailHash = ""
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

                    // The list stays alive under a torrent's page, so its search, filters
                    // and ticks are where they were when you come back
                    Loader {
                        anchors.fill: parent
                        visible: root.detailHash === ""
                        sourceComponent: root.currentTab === "torrents" ? torrentsComponent
                            : root.currentTab === "search" ? searchComponent
                            : root.currentTab === "add" ? addComponent : settingsComponent
                    }

                    Loader {
                        anchors.fill: parent
                        active: root.detailHash !== ""
                        sourceComponent: detailComponent
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
        id: torrentsComponent
        TorrentsPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            onAddRequested: root.selectTab("add")
            onTorrentOpened: hash => root.detailHash = hash
        }
    }

    Component {
        id: detailComponent
        TorrentDetailPage {
            hash: root.detailHash
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            onGone: root.detailHash = ""
        }
    }

    Component {
        id: searchComponent
        TorrentsSearchPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            active: root.shown
            onAdded: root.selectTab("torrents")
        }
    }

    Component {
        id: addComponent
        TorrentsAddPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            onAdded: root.selectTab("torrents")
        }
    }

    Component {
        id: settingsComponent
        TorrentsSettingsPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            active: root.shown
        }
    }
}
