import QtQuick
import qs.modules.common
import ".."
import "../../../../services/WeatherAppLogic.js" as Logic

/**
 * A theme-aware line / area / bar chart. It deliberately knows nothing about providers:
 * the chart page hands it numbers that are already in the user's units, and this item
 * only handles domains, axes, gaps and the hover readout.
 */
Item {
    id: root

    property var values: []
    property var secondary: []
    property var bars: []
    property var labels: []
    property var pointLabels: []
    property string unit: ""
    property string secondaryUnit: ""
    property string barUnit: ""
    property string primaryLabel: ""
    property string secondaryLabel: ""
    property string barLabel: ""
    property color primaryColor: WeatherStyle.colPrimary
    property color secondaryColor: WeatherStyle.colTertiary
    property color barColor: WeatherStyle.colSecondary
    property var yMin: null
    property var yMax: null
    property var secondaryMin: null
    property var secondaryMax: null
    property int decimals: 0
    property int secondaryDecimals: 0
    property int hoverIndex: -1

    implicitHeight: WeatherStyle.chartHeight
    clip: true

    readonly property int count: Math.max(
        root.values ? root.values.length : 0,
        root.secondary ? root.secondary.length : 0,
        root.bars ? root.bars.length : 0,
        root.labels ? root.labels.length : 0)
    readonly property bool hasPrimary: root.anyFinite(root.values)
    readonly property bool hasSecondary: root.anyFinite(root.secondary)
    readonly property bool hasBars: root.anyFinite(root.bars)
    readonly property bool hasAny: root.hasPrimary || root.hasSecondary || root.hasBars
    readonly property bool secondaryAxis: root.secondaryMin !== null || root.secondaryMax !== null
    readonly property real plotLeft: 36
    readonly property real plotRight: root.secondaryAxis ? 36 : 12
    readonly property real plotTop: 10
    readonly property real plotBottom: 24

    function anyFinite(list) {
        if (!list)
            return false;
        for (let i = 0; i < list.length; i++) {
            const value = list[i];
            if (value !== null && value !== undefined && Number.isFinite(Number(value)))
                return true;
        }
        return false;
    }

    function finiteValues(list) {
        const result = [];
        if (!list)
            return result;
        for (let i = 0; i < list.length; i++) {
            const value = list[i];
            if (value !== null && value !== undefined && Number.isFinite(Number(value)))
                result.push(Number(value));
        }
        return result;
    }

    function paddedDomain(values, minOverride, maxOverride, zeroFloor) {
        const finite = root.finiteValues(values);
        let min = minOverride !== null && minOverride !== undefined ? Number(minOverride) : (finite.length ? Math.min(...finite) : 0);
        let max = maxOverride !== null && maxOverride !== undefined ? Number(maxOverride) : (finite.length ? Math.max(...finite) : 1);
        if (!Number.isFinite(min)) min = 0;
        if (!Number.isFinite(max)) max = 1;
        if (min === max) {
            min -= 1;
            max += 1;
        }
        const span = max - min;
        if (minOverride === null || minOverride === undefined) {
            min -= span * 0.1;
            if (zeroFloor && min > 0 && min < span * 0.2)
                min = 0;
        }
        if (maxOverride === null || maxOverride === undefined)
            max += span * 0.1;
        if (max <= min)
            max = min + 1;
        return { min: min, max: max };
    }

    function primaryDomain() {
        if (!root.hasPrimary && root.hasBars) {
            const barValues = root.finiteValues(root.bars);
            const top = barValues.length ? Math.max(...barValues) : 1;
            return { min: 0, max: top > 0 ? top * 1.18 : 1 };
        }
        if (!root.hasPrimary && root.hasSecondary)
            return root.paddedDomain(root.secondary, root.yMin, root.yMax, false);
        return root.paddedDomain(root.values, root.yMin, root.yMax, false);
    }

    function secondaryDomain() {
        if (!root.secondaryAxis)
            return root.primaryDomain();
        return root.paddedDomain(root.secondary, root.secondaryMin, root.secondaryMax, false);
    }

    function xAt(index, step, plot) {
        return plot.x + (index + 0.5) * step;
    }

    function yAt(value, domain, plot) {
        return plot.y + (domain.max - value) / (domain.max - domain.min) * plot.h;
    }

    function roundedRect(ctx, x, y, w, h, r) {
        const radius = Math.min(r, w / 2, h / 2);
        ctx.beginPath();
        ctx.moveTo(x + radius, y);
        ctx.lineTo(x + w - radius, y);
        ctx.quadraticCurveTo(x + w, y, x + w, y + radius);
        ctx.lineTo(x + w, y + h - radius);
        ctx.quadraticCurveTo(x + w, y + h, x + w - radius, y + h);
        ctx.lineTo(x + radius, y + h);
        ctx.quadraticCurveTo(x, y + h, x, y + h - radius);
        ctx.lineTo(x, y + radius);
        ctx.quadraticCurveTo(x, y, x + radius, y);
        ctx.closePath();
    }

    function drawRun(ctx, series, domain, plot, step, color, width, fill) {
        let run = [];
        const flush = () => {
            if (run.length === 0)
                return;
            if (fill) {
                const gradient = ctx.createLinearGradient(0, plot.y, 0, plot.y + plot.h);
                gradient.addColorStop(0, WeatherStyle.alpha(color, 0.22));
                gradient.addColorStop(1, WeatherStyle.alpha(color, 0.01));
                ctx.beginPath();
                const first = run[0];
                const last = run[run.length - 1];
                ctx.moveTo(first.x, plot.y + plot.h);
                ctx.lineTo(first.x, first.y);
                for (let i = 1; i < run.length; i++)
                    ctx.lineTo(run[i].x, run[i].y);
                ctx.lineTo(last.x, plot.y + plot.h);
                ctx.closePath();
                ctx.fillStyle = gradient;
                ctx.fill();
            }
            if (run.length === 1) {
                ctx.beginPath();
                ctx.arc(run[0].x, run[0].y, width / 2 + 1.5, 0, Math.PI * 2);
                ctx.fillStyle = color;
                ctx.fill();
            } else {
                ctx.beginPath();
                ctx.moveTo(run[0].x, run[0].y);
                for (let i = 1; i < run.length; i++) {
                    const previous = run[i - 1];
                    const current = run[i];
                    const midX = (previous.x + current.x) / 2;
                    ctx.quadraticCurveTo(previous.x, previous.y, midX, (previous.y + current.y) / 2);
                    ctx.lineTo(current.x, current.y);
                }
                ctx.strokeStyle = color;
                ctx.lineWidth = width;
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                ctx.stroke();
            }
            run = [];
        };
        for (let i = 0; i < series.length; i++) {
            const value = series[i];
            if (value === null || value === undefined || !Number.isFinite(Number(value))) {
                flush();
                continue;
            }
            run.push({ x: root.xAt(i, step, plot), y: root.yAt(Number(value), domain, plot) });
        }
        flush();
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            target: root
            function onValuesChanged() { canvas.requestPaint(); }
            function onSecondaryChanged() { canvas.requestPaint(); }
            function onBarsChanged() { canvas.requestPaint(); }
            function onLabelsChanged() { canvas.requestPaint(); }
            function onHoverIndexChanged() { canvas.requestPaint(); }
            function onYMinChanged() { canvas.requestPaint(); }
            function onYMaxChanged() { canvas.requestPaint(); }
            function onSecondaryMinChanged() { canvas.requestPaint(); }
            function onSecondaryMaxChanged() { canvas.requestPaint(); }
        }

        onPaint: {
            const ctx = canvas.getContext("2d");
            ctx.clearRect(0, 0, canvas.width, canvas.height);
            const plot = {
                x: root.plotLeft,
                y: root.plotTop,
                w: Math.max(1, canvas.width - root.plotLeft - root.plotRight),
                h: Math.max(1, canvas.height - root.plotTop - root.plotBottom)
            };

            if (!root.hasAny || root.count === 0) {
                ctx.fillStyle = WeatherStyle.colSubtext;
                ctx.font = `400 11px "${WeatherStyle.chartFont}"`;
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";
                ctx.fillText("No data for this chart yet", canvas.width / 2, canvas.height / 2);
                return;
            }

            const primary = root.primaryDomain();
            const secondary = root.secondaryDomain();
            const step = plot.w / root.count;
            const axisDomain = root.hasPrimary ? primary : primary;
            const showBarAxis = !root.hasPrimary && root.hasBars;

            // Grid and frame
            ctx.font = `400 9px "${WeatherStyle.chartFont}"`;
            ctx.textBaseline = "middle";
            ctx.lineWidth = 1;
            for (let i = 0; i <= 4; i++) {
                const y = plot.y + plot.h * i / 4;
                ctx.beginPath();
                ctx.setLineDash([2, 4]);
                ctx.strokeStyle = WeatherStyle.alpha(WeatherStyle.colOutline, i === 4 ? 0.9 : 0.5);
                ctx.moveTo(plot.x, y);
                ctx.lineTo(plot.x + plot.w, y);
                ctx.stroke();
                ctx.setLineDash([]);
                const value = axisDomain.max - (axisDomain.max - axisDomain.min) * i / 4;
                ctx.fillStyle = WeatherStyle.colSubtext;
                ctx.textAlign = "right";
                ctx.fillText(Logic.chartAxisLabel(value), plot.x - 6, y);
            }

            if (root.secondaryAxis) {
                for (let i = 0; i <= 4; i++) {
                    const value = secondary.max - (secondary.max - secondary.min) * i / 4;
                    const y = plot.y + plot.h * i / 4;
                    ctx.fillStyle = WeatherStyle.colSubtext;
                    ctx.textAlign = "left";
                    ctx.fillText(Logic.chartAxisLabel(value), plot.x + plot.w + 6, y);
                }
            }

            // Bars first, so a line and a chance overlay stay readable.
            if (root.hasBars) {
                const barValues = root.finiteValues(root.bars);
                const barTop = barValues.length ? Math.max(...barValues) : 1;
                const barScale = barTop > 0 ? barTop * 1.18 : 1;
                const barWidth = Math.max(2, Math.min(18, step * 0.55));
                for (let i = 0; i < root.bars.length; i++) {
                    const value = root.bars[i];
                    if (value === null || value === undefined || !Number.isFinite(Number(value)) || Number(value) <= 0)
                        continue;
                    const barHeight = Math.max(1, Number(value) / barScale * plot.h);
                    const x = root.xAt(i, step, plot) - barWidth / 2;
                    ctx.fillStyle = WeatherStyle.alpha(root.barColor, 0.72);
                    ctx.fillRect(x, plot.y + plot.h - barHeight, barWidth, barHeight);
                }
            }

            if (root.hasPrimary)
                root.drawRun(ctx, root.values, primary, plot, step, root.primaryColor, 2.2, true);

            if (root.hasSecondary) {
                ctx.save();
                ctx.setLineDash([4, 3]);
                root.drawRun(ctx, root.secondary, secondary, plot, step, WeatherStyle.alpha(root.secondaryColor, 0.9), 1.5, false);
                ctx.restore();
            }

            // X labels
            ctx.font = `400 9px "${WeatherStyle.chartFont}"`;
            ctx.textAlign = "center";
            ctx.textBaseline = "top";
            ctx.fillStyle = WeatherStyle.colSubtext;
            for (let i = 0; i < root.labels.length; i++) {
                const label = root.labels[i];
                if (!label)
                    continue;
                const x = root.xAt(i, step, plot);
                if (x < plot.x + 10 || x > plot.x + plot.w - 10)
                    continue;
                ctx.fillText(String(label), x, plot.y + plot.h + 7);
            }

            // Hover readout
            const index = root.hoverIndex;
            if (index >= 0 && index < root.count) {
                const x = root.xAt(index, step, plot);
                const value = root.values ? root.values[index] : null;
                const second = root.secondary ? root.secondary[index] : null;
                const barValue = root.bars ? root.bars[index] : null;
                const hasValue = value !== null && value !== undefined && Number.isFinite(Number(value));
                const hasSecond = second !== null && second !== undefined && Number.isFinite(Number(second));
                const hasBar = barValue !== null && barValue !== undefined && Number.isFinite(Number(barValue));

                if (hasValue || hasSecond || hasBar) {
                    ctx.beginPath();
                    ctx.setLineDash([2, 3]);
                    ctx.strokeStyle = WeatherStyle.alpha(WeatherStyle.colOnSurfaceVariant, 0.45);
                    ctx.lineWidth = 1;
                    ctx.moveTo(x, plot.y);
                    ctx.lineTo(x, plot.y + plot.h);
                    ctx.stroke();
                    ctx.setLineDash([]);

                    if (hasValue) {
                        ctx.beginPath();
                        ctx.arc(x, root.yAt(Number(value), primary, plot), 3.5, 0, Math.PI * 2);
                        ctx.fillStyle = WeatherStyle.colSurface;
                        ctx.fill();
                        ctx.strokeStyle = root.primaryColor;
                        ctx.lineWidth = 2;
                        ctx.stroke();
                    }
                    if (hasSecond) {
                        ctx.beginPath();
                        ctx.arc(x, root.yAt(Number(second), secondary, plot), 3, 0, Math.PI * 2);
                        ctx.fillStyle = WeatherStyle.colSurface;
                        ctx.fill();
                        ctx.strokeStyle = root.secondaryColor;
                        ctx.lineWidth = 1.5;
                        ctx.stroke();
                    }
                }

                const lines = [];
                const pointLabel = root.pointLabels && root.pointLabels[index] ? root.pointLabels[index] : "";
                if (pointLabel)
                    lines.push({ text: pointLabel, color: WeatherStyle.colSubtext, weight: 400 });
                if (hasValue)
                    lines.push({
                        text: `${root.primaryLabel || "Value"}: ${Logic.formatChartValue(value, root.decimals)}${root.unit ? " " + root.unit : ""}`,
                        color: root.primaryColor,
                        weight: 600
                    });
                else if (hasBar)
                    lines.push({
                        text: `${root.barLabel || "Amount"}: ${Logic.formatChartValue(barValue, root.decimals)}${root.barUnit || root.unit ? " " + (root.barUnit || root.unit) : ""}`,
                        color: root.barColor,
                        weight: 600
                    });
                if (hasSecond)
                    lines.push({
                        text: `${root.secondaryLabel || "Secondary"}: ${Logic.formatChartValue(second, root.secondaryDecimals)}${root.secondaryUnit ? " " + root.secondaryUnit : ""}`,
                        color: root.secondaryColor,
                        weight: 600
                    });

                if (lines.length > 0) {
                    ctx.font = `400 10px "${WeatherStyle.chartFont}"`;
                    let boxWidth = 0;
                    for (const line of lines) {
                        ctx.font = `${line.weight} 10px "${WeatherStyle.chartFont}"`;
                        boxWidth = Math.max(boxWidth, ctx.measureText(line.text).width);
                    }
                    boxWidth = Math.min(boxWidth + 20, Math.max(120, plot.w - 8));
                    const boxHeight = 10 + lines.length * 15;
                    let boxX = x + 10;
                    if (boxX + boxWidth > canvas.width - 4)
                        boxX = x - boxWidth - 10;
                    boxX = Math.max(4, boxX);
                    const boxY = Math.max(4, plot.y + 4);
                    ctx.fillStyle = WeatherStyle.alpha(WeatherStyle.colSurfaceHighest, 0.97);
                    root.roundedRect(ctx, boxX, boxY, boxWidth, boxHeight, 7);
                    ctx.fill();
                    ctx.strokeStyle = WeatherStyle.alpha(WeatherStyle.colOutline, 0.7);
                    ctx.lineWidth = 1;
                    ctx.stroke();
                    ctx.textAlign = "left";
                    ctx.textBaseline = "middle";
                    for (let i = 0; i < lines.length; i++) {
                        const line = lines[i];
                        ctx.font = `${line.weight} 10px "${WeatherStyle.chartFont}"`;
                        ctx.fillStyle = line.color;
                        ctx.fillText(line.text, boxX + 9, boxY + 8 + i * 15);
                    }
                }
            }
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        preventStealing: true
        onPositionChanged: mouse => {
            if (!root.hasAny || root.count === 0) {
                root.hoverIndex = -1;
                return;
            }
            const plotWidth = Math.max(1, width - root.plotLeft - root.plotRight);
            const index = Math.floor((mouse.x - root.plotLeft) / (plotWidth / root.count));
            root.hoverIndex = Math.max(0, Math.min(root.count - 1, index));
        }
        onExited: root.hoverIndex = -1
    }
}
