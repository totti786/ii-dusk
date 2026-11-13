import QtQuick
import QtQuick.Effects
import qs.modules.common

/**
 * One of the library's pictograms in any colour. The app's icons are cached as white
 * shapes (soundscapes.py), and a full colourisation turns white into exactly `color`.
 */
Item {
    id: root

    property string source: ""
    property color color: "white"

    Image {
        id: image
        anchors.fill: parent
        visible: false
        source: root.source.length > 0 ? `file://${root.source}` : ""
        sourceSize: Qt.size(Math.max(32, Math.ceil(root.width * 2)), Math.max(32, Math.ceil(root.height * 2)))
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
    }
    MultiEffect {
        anchors.fill: image
        source: image
        colorization: 1.0
        colorizationColor: root.color
        opacity: image.status === Image.Ready ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
    }
}
