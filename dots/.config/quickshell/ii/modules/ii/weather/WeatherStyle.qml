pragma Singleton

import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Every colour, radius, size and motion token of the weather app.
 *
 * The app is deliberately built on the same Material 3 tokens as the rest of ii, so
 * switching theme or wallpaper changes the weather window with everything else. The
 * only weather-specific colours are the condition accents, which are always mixed back
 * into a surface colour so they never become a second, competing theme.
 */
Singleton {
    id: root

    // ── Surfaces ────────────────────────────────────────────────────────
    readonly property color colBackground: Appearance.colors.colLayer0
    // App windows are opaque even when panels are translucent: text behind a floating
    // forecast makes every number ambiguous. The tint still comes from the theme.
    readonly property color colWindow: Appearance.colors.colLayer0Base
    readonly property color colOnBackground: Appearance.colors.colOnLayer0
    readonly property color colSurface: Appearance.colors.colSurfaceContainerLow
    readonly property color colSurfaceHigh: Appearance.colors.colSurfaceContainerHigh
    readonly property color colSurfaceHighest: Appearance.colors.colSurfaceContainerHighest
    readonly property color colSurfaceHover: Appearance.colors.colSurfaceContainerHighestHover
    readonly property color colSurfaceActive: Appearance.colors.colSurfaceContainerHighestActive
    readonly property color colOnSurface: Appearance.colors.colOnSurface
    readonly property color colOnSurfaceVariant: Appearance.colors.colOnSurfaceVariant
    readonly property color colSubtext: Appearance.colors.colSubtext
    readonly property color colOutline: Appearance.colors.colOutlineVariant
    readonly property color colScrim: Appearance.colors.colScrim

    // Panes: the rail and the location sheet are slabs one step above the window, the
    // way the clock and notes apps build theirs.
    readonly property color colPane: Appearance.colors.colLayer1
    readonly property color colPaneHover: Appearance.colors.colLayer1Hover
    readonly property color colPaneActive: Appearance.colors.colLayer1Active
    readonly property color colSheet: Appearance.m3colors.m3surfaceContainerHigh
    readonly property color colField: Appearance.m3colors.m3surfaceContainerHighest
    readonly property color colFieldHover: Appearance.colors.colSurfaceContainerHighestHover

    // ── Accents ─────────────────────────────────────────────────────────
    readonly property color colPrimary: Appearance.colors.colPrimary
    readonly property color colPrimaryHover: Appearance.colors.colPrimaryHover
    readonly property color colPrimaryActive: Appearance.colors.colPrimaryActive
    readonly property color colOnPrimary: Appearance.colors.colOnPrimary
    readonly property color colPrimaryContainer: Appearance.colors.colPrimaryContainer
    readonly property color colPrimaryContainerHover: Appearance.colors.colPrimaryContainerHover
    readonly property color colPrimaryContainerActive: Appearance.colors.colPrimaryContainerActive
    readonly property color colOnPrimaryContainer: Appearance.colors.colOnPrimaryContainer
    readonly property color colSecondary: Appearance.colors.colSecondary
    readonly property color colOnSecondary: Appearance.colors.colOnSecondary
    readonly property color colSecondaryContainer: Appearance.colors.colSecondaryContainer
    readonly property color colSecondaryContainerHover: Appearance.colors.colSecondaryContainerHover
    readonly property color colSecondaryContainerActive: Appearance.colors.colSecondaryContainerActive
    readonly property color colOnSecondaryContainer: Appearance.colors.colOnSecondaryContainer
    readonly property color colTertiary: Appearance.colors.colTertiary
    readonly property color colOnTertiary: Appearance.colors.colOnTertiary
    readonly property color colTertiaryContainer: Appearance.colors.colTertiaryContainer
    readonly property color colTertiaryContainerHover: Appearance.colors.colTertiaryContainerHover
    readonly property color colTertiaryContainerActive: Appearance.colors.colTertiaryContainerActive
    readonly property color colOnTertiaryContainer: Appearance.colors.colOnTertiaryContainer
    readonly property color colError: Appearance.colors.colError
    readonly property color colOnError: Appearance.colors.colOnError
    readonly property color colErrorContainer: Appearance.colors.colErrorContainer
    readonly property color colErrorContainerHover: Appearance.colors.colErrorContainerHover
    readonly property color colErrorContainerActive: Appearance.colors.colErrorContainerActive
    readonly property color colOnErrorContainer: Appearance.colors.colOnErrorContainer
    readonly property color colSuccess: Appearance.m3colors.m3success
    readonly property color colSuccessContainer: Appearance.m3colors.m3successContainer
    readonly property color colOnSuccessContainer: Appearance.m3colors.m3onSuccessContainer

    // ── Shape ───────────────────────────────────────────────────────────
    readonly property real radiusSmall: Appearance.rounding.small
    readonly property real radiusNormal: Appearance.rounding.normal
    readonly property real radiusLarge: Appearance.rounding.large
    readonly property real radiusExtraLarge: Appearance.rounding.verylarge
    readonly property real radiusFull: Appearance.rounding.full
    readonly property real radiusCard: Appearance.rounding.verylarge
    readonly property real radiusTile: Appearance.rounding.normal
    readonly property real radiusKey: Appearance.rounding.full
    readonly property real radiusKeyPressed: Appearance.rounding.normal

    // A badge shape per kind of section, so a page of panes is not a column of identical
    // cookies. Anything unknown falls back to the clock family's default.
    function shapeFor(icon) {
        switch (icon) {
        case "schedule": return MaterialShape.Shape.Clover4Leaf;
        case "calendar_month":
        case "calendar_today": return MaterialShape.Shape.Cookie12Sided;
        case "thermostat":
        case "device_thermostat": return MaterialShape.Shape.Pill;
        case "air": return MaterialShape.Shape.SoftBurst;
        case "wb_twilight":
        case "wb_sunny":
        case "bedtime": return MaterialShape.Shape.Sunny;
        case "water_drop":
        case "rainy": return MaterialShape.Shape.Puffy;
        case "cloud": return MaterialShape.Shape.Flower;
        case "settings":
        case "tune": return MaterialShape.Shape.Cookie9Sided;
        default: return MaterialShape.Shape.Cookie9Sided;
        }
    }

    function pill(height) {
        return Math.min(height / 2, root.radiusFull);
    }

    // ── Type ────────────────────────────────────────────────────────────
    readonly property string fontMain: Appearance.font.family.main
    readonly property string fontTitle: Appearance.font.family.title
    readonly property string fontNumbers: Appearance.font.family.numbers
    // Canvas resolves font families before QML's fallback: pick one the system actually
    // has, so chart text renders instead of logging a missing-family warning per label.
    readonly property string chartFont: {
        const installed = Qt.fontFamilies();
        if (installed.indexOf(Appearance.font.family.main) >= 0)
            return Appearance.font.family.main;
        if (installed.indexOf("Noto Sans") >= 0)
            return "Noto Sans";
        return "Sans Serif";
    }
    readonly property string fontExpressive: Appearance.font.family.expressive
    readonly property var axesTitle: Appearance.font.variableAxes.titleRounded
    readonly property var axesDigits: ({ "wght": 560, "wdth": 30, "ROND": 100 })
    readonly property var axesDigitsBold: ({ "wght": 760, "wdth": 40, "ROND": 100 })
    readonly property int textTiny: Appearance.font.pixelSize.smaller
    readonly property int textSmall: Appearance.font.pixelSize.small
    readonly property int textNormal: Appearance.font.pixelSize.normal
    readonly property int textLarge: Appearance.font.pixelSize.large
    readonly property int textTitle: Appearance.font.pixelSize.huge
    readonly property int textDisplay: Appearance.font.pixelSize.larger * 3
    readonly property real iconSmall: Appearance.font.pixelSize.normal
    readonly property real iconNormal: Appearance.font.pixelSize.larger + 3
    readonly property real iconLarge: Appearance.font.pixelSize.huge + 6
    readonly property real iconDisplay: Appearance.font.pixelSize.huge + 28

    // ── Spacing (4 px grid) ─────────────────────────────────────────────
    readonly property int gapTiny: 4
    readonly property int gapSmall: 8
    readonly property int gap: 12
    readonly property int gapLarge: 16
    readonly property int gapHuge: 24
    readonly property int pagePadding: 16
    readonly property int pagePaddingWide: 24
    readonly property int cardPadding: 20
    readonly property int sectionSpacing: 16

    // ── Sizes ───────────────────────────────────────────────────────────
    readonly property int iconButton: 40
    readonly property int chipHeight: 36
    readonly property int buttonHeight: 44
    readonly property int topBarHeight: 64
    readonly property int railExpandedWidth: 228
    readonly property int railCollapsedWidth: 76
    readonly property int railRowHeight: 52
    readonly property int paneGap: 12
    readonly property int panePadding: 10
    readonly property int sheetWidth: 380
    readonly property int sheetWidthMin: 320
    readonly property int windowMinWidth: 420
    readonly property int windowMinHeight: 560
    readonly property int metricTileMinWidth: 168
    readonly property int chartCardMinWidth: 300
    readonly property int chartHeight: 208
    readonly property int hourlyCardWidth: 86
    readonly property int hourlyCardHeight: 142

    // ── Breakpoints ─────────────────────────────────────────────────────
    readonly property int compactMax: 720
    readonly property int mediumMax: 980
    readonly property int railExpandMin: 1080
    readonly property int chartTwoColumnMin: 760

    // ── Motion ──────────────────────────────────────────────────────────
    readonly property var motionFast: Appearance.animation.elementMoveFast
    readonly property var motionSpatial: Appearance.animation.elementMoveSmall
    readonly property var motionDefault: Appearance.animation.elementMove
    readonly property var motionEnter: Appearance.animation.elementMoveEnter
    readonly property var motionExit: Appearance.animation.elementMoveExit
    readonly property bool reducedMotion: Appearance.reducedMotion
    readonly property int staggerStep: 36
    readonly property real enterOffset: 20

    // ── Tone helpers ────────────────────────────────────────────────────
    function toneColor(tone) {
        switch (tone) {
        case "secondary": return root.colSecondary;
        case "tertiary": return root.colTertiary;
        case "error": return root.colError;
        case "success": return root.colSuccess;
        case "neutral": return root.colOnSurfaceVariant;
        default: return root.colPrimary;
        }
    }

    function toneContainer(tone) {
        switch (tone) {
        case "secondary": return root.colSecondaryContainer;
        case "tertiary": return root.colTertiaryContainer;
        case "error": return root.colErrorContainer;
        case "success": return root.colSuccessContainer;
        case "neutral": return root.colSurfaceHighest;
        default: return root.colPrimaryContainer;
        }
    }

    function toneOnContainer(tone) {
        switch (tone) {
        case "secondary": return root.colOnSecondaryContainer;
        case "tertiary": return root.colOnTertiaryContainer;
        case "error": return root.colOnErrorContainer;
        case "success": return root.colOnSuccessContainer;
        case "neutral": return root.colOnSurfaceVariant;
        default: return root.colOnPrimaryContainer;
        }
    }

    // Charts are the one place where adjacent series need to be told apart at a glance.
    // The theme palette is the default; when the Material theme is nearly monochrome the
    // user can opt into weather hues without changing the rest of the app's surfaces.
    readonly property bool vividCharts: WeatherAppService.settings.accentMode === "vivid"

    function chartColor(tone) {
        if (!root.vividCharts) {
            // A pure Material theme can be monochrome (Google's neutral scheme), which
            // makes every chart line the same off-white. Tint a weather hue with the
            // theme colour so series stay distinguishable and still change with the theme.
            const weather = {
                "primary": "#4f9bd9",
                "secondary": "#a27bd4",
                "tertiary": "#d99648",
                "error": "#d96b6b",
                "success": "#6fbf8a",
                "neutral": "#9aa4ad"
            }[tone] || "#4f9bd9";
            return ColorUtils.mix(root.toneColor(tone), weather, 0.5);
        }
        switch (tone) {
        case "secondary": return "#b39ddb";
        case "tertiary": return "#ffb86b";
        case "error": return "#ff8a80";
        case "success": return "#8bd5a3";
        case "neutral": return "#cfd8dc";
        default: return "#82b1ff";
        }
    }

    function aqiTone(aqi) {
        if (aqi === null || aqi === undefined || !Number.isFinite(Number(aqi)))
            return "neutral";
        const value = Number(aqi);
        if (value <= 50) return "success";
        if (value <= 100) return "primary";
        if (value <= 150) return "tertiary";
        return "error";
    }

    function uvTone(uv) {
        if (uv === null || uv === undefined || !Number.isFinite(Number(uv)))
            return "neutral";
        const value = Number(uv);
        if (value < 3) return "success";
        if (value < 6) return "primary";
        if (value < 8) return "tertiary";
        return "error";
    }

    function rainTone(chance) {
        if (chance === null || chance === undefined || !Number.isFinite(Number(chance)))
            return "neutral";
        const value = Number(chance);
        if (value >= 70) return "error";
        if (value >= 40) return "tertiary";
        if (value >= 15) return "primary";
        return "secondary";
    }

    // The tone a condition speaks in. Hero, badges and the big shape all follow it, so the
    // window changes character with the weather while every colour is still a theme role.
    function conditionTone(code, isDay) {
        const c = Number(code);
        if (c >= 95) return "error";
        if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82)) return "secondary";
        if (c === 45 || c === 48) return "tertiary";
        if (c >= 71 && c <= 86) return "primary";
        if (c === 0 || c === 1) return isDay ? "primary" : "tertiary";
        return "secondary";
    }

    // The shape the condition wears: sun rays for clear, a soft cookie for cloud, a puff
    // for rain, a flower for snow, a burst for storms, a pill for fog.
    function conditionShape(code, isDay) {
        const c = Number(code);
        if (c >= 95) return MaterialShape.Shape.Burst;
        if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82)) return MaterialShape.Shape.Puffy;
        if (c === 45 || c === 48) return MaterialShape.Shape.Pill;
        if (c >= 71 && c <= 86) return MaterialShape.Shape.Flower;
        if (c === 0 || c === 1) return isDay ? MaterialShape.Shape.Sunny : MaterialShape.Shape.Cookie9Sided;
        return MaterialShape.Shape.Cookie12Sided;
    }

    function conditionAccent(code, isDay) {
        const c = Number(code);
        if (c >= 95) return root.colError;
        if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82)) return root.colSecondary;
        if (c === 45 || c === 48) return root.colTertiary;
        if (c >= 71 && c <= 86) return root.colPrimary;
        if (c === 0 || c === 1) return isDay ? root.colPrimary : root.colTertiary;
        return root.colSecondary;
    }

    // The hero is a wash, not a poster: the condition colour is mixed into the window
    // surface, and the second stop is the same family one step further away.
    function heroStops(code, isDay) {
        const accent = root.conditionAccent(code, isDay);
        return [
            ColorUtils.mix(root.colSurface, accent, 0.26),
            ColorUtils.mix(root.colSurface, root.colSurfaceHigh, 0.42),
            root.colSurface
        ];
    }

    function heroTextColor(code, isDay) {
        const base = root.heroStops(code, isDay)[0];
        return ColorUtils.getContrastingTextColor(base);
    }

    function alpha(color, value) {
        return ColorUtils.applyAlpha(color, value);
    }

    // ── Provider presentation ──────────────────────────────────────────
    function providerIcon(id) {
        switch (id) {
        case "metNo": return "public";
        case "openWeatherMap": return "cloud_circle";
        case "weatherApi": return "api";
        case "pirateWeather": return "sailing";
        case "accuWeather": return "storm";
        case "infoplaza": return "public";
        case "brightSky": return "wb_sunny";
        default: return "cloud";
        }
    }

    function providerShortName(id) {
        switch (id) {
        case "openMeteo": return "Open-Meteo";
        case "metNo": return "MET Norway";
        case "openWeatherMap": return "OpenWeatherMap";
        case "weatherApi": return "WeatherAPI.com";
        case "pirateWeather": return "Pirate Weather";
        case "accuWeather": return "AccuWeather";
        case "infoplaza": return "Infoplaza";
        case "brightSky": return "Bright Sky (DWD)";
        default: return id;
        }
    }
}
