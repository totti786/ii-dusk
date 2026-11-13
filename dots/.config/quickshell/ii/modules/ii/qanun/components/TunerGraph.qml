import QtQuick
import qs.services
import qs.modules.common
import qs.modules.ii.qanun

/**
 * The tuner's pitch-history graph: cents across the last few seconds, with the
 * in-tune band and the ±25/±50 guides. A fresh, still reading draws a flat line
 * on the centre guide instead of an empty rectangle.
 */
Item {
    id: root

    property var history: []
    property int maxSeconds: 14
    property real inTuneCents: 5
    property int maxPoints: 220
    property color lineColor: QanunStyle.colGraph
    property color fillColor: QanunStyle.colGraphFill
    property color gridColor: Qt.alpha(QanunStyle.colOnSurface, 0.10)
    property color bandColor: Qt.alpha(QanunStyle.colInTune, 0.10)
    property color textColor: QanunStyle.colSubtext
    property bool active: true
    property real frozenAt: 0

    implicitHeight: 190
    clip: true

    readonly property var points: Array.from(root.history ?? []).slice(-root.maxPoints)

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        renderTarget: Canvas.FramebufferObject

        function yFor(cents): real {
            return height / 2 - (Math.max(-50, Math.min(50, Number(cents) || 0)) / 50) * (height / 2 - 14);
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            const left = 32;
            const right = width - 12;
            const top = 14;
            const bottom = height - 22;
            if (right <= left || bottom <= top)
                return;

            // In-tune threshold: two quiet lines instead of a slab. A filled
            // band reads like a shadow across the trace on a dark surface.
            ctx.strokeStyle = Qt.alpha(QanunStyle.colInTune, 0.32);
            ctx.lineWidth = 1;
            for (const threshold of [-root.inTuneCents, root.inTuneCents]) {
                const y = Math.round(yFor(threshold)) + 0.5;
                ctx.beginPath();
                ctx.moveTo(left, y);
                ctx.lineTo(right, y);
                ctx.stroke();
            }

            // Guides.
            ctx.strokeStyle = root.gridColor;
            ctx.lineWidth = 1;
            for (let value = -50; value <= 50; value += 25) {
                const y = Math.round(yFor(value)) + 0.5;
                ctx.beginPath();
                ctx.moveTo(left, y);
                ctx.lineTo(right, y);
                ctx.stroke();
                ctx.fillStyle = root.textColor;
                ctx.font = "10px 'Noto Sans'";
                ctx.textAlign = "right";
                ctx.textBaseline = "middle";
                ctx.fillText((value > 0 ? "+" : "") + String(value), left - 7, y);
            }

            // Centre guide is stronger.
            ctx.strokeStyle = Qt.alpha(QanunStyle.colInTune, 0.5);
            ctx.lineWidth = 1.2;
            const centre = Math.round(height / 2) + 0.5;
            ctx.beginPath();
            ctx.moveTo(left, centre);
            ctx.lineTo(right, centre);
            ctx.stroke();

            // Vertical time grid, one line per second.
            ctx.strokeStyle = root.gridColor;
            ctx.lineWidth = 0.8;
            for (let second = 1; second <= root.maxSeconds; ++second) {
                const x = left + (right - left) * (1 - second / root.maxSeconds);
                ctx.beginPath();
                ctx.moveTo(x, top);
                ctx.lineTo(x, bottom);
                ctx.stroke();
            }

            if (root.points.length < 2) {
                ctx.fillStyle = root.textColor;
                ctx.font = "12px 'Noto Sans'";
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";
                ctx.fillText(Translation.tr("Play a note — the pitch trace appears here"), (left + right) / 2, height / 2 - 28);
                return;
            }

            // Draw the most recent points against wall-clock age rather than
            // point index, so a quiet gap becomes a real gap in the trace.
            const now = root.active ? Date.now() : (root.frozenAt > 0 ? root.frozenAt : Date.now());
            const span = Math.max(1, root.maxSeconds * 1000);
            let started = false;
            const pathPoints = [];
            const validPoints = [];
            for (const point of root.points) {
                if (!point || point.valid === false)
                    continue;
                validPoints.push(point);
            }
            for (let i = 0; i < validPoints.length; ++i) {
                const point = validPoints[i];
                if (i > 0 && i < validPoints.length - 1) {
                    const previous = validPoints[i - 1];
                    const next = validPoints[i + 1];
                    // A single-frame spike is an attack transient, not a note.
                    if (Math.abs(Number(point.cents) - Number(previous.cents)) > 32
                            && Math.abs(Number(point.cents) - Number(next.cents)) > 32)
                        continue;
                }
                const age = Math.max(0, Math.min(span, now - Number(point.t ?? now)));
                const x = right - (age / span) * (right - left);
                const y = yFor(point.cents);
                pathPoints.push({ x: x, y: y, t: Number(point.t ?? now) });
            }
            if (pathPoints.length === 0)
                return;
            ctx.beginPath();
            let previous = null;
            for (let i = 0; i < pathPoints.length; ++i) {
                const current = pathPoints[i];
                // Do not connect across a silence: a new phrase should start a
                // new trace instead of a long diagonal across the graph.
                if (!previous || current.t - previous.t > 320) {
                    ctx.moveTo(current.x, current.y);
                } else {
                    const midX = (previous.x + current.x) / 2;
                    const midY = (previous.y + current.y) / 2;
                    ctx.quadraticCurveTo(previous.x, previous.y, midX, midY);
                }
                previous = current;
            }
            const lastPoint = pathPoints[pathPoints.length - 1];
            ctx.lineTo(lastPoint.x, lastPoint.y);
            started = true;
            ctx.strokeStyle = root.lineColor;
            ctx.lineWidth = 2.2;
            ctx.lineJoin = "round";
            ctx.stroke();

            // A soft fill underneath the trace is intentionally omitted: the
            // tuner should read as a line, not a translucent slab.
            // Current point.
            const last = root.points[root.points.length - 1];
            if (last && last.valid !== false) {
                const age = Math.max(0, Math.min(span, now - Number(last.t ?? now)));
                const x = right - (age / span) * (right - left);
                const y = yFor(last.cents);
                ctx.beginPath();
                ctx.arc(x, y, 4.5, 0, Math.PI * 2);
                ctx.fillStyle = QanunStyle.tuningColor(last.cents, root.inTuneCents);
                ctx.fill();
                ctx.beginPath();
                ctx.arc(x, y, 8, 0, Math.PI * 2);
                ctx.strokeStyle = Qt.alpha(QanunStyle.tuningColor(last.cents, root.inTuneCents), 0.4);
                ctx.lineWidth = 3;
                ctx.stroke();
            }
        }
    }

    onHistoryChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onInTuneCentsChanged: canvas.requestPaint()
    onActiveChanged: {
        if (!root.active)
            root.frozenAt = Date.now();
        canvas.requestPaint();
    }

    // Repaint while listening; stopped means the trace freezes where it is.
    Timer {
        interval: 120
        repeat: true
        running: root.active
        onTriggered: canvas.requestPaint()
    }
}
