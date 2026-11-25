import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.panadoro.components

/** Tasks: the things that are not habits, kept in the same day as them. */
Item {
    id: root

    property bool compact: false
    property bool wide: false
    property real layoutWidth: root.width
    property ClockSidePanel panels: null

    property string filter: "open"

    readonly property real padding: root.compact ? PanadoroStyle.pagePadding : PanadoroStyle.pagePaddingWide
    readonly property real contentWidth: root.layoutWidth - root.padding * 2
    readonly property int columns: root.contentWidth >= 820 ? 2 : 1
    readonly property var filters: [
        { id: "open", label: Translation.tr("Open"), icon: "radio_button_unchecked" },
        { id: "today", label: Translation.tr("Today"), icon: "today" },
        { id: "upcoming", label: Translation.tr("Upcoming"), icon: "date_range" },
        { id: "done", label: Translation.tr("Done"), icon: "check_circle" }
    ]
    readonly property var tasks: PanadoroService.taskFiltered(root.filter)
    readonly property string subtitle: Translation.tr("%1 open · %2 due today · %3 done")
        .arg(String(PanadoroService.openTaskCount))
        .arg(String(PanadoroService.dueTodayTaskCount))
        .arg(String(PanadoroService.doneTaskCount))

    function openTask(taskId = ""): void {
        root.panels.show(taskEditor, {
            taskId: String(taskId ?? ""),
            panels: root.panels
        });
    }

    function primaryAction(): void {
        root.openTask("");
    }

    Component {
        id: taskEditor
        PanadoroTaskEditorSheet {}
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + root.padding + PanadoroStyle.fabClearance
        clip: true

        ColumnLayout {
            id: column
            width: root.contentWidth
            x: root.padding
            spacing: PanadoroStyle.gap

            PanadoroHero {
                Layout.fillWidth: true
                compact: root.compact
                symbol: root.tasks.length === 0 ? "task_alt" : "checklist"
                title: root.tasks.length === 0
                    ? Translation.tr("Nothing left in this list.")
                    : Translation.tr("One thing at a time.")
                text: root.subtitle
                shapeName: "Cookie7Sided"
                colContainer: root.filter === "done" ? PanadoroStyle.colSuccessContainer : PanadoroStyle.colPrimaryContainer
                colOnContainer: root.filter === "done" ? PanadoroStyle.colOnSuccessContainer : PanadoroStyle.colOnPrimaryContainer
                colAccent: root.filter === "done" ? PanadoroStyle.colSuccess : PanadoroStyle.colPrimary

                ColumnLayout {
                    spacing: 0

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: String(root.tasks.length)
                        font.family: PanadoroStyle.fontNumbers
                        font.variableAxes: PanadoroStyle.axesDigitsBold
                        font.pixelSize: Appearance.font.pixelSize.huge + 8
                        color: root.filter === "done" ? PanadoroStyle.colOnSuccessContainer : PanadoroStyle.colOnPrimaryContainer
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.filter === "done" ? Translation.tr("done") : Translation.tr("showing")
                        font.pixelSize: PanadoroStyle.textSmall
                        color: root.filter === "done" ? PanadoroStyle.colOnSuccessContainer : PanadoroStyle.colOnPrimaryContainer
                        opacity: 0.8
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.contentWidth >= 640 ? 3 : 1
                columnSpacing: PanadoroStyle.gap
                rowSpacing: PanadoroStyle.gap

                PanadoroStatTile {
                    Layout.fillWidth: true
                    symbol: "radio_button_unchecked"
                    value: String(PanadoroService.openTaskCount)
                    label: Translation.tr("Open tasks")
                    shapeName: "Cookie7Sided"
                    colContainer: PanadoroStyle.colPrimaryContainer
                    colOnContainer: PanadoroStyle.colOnPrimaryContainer
                }

                PanadoroStatTile {
                    Layout.fillWidth: true
                    symbol: "today"
                    value: String(PanadoroService.dueTodayTaskCount)
                    label: Translation.tr("Due today")
                    hint: PanadoroService.overdueTaskCount > 0
                        ? Translation.tr("%1 overdue").arg(String(PanadoroService.overdueTaskCount)) : ""
                    shapeName: "Cookie9Sided"
                    colContainer: PanadoroStyle.colTertiaryContainer
                    colOnContainer: PanadoroStyle.colOnTertiaryContainer
                }

                PanadoroStatTile {
                    Layout.fillWidth: true
                    symbol: "check_circle"
                    value: String(PanadoroService.doneTaskCount)
                    label: Translation.tr("Finished")
                    shapeName: "Flower"
                    colContainer: PanadoroStyle.colSuccessContainer
                    colOnContainer: PanadoroStyle.colOnSuccessContainer
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: PanadoroStyle.gapSmall
                spacing: PanadoroStyle.gapSmall

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Tasks")
                    font.family: PanadoroStyle.fontTitle
                    font.variableAxes: PanadoroStyle.axesTitle
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: PanadoroStyle.colOnSurface
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: PanadoroStyle.gapSmall

                Repeater {
                    model: root.filters

                    PanadoroChoiceChip {
                        required property var modelData
                        label: String(modelData.label ?? "")
                        symbol: String(modelData.icon ?? "")
                        selected: root.filter === String(modelData.id)
                        onTriggered: root.filter = String(modelData.id)
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.tasks.length > 0 ? taskGrid.implicitHeight : 260

                GridLayout {
                    id: taskGrid
                    width: parent.width
                    columns: root.columns
                    columnSpacing: PanadoroStyle.gap
                    rowSpacing: PanadoroStyle.gap

                    Repeater {
                        model: root.tasks

                        PanadoroTaskRow {
                            Layout.fillWidth: true
                            onEditRequested: root.openTask(modelData.id)
                        }
                    }
                }

                ClockEmptyState {
                    anchors.centerIn: parent
                    width: parent.width
                    visible: root.tasks.length === 0
                    symbol: root.filter === "done" ? "history" : "task_alt"
                    shape: "Cookie9Sided"
                    shapeSize: 112
                    title: root.filter === "done" ? Translation.tr("No history yet") : Translation.tr("The list is clear")
                    subtitle: root.filter === "done"
                        ? Translation.tr("Finished tasks will collect here.")
                        : Translation.tr("Add a task, or enjoy the empty space.")
                    colShape: PanadoroStyle.colSecondaryContainer
                    colIcon: PanadoroStyle.colOnSecondaryContainer
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: PanadoroStyle.fabClearance
            }
        }
    }
}
