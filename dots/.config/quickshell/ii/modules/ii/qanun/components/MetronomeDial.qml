import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.qanun

/**
 * The metronome's circular stage: one ring per click track, with the current
 * beat drawn as a widening arc and the subdivision dots giving the bar its
 * shape. The centre is the tempo readout; drag vertically or use the wheel to
 * change it, like turning the dial on a physical metronome.
 */
Item {
    id: root

    property int bpm: 96
    property int numerator: 4
    property int denominator: 4
    property bool playing: false
    property int beatIndex: 0
    property real phase: 0
    property var divisions: [1, 2]
    property var accents: [1, 0, 0, 0]
    property var trackColors: [QanunStyle.colTrackPulse, QanunStyle.colTrackSubdivision]
    property int flashSerial: 0
    property bool counting: false

    signal tempoDragged(int bpm)

    implicitWidth: 380
    implicitHeight: 380

    readonly property real radius: Math.min(width, height) / 2 - 24
    readonly property int currentBeat: Math.max(0, Math.min(root.numerator - 1, root.beatIndex))

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        renderTarget: Canvas.FramebufferObject

        function angle(unit): real {
            return -Math.PI / 2 + unit * Math.PI * 2;
        }

        function drawRing(trackIndex, ringRadius) {
            const ctx = getContext("2d");
            if (trackIndex >= root.divisions.length)
                return;
            const division = Math.max(1, Math.min(8, Number(root.divisions[trackIndex]) || 1));
            const total = Math.max(1, root.numerator * division);
            const color = root.trackColors[trackIndex] ?? QanunStyle.colTrackPulse;
            const active = trackIndex === 0
                ? (root.currentBeat + root.phase) / Math.max(1, root.numerator)
                : (root.currentBeat + root.phase) / Math.max(1, root.numerator);

            // Idle ring.
            ctx.strokeStyle = Qt.alpha(color, 0.18);
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.arc(width / 2, height / 2, ringRadius, 0, Math.PI * 2);
            ctx.stroke();

            // Active progress.
            if (root.playing) {
                ctx.strokeStyle = color;
                ctx.lineWidth = 2.4;
                ctx.lineCap = "round";
                ctx.beginPath();
                ctx.arc(width / 2, height / 2, ringRadius, -Math.PI / 2, -Math.PI / 2 + active * Math.PI * 2);
                ctx.stroke();
            }

            // Subdivision dots.
            for (let i = 0; i < total; ++i) {
                const a = angle(i / total);
                const x = width / 2 + Math.cos(a) * ringRadius;
                const y = height / 2 + Math.sin(a) * ringRadius;
                const isBeat = i % division === 0;
                const isCurrent = Math.floor(i / division) === root.currentBeat
                    && trackIndex === 0
                    && Math.round(root.phase * division) === i % division;
                const isAccent = isBeat && Boolean(root.accents[Math.floor(i / division)] ?? 0);
                const dotRadius = isCurrent ? 5.4 : isBeat ? (isAccent ? 4.0 : 3.1) : 1.8;
                ctx.beginPath();
                ctx.arc(x, y, dotRadius, 0, Math.PI * 2);
                ctx.fillStyle = isCurrent ? color : isBeat
                    ? Qt.alpha(color, isAccent ? 0.95 : 0.62)
                    : Qt.alpha(color, 0.25);
                ctx.fill();
                if (isCurrent) {
                    ctx.beginPath();
                    ctx.arc(x, y, 10, 0, Math.PI * 2);
                    ctx.strokeStyle = Qt.alpha(color, 0.35);
                    ctx.lineWidth = 2;
                    ctx.stroke();
                }
            }
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            const centre = width / 2;
            // A subtle plate under the rings.
            ctx.beginPath();
            ctx.arc(centre, height / 2, root.radius + 12, 0, Math.PI * 2);
            ctx.fillStyle = Qt.alpha(QanunStyle.colPane, 0.5);
            ctx.fill();

            const outer = root.radius;
            drawRing(0, outer);
            if (root.divisions.length > 1)
                drawRing(1, outer - 22);

            // Beat marker on top, 12 o'clock.
            ctx.beginPath();
            ctx.arc(centre, height / 2 - root.radius, 3.2, 0, Math.PI * 2);
            ctx.fillStyle = Qt.alpha(QanunStyle.colOnSurface, 0.5);
            ctx.fill();
        }
    }

    // A pulse behind the centre when a beat lands.
    Rectangle {
        id: beatPulse
        anchors.centerIn: parent
        width: root.radius * 0.72
        height: width
        radius: width / 2
        color: Qt.alpha(root.trackColors[0] ?? QanunStyle.colPrimary, 0.12)
        opacity: 0
        scale: 0.86

        ParallelAnimation {
            id: pulseAnimation
            NumberAnimation { target: beatPulse; property: "opacity"; from: 0.8; to: 0; duration: Appearance.dur(260); easing.type: Easing.OutCubic }
            NumberAnimation { target: beatPulse; property: "scale"; from: 0.86; to: 1.12; duration: Appearance.dur(260); easing.type: Easing.OutCubic }
        }
    }

    Connections {
        target: root
        function onFlashSerialChanged() {
            if (root.playing && !Appearance.reducedMotion) {
                pulseAnimation.restart();
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 0

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: String(root.bpm)
            font.family: Appearance.font.family.numbers
            font.variableAxes: ({ "wght": 700, "wdth": 32, "ROND": 100 })
            font.pixelSize: Math.min(96, root.radius * 0.8)
            color: QanunStyle.colOnSurface
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: "BPM"
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            font.letterSpacing: 2.2
            color: QanunStyle.colSubtext
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 6
            text: QanunData.tempoMarking(root.bpm)
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            font.variableAxes: ({ "wght": 600, "wdth": 100, "ROND": 100 })
            color: QanunStyle.colTertiary
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 4
            text: root.numerator + " / " + root.denominator
            font.family: Appearance.font.family.numbers
            font.pixelSize: Appearance.font.pixelSize.small
            color: QanunStyle.colSubtext
        }
    }

    // Drag vertically to set the tempo.
    MouseArea {
        id: dialDrag
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: pressed ? Qt.SizeVerCursor : Qt.UpArrowCursor
        property int startBpm: 96
        property real startY: 0
        property bool moved: false

        onPressed: mouse => {
            startBpm = root.bpm;
            startY = mouse.y;
            moved = false;
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            const delta = Math.round((startY - mouse.y) / 3);
            if (Math.abs(delta) > 1) {
                moved = true;
                root.tempoDragged(Math.max(20, Math.min(320, startBpm + delta)));
            }
        }
        onWheel: wheel => {
            const delta = wheel.angleDelta.y > 0 ? 1 : -1;
            root.tempoDragged(Math.max(20, Math.min(320, root.bpm + delta * (wheel.modifiers & Qt.ShiftModifier ? 5 : 1))));
        }
    }

    Timer {
        interval: 33
        repeat: true
        running: root.playing
        onTriggered: canvas.requestPaint()
    }

    onBpmChanged: canvas.requestPaint()
    onNumeratorChanged: canvas.requestPaint()
    onDivisionsChanged: canvas.requestPaint()
    onAccentsChanged: canvas.requestPaint()
    onPhaseChanged: if (!root.playing) canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
}
