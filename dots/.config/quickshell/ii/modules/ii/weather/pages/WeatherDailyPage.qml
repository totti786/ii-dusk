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
 * The daily page is a list you can open. The range strip answers "which day is warmer"
 * before the rows answer "why".
 */
WeatherPage {
    id: root

    property real layoutWidth: width
    property bool compact: false
    property bool wide: false
    property int daysShown: 14
    property int selectedIndex: 0

    readonly property var units: WeatherAppService.units
    readonly property int offset: WeatherAppService.data?.utcOffset ?? 0
    readonly property string pageSubtitle: "Daily forecast · " + (Logic.providerModelLabel(WeatherAppService.data) || WeatherAppService.providerLabel)
    readonly property var shownDays: WeatherAppService.daily.slice(0, root.daysShown)

    readonly property var rangeDays: root.shownDays.map((day, index) => ({
        time: day.time,
        label: Logic.dayLabel(day.time, root.offset, index),
        date: Logic.formatMonthDay(day.time, root.offset),
        min: Logic.temperatureValue(day.minC, root.units),
        max: Logic.temperatureValue(day.maxC, root.units),
        minLabel: Logic.formatTemperature(day.minC, root.units),
        maxLabel: Logic.formatTemperature(day.maxC, root.units),
        condition: day.condition,
        isDay: true
    }))

    readonly property var domain: {
        let minimum = Infinity;
        let maximum = -Infinity;
        for (const day of root.shownDays) {
            const low = Logic.temperatureValue(day.minC, root.units);
            const high = Logic.temperatureValue(day.maxC, root.units);
            if (low !== null) minimum = Math.min(minimum, low);
            if (high !== null) maximum = Math.max(maximum, high);
        }
        if (!Number.isFinite(minimum) || !Number.isFinite(maximum))
            return { min: 0, max: 1 };
        if (minimum === maximum) {
            minimum -= 1;
            maximum += 1;
        }
        return { min: minimum, max: maximum };
    }

    readonly property string heroText: {
        const lows = root.shownDays.map(d => Logic.temperatureValue(d.minC, root.units)).filter(v => v !== null && Number.isFinite(v));
        const highs = root.shownDays.map(d => Logic.temperatureValue(d.maxC, root.units)).filter(v => v !== null && Number.isFinite(v));
        if (lows.length === 0 || highs.length === 0)
            return "Tap a day to open its details.";
        const wet = root.shownDays.filter(d => (Number(d.precipProb) || 0) >= 40).length;
        const lo = Logic.formatTemperature(root.shownDays.find(d => Logic.temperatureValue(d.minC, root.units) === Math.min(...lows))?.minC, root.units);
        const hi = Logic.formatTemperature(root.shownDays.find(d => Logic.temperatureValue(d.maxC, root.units) === Math.max(...highs))?.maxC, root.units);
        return `${lo} to ${hi}, ${wet === 0 ? "no rainy days" : wet === 1 ? "one rainy day" : wet + " rainy days"}. Tap a day to open its details.`;
    }

    ClockHero {
        Layout.fillWidth: true
        symbol: "calendar_month"
        shape: MaterialShape.Shape.Cookie12Sided
        title: `The next ${root.shownDays.length} days`
        text: root.heroText
        compact: root.compact
    }

    RowLayout {
        Layout.fillWidth: true

        Item {
            Layout.fillWidth: true
        }

        WeatherOptionChips {
            Layout.alignment: Qt.AlignVCenter
            options: [
                { value: 7, label: "7 days" },
                { value: 10, label: "10 days" },
                { value: 14, label: "14 days" }
            ]
            value: root.daysShown
            onSelected: value => root.daysShown = value
        }
    }

    WeatherSection {
        title: "Days"
        subtitle: root.shownDays.length > 0 ? "Low, high and the weather between" : "No daily forecast for this source"
        icon: "calendar_month"
        contentSpacing: 2

        Repeater {
            model: root.shownDays

            ColumnLayout {
                id: dayColumn
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 2

                WeatherDailyRow {
                    Layout.fillWidth: true
                    day: dayColumn.modelData
                    dayIndex: dayColumn.index
                    offset: root.offset
                    units: root.units
                    use24h: WeatherAppService.use24h
                    domainMin: root.domain.min
                    domainMax: root.domain.max
                    selected: root.selectedIndex === dayColumn.index
                    compact: root.compact
                    onClicked: root.selectedIndex = root.selectedIndex === dayColumn.index ? -1 : dayColumn.index
                }

                WeatherDailyDetail {
                    visible: root.selectedIndex === dayColumn.index
                    day: dayColumn.modelData
                    units: root.units
                    offset: root.offset
                    use24h: WeatherAppService.use24h
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
