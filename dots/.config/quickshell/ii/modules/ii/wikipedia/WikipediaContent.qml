pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "./WikipediaLogic.js" as WikiLogic

/** Wikipedia's frame: a compact shared bar, persistent search, and three clear places. */
FocusScope {
    id: root

    signal closeRequested()

    readonly property var svc: WikipediaService
    readonly property bool compact: root.width < ClockStyle.compactMax
    readonly property bool canExpandRail: root.width >= ClockStyle.railExpandMin
    readonly property bool railOpen: root.canExpandRail && root.railExpanded
    readonly property real railWidth: root.railOpen ? ClockStyle.railExpandedWidth : ClockStyle.railCollapsedWidth
    readonly property real pageLayoutWidth: Math.max(0, root.width - ClockStyle.paneGap * 2
        - (root.compact ? 0 : root.railWidth + ClockStyle.paneGap))
    readonly property bool shown: root.Window.window?.visible ?? true

    readonly property var tabs: [
        { "id": "home", "icon": "home", "label": Translation.tr("Home") },
        { "id": "search", "icon": "search", "label": Translation.tr("Search") },
        { "id": "article", "icon": "menu_book", "label": Translation.tr("Article") }
    ]
    readonly property var languageOptions: WikiLogic.languageCatalog()
    readonly property var currentLanguage: WikiLogic.languageForCode(root.languageOptions, root.svc.language)
    readonly property string languageButtonLabel: {
        const name = String(root.currentLanguage.englishName ?? root.svc.language).trim();
        const shortName = name.length > 12 ? name.slice(0, 11) + "…" : name;
        return shortName + " · " + root.svc.language.toUpperCase();
    }
    readonly property var tabIds: root.tabs.map(tab => tab.id)
    readonly property var badges: ({
        home: root.svc.homeArticle !== null ? "1" : "",
        search: root.svc.results.length > 0 ? String(root.svc.results.length) : "",
        article: root.svc.article !== null ? "" : ""
    })

    property string currentTab: "home"
    property bool railExpanded: true
    property bool stateInitialized: false

    function selectTab(tabId: string): void {
        if (!root.tabIds.includes(tabId))
            return;
        root.currentTab = tabId;
        if (tabId === "search") {
            Qt.callLater(() => root.focusSearch());
        } else if (tabId === "home" && !root.svc.homeLoaded && !root.svc.homeLoading
                && root.svc.homeError.length === 0) {
            root.svc.loadHome();
        }
    }

    function focusSearch(): void {
        searchField.focusInput();
    }

    function consumeRequestedTab(): void {
        const pending = root.svc.requestedTab;
        if (pending.length === 0)
            return;
        root.svc.requestedTab = "";
        if (root.tabIds.includes(pending))
            root.selectTab(pending);
    }

    function submitSearch(text): void {
        root.svc.search(text);
        root.focusSearch();
    }

    function openLanguagePicker(): void {
        languagePopup.open();
    }

    function openReadingSettings(): void {
        if (root.currentTab !== "article")
            root.selectTab("article");
        Qt.callLater(() => {
            if (contentLoader.item && typeof contentLoader.item.openReadingSettings === "function")
                contentLoader.item.openReadingSettings(readingButton, root);
        });
    }

    function refresh(): void {
        if (root.currentTab === "home")
            root.svc.retryHome();
        else if (root.currentTab === "search")
            root.svc.retrySearch();
        else
            root.svc.retryArticle();
    }

    Component.onCompleted: {
        root.stateInitialized = true;
        root.consumeRequestedTab();
        if (root.currentTab === "home" && !root.svc.homeLoaded && !root.svc.homeLoading
                && root.svc.homeError.length === 0)
            root.svc.loadHome();
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
            if (root.stateInitialized && root.svc.requestedTab.length > 0)
                root.consumeRequestedTab();
        }

        function onQueryChanged() {
            if (searchField.text !== root.svc.query)
                searchField.text = root.svc.query;
        }
    }

    // A field can be destroyed while the window closes; hand key navigation back to the frame.
    Connections {
        target: root.Window.window

        function onActiveFocusItemChanged() {
            if (root.Window.window && !root.Window.window.activeFocusItem)
                Qt.callLater(() => root.forceActiveFocus());
        }
    }

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (ctrl && root.currentTab === "article" && !searchField.inputActiveFocus
                && (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal
                    || event.key === Qt.Key_Minus || event.key === Qt.Key_0)) {
            if (typeof root.svc.adjustReaderFontSize !== "function")
                return;
            if (event.key === Qt.Key_0)
                root.svc.resetReaderFontSize();
            else
                root.svc.adjustReaderFontSize(event.key === Qt.Key_Minus ? -1 : 1);
            event.accepted = true;
        } else if (ctrl && event.key >= Qt.Key_1 && event.key < Qt.Key_1 + root.tabIds.length) {
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
            title: Translation.tr("Wikipedia")
            subtitle: root.currentTab === "home"
                ? Translation.tr("Daily reading · %1").arg(root.svc.language.toUpperCase())
                : root.currentTab === "search"
                    ? (root.svc.query.length > 0
                        ? Translation.tr("Search results · %1").arg(root.svc.query)
                        : Translation.tr("Find an article"))
                    : (root.svc.article?.title ?? Translation.tr("Article"))
            showBack: root.currentTab === "article" && root.svc.history.length > 0
            showRailToggle: !root.compact && root.canExpandRail
            railExpanded: root.railOpen
            onBackRequested: root.svc.back()
            onRailToggled: root.railExpanded = !root.railExpanded
            onCloseRequested: root.closeRequested()

            ClockButton {
                id: languageButton
                symbol: "language"
                label: root.languageButtonLabel
                variant: "text"
                tooltip: Translation.tr("Wikipedia language: %1 (%2)")
                    .arg(root.currentLanguage.englishName).arg(root.svc.language.toUpperCase())
                Accessible.name: Translation.tr("Wikipedia language: %1 (%2)")
                    .arg(root.currentLanguage.englishName).arg(root.svc.language.toUpperCase())
                onClicked: root.openLanguagePicker()
            }

            ClockButton {
                id: readingButton
                visible: root.currentTab === "article"
                symbol: "format_size"
                label: Translation.tr("Aa")
                variant: "text"
                tooltip: Translation.tr("Reading size")
                Accessible.name: Translation.tr("Reading size")
                onClicked: root.openReadingSettings()
            }

            ClockIconButton {
                symbol: "casino"
                tooltip: Translation.tr("Random article")
                scaleBehaviorEnabled: false
                onClicked: root.svc.random()
            }

            ClockIconButton {
                visible: root.currentTab === "article"
                symbol: "open_in_new"
                tooltip: Translation.tr("Open on Wikipedia")
                enabled: root.svc.article !== null
                scaleBehaviorEnabled: false
                onClicked: root.svc.openInBrowser()
            }

            ClockIconButton {
                visible: root.currentTab === "article"
                symbol: "content_copy"
                tooltip: Translation.tr("Copy link")
                enabled: root.svc.article !== null
                scaleBehaviorEnabled: false
                onClicked: root.svc.copyLink()
            }

            ClockIconButton {
                symbol: "refresh"
                tooltip: Translation.tr("Refresh")
                scaleBehaviorEnabled: false
                onClicked: root.refresh()
            }
        }

        WikipediaSearchField {
            id: searchField
            Layout.fillWidth: true
            text: root.svc.query
            onSubmitted: text => root.submitSearch(text)
            onCleared: root.svc.clearSearch()
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
                        id: contentLoader
                        anchors.fill: parent
                        sourceComponent: root.currentTab === "home" ? homeComponent
                            : root.currentTab === "search" ? searchComponent : articleComponent
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

    WikipediaLanguagePopup {
        id: languagePopup
        anchorItem: languageButton
        popupParent: root
        selectedCode: root.svc.language
        languages: root.languageOptions
        onLanguageSelected: code => root.svc.setLanguage(code)
    }

    Component {
        id: homeComponent
        WikipediaHomePage {
            compact: root.compact
        }
    }

    Component {
        id: searchComponent
        WikipediaSearchPage {
            compact: root.compact
        }
    }

    Component {
        id: articleComponent
        WikipediaArticlePage {
            compact: root.compact
        }
    }
}
