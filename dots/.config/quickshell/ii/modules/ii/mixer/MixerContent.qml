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
 * The mixer inside its window, built from the clock app's parts so it reads as one of the
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
        { id: "playback", icon: "volume_up", label: Translation.tr("Playback") },
        { id: "recording", icon: "mic", label: Translation.tr("Recording") },
        { id: "devices", icon: "speaker_group", label: Translation.tr("Devices") },
        { id: "config", icon: "tune", label: Translation.tr("Configuration") }
    ]
    readonly property var tabIds: root.tabs.map(tab => tab.id)
    readonly property var badges: ({
        playback: Audio.outputAppNodes.length > 0 ? String(Audio.outputAppNodes.length) : "",
        recording: Audio.inputAppNodes.length > 0 ? String(Audio.inputAppNodes.length) : "",
        devices: "",
        config: ""
    })

    property string currentTab: "playback"
    readonly property bool shown: root.Window.window?.visible ?? true

    function selectTab(tabId: string): void {
        if (root.tabIds.includes(tabId))
            root.currentTab = tabId;
    }

    function consumePendingTab(): void {
        const pending = GlobalStates.mixerPendingTab;
        GlobalStates.mixerPendingTab = "";
        if (root.tabIds.includes(pending))
            root.selectTab(pending);
    }

    function subtitleFor(tabId: string): string {
        switch (tabId) {
        case "playback": return Translation.tr("Volume for each app that is playing sound");
        case "recording": return Translation.tr("Volume for each app that is listening");
        case "devices": return Translation.tr("Pick the default speakers and microphone");
        default: return Translation.tr("Profiles of your sound cards");
        }
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
        function onMixerPendingTabChanged() {
            if (GlobalStates.mixerPendingTab.length > 0)
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
            subtitle: root.subtitleFor(root.currentTab)
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
                        sourceComponent: root.currentTab === "playback" ? playbackComponent
                            : root.currentTab === "recording" ? recordingComponent
                            : root.currentTab === "devices" ? devicesComponent : configComponent
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
        id: playbackComponent
        MixerStreamsPage {
            output: true
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
        }
    }

    Component {
        id: recordingComponent
        MixerStreamsPage {
            output: false
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
        }
    }

    Component {
        id: devicesComponent
        MixerDevicesPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
        }
    }

    Component {
        id: configComponent
        MixerCardsPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            active: root.shown
        }
    }
}
