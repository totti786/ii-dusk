pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * Qanun's extra colour vocabulary on top of ClockStyle: tuning states, the
 * two metronome rings, the qanun wood and the waveform.
 */
Singleton {
    id: root

    readonly property color colBackground: ClockStyle.colBackground
    readonly property color colPane: ClockStyle.colPane
    readonly property color colSheet: ClockStyle.colSheet
    readonly property color colOnSurface: ClockStyle.colOnSurface
    readonly property color colOnSurfaceVariant: ClockStyle.colOnSurfaceVariant
    readonly property color colSubtext: ClockStyle.colSubtext
    readonly property color colPrimary: ClockStyle.colPrimary
    readonly property color colOnPrimary: ClockStyle.colOnPrimary
    readonly property color colPrimaryContainer: ClockStyle.colPrimaryContainer
    readonly property color colOnPrimaryContainer: ClockStyle.colOnPrimaryContainer
    readonly property color colSecondaryContainer: ClockStyle.colSecondaryContainer
    readonly property color colOnSecondaryContainer: ClockStyle.colOnSecondaryContainer
    readonly property color colTertiary: ClockStyle.colTertiary
    readonly property color colTertiaryContainer: ClockStyle.colTertiaryContainer
    readonly property color colOnTertiaryContainer: ClockStyle.colOnTertiaryContainer
    readonly property color colError: ClockStyle.colError
    readonly property color colOnError: ClockStyle.colOnError
    readonly property color colField: ClockStyle.colField
    readonly property color colFieldHover: ClockStyle.colFieldHover
    readonly property color colOutline: ClockStyle.colOutline

    readonly property color colInTune: Appearance.m3colors.m3success
    readonly property color colClose: Appearance.m3colors.m3tertiary
    readonly property color colOffPitch: Appearance.m3colors.m3error
    readonly property color colGraph: Appearance.colors.colPrimary
    readonly property color colGraphFill: Qt.alpha(Appearance.colors.colPrimary, 0.16)
    readonly property color colTrackPulse: Appearance.colors.colPrimary
    readonly property color colTrackSubdivision: Appearance.colors.colTertiary
    readonly property color colBeatActive: Appearance.colors.colPrimary
    readonly property color colBeatIdle: Appearance.colors.colSecondaryContainer
    readonly property color colWaveform: Appearance.colors.colPrimary

    // The qanun body is intentionally warmer than the surface palette so the
    // diagram reads as an instrument rather than another card.
    readonly property color colWood: Qt.alpha(ColorUtils.mix(Appearance.m3colors.m3surfaceContainerHigh,
        Appearance.m3colors.m3primary, 0.22), 0.92)
    readonly property color colWoodLight: ColorUtils.mix(root.colWood, Appearance.m3colors.m3surfaceContainerHighest, 0.34)
    readonly property color colWoodDark: ColorUtils.mix(root.colWood, Appearance.m3colors.m3background, 0.38)
    readonly property color colString: Qt.alpha(Appearance.m3colors.m3onSurface, 0.58)
    readonly property color colMandala: Appearance.colors.colTertiary
    readonly property color colMandalOff: ColorUtils.mix(Appearance.colors.colOnSurfaceVariant,
        ClockStyle.colPane, 0.58)
    readonly property color colSelectedString: Appearance.colors.colPrimary

    function tuningColor(cents, threshold = 5): color {
        const value = Math.abs(Number(cents) || 0);
        if (value <= Number(threshold))
            return root.colInTune;
        if (value <= Math.max(15, Number(threshold) * 2.5))
            return root.colClose;
        return root.colOffPitch;
    }

    function tuningWord(cents, threshold = 5): string {
        const value = Number(cents) || 0;
        if (Math.abs(value) <= Number(threshold))
            return Translation.tr("In tune");
        return value > 0 ? Translation.tr("Sharp") : Translation.tr("Flat");
    }

    function centsLabel(cents): string {
        const value = Number(cents) || 0;
        return (value > 0 ? "+" : "") + value.toFixed(1) + " ¢";
    }
}
