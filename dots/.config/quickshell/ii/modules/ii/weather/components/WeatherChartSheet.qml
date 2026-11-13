import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import ".."
import "../../../../services/WeatherAppLogic.js" as Logic

/**
 * One condition, one chart. This is the whole of the old Charts page, reduced to the
 * thing the user actually asked for: click a condition, see its shape, close it.
 */
Rectangle {
    id: root

    property string chartId: ""
    property string range: "24h"
    signal closeRequested()

    readonly property var units: WeatherAppService.units
    readonly property var specs: Logic.buildCharts(WeatherAppService.data, root.units, root.range, WeatherAppService.use24h)
    readonly property var spec: root.specs.find(chart => chart.id === root.chartId) ?? null
    readonly property bool isRange: root.spec?.kind === "range"
    readonly property bool isDaily: root.spec?.group === "daily"
    readonly property var values: root.spec?.values ?? []
    readonly property var secondary: root.spec?.secondary ?? []
    readonly property var bars: root.spec?.bars ?? []
    readonly property string chartUnit: root.bars.length > 0 && root.values.length === 0
        ? (root.spec?.barUnit || root.spec?.unit || "")
        : (root.spec?.unit || "")
    readonly property color primaryColor: WeatherStyle.chartColor(root.spec?.tone || "primary")
    readonly property color secondaryColor: WeatherStyle.chartColor(root.spec?.secondaryTone || "tertiary")
    readonly property color barColor: WeatherStyle.chartColor(root.spec?.barTone || root.spec?.tone || "secondary")

    implicitWidth: 440
    radius: WeatherStyle.radiusCard
    color: WeatherStyle.colPane

    readonly property bool hasData: {
        if (!root.spec)
            return false;
        if (root.spec.kind === "range")
            return (root.spec.days || []).length > 0;
        return root.chartValuesHaveData(root.values) || root.chartValuesHaveData(root.secondary) || root.chartValuesHaveData(root.bars);
    }

    function chartValuesHaveData(list) {
        if (!list)
            return false;
        for (let i = 0; i < list.length; i++) {
            if (list[i] !== null && list[i] !== undefined && Number.isFinite(Number(list[i])))
                return true;
        }
        return false;
    }

    function finiteValues(list) {
        const result = [];
        for (const value of (list || [])) {
            if (value !== null && value !== undefined && Number.isFinite(Number(value)))
                result.push(Number(value));
        }
        return result;
    }

    function formatted(value) {
        if (value === null || value === undefined || !Number.isFinite(Number(value)))
            return "--";
        return Logic.formatChartValue(value, root.spec?.decimals ?? 0) + (root.chartUnit ? " " + root.chartUnit : "");
    }

    readonly property var stats: {
        if (!root.spec)
            return [];
        if (root.isRange) {
            const days = root.spec.days || [];
            let low = null, high = null;
            for (const day of days) {
                if (day.min !== null && day.min !== undefined)
                    low = low === null ? day.min : Math.min(low, day.min);
                if (day.max !== null && day.max !== undefined)
                    high = high === null ? day.max : Math.max(high, day.max);
            }
            return [
                { icon: "ac_unit", label: "Coolest", value: root.formatted(low), tone: "tertiary" },
                { icon: "wb_sunny", label: "Warmest", value: root.formatted(high), tone: "primary" },
                { icon: "calendar_month", label: "Days", value: String(days.length), tone: "secondary" }
            ];
        }

        if (root.bars.length > 0 && root.values.length === 0) {
            const list = root.finiteValues(root.bars);
            const total = list.reduce((sum, value) => sum + value, 0);
            const peak = list.length > 0 ? Math.max(...list) : null;
            const chanceList = root.finiteValues(root.secondary);
            const chance = chanceList.length > 0 ? Math.max(...chanceList) : null;
            return [
                { icon: "water_drop", label: "Total", value: root.formatted(total), tone: "primary" },
                { icon: "trending_up", label: "Peak", value: root.formatted(peak), tone: "tertiary" },
                { icon: "percent", label: "Chance", value: chance === null ? "--" : Logic.formatPercent(chance), tone: "secondary" }
            ];
        }

        const list = root.finiteValues(root.values);
        const current = list.length > 0 ? list[0] : null;
        const low = list.length > 0 ? Math.min(...list) : null;
        const high = list.length > 0 ? Math.max(...list) : null;
        return [
            { icon: "schedule", label: "Now", value: root.formatted(current), tone: "primary" },
            { icon: "trending_down", label: "Low", value: root.formatted(low), tone: "tertiary" },
            { icon: "trending_up", label: "High", value: root.formatted(high), tone: "secondary" }
        ];
    }

    readonly property var legend: {
        if (!root.spec)
            return [];
        if (root.isRange)
            return [
                { label: root.spec.primaryLabel || "Low", color: WeatherStyle.chartColor("tertiary") },
                { label: root.spec.secondaryLabel || "High", color: WeatherStyle.chartColor("primary") }
            ];
        if (root.bars.length > 0) {
            const items = [];
            if (root.spec.barLabel)
                items.push({ label: root.spec.barLabel, color: root.barColor });
            if (root.spec.secondaryLabel && root.chartValuesHaveData(root.secondary))
                items.push({ label: root.spec.secondaryLabel, color: root.secondaryColor });
            return items;
        }
        const items = [];
        if (root.spec.primaryLabel && root.chartValuesHaveData(root.values))
            items.push({ label: root.spec.primaryLabel, color: root.primaryColor });
        if (root.spec.secondaryLabel && root.chartValuesHaveData(root.secondary))
            items.push({ label: root.spec.secondaryLabel, color: root.secondaryColor });
        return items;
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: WeatherStyle.panePadding + 4
        }
        spacing: WeatherStyle.gap

        RowLayout {
            Layout.fillWidth: true
            spacing: WeatherStyle.gapSmall

            Rectangle {
                implicitWidth: 34
                implicitHeight: 34
                radius: WeatherStyle.radiusFull
                color: WeatherStyle.alpha(root.primaryColor, 0.14)

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.spec?.icon || "show_chart"
                    iconSize: 18
                    fill: 1
                    color: root.primaryColor
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.spec?.title || "Condition"
                    font.family: WeatherStyle.fontTitle
                    font.variableAxes: WeatherStyle.axesTitle
                    font.pixelSize: WeatherStyle.textLarge
                    color: WeatherStyle.colOnSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.spec?.subtitle || ""
                    font.pixelSize: WeatherStyle.textTiny
                    color: WeatherStyle.colSubtext
                    elide: Text.ElideRight
                }
            }

            WeatherIconButton {
                symbol: "close"
                tooltip: "Close chart"
                size: 36
                iconSize: 18
                onClicked: root.closeRequested()
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: contentColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            ScrollBar.vertical: StyledScrollBar {
                policy: ScrollBar.AsNeeded
            }

            ColumnLayout {
                id: contentColumn
                width: parent.width
                spacing: WeatherStyle.gap

                StyledText {
                    Layout.fillWidth: true
                    visible: root.isDaily
                    text: "Daily values · close the chart to return"
                    font.pixelSize: WeatherStyle.textTiny
                    color: WeatherStyle.colSubtext
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: WeatherStyle.gap
                    visible: root.legend.length > 0

                    Repeater {
                        model: root.legend

                        Row {
                            spacing: 5
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8
                                height: 8
                                radius: 4
                                color: modelData.color
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.pixelSize: WeatherStyle.textTiny
                                color: WeatherStyle.colSubtext
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: WeatherStyle.gapSmall
                    visible: !root.isDaily

                    StyledText {
                        text: "Range"
                        font.pixelSize: WeatherStyle.textTiny
                        font.weight: Font.DemiBold
                        color: WeatherStyle.colSubtext
                    }

                    WeatherOptionChips {
                        options: [
                            { value: "24h", label: "24 h" },
                            { value: "48h", label: "48 h" },
                            { value: "72h", label: "72 h" }
                        ]
                        value: root.range
                        onSelected: value => root.range = value
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.isRange
                        ? Math.max(220, (root.spec?.days ? root.spec.days.length : 7) * 36 + 18)
                        : Math.max(270, Math.min(360, root.height * 0.42))
                    radius: WeatherStyle.radiusTile
                    color: WeatherStyle.colSurfaceHigh
                    visible: root.hasData

                    WeatherChart {
                        visible: !root.isRange
                        anchors.fill: parent
                        anchors.margins: 8
                        values: root.values
                        secondary: root.secondary
                        bars: root.bars
                        labels: root.spec?.labels || []
                        pointLabels: root.spec?.pointLabels || []
                        unit: root.spec?.unit || ""
                        secondaryUnit: root.spec?.secondaryUnit || ""
                        barUnit: root.spec?.barUnit || ""
                        primaryLabel: root.spec?.primaryLabel || ""
                        secondaryLabel: root.spec?.secondaryLabel || ""
                        barLabel: root.spec?.barLabel || ""
                        primaryColor: root.primaryColor
                        secondaryColor: root.secondaryColor
                        barColor: root.barColor
                        yMin: root.spec?.yMin ?? null
                        yMax: root.spec?.yMax ?? null
                        secondaryMin: root.spec?.secondaryMin ?? null
                        secondaryMax: root.spec?.secondaryMax ?? null
                        decimals: root.spec?.decimals ?? 0
                        secondaryDecimals: root.spec?.secondaryDecimals ?? 0
                    }

                    WeatherRangeChart {
                        visible: root.isRange
                        anchors.fill: parent
                        anchors.margins: 8
                        days: root.spec?.days || []
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: !root.hasData
                    horizontalAlignment: Text.AlignHCenter
                    text: "This source has no data for this chart."
                    font.pixelSize: WeatherStyle.textSmall
                    color: WeatherStyle.colSubtext
                    wrapMode: Text.Wrap
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.hasData

                    Repeater {
                        model: root.stats

                        WeatherQuickStat {
                            required property var modelData
                            icon: modelData.icon
                            label: modelData.label
                            value: modelData.value
                            tone: modelData.tone
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "Times are local · " + (Logic.providerModelLabel(WeatherAppService.data) || WeatherAppService.providerLabel)
                    font.pixelSize: WeatherStyle.textTiny
                    color: WeatherStyle.colSubtext
                    elide: Text.ElideRight
                }
            }
        }
    }
}
