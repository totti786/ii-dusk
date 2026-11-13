pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * YouTube as a normal Clock-style app: a compact Home discovery view and a focused Search
 * view. Results are metadata cards; playback remains detached in mpv.
 */
FocusScope {
    id: root

    signal closeRequested()

    readonly property var svc: YouTubeService
    readonly property bool compact: root.width < ClockStyle.compactMax
    readonly property bool canExpandRail: root.width >= ClockStyle.railExpandMin
    property bool railExpanded: true
    readonly property bool railOpen: root.canExpandRail && root.railExpanded
    readonly property real railWidth: root.railOpen ? ClockStyle.railExpandedWidth : ClockStyle.railCollapsedWidth
    readonly property real pageLayoutWidth: Math.max(0, root.width - ClockStyle.paneGap * 2
        - (root.compact ? 0 : root.railWidth + ClockStyle.paneGap))
    readonly property bool shown: root.Window.window?.visible ?? true

    readonly property var tabs: [
        { "id": "home", "icon": "video_library", "label": Translation.tr("Home") },
        { "id": "search", "icon": "search", "label": Translation.tr("Search") }
    ]
    readonly property var tabIds: root.tabs.map(tab => tab.id)
    readonly property var badges: ({
        home: root.svc.homeResults.length > 0 ? String(root.svc.homeResults.length) : "",
        search: ""
    })

    property string currentTab: "home"
    property var _searchInput: null

    function selectTab(tabId: string): void {
        if (!root.tabIds.includes(tabId))
            return;
        root.currentTab = tabId;
        if (tabId === "search") {
            root.resumeSearchIfNeeded();
            Qt.callLater(() => root.focusSearch());
        } else if (root.svc.homeResults.length === 0 && !root.svc.homeLoading
                && root.svc.homeError.length === 0)
            root.svc.loadHome(root.svc.homeTopic || "Documentaries");
    }

    // Home and Search share one yt-dlp runner. If switching to Home canceled a pending
    // search, recover that query when the user returns instead of showing a false empty state.
    function resumeSearchIfNeeded(): void {
        if (root.svc.query.length > 0 && root.svc.results.length === 0
                && !root.svc.searching && root.svc.error.length === 0)
            root.svc.search(root.svc.query);
    }

    function consumeRequestedTab(): void {
        const pending = root.svc.requestedTab;
        root.svc.requestedTab = "";
        if (root.tabIds.includes(pending))
            root.selectTab(pending);
    }

    function focusSearch(): void {
        if (root.currentTab !== "search")
            return;
        if (root._searchInput) {
            root._searchInput.forceActiveFocus();
            root._searchInput.selectAll();
        }
    }

    function submitSearch(value): void {
        root.svc.submit(value);
        root.focusSearch();
    }

    function refresh(): void {
        if (root.currentTab === "home")
            root.svc.retryHome();
        else if (root.svc.query.length > 0)
            root.svc.search(root.svc.query);
        else
            root.focusSearch();
    }

    Component.onCompleted: {
        root.consumeRequestedTab();
        if (root.currentTab === "home" && root.svc.homeResults.length === 0
                && !root.svc.homeLoading && root.svc.homeError.length === 0)
            root.svc.loadHome("Documentaries");
        Qt.callLater(() => root.forceActiveFocus());
    }

    onShownChanged: {
        if (root.shown) {
            root.consumeRequestedTab();
            Qt.callLater(() => root.forceActiveFocus());
        }
    }

    Connections {
        target: root.svc

        function onRequestedTabChanged() {
            if (root.svc.requestedTab.length > 0)
                root.consumeRequestedTab();
        }

        function onQueryChanged() {
            if (root.currentTab === "search" && root._searchInput && root._searchInput.text !== root.svc.query)
                root._searchInput.text = root.svc.query;
        }
    }

    // A control that held focus is destroyed or hidden when the window closes; keep the
    // frame ready for keyboard navigation when it is shown again.
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
        } else if (ctrl && event.key === Qt.Key_F) {
            root.selectTab("search");
            event.accepted = true;
        } else if (ctrl && (event.key === Qt.Key_W || event.key === Qt.Key_Q)) {
            root.closeRequested();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
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
            title: Translation.tr("YouTube")
            subtitle: root.currentTab === "home" ? Translation.tr("Home · %1").arg(root.svc.homeSubtitle)
                : root.svc.query.length > 0 ? Translation.tr("Search results for %1").arg(root.svc.query)
                : Translation.tr("Search public videos")
            showRailToggle: !root.compact && root.canExpandRail
            railExpanded: root.railOpen
            onRailToggled: root.railExpanded = !root.railExpanded
            onCloseRequested: root.closeRequested()

            ClockIconButton {
                symbol: "refresh"
                tooltip: Translation.tr("Refresh")
                scaleBehaviorEnabled: false
                Accessible.name: Translation.tr("Refresh YouTube %1").arg(root.currentTab === "home"
                    ? Translation.tr("discovery") : Translation.tr("search"))
                onClicked: root.refresh()
            }
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
                        sourceComponent: root.currentTab === "home" ? homeComponent : searchComponent
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

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 52
            visible: root.svc.lastPlayed !== null
            radius: ClockStyle.radiusLarge
            color: ClockStyle.colSecondaryContainer

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: ClockStyle.gap
                anchors.rightMargin: ClockStyle.gapSmall
                spacing: ClockStyle.gapSmall

                MaterialSymbol {
                    text: "play_circle"
                    iconSize: ClockStyle.iconNormal
                    fill: 1
                    color: ClockStyle.colOnSecondaryContainer
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: Translation.tr("Last opened")
                        color: ClockStyle.colOnSecondaryContainer
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: Font.DemiBold
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.svc.lastPlayed?.title ?? ""
                        color: ClockStyle.colOnSecondaryContainer
                        opacity: 0.82
                        font.pixelSize: ClockStyle.textSmall
                        elide: Text.ElideRight
                    }
                }

                ClockButton {
                    symbol: "open_in_new"
                    label: Translation.tr("Open")
                    variant: "text"
                    scaleBehaviorEnabled: false
                    Accessible.name: Translation.tr("Open last video on YouTube")
                    onClicked: root.svc.openExternal(root.svc.lastPlayed)
                }
            }
        }
    }

    Component {
        id: homeComponent

        Item {
            ColumnLayout {
                anchors.fill: parent
                spacing: ClockStyle.gapSmall

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                    Flow {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall

                        Repeater {
                            model: root.svc.topicOptions

                            delegate: ClockChip {
                                required property var modelData
                                label: modelData.label
                                symbol: modelData.symbol
                                selected: root.svc.homeTopic === modelData.id
                                scaleBehaviorEnabled: false
                                Accessible.name: Translation.tr("Discover %1").arg(modelData.label)
                                onClicked: root.svc.loadHome(modelData.id)
                            }
                        }
                    }

                }

                YouTubeResultsList {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    service: root.svc
                    entries: root.svc.homeResults
                    loading: root.svc.homeLoading
                    error: root.svc.homeError
                    emptyTitle: Translation.tr("Nothing to discover yet")
                    emptySubtitle: Translation.tr("Choose a topic to load public videos.")
                    emptySymbol: "video_library"
                    onRetry: root.svc.retryHome()
                }
            }
        }
    }

    Component {
        id: searchComponent

        Item {
            ColumnLayout {
                anchors.fill: parent
                spacing: ClockStyle.paneGap

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 48
                            radius: ClockStyle.radiusSmall
                            color: searchInput.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField
                            Accessible.role: Accessible.EditableText
                            Accessible.name: Translation.tr("Search videos or paste a YouTube link")

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.IBeamCursor
                                onClicked: searchInput.forceActiveFocus()
                            }

                            MaterialSymbol {
                                anchors {
                                    left: parent.left
                                    leftMargin: ClockStyle.gap
                                    verticalCenter: parent.verticalCenter
                                }
                                text: "search"
                                iconSize: ClockStyle.iconNormal
                                color: ClockStyle.colOnSurfaceVariant
                            }

                            StyledTextInput {
                                id: searchInput
                                anchors {
                                    fill: parent
                                    leftMargin: 44
                                    rightMargin: 48
                                }
                                text: root.svc.query
                                verticalAlignment: TextInput.AlignVCenter
                                font.pixelSize: ClockStyle.textNormal
                                color: ClockStyle.colOnSurface
                                selectByMouse: true
                                activeFocusOnTab: true
                                Accessible.name: Translation.tr("Search videos or paste a YouTube link")
                                onAccepted: root.submitSearch(text)
                                Component.onCompleted: root._searchInput = searchInput
                                Component.onDestruction: {
                                    if (root._searchInput === searchInput)
                                        root._searchInput = null;
                                }

                                StyledText {
                                    anchors.fill: parent
                                    visible: searchInput.text.length === 0
                                    verticalAlignment: Text.AlignVCenter
                                    text: Translation.tr("Search titles or paste a YouTube link")
                                    color: ClockStyle.colSubtext
                                    font.pixelSize: ClockStyle.textNormal
                                }
                            }

                            ClockIconButton {
                                anchors {
                                    right: parent.right
                                    rightMargin: ClockStyle.gapTiny
                                    verticalCenter: parent.verticalCenter
                                }
                                visible: searchInput.text.length > 0
                                symbol: "close"
                                tooltip: Translation.tr("Clear")
                                scaleBehaviorEnabled: false
                                onClicked: {
                                    searchInput.text = "";
                                    root.svc.clear();
                                    root.svc.requestedTab = "search";
                                    searchInput.forceActiveFocus();
                                }
                            }
                        }

                        ClockButton {
                            symbol: "search"
                            label: Translation.tr("Search")
                            variant: "filled"
                            enabled: !root.svc.searching
                            scaleBehaviorEnabled: false
                            Accessible.name: Translation.tr("Search YouTube")
                            onClicked: root.submitSearch(searchInput.text)
                        }

                        ClockButton {
                            symbol: "link"
                            label: Translation.tr("Open link")
                            variant: "tonal"
                            enabled: !root.svc.searching
                            scaleBehaviorEnabled: false
                            Accessible.name: Translation.tr("Open a YouTube link")
                            onClicked: root.svc.openLink(searchInput.text.length > 0
                                ? searchInput.text : String(Quickshell.clipboardText ?? ""))
                        }
                }

                YouTubeResultsList {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    service: root.svc
                    entries: root.svc.results
                    loading: root.svc.searching
                    error: root.svc.error
                    emptyTitle: root.svc.query.length > 0
                        ? Translation.tr("No search results") : Translation.tr("Search public videos")
                    emptySubtitle: root.svc.query.length > 0
                        ? Translation.tr("Try another title or topic.")
                        : Translation.tr("Type a title or paste a YouTube video link.")
                    emptySymbol: "search"
                    onRetry: root.submitSearch(root.svc.query)
                }
            }
        }
    }
}
