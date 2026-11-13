import QtQuick

import qs.modules.common
import qs.modules.common.widgets

/** Placeholder with a CoverCard's footprint, pulsing while a catalog loads. */
Item {
    id: root

    readonly property real coverWidth: root.width - 16

    height: root.coverWidth * 1.5 + 16 + 10 + 40

    Item {
        anchors { fill: parent; margins: 8 }
        opacity: 0.45
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: !Appearance.motionOff
            NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.45; duration: 700; easing.type: Easing.InOutSine }
        }

        RoundedBox {
            id: cover
            width: parent.width
            height: width * 1.5
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer2
        }
        Rectangle {
            anchors { left: parent.left; top: cover.bottom; topMargin: 12 }
            width: parent.width * 0.75
            height: 12
            radius: 6
            color: Appearance.colors.colLayer2
        }
        Rectangle {
            anchors { left: parent.left; top: cover.bottom; topMargin: 32 }
            width: parent.width * 0.45
            height: 10
            radius: 5
            color: Appearance.colors.colLayer2
        }
    }
}
