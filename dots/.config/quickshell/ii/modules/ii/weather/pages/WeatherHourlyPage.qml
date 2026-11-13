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
 * The full hourly table, grouped by local day. The overview shows the shape of the next
 * hours; this page is for reading the exact numbers.
 */
WeatherPage {
    id: root

    property real layoutWidth: width
    property bool compact: false
    property bool wide: false
    property int selectedRange: 24

    readonly property var cur: WeatherAppService.current
    readonly property var units: WeatherAppService.units
    readonly property int offset: WeatherAppService.data?.utcOffset ?? 0
    readonly property string pageSubtitle: "Hour-by-hour forecast · " + (Logic.providerModelLabel(WeatherAppService.data) || WeatherAppService.providerLabel)

    readonly property var hourGroups: {
        const hours = WeatherAppService.hourly.slice(0, root.selectedRange);
        const offset = root.offset;
        const groups = [];
        for (const hour of hours) {
            const key = Logic.localDayKey(hour.time, offset);
            let group = groups.length > 0 ? groups[groups.length - 1] : null;
            if (!group || group.key !== key) {
                const daily = WeatherAppService.daily.find(day => Logic.localDayKey(day.time, offset) === key);
                group = {
                    key: key,
                    time: hour.time,
                    label: Logic.dayLabel(hour.time, offset, groups.length),
                    date: Logic.formatMonthDay(hour.time, offset),
                    minC: daily?.minC ?? null,
                    maxC: daily?.maxC ?? null,
                    sunrise: daily?.sunrise ?? null,
                    sunset: daily?.sunset ?? null,
                    hours: []
                };
                groups.push(group);
            }
            group.hours.push(hour);
        }
        return groups;
    }

    readonly property var windowHours: WeatherAppService.hourly.slice(0, root.selectedRange)
    readonly property string heroText: {
        const temps = root.windowHours.map(h => Logic.temperatureValue(h.tempC, root.units)).filter(v => v !== null && Number.isFinite(v));
        if (temps.length === 0)
            return "Times are local to the selected place.";
        const rain = Math.max(0, ...root.windowHours.map(h => Number(h.precipProb) || 0));
        const low = Logic.formatTemperature(root.windowHours.find(h => Logic.temperatureValue(h.tempC, root.units) === Math.min(...temps))?.tempC, root.units);
        const high = Logic.formatTemperature(root.windowHours.find(h => Logic.temperatureValue(h.tempC, root.units) === Math.max(...temps))?.tempC, root.units);
        return `${low} to ${high}, ${rain >= 15 ? "up to " + Math.round(rain) + "% chance of rain" : "no rain expected"}. Times are local to the selected place.`;
    }

    ClockHero {
        Layout.fillWidth: true
        symbol: "schedule"
        shape: MaterialShape.Shape.Clover4Leaf
        title: `The next ${root.selectedRange} hours`
        text: root.heroText
        compact: root.compact
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: WeatherStyle.gapLarge

        Item {
            Layout.fillWidth: true
        }

        WeatherOptionChips {
            Layout.alignment: Qt.AlignVCenter
            options: [
                { value: 24, label: "24 h" },
                { value: 48, label: "48 h" },
                { value: 72, label: "72 h" }
            ]
            value: root.selectedRange
            onSelected: value => root.selectedRange = value
        }
    }

    Repeater {
        id: groupRepeater
        model: root.hourGroups

        WeatherSection {
            id: daySection
            required property var modelData
            Layout.fillWidth: true
            title: modelData.label
            subtitle: `${modelData.date}${modelData.minC !== null && modelData.maxC !== null ? " · H " + Logic.formatTemperature(modelData.maxC, root.units) + "  L " + Logic.formatTemperature(modelData.minC, root.units) : ""}`
            icon: "schedule"
            contentSpacing: 2

            Repeater {
                model: daySection.modelData.hours

                WeatherHourRow {
                    required property var modelData
                    Layout.fillWidth: true
                    hour: modelData
                    offset: root.offset
                    units: root.units
                    use24h: WeatherAppService.use24h
                    compact: root.compact
                    // the hour that contains now: a half-open window, so two rows never both read "Now"
                    current: Date.now() >= modelData.time && Date.now() < modelData.time + 3600000
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: WeatherAppService.data?.source?.attribution || ""
        font.pixelSize: WeatherStyle.textTiny
        color: WeatherStyle.colSubtext
        wrapMode: Text.Wrap
    }
}
