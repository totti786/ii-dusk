pragma Singleton

import QtQuick
import Quickshell
import qs.services
import qs.modules.common

/**
 * The colour of the song playing, as a Material 3 tonal set. The hue comes from the cover,
 * pulled a quarter of the way to the system accent so it never fights the wallpaper palette
 * (M3 "harmonize"); lightness comes from the fixed M3 tones, so every pair keeps its
 * contrast whatever the cover looked like. Light and dark themes read different tones.
 */
Singleton {
    id: root

    readonly property color source: MusicService.track?.color ? MusicService.track.color : Appearance.colors.colPrimary
    readonly property color accentSource: Appearance.colors.colPrimary
    // A grey cover has no hue worth keeping: fall back to the system accent
    readonly property bool grey: root.source.hslSaturation < 0.12
    readonly property color base: root.grey ? root.accentSource : Qt.tint(root.source, Qt.alpha(root.accentSource, 0.25))
    readonly property real hue: root.base.hslHue < 0 ? root.accentSource.hslHue : root.base.hslHue
    readonly property real sat: Math.max(0.32, Math.min(0.72, root.base.hslSaturation))
    readonly property bool dark: Appearance.m3colors.darkmode


    function tone(l, s = root.sat) {
        return Qt.hsla(root.hue, s, l, 1);
    }

    readonly property color primary: root.tone(root.dark ? 0.78 : 0.38)
    readonly property color onPrimary: root.tone(root.dark ? 0.16 : 0.97, 0.3)
    readonly property color container: root.tone(root.dark ? 0.27 : 0.88, root.sat * 0.8)
    readonly property color containerContent: root.tone(root.dark ? 0.9 : 0.14, 0.4)
    readonly property color surface: root.tone(root.dark ? 0.13 : 0.95, root.sat * 0.5)
    readonly property color surfaceHigh: root.tone(root.dark ? 0.2 : 0.91, root.sat * 0.55)
    readonly property color content: root.tone(root.dark ? 0.92 : 0.12, 0.15)
    readonly property color contentVariant: root.tone(root.dark ? 0.76 : 0.34, 0.2)
    readonly property color track: root.tone(root.dark ? 0.3 : 0.8, root.sat * 0.6)
}
