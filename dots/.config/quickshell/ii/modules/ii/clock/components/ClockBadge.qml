import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * A Material shape carrying a glyph: the mark of a section, a device or a page. The glyph is
 * half the badge whatever its size, so every badge has the same proportions.
 */
MaterialShapeWrappedMaterialSymbol {
    id: root

    property real size: 52

    iconSize: Math.round(root.size * 0.5)
    padding: (root.size - root.iconSize) / 2
    fill: 1
    color: ClockStyle.colSecondaryContainer
    colSymbol: ClockStyle.colOnSecondaryContainer
}
