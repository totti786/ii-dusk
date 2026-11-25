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
import qs.modules.ii.panadoro.components
import qs.modules.ii.panadoro.tabs

/**
 * Panadoro inside its window. The same shell as the clock app — bar, rail, one live
 * page, a side sheet for editors, settings over the page — so moving between the
 * two apps never feels like changing applications.
 *
 * Only the visible tab exists. The focus timer does not: it lives in PanadoroService,
 * so closing this window leaves a running session running.
 */
FocusScope {
    id: root

    signal closeRequested()

    // ── Layout ──────────────────────────────────────────────────────────
    readonly property bool compact: root.width < PanadoroStyle.compactMax
    readonly property var appState: Persistent.states.panadoro
    readonly property bool canExpandRail: root.width >= PanadoroStyle.railExpandMin
    readonly property bool railExpanded: root.canExpandRail && (root.appState?.railExpanded ?? true)
    readonly property real railWidth: root.railExpanded ? PanadoroStyle.railExpandedWidth : PanadoroStyle.railCollapsedWidth
    readonly property real sheetWidth: root.compact
        ? root.width - PanadoroStyle.paneGap * 2
        : Math.max(PanadoroStyle.sheetWidthMin, Math.min(PanadoroStyle.sheetWidth, root.width * 0.28))
    // The width the page will have once the rail and the sheet have settled. Pages
    // lay themselves out against this, so opening a sheet slides the page narrower
    // instead of re-flowing it on every frame.
    readonly property real pageLayoutWidth: Math.max(0, root.width - PanadoroStyle.paneGap * 2
        - (root.compact ? 0 : root.railWidth + PanadoroStyle.paneGap)
        - (sidePanel.open && !root.compact ? root.sheetWidth + PanadoroStyle.paneGap : 0))
    readonly property bool wide: root.pageLayoutWidth >= PanadoroStyle.mediumMax

    // ── Tabs ────────────────────────────────────────────────────────────
    readonly property var tabs: [
        { id: "today", icon: "wb_sunny", label: Translation.tr("Today") },
        { id: "tasks", icon: "checklist", label: Translation.tr("Tasks") },
        { id: "focus", icon: "psychiatry", label: Translation.tr("Focus") },
        { id: "stats", icon: "monitoring", label: Translation.tr("Stats") },
        { id: "ranks", icon: "emoji_events", label: Translation.tr("Ranks") }
    ]
    readonly property var tabIds: root.tabs.map(tab => tab.id)
    readonly property var tabComponents: ({
        today: todayComponent,
        tasks: tasksComponent,
        focus: focusComponent,
        stats: statsComponent,
        ranks: ranksComponent
    })
    readonly property var tabActions: ({
        today: { label: Translation.tr("New habit"), symbol: "add_task" },
        tasks: { label: Translation.tr("New task"), symbol: "add" }
    })
    readonly property var currentAction: root.settingsOpen ? null : (root.tabActions[root.currentTab] ?? null)

    readonly property var badges: ({
        today: PanadoroService.todayHabitsTotal > 0
            ? String(PanadoroService.todayHabitsDone) + "/" + String(PanadoroService.todayHabitsTotal) : "",
        tasks: PanadoroService.openTaskCount > 0 ? String(PanadoroService.openTaskCount) : "",
        focus: PanadoroService.timerRunning ? "•" : "",
        stats: "",
        ranks: ""
    })

    property string currentTab: ""
    property string shownTab: ""
    property bool settingsOpen: false

    // ── Sync at a glance ────────────────────────────────────────────────
    readonly property string syncIcon: {
        if (!PanadoroService.signedIn)
            return "cloud_off";
        switch (PanadoroService.syncStatus) {
        case "synced": return "cloud_done";
        case "error": return "sync_problem";
        case "syncing": return "sync";
        default: return "cloud_sync";
        }
    }
    readonly property color syncColor: PanadoroService.syncStatus === "error"
        ? PanadoroStyle.colError
        : PanadoroService.syncStatus === "synced" ? PanadoroStyle.colSuccess : PanadoroStyle.colOnSurfaceVariant
    readonly property string syncTooltip: {
        if (!PanadoroService.signedIn)
            return Translation.tr("Sign in to sync between devices");
        if (PanadoroService.syncMessage.length > 0)
            return PanadoroService.syncMessage;
        return Translation.tr("Sync now");
    }

    // ── Time ────────────────────────────────────────────────────────────
    readonly property bool shown: root.Window.window?.visible ?? true

    onShownChanged: {
        if (root.shown) {
            Qt.callLater(() => root.forceActiveFocus());
        } else {
            sidePanel.closeNow();
            root.settingsOpen = false;
        }
    }

    Component.onCompleted: {
        root.currentTab = root.initialTab();
        root.shownTab = root.currentTab;
    }

    function initialTab(): string {
        const pending = GlobalStates.panadoroPendingTab;
        GlobalStates.panadoroPendingTab = "";
        if (root.tabIds.includes(pending))
            return pending;
        const last = root.appState?.tab ?? "today";
        return root.tabIds.includes(last) ? last : "today";
    }

    function selectTab(tabId: string): void {
        if (!root.tabIds.includes(tabId))
            return;
        root.settingsOpen = false;
        if (tabId !== root.currentTab)
            sidePanel.closeNow();
        root.currentTab = tabId;
        if (root.appState)
            root.appState.tab = tabId;
    }

    function toggleSettings(): void {
        sidePanel.closeNow();
        root.settingsOpen = !root.settingsOpen;
    }

    function triggerPrimaryAction(): void {
        const page = pageLoader.item;
        if (page && typeof page.primaryAction === "function")
            page.primaryAction();
    }

    function handleSync(): void {
        if (!PanadoroService.signedIn) {
            root.settingsOpen = true;
            return;
        }
        PanadoroService.syncNow();
    }

    // ── Celebration ─────────────────────────────────────────────────────
    property string celebrationMessage: ""
    property string celebrationSymbol: "celebration"
    property color celebrationColor: PanadoroStyle.colPrimary

    function showCelebration(message, symbol, color): void {
        celebrationLoader.active = false;
        root.celebrationMessage = String(message ?? "");
        root.celebrationSymbol = String(symbol ?? "celebration");
        root.celebrationColor = color ?? PanadoroStyle.colPrimary;
        Qt.callLater(() => celebrationLoader.active = true);
    }

    Connections {
        target: PanadoroService

        function onFocusCompleted(session) {
            const tag = PanadoroService.tagById(String(session?.tagId ?? "")) ?? PanadoroService.activeTag;
            root.showCelebration(
                Translation.tr("Focus complete · %1").arg(String(tag?.name ?? Translation.tr("Focus"))),
                "celebration",
                PanadoroStyle.tagColor(tag)
            );
        }

        function onAllHabitsCompleted(habit) {
            root.showCelebration(
                Translation.tr("Every habit done for today"),
                "local_fire_department",
                PanadoroStyle.colSuccess
            );
        }
    }

    onCurrentTabChanged: {
        if (root.currentTab === root.shownTab || root.shownTab.length === 0)
            return;
        if (PanadoroStyle.reducedMotion) {
            root.shownTab = root.currentTab;
            return;
        }
        tabSwitch.restart();
    }

    Connections {
        target: GlobalStates
        function onPanadoroPendingTabChanged() {
            const pending = GlobalStates.panadoroPendingTab;
            if (pending.length === 0)
                return;
            GlobalStates.panadoroPendingTab = "";
            root.selectTab(pending);
        }
    }

    // A sheet or field that owned the keyboard is destroyed on close; hand the keys
    // back so the app shortcuts keep working without a click.
    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            if (root.Window.window && !root.Window.window.activeFocusItem)
                Qt.callLater(() => root.forceActiveFocus());
        }
    }

    Connections {
        target: sidePanel
        function onClosed() {
            Qt.callLater(() => {
                if (pageLoader.item)
                    pageLoader.item.forceActiveFocus();
                else
                    root.forceActiveFocus();
            });
        }
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && event.key - Qt.Key_1 < root.tabIds.length) {
            root.selectTab(root.tabIds[event.key - Qt.Key_1]);
            event.accepted = true;
        } else if (ctrl && (event.key === Qt.Key_W || event.key === Qt.Key_Q)) {
            root.closeRequested();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_Comma) {
            root.toggleSettings();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_N && root.currentAction) {
            root.triggerPrimaryAction();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_E && root.currentTab === "focus"
            && pageLoader.item && typeof pageLoader.item.editTag === "function") {
            pageLoader.item.editTag(PanadoroService.activeTagId);
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && sidePanel.open) {
            sidePanel.close();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.settingsOpen) {
            root.settingsOpen = false;
            event.accepted = true;
        }
    }

    SequentialAnimation {
        id: tabSwitch

        NumberAnimation {
            target: pageHost
            property: "opacity"
            to: 0
            duration: PanadoroStyle.motionExit.duration / 2
            easing.type: Easing.BezierSpline
            easing.bezierCurve: PanadoroStyle.motionExit.bezierCurve
        }
        ScriptAction {
            script: {
                root.shownTab = root.currentTab;
                pageTranslate.y = PanadoroStyle.enterOffset;
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: pageHost
                property: "opacity"
                to: 1
                duration: PanadoroStyle.motionEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: PanadoroStyle.motionEnter.bezierCurve
            }
            NumberAnimation {
                target: pageTranslate
                property: "y"
                to: 0
                duration: PanadoroStyle.motionDefault.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: PanadoroStyle.motionDefault.bezierCurve
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: PanadoroStyle.colBackground
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: PanadoroStyle.paneGap
        anchors.topMargin: PanadoroStyle.gapTiny
        spacing: PanadoroStyle.gapTiny

        ClockTopBar {
            Layout.fillWidth: true
            title: root.settingsOpen
                ? Translation.tr("Settings")
                : (root.tabs.find(tab => tab.id === root.currentTab)?.label ?? "")
            subtitle: root.settingsOpen ? "" : (pageLoader.item?.subtitle ?? "")
            subtitleOpacity: pageHost.opacity
            showBack: root.settingsOpen
            showRailToggle: !root.compact && root.canExpandRail
            railExpanded: root.railExpanded
            onBackRequested: root.settingsOpen = false
            onRailToggled: {
                if (root.appState)
                    root.appState.railExpanded = !root.appState.railExpanded;
            }
            onCloseRequested: root.closeRequested()

            ClockChip {
                visible: PanadoroService.timerRunning
                symbol: PanadoroService.timerPhase === "focus" ? "psychiatry" : "coffee"
                label: PanadoroStyle.durationClock(PanadoroService.timerSecondsLeft)
                selected: PanadoroService.timerPhase === "focus"
                onClicked: root.selectTab("focus")
            }

            ClockIconButton {
                symbol: root.syncIcon
                tooltip: root.syncTooltip
                colIcon: root.syncColor
                onClicked: root.handleSync()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            ClockRail {
                Layout.fillHeight: true
                Layout.preferredWidth: root.railWidth
                Layout.rightMargin: PanadoroStyle.paneGap
                visible: !root.compact
                tabs: root.tabs
                currentTab: root.currentTab
                expanded: root.railExpanded
                settingsOpen: root.settingsOpen
                badges: root.badges
                settingsTooltip: Translation.tr("Settings")
                onSelected: tabId => root.selectTab(tabId)
                onSettingsRequested: root.toggleSettings()

                Behavior on Layout.preferredWidth {
                    animation: PanadoroStyle.motionFast.numberAnimation.createObject(this)
                }
            }

            ColumnLayout {
                id: pageColumn
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !(root.compact && sidePanel.open)
                spacing: PanadoroStyle.paneGap

                Item {
                    id: pageArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Item {
                        id: pageHost
                        anchors.fill: parent
                        transform: Translate {
                            id: pageTranslate
                        }

                        Loader {
                            id: pageLoader
                            anchors.fill: parent
                            focus: !root.settingsOpen && !sidePanel.open
                            sourceComponent: root.tabComponents[root.shownTab] ?? null
                        }
                    }

                    FloatingActionButton {
                        id: pageFab
                        readonly property bool shown: root.currentAction !== null
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: PanadoroStyle.gapLarge
                        anchors.bottomMargin: pageFab.shown ? PanadoroStyle.gapLarge : -pageFab.height - PanadoroStyle.gapHuge
                        z: 5
                        baseSize: PanadoroStyle.fabSizeLarge
                        iconSize: 34
                        buttonRadius: Appearance.rounding.large
                        buttonRadiusPressed: Appearance.rounding.normal
                        iconText: root.currentAction?.symbol ?? "add"
                        buttonText: root.currentAction?.label ?? ""
                        expanded: hovered
                        shortcut: "Ctrl\n+ N"
                        opacity: pageFab.shown ? 1 : 0
                        enabled: pageFab.shown
                        colBackground: PanadoroStyle.colPrimaryContainer
                        colBackgroundHover: PanadoroStyle.colPrimaryContainerHover
                        colBackgroundActive: PanadoroStyle.colPrimaryContainerActive
                        colRipple: PanadoroStyle.colPrimaryContainerActive
                        colOnBackground: PanadoroStyle.colOnPrimaryContainer
                        onClicked: root.triggerPrimaryAction()

                        Behavior on anchors.bottomMargin {
                            animation: PanadoroStyle.motionSpatial.numberAnimation.createObject(this)
                        }
                        Behavior on opacity {
                            animation: PanadoroStyle.motionFast.numberAnimation.createObject(this)
                        }

                        StyledToolTip {
                            text: (root.currentAction?.label ?? "") + " (Ctrl+N)"
                        }
                    }

                    Loader {
                        id: settingsLoader
                        property real progress: root.settingsOpen ? 1 : 0

                        anchors.fill: parent
                        active: root.settingsOpen || progress > 0
                        visible: progress > 0
                        z: 10

                        opacity: progress
                        Behavior on progress {
                            enabled: !PanadoroStyle.reducedMotion
                            NumberAnimation {
                                duration: root.settingsOpen ? PanadoroStyle.motionEnter.duration : PanadoroStyle.motionExit.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: root.settingsOpen ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel
                            }
                        }

                        sourceComponent: PanadoroSettingsPage {
                            compact: root.compact
                            wide: root.wide
                            layoutWidth: root.pageLayoutWidth
                            panels: sidePanel
                        }

                        transform: Translate {
                            x: (1 - settingsLoader.progress) * Math.min(pageArea.width * 0.1, 96)
                        }
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

            // ── Side sheet ──────────────────────────────────────────────
            Item {
                id: sheetSlot
                Layout.fillHeight: true
                Layout.preferredWidth: sidePanel.open ? root.sheetWidth + (root.compact ? 0 : PanadoroStyle.paneGap) : 0
                visible: Layout.preferredWidth > 1
                clip: true

                Behavior on Layout.preferredWidth {
                    enabled: !PanadoroStyle.reducedMotion
                    animation: PanadoroStyle.motionDefault.numberAnimation.createObject(this)
                }

                ClockSidePanel {
                    id: sidePanel
                    anchors {
                        top: parent.top
                        bottom: parent.bottom
                        right: parent.right
                    }
                    width: root.sheetWidth
                }
            }
        }
    }

    Loader {
        id: celebrationLoader
        anchors.fill: parent
        z: 200
        active: false
        sourceComponent: Component {
            PanadoroCelebration {
                message: root.celebrationMessage
                symbol: root.celebrationSymbol
                colAccent: root.celebrationColor
                onFinished: celebrationLoader.active = false
            }
        }
    }

    Component {
        id: todayComponent
        PanadoroTodayTab {
            layoutWidth: root.pageLayoutWidth
            compact: root.compact
            wide: root.wide
            panels: sidePanel
        }
    }

    Component {
        id: tasksComponent
        PanadoroTasksTab {
            layoutWidth: root.pageLayoutWidth
            compact: root.compact
            wide: root.wide
            panels: sidePanel
        }
    }

    Component {
        id: focusComponent
        PanadoroFocusTab {
            layoutWidth: root.pageLayoutWidth
            compact: root.compact
            wide: root.wide
            panels: sidePanel
        }
    }

    Component {
        id: statsComponent
        PanadoroStatsTab {
            layoutWidth: root.pageLayoutWidth
            compact: root.compact
            wide: root.wide
            panels: sidePanel
        }
    }

    Component {
        id: ranksComponent
        PanadoroRanksTab {
            layoutWidth: root.pageLayoutWidth
            compact: root.compact
            wide: root.wide
            panels: sidePanel
            onSettingsRequested: root.settingsOpen = true
        }
    }
}
