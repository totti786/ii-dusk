import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// A titled card, the building block of the pages.
Rectangle {
    id: root

    property string title: ""
    property string value: ""
    property string symbol: ""
    default property alias content: body.data

    radius: ClockStyle.radiusLarge
    color: ClockStyle.colSurface
    implicitHeight: column.implicitHeight + 24

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol {
                visible: root.symbol !== ""
                text: root.symbol
                iconSize: 18
                color: ClockStyle.colPrimary
            }
            StyledText {
                Layout.fillWidth: true
                text: root.title
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
                font.letterSpacing: 0.8
                elide: Text.ElideRight
            }
            StyledText {
                text: root.value
                color: ClockStyle.colOnBackground
                font.weight: Font.Medium
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8
        }
    }
}
