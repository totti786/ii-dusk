import QtQuick

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Round trip times of several targets on one time axis. `series` is a list of
 * { name, color, values } with `values` oldest first and a negative value for a lost ping.
 * Behind the lines sit bands for fine / slow / bad, lost pings are red ticks along the bottom
 * and hovering reads every series at that moment.
 */
Item {
    id: root

    property var series: []
    property int length: 120
    property real floorMax: 60
    property bool fillFirst: true
    /// Seconds between two samples, for the time axis
    property real interval: 1

    // Wide enough for the longest label of the current scale, in the font the labels are drawn in
    // The canvas does not know the theme font by name, so it draws in the generic one and the
    // metrics measure that one too
    readonly property string labelFont: "11px sans-serif"
    readonly property real leftPad: Math.ceil(labelMetrics.advanceWidth) + 12
    TextMetrics {
        id: labelMetrics
        font.family: "sans-serif"
        font.pixelSize: 11
        text: Math.round(root.scaleMax) + " ms"
    }
    readonly property real bottomPad: 16
    readonly property color gridColor: Qt.rgba(ClockStyle.colSubtext.r, ClockStyle.colSubtext.g, ClockStyle.colSubtext.b, 0.16)

    // Scale to the data, rounded up to a tidy number so the labels do not jitter every second
    readonly property real scaleMax: {
        // Scale to the 95th percentile, so one multi-second stall does not flatten everything else;
        // a line that goes past the top is clipped there
        const all = [];
        for (const s of root.series)
            for (const v of s.values)
                if (v >= 0)
                    all.push(v);
        all.sort((a, b) => a - b);
        let m = Math.max(root.floorMax, all.length > 0 ? all[Math.floor(all.length * 0.95)] : 0);
        const steps = [60, 100, 150, 200, 300, 500, 1000, 2000];
        for (const s of steps)
            if (m * 1.1 <= s)
                return s;
        return Math.ceil(m * 1.1 / 1000) * 1000;
    }

    property int hoverIndex: -1

    function rgba(c: color, a: real): string {
        return `rgba(${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)},${a})`;
    }

    // The plot area inside the axis labels
    readonly property real plotX: root.leftPad
    readonly property real plotY: 4
    readonly property real plotW: Math.max(1, root.width - root.leftPad - 4)
    readonly property real plotH: Math.max(1, root.height - root.bottomPad - 4)
    readonly property real step: root.plotW / (root.length - 1)

    onSeriesChanged: root.seriesUpdated()
    onScaleMaxChanged: { back.requestPaint(); lines.requestPaint(); }
    onLeftPadChanged: { back.requestPaint(); lines.requestPaint(); }
    onWidthChanged: back.requestPaint()
    onHeightChanged: back.requestPaint()

    function seriesUpdated(): void {
        lines.requestPaint();
        // Same glide as MonitorGraph: the new sample is painted a step to the right of the
        // visible area and the layer slides over to it
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

    // ── bands, grid and labels: only repainted when the scale or the size changes ──
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
            const Y = v => y1 - Math.max(0, Math.min(1, v / root.scaleMax)) * h;

            // Bands: fine below 60 ms, slow up to 150, bad above
            const bands = [[0, 60, ClockStyle.colPrimary], [60, 150, ClockStyle.colTertiary], [150, root.scaleMax, ClockStyle.colError]];
            for (const b of bands) {
                if (b[0] >= root.scaleMax)
                    continue;
                const top = Y(Math.min(b[1], root.scaleMax)), bottom = Y(b[0]);
                ctx.fillStyle = root.rgba(b[2], 0.07);
                ctx.fillRect(x0, top, w, bottom - top);
            }

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
            // What counts as fast and slow, dashed
            ctx.setLineDash([4, 4]);
            for (const t of [[60, ClockStyle.colPrimary], [150, ClockStyle.colTertiary]]) {
                if (t[0] >= root.scaleMax)
                    continue;
                ctx.strokeStyle = root.rgba(t[1], 0.45);
                ctx.beginPath();
                ctx.moveTo(x0, Math.round(Y(t[0])) + 0.5);
                ctx.lineTo(x1, Math.round(Y(t[0])) + 0.5);
                ctx.stroke();
            }
            ctx.setLineDash([]);

            ctx.font = root.labelFont;
            ctx.textBaseline = "middle";
            ctx.textAlign = "right";
            ctx.lineWidth = 1;
            const lines = 4;
            for (let i = 0; i <= lines; i++) {
                const v = root.scaleMax * i / lines;
                const y = Math.round(Y(v)) + 0.5;
                ctx.strokeStyle = root.gridColor.toString();
                ctx.beginPath();
                ctx.moveTo(x0, y);
                ctx.lineTo(x1, y);
                ctx.stroke();
                ctx.fillStyle = ClockStyle.colSubtext.toString();
                ctx.fillText(Math.round(v) + " ms", x0 - 6, Math.min(y1 - 2, Math.max(y0 + 5, y)));
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

    // ── the lines, in a clipped window so they can glide ──
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
                const Y = v => h - Math.max(0, Math.min(1, v / root.scaleMax)) * h;
                ctx.lineJoin = "round";
                ctx.lineCap = "round";

                // Lost pings first, as a faint column the full height so they cannot be missed
                const lostAt = new Set();
                for (const s of root.series) {
                    const off = n - s.values.length;
                    s.values.forEach((v, i) => { if (v < 0) lostAt.add(i + off); });
                }
                ctx.fillStyle = root.rgba(ClockStyle.colError, 0.16);
                for (const i of lostAt)
                    ctx.fillRect((i + 1) * step - step / 2, 0, step, h);

                // A smooth path through a run of points, left open for the caller
                const curve = run => {
                    ctx.moveTo(run[0][0], run[0][1]);
                    for (let i = 1; i < run.length - 1; i++) {
                        const mx = (run[i][0] + run[i + 1][0]) / 2, my = (run[i][1] + run[i + 1][1]) / 2;
                        ctx.quadraticCurveTo(run[i][0], run[i][1], mx, my);
                    }
                    ctx.lineTo(run[run.length - 1][0], run[run.length - 1][1]);
                };

                for (let si = root.series.length - 1; si >= 0; si--) {
                    const s = root.series[si];
                    const data = s.values;
                    const offset = n - data.length;
                    const color = Qt.color(s.color);
                    const X = i => (i + offset + 1) * step;
                    let run = [];
                    const flush = () => {
                        if (run.length > 1) {
                            ctx.beginPath();
                            curve(run);
                            ctx.lineTo(run[run.length - 1][0], h);
                            ctx.lineTo(run[0][0], h);
                            ctx.closePath();
                            const g = ctx.createLinearGradient(0, 0, 0, h);
                            g.addColorStop(0, root.rgba(color, si === 0 ? 0.30 : 0.12));
                            g.addColorStop(1, root.rgba(color, 0.0));
                            ctx.fillStyle = g;
                            ctx.fill();

                            ctx.beginPath();
                            curve(run);
                            ctx.strokeStyle = root.rgba(color, 1);
                            ctx.lineWidth = si === 0 ? 2.4 : 1.8;
                            ctx.stroke();
                        }
                        run = [];
                    };
                    for (let i = 0; i < data.length; i++) {
                        if (data[i] < 0) {
                            flush();
                            continue;
                        }
                        run.push([X(i), Y(data[i])]);
                        // Off the scale: a small marker on the top edge instead of a vanishing line
                        if (data[i] > root.scaleMax) {
                            ctx.fillStyle = root.rgba(ClockStyle.colError, 0.95);
                            ctx.beginPath();
                            ctx.moveTo(X(i) - 4, 0);
                            ctx.lineTo(X(i) + 4, 0);
                            ctx.lineTo(X(i), 7);
                            ctx.closePath();
                            ctx.fill();
                        }
                    }
                    flush();

                    // The latest reading gets a dot with a halo
                    for (let i = data.length - 1; i >= 0; i--) {
                        if (data[i] < 0)
                            break;
                        const x = X(i), y = Y(data[i]);
                        ctx.fillStyle = root.rgba(color, 0.25);
                        ctx.beginPath();
                        ctx.arc(x, y, 7, 0, Math.PI * 2);
                        ctx.fill();
                        ctx.fillStyle = root.rgba(color, 1);
                        ctx.beginPath();
                        ctx.arc(x, y, 3.5, 0, Math.PI * 2);
                        ctx.fill();
                        break;
                    }
                }
            }
        }
    }

    // ── hover cursor and the points under it, plain items so the lines are not repainted ──
    Rectangle {
        visible: root.hoverIndex >= 0
        x: root.plotX + root.hoverIndex * root.step
        y: root.plotY
        width: 1
        height: root.plotH
        color: ClockStyle.colSubtext
        opacity: 0.6
    }
    Repeater {
        model: root.hoverIndex >= 0 ? root.series.length : 0
        delegate: Rectangle {
            id: dot
            required property int index
            readonly property var s: root.series[index]
            readonly property int k: root.hoverIndex - (root.length - s.values.length)
            readonly property real v: k >= 0 && k < s.values.length ? s.values[k] : -1
            visible: v >= 0
            width: 8
            height: 8
            radius: 4
            color: s.color
            x: root.plotX + root.hoverIndex * root.step - 4
            y: root.plotY + root.plotH - Math.max(0, Math.min(1, v / root.scaleMax)) * root.plotH - 4
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: mouse => {
            const w = root.width - root.leftPad - 4;
            const i = Math.round((mouse.x - root.leftPad) / w * (root.length - 1));
            root.hoverIndex = i >= 0 && i < root.length ? i : -1;
        }
        onExited: root.hoverIndex = -1
    }

    // Readout for the hovered moment
    Rectangle {
        id: tip
        visible: root.hoverIndex >= 0 && root.series.length > 0
        readonly property real hx: root.leftPad + root.hoverIndex * (root.width - root.leftPad - 4) / (root.length - 1)
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
            Repeater {
                model: root.hoverIndex >= 0 ? root.series : []
                delegate: Row {
                    id: tipRow
                    required property var modelData
                    readonly property int k: root.hoverIndex - (root.length - modelData.values.length)
                    readonly property real v: k >= 0 && k < modelData.values.length ? modelData.values[k] : -2
                    visible: v > -2
                    spacing: 6
                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: tipRow.modelData.color
                    }
                    StyledText {
                        text: `${tipRow.modelData.name}  ${tipRow.v < 0 ? Translation.tr("lost") : (tipRow.v < 10 ? tipRow.v.toFixed(1) : Math.round(tipRow.v)) + " ms"}`
                        color: tipRow.v < 0 ? ClockStyle.colError : ClockStyle.colOnBackground
                        font.pixelSize: ClockStyle.textSmall
                    }
                }
            }
        }
    }
}
