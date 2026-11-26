import qs.modules.common
import QtQuick
import qs.services

StyledText {
    id: root
    property real iconSize: Appearance?.font.pixelSize.small ?? 16
    property real fill: 0
    // Keep the font on a complete outlined or filled glyph. Fractional FILL
    // values during animation can drop internal paths in Qt's variable-font
    // renderer after a parent scale transform.
    readonly property real truncatedFill: root.fill >= 0.5 ? 1 : 0
    // The optical size snaps to Material's four standard sizes: every distinct value opens a
    // new face of the font (an mmap of the whole file), and icon sizes animate.
    readonly property int opticalSize: root.iconSize < 22 ? 20 : root.iconSize < 32 ? 24 : root.iconSize < 44 ? 40 : 48

    // True while this symbol or any ancestor is scaled or rotated (popup scale
    // multiplier, rotating shapes). The binding reads every ancestor's
    // scale/rotation/parent, so it follows animations and reparenting.
    readonly property bool transformed: {
        for (let p = root; p; p = p.parent) {
            if (p.scale !== undefined && (Math.abs(p.scale - 1) > 0.001 || p.rotation % 360 !== 0))
                return true;
        }
        return false;
    }

    // NativeRendering gives the crispest glyph at its real size, but rasterizes
    // before transforms: a scale stretches that bitmap into jagged steps.
    // CurveRendering evaluates the outline at the final on-screen size, so it is
    // used only under a transform — untransformed its small-size antialiasing
    // wobbles. QtRendering's distance field drops contours from filled glyphs
    // (`devices`, `settings`), so it is never used here.
    renderType: root.transformed ? Text.CurveRendering : Text.NativeRendering
    antialiasing: true
    smooth: true
    horizontalAlignment: Text.AlignHCenter

    // Arrows that mean "back", "next", "undo" and so on point the wrong way in a right-to-left
    // layout. Layout mirroring moves items but never flips a glyph, so these are flipped here.
    // Media transport (play, skip), anything that rotates, and the absolute-direction glyphs
    // (west, east, arrow_upward/downward, arrow_left/right) are deliberately not in the list.
    readonly property var directionalIcons: ({
        "arrow_back": 1, "arrow_forward": 1, "arrow_back_ios": 1, "arrow_back_ios_new": 1, "arrow_forward_ios": 1,
        "chevron_left": 1, "chevron_right": 1,
        "navigate_before": 1, "navigate_next": 1, "keyboard_arrow_left": 1, "keyboard_arrow_right": 1,
        "keyboard_double_arrow_left": 1, "keyboard_double_arrow_right": 1, "first_page": 1, "last_page": 1,
        "undo": 1, "redo": 1, "reply": 1, "subdirectory_arrow_right": 1, "subdirectory_arrow_left": 1,
        "arrow_circle_left": 1, "arrow_circle_right": 1, "line_start": 1, "line_end": 1
    })
    /** False where the layout around the glyph stays left-to-right, such as a pager. */
    property bool mirrorInRtl: true
    readonly property bool flipForRtl: root.mirrorInRtl && root.LayoutMirroring.enabled && root.directionalIcons[root.text] === 1
    transform: Scale {
        xScale: root.flipForRtl ? -1 : 1
        origin.x: root.width / 2
    }

    font {
        hintingPreference: Font.PreferNoHinting
        family: Appearance?.font.family.iconMaterial ?? "Material Symbols Rounded"
        pixelSize: iconSize
        weight: Font.Normal
        variableAxes: ({
                "FILL": parseFloat(root.truncatedFill),
                "wght": 400,
                "opsz": root.opticalSize
            })
    }

    Behavior on fill {
        NumberAnimation {
            duration: Appearance?.animation.elementMoveFast.duration ?? 200
            easing.type: Appearance?.animation.elementMoveFast.type ?? Easing.BezierSpline
            easing.bezierCurve: Appearance?.animation.elementMoveFast.bezierCurve ?? [0.34, 0.80, 0.34, 1.00, 1, 1]
        }
    }
}

