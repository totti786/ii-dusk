import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.qanun

/**
 * The small rotating tuning mark: a scalloped shape that spins while the
 * microphone is live, with the current cents inside. It is deliberately small
 * and stays still when the tuner is stopped.
 */
Item {
    id: root

    property real cents: 0
    property bool active: false
    property real size: 62
    property color statusColor: QanunStyle.tuningColor(root.cents, 5)

    implicitWidth: root.size
    implicitHeight: root.size

    MaterialShape {
        id: orbit
        anchors.fill: parent
        shapeString: "Cookie12Sided"
        color: Qt.alpha(root.statusColor, 0.20)

        RotationAnimator {
            target: orbit
            from: 0
            to: 360
            duration: 7200
            loops: Animation.Infinite
            running: root.active && !Appearance.reducedMotion
        }
    }

    MaterialShape {
        id: core
        anchors.centerIn: parent
        width: parent.width * 0.72
        height: width
        shapeString: "Circle"
        color: Qt.alpha(root.statusColor, 0.28)

        RotationAnimator {
            target: core
            from: 360
            to: 0
            duration: 9800
            loops: Animation.Infinite
            running: root.active && !Appearance.reducedMotion
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: -2
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: (root.cents > 0 ? "+" : "") + Math.round(root.cents)
            font.family: Appearance.font.family.numbers
            font.pixelSize: 13
            font.weight: Font.Bold
            color: root.statusColor
        }
        MaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.cents > 2 ? "north" : root.cents < -2 ? "south" : "check"
            iconSize: 13
            fill: 1
            color: root.statusColor
        }
    }
}
