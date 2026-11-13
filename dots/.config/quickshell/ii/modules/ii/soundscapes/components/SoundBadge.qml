import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A sound's mark: its pictogram on a scalloped shape. The shape turns slowly while the
 * sound is audible, so a glance at the library shows what is playing.
 */
Item {
    id: root

    property string icon: ""
    property string shapeName: "Cookie9Sided"
    property real size: 56
    property color colShape: ClockStyle.colPrimaryContainer
    property color colIcon: ClockStyle.colOnPrimaryContainer
    property bool spinning: false
    property real iconScale: 0.56

    implicitWidth: root.size
    implicitHeight: root.size

    MaterialShape {
        id: shape
        anchors.fill: parent
        implicitSize: root.size
        shapeString: root.shapeName
        color: root.colShape
        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }
        NumberAnimation on rotation {
            from: 0
            to: 360
            duration: 28000
            loops: Animation.Infinite
            running: root.spinning && !ClockStyle.reducedMotion
        }
    }
    SoundIcon {
        anchors.centerIn: parent
        width: root.size * root.iconScale
        height: width
        source: root.icon
        color: root.colIcon
        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }
    }
}
