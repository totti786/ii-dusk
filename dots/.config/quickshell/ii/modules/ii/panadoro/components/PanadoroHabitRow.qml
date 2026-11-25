import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.panadoro.components

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
    readonly property bool done: PanadoroService.habitDone(root.habit)
    readonly property real progress: PanadoroService.habitProgress(root.habit)
    readonly property var category: PanadoroService.categoryById(root.habit?.categoryId ?? "")
    readonly property color colAccent: PanadoroStyle.categoryColor(root.category)
    readonly property color colContainer: PanadoroStyle.categoryContainer(root.category)
    readonly property color colOn: PanadoroStyle.categoryOn(root.category)
    readonly property int streak: PanadoroService.currentStreak(root.habit)
    readonly property int value: PanadoroService.habitValue(root.habit?.id ?? "", PanadoroService.todayKey)
    readonly property int target: Math.max(1, Number(root.habit?.target ?? 1))
    readonly property int weekCellSize: root.width >= 560 ? 36 : root.width >= 420 ? 30 : 22

    signal editRequested()
    signal toggleRequested()

    implicitHeight: Math.max(118, content.implicitHeight + PanadoroStyle.gapLarge * 2)
    radius: PanadoroStyle.radiusLarge
    color: root.done
        ? ColorUtils.mix(root.colContainer, PanadoroStyle.colSurface, 0.58)
        : PanadoroStyle.colSurface

    Behavior on color {
        animation: PanadoroStyle.motionFast.colorAnimation.createObject(this)
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
            leftMargin: PanadoroStyle.gapLarge
            rightMargin: PanadoroStyle.gapLarge
        }
        spacing: PanadoroStyle.gapLarge

        MaterialShapeWrappedMaterialSymbol {
            text: String(root.habit?.icon ?? "check_circle")
            iconSize: 23
            padding: 12
            shape: root.done ? "Cookie12Sided" : "Cookie7Sided"
            color: root.done ? root.colAccent : root.colContainer
            colSymbol: root.done
                ? ColorUtils.mostReadable(root.colAccent, [PanadoroStyle.colOnPrimary, PanadoroStyle.colBackground])
                : root.colOn
            rotation: root.done ? 18 : 0

            Behavior on rotation {
                enabled: !PanadoroStyle.reducedMotion
                NumberAnimation {
                    duration: PanadoroStyle.motionDefault.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: PanadoroStyle.motionDefault.bezierCurve
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                spacing: PanadoroStyle.gapSmall

                StyledText {
                    Layout.fillWidth: true
                    text: String(root.habit?.name ?? "")
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: root.done ? PanadoroStyle.colOnSurfaceVariant : PanadoroStyle.colOnSurface
                    font.strikeout: root.done && root.target === 1
                }

                PanadoroFlame {
                    Layout.alignment: Qt.AlignVCenter
                    count: root.streak
                    colFlame: root.colAccent
                    iconSize: 13
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: PanadoroStyle.gapSmall

                StyledText {
                    text: String(root.category?.name ?? "")
                    font.pixelSize: PanadoroStyle.textSmall
                    color: root.colAccent
                }

                StyledText {
                    visible: String(root.habit?.time ?? "").length > 0
                    text: "· " + String(root.habit?.time ?? "")
                    font.pixelSize: PanadoroStyle.textSmall
                    color: PanadoroStyle.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.showProgress
                        ? Translation.tr("%1 of %2 %3").arg(String(root.value)).arg(String(root.target)).arg(String(root.habit?.unit ?? ""))
                        : (root.done ? Translation.tr("Done today") : Translation.tr("Not yet"))
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: PanadoroStyle.textSmall
                    color: root.done ? root.colAccent : PanadoroStyle.colSubtext
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.showProgress
                implicitHeight: 5
                radius: 3
                color: PanadoroStyle.colField

                Rectangle {
                    width: Math.max(parent.height, parent.width * root.progress)
                    height: parent.height
                    radius: parent.radius
                    color: root.colAccent

                    Behavior on width {
                        enabled: !PanadoroStyle.reducedMotion
                        NumberAnimation {
                            duration: PanadoroStyle.motionSpatial.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: PanadoroStyle.motionSpatial.bezierCurve
                        }
                    }
                }
            }

            PanadoroHabitWeek {
                Layout.fillWidth: true
                Layout.topMargin: PanadoroStyle.gapTiny
                habit: root.habit
                colAccent: root.colAccent
                colOnAccent: ColorUtils.mostReadable(root.colAccent,
                    [PanadoroStyle.colOnPrimary, PanadoroStyle.colBackground])
                cellSize: 36
            }
        }

        Item {
            implicitWidth: 48
            implicitHeight: 48

            RippleButton {
                id: check
                anchors.fill: parent
                buttonRadius: root.done ? PanadoroStyle.radiusSmall : width / 2
                buttonRadiusPressed: PanadoroStyle.radiusSmall
                colBackground: root.done ? root.colAccent : "transparent"
                colBackgroundHover: root.done
                    ? ColorUtils.mix(root.colAccent, PanadoroStyle.colOnSurface, 0.9)
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
                            ? ColorUtils.mostReadable(root.colAccent, [PanadoroStyle.colOnPrimary, PanadoroStyle.colBackground])
                            : root.colAccent
                        animateChange: !PanadoroStyle.reducedMotion
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
        if (!root.done || PanadoroStyle.reducedMotion)
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
        active: !PanadoroStyle.reducedMotion
    }
}
