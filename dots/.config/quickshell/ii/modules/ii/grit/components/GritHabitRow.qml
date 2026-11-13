import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.grit.components

/**
 * One habit today. The whole card opens its editor; the shape on the right is the
 * completion control, sized for a thumb and drawn in the habit's category colour.
 */
Rectangle {
    id: root

    required property var modelData
    required property int index

    property var habit: root.modelData

    property bool showProgress: Number(root.habit?.target ?? 1) > 1
    readonly property bool done: GritService.habitDone(root.habit)
    readonly property real progress: GritService.habitProgress(root.habit)
    readonly property var category: GritService.categoryById(root.habit?.categoryId ?? "")
    readonly property color colAccent: GritStyle.categoryColor(root.category)
    readonly property color colContainer: GritStyle.categoryContainer(root.category)
    readonly property color colOn: GritStyle.categoryOn(root.category)
    readonly property int streak: GritService.currentStreak(root.habit)
    readonly property int value: GritService.habitValue(root.habit?.id ?? "", GritService.todayKey)
    readonly property int target: Math.max(1, Number(root.habit?.target ?? 1))
    readonly property int weekCellSize: root.width >= 560 ? 36 : root.width >= 420 ? 30 : 22

    signal editRequested()
    signal toggleRequested()

    implicitHeight: Math.max(118, content.implicitHeight + GritStyle.gapLarge * 2)
    radius: GritStyle.radiusLarge
    color: root.done
        ? ColorUtils.mix(root.colContainer, GritStyle.colSurface, 0.58)
        : GritStyle.colSurface
    border.width: 1
    border.color: root.done ? "transparent" : ColorUtils.applyAlpha(GritStyle.colOutline, 0.32)

    Behavior on color {
        animation: GritStyle.motionFast.colorAnimation.createObject(this)
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.editRequested()
    }

    RowLayout {
        id: content
        anchors {
            fill: parent
            leftMargin: GritStyle.gapLarge
            rightMargin: GritStyle.gapLarge
        }
        spacing: GritStyle.gapLarge

        MaterialShapeWrappedMaterialSymbol {
            text: String(root.habit?.icon ?? "check_circle")
            iconSize: 23
            padding: 12
            shape: root.done ? "Cookie12Sided" : "Cookie7Sided"
            color: root.done ? root.colAccent : root.colContainer
            colSymbol: root.done
                ? ColorUtils.mostReadable(root.colAccent, [GritStyle.colOnPrimary, GritStyle.colBackground])
                : root.colOn
            rotation: root.done ? 18 : 0

            Behavior on rotation {
                enabled: !GritStyle.reducedMotion
                NumberAnimation {
                    duration: GritStyle.motionDefault.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: GritStyle.motionDefault.bezierCurve
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                spacing: GritStyle.gapSmall

                StyledText {
                    Layout.fillWidth: true
                    text: String(root.habit?.name ?? "")
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: root.done ? GritStyle.colOnSurfaceVariant : GritStyle.colOnSurface
                    font.strikeout: root.done && root.target === 1
                }

                GritFlame {
                    Layout.alignment: Qt.AlignVCenter
                    count: root.streak
                    colFlame: root.colAccent
                    iconSize: 13
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: GritStyle.gapSmall

                StyledText {
                    text: String(root.category?.name ?? "")
                    font.pixelSize: GritStyle.textSmall
                    color: root.colAccent
                }

                StyledText {
                    visible: String(root.habit?.time ?? "").length > 0
                    text: "· " + String(root.habit?.time ?? "")
                    font.pixelSize: GritStyle.textSmall
                    color: GritStyle.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.showProgress
                        ? Translation.tr("%1 of %2 %3").arg(String(root.value)).arg(String(root.target)).arg(String(root.habit?.unit ?? ""))
                        : (root.done ? Translation.tr("Done today") : Translation.tr("Not yet"))
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: GritStyle.textSmall
                    color: root.done ? root.colAccent : GritStyle.colSubtext
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.showProgress
                implicitHeight: 5
                radius: 3
                color: GritStyle.colField

                Rectangle {
                    width: Math.max(parent.height, parent.width * root.progress)
                    height: parent.height
                    radius: parent.radius
                    color: root.colAccent

                    Behavior on width {
                        enabled: !GritStyle.reducedMotion
                        NumberAnimation {
                            duration: GritStyle.motionSpatial.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: GritStyle.motionSpatial.bezierCurve
                        }
                    }
                }
            }

            GritHabitWeek {
                Layout.fillWidth: true
                Layout.topMargin: GritStyle.gapTiny
                habit: root.habit
                colAccent: root.colAccent
                colOnAccent: ColorUtils.mostReadable(root.colAccent,
                    [GritStyle.colOnPrimary, GritStyle.colBackground])
                cellSize: 36
            }
        }

        Item {
            implicitWidth: 48
            implicitHeight: 48

            RippleButton {
                id: check
                anchors.fill: parent
                buttonRadius: root.done ? GritStyle.radiusSmall : width / 2
                buttonRadiusPressed: GritStyle.radiusSmall
                colBackground: root.done ? root.colAccent : "transparent"
                colBackgroundHover: root.done
                    ? ColorUtils.mix(root.colAccent, GritStyle.colOnSurface, 0.9)
                    : root.colContainer
                colRipple: root.colContainer
                borderWidth: root.done ? 0 : 1
                borderColor: root.colAccent
                onClicked: root.toggleRequested()

                contentItem: Item {
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.done ? "check" : "add"
                        iconSize: 22
                        fill: 1
                        color: root.done
                            ? ColorUtils.mostReadable(root.colAccent, [GritStyle.colOnPrimary, GritStyle.colBackground])
                            : root.colAccent
                        animateChange: !GritStyle.reducedMotion
                    }
                }

                StyledToolTip {
                    text: root.done ? Translation.tr("Undo") : Translation.tr("Complete")
                }
            }

            Rectangle {
                id: burst
                anchors.centerIn: check
                width: 44
                height: 44
                radius: 22
                color: "transparent"
                border.width: 2
                border.color: root.colAccent
                opacity: 0
                scale: 0.7
                z: 3
            }
        }
    }

    onDoneChanged: {
        if (!root.done || GritStyle.reducedMotion)
            return;
        completionBurst.restart();
        checkPop.restart();
    }

    ParallelAnimation {
        id: completionBurst

        NumberAnimation {
            target: burst
            property: "opacity"
            from: 0.62
            to: 0
            duration: Appearance.dur(520)
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: burst
            property: "scale"
            from: 0.7
            to: 1.55
            duration: Appearance.dur(520)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
        }
    }

    SequentialAnimation {
        id: checkPop

        NumberAnimation {
            target: check
            property: "scale"
            from: 0.78
            to: 1
            duration: Appearance.dur(360)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
        }
    }

    StaggeredEntrance {
        index: root.index
        active: !GritStyle.reducedMotion
    }
}
