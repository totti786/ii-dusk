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
 * The Music app inside its window, built from the clock app's parts: top bar, rail,
 * the page, and the player strip along the bottom. The big now-playing view and an opened
 * album sit over the current tab and close back to it.
 */
FocusScope {
    id: root

    signal closeRequested()

    readonly property bool compact: root.width < ClockStyle.compactMax
    readonly property bool canExpandRail: root.width >= ClockStyle.railExpandMin
    property bool railExpanded: true
    readonly property bool railOpen: root.canExpandRail && root.railExpanded
    readonly property real railWidth: root.railOpen ? ClockStyle.railExpandedWidth : ClockStyle.railCollapsedWidth

    readonly property var tabs: [
        { id: "home", icon: "home", label: Translation.tr("Home") },
        { id: "search", icon: "search", label: Translation.tr("Search") },
        { id: "library", icon: "favorite", label: Translation.tr("Library") },
        { id: "queue", icon: "queue_music", label: Translation.tr("Queue") }
    ]
    readonly property var tabIds: root.tabs.map(tab => tab.id)

    property string currentTab: "home"
    property bool settingsOpen: false
    property bool nowOpen: false
    property bool collectionOpen: false
    property bool artistOpen: false
    // Pages left behind on the way in (artist -> album -> back), kept whole so going back is instant
    property var backStack: []
    readonly property bool overlayOpen: root.settingsOpen || root.nowOpen || root.collectionOpen || root.artistOpen
    readonly property bool shown: root.Window.window?.visible ?? true

    function selectTab(tabId: string): void {
        if (!root.tabIds.includes(tabId))
            return;
        root.settingsOpen = false;
        root.nowOpen = false;
        root.collectionOpen = false;
        root.artistOpen = false;
        root.backStack = [];
        root.currentTab = tabId;
    }

    /// What the floating shuffle button mixes: the Library's open list, or Home's picks
    readonly property var shuffleTracks: {
        if (root.currentTab === "library")
            return libraryLoader.item?.tracks ?? [];
        const seen = {}, picks = [];
        for (const shelf of MusicService.homeShelves) {
            for (const t of shelf.tracks) {
                if (!seen[t.id]) {
                    seen[t.id] = true;
                    picks.push(t);
                }
            }
        }
        return picks.length > 0 ? picks : MusicService.favorites;
    }
    readonly property bool shuffleVisible: !root.overlayOpen && ["home", "library"].includes(root.currentTab)
        && root.shuffleTracks.length > 1

    function goBack(): void {
        if (root.settingsOpen)
            root.settingsOpen = false;
        else if (root.nowOpen)
            root.nowOpen = false;
        else if (root.backStack.length > 0) {
            const prev = root.backStack[root.backStack.length - 1];
            root.backStack = root.backStack.slice(0, -1);
            if (prev.kind === "artist") {
                MusicService.restoreArtist(prev.data);
                root.collectionOpen = false;
                root.artistOpen = true;
            } else {
                MusicService.collection = prev.data;
                MusicService.collectionLoading = false;
                MusicService.collectionError = "";
                root.artistOpen = false;
                root.collectionOpen = true;
            }
        } else {
            root.collectionOpen = false;
            root.artistOpen = false;
        }
    }

    /// Remember the page being left, if there is one
    function pushCurrent(): void {
        if (root.artistOpen)
            root.backStack = root.backStack.concat([{ kind: "artist", data: MusicService.artist }]);
        else if (root.collectionOpen)
            root.backStack = root.backStack.concat([{ kind: "collection", data: MusicService.collection }]);
    }

    function openCollection(kind: string, id: string): void {
        root.pushCurrent();
        MusicService.openCollection(kind, id);
        root.settingsOpen = false;
        root.nowOpen = false;
        root.artistOpen = false;
        root.collectionOpen = true;
    }

    function openArtist(id: string, name: string, art: string): void {
        root.pushCurrent();
        MusicService.openArtist(id, name, art);
        root.settingsOpen = false;
        root.nowOpen = false;
        root.collectionOpen = false;
        root.artistOpen = true;
    }

    // Any artist name in the app asks for the page this way
    Connections {
        target: MusicService
        function onArtistRequested(id: string, name: string, art: string): void {
            root.openArtist(id, name, art);
        }
    }

    function consumePendingTab(): void {
        const pending = GlobalStates.musicPendingTab;
        GlobalStates.musicPendingTab = "";
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
        if (ctrl && event.key >= Qt.Key_1 && event.key < Qt.Key_1 + root.tabIds.length) {
            root.selectTab(root.tabIds[event.key - Qt.Key_1]);
            event.accepted = true;
        } else if (ctrl && (event.key === Qt.Key_W || event.key === Qt.Key_Q)) {
            root.closeRequested();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_Comma) {
            root.settingsOpen = !root.settingsOpen;
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_L) {
            root.nowOpen = !root.nowOpen;
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_F) {
            root.selectTab("search");
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            if (root.overlayOpen)
                root.goBack();
            else
                root.closeRequested();
            event.accepted = true;
        } else if (!root.typing && event.key === Qt.Key_Space) {
            MusicService.toggle();
            event.accepted = true;
        } else if (!root.typing && event.key === Qt.Key_Right && ctrl) {
            MusicService.next();
            event.accepted = true;
        } else if (!root.typing && event.key === Qt.Key_Left && ctrl) {
            MusicService.prev();
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
            title: root.settingsOpen ? Translation.tr("Music settings")
                : root.nowOpen ? Translation.tr("Now playing")
                : root.artistOpen ? (MusicService.artist.head?.name ?? "")
                : root.collectionOpen ? (MusicService.collection.head?.title ?? "")
                : (root.tabs.find(tab => tab.id === root.currentTab)?.label ?? "")
            subtitle: ""
            showBack: root.overlayOpen
            showRailToggle: !root.compact && root.canExpandRail
            railExpanded: root.railOpen
            onBackRequested: root.goBack()
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
                currentTab: root.overlayOpen ? "" : root.currentTab
                expanded: root.railOpen
                settingsOpen: root.settingsOpen
                settingsTooltip: Translation.tr("Music settings")
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
                        id: libraryLoader
                        anchors.fill: parent
                        visible: !root.overlayOpen
                        sourceComponent: root.currentTab === "home" ? homeComponent
                            : root.currentTab === "search" ? searchComponent
                            : root.currentTab === "library" ? libraryComponent : queueComponent
                    }

                    ClockButton {
                        z: 5
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 12
                        visible: root.shuffleVisible
                        variant: "filled"
                        symbol: "shuffle"
                        label: Translation.tr("Shuffle")
                        onClicked: MusicService.shuffleAndPlay(root.shuffleTracks)
                    }

                    Loader {
                        anchors.fill: parent
                        active: root.collectionOpen
                        visible: active && !root.settingsOpen && !root.nowOpen
                        sourceComponent: CollectionPage { compact: root.compact }
                    }

                    Loader {
                        anchors.fill: parent
                        active: root.artistOpen
                        visible: active && !root.settingsOpen && !root.nowOpen
                        sourceComponent: ArtistPage {
                            compact: root.compact
                            onCollectionRequested: (kind, id) => root.openCollection(kind, id)
                        }
                    }

                    Loader {
                        anchors.fill: parent
                        active: root.settingsOpen
                        visible: active
                        sourceComponent: MusicSettingsPage { compact: root.compact }
                    }

                    Loader {
                        anchors.fill: parent
                        active: root.nowOpen && !root.settingsOpen
                        visible: active
                        sourceComponent: NowPlaying { compact: root.compact }
                    }
                }

                PlayerBar {
                    Layout.fillWidth: true
                    visible: !root.nowOpen
                    compact: root.compact
                    onExpandRequested: root.nowOpen = true
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

    Component { id: homeComponent; HomePage { compact: root.compact } }
    Component {
        id: searchComponent
        SearchPage {
            compact: root.compact
            onCollectionRequested: (kind, id) => root.openCollection(kind, id)
        }
    }
    Component { id: libraryComponent; LibraryPage { compact: root.compact } }
    Component { id: queueComponent; QueuePage { compact: root.compact } }
}
