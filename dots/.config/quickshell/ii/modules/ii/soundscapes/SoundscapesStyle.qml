pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.ii.clock.components

/**
 * What the Soundscapes app adds to the clock app's tokens: the three tone families a sound
 * can wear (primary, secondary, tertiary container), so the library is colourful without
 * leaving the wallpaper's palette, and the shape each badge morphs into when it is on.
 */
Singleton {
    id: root

    function container(tone) {
        return tone === 1 ? ClockStyle.colSecondaryContainer : tone === 2 ? ClockStyle.colTertiaryContainer : ClockStyle.colPrimaryContainer;
    }
    function containerHover(tone) {
        return tone === 1 ? ClockStyle.colSecondaryContainerHover : tone === 2 ? ClockStyle.colTertiaryContainerHover : ClockStyle.colPrimaryContainerHover;
    }
    function onContainer(tone) {
        return tone === 1 ? ClockStyle.colOnSecondaryContainer : tone === 2 ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnPrimaryContainer;
    }
    function accent(tone) {
        return tone === 1 ? Appearance.colors.colSecondary : tone === 2 ? ClockStyle.colTertiary : ClockStyle.colPrimary;
    }
    function onAccent(tone) {
        return tone === 1 ? Appearance.colors.colOnSecondary : tone === 2 ? ClockStyle.colOnTertiary : ClockStyle.colOnPrimary;
    }

    /// The shape a badge turns into when its sound is on: a relative of its resting shape.
    readonly property var morphs: ({
        "Cookie9Sided": "Cookie12Sided",
        "Cookie12Sided": "Sunny",
        "Clover4Leaf": "Clover8Leaf",
        "SoftBurst": "Burst",
        "Pentagon": "Gem",
        "Sunny": "VerySunny"
    })
    function morphOf(name) {
        return root.morphs[name] ?? "SoftBurst";
    }

    readonly property int tileMinWidth: 172
    readonly property int tileHeight: 176
    /// Room a page keeps under its last row while the now-playing dock floats over it.
    readonly property int dockClearance: 104
}
