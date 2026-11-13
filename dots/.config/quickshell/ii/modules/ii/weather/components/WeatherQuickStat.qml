import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import ".."

/**
 * A small translucent fact for the hero. It is not a card: the hero already has a
 * surface, and another rounded rectangle in it would read as a second layer.
 */
Rectangle {
    id: root

    property string icon: "circle"
    property string label: ""
    property string value: ""
    property string tone: "primary"
    property string chartId: ""
    // Defaults suit a pane; the hero passes colours of its own tone
    property color colChip: WeatherStyle.colSurfaceHigh
    property color colText: WeatherStyle.colOnSurface
    property color colMuted: WeatherStyle.colSubtext
    property color colGlyph: WeatherStyle.toneOnContainer(root.tone)
    property color colGlyphBack: WeatherStyle.toneContainer(root.tone)

    signal triggered()

    readonly property bool interactive: root.chartId.length > 0

    implicitWidth: statRow.implicitWidth + 24
    implicitHeight: 48
    clip: true
    radius: WeatherStyle.radiusFull
    color: root.interactive && chipHover.hovered ? ColorUtils.mix(root.colChip, root.colText, 0.9) : root.colChip

    HoverHandler {
        id: chipHover
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        enabled: root.interactive
        onTapped: root.triggered()
    }

    RowLayout {
        id: statRow
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            right: parent.right
            leftMargin: 8
            rightMargin: 12
        }
        spacing: 8

        Rectangle {
            implicitWidth: 32
            implicitHeight: 32
            radius: WeatherStyle.radiusFull
            color: root.colGlyphBack

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.icon
                iconSize: 17
                fill: 1
                color: root.colGlyph
            }
        }

        ColumnLayout {
            spacing: 0

            StyledText {
                text: root.label
                font.pixelSize: WeatherStyle.textTiny
                color: root.colMuted
            }

            StyledText {
                text: root.value
                font.family: WeatherStyle.fontNumbers
                font.pixelSize: WeatherStyle.textNormal
                font.weight: Font.DemiBold
                color: root.colText
            }
        }
    }
}
