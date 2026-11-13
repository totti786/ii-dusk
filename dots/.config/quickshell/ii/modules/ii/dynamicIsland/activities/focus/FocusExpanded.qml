pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The Grit focus session: the time left, how far through it is, and the three things you
 * want mid-session: pause or resume, skip to the next phase, open Focus.
 *
 * Self-contained on purpose: the bubble loads cards by URL, and such a file gets none of its
 * directory's types. It reads GritService, which the island already follows.
 */
Item {
    id: root

    readonly property bool running: GritService.timerRunning
    readonly property bool onBreak: GritService.timerPhase !== "focus"
    readonly property int secondsLeft: GritService.timerSecondsLeft
    readonly property var heroItems: [marker]

    readonly property real margin: 14
    readonly property real preferredExpandedWidth: 300
    readonly property real preferredExpandedHeight: column.implicitHeight + 2 * root.margin

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.margin
        }
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            MaterialShapeWrappedMaterialSymbol {
                id: marker
                shape: root.onBreak ? "SoftBurst" : String(GritService.activeTag?.shape ?? "Cookie7Sided")
                implicitSize: 44
                iconSize: 22
                padding: 5
                text: !root.running ? "pause" : (root.onBreak ? "coffee" : "psychiatry")
                color: root.onBreak ? Appearance.colors.colTertiaryContainer : Appearance.colors.colPrimary
                colSymbol: root.onBreak ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: GritService.timerPhaseLabel + (root.running ? "" : "  ·  " + Translation.tr("Paused"))
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    text: (GritService.activeTag?.name ?? "") + "  ·  " + (GritService.timerCycle + 1) + "/" + GritService.timerCycles
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            StyledText {
                text: String(Math.floor(root.secondsLeft / 60)).padStart(2, "0") + ":" + String(root.secondsLeft % 60).padStart(2, "0")
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
                opacity: root.running ? 1 : 0.6
                color: Appearance.colors.colOnSurface
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 6
            radius: 3
            color: Appearance.colors.colSurfaceContainerHighest
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, GritService.timerProgress))
                height: parent.height
                radius: 3
                color: root.onBreak ? Appearance.colors.colTertiary : Appearance.colors.colPrimary
                Behavior on width {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ActionButton {
                Layout.fillWidth: true
                filled: true
                label: root.running ? Translation.tr("Pause") : Translation.tr("Resume")
                onClicked: GritService.toggleTimer()
            }
            ActionButton {
                Layout.fillWidth: true
                label: Translation.tr("Skip")
                onClicked: GritService.skipTimer()
            }
            ActionButton {
                Layout.fillWidth: true
                label: Translation.tr("Open")
                onClicked: GlobalStates.openGritApp("focus")
            }
        }
    }

    component ActionButton: RippleButton {
        id: action
        property string label
        property bool filled: false

        implicitHeight: 38
        buttonRadius: Appearance.rounding.full
        colBackground: action.filled ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHigh
        colBackgroundHover: action.filled ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighest
        colRipple: action.filled ? Appearance.colors.colPrimaryActive : Appearance.colors.colSurfaceContainerHighestActive

        contentItem: Item {
            StyledText {
                anchors.centerIn: parent
                text: action.label
                font.weight: Font.DemiBold
                color: action.filled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
            }
        }
    }
}
