import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.panadoro.components

/**
 * The seven-day strip under a habit, like the week calendar in the original Panadoro:
 * completed days fill with the habit's colour, scheduled days wait with an outline,
 * and any past day can be tapped to backfill it.
 */
RowLayout {
    id: root

    required property var habit
    property color colAccent: PanadoroStyle.colPrimary
    property color colOnAccent: PanadoroStyle.colOnPrimary
    property int cellSize: 30

    readonly property var days: PanadoroService.thisWeekDays()
    readonly property string today: PanadoroService.todayKey
    readonly property int target: Math.max(1, Number(root.habit?.target ?? 1))

    spacing: 4

    Repeater {
        model: root.days

        Rectangle {
            id: cell
            required property var modelData

            readonly property string key: String(modelData ?? "")
            readonly property bool scheduled: PanadoroService.scheduledOn(root.habit, cell.key)
            readonly property bool done: PanadoroService.habitDone(root.habit, cell.key)
            readonly property real progress: PanadoroService.habitProgress(root.habit, cell.key)
            readonly property bool future: cell.key > root.today
            readonly property bool isToday: cell.key === root.today
            readonly property var date: PanadoroService.dateFromKey(cell.key)

            implicitWidth: root.cellSize
            implicitHeight: root.cellSize
            radius: 8
            color: cell.done
                ? ColorUtils.mix(root.colAccent, PanadoroStyle.colField, 0.35 + 0.65 * cell.progress)
                : cell.scheduled && !cell.future
                    ? PanadoroStyle.colField
                    : ColorUtils.applyAlpha(PanadoroStyle.colField, 0.4)
            border.width: cell.isToday ? 1.5 : cell.scheduled && !cell.done && !cell.future ? 1 : 0
            border.color: cell.isToday
                ? root.colAccent
                : ColorUtils.applyAlpha(PanadoroStyle.colOutlineStrong, 0.55)
            opacity: cell.future ? 0.4 : 1

            Behavior on color {
                animation: PanadoroStyle.motionFast.colorAnimation.createObject(this)
            }
            Behavior on opacity {
                animation: PanadoroStyle.motionFast.numberAnimation.createObject(this)
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: -2

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.dayName(cell.date.getDay(), Locale.NarrowFormat)
                    font.pixelSize: Math.max(9, root.cellSize * 0.3)
                    font.weight: Font.DemiBold
                    color: cell.done
                        ? ColorUtils.mostReadable(cell.color, [root.colOnAccent, PanadoroStyle.colOnSurface])
                        : PanadoroStyle.colSubtext
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: String(cell.date.getDate())
                    font.family: PanadoroStyle.fontNumbers
                    font.variableAxes: PanadoroStyle.axesDigits
                    font.pixelSize: Math.max(12, root.cellSize * 0.4)
                    color: cell.done
                        ? ColorUtils.mostReadable(cell.color, [root.colOnAccent, PanadoroStyle.colOnSurface])
                        : cell.scheduled ? PanadoroStyle.colOnSurface : PanadoroStyle.colSubtext
                }
            }

            MouseArea {
                id: hit
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: cell.scheduled && !cell.future ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (!cell.scheduled || cell.future)
                        return;
                    PanadoroService.setHabitEntry(root.habit?.id ?? "", cell.key,
                        cell.done ? 0 : root.target);
                }
            }

            StyledToolTip {
                text: PanadoroService.relativeDay(cell.key) + " · "
                    + (cell.done ? Translation.tr("Done")
                        : cell.scheduled ? Translation.tr("Not yet")
                        : Translation.tr("Not scheduled"))
                extraVisibleCondition: hit.containsMouse
            }

            SequentialAnimation {
                id: pop
                running: false
                NumberAnimation {
                    target: cell
                    property: "scale"
                    from: 1.18
                    to: 1
                    duration: Appearance.dur(280)
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                }
            }

            onDoneChanged: {
                if (cell.done && !PanadoroStyle.reducedMotion)
                    pop.restart();
            }
        }
    }
}
