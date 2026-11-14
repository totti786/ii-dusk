import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.ii.dynamicIsland.core
import "panelFamilies"

// Owns the actual ii wallpaper and bars for the entire engine generation.
// The rest of the family is loaded later; it never replaces these windows.
Scope {
    id: root

    readonly property bool activeFamily: Config.ready && Config.options.panelFamily === "ii"
    property bool barExtraCondition: true
    readonly property bool usingWrappedFrame: Config.options.appearance.fakeScreenRounding === 3
    readonly property bool barBot: BarPlacement.bottom
    readonly property bool barVert: BarPlacement.vertical
    readonly property bool wallpaperReady: !Config.options.background.enable
        || Array.from(Quickshell.screens).every(screen => StartupState.wallpaperScreens.indexOf(screen.name) !== -1)

    readonly property bool firstFramesReady: Config.ready && (!activeFamily || (
        root.wallpaperReady
        && (!GlobalStates.barOpen || GlobalStates.connectModeActive || Array.from(GlobalStates.allowedScreens).every(
            screen => StartupState.barScreens.indexOf(screen.name) !== -1))
        && (!IslandPolicy.enabled || StartupState.islandReady)))

    onFirstFramesReadyChanged: {
        if (firstFramesReady) StartupState.finish();
    }

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        Wallpapers.load();
        ConflictKiller.load();
        Qt.callLater(root.updateBarExtraCondition);
        if (firstFramesReady) StartupState.finish();
    }

    // A missing wallpaper, hidden output or failed bar must not prevent Settings,
    // notification handling and recovery controls from becoming available.
    Timer {
        interval: 8000
        running: Config.ready && !StartupState.desktopReady
        onTriggered: {
            console.warn("[Startup] First-frame wait timed out; loading recovery controls");
            StartupState.finish();
        }
    }

    onUsingWrappedFrameChanged: updateBarExtraCondition()
    onBarBotChanged: updateBarExtraCondition()
    onBarVertChanged: updateBarExtraCondition()

    function updateBarExtraCondition() {
        if (!usingWrappedFrame) return;
        barExtraCondition = false;
        Qt.callLater(() => barExtraCondition = true);
    }

    BarPopupService {}

    PanelUrlLoader {
        extraCondition: root.activeFamily && Config.options.background.enable
        panelUrl: Qt.resolvedUrl("modules/ii/background/Background.qml")
        priority: 5
    }
    PanelUrlLoader {
        extraCondition: root.activeFamily && (root.wallpaperReady || StartupState.desktopReady) && !BarPlacement.vertical && root.barExtraCondition && !GlobalStates.connectModeActive
        panelUrl: Qt.resolvedUrl("modules/ii/bar/Bar.qml")
        priority: 4
    }
    PanelUrlLoader {
        extraCondition: root.activeFamily && (root.wallpaperReady || StartupState.desktopReady) && BarPlacement.vertical && root.barExtraCondition && !GlobalStates.connectModeActive
        panelUrl: Qt.resolvedUrl("modules/ii/verticalBar/VerticalBar.qml")
        priority: 4
    }
    PanelUrlLoader {
        extraCondition: root.activeFamily && (root.wallpaperReady || StartupState.desktopReady) && IslandPolicy.enabled
        panelUrl: Qt.resolvedUrl("modules/ii/dynamicIsland/DynamicIsland.qml")
        priority: 4
    }
}
