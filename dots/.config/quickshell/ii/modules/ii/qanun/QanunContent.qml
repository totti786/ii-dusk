pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.qanun
import qs.modules.ii.qanun.tabs
import qs.modules.ii.qanun.components

/**
 * Qanun inside its window: the same rail, top bar and responsive page area as
 * the shell's other apps, with six destinations. Only the visible tab exists, so
 * the tuner's microphone process and the metronome's click timer stop when you
 * leave their page.
 */
FocusScope {
    id: root

    signal closeRequested()

    readonly property bool compact: root.width < ClockStyle.compactMax
    readonly property bool canExpandRail: root.width >= ClockStyle.railExpandMin
    readonly property var appState: QanunStore.normalized.ui ?? ({ tab: "tuner", railExpanded: true })
    readonly property bool railExpanded: root.canExpandRail && (root.appState.railExpanded ?? true)
    readonly property real railWidth: root.railExpanded ? ClockStyle.railExpandedWidth : ClockStyle.railCollapsedWidth
    readonly property real pageLayoutWidth: Math.max(0, root.width - ClockStyle.paneGap * 2
        - (root.compact ? 0 : root.railWidth + ClockStyle.paneGap))
    readonly property bool wide: root.pageLayoutWidth >= ClockStyle.mediumMax

    readonly property var tabs: [
        { id: "tuner", icon: "tune", label: Translation.tr("Tuner") },
        { id: "metronome", icon: "speed", label: Translation.tr("Metronome") },
        { id: "scales", icon: "auto_awesome", label: Translation.tr("Maqams & scales") },
        { id: "library", icon: "library_music", label: Translation.tr("Sheet music") },
        { id: "tracks", icon: "graphic_eq", label: Translation.tr("Tracks") },
        { id: "flashcards", icon: "school", label: Translation.tr("Flashcards") },
        { id: "earTraining", icon: "hearing", label: Translation.tr("Ear training") }
    ]
    readonly property var tabIds: root.tabs.map(tab => tab.id)
    readonly property var tabComponents: ({
        tuner: tunerComponent,
        metronome: metronomeComponent,
        scales: scalesComponent,
        library: libraryComponent,
        tracks: tracksComponent,
        flashcards: flashcardsComponent,
        earTraining: earTrainingComponent
    })
    readonly property var badges: ({
        tracks: AudioRecorderService.recording
            ? (AudioRecorderService.paused ? "Ⅱ" : "•") : "",
        flashcards: Number(QanunStore.stats.streak ?? 0) > 0
            ? String(QanunStore.stats.streak) : "",
        earTraining: Number(QanunStore.earStats.streak ?? 0) > 0
            ? String(QanunStore.earStats.streak) : ""
    })

    property string currentTab: "tuner"
    property string shownTab: ""
    property bool settingsOpen: false
    property string startupTab: ""

    readonly property var currentTabInfo: root.tabs.find(tab => tab.id === root.shownTab) ?? root.tabs[0]

    function initialTab(): string {
        const startup = String(root.startupTab ?? "");
        const chosen = root.tabIds.includes(startup) ? startup
            : root.tabIds.includes(GlobalStates.qanunPendingTab) ? GlobalStates.qanunPendingTab
            : root.tabIds.includes(String(root.appState.tab ?? "")) ? String(root.appState.tab)
            : "tuner";
        GlobalStates.qanunPendingTab = "";
        return chosen;
    }

    function selectTab(tabId: string): void {
        if (!root.tabIds.includes(tabId))
            return;
        QanunStore.stopAllAudio();
        root.settingsOpen = false;
        if (tabId === root.currentTab)
            return;
        root.currentTab = tabId;
        QanunStore.setUi("tab", tabId);
    }

    function currentPage(): var {
        return pageLoader.item;
    }

    Component.onCompleted: {
        root.currentTab = root.initialTab();
        root.shownTab = root.currentTab;
        root.forceActiveFocus();
    }

    onCurrentTabChanged: {
        if (root.currentTab === root.shownTab)
            return;
        if (Appearance.reducedMotion) {
            root.shownTab = root.currentTab;
            return;
        }
        tabSwitch.restart();
    }

    Connections {
        target: GlobalStates
        function onQanunPendingTabChanged() {
            const pending = GlobalStates.qanunPendingTab;
            if (pending.length === 0)
                return;
            GlobalStates.qanunPendingTab = "";
            root.selectTab(pending);
        }
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_9
                && event.key - Qt.Key_1 < root.tabIds.length) {
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

    SequentialAnimation {
        id: tabSwitch

        NumberAnimation {
            target: pageHost
            property: "opacity"
            to: 0
            duration: ClockStyle.motionExit.duration / 2
            easing.type: Easing.BezierSpline
            easing.bezierCurve: ClockStyle.motionExit.bezierCurve
        }
        ScriptAction {
            script: {
                root.shownTab = root.currentTab;
                pageTranslate.y = ClockStyle.enterOffset;
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: pageHost
                property: "opacity"
                to: 1
                duration: ClockStyle.motionEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: ClockStyle.motionEnter.bezierCurve
            }
            NumberAnimation {
                target: pageTranslate
                property: "y"
                to: 0
                duration: ClockStyle.motionDefault.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: ClockStyle.motionDefault.bezierCurve
            }
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

        QanunTopBar {
            Layout.fillWidth: true
            title: root.settingsOpen ? Translation.tr("Qanun settings") : (root.currentTabInfo?.label ?? "Qanun")
            subtitle: root.settingsOpen ? "" : (pageLoader.item?.pageSubtitle ?? "")
            showBack: root.settingsOpen
            showRailToggle: !root.compact && root.canExpandRail
            railExpanded: root.railExpanded
            onBackRequested: root.settingsOpen = false
            onRailToggled: QanunStore.setUi("railExpanded", !root.railExpanded)
            onCloseRequested: root.closeRequested()

            ClockIconButton {
                symbol: "volume_off"
                tooltip: Translation.tr("Stop all audio")
                onClicked: QanunStore.stopAllAudio()
            }
            ClockIconButton {
                symbol: "help"
                tooltip: Translation.tr("Qanun is a tuner, metronome, maqam reference, library, recorder and note trainer")
                onClicked: root.settingsOpen = true
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
                expanded: root.railExpanded
                settingsOpen: root.settingsOpen
                badges: root.badges
                settingsTooltip: Translation.tr("Qanun settings")
                onSelected: tabId => root.selectTab(tabId)
                onSettingsRequested: root.settingsOpen = !root.settingsOpen

                Behavior on Layout.preferredWidth {
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }
            }

            ColumnLayout {
                id: pageColumn
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: ClockStyle.paneGap

                Item {
                    id: pageArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Item {
                        id: pageHost
                        anchors.fill: parent
                        transform: Translate { id: pageTranslate }

                        Loader {
                            id: pageLoader
                            anchors.fill: parent
                            focus: !root.settingsOpen
                            sourceComponent: root.tabComponents[root.shownTab] ?? null
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
                        sourceComponent: QanunSettingsPage {
                            compact: root.compact
                            wide: root.wide
                            layoutWidth: root.pageLayoutWidth
                            onCloseRequested: root.settingsOpen = false
                        }
                        Behavior on progress {
                            enabled: !Appearance.reducedMotion
                            NumberAnimation {
                                duration: root.settingsOpen ? ClockStyle.motionEnter.duration : ClockStyle.motionExit.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: root.settingsOpen ? Appearance.animationCurves.emphasizedDecel
                                    : Appearance.animationCurves.emphasizedAccel
                            }
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
        }
    }

    Component {
        id: tunerComponent
        TunerTab {
            compact: root.compact
            wide: root.wide
        }
    }

    Component {
        id: metronomeComponent
        MetronomeTab {
            compact: root.compact
            wide: root.wide
        }
    }

    Component {
        id: scalesComponent
        ScalesTab {
            compact: root.compact
            wide: root.wide
        }
    }

    Component {
        id: libraryComponent
        LibraryTab {
            compact: root.compact
            wide: root.wide
        }
    }

    Component {
        id: tracksComponent
        TracksTab {
            compact: root.compact
            wide: root.wide
        }
    }

    Component {
        id: flashcardsComponent
        FlashcardsTab {
            compact: root.compact
            wide: root.wide
        }
    }

    Component {
        id: earTrainingComponent
        EarTrainingTab {
            compact: root.compact
            wide: root.wide
        }
    }
}
