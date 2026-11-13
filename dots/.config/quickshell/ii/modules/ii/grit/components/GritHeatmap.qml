import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.grit.components

/**
 * A week-aligned focus heatmap. Columns are real weeks, rows are the days of the
 * week, and the colour is deliberately quiet: the grid is context, not a dashboard
 * competing with the numbers above it.
 *
 * `values` must come from `GritService.focusHeatmapWeeks()`, which supplies leading
 * and trailing days so every column has seven cells.
 */
Item {
    id: root

    property var values: []
    property color colAccent: GritStyle.colPrimary
    property color colEmpty: GritStyle.colField
    property real cellSize: 11
    property real cellGap: 3
    property bool showLabels: true

    readonly property bool mondayStart: Persistent.states.grit?.weekStartMonday ?? true
    readonly property int startDay: root.mondayStart ? 1 : 0
    readonly property real maxValue: {
        let max = 1;
        for (const item of Array.from(root.values ?? []))
            max = Math.max(max, Number(item?.value ?? 0));
        return max;
    }
    readonly property var chunks: {
        const list = Array.from(root.values ?? []);
        const out = [];
        for (let i = 0; i < list.length; i += 7)
            out.push(list.slice(i, i + 7));
        return out;
    }

    implicitWidth: grid.implicitWidth
    implicitHeight: grid.implicitHeight

    Row {
        id: grid
        spacing: 6

        Rectangle {
            id: labelBox
            visible: root.showLabels
            width: Math.max(18, root.cellSize * 0.9)
            height: root.cellSize * 7 + root.cellGap * 6
            radius: Math.max(3, root.cellSize * 0.16)
            color: GritStyle.colField
            border.width: 1
            border.color: ColorUtils.applyAlpha(GritStyle.colOutline, 0.24)

            Column {
                anchors.centerIn: parent
                spacing: root.cellGap

                Repeater {
                    model: 7

                    Item {
                        required property int index
                        width: labelBox.width
                        height: root.cellSize

                        StyledText {
                            anchors.centerIn: parent
                            text: Qt.locale().dayName((root.startDay + index) % 7, Locale.ShortFormat).slice(0, 1)
                            font.pixelSize: Math.max(9, root.cellSize * 0.5)
                            font.weight: Font.DemiBold
                            color: GritStyle.colOnSurfaceVariant
                        }
                    }
                }
            }
        }

        Repeater {
            model: root.chunks

            Column {
                id: week
                required property var modelData
                spacing: root.cellGap

                Repeater {
                    model: week.modelData

                    Rectangle {
                        id: cell
                        required property var modelData

                        readonly property bool future: cell.modelData?.future === true
                        readonly property real value: Number(cell.modelData?.value ?? 0)

                        width: root.cellSize
                        height: root.cellSize
                        radius: Math.max(2, root.cellSize * 0.22)
                        color: cell.value <= 0
                            ? ColorUtils.applyAlpha(root.colEmpty, cell.future ? 0.25 : 0.65)
                            : ColorUtils.mix(root.colAccent, root.colEmpty,
                                0.2 + 0.55 * Math.min(1, Math.sqrt(cell.value / root.maxValue)))
                        border.width: String(cell.modelData?.date ?? "") === GritService.todayKey ? 1 : 0
                        border.color: ColorUtils.applyAlpha(root.colAccent, 0.85)
                        opacity: cell.future ? 0.35 : 1

                        Behavior on color {
                            animation: GritStyle.motionFast.colorAnimation.createObject(this)
                        }

                        StyledToolTip {
                            text: GritService.relativeDay(String(cell.modelData?.date ?? "")) + " · "
                                + (cell.value > 0
                                    ? GritStyle.durationShort(Math.round(cell.value / 60))
                                    : Translation.tr("No focus"))
                            extraVisibleCondition: cellHover.containsMouse
                        }

                        MouseArea {
                            id: cellHover
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                    }
                }
            }
        }
    }
}
