import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import ".."

/**
 * The sleep timer: pick a length and the mix fades out and pauses when it ends. While it
 * runs, a ring drains and the time left counts down.
 */
ClockPane {
    id: root

    title: Translation.tr("Sleep timer")
    symbol: "bedtime"
    shape: MaterialShape.Shape.Clover4Leaf

    readonly property var lengths: [15, 30, 45, 60, 90, 120]
    readonly property var fades: [10, 30, 60, 120]
    readonly property bool running: SoundscapesService.timerRunning

    function lengthLabel(minutes) {
        if (minutes < 60)
            return `${minutes} min`;
        const rest = minutes % 60;
        return rest === 0 ? `${minutes / 60} h` : `${Math.floor(minutes / 60)} h ${rest}`;
    }
    function fadeLabel(seconds) {
        return seconds >= 60 ? `${seconds / 60} min` : `${seconds} s`;
    }

    // The countdown, when one is running
    Rectangle {
        Layout.fillWidth: true
        visible: root.running
        implicitHeight: countdown.implicitHeight + ClockStyle.gap * 2
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colTertiaryContainer

        RowLayout {
            id: countdown
            anchors {
                fill: parent
                margins: ClockStyle.gap
            }
            spacing: ClockStyle.gapLarge

            Item {
                Layout.preferredWidth: 84
                Layout.preferredHeight: 84
                ClockProgressRing {
                    anchors.fill: parent
                    thickness: 9
                    tickDuration: 1000
                    colIndicator: ClockStyle.colTertiary
                    colTrack: ClockStyle.colSurfaceHigh
                    value: SoundscapesService.timerTotal > 0 ? SoundscapesService.timerLeft / SoundscapesService.timerTotal : 0
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "bedtime"
                    fill: 1
                    iconSize: 28
                    color: ClockStyle.colOnTertiaryContainer
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: SoundscapesService.formatTime(SoundscapesService.timerLeft)
                    font.family: Appearance.font.family.numbers
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.pixelSize: 40
                    color: ClockStyle.colOnTertiaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Then the sounds fade out over %1").arg(root.fadeLabel(SoundscapesService.timerFade))
                    wrapMode: Text.WordWrap
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colOnTertiaryContainer
                    opacity: 0.8
                }
            }
            ClockButton {
                symbol: "close"
                label: Translation.tr("Cancel")
                variant: "tonal"
                onClicked: SoundscapesService.setTimer(0)
            }
        }
    }

    StyledText {
        text: root.running ? Translation.tr("Restart with another length") : Translation.tr("Stop after")
        font.pixelSize: ClockStyle.textSmall
        color: ClockStyle.colSubtext
    }
    Flow {
        Layout.fillWidth: true
        spacing: ClockStyle.gapSmall
        Repeater {
            model: root.lengths
            delegate: ClockChip {
                required property int modelData
                symbol: "schedule"
                label: root.lengthLabel(modelData)
                onClicked: SoundscapesService.setTimer(modelData)
            }
        }
    }

    StyledText {
        Layout.topMargin: ClockStyle.gapTiny
        text: Translation.tr("Fade out over")
        font.pixelSize: ClockStyle.textSmall
        color: ClockStyle.colSubtext
    }
    Flow {
        Layout.fillWidth: true
        spacing: ClockStyle.gapSmall
        Repeater {
            model: root.fades
            delegate: ClockChip {
                required property int modelData
                label: root.fadeLabel(modelData)
                selected: Math.round(SoundscapesService.timerFade) === modelData
                onClicked: SoundscapesService.setTimerFade(modelData)
            }
        }
    }
}
