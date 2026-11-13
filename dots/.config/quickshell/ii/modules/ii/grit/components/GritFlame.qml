import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.grit.components

/** A small, living streak: the flame the original Grit uses beside a habit. */
RowLayout {
    id: root

    property int count: 0
    property color colFlame: GritStyle.colTertiary
    property int iconSize: 15
    property bool showZero: false

    visible: root.count > 0 || root.showZero
    spacing: 3

    Item {
        implicitWidth: root.iconSize + 10
        implicitHeight: root.iconSize + 10

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: ColorUtils.mix(root.colFlame, GritStyle.colSurface, 0.14)
        }

        MaterialSymbol {
            id: flame
            anchors.centerIn: parent
            text: "local_fire_department"
            iconSize: root.iconSize
            fill: 1
            color: root.colFlame
            animateChange: false
        }

        SequentialAnimation on scale {
            running: (root.count > 0 && !GritStyle.reducedMotion && root.visible) && !Appearance.motionOff
            loops: Animation.Infinite
            NumberAnimation {
                from: 1
                to: 1.13
                duration: 1100
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                from: 1.13
                to: 1
                duration: 1100
                easing.type: Easing.InOutSine
            }
        }
    }

    StyledText {
        text: String(root.count)
        font.family: GritStyle.fontNumbers
        font.variableAxes: GritStyle.axesDigitsBold
        font.pixelSize: GritStyle.textSmall
        color: root.colFlame
    }
}
