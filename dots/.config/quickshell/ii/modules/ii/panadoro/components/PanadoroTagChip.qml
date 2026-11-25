import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.panadoro.components

/** A focus tag as a filter chip: its own shape, its own colour, its own name. */
RippleButton {
    id: root

    property var tag: null
    property bool selected: false
    property string trailingText: ""

    readonly property color colTag: PanadoroStyle.tagColor(root.tag)
    readonly property color colContainer: root.selected
        ? PanadoroStyle.tagContainer(root.tag) : PanadoroStyle.tagSoftContainer(root.tag)
    readonly property color colOn: root.selected
        ? PanadoroStyle.tagOn(root.tag) : PanadoroStyle.colOnSurface

    implicitHeight: PanadoroStyle.chipHeight
    implicitWidth: chipRow.implicitWidth + PanadoroStyle.gapLarge * 2
    buttonRadius: root.selected ? PanadoroStyle.radiusNormal : PanadoroStyle.pill(PanadoroStyle.chipHeight)
    buttonRadiusPressed: PanadoroStyle.radiusSmall
    colBackground: root.colContainer
    colBackgroundHover: root.selected
        ? PanadoroStyle.tagContainer(root.tag)
        : ColorUtils.mix(root.colTag, PanadoroStyle.colSurface, 0.2)
    colRipple: root.selected ? PanadoroStyle.tagContainer(root.tag) : PanadoroStyle.tagSoftContainer(root.tag)

    contentItem: RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: PanadoroStyle.gapSmall

        Item {
            implicitWidth: 22
            implicitHeight: 22

            MaterialShape {
                anchors.fill: parent
                shapeString: String(root.tag?.shape ?? "Cookie7Sided")
                color: root.selected ? root.colTag : ColorUtils.applyAlpha(root.colTag, 0.85)
                rotation: root.selected ? 12 : 0

                Behavior on rotation {
                    enabled: !PanadoroStyle.reducedMotion
                    NumberAnimation {
                        duration: PanadoroStyle.motionDefault.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: PanadoroStyle.motionDefault.bezierCurve
                    }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: PanadoroStyle.tagIcon(root.tag)
                iconSize: 14
                fill: 1
                color: root.selected
                    ? ColorUtils.mostReadable(root.colTag, [PanadoroStyle.colOnPrimary, PanadoroStyle.colBackground])
                    : ColorUtils.mostReadable(root.colTag, [PanadoroStyle.colOnSurface, PanadoroStyle.colBackground])
            }
        }

        StyledText {
            text: String(root.tag?.name ?? "")
            font.pixelSize: PanadoroStyle.textNormal
            font.weight: root.selected ? Font.DemiBold : Font.Medium
            color: root.colOn
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        StyledText {
            visible: root.trailingText.length > 0
            text: root.trailingText
            font.pixelSize: PanadoroStyle.textSmall
            color: root.colOn
            opacity: 0.72
        }
    }
}
