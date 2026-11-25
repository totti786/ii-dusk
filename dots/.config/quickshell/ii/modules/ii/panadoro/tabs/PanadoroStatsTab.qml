import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.panadoro.components

/** Statistics: what the week actually looked like, by tag, day and habit. */
Item {
    id: root

    property bool compact: false
    property bool wide: false
    property real layoutWidth: root.width
    property ClockSidePanel panels: null

    property int rangeDays: 7
    property string chartMode: "tags"

    readonly property real padding: root.compact ? PanadoroStyle.pagePadding : PanadoroStyle.pagePaddingWide
    readonly property real contentWidth: root.layoutWidth - root.padding * 2
    readonly property var ranges: [
        { id: 7, label: Translation.tr("7 days") },
        { id: 30, label: Translation.tr("30 days") },
        { id: 90, label: Translation.tr("90 days") }
    ]
    readonly property var series: PanadoroService.dailyFocusSeries(root.rangeDays)
    readonly property var tagSeries: PanadoroService.dailyTagFocusSeries(root.rangeDays)
    readonly property var breakSeries: root.series.map(day => ({
        date: day.date,
        label: day.label,
        total: Number(day.breaks ?? 0),
        segments: Number(day.breaks ?? 0) > 0
            ? [{ tag: null, label: Translation.tr("Breaks"), seconds: Number(day.breaks) }] : []
    }))
    readonly property var chartSeries: root.chartMode === "breaks" ? root.breakSeries : root.tagSeries
    readonly property var tags: PanadoroService.tagStats(root.rangeDays)
    readonly property var habits: PanadoroService.habitStats(root.rangeDays)
    readonly property var dayParts: PanadoroService.timeOfDayStats(root.rangeDays)
    readonly property int focusMinutes: PanadoroService.focusMinutesInRange(root.rangeDays)
    readonly property int sessionCount: PanadoroService.sessionsInRange(root.rangeDays, "focus").length
    readonly property int averageMinutes: Math.round(root.focusMinutes / root.rangeDays)
    readonly property var bestDay: PanadoroService.bestFocusDay(root.rangeDays)
    readonly property var breakInfo: PanadoroService.breakRatio(root.rangeDays)
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
        return PanadoroService.activeTags.map(tag => {
            const stat = stats.find(item => String(item.tagId) === String(tag.id));
            return {
                tag: tag,
                name: String(tag.name ?? ""),
                seconds: Number(stat?.seconds ?? 0),
                sessions: Number(stat?.sessions ?? 0),
                percent: PanadoroService.tagPercent(tag.id, root.rangeDays),
                streak: PanadoroService.tagStreak(tag.id),
                goalMinutes: Math.max(0, Number(tag.dailyGoalMinutes ?? 0)),
                todayMinutes: PanadoroService.tagTodayMinutes(tag.id),
                goalProgress: PanadoroService.tagGoalProgress(tag)
            };
        });
    }
    readonly property var focusSlices: {
        // Touch a palette property so the slice colours follow a live theme change.
        const themeAccent = PanadoroStyle.colPrimary;
        return root.tags
            .filter(item => Number(item.seconds ?? 0) > 0)
            .map(item => ({
                name: String(item.name ?? ""),
                value: Number(item.seconds ?? 0),
                percent: Number(item.percent ?? 0),
                color: item.tag ? PanadoroStyle.tagColor(item.tag) : themeAccent
            }));
    }
    readonly property int labelEvery: root.rangeDays <= 7 ? 1 : root.rangeDays <= 30 ? 3 : 14
    readonly property int tagChartDays: Math.min(root.rangeDays, 30)
    readonly property int tagChartLabelEvery: root.tagChartDays <= 7 ? 1 : root.tagChartDays <= 14 ? 2 : 5
    readonly property string subtitle: Translation.tr("%1 focused across %2 days")
        .arg(PanadoroStyle.durationShort(root.focusMinutes))
        .arg(String(root.rangeDays))

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + root.padding + PanadoroStyle.gapHuge
        clip: true

        ColumnLayout {
            id: column
            width: root.contentWidth
            x: root.padding
            spacing: PanadoroStyle.gap

            PanadoroHero {
                Layout.fillWidth: true
                compact: root.compact
                symbol: "monitoring"
                title: root.focusMinutes > 0
                    ? Translation.tr("You gave the time a shape.")
                    : Translation.tr("The first session is a blank page.")
                text: root.subtitle
                shapeName: "Cookie12Sided"
                colContainer: PanadoroStyle.colSecondaryContainer
                colOnContainer: PanadoroStyle.colOnSecondaryContainer
                colAccent: PanadoroStyle.colPrimary

                RowLayout {
                    spacing: PanadoroStyle.gapSmall

                    Repeater {
                        model: root.ranges

                        PanadoroChoiceChip {
                            required property var modelData
                            label: String(modelData.label ?? "")
                            selected: root.rangeDays === Number(modelData.id)
                            colSelected: PanadoroStyle.colPrimary
                            colOnSelected: PanadoroStyle.colOnPrimary
                            onTriggered: root.rangeDays = Number(modelData.id)
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.contentWidth >= 900 ? 4 : root.contentWidth >= 560 ? 2 : 1
                columnSpacing: PanadoroStyle.gap
                rowSpacing: PanadoroStyle.gap

                PanadoroStatTile {
                    Layout.fillWidth: true
                    symbol: "psychiatry"
                    value: PanadoroStyle.durationShort(root.focusMinutes)
                    label: Translation.tr("Focus time")
                    hint: Translation.tr("%1 per day").arg(PanadoroStyle.durationShort(root.averageMinutes))
                    shapeName: "Flower"
                    colContainer: PanadoroStyle.colPrimaryContainer
                    colOnContainer: PanadoroStyle.colOnPrimaryContainer
                }

                PanadoroStatTile {
                    Layout.fillWidth: true
                    symbol: "timelapse"
                    value: String(root.sessionCount)
                    label: Translation.tr("Sessions")
                    hint: Translation.tr("%1 break time").arg(PanadoroStyle.durationShort(Math.round(root.breakInfo.breaks / 60)))
                    shapeName: "Cookie9Sided"
                    colContainer: PanadoroStyle.colTertiaryContainer
                    colOnContainer: PanadoroStyle.colOnTertiaryContainer
                }

                PanadoroStatTile {
                    Layout.fillWidth: true
                    symbol: "emoji_events"
                    value: root.bestDay.focus > 0
                        ? PanadoroStyle.durationShort(Math.round(root.bestDay.focus / 60)) : "—"
                    label: Translation.tr("Best day")
                    hint: root.bestDay.date.length > 0 ? PanadoroService.relativeDay(root.bestDay.date) : Translation.tr("No sessions yet")
                    shapeName: "Cookie12Sided"
                    colContainer: PanadoroStyle.colSuccessContainer
                    colOnContainer: PanadoroStyle.colOnSuccessContainer
                }

                PanadoroStatTile {
                    Layout.fillWidth: true
                    symbol: "local_fire_department"
                    value: String(PanadoroService.focusStreak())
                    label: Translation.tr("Day streak")
                    hint: Translation.tr("Days in a row with focus")
                    shapeName: "SoftBurst"
                    colContainer: PanadoroStyle.colSecondaryContainer
                    colOnContainer: PanadoroStyle.colOnSecondaryContainer
                    flame: true
                }
            }

            // ── Daily rhythm ────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: chartColumn.implicitHeight + PanadoroStyle.cardPadding * 2
                radius: PanadoroStyle.radiusLarge
                color: PanadoroStyle.colSurface

                ColumnLayout {
                    id: chartColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: PanadoroStyle.cardPadding
                    }
                    spacing: PanadoroStyle.gap

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: PanadoroStyle.gap

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: Translation.tr("Focus rhythm")
                                font.family: PanadoroStyle.fontTitle
                                font.variableAxes: PanadoroStyle.axesTitle
                                font.pixelSize: Appearance.font.pixelSize.large
                                color: PanadoroStyle.colOnSurface
                            }

                            StyledText {
                                text: root.chartMode === "breaks"
                                    ? Translation.tr("Breaks between focus sessions")
                                    : Translation.tr("Focus time by tag, day by day")
                                font.pixelSize: PanadoroStyle.textSmall
                                color: PanadoroStyle.colSubtext
                            }
                        }

                        RowLayout {
                            spacing: PanadoroStyle.gapTiny

                            PanadoroChoiceChip {
                                label: Translation.tr("By tag")
                                selected: root.chartMode === "tags"
                                onTriggered: root.chartMode = "tags"
                            }

                            PanadoroChoiceChip {
                                label: Translation.tr("Breaks")
                                selected: root.chartMode === "breaks"
                                onTriggered: root.chartMode = "breaks"
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: PanadoroStyle.gap
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
                                    color: PanadoroStyle.tagColor(legendRow.modelData.tag)
                                }

                                StyledText {
                                    text: String(legendRow.modelData.name ?? "")
                                    font.pixelSize: PanadoroStyle.textSmall
                                    color: PanadoroStyle.colSubtext
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.chartMode === "breaks"
                        text: Translation.tr("Breaks")
                        font.pixelSize: PanadoroStyle.textSmall
                        color: PanadoroStyle.colSubtext
                    }

                    PanadoroTagBarChart {
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        series: root.chartSeries
                        chartHeight: root.compact ? 120 : 160
                        showLabels: true
                        labelEvery: root.labelEvery
                        colFallback: root.chartMode === "breaks" ? PanadoroStyle.colTertiary : PanadoroStyle.colPrimary
                    }
                }
            }

            // ── Tag split + time of day ─────────────────────────────────
            GridLayout {
                Layout.fillWidth: true
                columns: root.contentWidth >= 840 ? 2 : 1
                columnSpacing: PanadoroStyle.gap
                rowSpacing: PanadoroStyle.gap

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: tagColumn.implicitHeight + PanadoroStyle.cardPadding * 2
                    radius: PanadoroStyle.radiusLarge
                    color: PanadoroStyle.colSurface

                    ColumnLayout {
                        id: tagColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: PanadoroStyle.cardPadding
                        }
                        spacing: PanadoroStyle.gapSmall

                        StyledText {
                            text: Translation.tr("Focus split")
                            font.family: PanadoroStyle.fontTitle
                            font.variableAxes: PanadoroStyle.axesTitle
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: PanadoroStyle.colOnSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Focused time divided between tags")
                            font.pixelSize: PanadoroStyle.textSmall
                            color: PanadoroStyle.colSubtext
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: PanadoroStyle.gapSmall
                            spacing: PanadoroStyle.gapLarge

                            PanadoroDonutChart {
                                Layout.preferredWidth: 182
                                Layout.preferredHeight: 182
                                slices: root.focusSlices
                                thickness: 23
                                centerValue: PanadoroStyle.durationShort(root.focusMinutes)
                                centerLabel: Translation.tr("focused")
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: PanadoroStyle.gapSmall

                                Repeater {
                                    model: root.focusSlices

                                    RowLayout {
                                        id: sliceRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: PanadoroStyle.gapSmall

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
                                            font.pixelSize: PanadoroStyle.textNormal
                                            color: PanadoroStyle.colOnSurface
                                        }

                                        StyledText {
                                            text: String(Math.round(Number(sliceRow.modelData.percent ?? 0) * 100)) + "%"
                                            font.family: PanadoroStyle.fontNumbers
                                            font.variableAxes: PanadoroStyle.axesDigitsBold
                                            font.pixelSize: PanadoroStyle.textNormal
                                            color: sliceRow.modelData.color
                                        }

                                        StyledText {
                                            text: PanadoroStyle.durationShort(Math.round(Number(sliceRow.modelData.value ?? 0) / 60))
                                            font.pixelSize: PanadoroStyle.textSmall
                                            color: PanadoroStyle.colSubtext
                                        }
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: root.focusSlices.length === 0
                                    text: Translation.tr("No focus time in this range yet.")
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: PanadoroStyle.textSmall
                                    color: PanadoroStyle.colSubtext
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: partColumn.implicitHeight + PanadoroStyle.cardPadding * 2
                    radius: PanadoroStyle.radiusLarge
                    color: PanadoroStyle.colSurface

                    ColumnLayout {
                        id: partColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: PanadoroStyle.cardPadding
                        }
                        spacing: PanadoroStyle.gapSmall

                        StyledText {
                            text: Translation.tr("When you focus")
                            font.family: PanadoroStyle.fontTitle
                            font.variableAxes: PanadoroStyle.axesTitle
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: PanadoroStyle.colOnSurface
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
                                        font.pixelSize: PanadoroStyle.textNormal
                                        color: PanadoroStyle.colOnSurface
                                    }

                                    StyledText {
                                        text: PanadoroStyle.durationShort(Math.round(Number(partRow.modelData.seconds ?? 0) / 60))
                                        font.pixelSize: PanadoroStyle.textSmall
                                        font.weight: Font.DemiBold
                                        color: PanadoroStyle.colSubtext
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 8
                                    radius: 4
                                    color: PanadoroStyle.colField

                                    Rectangle {
                                        width: Math.max(parent.height, parent.width * (Number(partRow.modelData.seconds ?? 0) / root.dayPartMax))
                                        height: parent.height
                                        radius: parent.radius
                                        color: PanadoroStyle.colTertiary
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
                columnSpacing: PanadoroStyle.gap
                rowSpacing: PanadoroStyle.gap

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: heatColumn.implicitHeight + PanadoroStyle.cardPadding * 2
                    radius: PanadoroStyle.radiusLarge
                    color: PanadoroStyle.colSurface

                    ColumnLayout {
                        id: heatColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: PanadoroStyle.cardPadding
                        }
                        spacing: PanadoroStyle.gapSmall

                        RowLayout {
                            Layout.fillWidth: true

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Twelve weeks of consistency")
                                    font.pixelSize: PanadoroStyle.textNormal
                                    font.weight: Font.DemiBold
                                    color: PanadoroStyle.colOnSurface
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Each column is a week · darker means more focus")
                                    font.pixelSize: PanadoroStyle.textSmall
                                    color: PanadoroStyle.colSubtext
                                }
                            }
                        }

                        PanadoroHeatmap {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredHeight: implicitHeight
                            values: PanadoroService.focusHeatmapWeeks(12)
                            colAccent: PanadoroStyle.colPrimary
                            cellSize: 24
                            cellGap: 4
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: PanadoroStyle.gapTiny
                            spacing: PanadoroStyle.gapTiny

                            StyledText {
                                text: Translation.tr("Quieter")
                                font.pixelSize: 9
                                color: PanadoroStyle.colSubtext
                            }

                            Repeater {
                                model: 5

                                Rectangle {
                                    required property int index
                                    implicitWidth: 9
                                    implicitHeight: 9
                                    radius: 2
                                    color: index === 0 ? PanadoroStyle.colField
                                        : ColorUtils.mix(PanadoroStyle.colPrimary, PanadoroStyle.colField,
                                            0.2 + index * 0.14)
                                }
                            }

                            StyledText {
                                text: Translation.tr("More focus")
                                font.pixelSize: 9
                                color: PanadoroStyle.colSubtext
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: habitColumn.implicitHeight + PanadoroStyle.cardPadding * 2
                    radius: PanadoroStyle.radiusLarge
                    color: PanadoroStyle.colSurface

                    ColumnLayout {
                        id: habitColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: PanadoroStyle.cardPadding
                        }
                        spacing: PanadoroStyle.gapSmall

                        StyledText {
                            text: Translation.tr("Habit consistency")
                            font.family: PanadoroStyle.fontTitle
                            font.variableAxes: PanadoroStyle.axesTitle
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: PanadoroStyle.colOnSurface
                        }

                        Repeater {
                            model: root.habits

                            RowLayout {
                                id: habitRow
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: PanadoroStyle.gapSmall

                                MaterialShapeWrappedMaterialSymbol {
                                    text: String(habitRow.modelData.habit?.icon ?? "check_circle")
                                    iconSize: 15
                                    padding: 6
                                    shape: "Cookie4Sided"
                                    color: PanadoroStyle.colPrimaryContainer
                                    colSymbol: PanadoroStyle.colOnPrimaryContainer
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(habitRow.modelData.name ?? "")
                                    elide: Text.ElideRight
                                    font.pixelSize: PanadoroStyle.textNormal
                                    color: PanadoroStyle.colOnSurface
                                }

                                StyledText {
                                    text: habitRow.modelData.due > 0
                                        ? String(habitRow.modelData.done) + "/" + String(habitRow.modelData.due) : "—"
                                    font.pixelSize: PanadoroStyle.textSmall
                                    color: PanadoroStyle.colSubtext
                                }

                                Rectangle {
                                    implicitWidth: 70
                                    implicitHeight: 7
                                    radius: 4
                                    color: PanadoroStyle.colField

                                    Rectangle {
                                        width: Math.max(parent.height, parent.width * Number(habitRow.modelData.rate ?? 0))
                                        height: parent.height
                                        radius: parent.radius
                                        color: Number(habitRow.modelData.rate ?? 0) >= 1
                                            ? PanadoroStyle.colSuccess : PanadoroStyle.colPrimary
                                    }
                                }

                                PanadoroFlame {
                                    count: Number(habitRow.modelData.streak ?? 0)
                                    colFlame: PanadoroStyle.colTertiary
                                    iconSize: 13
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: root.habits.length === 0
                            text: Translation.tr("Add a habit to see its consistency here.")
                            wrapMode: Text.WordWrap
                            font.pixelSize: PanadoroStyle.textSmall
                            color: PanadoroStyle.colSubtext
                        }
                    }
                }
            }

            // ── Consistency by tag ──────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                visible: root.tagCards.length > 0
                implicitHeight: byTagColumn.implicitHeight + PanadoroStyle.cardPadding * 2
                radius: PanadoroStyle.radiusLarge
                color: PanadoroStyle.colSurface

                ColumnLayout {
                    id: byTagColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: PanadoroStyle.cardPadding
                    }
                    spacing: PanadoroStyle.gapSmall

                    RowLayout {
                        Layout.fillWidth: true

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Consistency by tag")
                                font.pixelSize: PanadoroStyle.textNormal
                                font.weight: Font.DemiBold
                                color: PanadoroStyle.colOnSurface
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("A focus graph and twelve weeks of consistency for each tag")
                                font.pixelSize: PanadoroStyle.textSmall
                                color: PanadoroStyle.colSubtext
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: PanadoroStyle.gapSmall

                        Repeater {
                            model: root.tagCards

                            Rectangle {
                                id: tagCard
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: tagCardColumn.implicitHeight + PanadoroStyle.cardPadding * 2
                                radius: PanadoroStyle.radiusLarge
                                color: ColorUtils.mix(PanadoroStyle.tagColor(tagCard.modelData.tag),
                                    PanadoroStyle.colSurface, 0.08)

                                ColumnLayout {
                                    id: tagCardColumn
                                    anchors {
                                        fill: parent
                                        margins: PanadoroStyle.cardPadding
                                    }
                                    spacing: PanadoroStyle.gapSmall

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: PanadoroStyle.gapSmall

                                        MaterialShapeWrappedMaterialSymbol {
                                            text: PanadoroStyle.tagIcon(tagCard.modelData.tag)
                                            iconSize: 17
                                            padding: 7
                                            shape: String(tagCard.modelData.tag?.shape ?? "Cookie7Sided")
                                            color: PanadoroStyle.tagColor(tagCard.modelData.tag)
                                            colSymbol: PanadoroStyle.tagOnSolid(tagCard.modelData.tag)
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: tagCard.modelData.name
                                            elide: Text.ElideRight
                                            font.pixelSize: PanadoroStyle.textNormal
                                            font.weight: Font.DemiBold
                                            color: PanadoroStyle.colOnSurface
                                        }

                                        StyledText {
                                            text: String(Math.round(tagCard.modelData.percent * 100)) + "%"
                                            font.family: PanadoroStyle.fontNumbers
                                            font.variableAxes: PanadoroStyle.axesDigitsBold
                                            font.pixelSize: PanadoroStyle.textNormal
                                            color: PanadoroStyle.tagColor(tagCard.modelData.tag)
                                        }

                                        StyledText {
                                            text: PanadoroStyle.durationShort(Math.round(tagCard.modelData.seconds / 60))
                                            font.pixelSize: PanadoroStyle.textSmall
                                            color: PanadoroStyle.colSubtext
                                        }

                                        PanadoroFlame {
                                            count: tagCard.modelData.streak
                                            showZero: true
                                            colFlame: PanadoroStyle.tagColor(tagCard.modelData.tag)
                                            iconSize: 12
                                        }

                                        StyledText {
                                            text: Translation.tr("days")
                                            font.pixelSize: PanadoroStyle.textSmall
                                            color: PanadoroStyle.colSubtext
                                        }
                                    }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: root.contentWidth >= 760 ? 2 : 1
                                        columnSpacing: PanadoroStyle.gap
                                        rowSpacing: PanadoroStyle.gapSmall

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignTop
                                            spacing: 2

                                            StyledText {
                                                text: Translation.tr("Focus time · %1 days")
                                                    .arg(String(root.tagChartDays))
                                                font.pixelSize: PanadoroStyle.textSmall
                                                font.weight: Font.DemiBold
                                                color: PanadoroStyle.colSubtext
                                            }

                                            PanadoroTagBarChart {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: implicitHeight
                                                series: PanadoroService.tagFocusSeries(
                                                    tagCard.modelData.tag?.id ?? "", root.tagChartDays)
                                                chartHeight: 104
                                                showLabels: true
                                                labelEvery: root.tagChartLabelEvery
                                                colFallback: PanadoroStyle.tagColor(tagCard.modelData.tag)
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.alignment: Qt.AlignTop
                                            spacing: 2

                                            StyledText {
                                                text: Translation.tr("Last 12 weeks")
                                                font.pixelSize: PanadoroStyle.textSmall
                                                font.weight: Font.DemiBold
                                                color: PanadoroStyle.colSubtext
                                            }

                                            PanadoroHeatmap {
                                                Layout.alignment: Qt.AlignHCenter
                                                Layout.preferredHeight: implicitHeight
                                                values: PanadoroService.focusHeatmapWeeks(12, tagCard.modelData.tag?.id ?? "")
                                                colAccent: PanadoroStyle.tagColor(tagCard.modelData.tag)
                                                cellSize: 22
                                                cellGap: 2
                                                showLabels: true
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.topMargin: PanadoroStyle.gapTiny
                                        spacing: PanadoroStyle.gapSmall

                                        StyledText {
                                            visible: tagCard.modelData.goalMinutes > 0
                                            text: Translation.tr("%1 / %2 today")
                                                .arg(PanadoroStyle.durationShort(tagCard.modelData.todayMinutes))
                                                .arg(PanadoroStyle.durationShort(tagCard.modelData.goalMinutes))
                                            font.pixelSize: PanadoroStyle.textSmall
                                            color: PanadoroStyle.colSubtext
                                        }

                                        StyledText {
                                            visible: tagCard.modelData.goalMinutes <= 0
                                            text: Translation.tr("No daily goal")
                                            font.pixelSize: PanadoroStyle.textSmall
                                            color: PanadoroStyle.colSubtext
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            visible: tagCard.modelData.goalMinutes > 0
                                            implicitHeight: 5
                                            radius: 3
                                            color: PanadoroStyle.colField

                                            Rectangle {
                                                width: Math.max(parent.height,
                                                    parent.width * Math.max(0, tagCard.modelData.goalProgress))
                                                height: parent.height
                                                radius: parent.radius
                                                color: PanadoroStyle.tagColor(tagCard.modelData.tag)
                                            }
                                        }

                                        StyledText {
                                            visible: tagCard.modelData.goalMinutes > 0
                                            text: String(Math.round(Math.max(0, tagCard.modelData.goalProgress) * 100)) + "%"
                                            font.family: PanadoroStyle.fontNumbers
                                            font.variableAxes: PanadoroStyle.axesDigits
                                            font.pixelSize: PanadoroStyle.textSmall
                                            color: PanadoroStyle.tagColor(tagCard.modelData.tag)
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
                Layout.preferredHeight: PanadoroStyle.gapHuge
            }
        }
    }
}
