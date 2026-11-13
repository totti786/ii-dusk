import QtQuick

import qs.modules.common
import qs.modules.ii.clock.components

/**
 * A graph of the last couple of minutes. `values` is oldest first; a value below zero is a gap
 * (a lost ping). `maxValue` of 0 scales to the data, otherwise it is fixed (100 for
 * percentages). `secondary` is a second series on the same scale (upload next to download).
 *
 * The grid is painted once. The data layer is painted when a sample arrives and then glides left
 * by one step over the next second, so a new sample slides in instead of the whole graph
 * redrawing in place.
 *
 * `style`: "line" a filled line, "bars" rounded columns, "mirror" `values` above a middle line
 * and `secondary` below it.
 */
Item {
    id: root

    property var values: []
    property var secondary: []
    property real maxValue: 0
    property real floorMax: 1
    property int length: 120
    property color lineColor: ClockStyle.colPrimary
    property color secondaryColor: ClockStyle.colTertiary
    property bool filled: true
    property bool grid: true
    property real lineWidth: 2
    property string style: "line"
    /// Seconds between samples; the glide takes this long
    property real interval: 1

    readonly property real step: root.width / (root.length - 1)
    readonly property real valueScale: {
        if (root.maxValue > 0)
            return root.maxValue;
        let m = root.floorMax;
        for (const v of root.values)
            m = Math.max(m, v);
        for (const v of root.secondary)
            m = Math.max(m, v);
        return root.style === "line" ? m * 1.15 : m * 1.05;
    }

    clip: true

    function rgba(c: color, a: real): string {
        return `rgba(${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)},${a})`;
    }

    onValuesChanged: root.dataChanged()
    onSecondaryChanged: root.dataChanged()
    onValueScaleChanged: data.requestPaint()
    onLineColorChanged: { data.requestPaint(); back.requestPaint(); }
    onStyleChanged: { data.requestPaint(); back.requestPaint(); }

    function dataChanged(): void {
        data.requestPaint();
        // The new sample is painted one step to the right, off the visible area; the layer
        // starts where the old picture was and glides to where the new one belongs
        if (!ClockStyle.reducedMotion && root.width > 0) {
            glide.stop();
            data.x = 0;
            glide.from = 0;
            glide.to = -root.step;
            glide.duration = root.interval * 1000;
            glide.start();
        } else {
            data.x = -root.step;
        }
    }

    // ── static grid ──
    Canvas {
        id: back
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (!root.grid)
                return;
            ctx.strokeStyle = root.rgba(root.lineColor, 0.12);
            ctx.lineWidth = 1;
            for (let i = 1; i < 4; i++) {
                if (root.style === "mirror" && i === 2)
                    continue;
                ctx.beginPath();
                ctx.moveTo(0, Math.round(height * i / 4) + 0.5);
                ctx.lineTo(width, Math.round(height * i / 4) + 0.5);
                ctx.stroke();
            }
            if (root.style === "mirror") {
                ctx.strokeStyle = root.rgba(root.lineColor, 0.3);
                ctx.beginPath();
                ctx.moveTo(0, Math.round(height / 2) + 0.5);
                ctx.lineTo(width, Math.round(height / 2) + 0.5);
                ctx.stroke();
            }
        }
    }

    // ── the data, one step wider than the graph so there is room to glide ──
    Canvas {
        id: data
        x: -root.step
        width: root.width + root.step
        height: root.height
        onWidthChanged: {
            requestPaint();
            if (!glide.running)
                data.x = -root.step;
        }
        onHeightChanged: requestPaint()

        NumberAnimation on x {
            id: glide
            running: false
            easing.type: Easing.Linear
        }

        function bars(ctx) {
            const n = root.length;
            const step = root.step;
            const bw = Math.max(1.5, step - 1.5);
            const mirror = root.style === "mirror";
            const mid = mirror ? Math.round(root.height / 2) : root.height;
            const room = (mirror ? mid : root.height) - 2;
            const column = (i, v, color, down) => {
                const frac = Math.max(0, Math.min(1, v / root.valueScale));
                const hgt = frac > 0 ? Math.max(2, frac * room) : 0;
                if (hgt <= 0)
                    return;
                const x = (i + 1) * step - bw / 2;
                const hot = root.maxValue > 0 && frac >= 0.9 && !down;
                const c = hot ? ClockStyle.colError : color;
                const top = down ? mid + 1 : mid - hgt;
                const g = ctx.createLinearGradient(0, down ? mid : mid - hgt, 0, down ? mid + hgt : mid);
                g.addColorStop(0, root.rgba(c, down ? 0.4 : 1));
                g.addColorStop(1, root.rgba(c, down ? 1 : 0.4));
                ctx.fillStyle = g;
                ctx.beginPath();
                ctx.roundedRect(x, top, bw, hgt, Math.min(bw / 2, 3), Math.min(bw / 2, 3));
                ctx.fill();
            };
            const a = root.values, b = root.secondary;
            for (let i = 0; i < a.length; i++)
                column(i + n - a.length, a[i], root.lineColor, false);
            if (mirror)
                for (let i = 0; i < b.length; i++)
                    column(i + n - b.length, b[i], root.secondaryColor, true);
        }

        function trace(ctx, series, color, fill) {
            const n = root.length;
            const step = root.step;
            const offset = n - series.length;
            const y = v => root.height - 2 - Math.max(0, Math.min(1, v / root.valueScale)) * (root.height - 4);
            const c = Qt.color(color);
            ctx.lineJoin = "round";
            ctx.lineCap = "round";
            let run = [];
            const flush = () => {
                if (run.length > 1) {
                    ctx.beginPath();
                    ctx.moveTo(run[0][0], run[0][1]);
                    for (const p of run.slice(1))
                        ctx.lineTo(p[0], p[1]);
                    ctx.strokeStyle = color;
                    ctx.lineWidth = root.lineWidth;
                    ctx.stroke();
                    if (fill) {
                        ctx.lineTo(run[run.length - 1][0], root.height);
                        ctx.lineTo(run[0][0], root.height);
                        ctx.closePath();
                        const g = ctx.createLinearGradient(0, 0, 0, root.height);
                        g.addColorStop(0, root.rgba(c, 0.35));
                        g.addColorStop(1, root.rgba(c, 0.02));
                        ctx.fillStyle = g;
                        ctx.fill();
                    }
                }
                run = [];
            };
            for (let i = 0; i < series.length; i++) {
                if (series[i] < 0) {
                    flush();
                    continue;
                }
                run.push([(i + offset + 1) * step, y(series[i])]);
            }
            flush();
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (root.style !== "line") {
                data.bars(ctx);
                return;
            }
            if (root.secondary.length > 1)
                data.trace(ctx, root.secondary, root.secondaryColor.toString(), root.filled);
            if (root.values.length > 1)
                data.trace(ctx, root.values, root.lineColor.toString(), root.filled);
        }
    }
}
