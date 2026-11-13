import QtQuick
import qs.modules.common
import ".."

/**
 * The daily low/high strip. A shared domain across every day makes the bars comparable,
 * which a row of unrelated progress bars would not be.
 */
Item {
    id: root

    property var days: []
    property string unit: ""
    property int hoverIndex: -1

    implicitHeight: Math.max(112, (root.days ? root.days.length : 0) * 36 + 18)
    clip: true

    readonly property real labelWidth: 86
    readonly property real valueWidth: 84
    readonly property real rowHeight: 36

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

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            target: root
            function onDaysChanged() { canvas.requestPaint(); }
            function onHoverIndexChanged() { canvas.requestPaint(); }
        }

        onPaint: {
            const ctx = canvas.getContext("2d");
            ctx.clearRect(0, 0, canvas.width, canvas.height);
            if (!root.days || root.days.length === 0) {
                ctx.fillStyle = WeatherStyle.colSubtext;
                ctx.font = `400 11px "${WeatherStyle.chartFont}"`;
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";
                ctx.fillText("No daily forecast yet", canvas.width / 2, canvas.height / 2);
                return;
            }

            let minimum = Infinity;
            let maximum = -Infinity;
            for (const day of root.days) {
                if (day.min !== null && Number.isFinite(Number(day.min)))
                    minimum = Math.min(minimum, Number(day.min));
                if (day.max !== null && Number.isFinite(Number(day.max)))
                    maximum = Math.max(maximum, Number(day.max));
            }
            if (!Number.isFinite(minimum) || !Number.isFinite(maximum)) {
                minimum = 0;
                maximum = 1;
            }
            if (minimum === maximum) {
                minimum -= 1;
                maximum += 1;
            }
            const pad = (maximum - minimum) * 0.12;
            minimum -= pad;
            maximum += pad;

            const labelWidth = Math.min(root.labelWidth, canvas.width * 0.28);
            const valueWidth = Math.min(root.valueWidth, canvas.width * 0.26);
            const trackX = labelWidth + 8;
            const trackWidth = Math.max(10, canvas.width - trackX - valueWidth - 8);
            const rowHeight = root.rowHeight;
            const top = 9;

            for (let i = 0; i < root.days.length; i++) {
                const day = root.days[i];
                const y = top + i * rowHeight + rowHeight / 2;
                const isHover = i === root.hoverIndex;

                if (isHover) {
                    ctx.fillStyle = WeatherStyle.alpha(WeatherStyle.colOnSurface, 0.055);
                    root.roundedRect(ctx, 2, top + i * rowHeight, canvas.width - 4, rowHeight, 8);
                    ctx.fill();
                }

                if (day.label) {
                    ctx.fillStyle = WeatherStyle.colOnSurface;
                    ctx.font = `500 10.5px "${WeatherStyle.chartFont}"`;
                    ctx.textAlign = "left";
                    ctx.textBaseline = "middle";
                    ctx.fillText(String(day.label), 4, y - 6);
                }
                if (day.date) {
                    ctx.fillStyle = WeatherStyle.colSubtext;
                    ctx.font = `400 9px "${WeatherStyle.chartFont}"`;
                    ctx.textAlign = "left";
                    ctx.textBaseline = "middle";
                    ctx.fillText(String(day.date), 4, y + 8);
                }

                ctx.beginPath();
                ctx.lineCap = "round";
                ctx.lineWidth = 5;
                ctx.strokeStyle = WeatherStyle.alpha(WeatherStyle.colOutline, 0.7);
                ctx.moveTo(trackX, y);
                ctx.lineTo(trackX + trackWidth, y);
                ctx.stroke();

                const minValue = day.min !== null && Number.isFinite(Number(day.min)) ? Number(day.min) : minimum;
                const maxValue = day.max !== null && Number.isFinite(Number(day.max)) ? Number(day.max) : maximum;
                const startX = trackX + (Math.max(minimum, Math.min(maximum, minValue)) - minimum) / (maximum - minimum) * trackWidth;
                const endX = trackX + (Math.max(minimum, Math.min(maximum, maxValue)) - minimum) / (maximum - minimum) * trackWidth;
                const width = Math.max(6, endX - startX);

                const gradient = ctx.createLinearGradient(startX, 0, startX + width, 0);
                gradient.addColorStop(0, WeatherStyle.alpha(WeatherStyle.colTertiary, 0.92));
                gradient.addColorStop(1, WeatherStyle.alpha(WeatherStyle.colPrimary, 0.92));
                ctx.fillStyle = gradient;
                root.roundedRect(ctx, startX, y - 4, width, 8, 4);
                ctx.fill();

                ctx.beginPath();
                ctx.arc(startX, y, 3.5, 0, Math.PI * 2);
                ctx.fillStyle = WeatherStyle.colTertiary;
                ctx.fill();
                ctx.beginPath();
                ctx.arc(startX + width, y, 3.5, 0, Math.PI * 2);
                ctx.fillStyle = WeatherStyle.colPrimary;
                ctx.fill();

                ctx.fillStyle = WeatherStyle.colOnSurfaceVariant;
                ctx.font = `500 10px "${WeatherStyle.chartFont}"`;
                ctx.textAlign = "right";
                ctx.textBaseline = "middle";
                const minText = day.minLabel ? String(day.minLabel) : "--";
                const maxText = day.maxLabel ? String(day.maxLabel) : "--";
                ctx.fillText(`${minText}  ${maxText}`, canvas.width - 4, y);
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: mouse => {
            if (!root.days || root.days.length === 0) {
                root.hoverIndex = -1;
                return;
            }
            const index = Math.floor((mouse.y - 9) / root.rowHeight);
            root.hoverIndex = index >= 0 && index < root.days.length ? index : -1;
        }
        onExited: root.hoverIndex = -1
    }
}
