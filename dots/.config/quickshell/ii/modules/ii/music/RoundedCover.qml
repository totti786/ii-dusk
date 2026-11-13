import QtQuick
import QtQuick.Effects

import qs.modules.common
import qs.modules.common.widgets
import "MusicFormat.js" as Fmt

/** A square cover with rounded corners, and a quiet placeholder while there is none. */
Item {
    id: root

    property string path: ""
    property real radius: 12
    property string symbol: "music_note"
    property color colPlaceholder: Appearance.colors.colSurfaceContainerHigh

    readonly property bool ready: img.status === Image.Ready

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.colPlaceholder
        visible: !root.ready

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.symbol
            iconSize: Math.max(16, root.width * 0.38)
            color: Appearance.colors.colSubtext
        }
    }

    Image {
        id: img
        anchors.fill: parent
        source: Fmt.fileUrl(root.path)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        sourceSize: Qt.size(Math.max(1, root.width * 2), Math.max(1, root.height * 2))
        visible: false
    }

    // The mask stays in the tree, rendered to a layer: Qt5Compat's OpacityMask leaks window
    // references, and a MultiEffect mask does not (see docs/design/material3-expressive.md).
    Rectangle {
        id: mask
        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        source: img
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
        opacity: root.ready ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Appearance.dur(220) }
        }
    }
}
