pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** The mediator inside its window: top bar and rail from the clock's parts, the shared browser as the page. */
FocusScope {
    id: root

    signal closeRequested()
    signal overlayRequested()

    readonly property bool compact: root.width < ClockStyle.compactMax
    readonly property bool canExpandRail: root.width >= ClockStyle.railExpandMin
    property bool railExpanded: true
    readonly property bool railOpen: root.canExpandRail && root.railExpanded
    readonly property real railWidth: root.railOpen ? ClockStyle.railExpandedWidth : ClockStyle.railCollapsedWidth

    readonly property var tabs: [
        { id: "all", icon: "grid_view", label: Translation.tr("All") },
        { id: "anime", icon: "animation", label: Translation.tr("Anime") },
        { id: "shows", icon: "tv", label: Translation.tr("Shows") },
        { id: "movies", icon: "movie", label: Translation.tr("Movies") },
        { id: "stream", icon: "live_tv", label: Translation.tr("Streaming") }
    ]
    readonly property var tabIds: root.tabs.map(tab => tab.id)
    readonly property var badges: {
        const out = ({ all: String(MediatorService.titles.length) });
        for (const lib of ["anime", "shows", "movies"])
            out[lib] = String(MediatorService.titles.filter(t => t.lib === lib).length);
        return out;
    }
    readonly property string currentTab: browser.streaming ? "stream"
        : (browser.settingsOpen ? "" : (browser.tab === "" ? "all" : browser.tab))

    function selectTab(tabId: string): void {
        if (!root.tabIds.includes(tabId))
            return;
        browser.closeSettings();
        MediatorService.clearDetail();
        browser.setTab(tabId === "all" ? "" : tabId);
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
            title: browser.settingsOpen ? Translation.tr("Settings")
                : (root.tabs.find(tab => tab.id === root.currentTab)?.label ?? Translation.tr("Mediator"))
            subtitle: browser.stremio ? Translation.tr("Movies and series from your Stremio addons")
                : browser.streaming
                ? (MediatorService.anilistStatus?.ok
                    ? Translation.tr("AniList · %1").arg(MediatorService.anilistStatus.username ?? "")
                    : Translation.tr("Local streams and provider search"))
                : MediatorService.loading ? Translation.tr("Scanning…")
                : Translation.tr("%1 titles").arg(browser.localItems.length)
            showRailToggle: !root.compact && root.canExpandRail
            railExpanded: root.railOpen
            onRailToggled: root.railExpanded = !root.railExpanded
            onCloseRequested: root.closeRequested()

            ClockIconButton {
                symbol: "refresh"
                tooltip: Translation.tr("Rescan the library")
                onClicked: MediatorService.refresh()
            }

            ClockIconButton {
                symbol: "fullscreen"
                tooltip: Translation.tr("Open as overlay")
                onClicked: root.overlayRequested()
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
                settingsOpen: browser.settingsOpen
                settingsTooltip: Translation.tr("Mediator settings")
                badges: root.badges
                onSelected: tabId => root.selectTab(tabId)
                onSettingsRequested: browser.settingsOpen ? browser.closeSettings() : browser.openSettings()

                Behavior on Layout.preferredWidth {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: ClockStyle.paneGap

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: ClockStyle.radiusLarge
                    color: ClockStyle.colPane
                    clip: true

                    MediatorBrowser {
                        id: browser
                        anchors { fill: parent; margins: ClockStyle.cardPadding }
                        overlay: false
                        focus: true
                        onCloseRequested: root.closeRequested()
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
}
