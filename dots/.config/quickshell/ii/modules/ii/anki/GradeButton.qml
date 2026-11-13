import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** One answer button: the next interval, the label, and the key that presses it. */
RippleButton {
    id: root

    property string label: ""
    property string interval: ""
    property string keyHint: ""
    property color buttonColor: ClockStyle.colSecondaryContainer
    property color contentColor: ClockStyle.colOnSecondaryContainer

    Layout.fillWidth: true
    implicitHeight: 72
    buttonRadius: ClockStyle.radiusCard
    buttonRadiusPressed: ClockStyle.radiusSmall
    colBackground: root.buttonColor
    colBackgroundHover: Qt.lighter(root.buttonColor, 1.08)
    colRipple: Qt.lighter(root.buttonColor, 0.92)
    opacity: root.enabled ? 1 : 0.45

    contentItem: Item {
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 1

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: root.interval.length > 0
                text: root.interval
                color: root.contentColor
                opacity: 0.75
                font.pixelSize: ClockStyle.textSmall
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.label
                color: root.contentColor
                font.pixelSize: ClockStyle.textLarge
                font.weight: Font.DemiBold
            }
        }

        Rectangle {
            visible: root.keyHint.length > 0
            anchors {
                top: parent.top
                right: parent.right
                topMargin: 8
                rightMargin: 10
            }
            width: 20
            height: 20
            radius: 6
            color: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.16)

            StyledText {
                anchors.centerIn: parent
                text: root.keyHint
                color: root.contentColor
                font.pixelSize: ClockStyle.textSmall
            }
        }
    }
}
