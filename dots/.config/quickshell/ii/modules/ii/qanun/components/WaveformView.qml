import QtQuick
import qs.services
import qs.modules.common
import qs.modules.ii.qanun

/**
 * A compact waveform thumbnail. Used in the recordings list (before opening a
 * take) and in the player, where clicking seeks.
 */
Item {
    id: root

    property var peaks: []
    property real progress: 0
    property bool interactive: false
    property bool placeholder: false
    property color waveColor: QanunStyle.colWaveform
    property color playedColor: QanunStyle.colPrimary
    property color idleColor: Qt.alpha(QanunStyle.colOnSurface, 0.30)
    property color baselineColor: Qt.alpha(QanunStyle.colOnSurface, 0.08)
    property real barWidth: 2.4
    property real barGap: 1.6

    signal seekRequested(real fraction)

    implicitHeight: 48
    clip: true

    readonly property var bars: Array.from(root.peaks ?? [])

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        renderTarget: Canvas.FramebufferObject

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            const mid = height / 2;
            ctx.strokeStyle = root.baselineColor;
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(0, Math.round(mid) + 0.5);
            ctx.lineTo(width, Math.round(mid) + 0.5);
            ctx.stroke();

            const bars = root.bars;
            if (!bars || bars.length === 0) {
                ctx.strokeStyle = Qt.alpha(QanunStyle.colOnSurface, 0.18);
                ctx.lineWidth = 1.6;
                ctx.lineCap = "round";
                ctx.beginPath();
                ctx.moveTo(width * 0.1, mid);
                ctx.lineTo(width * 0.9, mid);
                ctx.stroke();
                return;
            }
            const step = width / bars.length;
            const playHead = Math.max(0, Math.min(1, Number(root.progress) || 0)) * width;
            for (let i = 0; i < bars.length; ++i) {
                const x = i * step + step / 2;
                const amplitude = Math.max(0.04, Math.min(1, Number(bars[i]) || 0));
                const h = Math.max(2, amplitude * (height - 8));
                ctx.beginPath();
                ctx.lineCap = "round";
                ctx.lineWidth = Math.max(1.2, Math.min(step * 0.62, root.barWidth));
                ctx.strokeStyle = x <= playHead ? root.playedColor : root.idleColor;
                ctx.moveTo(x, mid - h / 2);
                ctx.lineTo(x, mid + h / 2);
                ctx.stroke();
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        hoverEnabled: root.interactive
        onPressed: mouse => root.seekRequested(Math.max(0, Math.min(1, mouse.x / width)))
        onPositionChanged: mouse => {
            if (pressed)
                root.seekRequested(Math.max(0, Math.min(1, mouse.x / width)));
        }
    }

    onPeaksChanged: canvas.requestPaint()
    onProgressChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
}
