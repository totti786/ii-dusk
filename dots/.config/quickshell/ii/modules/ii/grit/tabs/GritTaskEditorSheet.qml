import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.grit.components

/** Create or edit a task, including its subtasks and due date. */
ClockSheet {
    id: root

    property string taskId: ""
    property ClockSidePanel panels: null

    readonly property var existing: GritService.taskById(root.taskId)
    readonly property bool editing: root.existing !== null

    property string taskTitle: ""
    property string notes: ""
    property string categoryId: ""
    property string taskTag: ""
    property string due: ""
    property int priority: 0
    property var subtasksDraft: []
    property string newSubtask: ""

    title: root.editing ? Translation.tr("Edit task") : Translation.tr("New task")
    subtitle: Translation.tr("Capture it now, finish it when you can")
    scrollable: true

    function load(): void {
        const task = root.existing;
        if (!task) {
            root.categoryId = GritService.activeCategories[0]?.id ?? "";
            return;
        }
        root.taskTitle = String(task.title ?? "");
        root.notes = String(task.notes ?? "");
        root.categoryId = String(task.categoryId ?? "");
        root.taskTag = String(task.taskTag ?? "");
        root.due = String(task.due ?? "");
        root.priority = Number(task.priority ?? 0);
        root.subtasksDraft = Array.from(task.subtasks ?? []).map(sub => Object.assign({}, sub));
    }

    function addSubtask(): void {
        const text = root.newSubtask.trim();
        if (text.length === 0)
            return;
        root.subtasksDraft = Array.from(root.subtasksDraft).concat([{
            id: "draft-" + Date.now().toString(36) + "-" + Math.floor(Math.random() * 1000),
            title: text,
            done: false,
            updatedAt: Date.now()
        }]);
        root.newSubtask = "";
    }

    function toggleDraftSubtask(id): void {
        root.subtasksDraft = Array.from(root.subtasksDraft).map(sub =>
            String(sub.id) === String(id) ? Object.assign({}, sub, { done: !sub.done }) : sub);
    }

    function removeDraftSubtask(id): void {
        root.subtasksDraft = Array.from(root.subtasksDraft).filter(sub => String(sub.id) !== String(id));
    }

    function setDue(days): void {
        if (days === null)
            root.due = "";
        else
            root.due = GritService.addDays(GritService.todayKey, Number(days));
    }

    function save(): void {
        const draft = {
            title: root.taskTitle.trim().length > 0 ? root.taskTitle.trim() : Translation.tr("New task"),
            notes: root.notes.trim(),
            categoryId: root.categoryId,
            taskTag: root.taskTag,
            due: root.due.trim(),
            priority: root.priority,
            subtasks: Array.from(root.subtasksDraft)
        };
        if (root.editing)
            GritService.updateTask(root.taskId, draft);
        else
            GritService.createTask(draft);
        root.close();
    }

    Component.onCompleted: root.load()

    ClockFormField {
        symbol: "task_alt"
        shapeKind: MaterialShape.Shape.Cookie4Sided
        caption: Translation.tr("Task")
        placeholder: Translation.tr("Draft the letter")
        text: root.taskTitle
        onTextChanged: root.taskTitle = text
        onAccepted: root.addSubtask()
    }

    ClockFormField {
        symbol: "notes"
        shapeKind: MaterialShape.Shape.Cookie7Sided
        caption: Translation.tr("Notes")
        placeholder: Translation.tr("Anything worth remembering")
        text: root.notes
        onTextChanged: root.notes = text
    }

    StyledText {
        Layout.leftMargin: 4
        Layout.topMargin: 4
        text: Translation.tr("Category")
        font.pixelSize: GritStyle.textSmall
        font.weight: Font.DemiBold
        color: GritStyle.colOnSurfaceVariant
    }

    Flow {
        Layout.fillWidth: true
        spacing: GritStyle.gapSmall

        Repeater {
            model: GritService.activeCategories

            ClockFormChip {
                required property var modelData
                label: String(modelData?.name ?? "")
                selected: root.categoryId === String(modelData?.id ?? "")
                onTriggered: root.categoryId = String(modelData?.id ?? "")
            }
        }
    }

    StyledText {
        Layout.leftMargin: 4
        Layout.topMargin: 4
        text: Translation.tr("Focus tag")
        font.pixelSize: GritStyle.textSmall
        font.weight: Font.DemiBold
        color: GritStyle.colOnSurfaceVariant
    }

    Flow {
        Layout.fillWidth: true
        spacing: GritStyle.gapSmall

        ClockFormChip {
            label: Translation.tr("None")
            selected: root.taskTag.length === 0
            onTriggered: root.taskTag = ""
        }

        Repeater {
            model: GritService.activeTags

            GritTagChip {
                required property var modelData
                tag: modelData
                selected: root.taskTag === String(modelData.id ?? "")
                onClicked: root.taskTag = String(modelData.id ?? "")
            }
        }
    }

    StyledText {
        Layout.leftMargin: 4
        Layout.topMargin: 4
        text: Translation.tr("Due")
        font.pixelSize: GritStyle.textSmall
        font.weight: Font.DemiBold
        color: GritStyle.colOnSurfaceVariant
    }

    Flow {
        Layout.fillWidth: true
        spacing: GritStyle.gapSmall

        ClockFormChip {
            label: Translation.tr("None")
            selected: root.due.length === 0
            onTriggered: root.setDue(null)
        }
        ClockFormChip {
            label: Translation.tr("Today")
            selected: root.due === GritService.todayKey
            onTriggered: root.setDue(0)
        }
        ClockFormChip {
            label: Translation.tr("Tomorrow")
            selected: root.due === GritService.addDays(GritService.todayKey, 1)
            onTriggered: root.setDue(1)
        }
        ClockFormChip {
            label: Translation.tr("Next week")
            symbol: "date_range"
            selected: root.due === GritService.addDays(GritService.todayKey, 7)
            onTriggered: root.setDue(7)
        }
    }

    ClockFormField {
        symbol: "event"
        shapeKind: MaterialShape.Shape.Cookie9Sided
        caption: Translation.tr("Date")
        placeholder: "yyyy-MM-dd"
        text: root.due
        onTextChanged: root.due = text
    }

    StyledText {
        Layout.leftMargin: 4
        Layout.topMargin: 4
        text: Translation.tr("Priority")
        font.pixelSize: GritStyle.textSmall
        font.weight: Font.DemiBold
        color: GritStyle.colOnSurfaceVariant
    }

    Flow {
        Layout.fillWidth: true
        spacing: GritStyle.gapSmall

        ClockFormChip {
            label: Translation.tr("Normal")
            selected: root.priority === 0
            onTriggered: root.priority = 0
        }
        ClockFormChip {
            label: Translation.tr("Important")
            symbol: "priority_high"
            selected: root.priority === 1
            onTriggered: root.priority = 1
        }
        ClockFormChip {
            label: Translation.tr("Urgent")
            symbol: "error"
            selected: root.priority === 2
            onTriggered: root.priority = 2
        }
    }

    StyledText {
        Layout.leftMargin: 4
        Layout.topMargin: 4
        text: Translation.tr("Subtasks")
        font.pixelSize: GritStyle.textSmall
        font.weight: Font.DemiBold
        color: GritStyle.colOnSurfaceVariant
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: GritStyle.gapSmall

        ClockFormField {
            Layout.fillWidth: true
            symbol: "add_task"
            shapeKind: MaterialShape.Shape.Cookie4Sided
            caption: Translation.tr("Break it down")
            placeholder: Translation.tr("One small step")
            text: root.newSubtask
            onTextChanged: root.newSubtask = text
            onAccepted: root.addSubtask()
        }

        ClockIconButton {
            symbol: "add"
            size: 44
            tooltip: Translation.tr("Add subtask")
            colBackground: GritStyle.colSecondaryContainer
            colIcon: GritStyle.colOnSecondaryContainer
            onClicked: root.addSubtask()
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Repeater {
            model: root.subtasksDraft

            RowLayout {
                id: draftRow
                required property var modelData
                Layout.fillWidth: true
                spacing: GritStyle.gapSmall

                ClockIconButton {
                    symbol: draftRow.modelData.done ? "check_circle" : "radio_button_unchecked"
                    size: 28
                    iconSize: 18
                    colIcon: draftRow.modelData.done ? GritStyle.colPrimary : GritStyle.colSubtext
                    onClicked: root.toggleDraftSubtask(draftRow.modelData.id)
                }

                StyledText {
                    Layout.fillWidth: true
                    text: String(draftRow.modelData.title ?? "")
                    elide: Text.ElideRight
                    font.pixelSize: GritStyle.textNormal
                    color: draftRow.modelData.done ? GritStyle.colSubtext : GritStyle.colOnSurface
                    font.strikeout: draftRow.modelData.done === true
                }

                ClockIconButton {
                    symbol: "close"
                    size: 28
                    iconSize: 16
                    onClicked: root.removeDraftSubtask(draftRow.modelData.id)
                }
            }
        }
    }

    actions: ColumnLayout {
        Layout.fillWidth: true
        spacing: GritStyle.gapSmall

        ClockButton {
            Layout.fillWidth: true
            variant: "filled"
            symbol: "check"
            label: root.editing ? Translation.tr("Save task") : Translation.tr("Create task")
            onClicked: root.save()
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: GritStyle.gapSmall

            ClockButton {
                Layout.fillWidth: true
                symbol: "close"
                label: Translation.tr("Cancel")
                onClicked: root.close()
            }

            ClockButton {
                visible: root.editing
                Layout.fillWidth: true
                danger: true
                symbol: "delete"
                label: Translation.tr("Delete")
                onClicked: {
                    GritService.deleteTask(root.taskId);
                    root.close();
                }
            }
        }
    }
}
