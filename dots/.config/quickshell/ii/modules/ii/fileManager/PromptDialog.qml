import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// Asks for a name, or (with `input: false`) just confirms. `danger` colours the button.
FmDialog {
    id: root

    property string message: ""
    property string label: ""
    property string text: ""
    property string confirmText: qsTr("OK")
    property bool input: true
    property bool danger: false
    property bool selectBase: true
    property bool secret: false

    signal accepted(string text)

    cardWidth: 440

    function submit(): void {
        if (root.input && field.text.trim().length === 0)
            return;
        root.accepted(root.input ? field.text : "");
    }

    Component.onCompleted: {
        opacity = 1;
        if (root.input) {
            field.text = root.text;
            field.input.forceActiveFocus();
            const dot = root.selectBase ? root.text.lastIndexOf(".") : -1;
            field.input.select(0, dot > 0 ? dot : root.text.length);
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.message.length > 0
        text: root.message
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.small
        color: ClockStyle.colOnSurfaceVariant
    }
    FmField {
        id: field
        Layout.fillWidth: true
        visible: root.input
        label: root.label
        secret: root.secret
        onAccepted: root.submit()
    }

    actions: [
        FmButton { text: qsTr("Cancel"); onClicked: root.close() },
        FmButton {
            text: root.confirmText
            kind: root.danger ? "danger" : "filled"
            onClicked: root.submit()
        }
    ]
}
