import QtQuick

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A book's cover, or a tile with its first letters when there is none yet.
 * The tile's hue comes from the title, so the same book always looks the same.
 */
Rectangle {
    id: root

    property string source: ""
    property string title: ""
    property string format: ""

    readonly property bool hasCover: image.status === Image.Ready
    readonly property real hue: {
        let h = 7;
        for (let i = 0; i < root.title.length; i++)
            h = (h * 31 + root.title.charCodeAt(i)) % 360;
        return h / 360;
    }
    readonly property string initials: {
        const words = root.title.split(/\s+/).filter(w => w.length > 0);
        return words.slice(0, 2).map(w => Array.from(w)[0]).join("").toUpperCase();
    }

    radius: ClockStyle.radiusCard
    clip: true
    color: Qt.hsla(root.hue, 0.28, 0.24, 1)

    // A clip does not round what is inside it, so the picture goes through a rounded mask.
    Image {
        id: image
        anchors.fill: parent
        visible: false
        source: root.source
        asynchronous: true
        cache: true
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 360
    }

    Item {
        id: roundMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            radius: root.radius
        }
    }

    MaskMultiEffect {
        anchors.fill: parent
        source: image
        maskSource: roundMask
        opacity: image.status === Image.Ready ? 1 : 0

        Behavior on opacity {
            enabled: !ClockStyle.reducedMotion
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
    }

    StyledText {
        anchors.centerIn: parent
        visible: !root.hasCover
        text: root.initials
        color: Qt.hsla(root.hue, 0.5, 0.78, 1)
        font.pixelSize: Math.max(18, root.width * 0.28)
        font.weight: Font.DemiBold
    }

    Rectangle {
        anchors {
            left: parent.left
            top: parent.top
            margins: 8
        }
        visible: root.format.length > 0
        radius: 6
        height: 18
        width: formatLabel.implicitWidth + 12
        color: "#99000000"

        StyledText {
            id: formatLabel
            anchors.centerIn: parent
            text: root.format.toUpperCase()
            color: "white"
            font.pixelSize: 10
            font.weight: Font.DemiBold
        }
    }
}
