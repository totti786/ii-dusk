import QtQuick
import QtQuick.Effects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A round account picture. While it loads, or when there is none, the first letter of the name sits
 * on the primary container so the spot is never empty.
 */
Item {
    id: root

    property string source: ""
    property string name: ""
    property real size: 32

    implicitWidth: root.size
    implicitHeight: root.size

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: ClockStyle.colPrimaryContainer

        StyledText {
            anchors.centerIn: parent
            text: root.name.length > 0 ? root.name.charAt(0).toUpperCase() : "?"
            color: ClockStyle.colOnPrimaryContainer
            font.family: ClockStyle.fontTitle
            font.variableAxes: ClockStyle.axesTitle
            font.pixelSize: Math.round(root.size * 0.45)
        }
    }

    Image {
        id: picture
        anchors.fill: parent
        visible: false
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        source: root.source
        sourceSize: Qt.size(root.size * 2, root.size * 2)
    }

    Item {
        id: roundMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle {
            anchors.fill: parent
            radius: width / 2
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: picture
        visible: picture.status === Image.Ready
        maskEnabled: true
        maskSource: roundMask
    }
}
