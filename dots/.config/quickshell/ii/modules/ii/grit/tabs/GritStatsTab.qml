import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.grit.components

/** Statistics: what the week actually looked like, by tag, day and habit. */
Item {
    id: root

    property bool compact: false
    property bool wide: false
    property real layoutWidth: root.width
    property ClockSidePanel panels: null

    property int rangeDays: 7
    property string chartMode: "tags"

    readonly property real padding: root.compact ? GritStyle.pagePadding : GritStyle.pagePaddingWide
    readonly property real contentWidth: root.layoutWidth - root.padding * 2
    readonly property var ranges: [
        { id: 7, label: Translation.tr("7 days") },
        { id: 30, label: Translation.tr("30 days") },
        { id: 90, label: Translation.tr("90 days") }
    ]
    readonly property var series: GritService.dailyFocusSeries(root.rangeDays)
    readonly property var tagSeries: GritService.dailyTagFocusSeries(root.rangeDays)
    readonly property var breakSeries: root.series.map(day => ({
        date: day.date,
        label: day.label,
        total: Number(day.breaks ?? 0),
        segments: Number(day.breaks ?? 0) > 0
            ? [{ tag: null, label: Translation.tr("Breaks"), seconds: Number(day.breaks) }] : []
    }))
    readonly property var chartSeries: root.chartMode === "breaks" ? root.breakSeries : root.tagSeries
    readonly property var tags: GritService.tagStats(root.rangeDays)
    readonly property var habits: GritService.habitStats(root.rangeDays)
    readonly property var dayParts: GritService.timeOfDayStats(root.rangeDays)
    readonly property int focusMinutes: GritService.focusMinutesInRange(root.rangeDays)
    readonly property int sessionCount: GritService.sessionsInRange(root.rangeDays, "focus").length
    readonly property int averageMinutes: Math.round(root.focusMinutes / root.rangeDays)
    readonly property var bestDay: GritService.bestFocusDay(root.rangeDays)
    readonly property var breakInfo: GritService.breakRatio(root.rangeDays)
    readonly property real tagMax: {
        let max = 1;
        for (const tag of root.tags)
            max = Math.max(max, Number(tag.seconds ?? 0));
        return max;
    }
    readonly property real dayPartMax: {
        let max = 1;
        for (const part of root.dayParts)
            max = Math.max(max, Number(part.seconds ?? 0));
        return max;
    }
    readonly property var tagCards: {
        const stats = root.tags;
        return GritService.activeTags.map(tag => {
            const stat = stats.find(item => String(item.tagId) === String(tag.id));
            return {
                tag: tag,
                name: String(tag.name ?? ""),
                seconds: Number(stat?.seconds ?? 0),
                sessions: Number(stat?.sessions ?? 0),
                percent: GritService.tagPercent(tag.id, root.rangeDays),
                streak: GritService.tagStreak(tag.id),
                goalMinutes: Math.max(0, Number(tag.dailyGoalMinutes ?? 0)),
                todayMinutes: GritService.tagTodayMinutes(tag.id),
                goalProgress: GritService.tagGoalProgress(tag)
            };
        });
    }
    readonly property var focusSlices: {
        // Touch a palette property so the slice colours follow a live theme change.
        const themeAccent = GritStyle.colPrimary;
        return root.tags
            .filter(item => Number(item.seconds ?? 0) > 0)
            .map(item => ({
                name: String(item.name ?? ""),
                value: Number(item.seconds ?? 0),
                percent: Number(item.percent ?? 0),
                color: item.tag ? GritStyle.tagColor(item.tag) : themeAccent
            }));
    }
    readonly property int labelEvery: root.rangeDays <= 7 ? 1 : root.rangeDays <= 30 ? 3 : 14
    readonly property int tagChartDays: Math.min(root.rangeDays, 30)
    readonly property int tagChartLabelEvery: root.tagChartDays <= 7 ? 1 : root.tagChartDays <= 14 ? 2 : 5
    readonly property string subtitle: Translation.tr("%1 focused across %2 days")
        .arg(GritStyle.durationShort(root.focusMinutes))
        .arg(String(root.rangeDays))

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + root.padding + GritStyle.gapHuge
        clip: true

        ColumnLayout {
            id: column
            width: root.contentWidth
            x: root.padding
            spacing: GritStyle.gap

            GritHero {
                Layout.fillWidth: true
                compact: root.compact
                symbol: "monitoring"
                title: root.focusMinutes > 0
                    ? Translation.tr("You gave the time a shape.")
                    : Translation.tr("The first session is a blank page.")
                text: root.subtitle
                shapeName: "Cookie12Sided"
                colContainer: GritStyle.colSecondaryContainer
                colOnContainer: GritStyle.colOnSecondaryContainer
                colAccent: GritStyle.colPrimary

                RowLayout {
                    spacing: GritStyle.gapSmall

                    Repeater {
                        model: root.ranges

                        ClockFormChip {
                            required property var modelData
                            label: String(modelData.label ?? "")
                            selected: root.rangeDays === Number(modelData.id)
                            onTriggered: root.rangeDays = Number(modelData.id)
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.contentWidth >= 900 ? 4 : root.contentWidth >= 560 ? 2 : 1
                columnSpacing: GritStyle.gap
                rowSpacing: GritStyle.gap

                GritStatTile {
                    Layout.fillWidth: true
                    symbol: "psychiatry"
                    value: GritStyle.durationShort(root.focusMinutes)
                    label: Translation.tr("Focus time")
                    hint: Translation.tr("%1 per day").arg(GritStyle.durationShort(root.averageMinutes))
                    shapeName: "Flower"
                    colContainer: GritStyle.colPrimaryContainer
                    colOnContainer: GritStyle.colOnPrimaryContainer
                }

                GritStatTile {
                    Layout.fillWidth: true
                    symbol: "timelapse"
                    value: String(root.sessionCount)
                    label: Translation.tr("Sessions")
                    hint: Translation.tr("%1 break time").arg(GritStyle.durationShort(Math.round(root.breakInfo.breaks / 60)))
                    shapeName: "Cookie9Sided"
                    colContainer: GritStyle.colTertiaryContainer
                    colOnContainer: GritStyle.colOnTertiaryContainer
                }

                GritStatTile {
                    Layout.fillWidth: true
                    symbol: "emoji_events"
                    value: root.bestDay.focus > 0
                        ? GritStyle.durationShort(Math.round(root.bestDay.focus / 60)) : "—"
                    label: Translation.tr("Best day")
                    hint: root.bestDay.date.length > 0 ? GritService.relativeDay(root.bestDay.date) : Translation.tr("No sessions yet")
                    shapeName: "Cookie12Sided"
                    colContainer: GritStyle.colSuccessContainer
                    colOnContainer: GritStyle.colOnSuccessContainer
                }

                GritStatTile {
                    Layout.fillWidth: true
                    symbol: "local_fire_department"
                    value: String(GritService.focusStreak())
                    label: Translation.tr("Day streak")
                    hint: Translation.tr("Days in a row with focus")
                    shapeName: "SoftBurst"
                    colContainer: GritStyle.colSecondaryContainer
                    colOnContainer: GritStyle.colOnSecondaryContainer
                    flame: true
                }
            }

            // ── Daily rhythm ────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: chartColumn.implicitHeight + GritStyle.cardPadding * 2
                radius: GritStyle.radiusLarge
                color: GritStyle.colSurface

                ColumnLayout {
                    id: chartColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: GritStyle.cardPadding
                    }
                    spacing: GritStyle.gap

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: GritStyle.gap

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: Translation.tr("Focus rhythm")
                                font.family: GritStyle.fontTitle
                                font.variableAxes: GritStyle.axesTitle
                                font.pixelSize: Appearance.font.pixelSize.large
                                color: GritStyle.colOnSurface
                            }

                            StyledText {
                                text: root.chartMode === "breaks"
                                    ? Translation.tr("Breaks between focus sessions")
                                    : Translation.tr("Focus time by tag, day by day")
                                font.pixelSize: GritStyle.textSmall
                                color: GritStyle.colSubtext
                            }
                        }

                        RowLayout {
                            spacing: GritStyle.gapTiny

                            ClockFormChip {
                                label: Translation.tr("By tag")
                                selected: root.chartMode === "tags"
                                onTriggered: root.chartMode = "tags"
                            }

                            ClockFormChip {
                                label: Translation.tr("Breaks")
                                selected: root.chartMode === "breaks"
                                onTriggered: root.chartMode = "breaks"
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: GritStyle.gap
                        visible: root.chartMode === "tags" && root.tags.length > 0

                        Repeater {
                            model: root.tags

                            RowLayout {
                                id: legendRow
                                required property var modelData
                                spacing: 4

                                Rectangle {
                                    implicitWidth: 8
                                    implicitHeight: 8
                                    radius: 4
                                    color: GritStyle.tagColor(legendRow.modelData.tag)
                                }

                                StyledText {
                                    text: String(legendRow.modelData.name ?? "")
                                    font.pixelSize: GritStyle.textSmall
                                    color: GritStyle.colSubtext
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.chartMode === "breaks"
                        text: Translation.tr("Breaks")
                        font.pixelSize: GritStyle.textSmall
                        color: GritStyle.colSubtext
                    }

                    GritTagBarChart {
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        series: root.chartSeries
                        chartHeight: root.compact ? 120 : 160
                        showLabels: true
                        labelEvery: root.labelEvery
                        colFallback: root.chartMode === "breaks" ? GritStyle.colTertiary : GritStyle.colPrimary
                    }
                }
            }

            // ── Tag split + time of day ─────────────────────────────────
            GridLayout {
                Layout.fillWidth: true
                columns: root.contentWidth >= 840 ? 2 : 1
                columnSpacing: GritStyle.gap
                rowSpacing: GritStyle.gap

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: tagColumn.implicitHeight + GritStyle.cardPadding * 2
                    radius: GritStyle.radiusLarge
                    color: GritStyle.colSurface

                    ColumnLayout {
                        id: tagColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: GritStyle.cardPadding
                        }
                        spacing: GritStyle.gapSmall

                        StyledText {
                            text: Translation.tr("Focus split")
                            font.family: GritStyle.fontTitle
                            font.variableAxes: GritStyle.axesTitle
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: GritStyle.colOnSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Focused time divided between tags")
                            font.pixelSize: GritStyle.textSmall
                            color: GritStyle.colSubtext
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: GritStyle.gapSmall
                            spacing: GritStyle.gapLarge

                            GritDonutChart {
                                Layout.preferredWidth: 182
                                Layout.preferredHeight: 182
                                slices: root.focusSlices
                                thickness: 23
                                centerValue: GritStyle.durationShort(root.focusMinutes)
                                centerLabel: Translation.tr("focused")
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: GritStyle.gapSmall

                                Repeater {
                                    model: root.focusSlices

                                    RowLayout {
                                        id: sliceRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: GritStyle.gapSmall

                                        Rectangle {
                                            implicitWidth: 10
                                            implicitHeight: 10
                                            radius: 5
                                            color: sliceRow.modelData.color
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: String(sliceRow.modelData.name ?? "")
                                            elide: Text.ElideRight
                                            font.pixelSize: GritStyle.textNormal
                                            color: GritStyle.colOnSurface
                                        }

                                        StyledText {
                                            text: String(Math.round(Number(sliceRow.modelData.percent ?? 0) * 100)) + "%"
                                            font.family: GritStyle.fontNumbers
                                            font.variableAxes: GritStyle.axesDigitsBold
                                            font.pixelSize: GritStyle.textNormal
                                            color: sliceRow.modelData.color
                                        }

                                        StyledText {
                                            text: GritStyle.durationShort(Math.round(Number(sliceRow.modelData.value ?? 0) / 60))
                                            font.pixelSize: GritStyle.textSmall
                                            color: GritStyle.colSubtext
                                        }
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: root.focusSlices.length === 0
                                    text: Translation.tr("No focus time in this range yet.")
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: GritStyle.textSmall
                                    color: GritStyle.colSubtext
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: partColumn.implicitHeight + GritStyle.cardPadding * 2
                    radius: GritStyle.radiusLarge
                    color: GritStyle.colSurface

                    ColumnLayout {
                        id: partColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: GritStyle.cardPadding
                        }
                        spacing: GritStyle.gapSmall

                        StyledText {
                            text: Translation.tr("When you focus")
                            font.family: GritStyle.fontTitle
                            font.variableAxes: GritStyle.axesTitle
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: GritStyle.colOnSurface
                        }

                        Repeater {
                            model: root.dayParts

                            ColumnLayout {
                                id: partRow
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 3

                                RowLayout {
                                    Layout.fillWidth: true

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: String(partRow.modelData.label ?? "") + "  " + String(partRow.modelData.range ?? "")
                                        font.pixelSize: GritStyle.textNormal
                                        color: GritStyle.colOnSurface
                                    }

                                    StyledText {
                                        text: GritStyle.durationShort(Math.round(Number(partRow.modelData.seconds ?? 0) / 60))
                                        font.pixelSize: GritStyle.textSmall
                                        font.weight: Font.DemiBold
                                        color: GritStyle.colSubtext
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 8
                                    radius: 4
                                    color: GritStyle.colField

                                    Rectangle {
                                        width: Math.max(parent.height, parent.width * (Number(partRow.modelData.seconds ?? 0) / root.dayPartMax))
                                        height: parent.height
                                        radius: parent.radius
                                        color: GritStyle.colTertiary
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Heatmap + habits ────────────────────────────────────────
            GridLayout {
                Layout.fillWidth: true
                columns: root.contentWidth >= 840 ? 2 : 1
                columnSpacing: GritStyle.gap
                rowSpacing: GritStyle.gap

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: heatColumn.implicitHeight + GritStyle.cardPadding * 2
                    radius: GritStyle.radiusLarge
                    color: GritStyle.colSurface

                    ColumnLayout {
                        id: heatColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: GritStyle.cardPadding
                        }
                        spacing: GritStyle.gapSmall

                        RowLayout {
                            Layout.fillWidth: true

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Twelve weeks of consistency")
                                    font.pixelSize: GritStyle.textNormal
                                    font.weight: Font.DemiBold
                                    color: GritStyle.colOnSurface
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Each column is a week · darker means more focus")
                                    font.pixelSize: GritStyle.textSmall
                                    color: GritStyle.colSubtext
                                }
                            }
                        }

                        GritHeatmap {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredHeight: implicitHeight
                            values: GritService.focusHeatmapWeeks(12)
                            colAccent: GritStyle.colPrimary
                            cellSize: 24
                            cellGap: 4
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: GritStyle.gapTiny
                            spacing: GritStyle.gapTiny

                            StyledText {
                                text: Translation.tr("Quieter")
                                font.pixelSize: 9
                                color: GritStyle.colSubtext
                            }

                            Repeater {
                                model: 5

                                Rectangle {
                                    required property int index
                                    implicitWidth: 9
                                    implicitHeight: 9
                                    radius: 2
                                    color: index === 0 ? GritStyle.colField
                                        : ColorUtils.mix(GritStyle.colPrimary, GritStyle.colField,
                                            0.2 + index * 0.14)
                                }
                            }

                            StyledText {
                                text: Translation.tr("More focus")
                                font.pixelSize: 9
                                color: GritStyle.colSubtext
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: habitColumn.implicitHeight + GritStyle.cardPadding * 2
                    radius: GritStyle.radiusLarge
                    color: GritStyle.colSurface

                    ColumnLayout {
                        id: habitColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: GritStyle.cardPadding
                        }
                        spacing: GritStyle.gapSmall

                        StyledText {
                            text: Translation.tr("Habit consistency")
                            font.family: GritStyle.fontTitle
                            font.variableAxes: GritStyle.axesTitle
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: GritStyle.colOnSurface
                        }

                        Repeater {
                            model: root.habits

                            RowLayout {
                                id: habitRow
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: GritStyle.gapSmall

                                MaterialShapeWrappedMaterialSymbol {
                                    text: String(habitRow.modelData.habit?.icon ?? "check_circle")
                                    iconSize: 15
                                    padding: 6
                                    shape: "Cookie4Sided"
                                    color: GritStyle.colPrimaryContainer
                                    colSymbol: GritStyle.colOnPrimaryContainer
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(habitRow.modelData.name ?? "")
                                    elide: Text.ElideRight
                                    font.pixelSize: GritStyle.textNormal
                                    color: GritStyle.colOnSurface
                                }

                                StyledText {
                                    text: habitRow.modelData.due > 0
                                        ? String(habitRow.modelData.done) + "/" + String(habitRow.modelData.due) : "—"
                                    font.pixelSize: GritStyle.textSmall
                                    color: GritStyle.colSubtext
                                }

                                Rectangle {
                                    implicitWidth: 70
                                    implicitHeight: 7
                                    radius: 4
                                    color: GritStyle.colField

                                    Rectangle {
                                        width: Math.max(parent.height, parent.width * Number(habitRow.modelData.rate ?? 0))
                                        height: parent.height
                                        radius: parent.radius
                                        color: Number(habitRow.modelData.rate ?? 0) >= 1
                                            ? GritStyle.colSuccess : GritStyle.colPrimary
                                    }
                                }

                                GritFlame {
                                    count: Number(habitRow.modelData.streak ?? 0)
                                    colFlame: GritStyle.colTertiary
                                    iconSize: 13
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: root.habits.length === 0
                            text: Translation.tr("Add a habit to see its consistency here.")
                            wrapMode: Text.WordWrap
                            font.pixelSize: GritStyle.textSmall
                            color: GritStyle.colSubtext
                        }
                    }
                }
            }

            // ── Consistency by tag ──────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                visible: root.tagCards.length > 0
                implicitHeight: byTagColumn.implicitHeight + GritStyle.cardPadding * 2
                radius: GritStyle.radiusLarge
                color: GritStyle.colSurface

                ColumnLayout {
                    id: byTagColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: GritStyle.cardPadding
                    }
                    spacing: GritStyle.gapSmall

                    RowLayout {
                        Layout.fillWidth: true

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Consistency by tag")
                                font.pixelSize: GritStyle.textNormal
                                font.weight: Font.DemiBold
                                color: GritStyle.colOnSurface
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("A focus graph and twelve weeks of consistency for each tag")
                                font.pixelSize: GritStyle.textSmall
                                color: GritStyle.colSubtext
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: GritStyle.gapSmall

                        Repeater {
                            model: root.tagCards

                            Rectangle {
                                id: tagCard
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: tagCardColumn.implicitHeight + GritStyle.cardPadding * 2
                                radius: GritStyle.radiusLarge
                                color: ColorUtils.mix(GritStyle.tagColor(tagCard.modelData.tag),
                                    GritStyle.colSurface, 0.055)
                                border.width: 1
                                border.color: ColorUtils.applyAlpha(
                                    GritStyle.tagColor(tagCard.modelData.tag), 0.16)

                                ColumnLayout {
                                    id: tagCardColumn
                                    anchors {
                                        fill: parent
                                        margins: GritStyle.cardPadding
                                    }
                                    spacing: GritStyle.gapSmall

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: GritStyle.gapSmall

                                        MaterialShapeWrappedMaterialSymbol {
                                            text: GritStyle.tagIcon(tagCard.modelData.tag)
                                            iconSize: 17
                                            padding: 7
                                            shape: String(tagCard.modelData.tag?.shape ?? "Cookie7Sided")
                                            color: GritStyle.tagColor(tagCard.modelData.tag)
                                            colSymbol: GritStyle.tagOnSolid(tagCard.modelData.tag)
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: tagCard.modelData.name
                                            elide: Text.ElideRight
                                            font.pixelSize: GritStyle.textNormal
                                            font.weight: Font.DemiBold
                                            color: GritStyle.colOnSurface
                                        }

                                        StyledText {
                                            text: String(Math.round(tagCard.modelData.percent * 100)) + "%"
                                            font.family: GritStyle.fontNumbers
                                            font.variableAxes: GritStyle.axesDigitsBold
                                            font.pixelSize: GritStyle.textNormal
                                            color: GritStyle.tagColor(tagCard.modelData.tag)
                                        }

                                        StyledText {
                                            text: GritStyle.durationShort(Math.round(tagCard.modelData.seconds / 60))
                                            font.pixelSize: GritStyle.textSmall
                                            color: GritStyle.colSubtext
                                        }

                                        GritFlame {
                                            count: tagCard.modelData.streak
                                            showZero: true
                                            colFlame: GritStyle.tagColor(tagCard.modelData.tag)
                                            iconSize: 12
                                        }

                                        StyledText {
                                            text: Translation.tr("days")
                                            font.pixelSize: GritStyle.textSmall
                                            color: GritStyle.colSubtext
                                        }
                                    }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: root.contentWidth >= 760 ? 2 : 1
                                        columnSpacing: GritStyle.gap
                                        rowSpacing: GritStyle.gapSmall

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignTop
                                            spacing: 2

                                            StyledText {
                                                text: Translation.tr("Focus time · %1 days")
                                                    .arg(String(root.tagChartDays))
                                                font.pixelSize: GritStyle.textSmall
                                                font.weight: Font.DemiBold
                                                color: GritStyle.colSubtext
                                            }

                                            GritTagBarChart {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: implicitHeight
                                                series: GritService.tagFocusSeries(
                                                    tagCard.modelData.tag?.id ?? "", root.tagChartDays)
                                                chartHeight: 104
                                                showLabels: true
                                                labelEvery: root.tagChartLabelEvery
                                                colFallback: GritStyle.tagColor(tagCard.modelData.tag)
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.alignment: Qt.AlignTop
                                            spacing: 2

                                            StyledText {
                                                text: Translation.tr("Last 12 weeks")
                                                font.pixelSize: GritStyle.textSmall
                                                font.weight: Font.DemiBold
                                                color: GritStyle.colSubtext
                                            }

                                            GritHeatmap {
                                                Layout.alignment: Qt.AlignHCenter
                                                Layout.preferredHeight: implicitHeight
                                                values: GritService.focusHeatmapWeeks(12, tagCard.modelData.tag?.id ?? "")
                                                colAccent: GritStyle.tagColor(tagCard.modelData.tag)
                                                cellSize: 22
                                                cellGap: 2
                                                showLabels: true
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.topMargin: GritStyle.gapTiny
                                        spacing: GritStyle.gapSmall

                                        StyledText {
                                            visible: tagCard.modelData.goalMinutes > 0
                                            text: Translation.tr("%1 / %2 today")
                                                .arg(GritStyle.durationShort(tagCard.modelData.todayMinutes))
                                                .arg(GritStyle.durationShort(tagCard.modelData.goalMinutes))
                                            font.pixelSize: GritStyle.textSmall
                                            color: GritStyle.colSubtext
                                        }

                                        StyledText {
                                            visible: tagCard.modelData.goalMinutes <= 0
                                            text: Translation.tr("No daily goal")
                                            font.pixelSize: GritStyle.textSmall
                                            color: GritStyle.colSubtext
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            visible: tagCard.modelData.goalMinutes > 0
                                            implicitHeight: 5
                                            radius: 3
                                            color: GritStyle.colField

                                            Rectangle {
                                                width: Math.max(parent.height,
                                                    parent.width * Math.max(0, tagCard.modelData.goalProgress))
                                                height: parent.height
                                                radius: parent.radius
                                                color: GritStyle.tagColor(tagCard.modelData.tag)
                                            }
                                        }

                                        StyledText {
                                            visible: tagCard.modelData.goalMinutes > 0
                                            text: String(Math.round(Math.max(0, tagCard.modelData.goalProgress) * 100)) + "%"
                                            font.family: GritStyle.fontNumbers
                                            font.variableAxes: GritStyle.axesDigits
                                            font.pixelSize: GritStyle.textSmall
                                            color: GritStyle.tagColor(tagCard.modelData.tag)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: GritStyle.gapHuge
            }
        }
    }
}
