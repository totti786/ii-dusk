pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import ".."
import "../components"
import "../../../../services/WeatherAppLogic.js" as Logic

/**
 * The reference page: every current value, pollution and pollen, astronomy, the
 * short-range rain nowcast where the source provides one, and where the data came from.
 */
WeatherPage {
    id: root

    property real layoutWidth: width
    property bool compact: false
    property bool wide: false

    signal chartRequested(string chartId)

    readonly property var cur: WeatherAppService.current
    readonly property var units: WeatherAppService.units
    readonly property int offset: WeatherAppService.data?.utcOffset ?? 0
    readonly property var data: WeatherAppService.data
    readonly property string pageSubtitle: "Current conditions, air and astronomy · " + (Logic.providerModelLabel(root.data) || WeatherAppService.providerLabel)

    readonly property int metricColumns: root.layoutWidth >= 1040 ? 4 : (root.layoutWidth >= 700 ? 3 : 2)
    readonly property bool hasAq: !!(root.cur && ((root.cur.aqi !== null && root.cur.aqi !== undefined) || (root.cur.pm25 !== null && root.cur.pm25 !== undefined)))
    readonly property bool hasPollen: root.cur && root.cur.pollen && root.cur.pollen.total !== null && root.cur.pollen.total !== undefined

    function chartIdFor(label) {
        switch (label) {
        case "Temperature":
        case "Feels like": return "temperature";
        case "Dew point": return "dew";
        case "Humidity": return "humidity";
        case "Pressure": return "pressure";
        case "Wind":
        case "Gusts": return "wind";
        case "Visibility": return "visibility";
        case "Cloud cover": return "cloud";
        case "UV index": return "uv";
        case "Precipitation":
        case "Rain": return "precipitation";
        case "Snow": return "dailyPrecipitation";
        case "PM2.5":
        case "PM10": return "particulates";
        case "Ozone":
        case "Nitrogen dioxide": return "gases";
        case "Sulphur dioxide":
        case "Carbon monoxide": return "sulfur";
        case "European AQI": return "aqi";
        case "Pollen": return "pollen";
        default: return "";
        }
    }

    readonly property var metrics: [
        {
            label: "Temperature",
            value: Logic.formatTemperature(root.cur.tempC, root.units),
            subtext: "Air temperature",
            icon: "thermostat",
            tone: "primary"
        },
        {
            label: "Feels like",
            value: Logic.formatTemperature(root.cur.feelsC, root.units),
            subtext: "Apparent temperature",
            icon: "device_thermostat",
            tone: "primary"
        },
        {
            label: "Dew point",
            value: Logic.formatTemperature(root.cur.dewC, root.units),
            subtext: "Condensation point",
            icon: "water_drop",
            tone: "secondary"
        },
        {
            label: "Humidity",
            value: Logic.formatPercent(root.cur.humidity),
            subtext: Logic.humidityComfort(root.cur.humidity),
            icon: "humidity_percentage",
            tone: "secondary"
        },
        {
            label: "Pressure",
            value: Logic.formatPressure(root.cur.pressureHpa, root.units),
            subtext: Logic.pressureTrend(root.cur.pressureHpa, WeatherAppService.hourly[0]?.pressureHpa).label,
            icon: "speed",
            tone: "primary"
        },
        {
            label: "Wind",
            value: Logic.formatWind(root.cur.windKmh, root.units),
            subtext: Logic.windDirection(root.cur.windDirDeg),
            icon: "air",
            tone: "tertiary"
        },
        {
            label: "Gusts",
            value: Logic.formatWind(root.cur.gustKmh, root.units),
            subtext: "Peak wind",
            icon: "storm",
            tone: "tertiary"
        },
        {
            label: "Visibility",
            value: Logic.formatVisibility(root.cur.visibilityKm, root.units),
            subtext: "Horizontal range",
            icon: "visibility",
            tone: "primary"
        },
        {
            label: "Cloud cover",
            value: Logic.formatPercent(root.cur.cloud),
            subtext: root.cur.isDay !== false ? "Daytime" : "Night",
            icon: "cloud",
            tone: "tertiary"
        },
        {
            label: "UV index",
            value: Logic.formatUv(root.cur.uv),
            subtext: Logic.uvCategory(root.cur.uv).label,
            icon: "wb_sunny",
            tone: WeatherStyle.uvTone(root.cur.uv)
        },
        {
            label: "Precipitation",
            value: Logic.formatPercent(root.cur.precipProb),
            subtext: Logic.formatPrecip(root.cur.precipMm, root.units) + " now",
            icon: "rainy",
            tone: WeatherStyle.rainTone(root.cur.precipProb)
        },
        {
            label: "Rain",
            value: Logic.formatPrecip(root.cur.rainMm, root.units),
            subtext: "Liquid equivalent",
            icon: "water_drop",
            tone: "secondary"
        },
        {
            label: "Snow",
            value: root.cur.snowCm === null || root.cur.snowCm === undefined
                ? "--"
                : (root.units.snow === "in"
                    ? Logic.formatNumber(root.cur.snowCm / 2.54, 2) + " in"
                    : Logic.formatNumber(root.cur.snowCm, 1) + " cm"),
            subtext: "Accumulation",
            icon: "ac_unit",
            tone: "primary"
        }
    ]

    readonly property var aqMetrics: [
        {
            label: "PM2.5",
            value: Logic.formatNumber(root.cur.pm25, 1) + " µg/m³",
            subtext: "Fine particles",
            icon: "grain",
            tone: WeatherStyle.aqiTone(root.cur.aqi)
        },
        {
            label: "PM10",
            value: Logic.formatNumber(root.cur.pm10, 1) + " µg/m³",
            subtext: "Coarse particles",
            icon: "blur_on",
            tone: "tertiary"
        },
        {
            label: "Ozone",
            value: Logic.formatNumber(root.cur.ozone, 1) + " µg/m³",
            subtext: "O₃",
            icon: "science",
            tone: "secondary"
        },
        {
            label: "Nitrogen dioxide",
            value: Logic.formatNumber(root.cur.no2, 1) + " µg/m³",
            subtext: "NO₂",
            icon: "science",
            tone: "tertiary"
        },
        {
            label: "Sulphur dioxide",
            value: Logic.formatNumber(root.cur.so2, 1) + " µg/m³",
            subtext: "SO₂",
            icon: "science",
            tone: "secondary"
        },
        {
            label: "Carbon monoxide",
            value: Logic.formatNumber(root.cur.co, 1) + " µg/m³",
            subtext: "CO",
            icon: "science",
            tone: "tertiary"
        },
        {
            label: "European AQI",
            value: Logic.formatAqi(root.cur.europeanAqi),
            subtext: Logic.aqiCategory(root.cur.europeanAqi).label,
            icon: "eco",
            tone: WeatherStyle.aqiTone(root.cur.europeanAqi)
        }
    ]

    readonly property var pollenMetrics: {
        if (!root.cur.pollen)
            return [];
        const names = {
            alder: "Alder",
            birch: "Birch",
            grass: "Grass",
            mugwort: "Mugwort",
            olive: "Olive",
            ragweed: "Ragweed"
        };
        const list = [];
        for (const key of Object.keys(names)) {
            const value = root.cur.pollen[key];
            if (value === null || value === undefined)
                continue;
            list.push({
                label: names[key],
                value: Logic.formatNumber(value, 1),
                tone: Logic.pollenCategory(value).tone
            });
        }
        return list;
    }

    readonly property var minutely: (root.data?.minutely ?? []).slice(0, 24)
    readonly property var minutelyBars: root.minutely.map(minute => minute.precipMm)
    readonly property var minutelyLabels: root.minutely.map((minute, index) => index % 4 === 0 ? Logic.formatHour(minute.time, root.offset, WeatherAppService.use24h) : "")
    readonly property var minutelyPointLabels: root.minutely.map(minute => Logic.formatTime(minute.time, root.offset, WeatherAppService.use24h))
    readonly property bool minutelyHasRain: root.minutely.some(minute => Number(minute.precipMm) > 0.01)

    ClockHero {
        Layout.fillWidth: true
        symbol: "tune"
        shape: MaterialShape.Shape.Cookie9Sided
        title: "Conditions right now"
        text: `${root.cur.summary || Logic.conditionText(root.cur.condition)}. This is the current reading, not a forecast. Tap a condition to chart it.`
        compact: root.compact
    }

    // ── Current conditions ──────────────────────────────────────────────
    WeatherSection {
        title: "Now"
        subtitle: root.cur.summary || Logic.conditionText(root.cur.condition)
        icon: "device_thermostat"

        GridLayout {
            Layout.fillWidth: true
            columns: root.metricColumns
            rowSpacing: 10
            columnSpacing: 10

            Repeater {
                model: root.metrics

                WeatherMetricTile {
                    required property var modelData
                    required property int index
                    // the last tile takes the rest of its row, so no row is left half empty
                    Layout.columnSpan: index === root.metrics.length - 1
                        ? root.metricColumns - (root.metrics.length - 1) % root.metricColumns
                        : 1
                    label: modelData.label
                    value: modelData.value
                    subtext: modelData.subtext
                    icon: modelData.icon
                    tone: modelData.tone
                    chartId: root.chartIdFor(modelData.label)
                    onTriggered: root.chartRequested(root.chartIdFor(modelData.label))
                }
            }
        }
    }

    // ── Minutely precipitation ──────────────────────────────────────────
    WeatherSection {
        visible: root.minutely.length > 0
        title: "Minute precipitation"
        subtitle: root.minutelyHasRain ? "Short-range nowcast from the current source" : "No precipitation expected in the near term"
        icon: "water_drop"

        WeatherChart {
            visible: root.minutelyHasRain
            Layout.fillWidth: true
            Layout.preferredHeight: 168
            values: []
            bars: root.minutelyBars
            labels: root.minutelyLabels
            pointLabels: root.minutelyPointLabels
            barLabel: "Precipitation"
            barUnit: Logic.precipUnit(root.units)
            barColor: WeatherStyle.colPrimary
            decimals: 2
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !root.minutelyHasRain
            spacing: WeatherStyle.gapSmall

            MaterialSymbol {
                text: "check_circle"
                iconSize: 20
                fill: 1
                color: WeatherStyle.colSuccess
            }

            StyledText {
                Layout.fillWidth: true
                text: "The provider has a minutely forecast, and it is dry for the next few hours."
                font.pixelSize: WeatherStyle.textSmall
                color: WeatherStyle.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }
        }
    }

    // ── Air quality ─────────────────────────────────────────────────────
    WeatherSection {
        visible: root.hasAq
        title: "Air quality & pollen"
        subtitle: "Tap a pollutant for its chart · Open-Meteo / CAMS supplement"
        icon: "masks"

        GridLayout {
            Layout.fillWidth: true
            columns: root.layoutWidth >= 760 ? 2 : 1
            columnSpacing: WeatherStyle.gapHuge
            rowSpacing: WeatherStyle.gap

            WeatherAqiGauge {
                Layout.fillWidth: root.layoutWidth < 760
                Layout.preferredWidth: 260
                Layout.minimumWidth: 210
                Layout.maximumWidth: 320
                Layout.preferredHeight: 158
                Layout.alignment: Qt.AlignTop
                value: root.cur.aqi
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 320
                columns: 2
                rowSpacing: 8
                columnSpacing: 8

                Repeater {
                    model: root.aqMetrics

                    WeatherMetricTile {
                        required property var modelData
                        label: modelData.label
                        value: modelData.value
                        subtext: modelData.subtext
                        icon: modelData.icon
                        tone: modelData.tone
                        chartId: root.chartIdFor(modelData.label)
                        onTriggered: root.chartRequested(root.chartIdFor(modelData.label))
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: WeatherStyle.gapTiny
            implicitHeight: 1
            color: WeatherStyle.colOutline
            opacity: 0.3
            visible: root.pollenMetrics.length > 0
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: WeatherStyle.gapSmall
            visible: root.pollenMetrics.length > 0

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    text: "Pollen"
                    font.pixelSize: WeatherStyle.textSmall
                    font.weight: Font.DemiBold
                    color: WeatherStyle.colOnSurface
                }

                StyledText {
                    text: "grains/m³"
                    font.pixelSize: WeatherStyle.textTiny
                    color: WeatherStyle.colSubtext
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: root.pollenMetrics

                    WeatherQuickStat {
                        required property var modelData
                        icon: "local_florist"
                        label: modelData.label
                        value: modelData.value
                        tone: modelData.tone
                        chartId: "pollen"
                        onTriggered: root.chartRequested("pollen")
                    }
                }
            }
        }
    }

    // ── Astronomy ───────────────────────────────────────────────────────
    WeatherSection {
        title: "Astronomy"
        subtitle: "Local calculations fill in whatever the provider omits"
        icon: "dark_mode"

        GridLayout {
            Layout.fillWidth: true
            columns: root.layoutWidth >= 760 ? 2 : 1
            columnSpacing: WeatherStyle.gapHuge
            rowSpacing: WeatherStyle.gap

            WeatherSunArc {
                Layout.fillWidth: true
                Layout.minimumWidth: 260
                sunrise: root.cur.sunrise || 0
                sunset: root.cur.sunset || 0
                moonrise: root.cur.moonrise || 0
                moonset: root.cur.moonset || 0
                nextSunrise: WeatherAppService.daily[1]?.sunrise || 0
                isDay: root.cur.isDay !== false
                offset: root.offset
                use24h: WeatherAppService.use24h
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                WeatherInfoRow {
                    label: "Moon phase"
                    value: root.cur.moonPhaseName || "--"
                    icon: "nightlight"
                }
                WeatherInfoRow {
                    label: "Illumination"
                    value: root.cur.moonIllum !== null && root.cur.moonIllum !== undefined
                        ? Logic.formatPercent(root.cur.moonIllum)
                        : "--"
                    icon: "brightness_6"
                }
                WeatherInfoRow {
                    label: "Sunrise"
                    value: root.cur.sunrise ? Logic.formatTime(root.cur.sunrise, root.offset, WeatherAppService.use24h) : "--"
                    icon: "wb_twilight"
                }
                WeatherInfoRow {
                    label: "Sunset"
                    value: root.cur.sunset ? Logic.formatTime(root.cur.sunset, root.offset, WeatherAppService.use24h) : "--"
                    icon: "wb_twilight"
                }
                WeatherInfoRow {
                    label: "Moonrise"
                    value: root.cur.moonrise ? Logic.formatTime(root.cur.moonrise, root.offset, WeatherAppService.use24h) : "--"
                    icon: "bedtime"
                }
                WeatherInfoRow {
                    label: "Moonset"
                    value: root.cur.moonset ? Logic.formatTime(root.cur.moonset, root.offset, WeatherAppService.use24h) : "--"
                    icon: "dark_mode"
                }
                WeatherInfoRow {
                    label: "Daylight"
                    value: root.cur.sunrise && root.cur.sunset
                        ? Logic.formatDaylight((root.cur.sunset - root.cur.sunrise) / 1000)
                        : "--"
                    icon: "light_mode"
                }
            }
        }
    }

    // ── Source ──────────────────────────────────────────────────────────
    WeatherSection {
        title: "Data source"
        subtitle: root.data?.source?.attribution || ""
        icon: "cloud"
        actionLabel: "Website"
        onActionClicked: {
            if (root.data?.source?.url)
                Qt.openUrlExternally(root.data.source.url);
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 5

            WeatherInfoRow {
                label: "Provider"
                value: root.data?.providerName || WeatherAppService.providerLabel
                icon: "cloud"
            }
            WeatherInfoRow {
                label: "Model"
                value: Logic.providerModelLabel(root.data) || "Default"
                icon: "memory"
            }
            WeatherInfoRow {
                label: "Updated"
                value: WeatherAppService.lastFetchTime > 0
                    ? Logic.formatDateTime(WeatherAppService.lastFetchTime, root.offset, WeatherAppService.use24h) + ` (${Logic.timeAgo(WeatherAppService.lastFetchTime)})`
                    : "--"
                icon: "schedule"
            }
            WeatherInfoRow {
                label: "Coordinates"
                value: root.data?.location
                    ? `${Logic.formatNumber(root.data.location.latitude, 3)}, ${Logic.formatNumber(root.data.location.longitude, 3)}`
                    : "--"
                icon: "location_on"
            }
            WeatherInfoRow {
                label: "Timezone"
                value: root.data?.timezone || "--"
                icon: "public"
            }
            WeatherInfoRow {
                label: "Air quality source"
                value: root.data?.airQuality?.source || "--"
                icon: "masks"
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: root.data?.source?.attribution || ""
        font.pixelSize: WeatherStyle.textTiny
        color: WeatherStyle.colSubtext
        wrapMode: Text.Wrap
    }
}
