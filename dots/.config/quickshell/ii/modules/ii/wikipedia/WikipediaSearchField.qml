pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** The one control that stays within reach on every Wikipedia page. */
Rectangle {
    id: root

    property alias text: input.text
    property string placeholder: Translation.tr("Search Wikipedia")
    readonly property bool inputActiveFocus: input.activeFocus

    signal submitted(string text)
    signal cleared()

    implicitHeight: 48
    radius: ClockStyle.pill(implicitHeight)
    color: input.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField

    function focusInput(): void {
        input.forceActiveFocus();
        input.selectAll();
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: input.forceActiveFocus()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: ClockStyle.gapSmall
        anchors.rightMargin: ClockStyle.gapTiny
        spacing: ClockStyle.gapSmall

        MaterialSymbol {
            text: "search"
            iconSize: ClockStyle.iconNormal
            color: ClockStyle.colSubtext
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledTextInput {
                id: input
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                selectByMouse: true
                activeFocusOnTab: true
                color: ClockStyle.colOnSurface
                font.pixelSize: ClockStyle.textNormal
                onAccepted: root.submitted(text)

                StyledText {
                    anchors.fill: parent
                    visible: input.text.length === 0
                    verticalAlignment: Text.AlignVCenter
                    text: root.placeholder
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textNormal
                }
            }
        }

        ClockIconButton {
            visible: input.text.length > 0
            symbol: "close"
            tooltip: Translation.tr("Clear search")
            onClicked: {
                input.text = "";
                root.cleared();
                input.forceActiveFocus();
            }
        }

        ClockIconButton {
            symbol: "arrow_forward"
            tooltip: Translation.tr("Search")
            enabled: input.text.trim().length > 0
            onClicked: root.submitted(input.text)
        }
    }
}
