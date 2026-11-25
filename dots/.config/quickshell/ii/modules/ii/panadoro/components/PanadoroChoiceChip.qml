import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A choice chip for filters and pickers (period, repeat, priority, colour): a quiet tonal
 * pill while unchosen, the secondary container once chosen. Separation comes from the fill,
 * never from an outline.
 */
Rectangle {
    id: root

    property string label: ""
    property string symbol: ""
    property bool selected: false
    /// Override both on a surface where the secondary container would vanish, such as a hero.
    property color colSelected: PanadoroStyle.colSecondaryContainer
    property color colOnSelected: PanadoroStyle.colOnSecondaryContainer

    signal triggered()

    readonly property color colContent: root.selected ? root.colOnSelected : PanadoroStyle.colOnSurfaceVariant

    implicitWidth: chipRow.implicitWidth + PanadoroStyle.gapLarge * 2
    implicitHeight: PanadoroStyle.chipHeight - 2
    radius: PanadoroStyle.pill(implicitHeight)
    color: root.selected ? root.colSelected
        : pointer.containsMouse ? PanadoroStyle.colFieldHover : PanadoroStyle.colField

    Behavior on color {
        animation: PanadoroStyle.motionFast.colorAnimation.createObject(this)
    }

    RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: PanadoroStyle.gapTiny

        MaterialSymbol {
            visible: root.symbol.length > 0
            text: root.symbol
            iconSize: Appearance.font.pixelSize.normal
            fill: root.selected ? 1 : 0
            color: root.colContent
        }

        StyledText {
            text: root.label
            font.pixelSize: PanadoroStyle.textNormal
            font.weight: Font.Bold
            color: root.colContent
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.triggered()
    }
}
