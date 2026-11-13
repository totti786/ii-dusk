pragma Singleton

import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Grit's design tokens.
 *
 * The shell's Material palette supplies the surfaces; this file adds the one thing
 * the app needs on top of them: an accent per focus tag, resolved to a filled
 * colour, a tinted container and a readable foreground. A tag can name a palette
 * role ("primary", "tertiary", "success") or carry its own hex colour, and every
 * shape in the app — rail badges, timer ring, bars, confetti — asks here instead
 * of hard-coding a hue.
 */
Singleton {
    id: root

    // ── Surfaces ────────────────────────────────────────────────────────
    readonly property color colBackground: Appearance.colors.colLayer0
    readonly property color colOnBackground: Appearance.colors.colOnLayer0
    readonly property color colPane: Appearance.colors.colLayer1
    readonly property color colSurface: Appearance.colors.colSurfaceContainerLow
    readonly property color colSurfaceHigh: Appearance.colors.colSurfaceContainerHigh
    readonly property color colField: Appearance.colors.colSurfaceContainerHighest
    readonly property color colFieldHover: Appearance.colors.colSurfaceContainerHighestHover
    readonly property color colOnSurface: Appearance.colors.colOnSurface
    readonly property color colOnSurfaceVariant: Appearance.colors.colOnSurfaceVariant
    readonly property color colSubtext: Appearance.colors.colSubtext
    readonly property color colOutline: Appearance.colors.colOutlineVariant
    readonly property color colOutlineStrong: Appearance.colors.colOutline

    // ── Core accents ────────────────────────────────────────────────────
    readonly property color colPrimary: Appearance.colors.colPrimary
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
    readonly property color colOnTertiaryContainer: Appearance.colors.colOnTertiaryContainer
    readonly property color colError: Appearance.colors.colError
    readonly property color colOnError: Appearance.colors.colOnError
    readonly property color colErrorContainer: Appearance.colors.colErrorContainer
    readonly property color colErrorContainerHover: Appearance.colors.colErrorContainerHover
    readonly property color colOnErrorContainer: Appearance.colors.colOnErrorContainer
    readonly property color colSuccess: Appearance.m3colors.m3success
    readonly property color colOnSuccess: Appearance.m3colors.m3onSuccess
    readonly property color colSuccessContainer: Appearance.m3colors.m3successContainer
    readonly property color colOnSuccessContainer: Appearance.m3colors.m3onSuccessContainer

    // ── Type ────────────────────────────────────────────────────────────
    readonly property string fontMain: Appearance.font.family.main
    readonly property string fontTitle: Appearance.font.family.title
    readonly property string fontNumbers: Appearance.font.family.numbers
    readonly property string fontExpressive: Appearance.font.family.expressive
    readonly property var axesDigits: ({ "wght": 620, "wdth": 35, "ROND": 100 })
    readonly property var axesDigitsBold: ({ "wght": 780, "wdth": 45, "ROND": 100 })
    readonly property var axesDisplay: ({ "wght": 480, "wdth": 100, "ROND": 100 })
    readonly property var axesTitle: Appearance.font.variableAxes.titleRounded
    readonly property int textSmall: Appearance.font.pixelSize.smaller
    readonly property int textNormal: Appearance.font.pixelSize.small
    readonly property int textLarge: Appearance.font.pixelSize.large
    readonly property int textTitle: Appearance.font.pixelSize.huge
    readonly property real iconSmall: Appearance.font.pixelSize.normal
    readonly property real iconNormal: Appearance.font.pixelSize.larger + 3
    readonly property real iconLarge: Appearance.font.pixelSize.huge + 6

    // ── Spacing ─────────────────────────────────────────────────────────
    readonly property int gapTiny: 4
    readonly property int gapSmall: 8
    readonly property int gap: 12
    readonly property int gapLarge: 16
    readonly property int gapHuge: 24
    readonly property int pagePadding: 16
    readonly property int pagePaddingWide: 24
    readonly property int cardPadding: 18

    // ── Sizes ───────────────────────────────────────────────────────────
    readonly property int iconButton: 40
    readonly property int buttonHeight: 42
    readonly property int chipHeight: 36
    readonly property int rowHeight: 54
    readonly property int fabSize: 64
    readonly property int fabSizeLarge: 88
    readonly property int navBarHeight: 76
    readonly property int topBarHeight: 64
    readonly property int paneGap: 12
    readonly property int panePadding: 10
    readonly property int railExpandedWidth: 222
    readonly property int railCollapsedWidth: 76
    readonly property int sheetWidth: 360
    readonly property int sheetWidthMin: 300
    readonly property int windowMinWidth: 380
    readonly property int windowMinHeight: 520
    readonly property int compactMax: 700
    readonly property int mediumMax: 900
    readonly property int railExpandMin: 1080
    readonly property int fabClearance: 104
    readonly property int heroMinHeight: 128

    // ── Shape ───────────────────────────────────────────────────────────
    readonly property real radiusSmall: Appearance.rounding.small
    readonly property real radiusNormal: Appearance.rounding.normal
    readonly property real radiusLarge: Appearance.rounding.large
    readonly property real radiusExtraLarge: Appearance.rounding.verylarge
    readonly property real radiusFull: Appearance.rounding.full
    readonly property real radiusCard: Appearance.rounding.verylarge

    function pill(height) {
        return Math.min(height / 2, root.radiusFull);
    }

    readonly property var shapeNames: [
        "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Cookie4Sided",
        "Flower", "Sunny", "VerySunny", "SoftBurst", "Burst", "Clover4Leaf",
        "Clover8Leaf", "Heart", "Gem", "Diamond", "Pentagon", "Ghostish"
    ]

    readonly property var shapeMap: ({
        "Cookie4Sided": MaterialShape.Shape.Cookie4Sided,
        "Cookie6Sided": MaterialShape.Shape.Cookie6Sided,
        "Cookie7Sided": MaterialShape.Shape.Cookie7Sided,
        "Cookie9Sided": MaterialShape.Shape.Cookie9Sided,
        "Cookie12Sided": MaterialShape.Shape.Cookie12Sided,
        "Flower": MaterialShape.Shape.Flower,
        "Sunny": MaterialShape.Shape.Sunny,
        "VerySunny": MaterialShape.Shape.VerySunny,
        "SoftBurst": MaterialShape.Shape.SoftBurst,
        "Burst": MaterialShape.Shape.Burst,
        "Clover4Leaf": MaterialShape.Shape.Clover4Leaf,
        "Clover8Leaf": MaterialShape.Shape.Clover8Leaf,
        "Heart": MaterialShape.Shape.Heart,
        "Gem": MaterialShape.Shape.Gem,
        "Diamond": MaterialShape.Shape.Diamond,
        "Pentagon": MaterialShape.Shape.Pentagon,
        "Ghostish": MaterialShape.Shape.Ghostish
    })

    function shapeValue(name) {
        return root.shapeMap[String(name ?? "")] ?? MaterialShape.Shape.Cookie7Sided;
    }

    // ── Palette roles ───────────────────────────────────────────────────
    readonly property var accentNames: [
        { id: "primary", label: Translation.tr("Primary") },
        { id: "secondary", label: Translation.tr("Secondary") },
        { id: "tertiary", label: Translation.tr("Tertiary") },
        { id: "success", label: Translation.tr("Green") },
        { id: "error", label: Translation.tr("Red") },
        { id: "outline", label: Translation.tr("Neutral") }
    ]

    function isHex(value) {
        return /^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(String(value ?? "").trim());
    }

    function accent(name) {
        switch (String(name ?? "")) {
        case "secondary": return root.colSecondary;
        case "tertiary": return root.colTertiary;
        case "success": return root.colSuccess;
        case "error": return root.colError;
        case "outline": return root.colOnSurfaceVariant;
        default: return root.colPrimary;
        }
    }

    function accentContainer(name) {
        switch (String(name ?? "")) {
        case "secondary": return root.colSecondaryContainer;
        case "tertiary": return root.colTertiaryContainer;
        case "success": return root.colSuccessContainer;
        case "error": return root.colErrorContainer;
        case "outline": return root.colField;
        default: return root.colPrimaryContainer;
        }
    }

    function accentOn(name) {
        switch (String(name ?? "")) {
        case "secondary": return root.colOnSecondaryContainer;
        case "tertiary": return root.colOnTertiaryContainer;
        case "success": return root.colOnSuccessContainer;
        case "error": return root.colOnErrorContainer;
        case "outline": return root.colOnSurface;
        default: return root.colOnPrimaryContainer;
        }
    }

    function accentOnSolid(name) {
        switch (String(name ?? "")) {
        case "secondary": return root.colOnSecondary;
        case "success": return root.colOnSuccess;
        case "error": return root.colOnError;
        case "outline": return root.colBackground;
        default: return root.colOnPrimary;
        }
    }

    // ── Tag accents ─────────────────────────────────────────────────────
    function customTagColor(tag) {
        if (tag && root.isHex(tag.color))
            return Qt.color(String(tag.color).trim());
        return null;
    }

    function tagColor(tag) {
        return root.customTagColor(tag) ?? root.accent(tag?.accent ?? "primary");
    }

    function tagContainer(tag) {
        const custom = root.customTagColor(tag);
        if (custom)
            return ColorUtils.mix(custom, root.colSurface, 0.24);
        return root.accentContainer(tag?.accent ?? "primary");
    }

    /** A low-key wash of the tag's colour for unselected chips and task rows. */
    function tagSoftContainer(tag) {
        return ColorUtils.mix(root.tagColor(tag), root.colSurface, 0.13);
    }

    function tagOn(tag) {
        const custom = root.customTagColor(tag);
        if (custom)
            return ColorUtils.mostReadable(root.tagContainer(tag), [root.colOnSurface, custom]);
        return root.accentOn(tag?.accent ?? "primary");
    }

    function tagOnSolid(tag) {
        const custom = root.customTagColor(tag);
        if (custom)
            return ColorUtils.mostReadable(custom, [root.colOnSurface, "#FFFFFF"]);
        return root.accentOnSolid(tag?.accent ?? "primary");
    }

    function tagShape(tag) {
        return root.shapeValue(String(tag?.shape ?? "Cookie7Sided"));
    }

    function tagIcon(tag) {
        return String(tag?.icon ?? "local_fire_department");
    }

    function categoryColor(category) {
        return root.accent(category?.accent ?? "outline");
    }

    function categoryContainer(category) {
        return root.accentContainer(category?.accent ?? "outline");
    }

    function categoryOn(category) {
        return root.accentOn(category?.accent ?? "outline");
    }

    function durationShort(minutes) {
        const value = Math.max(0, Math.round(Number(minutes ?? 0)));
        if (value < 60)
            return String(value) + "m";
        const hours = Math.floor(value / 60);
        const rest = value % 60;
        return rest === 0 ? String(hours) + "h" : String(hours) + "h " + String(rest) + "m";
    }

    function durationClock(seconds) {
        const total = Math.max(0, Math.round(Number(seconds ?? 0)));
        const minutes = Math.floor(total / 60);
        const rest = total % 60;
        return String(minutes).padStart(2, "0") + ":" + String(rest).padStart(2, "0");
    }

    // ── Motion ──────────────────────────────────────────────────────────
    readonly property var motionFast: Appearance.animation.elementMoveFast
    readonly property var motionSpatial: Appearance.animation.elementMoveSmall
    readonly property var motionDefault: Appearance.animation.elementMove
    readonly property var motionEnter: Appearance.animation.elementMoveEnter
    readonly property var motionExit: Appearance.animation.elementMoveExit
    readonly property bool reducedMotion: Appearance.reducedMotion
    readonly property int staggerStep: 32
    readonly property real enterOffset: 20
}
