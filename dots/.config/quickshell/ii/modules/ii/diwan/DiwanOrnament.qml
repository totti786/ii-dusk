import QtQuick

import qs.modules.common

/// A hairline that fades out to both sides with a small diamond between two dots.
Item {
    id: root

    property color tint: Appearance.colors.colPrimary
    property real span: 260

    implicitWidth: root.span
    implicitHeight: 16

    component Fade: Rectangle {
        required property bool toRight
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        width: (root.span - 44) / 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, toRight ? 0.7 : 0) }
            GradientStop { position: 1; color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, toRight ? 0 : 0.7) }
        }
    }

    Fade { toRight: false; x: 0 }
    Fade { toRight: true; x: root.width - width }
    Repeater {
        model: [-14, 14]
        delegate: Rectangle {
            required property int modelData
            width: 3
            height: 3
            radius: 1.5
            color: root.tint
            opacity: 0.7
            x: root.width / 2 + modelData - 1.5
            y: (root.height - 3) / 2
        }
    }
    Rectangle {
        width: 8
        height: 8
        rotation: 45
        color: root.tint
        x: (root.width - 8) / 2
        y: (root.height - 8) / 2
    }
}
