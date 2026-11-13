pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One key of the keypad, in the Material roles the clock's buttons use:
 * "digit" on the layer above the window, "operator" tonal, "clear" tonal too, "equals" filled
 * with the primary, and "function" a quieter surface for the scientific keys.
 * A key can be `selected` (2nd, the angle unit): it fills with the primary container.
 */
RippleButton {
    id: root

    property string label: ""
    property string symbol: ""
    property string role: "digit"
    property bool selected: false
    /// Lit while its keyboard shortcut is typed, so typing reads like pressing the key.
    property bool flashed: false
    property real labelSize: ClockStyle.textLarge

    // "clear" keys share the tonal role with operators: the error container is reserved for
    // destructive actions, and in this palette it reads as an alarm on a calculator.
    readonly property bool tonal: root.role === "operator" || root.role === "clear"
    readonly property bool quiet: root.role === "function"
    readonly property color colContainer: root.selected ? ClockStyle.colPrimaryContainer
        : root.role === "equals" ? ClockStyle.colPrimary
        : root.tonal ? ClockStyle.colSecondaryContainer
        : root.quiet ? ClockStyle.colSurfaceHigh
        : ClockStyle.colField
    readonly property color colContainerHover: root.selected ? ClockStyle.colPrimaryContainerHover
        : root.role === "equals" ? ClockStyle.colPrimaryHover
        : root.tonal ? ClockStyle.colSecondaryContainerHover
        : root.quiet ? ClockStyle.colSurfaceHover
        : ClockStyle.colFieldHover
    readonly property color colContainerActive: root.selected ? ClockStyle.colPrimaryContainerActive
        : root.role === "equals" ? ClockStyle.colPrimaryActive
        : root.tonal ? ClockStyle.colSecondaryContainerActive
        : ClockStyle.colSurfaceActive
    readonly property color colContent: root.selected ? ClockStyle.colOnPrimaryContainer
        : root.role === "equals" ? ClockStyle.colOnPrimary
        : root.tonal ? ClockStyle.colOnSecondaryContainer
        : root.quiet ? ClockStyle.colOnSurfaceVariant
        : ClockStyle.colOnSurface

    focusPolicy: Qt.NoFocus
    buttonRadius: Math.min(height / 2, ClockStyle.radiusKey)
    buttonRadiusPressed: ClockStyle.radiusKeyPressed
    colBackground: root.flashed ? root.colContainerActive : root.colContainer
    colBackgroundHover: root.flashed ? root.colContainerActive : root.colContainerHover
    colBackgroundActive: root.colContainerActive
    colRipple: root.colContainerActive
    scale: root.down || root.flashed ? 0.95 : 1

    Behavior on scale {
        enabled: !ClockStyle.reducedMotion
        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
    }

    contentItem: Item {
        StyledText {
            anchors.centerIn: parent
            visible: root.symbol.length === 0
            text: root.label
            font.family: ClockStyle.fontNumbers
            font.variableAxes: ClockStyle.axesDigits
            font.pixelSize: root.labelSize
            color: root.colContent
        }
        MaterialSymbol {
            anchors.centerIn: parent
            visible: root.symbol.length > 0
            text: root.symbol
            iconSize: root.labelSize + 2
            color: root.colContent
        }
    }
}
