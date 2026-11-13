import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

/// A rounded slider with an icon on the left, value 0 to 1. Drag or click to set it.
Item {
    id: root

    property real value: 0
    property string icon: ""
    property bool dimmed: false
    signal moved(real value)
    signal iconClicked()

    implicitHeight: 44

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: Appearance.colors.colLayer2

        Rectangle {
            width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, root.value)))
            height: parent.height
            radius: parent.radius
            color: root.dimmed ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
        }

        MouseArea {
            anchors.fill: parent
            anchors.leftMargin: track.height
            cursorShape: Qt.PointingHandCursor
            function set(mouse) {
                root.moved(Math.max(0, Math.min(1, (mouse.x + track.height) / track.width)));
            }
            onPressed: mouse => set(mouse)
            onPositionChanged: mouse => { if (pressed) set(mouse); }
        }

        MouseArea {
            width: track.height
            height: track.height
            cursorShape: Qt.PointingHandCursor
            onClicked: root.iconClicked()
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.icon
                iconSize: 22
                color: Appearance.colors.colOnPrimary
            }
        }
    }
}
