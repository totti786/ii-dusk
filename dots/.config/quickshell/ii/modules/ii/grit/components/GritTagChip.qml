import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.grit.components

/** A focus tag as a filter chip: its own shape, its own colour, its own name. */
RippleButton {
    id: root

    property var tag: null
    property bool selected: false
    property string trailingText: ""

    readonly property color colTag: GritStyle.tagColor(root.tag)
    readonly property color colContainer: root.selected
        ? GritStyle.tagContainer(root.tag) : GritStyle.tagSoftContainer(root.tag)
    readonly property color colOn: root.selected
        ? GritStyle.tagOn(root.tag) : GritStyle.colOnSurface

    implicitHeight: GritStyle.chipHeight
    implicitWidth: chipRow.implicitWidth + GritStyle.gapLarge * 2
    buttonRadius: root.selected ? GritStyle.radiusNormal : GritStyle.pill(GritStyle.chipHeight)
    buttonRadiusPressed: GritStyle.radiusSmall
    colBackground: root.colContainer
    colBackgroundHover: root.selected
        ? GritStyle.tagContainer(root.tag)
        : ColorUtils.mix(root.colTag, GritStyle.colSurface, 0.2)
    colRipple: root.selected ? GritStyle.tagContainer(root.tag) : GritStyle.tagSoftContainer(root.tag)
    borderWidth: root.selected ? 0 : 1
    borderColor: ColorUtils.applyAlpha(root.colTag, 0.22)

    contentItem: RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: GritStyle.gapSmall

        Item {
            implicitWidth: 22
            implicitHeight: 22

            MaterialShape {
                anchors.fill: parent
                shapeString: String(root.tag?.shape ?? "Cookie7Sided")
                color: root.selected ? root.colTag : ColorUtils.applyAlpha(root.colTag, 0.85)
                rotation: root.selected ? 12 : 0

                Behavior on rotation {
                    enabled: !GritStyle.reducedMotion
                    NumberAnimation {
                        duration: GritStyle.motionDefault.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: GritStyle.motionDefault.bezierCurve
                    }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: GritStyle.tagIcon(root.tag)
                iconSize: 14
                fill: 1
                color: root.selected
                    ? ColorUtils.mostReadable(root.colTag, [GritStyle.colOnPrimary, GritStyle.colBackground])
                    : ColorUtils.mostReadable(root.colTag, [GritStyle.colOnSurface, GritStyle.colBackground])
            }
        }

        StyledText {
            text: String(root.tag?.name ?? "")
            font.pixelSize: GritStyle.textNormal
            font.weight: root.selected ? Font.DemiBold : Font.Medium
            color: root.colOn
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        StyledText {
            visible: root.trailingText.length > 0
            text: root.trailingText
            font.pixelSize: GritStyle.textSmall
            color: root.colOn
            opacity: 0.72
        }
    }
}
