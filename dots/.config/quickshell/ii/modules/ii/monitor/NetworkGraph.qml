import QtQuick

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "MonitorFormat.js" as Fmt

/**
 * Traffic over the last couple of minutes: download rises above the middle line, upload hangs
 * below it, both on one scale. The scale follows typical traffic (a single burst does not flatten
 * everything else; a line that goes past the edge is clipped there), the labels sit in their own
 * margin, and hovering reads both values at that moment. Like the latency graph, the grid and
 * labels are painted once and the lines glide a step to the left with each new sample.
 */
Item {
    id: root

    property var down: []
    property var up: []
    property int length: 120
    property real floorMax: 10 * 1024
    property real interval: 1
    property color downColor: ClockStyle.colPrimary
    property color upColor: ClockStyle.colTertiary

    readonly property real leftPad: Math.ceil(labelMetrics.advanceWidth) + 12
    readonly property real bottomPad: 16
    readonly property color gridColor: Qt.rgba(ClockStyle.colSubtext.r, ClockStyle.colSubtext.g, ClockStyle.colSubtext.b, 0.16)

    readonly property real scaleMax: {
        const all = [];
        for (const v of root.down)
            all.push(v);
        for (const v of root.up)
            all.push(v);
        all.sort((a, b) => a - b);
        const typical = all.length > 0 ? all[Math.floor(all.length * 0.9)] : 0;
        const want = Math.max(root.floorMax, typical) * 1.3;
        // The next round number: 1, 2, 5 or 10 times a power of ten
        const base = Math.pow(10, Math.floor(Math.log10(want)));
        for (const m of [1, 2, 5, 10])
            if (m * base >= want)
                return m * base;
        return 10 * base;
    }

    property int hoverIndex: -1

    readonly property real plotX: root.leftPad
    readonly property real plotY: 4
    readonly property real plotW: Math.max(1, root.width - root.leftPad - 4)
    readonly property real plotH: Math.max(1, root.height - root.bottomPad - 4)
    readonly property real step: root.plotW / (root.length - 1)

    function rgba(c: color, a: real): string {
        return `rgba(${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)},${a})`;
    }

    TextMetrics {
        id: labelMetrics
        font.family: "sans-serif"
        font.pixelSize: 11
        text: Fmt.rate(root.scaleMax)
    }

    onDownChanged: root.seriesUpdated()
    onUpChanged: root.seriesUpdated()
    onScaleMaxChanged: { back.requestPaint(); lines.requestPaint(); }
    onLeftPadChanged: { back.requestPaint(); lines.requestPaint(); }
    onWidthChanged: back.requestPaint()
    onHeightChanged: back.requestPaint()
    onDownColorChanged: lines.requestPaint()
    onUpColorChanged: lines.requestPaint()

    function seriesUpdated(): void {
        lines.requestPaint();
        if (!ClockStyle.reducedMotion && root.plotW > 10) {
            glide.stop();
            lines.x = 0;
            glide.from = 0;
            glide.to = -root.step;
            glide.duration = root.interval * 1000;
            glide.start();
        } else {
            lines.x = -root.step;
        }
    }

    // ── grid and labels ──
    Canvas {
        id: back
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            const x0 = root.plotX, x1 = x0 + root.plotW;
            const y0 = root.plotY, y1 = y0 + root.plotH;
            const w = root.plotW, h = root.plotH;
            if (w < 10 || h < 10)
                return;
            const mid = y0 + h / 2;

            // The two halves get a faint tint of their own colour
            ctx.fillStyle = root.rgba(root.downColor, 0.05);
            ctx.fillRect(x0, y0, w, h / 2);
            ctx.fillStyle = root.rgba(root.upColor, 0.05);
            ctx.fillRect(x0, mid, w, h / 2);

            // Time grid every 30 s
            ctx.strokeStyle = root.gridColor.toString();
            ctx.lineWidth = 1;
            const per = 30 / root.interval;
            for (let i = root.length - 1 - per; i > 0; i -= per) {
                const x = Math.round(x0 + i * w / (root.length - 1)) + 0.5;
                ctx.beginPath();
                ctx.moveTo(x, y0);
                ctx.lineTo(x, y1);
                ctx.stroke();
            }

            // Horizontal lines at the half and full scale in each direction
            ctx.font = "11px sans-serif";
            ctx.textAlign = "right";
            ctx.textBaseline = "middle";
            const marks = [[-1, 1], [-0.5, 0.5], [0, 0], [0.5, -0.5], [1, -1]];
            for (const [f, dir] of marks) {
                const y = Math.round(mid + f * h / 2) + 0.5;
                ctx.strokeStyle = f === 0 ? root.rgba(ClockStyle.colSubtext, 0.45) : root.gridColor.toString();
                ctx.beginPath();
                ctx.moveTo(x0, y);
                ctx.lineTo(x1, y);
                ctx.stroke();
                // The half-way labels only when there is room for them
                if (Math.abs(f) === 0.5 && h < 150)
                    continue;
                ctx.fillStyle = ClockStyle.colSubtext.toString();
                const label = f === 0 ? "0" : Fmt.rate(root.scaleMax * Math.abs(f));
                ctx.fillText(label, x0 - 6, Math.min(y1 - 2, Math.max(y0 + 5, y)));
            }

            ctx.textBaseline = "alphabetic";
            ctx.fillStyle = ClockStyle.colSubtext.toString();
            const span = (root.length - 1) * root.interval;
            ctx.textAlign = "left";
            ctx.fillText(`-${Math.round(span)}s`, x0, height - 3);
            ctx.textAlign = "center";
            ctx.fillText(`-${Math.round(span / 2)}s`, x0 + w / 2, height - 3);
            ctx.textAlign = "right";
            ctx.fillText(Translation.tr("now"), x1, height - 3);
        }
    }

    // ── the traffic, in a clipped window so it can glide ──
    Item {
        x: root.plotX
        y: root.plotY
        width: root.plotW
        height: root.plotH
        clip: true

        Canvas {
            id: lines
            x: -root.step
            width: root.plotW + root.step
            height: root.plotH
            onWidthChanged: {
                requestPaint();
                if (!glide.running)
                    lines.x = -root.step;
            }
            onHeightChanged: requestPaint()

            NumberAnimation on x {
                id: glide
                running: false
                easing.type: Easing.Linear
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                const h = root.plotH, n = root.length, step = root.step;
                const mid = h / 2;
                ctx.lineJoin = "round";
                ctx.lineCap = "round";

                const layer = (data, color, dir) => {
                    if (data.length < 2)
                        return;
                    const offset = n - data.length;
                    const pts = data.map((v, i) => [(i + offset + 1) * step, mid - dir * Math.min(1, Math.max(0, v / root.scaleMax)) * mid]);
                    const curve = () => {
                        ctx.moveTo(pts[0][0], pts[0][1]);
                        for (let i = 1; i < pts.length - 1; i++) {
                            const mx = (pts[i][0] + pts[i + 1][0]) / 2, my = (pts[i][1] + pts[i + 1][1]) / 2;
                            ctx.quadraticCurveTo(pts[i][0], pts[i][1], mx, my);
                        }
                        ctx.lineTo(pts[pts.length - 1][0], pts[pts.length - 1][1]);
                    };
                    // Fill back to the middle line
                    ctx.beginPath();
                    curve();
                    ctx.lineTo(pts[pts.length - 1][0], mid);
                    ctx.lineTo(pts[0][0], mid);
                    ctx.closePath();
                    const g = ctx.createLinearGradient(0, dir > 0 ? 0 : h, 0, mid);
                    g.addColorStop(0, root.rgba(color, 0.42));
                    g.addColorStop(1, root.rgba(color, 0.03));
                    ctx.fillStyle = g;
                    ctx.fill();
                    ctx.beginPath();
                    curve();
                    ctx.strokeStyle = root.rgba(color, 1);
                    ctx.lineWidth = 2;
                    ctx.stroke();

                    // The latest reading
                    const last = pts[pts.length - 1];
                    ctx.fillStyle = root.rgba(color, 0.25);
                    ctx.beginPath();
                    ctx.arc(last[0], last[1], 6, 0, Math.PI * 2);
                    ctx.fill();
                    ctx.fillStyle = root.rgba(color, 1);
                    ctx.beginPath();
                    ctx.arc(last[0], last[1], 3, 0, Math.PI * 2);
                    ctx.fill();
                };
                layer(root.down, root.downColor, 1);
                layer(root.up, root.upColor, -1);
            }
        }
    }

    // ── hover ──
    Rectangle {
        visible: root.hoverIndex >= 0
        x: root.plotX + root.hoverIndex * root.step
        y: root.plotY
        width: 1
        height: root.plotH
        color: ClockStyle.colSubtext
        opacity: 0.6
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: mouse => {
            const i = Math.round((mouse.x - root.plotX) / root.plotW * (root.length - 1));
            root.hoverIndex = i >= 0 && i < root.length ? i : -1;
        }
        onExited: root.hoverIndex = -1
    }

    Rectangle {
        id: tip
        readonly property int k: root.hoverIndex - (root.length - root.down.length)
        readonly property int ku: root.hoverIndex - (root.length - root.up.length)
        visible: root.hoverIndex >= 0 && k >= 0 && k < root.down.length
        readonly property real hx: root.plotX + root.hoverIndex * root.step
        x: hx + 12 + width > root.width ? hx - 12 - width : hx + 12
        y: 6
        radius: ClockStyle.radiusSmall
        color: ClockStyle.colSurfaceHigh
        border.width: 1
        border.color: root.gridColor
        implicitWidth: tipColumn.implicitWidth + 16
        implicitHeight: tipColumn.implicitHeight + 12

        Column {
            id: tipColumn
            anchors.centerIn: parent
            spacing: 2
            StyledText {
                text: {
                    const ago = Math.round((root.length - 1 - root.hoverIndex) * root.interval);
                    return ago === 0 ? Translation.tr("now") : Translation.tr("%1 s ago").arg(ago);
                }
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall - 1
            }
            StyledText {
                text: "↓ " + (tip.k >= 0 && tip.k < root.down.length ? Fmt.rate(root.down[tip.k]) : "–")
                color: root.downColor
                font.pixelSize: ClockStyle.textSmall
            }
            StyledText {
                text: "↑ " + (tip.ku >= 0 && tip.ku < root.up.length ? Fmt.rate(root.up[tip.ku]) : "–")
                color: root.upColor
                font.pixelSize: ClockStyle.textSmall
            }
        }
    }
}
