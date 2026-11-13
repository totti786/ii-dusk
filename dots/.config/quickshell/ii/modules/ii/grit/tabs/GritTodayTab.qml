import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.grit.components

/** Today: the habits that are due, the smallest possible next step, and the score. */
Item {
    id: root

    property bool compact: false
    property bool wide: false
    property real layoutWidth: root.width
    property ClockSidePanel panels: null

    property string selectedCategory: "all"

    readonly property real padding: root.compact ? GritStyle.pagePadding : GritStyle.pagePaddingWide
    readonly property real contentWidth: root.layoutWidth - root.padding * 2
    readonly property int columns: root.contentWidth >= 760 ? 2 : 1
    readonly property var categoryFilters: [{
        id: "all", name: Translation.tr("All"), icon: "apps", accent: "primary", deleted: false
    }].concat(GritService.activeCategories)

    readonly property var visibleHabits: {
        const list = root.selectedCategory === "all"
            ? GritService.todayHabits
            : GritService.todayHabits.filter(habit => String(habit.categoryId) === root.selectedCategory);
        const showDone = Persistent.states.grit?.showCompleted ?? true;
        return showDone ? list : list.filter(habit => !GritService.habitDone(habit));
    }

    readonly property int doneCount: root.visibleHabits.filter(habit => GritService.habitDone(habit)).length
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
            .arg(GritStyle.durationShort(GritService.todayFocusMinutes));
    }

    signal newCategoryRequested()

    function openHabit(habitId = ""): void {
        root.panels.show(habitEditor, {
            habitId: String(habitId ?? ""),
            panels: root.panels
        });
    }

    function toggleHabit(habit): void {
        if (GritService.habitDone(habit))
            GritService.toggleHabitDone(habit.id);
        else if (Math.max(1, Number(habit?.target ?? 1)) > 1)
            GritService.incrementHabit(habit.id, 1);
        else
            GritService.toggleHabitDone(habit.id);
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
        GritHabitEditorSheet {}
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + root.padding + GritStyle.fabClearance
        clip: true

        ColumnLayout {
            id: column
            width: root.contentWidth
            x: root.padding
            spacing: GritStyle.gap

            GritHero {
                Layout.fillWidth: true
                compact: root.compact
                symbol: root.progress >= 1 && root.totalCount > 0 ? "celebration" : "wb_sunny"
                title: root.greeting + (root.totalCount > 0 && root.progress >= 1 ? ", all done." : ".")
                text: root.subtitle
                shapeName: root.progress >= 1 ? "Flower" : "Cookie9Sided"
                colContainer: root.progress >= 1 ? GritStyle.colSuccessContainer : GritStyle.colTertiaryContainer
                colOnContainer: root.progress >= 1 ? GritStyle.colOnSuccessContainer : GritStyle.colOnTertiaryContainer
                colAccent: root.progress >= 1 ? GritStyle.colSuccess : GritStyle.colTertiary

                RowLayout {
                    spacing: GritStyle.gapTiny

                    Item {
                        implicitWidth: 76
                        implicitHeight: 76

                        ClockProgressRing {
                            anchors.fill: parent
                            value: root.progress
                            thickness: 6
                            wavy: root.totalCount > 0 && root.progress < 1
                            maxAmplitude: 2
                            colIndicator: root.progress >= 1 ? GritStyle.colSuccess : GritStyle.colTertiary
                            colTrack: ColorUtils.applyAlpha(GritStyle.colOnTertiaryContainer, 0.16)
                        }

                        StyledText {
                            anchors.centerIn: parent
                            text: String(root.doneCount) + "/" + String(root.totalCount)
                            font.family: GritStyle.fontNumbers
                            font.variableAxes: GritStyle.axesDigitsBold
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: root.progress >= 1 ? GritStyle.colOnSuccessContainer : GritStyle.colOnTertiaryContainer
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: GritStyle.gapTiny
                columns: root.contentWidth >= 640 ? 3 : 1
                columnSpacing: GritStyle.gap
                rowSpacing: GritStyle.gap

                GritStatTile {
                    Layout.fillWidth: true
                    symbol: "check_circle"
                    value: String(GritService.todayHabitsDone) + " / " + String(GritService.todayHabitsTotal)
                    label: Translation.tr("Habits today")
                    hint: Translation.tr("%1% complete").arg(String(Math.round(GritService.todayHabitsProgress * 100)))
                    shapeName: "Cookie7Sided"
                    colContainer: GritStyle.colPrimaryContainer
                    colOnContainer: GritStyle.colOnPrimaryContainer
                }

                GritStatTile {
                    Layout.fillWidth: true
                    symbol: "psychiatry"
                    value: GritStyle.durationShort(GritService.todayFocusMinutes)
                    label: Translation.tr("Focused today")
                    hint: Translation.tr("Goals are set per tag")
                    shapeName: "Flower"
                    colContainer: GritStyle.colTertiaryContainer
                    colOnContainer: GritStyle.colOnTertiaryContainer
                }

                GritStatTile {
                    Layout.fillWidth: true
                    symbol: "local_fire_department"
                    value: String(GritService.focusStreak())
                    label: Translation.tr("Focus streak")
                    hint: Translation.tr("Keep the thread")
                    shapeName: "SoftBurst"
                    colContainer: GritStyle.colSecondaryContainer
                    colOnContainer: GritStyle.colOnSecondaryContainer
                    flame: true
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: GritStyle.gapSmall
                spacing: GritStyle.gapSmall

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Today")
                    font.family: GritStyle.fontTitle
                    font.variableAxes: GritStyle.axesTitle
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: GritStyle.colOnSurface
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
                    colIcon: GritStyle.colError
                    onClicked: GritService.deleteCategory(root.selectedCategory)
                }

                ClockButton {
                    symbol: "add"
                    label: Translation.tr("Category")
                    onClicked: root.editCategory("")
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: GritStyle.gapSmall

                Repeater {
                    model: root.categoryFilters

                    GritTagChip {
                        required property var modelData
                        tag: modelData.id === "all" ? {
                            id: "all", name: modelData.name, icon: "apps",
                            accent: "primary", shape: "Cookie4Sided"
                        } : modelData
                        selected: root.selectedCategory === String(modelData.id)
                        trailingText: modelData.id === "all"
                            ? String(GritService.todayHabitsTotal) : ""
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
                    columnSpacing: GritStyle.gap
                    rowSpacing: GritStyle.gap

                    Repeater {
                        model: root.visibleHabits

                        GritHabitRow {
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
                    colShape: GritStyle.colSecondaryContainer
                    colIcon: GritStyle.colOnSecondaryContainer
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: GritStyle.fabClearance
            }
        }
    }

    Component {
        id: categoryEditor
        GritCategoryEditorSheet {}
    }

    Connections {
        target: GritService

        function onCategoriesChanged() {
            if (root.selectedCategory === "all")
                return;
            if (!GritService.activeCategories.some(item => String(item.id) === root.selectedCategory))
                root.selectedCategory = "all";
        }
    }
}
