import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A tonal card for one section of a page: a badge, a title and a count, then whatever is put
 * inside it. Pages are made of these, so every app in the family reads the same.
 */
Rectangle {
    id: root

    property string title: ""
    property string symbol: ""
    /// Shown in a pill after the title; a negative number hides it.
    property int count: -1
    property var shape: MaterialShape.Shape.Cookie9Sided
    default property alias content: body.data
    /// Extra items at the right end of the header (buttons, a toggle).
    property alias headerExtras: extras.data

    readonly property bool hasHeader: root.title.length > 0

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
            visible: root.hasHeader
            spacing: ClockStyle.gap

            ClockBadge {
                visible: root.symbol.length > 0
                size: 44
                text: root.symbol
                shape: root.shape
                color: ClockStyle.colPrimary
                colSymbol: ClockStyle.colOnPrimary
            }
            StyledText {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                font.family: Appearance.font.family.title
                font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                font.pixelSize: Appearance.font.pixelSize.huge
                color: ClockStyle.colOnBackground
            }
            RowLayout {
                id: extras
                spacing: ClockStyle.gapSmall
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
            spacing: ClockStyle.gapSmall
        }
    }
}
