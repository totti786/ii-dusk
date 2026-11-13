import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import ".."

/**
 * A compact measurement card. The tinted icon and the subtext share the same tone so a
 * high UV or a bad AQI is legible at a glance without reading the number first.
 */
Rectangle {
    id: root

    property string label: ""
    property string value: ""
    property string subtext: ""
    property string icon: "circle"
    property string tone: "primary"
    property bool emphasized: false
    property string chartId: ""

    signal triggered()

    Layout.fillWidth: true
    implicitHeight: 124
    clip: true
    radius: WeatherStyle.radiusTile
    color: root.emphasized ? WeatherStyle.toneContainer(root.tone) : (tileHover.hovered && root.interactive ? WeatherStyle.colSurfaceHover : WeatherStyle.colSurfaceHigh)

    readonly property bool interactive: root.chartId.length > 0
    readonly property bool hovered: tileHover.hovered
    readonly property color accent: WeatherStyle.toneColor(root.tone)
    readonly property color onAccent: WeatherStyle.toneOnContainer(root.tone)

    Behavior on color {
        animation: WeatherStyle.motionFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: tileHover
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        enabled: root.interactive
        onTapped: root.triggered()
    }

    ColumnLayout {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: parent.bottom
            margins: 14
        }
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: WeatherStyle.gapSmall

            ClockBadge {
                size: 36
                text: root.icon
                shape: root.hovered && root.interactive ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Cookie6Sided
                color: root.emphasized ? WeatherStyle.alpha(root.onAccent, 0.16) : WeatherStyle.toneContainer(root.tone)
                colSymbol: root.emphasized ? root.onAccent : WeatherStyle.toneOnContainer(root.tone)
            }

            StyledText {
                Layout.fillWidth: true
                text: root.label
                font.pixelSize: WeatherStyle.textSmall
                font.weight: Font.Medium
                color: root.emphasized ? WeatherStyle.alpha(root.onAccent, 0.8) : WeatherStyle.colOnSurfaceVariant
                elide: Text.ElideRight
            }

        }

        StyledText {
            Layout.fillWidth: true
            text: root.value
            font.family: WeatherStyle.fontNumbers
            font.pixelSize: 28
            font.variableAxes: WeatherStyle.axesDigits
            font.weight: Font.DemiBold
            color: root.emphasized ? root.onAccent : WeatherStyle.colOnSurface
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.subtext.length > 0
            text: root.subtext
            font.pixelSize: WeatherStyle.textSmall
            color: root.emphasized ? WeatherStyle.alpha(root.onAccent, 0.75) : WeatherStyle.colSubtext
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
}
