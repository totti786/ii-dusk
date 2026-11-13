import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** A pill-shaped search box: icon, input with a placeholder, and a clear button. */
Rectangle {
    id: root

    property string placeholder: ""
    property alias text: input.text
    property alias input: input

    signal accepted()

    function focusInput(): void {
        input.forceActiveFocus();
    }

    Layout.fillWidth: true
    implicitHeight: 48
    radius: ClockStyle.pill(48)
    color: input.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: input.forceActiveFocus()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 8
        spacing: 10

        MaterialSymbol {
            text: "search"
            iconSize: 22
            color: ClockStyle.colOnSurfaceVariant
        }
        StyledTextInput {
            id: input
            Layout.fillWidth: true
            clip: true
            font.pixelSize: Appearance.font.pixelSize.normal
            color: ClockStyle.colOnSurface
            onAccepted: root.accepted()

            StyledText {
                anchors.fill: parent
                visible: input.text.length === 0
                verticalAlignment: Text.AlignVCenter
                text: root.placeholder
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer1Inactive
            }
        }
        ClockIconButton {
            visible: input.text.length > 0
            symbol: "close"
            size: 32
            iconSize: 18
            tooltip: Translation.tr("Clear")
            onClicked: {
                input.text = "";
                input.forceActiveFocus();
            }
        }
    }
}
