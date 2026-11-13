import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import ".."
import "../../../../services/WeatherAppLogic.js" as Logic

/**
 * One line of the hourly table. The condition text is the first thing to go on a narrow
 * window, because the icon and the numbers still carry the forecast.
 */
Rectangle {
    id: root

    property var hour: ({})
    property int offset: 0
    property var units: ({})
    property bool use24h: true
    property bool compact: false
    property bool current: false

    // Every column has one fixed width, so the numbers of one row sit under the numbers
    // of the row above whatever the condition text says.
    component Cell: RowLayout {
        property real cellWidth: 64
        Layout.preferredWidth: cellWidth
        Layout.minimumWidth: cellWidth
        Layout.maximumWidth: cellWidth
        spacing: 4
    }

    readonly property color colMuted: root.current ? WeatherStyle.colOnPrimaryContainer : WeatherStyle.colSubtext
    readonly property bool wet: (root.hour.precipProb || 0) >= 40

    implicitHeight: 52
    radius: WeatherStyle.radiusNormal
    color: root.current
        ? WeatherStyle.colPrimaryContainer
        : (hover.hovered ? WeatherStyle.colSurfaceHover : "transparent")

    Behavior on color {
        animation: WeatherStyle.motionFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: hover
    }

    RowLayout {
        anchors {
            fill: parent
            leftMargin: WeatherStyle.gap
            rightMargin: WeatherStyle.gap
        }
        spacing: WeatherStyle.gap

        StyledText {
            Layout.preferredWidth: 52
            Layout.minimumWidth: 52
            text: root.current ? "Now" : Logic.formatHour(root.hour.time, root.offset, root.use24h)
            font.pixelSize: WeatherStyle.textSmall
            font.weight: root.current ? Font.Bold : Font.Medium
            color: root.current ? WeatherStyle.colOnPrimaryContainer : WeatherStyle.colOnSurfaceVariant
        }

        WeatherIcon {
            Layout.alignment: Qt.AlignVCenter
            iconSize: 30
            code: root.hour.condition
            isDay: root.hour.isDay !== false
        }

        StyledText {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            visible: !root.compact
            text: Logic.conditionText(root.hour.condition)
            font.pixelSize: WeatherStyle.textSmall
            color: root.current ? WeatherStyle.colOnPrimaryContainer : WeatherStyle.colSubtext
            elide: Text.ElideRight
        }

        Item {
            Layout.fillWidth: true
            visible: root.compact
        }

        StyledText {
            Layout.preferredWidth: 48
            Layout.minimumWidth: 48
            horizontalAlignment: Text.AlignRight
            text: Logic.formatTemperature(root.hour.tempC, root.units)
            font.family: WeatherStyle.fontNumbers
            font.pixelSize: WeatherStyle.textLarge
            font.weight: Font.DemiBold
            font.variableAxes: WeatherStyle.axesDigits
            color: root.current ? WeatherStyle.colOnPrimaryContainer : WeatherStyle.colOnSurface
        }

        Cell {
            cellWidth: 64
            MaterialSymbol {
                text: "water_drop"
                iconSize: 15
                fill: root.wet ? 1 : 0
                color: root.wet && !root.current ? WeatherStyle.colPrimary : root.colMuted
            }
            StyledText {
                text: Logic.formatPercent(root.hour.precipProb)
                font.pixelSize: WeatherStyle.textSmall
                color: root.wet && !root.current ? WeatherStyle.colPrimary : root.colMuted
            }
        }

        Cell {
            visible: !root.compact
            cellWidth: 92
            MaterialSymbol {
                text: "air"
                iconSize: 15
                color: root.colMuted
            }
            StyledText {
                Layout.fillWidth: true
                text: Logic.formatWind(root.hour.windKmh, root.units)
                font.pixelSize: WeatherStyle.textSmall
                color: root.colMuted
                elide: Text.ElideRight
            }
        }

        Cell {
            visible: !root.compact
            cellWidth: 64
            MaterialSymbol {
                text: "humidity_percentage"
                iconSize: 15
                color: root.colMuted
            }
            StyledText {
                text: Logic.formatPercent(root.hour.humidity)
                font.pixelSize: WeatherStyle.textSmall
                color: root.colMuted
            }
        }
    }
}
