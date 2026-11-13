pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import ".."
import "../components"
import "../../../../services/WeatherAppLogic.js" as Logic

/**
 * The page you see first: one honest summary of now, then the shortest path into the
 * rest of the forecast. Every section is a real section, not a card inside a card.
 */
WeatherPage {
    id: root

    property real layoutWidth: width
    property bool compact: false
    property bool wide: false

    signal requestTab(string tabId)
    signal chartRequested(string chartId)

    readonly property var cur: WeatherAppService.current
    readonly property var units: WeatherAppService.units
    readonly property int offset: WeatherAppService.data?.utcOffset ?? 0
    readonly property string locationName: WeatherAppService.data?.location?.name || WeatherAppService.resolvedLocation?.name || "Weather"
    readonly property string providerText: Logic.providerModelLabel(WeatherAppService.data) || WeatherAppService.providerLabel
    readonly property bool hasAq: root.cur && root.cur.aqi !== null && root.cur.aqi !== undefined
    readonly property int metricColumns: root.layoutWidth >= 1040 ? 4 : (root.layoutWidth >= 700 ? 3 : 2)
    readonly property var dailyDomain: {
        let minimum = Infinity;
        let maximum = -Infinity;
        for (const day of WeatherAppService.daily.slice(0, 5)) {
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
    readonly property string pageSubtitle: WeatherAppService.hasData
        ? `${root.locationName} · ${root.providerText}`
        : "Fetching a forecast"

    readonly property var quickStats: [
        {
            icon: "thermostat",
            label: "Feels",
            value: Logic.formatTemperature(root.cur.feelsC, root.units),
            tone: "primary"
        },
        {
            icon: "humidity_percentage",
            label: "Humidity",
            value: Logic.formatPercent(root.cur.humidity),
            tone: "secondary"
        },
        {
            icon: "air",
            label: "Wind",
            value: Logic.formatWind(root.cur.windKmh, root.units),
            tone: "tertiary"
        },
        {
            icon: "rainy",
            label: "Rain",
            value: Logic.formatPercent(root.cur.precipProb),
            tone: WeatherStyle.rainTone(root.cur.precipProb)
        },
        {
            icon: "wb_sunny",
            label: "UV",
            value: Logic.formatUv(root.cur.uv),
            tone: WeatherStyle.uvTone(root.cur.uv)
        },
        {
            icon: "speed",
            label: "Pressure",
            value: Logic.formatPressure(root.cur.pressureHpa, root.units),
            tone: "primary"
        }
    ]

    readonly property var heroStats: root.quickStats.map(stat => Object.assign({}, stat, { chartId: root.chartIdFor(stat.label) }))

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

    function chartIdFor(label) {
        switch (label) {
        case "Temperature":
        case "Feels like":
        case "Feels": return "temperature";
        case "Dew point": return "dew";
        case "Humidity": return "humidity";
        case "Pressure": return "pressure";
        case "Wind":
        case "Gusts": return "wind";
        case "Visibility": return "visibility";
        case "Cloud cover": return "cloud";
        case "UV index":
        case "UV": return "uv";
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

    readonly property var metrics: {
        const trend = Logic.pressureTrend(root.cur.pressureHpa, WeatherAppService.hourly[0]?.pressureHpa);
        return [
            {
                label: "Feels like",
                value: Logic.formatTemperature(root.cur.feelsC, root.units),
                subtext: "Air " + Logic.formatTemperature(root.cur.tempC, root.units),
                icon: "thermostat",
                tone: "primary"
            },
            {
                label: "Humidity",
                value: Logic.formatPercent(root.cur.humidity),
                subtext: Logic.humidityComfort(root.cur.humidity),
                icon: "humidity_percentage",
                tone: "secondary"
            },
            {
                label: "Wind",
                value: Logic.formatWind(root.cur.windKmh, root.units),
                subtext: `${Logic.windDirection(root.cur.windDirDeg)} · gusts ${Logic.formatWind(root.cur.gustKmh, root.units)}`,
                icon: "air",
                tone: "tertiary"
            },
            {
                label: "Precipitation",
                value: Logic.formatPercent(root.cur.precipProb),
                subtext: `${Logic.formatPrecip(root.cur.precipMm, root.units)} expected`,
                icon: "rainy",
                tone: WeatherStyle.rainTone(root.cur.precipProb)
            },
            {
                label: "Pressure",
                value: Logic.formatPressure(root.cur.pressureHpa, root.units),
                subtext: trend.label,
                icon: "speed",
                tone: "primary"
            },
            {
                label: "UV index",
                value: Logic.formatUv(root.cur.uv),
                subtext: Logic.uvCategory(root.cur.uv).label,
                icon: "wb_sunny",
                tone: WeatherStyle.uvTone(root.cur.uv)
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
                subtext: root.cur.isDay ? "Daytime" : "Night",
                icon: "cloud",
                tone: "tertiary"
            },
            {
                label: "Dew point",
                value: Logic.formatTemperature(root.cur.dewC, root.units),
                subtext: "Condensation point",
                icon: "water_drop",
                tone: "secondary"
            }
        ];
    }

    readonly property var aqMetrics: [
        {
            label: "PM2.5",
            value: Logic.formatNumber(root.cur.pm25, 1) + " µg/m³",
            subtext: "Fine particles",
            icon: "grain",
            tone: "primary"
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
            label: "Pollen",
            value: Logic.formatNumber(root.cur.pollen?.total, 1),
            subtext: Logic.pollenCategory(root.cur.pollen?.total).label,
            icon: "local_florist",
            tone: Logic.pollenCategory(root.cur.pollen?.total).tone
        }
    ]

    // ── Reorderable blocks ─────────────────────────────────────────────
    readonly property var defaultBlockOrder: ["hero", "hourly", "daily", "conditions", "airQuality", "astronomy"]
    property var blockOrder: root.defaultBlockOrder
    property int dragFrom: -1

    property Component heroBlock: Component {
        WeatherHero {
            cur: root.cur
            units: root.units
            offset: root.offset
            compact: root.compact
            locationName: root.locationName
            providerText: root.providerText
            stats: root.heroStats
            onStatTriggered: label => root.chartRequested(root.chartIdFor(label))
        }
    }

    property Component hourlyBlock: Component {
    // ── Next hours ──────────────────────────────────────────────────────
    WeatherSection {
        title: "Next hours"
        subtitle: "Temperature, rain chance and wind"
        icon: "schedule"
        actionLabel: "Hourly"
        onActionClicked: root.requestTab("hourly")

        WeatherHourlyStrip {
            Layout.fillWidth: true
            hours: WeatherAppService.hourly
            units: root.units
            offset: root.offset
            use24h: WeatherAppService.use24h
            maxItems: 24
        }
    }
    }

    property Component dailyBlock: Component {
    // ── Daily preview ───────────────────────────────────────────────────
    WeatherSection {
        title: "Daily forecast"
        subtitle: WeatherAppService.settings.provider === "brightSky" ? "Station-based DWD forecast" : "The next few days at a glance"
        icon: "calendar_month"
        actionLabel: "All days"
        onActionClicked: root.requestTab("daily")
        contentSpacing: 2

        Repeater {
            model: WeatherAppService.daily.slice(0, 5)

            WeatherDailyRow {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                day: modelData
                dayIndex: index
                offset: root.offset
                units: root.units
                use24h: WeatherAppService.use24h
                domainMin: root.dailyDomain.min
                domainMax: root.dailyDomain.max
                compact: root.layoutWidth < 680
                onClicked: root.requestTab("daily")
            }
        }
    }
    }

    property Component conditionsBlock: Component {
    // ── Conditions ──────────────────────────────────────────────────────
    WeatherSection {
        title: "Conditions"
        subtitle: "Tap a condition to open its chart"
        icon: "explore"

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
    }

    property Component airQualityBlock: Component {
    // ── Air quality ─────────────────────────────────────────────────────
    WeatherSection {
        visible: root.hasAq
        title: "Air quality & pollen"
        subtitle: "Tap a pollutant for its chart · Open-Meteo / CAMS supplement"
        icon: "masks"

        GridLayout {
            Layout.fillWidth: true
            columns: root.layoutWidth >= 760 ? 2 : 1
            columnSpacing: WeatherStyle.gapLarge
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
    }

    property Component astronomyBlock: Component {
    // ── Sun and moon ────────────────────────────────────────────────────
    WeatherSection {
        title: "Sun & moon"
        subtitle: "Calculated locally when the forecast source omits it"
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
                spacing: WeatherStyle.gapSmall

                RowLayout {
                    Layout.fillWidth: true
                    spacing: WeatherStyle.gapSmall

                    MaterialSymbol {
                        text: "nightlight"
                        iconSize: 20
                        fill: 1
                        color: WeatherStyle.colTertiary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: root.cur.moonPhaseName || "Moon"
                            font.pixelSize: WeatherStyle.textSmall
                            font.weight: Font.DemiBold
                            color: WeatherStyle.colOnSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.cur.moonIllum !== null && root.cur.moonIllum !== undefined
                                ? `${Logic.formatPercent(root.cur.moonIllum)} illuminated`
                                : "Illumination unavailable"
                            font.pixelSize: WeatherStyle.textTiny
                            color: WeatherStyle.colSubtext
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: WeatherStyle.colOutline
                    opacity: 0.35
                }

                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: "Moonrise"
                        font.pixelSize: WeatherStyle.textTiny
                        color: WeatherStyle.colSubtext
                    }
                    StyledText {
                        text: root.cur.moonrise ? Logic.formatTime(root.cur.moonrise, root.offset, WeatherAppService.use24h) : "--"
                        font.pixelSize: WeatherStyle.textTiny
                        color: WeatherStyle.colOnSurfaceVariant
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: "Moonset"
                        font.pixelSize: WeatherStyle.textTiny
                        color: WeatherStyle.colSubtext
                    }
                    StyledText {
                        text: root.cur.moonset ? Logic.formatTime(root.cur.moonset, root.offset, WeatherAppService.use24h) : "--"
                        font.pixelSize: WeatherStyle.textTiny
                        color: WeatherStyle.colOnSurfaceVariant
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: "Daylight"
                        font.pixelSize: WeatherStyle.textTiny
                        color: WeatherStyle.colSubtext
                    }
                    StyledText {
                        text: root.cur.sunrise && root.cur.sunset
                            ? Logic.formatDaylight((root.cur.sunset - root.cur.sunrise) / 1000)
                            : "--"
                        font.pixelSize: WeatherStyle.textTiny
                        color: WeatherStyle.colOnSurfaceVariant
                    }
                }
            }
        }
    }
    }

    function componentFor(id) {
        switch (id) {
        case "hero": return root.heroBlock;
        case "hourly": return root.hourlyBlock;
        case "daily": return root.dailyBlock;
        case "conditions": return root.conditionsBlock;
        case "airQuality": return root.airQualityBlock;
        case "astronomy": return root.astronomyBlock;
        default: return null;
        }
    }

    function loadBlockOrder() {
        let saved = [];
        try {
            saved = JSON.parse(WeatherAppService.settings.overviewOrderJson || "[]");
        } catch (e) {
            saved = [];
        }
        const order = [];
        for (const id of saved) {
            if (root.defaultBlockOrder.includes(id) && !order.includes(id))
                order.push(id);
        }
        for (const id of root.defaultBlockOrder) {
            if (!order.includes(id))
                order.push(id);
        }
        if (JSON.stringify(order) === JSON.stringify(root.blockOrder))
            return;
        root.blockOrder = order;
    }

    function saveBlockOrder() {
        WeatherAppService.setOverviewOrder(root.blockOrder);
    }

    function finishBlockDrag(slot) {
        const from = root.blockOrder.indexOf(slot.modelData);
        if (from < 0)
            return;
        const center = slot.y + slot.height / 2 + slot.dragOffset;
        let target = 0;
        for (let i = 0; i < blockRepeater.count; i++) {
            const other = blockRepeater.itemAt(i);
            if (!other || other === slot || !other.visible || other.height <= 0)
                continue;
            if (other.y + other.height / 2 < center)
                target++;
        }
        const order = Array.from(root.blockOrder);
        const [id] = order.splice(from, 1);
        order.splice(Math.max(0, Math.min(target, order.length)), 0, id);
        slot.dragOffset = 0;
        root.blockOrder = order;
        root.saveBlockOrder();
        root.dragFrom = -1;
    }

    Component.onCompleted: root.loadBlockOrder()

    Connections {
        target: WeatherAppService.settings
        function onOverviewOrderJsonChanged() {
            root.loadBlockOrder();
        }
    }

    // ── The block canvas ───────────────────────────────────────────────
    Column {
        id: blocksColumn
        width: parent.width
        Layout.preferredWidth: parent.width
        Layout.fillWidth: true
        spacing: WeatherStyle.gapHuge

        Repeater {
            id: blockRepeater
            model: root.blockOrder

            Item {
                id: blockSlot
                required property string modelData
                required property int index

                width: blocksColumn.width
                height: blockLoader.item ? (blockLoader.item.visible ? blockLoader.item.implicitHeight : 0) : 0
                z: dragHandler.active ? 50 : 0

                property real dragOffset: 0
                property bool dragging: dragHandler.active

                Behavior on y {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on dragOffset {
                    enabled: !blockSlot.dragging
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }

                transform: Translate {
                    y: blockSlot.dragOffset
                }

                Loader {
                    id: blockLoader
                    width: parent.width
                    sourceComponent: root.componentFor(blockSlot.modelData)
                    onLoaded: if (item) item.width = Qt.binding(() => blockLoader.width)
                }

                HoverHandler {
                    id: slotHover
                }

                Rectangle {
                    id: dragHandle
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 2
                    width: 36
                    height: 18
                    radius: WeatherStyle.radiusFull
                    color: WeatherStyle.alpha(WeatherStyle.colSurfaceHighest, 0.95)
                    border.width: 1
                    border.color: WeatherStyle.alpha(WeatherStyle.colOutline, 0.5)
                    opacity: blockSlot.dragging || slotHover.hovered ? 1 : 0
                    visible: opacity > 0
                    z: 20

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "drag_indicator"
                        iconSize: 14
                        color: WeatherStyle.colOnSurfaceVariant
                    }

                    HoverHandler {
                        cursorShape: Qt.OpenHandCursor
                    }

                    DragHandler {
                        id: dragHandler
                        target: null
                        xAxis.enabled: false
                        yAxis.enabled: true
                        dragThreshold: 4
                        grabPermissions: PointerHandler.CanTakeOverFromAnything
                        onActiveChanged: {
                            if (active) {
                                root.dragFrom = blockSlot.index;
                            } else {
                                root.finishBlockDrag(blockSlot);
                            }
                        }
                        onActiveTranslationChanged: {
                            blockSlot.dragOffset = dragHandler.activeTranslation.y;
                        }
                    }
                }
            }
        }
    }

    // ── Attribution ─────────────────────────────────────────────────────
    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: -WeatherStyle.gapSmall
        horizontalAlignment: Text.AlignHCenter
        text: WeatherAppService.data?.source?.attribution || ""
        font.pixelSize: WeatherStyle.textTiny
        color: WeatherStyle.colSubtext
        wrapMode: Text.Wrap
    }
}
