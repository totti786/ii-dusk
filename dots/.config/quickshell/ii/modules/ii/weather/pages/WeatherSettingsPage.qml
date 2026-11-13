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
 * Settings are the app's only write surface: source, place, units and what to fetch.
 * Everything is applied immediately; there is no Save button to forget.
 */
WeatherPage {
    id: root

    property real layoutWidth: width
    property bool compact: false
    property bool wide: false

    readonly property var units: WeatherAppService.units
    readonly property string pageSubtitle: "Sources, place, units and refresh"
    readonly property int providerColumns: root.layoutWidth >= 920 ? 2 : 1
    readonly property var availableProviders: WeatherAppService.providerCatalog.filter(provider =>
        WeatherAppService.providerSupportsLocation(provider,
            WeatherAppService.resolvedLocation?.country ? WeatherAppService.resolvedLocation : (WeatherAppService.activeLocation || {})))

    ClockHero {
        Layout.fillWidth: true
        symbol: "settings"
        shape: MaterialShape.Shape.Cookie9Sided
        title: "Make it yours"
        text: "Choose where the forecast comes from, your place, units and how often it refreshes. Changes take effect on the next update."
        compact: root.compact
    }

    // ── Error ───────────────────────────────────────────────────────────
    WeatherSection {
        visible: WeatherAppService.error.length > 0 || WeatherAppService.missingKey
        flat: true
        title: "The last update failed"
        icon: "error"
        contentSpacing: WeatherStyle.gapSmall

        StyledText {
            Layout.fillWidth: true
            text: WeatherAppService.error
            font.pixelSize: WeatherStyle.textSmall
            color: WeatherStyle.colOnSurfaceVariant
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: WeatherStyle.gapSmall

            WeatherChip {
                iconName: "refresh"
                label: "Try again"
                onClicked: WeatherAppService.refresh(true)
            }

            WeatherChip {
                iconName: "close"
                label: "Dismiss"
                onClicked: WeatherAppService.dismissError()
            }
        }
    }

    // ── Weather sources ──────────────────────────────────────────────────
    WeatherSection {
        title: "Weather sources"
        subtitle: "Only keyless sources that work for this location are shown. Selecting one merges its forecast with the shared air-quality and pollen sources."
        icon: "cloud"

        GridLayout {
            Layout.fillWidth: true
            columns: root.providerColumns
            rowSpacing: WeatherStyle.gapSmall
            columnSpacing: WeatherStyle.gapSmall

            Repeater {
                model: root.availableProviders

                WeatherProviderCard {
                    required property var modelData
                    provider: modelData
                    selected: WeatherAppService.settings.provider === modelData.id
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: WeatherStyle.gapTiny
            implicitHeight: 1
            color: WeatherStyle.colOutline
            opacity: 0.3
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: WeatherStyle.gapSmall

            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: "masks"
                iconSize: 17
                color: WeatherStyle.colSecondary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: "Air quality & pollen · Open-Meteo / CAMS"
                    font.pixelSize: WeatherStyle.textSmall
                    font.weight: Font.Medium
                    color: WeatherStyle.colOnSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "Shared by every forecast source, so the AQI and pollen charts stay comparable."
                    font.pixelSize: WeatherStyle.textTiny
                    color: WeatherStyle.colSubtext
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    // ── Location ────────────────────────────────────────────────────────
    WeatherSection {
        title: "Location"
        subtitle: "Search a city, use GPS, or switch between saved places"
        icon: "location_on"

        WeatherLocationManager {
            Layout.fillWidth: true
        }
    }

    // ── Units ───────────────────────────────────────────────────────────
    WeatherSection {
        title: "Units"
        subtitle: "Internal data stays metric; only the display changes"
        icon: "straighten"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: WeatherStyle.gapLarge

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    text: "Temperature"
                    font.pixelSize: WeatherStyle.textSmall
                    font.weight: Font.Medium
                    color: WeatherStyle.colOnSurface
                }

                WeatherOptionChips {
                    Layout.fillWidth: true
                    options: [
                        { value: "c", label: "Celsius · °C" },
                        { value: "f", label: "Fahrenheit · °F" }
                    ]
                    value: root.units.temperature
                    onSelected: value => WeatherAppService.setUnit("temperature", value)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    text: "Wind speed"
                    font.pixelSize: WeatherStyle.textSmall
                    font.weight: Font.Medium
                    color: WeatherStyle.colOnSurface
                }

                WeatherOptionChips {
                    Layout.fillWidth: true
                    options: [
                        { value: "kmh", label: "km/h" },
                        { value: "mph", label: "mph" },
                        { value: "ms", label: "m/s" },
                        { value: "kn", label: "knots" }
                    ]
                    value: root.units.wind
                    onSelected: value => WeatherAppService.setUnit("wind", value)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    text: "Precipitation"
                    font.pixelSize: WeatherStyle.textSmall
                    font.weight: Font.Medium
                    color: WeatherStyle.colOnSurface
                }

                WeatherOptionChips {
                    Layout.fillWidth: true
                    options: [
                        { value: "mm", label: "Millimetres" },
                        { value: "in", label: "Inches" }
                    ]
                    value: root.units.precip
                    onSelected: value => WeatherAppService.setUnit("precip", value)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    text: "Pressure"
                    font.pixelSize: WeatherStyle.textSmall
                    font.weight: Font.Medium
                    color: WeatherStyle.colOnSurface
                }

                WeatherOptionChips {
                    Layout.fillWidth: true
                    options: [
                        { value: "hpa", label: "hPa" },
                        { value: "inhg", label: "inHg" }
                    ]
                    value: root.units.pressure
                    onSelected: value => WeatherAppService.setUnit("pressure", value)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    text: "Visibility"
                    font.pixelSize: WeatherStyle.textSmall
                    font.weight: Font.Medium
                    color: WeatherStyle.colOnSurface
                }

                WeatherOptionChips {
                    Layout.fillWidth: true
                    options: [
                        { value: "km", label: "Kilometres" },
                        { value: "mi", label: "Miles" }
                    ]
                    value: root.units.visibility
                    onSelected: value => WeatherAppService.setUnit("visibility", value)
                }
            }
        }
    }

    // ── Charts ──────────────────────────────────────────────────────────
    WeatherSection {
        title: "Charts"
        subtitle: "Click any condition card to open its chart"
        icon: "show_chart"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: WeatherStyle.gapSmall

            StyledText {
                text: "Chart palette"
                font.pixelSize: WeatherStyle.textSmall
                font.weight: Font.Medium
                color: WeatherStyle.colOnSurface
            }

            WeatherOptionChips {
                Layout.fillWidth: true
                options: [
                    { value: "theme", label: "Follow theme" },
                    { value: "vivid", label: "Vivid weather" }
                ]
                value: WeatherAppService.settings.accentMode
                onSelected: value => WeatherAppService.setAccentMode(value)
            }

            Row {
                spacing: 6

                Rectangle {
                    width: 18
                    height: 8
                    radius: 4
                    color: WeatherStyle.chartColor("primary")
                }
                Rectangle {
                    width: 18
                    height: 8
                    radius: 4
                    color: WeatherStyle.chartColor("secondary")
                }
                Rectangle {
                    width: 18
                    height: 8
                    radius: 4
                    color: WeatherStyle.chartColor("tertiary")
                }
                Rectangle {
                    width: 18
                    height: 8
                    radius: 4
                    color: WeatherStyle.chartColor("error")
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: "Follow theme tints a weather palette with your Material colours, so series stay readable even when the theme is nearly monochrome. Vivid weather uses fully saturated hues; the rest of the app still follows the theme."
                font.pixelSize: WeatherStyle.textTiny
                color: WeatherStyle.colSubtext
                wrapMode: Text.Wrap
            }
        }
    }

    // ── Refresh and data ────────────────────────────────────────────────
    WeatherSection {
        title: "Refresh"
        subtitle: "How often the app reaches out, and what it brings back"
        icon: "sync"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: WeatherStyle.gapLarge

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    text: "Automatic refresh"
                    font.pixelSize: WeatherStyle.textSmall
                    font.weight: Font.Medium
                    color: WeatherStyle.colOnSurface
                }

                WeatherOptionChips {
                    Layout.fillWidth: true
                    options: [
                        { value: 5, label: "5 min" },
                        { value: 10, label: "10 min" },
                        { value: 15, label: "15 min" },
                        { value: 30, label: "30 min" },
                        { value: 60, label: "60 min" }
                    ]
                    value: WeatherAppService.settings.refreshMinutes
                    onSelected: value => WeatherAppService.setRefreshMinutes(value)
                }
            }

            WeatherSettingsRow {
                label: "Air quality & pollen"
                description: "Adds AQI, particulate, gas and pollen charts from Open-Meteo/CAMS."
                StyledSwitch {
                    checked: WeatherAppService.settings.includeAirQuality
                    onToggled: WeatherAppService.setIncludeAirQuality(checked)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: WeatherStyle.colOutline
                opacity: 0.3
            }

            WeatherInfoRow {
                label: "Last successful update"
                value: WeatherAppService.lastFetchTime > 0
                    ? `${Logic.formatDateTime(WeatherAppService.lastFetchTime, WeatherAppService.data?.utcOffset ?? 0, WeatherAppService.use24h)} (${Logic.timeAgo(WeatherAppService.lastFetchTime)})`
                    : "Never"
                icon: "schedule"
            }

            WeatherInfoRow {
                label: "Active place"
                value: WeatherAppService.settings.useGps
                    ? "Current location (GPS)"
                    : (WeatherAppService.activeLocation?.name || "Default")
                icon: "location_on"
            }

            WeatherInfoRow {
                label: "Forecast provider"
                value: Logic.providerModelLabel(WeatherAppService.data) || WeatherAppService.providerLabel
                icon: "cloud"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: WeatherStyle.gapSmall

                WeatherChip {
                    iconName: "refresh"
                    label: "Refresh now"
                    onClicked: WeatherAppService.refresh(true)
                }

                Item { Layout.fillWidth: true }

                StyledText {
                    text: WeatherAppService.stale ? "Data may be stale" : "Cache is current"
                    font.pixelSize: WeatherStyle.textTiny
                    color: WeatherAppService.stale ? WeatherStyle.colError : WeatherStyle.colSubtext
                }
            }
        }
    }

    // ── About ───────────────────────────────────────────────────────────
    WeatherSection {
        title: "About"
        subtitle: "A floating forecast for the ii shell"
        icon: "info"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 5

            StyledText {
                Layout.fillWidth: true
                text: "Weather for ii reuses the same Material 3 tokens as the bar, panels and other apps. Forecast data is normalized to °C, km/h, mm and hPa internally, then converted only for display."
                font.pixelSize: WeatherStyle.textTiny
                color: WeatherStyle.colSubtext
                wrapMode: Text.Wrap
            }

            WeatherInfoRow {
                label: "Settings file"
                value: WeatherAppService.settingsPath
                icon: "description"
            }

            WeatherInfoRow {
                label: "Keyboard"
                value: "Ctrl+R refresh · Esc close · Ctrl+1…6 pages"
                icon: "keyboard"
            }

            WeatherInfoRow {
                label: "Provider attribution"
                value: WeatherAppService.data?.source?.attribution || "Select a provider to fetch data"
                icon: "verified"
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: WeatherStyle.gapTiny
                text: "Location search uses Open-Meteo geocoding. GPS coordinates stay local. The app only uses keyless sources, so there is no account or API key to store."
                font.pixelSize: WeatherStyle.textTiny
                color: WeatherStyle.colSubtext
                wrapMode: Text.Wrap
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: "Weather for ii"
        font.pixelSize: WeatherStyle.textTiny
        color: WeatherStyle.colSubtext
    }
}
