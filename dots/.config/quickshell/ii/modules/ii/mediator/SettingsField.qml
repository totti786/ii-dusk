pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

/// One labelled text row in the settings. `secret` hides the text and shows `placeholder`
/// (e.g. "saved, type to replace") while nothing has been typed.
ColumnLayout {
    id: root

    property string label
    property string hint
    property string text
    property string placeholder
    property bool secret: false
    property string original: ""

    readonly property bool changed: root.text !== root.original
    readonly property alias input: field

    signal accepted()

    Layout.fillWidth: true
    spacing: 6

    StyledText {
        text: root.label
        color: Appearance.colors.colOnLayer0
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.Medium
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 44
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer1
        border.width: field.activeFocus ? 2 : 0
        border.color: Appearance.colors.colPrimary

        TextInput {
            id: field
            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
            verticalAlignment: TextInput.AlignVCenter
            color: Appearance.colors.colOnLayer0
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.normal
            echoMode: root.secret ? TextInput.Password : TextInput.Normal
            passwordCharacter: "•"
            selectByMouse: true
            activeFocusOnPress: true
            clip: true
            text: root.text
            onTextChanged: root.text = text
            onAccepted: root.accepted()

            StyledText {
                visible: field.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: root.placeholder
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.normal
            }
        }
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
