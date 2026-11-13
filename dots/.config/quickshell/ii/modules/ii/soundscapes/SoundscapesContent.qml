pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "components"
import "pages"

/**
 * The ambient mixer inside its window, on the clock app's frame: top bar, rail, page and a
 * side sheet. The mix itself lives in a daemon (SoundscapesService), so closing the window
 * never stops the sound; a floating dock keeps it in reach on every page.
 */
FocusScope {
    id: root

    signal closeRequested()

    readonly property bool compact: root.width < ClockStyle.compactMax
    readonly property bool canExpandRail: root.width >= ClockStyle.railExpandMin
    property bool railExpanded: true
    readonly property bool railOpen: root.canExpandRail && root.railExpanded
    readonly property real railWidth: root.railOpen ? ClockStyle.railExpandedWidth : ClockStyle.railCollapsedWidth
    readonly property real sheetWidth: root.compact
        ? Math.max(0, root.width - ClockStyle.paneGap * 2)
        : Math.max(ClockStyle.sheetWidthMin, Math.min(ClockStyle.sheetWidth, root.width * 0.3))
    readonly property real pageLayoutWidth: Math.max(0, root.width - ClockStyle.paneGap * 2
        - (root.compact ? 0 : root.railWidth + ClockStyle.paneGap)
        - (sidePanel.open && !root.compact ? root.sheetWidth + ClockStyle.paneGap : 0))
    readonly property bool shown: root.Window.window?.visible ?? true

    readonly property var tabs: [
        { id: "sounds", icon: "waves", label: Translation.tr("Sounds") },
        { id: "mix", icon: "tune", label: Translation.tr("Mix") },
        { id: "presets", icon: "bookmark_stacks", label: Translation.tr("Mixes") }
    ]
    readonly property var tabIds: root.tabs.map(tab => tab.id)
    readonly property var badges: ({
        sounds: "",
        mix: SoundscapesService.activeCount > 0 ? String(SoundscapesService.activeCount) : "",
        presets: ""
    })

    property string currentTab: "sounds"
    property bool settingsOpen: false

    readonly property string pageTitle: root.settingsOpen ? Translation.tr("Settings")
        : root.tabs.find(tab => tab.id === root.currentTab)?.label ?? ""
    readonly property string pageSubtitle: {
        if (root.settingsOpen)
            return Translation.tr("Where the sounds live");
        switch (root.currentTab) {
        case "mix": return SoundscapesService.hasMix ? Translation.tr("What is playing, and how loud") : Translation.tr("Nothing is playing");
        case "presets": return Translation.tr("Ready-made and saved mixes");
        default: return Translation.tr("%1 to layer").arg(SoundscapesService.countLabel(SoundscapesService.sounds.length));
        }
    }

    function selectTab(tabId: string): void {
        if (!root.tabIds.includes(tabId))
            return;
        sidePanel.closeNow();
        root.settingsOpen = false;
        root.currentTab = tabId;
    }

    function toggleSettings(): void {
        sidePanel.closeNow();
        root.settingsOpen = !root.settingsOpen;
    }

    function initialTab(): string {
        const pending = GlobalStates.soundscapesPendingTab;
        GlobalStates.soundscapesPendingTab = "";
        if (pending === "settings") {
            root.settingsOpen = true;
            return "sounds";
        }
        if (root.tabIds.includes(pending))
            return pending;
        const configured = Config.options.soundscapes?.startTab ?? "sounds";
        return root.tabIds.includes(configured) ? configured : "sounds";
    }

    Component.onCompleted: {
        root.currentTab = root.initialTab();
        root.consumePendingSound();
        if (root.shown)
            SoundscapesService.retain();
    }
    Component.onDestruction: if (root.shown) SoundscapesService.release()

    onShownChanged: {
        if (root.shown) {
            SoundscapesService.retain();
            Qt.callLater(() => root.forceActiveFocus());
        } else {
            SoundscapesService.release();
            sidePanel.closeNow();
        }
    }

    function consumePendingSound(): void {
        const id = GlobalStates.soundscapesPendingSound;
        GlobalStates.soundscapesPendingSound = "";
        if (id.length > 0 && SoundscapesService.sound(id))
            Qt.callLater(() => root.showInfo(id));
    }

    Connections {
        target: GlobalStates
        function onSoundscapesPendingSoundChanged() {
            if (GlobalStates.soundscapesPendingSound.length > 0)
                root.consumePendingSound();
        }
        function onSoundscapesPendingTabChanged() {
            const pending = GlobalStates.soundscapesPendingTab;
            if (pending.length === 0)
                return;
            GlobalStates.soundscapesPendingTab = "";
            if (pending === "settings") {
                sidePanel.closeNow();
                root.settingsOpen = true;
            } else {
                root.selectTab(pending);
            }
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
        } else if (event.key === Qt.Key_Space && !ctrl) {
            SoundscapesService.togglePlay();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && sidePanel.open) {
            sidePanel.close();
            event.accepted = true;
        }
    }

    function showInfo(soundId: string): void {
        sidePanel.show(infoComponent, { soundId: soundId });
    }

    function promptSave(): void {
        sidePanel.show(saveComponent, {});
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
            title: root.pageTitle
            subtitle: root.pageSubtitle
            showRailToggle: !root.compact && root.canExpandRail
            railExpanded: root.railOpen
            onRailToggled: root.railExpanded = !root.railExpanded
            onCloseRequested: root.closeRequested()

            ClockIconButton {
                visible: root.compact
                symbol: "settings"
                tooltip: Translation.tr("Settings")
                toggled: root.settingsOpen
                onClicked: root.toggleSettings()
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
                currentTab: root.settingsOpen ? "" : root.currentTab
                expanded: root.railOpen
                settingsOpen: root.settingsOpen
                settingsTooltip: Translation.tr("Settings")
                badges: root.badges
                onSelected: tabId => root.selectTab(tabId)
                onSettingsRequested: root.toggleSettings()

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
                        id: pageLoader
                        anchors.fill: parent
                        sourceComponent: root.settingsOpen ? settingsComponent
                            : root.currentTab === "mix" ? mixComponent
                            : root.currentTab === "presets" ? presetsComponent : soundsComponent
                        onSourceComponentChanged: if (!ClockStyle.reducedMotion) pageFade.restart()
                        NumberAnimation {
                            id: pageFade
                            target: pageLoader
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: 220
                            easing.type: Easing.OutCubic
                        }
                    }

                    NowPlayingDock {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                            margins: ClockStyle.gap
                        }
                        compact: root.compact
                        shown: SoundscapesService.hasMix && root.currentTab !== "mix" && !root.settingsOpen
                        onOpenMix: root.selectTab("mix")
                    }
                }

                ClockNavigation {
                    Layout.fillWidth: true
                    visible: root.compact
                    tabs: root.tabs
                    currentTab: root.settingsOpen ? "" : root.currentTab
                    onSelected: tabId => root.selectTab(tabId)
                }
            }

            // The side sheet's slot animates its width; the sheet inside keeps its own width
            // pinned to the right, so it slides in instead of reflowing.
            Item {
                id: sheetSlot
                Layout.fillHeight: true
                Layout.preferredWidth: sidePanel.open ? root.sheetWidth + (root.compact ? 0 : ClockStyle.paneGap) : 0
                visible: Layout.preferredWidth > 1
                clip: true

                Behavior on Layout.preferredWidth {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
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

    Connections {
        target: sidePanel
        function onClosed() {
            Qt.callLater(() => root.forceActiveFocus());
        }
    }

    Component {
        id: soundsComponent
        SoundsPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            onInfoRequested: soundId => root.showInfo(soundId)
        }
    }
    Component {
        id: mixComponent
        MixPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            onBrowseRequested: root.selectTab("sounds")
            onSaveRequested: root.promptSave()
        }
    }
    Component {
        id: presetsComponent
        PresetsPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            onSaveRequested: root.promptSave()
        }
    }
    Component {
        id: settingsComponent
        SoundscapesSettingsPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
        }
    }
    Component {
        id: infoComponent
        SoundInfoSheet {}
    }
    Component {
        id: saveComponent
        ClockTextPromptSheet {
            title: Translation.tr("Save this mix")
            subtitle: Translation.tr("It keeps these sounds and their volumes")
            caption: Translation.tr("Name")
            placeholder: Translation.tr("Rainy Sunday")
            symbol: "bookmark"
            confirmLabel: Translation.tr("Save")
            onSubmitted: text => {
                if (text.length > 0)
                    SoundscapesService.savePreset(text);
            }
        }
    }
}
