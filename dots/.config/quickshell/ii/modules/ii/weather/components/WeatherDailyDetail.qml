import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import ".."
import "../../../../services/WeatherAppLogic.js" as Logic

/**
 * The extra numbers behind one day. Kept out of the row so the list stays scannable,
 * and revealed in place so the explanation is next to the thing it explains.
 */
Rectangle {
    id: root

    property var day: ({})
    property var units: ({})
    property int offset: 0
    property bool use24h: true

    Layout.fillWidth: true
    implicitHeight: detailLayout.implicitHeight + 24
    radius: WeatherStyle.radiusTile
    color: WeatherStyle.alpha(WeatherStyle.colPrimary, 0.065)
    border.width: 1
    border.color: WeatherStyle.alpha(WeatherStyle.colOutline, 0.18)

    ColumnLayout {
        id: detailLayout
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: 12
            rightMargin: 12
            topMargin: 10
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: WeatherStyle.gapSmall

            WeatherIcon {
                iconSize: 32
                code: root.day.condition
                isDay: true
            }

            StyledText {
                Layout.fillWidth: true
                text: root.day.summary || Logic.conditionText(root.day.condition)
                font.pixelSize: WeatherStyle.textSmall
                font.weight: Font.Medium
                color: WeatherStyle.colOnSurface
                elide: Text.ElideRight
            }

            StyledText {
                text: `${Logic.formatTemperature(root.day.maxC, root.units)} / ${Logic.formatTemperature(root.day.minC, root.units)}`
                font.family: WeatherStyle.fontNumbers
                font.pixelSize: WeatherStyle.textSmall
                font.weight: Font.DemiBold
                color: WeatherStyle.colOnSurfaceVariant
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6

            WeatherQuickStat {
                icon: "rainy"
                label: "Precipitation"
                value: Logic.formatPrecip(root.day.precipMm, root.units)
                tone: WeatherStyle.rainTone(root.day.precipProb)
            }

            WeatherQuickStat {
                icon: "water_drop"
                label: "Chance"
                value: Logic.formatPercent(root.day.precipProb)
                tone: WeatherStyle.rainTone(root.day.precipProb)
            }

            WeatherQuickStat {
                icon: "air"
                label: "Wind · " + Logic.windDirection(root.day.windDirDeg)
                value: Logic.formatWind(root.day.windKmh, root.units)
                tone: "tertiary"
            }

            WeatherQuickStat {
                icon: "storm"
                label: "Gusts"
                value: Logic.formatWind(root.day.gustKmh, root.units)
                tone: "tertiary"
            }

            WeatherQuickStat {
                icon: "wb_sunny"
                label: "UV index"
                value: Logic.formatUv(root.day.uv)
                tone: WeatherStyle.uvTone(root.day.uv)
            }

            WeatherQuickStat {
                icon: "wb_twilight"
                label: "Sunrise"
                value: root.day.sunrise ? Logic.formatTime(root.day.sunrise, root.offset, root.use24h) : "--"
                tone: "tertiary"
            }

            WeatherQuickStat {
                icon: "nightlight"
                label: "Sunset"
                value: root.day.sunset ? Logic.formatTime(root.day.sunset, root.offset, root.use24h) : "--"
                tone: "primary"
            }

            WeatherQuickStat {
                icon: "bedtime"
                label: "Moonrise"
                value: root.day.moonrise ? Logic.formatTime(root.day.moonrise, root.offset, root.use24h) : "--"
                tone: "primary"
            }

            WeatherQuickStat {
                icon: "dark_mode"
                label: "Moonset"
                value: root.day.moonset ? Logic.formatTime(root.day.moonset, root.offset, root.use24h) : "--"
                tone: "tertiary"
            }
        }
    }
}
