import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.panadoro.components

/** Today: the habits that are due, the smallest possible next step, and the score. */
Item {
    id: root

    property bool compact: false
    property bool wide: false
    property real layoutWidth: root.width
    property ClockSidePanel panels: null

    property string selectedCategory: "all"

    readonly property real padding: root.compact ? PanadoroStyle.pagePadding : PanadoroStyle.pagePaddingWide
    readonly property real contentWidth: root.layoutWidth - root.padding * 2
    readonly property int columns: root.contentWidth >= 760 ? 2 : 1
    readonly property var categoryFilters: [{
        id: "all", name: Translation.tr("All"), icon: "apps", accent: "primary", deleted: false
    }].concat(PanadoroService.activeCategories)

    readonly property var visibleHabits: {
        const list = root.selectedCategory === "all"
            ? PanadoroService.todayHabits
            : PanadoroService.todayHabits.filter(habit => String(habit.categoryId) === root.selectedCategory);
        const showDone = Persistent.states.panadoro?.showCompleted ?? true;
        return showDone ? list : list.filter(habit => !PanadoroService.habitDone(habit));
    }

    readonly property int doneCount: root.visibleHabits.filter(habit => PanadoroService.habitDone(habit)).length
    readonly property int totalCount: root.visibleHabits.length
    readonly property real progress: root.totalCount > 0 ? root.doneCount / root.totalCount : 0
    readonly property string greeting: {
        const hour = new Date().getHours();
        if (hour < 5) return Translation.tr("Still up?");
        if (hour < 12) return Translation.tr("Good morning");
        if (hour < 18) return Translation.tr("Good afternoon");
        return Translation.tr("Good evening");
    }
    readonly property string subtitle: {
        if (root.totalCount === 0)
            return Translation.tr("Nothing scheduled. Add one small thing.");
        return Translation.tr("%1 of %2 habits · %3 focused today")
            .arg(String(root.doneCount))
            .arg(String(root.totalCount))
            .arg(PanadoroStyle.durationShort(PanadoroService.todayFocusMinutes));
    }

    signal newCategoryRequested()

    function openHabit(habitId = ""): void {
        root.panels.show(habitEditor, {
            habitId: String(habitId ?? ""),
            panels: root.panels
        });
    }

    function toggleHabit(habit): void {
        if (PanadoroService.habitDone(habit))
            PanadoroService.toggleHabitDone(habit.id);
        else if (Math.max(1, Number(habit?.target ?? 1)) > 1)
            PanadoroService.incrementHabit(habit.id, 1);
        else
            PanadoroService.toggleHabitDone(habit.id);
    }

    function primaryAction(): void {
        root.openHabit("");
    }

    function editCategory(categoryId = ""): void {
        root.panels.show(categoryEditor, {
            categoryId: String(categoryId ?? ""),
            panels: root.panels
        });
    }

    Component {
        id: habitEditor
        PanadoroHabitEditorSheet {}
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
                symbol: root.progress >= 1 && root.totalCount > 0 ? "celebration" : "wb_sunny"
                title: root.greeting + (root.totalCount > 0 && root.progress >= 1 ? ", all done." : ".")
                text: root.subtitle
                shapeName: root.progress >= 1 ? "Flower" : "Cookie9Sided"
                colContainer: root.progress >= 1 ? PanadoroStyle.colSuccessContainer : PanadoroStyle.colTertiaryContainer
                colOnContainer: root.progress >= 1 ? PanadoroStyle.colOnSuccessContainer : PanadoroStyle.colOnTertiaryContainer
                colAccent: root.progress >= 1 ? PanadoroStyle.colSuccess : PanadoroStyle.colTertiary

                RowLayout {
                    spacing: PanadoroStyle.gapTiny

                    Item {
                        implicitWidth: 76
                        implicitHeight: 76

                        ClockProgressRing {
                            anchors.fill: parent
                            value: root.progress
                            thickness: 6
                            wavy: root.totalCount > 0 && root.progress < 1
                            maxAmplitude: 2
                            colIndicator: root.progress >= 1 ? PanadoroStyle.colSuccess : PanadoroStyle.colTertiary
                            colTrack: ColorUtils.applyAlpha(PanadoroStyle.colOnTertiaryContainer, 0.16)
                        }

                        StyledText {
                            anchors.centerIn: parent
                            text: String(root.doneCount) + "/" + String(root.totalCount)
                            font.family: PanadoroStyle.fontNumbers
                            font.variableAxes: PanadoroStyle.axesDigitsBold
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: root.progress >= 1 ? PanadoroStyle.colOnSuccessContainer : PanadoroStyle.colOnTertiaryContainer
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: PanadoroStyle.gapTiny
                columns: root.contentWidth >= 640 ? 3 : 1
                columnSpacing: PanadoroStyle.gap
                rowSpacing: PanadoroStyle.gap

                PanadoroStatTile {
                    Layout.fillWidth: true
                    symbol: "check_circle"
                    value: String(PanadoroService.todayHabitsDone) + " / " + String(PanadoroService.todayHabitsTotal)
                    label: Translation.tr("Habits today")
                    hint: Translation.tr("%1% complete").arg(String(Math.round(PanadoroService.todayHabitsProgress * 100)))
                    shapeName: "Cookie7Sided"
                    colContainer: PanadoroStyle.colPrimaryContainer
                    colOnContainer: PanadoroStyle.colOnPrimaryContainer
                }

                PanadoroStatTile {
                    Layout.fillWidth: true
                    symbol: "psychiatry"
                    value: PanadoroStyle.durationShort(PanadoroService.todayFocusMinutes)
                    label: Translation.tr("Focused today")
                    hint: Translation.tr("Goals are set per tag")
                    shapeName: "Flower"
                    colContainer: PanadoroStyle.colTertiaryContainer
                    colOnContainer: PanadoroStyle.colOnTertiaryContainer
                }

                PanadoroStatTile {
                    Layout.fillWidth: true
                    symbol: "local_fire_department"
                    value: String(PanadoroService.focusStreak())
                    label: Translation.tr("Focus streak")
                    hint: Translation.tr("Keep the thread")
                    shapeName: "SoftBurst"
                    colContainer: PanadoroStyle.colSecondaryContainer
                    colOnContainer: PanadoroStyle.colOnSecondaryContainer
                    flame: true
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: PanadoroStyle.gapSmall
                spacing: PanadoroStyle.gapSmall

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Today")
                    font.family: PanadoroStyle.fontTitle
                    font.variableAxes: PanadoroStyle.axesTitle
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: PanadoroStyle.colOnSurface
                }

                ClockIconButton {
                    visible: root.selectedCategory !== "all"
                    symbol: "edit"
                    size: 40
                    iconSize: 18
                    tooltip: Translation.tr("Edit this category")
                    onClicked: root.editCategory(root.selectedCategory)
                }

                ClockIconButton {
                    visible: root.selectedCategory !== "all"
                    symbol: "delete"
                    size: 40
                    iconSize: 18
                    tooltip: Translation.tr("Delete this category")
                    colIcon: PanadoroStyle.colError
                    onClicked: PanadoroService.deleteCategory(root.selectedCategory)
                }

                ClockButton {
                    symbol: "add"
                    label: Translation.tr("Category")
                    onClicked: root.editCategory("")
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: PanadoroStyle.gapSmall

                Repeater {
                    model: root.categoryFilters

                    PanadoroTagChip {
                        required property var modelData
                        tag: modelData.id === "all" ? {
                            id: "all", name: modelData.name, icon: "apps",
                            accent: "primary", shape: "Cookie4Sided"
                        } : modelData
                        selected: root.selectedCategory === String(modelData.id)
                        trailingText: modelData.id === "all"
                            ? String(PanadoroService.todayHabitsTotal) : ""
                        onClicked: root.selectedCategory = String(modelData.id)
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.visibleHabits.length > 0 ? habitGrid.implicitHeight : 260
                visible: true

                GridLayout {
                    id: habitGrid
                    width: parent.width
                    columns: root.columns
                    columnSpacing: PanadoroStyle.gap
                    rowSpacing: PanadoroStyle.gap

                    Repeater {
                        model: root.visibleHabits

                        PanadoroHabitRow {
                            Layout.fillWidth: true
                            onEditRequested: root.openHabit(modelData.id)
                            onToggleRequested: root.toggleHabit(modelData)
                        }
                    }
                }

                ClockEmptyState {
                    anchors.centerIn: parent
                    width: parent.width
                    visible: root.visibleHabits.length === 0
                    symbol: root.selectedCategory === "all" ? "check_circle" : "label"
                    shape: "Cookie9Sided"
                    shapeSize: 112
                    title: root.selectedCategory === "all"
                        ? Translation.tr("A clear day")
                        : Translation.tr("Nothing here")
                    subtitle: root.selectedCategory === "all"
                        ? Translation.tr("Add a habit you can keep, and it will wait for you here.")
                        : Translation.tr("No habits in this category are scheduled today.")
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

    Component {
        id: categoryEditor
        PanadoroCategoryEditorSheet {}
    }

    Connections {
        target: PanadoroService

        function onCategoriesChanged() {
            if (root.selectedCategory === "all")
                return;
            if (!PanadoroService.activeCategories.some(item => String(item.id) === root.selectedCategory))
                root.selectedCategory = "all";
        }
    }
}
