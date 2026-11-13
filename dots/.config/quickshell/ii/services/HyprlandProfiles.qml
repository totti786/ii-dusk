pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "HyprlandProfiles.js" as Profiles

// Profiles only reset keys from the profile being released, so entering Lite or
// Game Mode never erases another profile's values. The marker line is the source
// of truth for game mode, and only an explicit Game Mode release removes it.
Singleton {
    id: root

    readonly property bool lite: PanelFamily.isLite
    readonly property bool reduceMotion: (Config.options?.appearance?.reduceMotion ?? false)
        || Appearance.powerSaverMotionOff
    property bool gameModeActive: false
    property bool overridesLoaded: false

    FileView {
        id: overridesFile
        path: HyprlandConfig.shellOverridesPath
        blockLoading: true
        watchChanges: true
        printErrors: false

        onLoaded: {
            if (root.overridesLoaded)
                return;
            root.gameModeActive = overridesFile.text().includes(Profiles.GAME_MODE_RULE_MARKER);
            root.overridesLoaded = true;
            root.apply(null, false);
        }
    }

    function apply(resetScope, releaseGameMode) {
        releaseGameMode = releaseGameMode === true;
        const result = Profiles.plan({
            lite: root.lite,
            reduceMotion: root.reduceMotion,
            gameMode: root.gameModeActive
        }, resetScope, releaseGameMode);
        if (Object.keys(result.set).length === 0 && result.reset.length === 0
                && result.addLines.length === 0 && result.removeMatching.length === 0)
            return;
        HyprlandConfig.applyOverrides(result.set, result.reset, {
            addLines: result.addLines,
            removeMatching: result.removeMatching
        });
    }

    function setGameMode(on) {
        root.gameModeActive = !!on;
        if (root.gameModeActive)
            root.apply(Profiles.GAME_MODE_KEYS, false);
        else
            root.apply(Profiles.GAME_MODE_KEYS, true);
    }

    function clearGameMode() {
        root.gameModeActive = false;
        root.apply(Profiles.GAME_MODE_KEYS, true);
    }

    // Both are called from the change signal of what they depend on. At that moment this singleton's
    // own binding to the same setting may not have been re-evaluated yet, so planning right away used
    // the previous value: turning Reduce motion on changed nothing, and turning it off switched
    // Hyprland's animations off. Waiting for the event loop lets the bindings settle first.
    function syncPanelFamily() {
        Qt.callLater(() => root.apply(Profiles.LITE_KEYS, false));
    }

    function syncReduceMotion() {
        Qt.callLater(() => root.apply(["animations:enabled"], false));
    }
}
