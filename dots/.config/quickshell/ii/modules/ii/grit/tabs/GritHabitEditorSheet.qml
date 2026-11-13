import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.grit.components

/** Create or edit a habit: its face, its days, and what counts as done. */
ClockSheet {
    id: root

    property string habitId: ""
    property ClockSidePanel panels: null

    readonly property var existing: GritService.habitById(root.habitId)
    readonly property bool editing: root.existing !== null
    readonly property color colAccent: GritStyle.categoryColor(GritService.categoryById(root.categoryId))

    property string name: ""
    property string icon: "check_circle"
    property string categoryId: ""
    property var dayFlags: [true, true, true, true, true, true, true]
    property int targetValue: 1
    property string unit: Translation.tr("times")
    property string time: ""
    property string note: ""

    title: root.editing ? Translation.tr("Edit habit") : Translation.tr("New habit")
    subtitle: Translation.tr("Small enough to keep, visible enough to remember")
    scrollable: true

    function load(): void {
        const habit = root.existing;
        if (!habit) {
            root.categoryId = GritService.activeCategories[0]?.id ?? "";
            return;
        }
        root.name = String(habit.name ?? "");
        root.icon = String(habit.icon ?? "check_circle");
        root.categoryId = String(habit.categoryId ?? "");
        root.targetValue = Math.max(1, Number(habit.target ?? 1));
        root.unit = String(habit.unit ?? Translation.tr("times"));
        root.time = String(habit.time ?? "");
        root.note = String(habit.note ?? "");
        const scheduled = Array.from(habit.days ?? [0, 1, 2, 3, 4, 5, 6]).map(Number);
        root.dayFlags = [0, 1, 2, 3, 4, 5, 6].map(day => scheduled.includes(day));
    }

    function toggleDay(day): void {
        const next = Array.from(root.dayFlags);
        next[day] = !next[day];
        if (!next.some(Boolean))
            next[day] = true;
        root.dayFlags = next;
    }

    function save(): void {
        const days = root.dayFlags.map((on, index) => on ? index : -1).filter(index => index >= 0);
        const draft = {
            name: root.name.trim().length > 0 ? root.name.trim() : Translation.tr("New habit"),
            icon: root.icon,
            categoryId: root.categoryId,
            days: days.length > 0 ? days : [0, 1, 2, 3, 4, 5, 6],
            target: Math.max(1, root.targetValue),
            unit: root.unit.trim().length > 0 ? root.unit.trim() : Translation.tr("times"),
            time: root.time.trim(),
            note: root.note.trim()
        };
        if (root.editing)
            GritService.updateHabit(root.habitId, draft);
        else
            GritService.createHabit(draft);
        root.close();
    }

    Component.onCompleted: root.load()

    ClockFormField {
        symbol: "edit_note"
        shapeKind: MaterialShape.Shape.Cookie7Sided
        caption: Translation.tr("Habit")
        placeholder: Translation.tr("Read ten pages")
        text: root.name
        onTextChanged: root.name = text
        onAccepted: root.save()
    }

    StyledText {
        Layout.leftMargin: 4
        text: Translation.tr("Icon")
        font.pixelSize: GritStyle.textSmall
        font.weight: Font.DemiBold
        color: GritStyle.colOnSurfaceVariant
    }

    GritIconPicker {
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        selected: root.icon
        colAccent: root.colAccent
        onPicked: icon => root.icon = icon
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
        text: Translation.tr("Days")
        font.pixelSize: GritStyle.textSmall
        font.weight: Font.DemiBold
        color: GritStyle.colOnSurfaceVariant
    }

    ClockDayChips {
        Layout.fillWidth: true
        days: root.dayFlags
        onToggled: day => root.toggleDay(day)
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: targetRow.implicitHeight + 20
        radius: GritStyle.radiusSmall
        color: GritStyle.colField

        RowLayout {
            id: targetRow
            anchors {
                fill: parent
                leftMargin: 12
                rightMargin: 10
            }
            spacing: GritStyle.gap

            MaterialShapeWrappedMaterialSymbol {
                text: "flag"
                iconSize: 18
                padding: 8
                shape: "Cookie4Sided"
                color: GritStyle.colPrimaryContainer
                colSymbol: GritStyle.colOnPrimaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: Translation.tr("Daily target")
                    font.pixelSize: GritStyle.textNormal
                    font.weight: Font.DemiBold
                    color: GritStyle.colOnSurface
                }

                StyledText {
                    text: Translation.tr("How many times before the habit is done")
                    font.pixelSize: GritStyle.textSmall
                    color: GritStyle.colSubtext
                }
            }

            ClockStepper {
                value: root.targetValue
                from: 1
                to: 100
                onMoved: value => root.targetValue = value
            }
        }
    }

    ClockFormField {
        symbol: "straighten"
        shapeKind: MaterialShape.Shape.Cookie4Sided
        caption: Translation.tr("Unit")
        placeholder: Translation.tr("times")
        text: root.unit
        onTextChanged: root.unit = text
    }

    ClockFormField {
        symbol: "schedule"
        shapeKind: MaterialShape.Shape.Cookie9Sided
        caption: Translation.tr("Preferred time")
        placeholder: "07:00"
        text: root.time
        onTextChanged: root.time = text
    }

    ClockFormField {
        symbol: "notes"
        shapeKind: MaterialShape.Shape.Cookie7Sided
        caption: Translation.tr("Why this habit")
        placeholder: Translation.tr("A sentence to your future self")
        text: root.note
        onTextChanged: root.note = text
    }

    actions: ColumnLayout {
        Layout.fillWidth: true
        spacing: GritStyle.gapSmall

        ClockButton {
            Layout.fillWidth: true
            variant: "filled"
            symbol: "check"
            label: root.editing ? Translation.tr("Save habit") : Translation.tr("Create habit")
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
                    GritService.deleteHabit(root.habitId);
                    root.close();
                }
            }
        }
    }
}
