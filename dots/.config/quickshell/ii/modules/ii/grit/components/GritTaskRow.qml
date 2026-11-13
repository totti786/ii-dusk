import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.grit.components

/** One task, with its subtasks folded underneath and its due date kept honest. */
Rectangle {
    id: root

    required property var modelData
    required property int index

    property var task: root.modelData

    property bool expanded: false

    readonly property var category: GritService.categoryById(root.task?.categoryId ?? "")
    readonly property var taskTag: GritService.tagById(root.task?.taskTag ?? "")
    readonly property color colAccent: root.taskTag
        ? GritStyle.tagColor(root.taskTag) : GritStyle.categoryColor(root.category)
    readonly property color colContainer: root.taskTag
        ? GritStyle.tagContainer(root.taskTag) : GritStyle.categoryContainer(root.category)
    readonly property var subtasks: Array.from(root.task?.subtasks ?? [])
    readonly property int subtaskDone: root.subtasks.filter(sub => sub.done).length
    readonly property bool overdue: !root.task?.done && String(root.task?.due ?? "").length > 0 && String(root.task.due) < GritService.todayKey
    readonly property bool dueToday: String(root.task?.due ?? "") === GritService.todayKey
    readonly property var priority: Number(root.task?.priority ?? 0)

    signal editRequested()

    implicitHeight: column.implicitHeight + GritStyle.gapLarge * 2
    radius: GritStyle.radiusLarge
    color: root.task?.done ? ColorUtils.mix(GritStyle.colSurface, GritStyle.colField, 0.5) : GritStyle.colSurface

    Behavior on implicitHeight {
        enabled: !GritStyle.reducedMotion
        NumberAnimation {
            duration: GritStyle.motionSpatial.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: GritStyle.motionSpatial.bezierCurve
        }
    }
    Behavior on color {
        animation: GritStyle.motionFast.colorAnimation.createObject(this)
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: GritStyle.gapLarge
            rightMargin: GritStyle.gapLarge
            topMargin: GritStyle.gapLarge
        }
        spacing: GritStyle.gapSmall

        RowLayout {
            Layout.fillWidth: true
            spacing: GritStyle.gap

            RippleButton {
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: root.task?.done ? GritStyle.radiusSmall : 15
                buttonRadiusPressed: GritStyle.radiusSmall
                colBackground: root.task?.done ? root.colAccent : "transparent"
                colBackgroundHover: root.colContainer
                colRipple: root.colContainer
                borderWidth: root.task?.done ? 0 : 2
                borderColor: root.task?.done ? root.colAccent : GritStyle.colOutlineStrong
                onClicked: GritService.toggleTask(root.task?.id ?? "")

                contentItem: Item {
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: root.task?.done === true
                        text: "check"
                        iconSize: 18
                        fill: 1
                        color: ColorUtils.mostReadable(root.colAccent,
                            [GritStyle.colOnPrimary, GritStyle.colBackground])
                        animateChange: !GritStyle.reducedMotion
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: String(root.task?.title ?? "")
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: root.task?.done ? GritStyle.colOnSurfaceVariant : GritStyle.colOnSurface
                    font.strikeout: root.task?.done === true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: GritStyle.gapSmall

                    StyledText {
                        visible: root.taskTag !== null
                        text: String(root.taskTag?.name ?? "")
                        font.pixelSize: GritStyle.textSmall
                        font.weight: Font.DemiBold
                        color: root.colAccent
                    }

                    StyledText {
                        visible: String(root.category?.name ?? "").length > 0
                        text: String(root.category?.name ?? "")
                        font.pixelSize: GritStyle.textSmall
                        color: root.taskTag !== null ? GritStyle.colSubtext : root.colAccent
                    }

                    StyledText {
                        visible: String(root.task?.due ?? "").length > 0
                        text: root.overdue ? Translation.tr("Overdue · %1").arg(GritService.relativeDay(String(root.task.due)))
                            : root.dueToday ? Translation.tr("Today")
                            : GritService.relativeDay(String(root.task?.due ?? ""))
                        font.pixelSize: GritStyle.textSmall
                        font.weight: root.overdue || root.dueToday ? Font.DemiBold : Font.Normal
                        color: root.overdue ? GritStyle.colError : GritStyle.colSubtext
                    }

                    StyledText {
                        visible: root.priority > 0
                        text: root.priority === 2 ? "!!" : "!"
                        font.pixelSize: GritStyle.textSmall
                        font.weight: Font.Bold
                        color: root.priority === 2 ? GritStyle.colError : GritStyle.colTertiary
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        visible: root.subtasks.length > 0
                        text: String(root.subtaskDone) + "/" + String(root.subtasks.length)
                        font.pixelSize: GritStyle.textSmall
                        color: GritStyle.colSubtext
                    }

                    ClockIconButton {
                        visible: root.subtasks.length > 0
                        symbol: root.expanded ? "expand_less" : "expand_more"
                        size: 28
                        iconSize: 18
                        onClicked: root.expanded = !root.expanded
                    }
                }
            }

            ClockIconButton {
                symbol: "edit"
                size: 34
                iconSize: 18
                tooltip: Translation.tr("Edit")
                onClicked: root.editRequested()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 42
            visible: root.expanded && root.subtasks.length > 0
            spacing: 2

            Repeater {
                model: root.subtasks

                RowLayout {
                    id: subRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: GritStyle.gapSmall

                    RippleButton {
                        implicitWidth: 22
                        implicitHeight: 22
                        buttonRadius: subRow.modelData.done ? GritStyle.radiusSmall : 11
                        colBackground: subRow.modelData.done ? root.colAccent : "transparent"
                        colBackgroundHover: root.colContainer
                        colRipple: root.colContainer
                        borderWidth: subRow.modelData.done ? 0 : 1
                        borderColor: GritStyle.colOutlineStrong
                        onClicked: GritService.toggleSubtask(root.task?.id ?? "", subRow.modelData.id)

                        contentItem: Item {
                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: subRow.modelData.done
                                text: "check"
                                iconSize: 14
                                fill: 1
                                color: ColorUtils.mostReadable(root.colAccent,
                                    [GritStyle.colOnPrimary, GritStyle.colBackground])
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: subRow.modelData.title
                        elide: Text.ElideRight
                        font.pixelSize: GritStyle.textNormal
                        color: subRow.modelData.done ? GritStyle.colSubtext : GritStyle.colOnSurfaceVariant
                        font.strikeout: subRow.modelData.done
                    }

                    ClockIconButton {
                        symbol: "close"
                        size: 24
                        iconSize: 14
                        onClicked: GritService.removeSubtask(root.task?.id ?? "", subRow.modelData.id)
                    }
                }
            }
        }
    }

    StaggeredEntrance {
        index: root.index
        active: !GritStyle.reducedMotion
    }
}
