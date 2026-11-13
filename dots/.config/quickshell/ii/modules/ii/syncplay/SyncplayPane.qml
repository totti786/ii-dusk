import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One section of the room: a title, an optional count and header actions, then the content.
 * The content column fills the pane, so a list inside it can take the remaining height.
 */
Rectangle {
    id: root

    property string title: ""
    property int count: -1
    default property alias content: body.data
    property alias headerExtras: extras.data

    implicitHeight: column.implicitHeight + ClockStyle.cardPadding * 2
    radius: ClockStyle.radiusCard
    color: ClockStyle.colPane

    ColumnLayout {
        id: column
        anchors {
            fill: parent
            margins: ClockStyle.cardPadding
        }
        spacing: ClockStyle.gap

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall

            StyledText {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                font.family: ClockStyle.fontTitle
                font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                font.pixelSize: ClockStyle.textLarge + 2
                color: ClockStyle.colOnBackground
            }

            RowLayout {
                id: extras
                spacing: ClockStyle.gapTiny
            }

            Rectangle {
                visible: root.count >= 0
                implicitWidth: Math.max(28, countText.implicitWidth + 16)
                implicitHeight: 28
                radius: 14
                color: ClockStyle.colSecondaryContainer

                StyledText {
                    id: countText
                    anchors.centerIn: parent
                    text: String(root.count)
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colOnSecondaryContainer
                }
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: ClockStyle.gapSmall
        }
    }
}
