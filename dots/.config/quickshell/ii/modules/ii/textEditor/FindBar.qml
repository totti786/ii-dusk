import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.fileManager

/// Find / replace strip above the editor. The owner supplies hit counts and handles the signals.
Rectangle {
    id: root

    property bool replaceMode: false
    property alias findText: findField.text
    property alias replaceText: replaceField.text
    property bool matchCase: false
    property bool useRegex: false
    property int count: 0
    property int index: -1
    property bool invalid: false

    signal changed()
    signal next()
    signal previous()
    signal replaceOne()
    signal replaceAll()
    signal closeRequested()

    function focusFind(): void {
        findField.input.forceActiveFocus();
        findField.input.selectAll();
    }

    implicitHeight: col.implicitHeight + 16
    radius: 18
    color: ClockStyle.colSheet

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            FmIconButton {
                size: 32; iconSize: 18
                symbol: root.replaceMode ? "expand_less" : "expand_more"
                tip: qsTr("Replace")
                onClicked: root.replaceMode = !root.replaceMode
            }
            FmField {
                id: findField
                Layout.fillWidth: true
                mono: true
                placeholder: qsTr("Find")
                onEdited: root.changed()
                onAccepted: root.next()
                input.Keys.onPressed: e => {
                    if (e.key === Qt.Key_Escape) { root.closeRequested(); e.accepted = true; }
                    else if (e.key === Qt.Key_Return && (e.modifiers & Qt.ShiftModifier)) { root.previous(); e.accepted = true; }
                }
            }
            StyledText {
                Layout.preferredWidth: 70
                horizontalAlignment: Text.AlignHCenter
                text: root.invalid ? qsTr("bad regex") : root.findText.length === 0 ? "" : root.count === 0 ? qsTr("none") : (root.index + 1) + " / " + root.count
                font.pixelSize: 12
                color: root.invalid || (root.count === 0 && root.findText.length > 0) ? ClockStyle.colError : ClockStyle.colSubtext
            }
            FmIconButton { size: 32; iconSize: 18; symbol: "match_case"; tip: qsTr("Match case"); active: root.matchCase; onClicked: { root.matchCase = !root.matchCase; root.changed(); } }
            FmIconButton { size: 32; iconSize: 18; symbol: "regular_expression"; tip: qsTr("Regular expression"); active: root.useRegex; onClicked: { root.useRegex = !root.useRegex; root.changed(); } }
            FmIconButton { size: 32; iconSize: 18; symbol: "keyboard_arrow_up"; tip: qsTr("Previous"); onClicked: root.previous() }
            FmIconButton { size: 32; iconSize: 18; symbol: "keyboard_arrow_down"; tip: qsTr("Next"); onClicked: root.next() }
            FmIconButton { size: 32; iconSize: 18; symbol: "close"; tip: qsTr("Close"); onClicked: root.closeRequested() }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: root.replaceMode
            spacing: 6
            Item { Layout.preferredWidth: 32 }
            FmField {
                id: replaceField
                Layout.fillWidth: true
                mono: true
                placeholder: qsTr("Replace with")
                onAccepted: root.replaceOne()
                input.Keys.onEscapePressed: root.closeRequested()
            }
            FmButton { text: qsTr("Replace"); kind: "tonal"; onClicked: root.replaceOne() }
            FmButton { text: qsTr("All"); kind: "tonal"; onClicked: root.replaceAll() }
        }
    }
}
