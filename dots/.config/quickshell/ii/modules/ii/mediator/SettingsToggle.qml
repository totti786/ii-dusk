pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

/// A labelled on/off row.
Item {
    id: root

    property string label
    property string hint
    property bool checked: false
    property bool original: false
    readonly property bool changed: root.checked !== root.original

    Layout.fillWidth: true
    implicitHeight: 52

    ColumnLayout {
        anchors { left: parent.left; right: sw.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
        spacing: 2
        StyledText {
            text: root.label
            color: Appearance.colors.colOnLayer0
            font.weight: Font.Medium
        }
        StyledText {
            visible: root.hint !== ""
            Layout.fillWidth: true
            text: root.hint
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    Rectangle {
        id: sw
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: 52
        height: 30
        radius: Appearance.rounding.full
        color: root.checked ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
        Behavior on color {
            ColorAnimation { duration: Appearance.dur(120) }
        }
        Rectangle {
            width: 22
            height: 22
            radius: Appearance.rounding.full
            y: 4
            x: root.checked ? parent.width - width - 4 : 4
            color: root.checked ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
            Behavior on x {
                NumberAnimation { duration: Appearance.dur(140); easing.type: Easing.OutCubic }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.checked = !root.checked
    }
}
