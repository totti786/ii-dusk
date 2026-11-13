import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/*
 * Stopwatch (1x1). The elapsed time fills the top in tall condensed digits
 * with the hundredths in monospace beside them. The start key is the dial
 * itself: a scalloped shape that turns once a minute with the elapsed time,
 * in the accent while it runs. Lap and reset sit beside it.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "timer_stopwatch"

    // 1x1 is the dial and the time; 2x1 adds the laps, newest first, with each split
    supportedSizes: ["1x1", "2x1"]
    defaultSize: "1x1"
    faceWidth: 240

    function clock10(t) {
        const total = Math.floor(t / 100);
        const m = Math.floor(total / 60);
        const s = total % 60;
        return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0") + "." + String(Math.floor(t % 100)).padStart(2, "0");
    }

    readonly property real padding: 16
    readonly property real dialSize: 84
    readonly property real digitSize: 92

    readonly property bool running: TimerService.stopwatchRunning
    readonly property var laps: TimerService.stopwatchLaps ?? []
    // The service counts in 10 ms; the face only needs a tenth of that, and
    // nothing at all while it is not running.
    property int shownTime: TimerService.stopwatchTime
    Timer {
        interval: 100
        repeat: true
        running: root.running && root.live
        onTriggered: root.shownTime = TimerService.stopwatchTime
    }
    Connections {
        target: TimerService
        enabled: !root.running
        function onStopwatchTimeChanged() {
            root.shownTime = TimerService.stopwatchTime;
        }
    }

    readonly property int totalSeconds: Math.floor(root.shownTime / 100)
    readonly property string mainText: {
        const hours = Math.floor(root.totalSeconds / 3600);
        const minutes = Math.floor((root.totalSeconds % 3600) / 60);
        const seconds = root.totalSeconds % 60;
        const tail = String(minutes).padStart(2, "0") + ":" + String(seconds).padStart(2, "0");
        return hours > 0 ? hours + ":" + tail : tail;
    }
    readonly property string hundredths: String(Math.floor(root.shownTime % 100)).padStart(2, "0")
    readonly property bool started: root.shownTime > 0

    // ── Caption + laps ──
    StyledText {
        x: root.padding + 2
        y: root.padding
        text: Translation.tr("Stopwatch").toUpperCase()
        color: root.cardScheme.subtextColorOnBg
        font.family: Appearance.font.family.monospace
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.letterSpacing: 1.5
    }

    Rectangle {
        visible: root.laps.length > 0
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        y: root.padding - 4
        width: lapText.implicitWidth + 18
        height: 24
        radius: root.pill(height)
        color: root.cardScheme.pillBgColor

        StyledText {
            id: lapText
            anchors.centerIn: parent
            text: Translation.tr("Lap %1").arg(root.laps.length)
            color: root.cardScheme.textColorOnBg
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    // ── Time ──
    Row {
        x: root.padding - 2
        y: 34
        spacing: 2

        Text {
            id: digits
            text: root.mainText
            color: root.started ? root.cardScheme.textColorOnBg : root.cardScheme.subtextColorOnBg
            font.family: Appearance.font.family.main
            // Hours push the line wider: give them room by shrinking, not clipping.
            font.pixelSize: root.totalSeconds >= 3600 ? Math.round(root.digitSize * 0.72) : root.digitSize
            font.variableAxes: ({ "wght": root.running ? 760 : 560, "wdth": 40, "ROND": 100, "opsz": 144 })
            renderType: Text.QtRendering
        }

        StyledText {
            anchors.baseline: digits.baseline
            text: root.hundredths
            color: root.cardScheme.accentColor
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.huge
        }
    }

    // ── Dial key ──
    Item {
        id: dial
        x: root.padding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        width: root.dialSize
        height: root.dialSize

        MaterialShape {
            anchors.fill: parent
            shape: dialHover.hovered && root.actionsEnabled ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie9Sided
            color: root.running ? root.cardScheme.accentColor
                : root.started ? root.cardScheme.pillFillColor : root.cardScheme.pillBgColor
            // One turn a minute with the elapsed time.
            rotation: (root.shownTime % 6000) / 6000 * 360

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.running ? "pause" : "play_arrow"
            iconSize: 36
            fill: 1
            color: root.running ? root.cardScheme.onAccentColor
                : root.started ? root.cardScheme.textColorOnPillFill : root.cardScheme.textColorOnBg
        }

        HoverHandler {
            id: dialHover
            enabled: root.actionsEnabled
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: root.actionsEnabled
            onTapped: TimerService.toggleStopwatch()
        }
    }

    // ── Lap / reset ──
    Column {
        anchors.left: dial.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        anchors.verticalCenter: dial.verticalCenter
        spacing: 6

        WidgetButton {
            width: parent.width
            height: 39
            enabled: root.running
            symbol: "flag"
            symbolSize: 18
            label: Translation.tr("Lap")
            colFill: root.cardScheme.pillBgColor
            colContent: root.cardScheme.textColorOnBg
            onClicked: TimerService.stopwatchRecordLap()
        }

        WidgetButton {
            width: parent.width
            height: 39
            enabled: root.started && !root.running
            symbol: "restart_alt"
            symbolSize: 18
            label: Translation.tr("Reset")
            colFill: root.cardScheme.pillBgColor
            colContent: root.cardScheme.textColorOnBg
            onClicked: TimerService.stopwatchReset()
        }
    }

    // ── 2x1: the laps, newest first, each with its split and the running total ──
    Item {
        parent: root.extraItem
        anchors.fill: parent
        visible: root.hasExtras

        StyledText {
            x: 6
            y: root.padding
            text: Translation.tr("Laps").toUpperCase()
            color: root.cardScheme.subtextColorOnBg
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.variableAxes: ({ "wght": 650, "wdth": 100 })
            font.letterSpacing: 1
        }

        StyledText {
            visible: root.laps.length === 0
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 26
            wrapMode: Text.Wrap
            text: root.started ? Translation.tr("Tap lap to mark a split") : Translation.tr("Start the stopwatch, then tap lap to mark splits")
            color: root.cardScheme.subtextColorOnBg
            font.pixelSize: Appearance.font.pixelSize.small
        }

        Column {
            x: 6
            y: root.padding + 26
            width: parent.width - 26
            spacing: 6
            visible: root.laps.length > 0

            Repeater {
                // Newest first, five at most; each lap's number is its place in the whole run
                model: {
                    const all = Array.from(root.laps);
                    return all.map((t, i) => ({ "n": i + 1, "total": t, "split": t - (i > 0 ? all[i - 1] : 0) })).slice(-5).reverse();
                }
                delegate: Row {
                    id: lapLine
                    required property var modelData
                    width: parent.width
                    spacing: 8
                    StyledText {
                        width: 24
                        text: String(lapLine.modelData.n)
                        color: root.cardScheme.subtextColorOnBg
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    Text {
                        width: parent.width - 32 - totalText.implicitWidth
                        text: root.clock10(lapLine.modelData.split)
                        color: root.cardScheme.textColorOnBg
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.variableAxes: ({ "wght": 600 })
                    }
                    Text {
                        id: totalText
                        text: root.clock10(lapLine.modelData.total)
                        color: root.cardScheme.subtextColorOnBg
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }
        }
    }
}
