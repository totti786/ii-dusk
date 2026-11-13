import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// A labelled single-line text field.
ColumnLayout {
    id: root

    property string label: ""
    property alias text: input.text
    property string placeholder: ""
    property bool mono: false
    property bool secret: false
    property alias input: input

    signal accepted()
    signal edited()

    spacing: 4

    StyledText {
        visible: root.label.length > 0
        text: root.label
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: ClockStyle.colSubtext
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 42
        radius: Appearance.rounding.small
        color: ClockStyle.colField
        border.width: input.activeFocus ? 2 : 0
        border.color: ClockStyle.colPrimary
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            verticalAlignment: TextInput.AlignVCenter
            color: ClockStyle.colOnSurface
            font.pixelSize: Appearance.font.pixelSize.small
            font.family: root.mono ? "monospace" : Appearance.font.family.main
            selectByMouse: true
            clip: true
            echoMode: root.secret ? TextInput.Password : TextInput.Normal
            onAccepted: root.accepted()
            onTextEdited: root.edited()
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text.length === 0
                text: root.placeholder
                font.pixelSize: Appearance.font.pixelSize.small
                color: ClockStyle.colSubtext
            }
        }
    }
}
