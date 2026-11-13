import QtQuick
import qs.modules.common
import ".."
import "../../../../services/WeatherAppLogic.js" as Logic

/**
 * A half-dial for US AQI. The scale is 0–300 because above 300 "hazardous" is a
 * different conversation than the number on the dial; the label carries that.
 */
Item {
    id: root

    property var value: null
    property int decimals: 0

    implicitHeight: 158
    implicitWidth: 220

    readonly property var category: Logic.aqiCategory(root.value)
    readonly property color accent: WeatherStyle.toneColor(root.category.tone)

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            target: root
            function onValueChanged() { canvas.requestPaint(); }
        }

        onPaint: {
            const ctx = canvas.getContext("2d");
            ctx.clearRect(0, 0, canvas.width, canvas.height);

            const centerX = canvas.width / 2;
            const baseline = canvas.height - 34;
            const radius = Math.max(24, Math.min(canvas.width / 2 - 26, 64));
            const start = Math.PI;
            const end = Math.PI * 2;

            ctx.lineCap = "round";
            ctx.lineWidth = 11;
            ctx.strokeStyle = WeatherStyle.alpha(WeatherStyle.colOutline, 0.7);
            ctx.beginPath();
            ctx.arc(centerX, baseline, radius, start, end);
            ctx.stroke();

            const hasValue = root.value !== null && root.value !== undefined && Number.isFinite(Number(root.value));
            const normalized = hasValue ? Math.max(0, Math.min(1, Number(root.value) / 300)) : 0;
            if (hasValue && normalized > 0) {
                ctx.beginPath();
                ctx.strokeStyle = root.accent;
                ctx.arc(centerX, baseline, radius, start, start + Math.PI * normalized);
                ctx.stroke();

                const angle = start + Math.PI * normalized;
                const markerX = centerX + Math.cos(angle) * radius;
                const markerY = baseline + Math.sin(angle) * radius;
                ctx.beginPath();
                ctx.arc(markerX, markerY, 5, 0, Math.PI * 2);
                ctx.fillStyle = WeatherStyle.colSurface;
                ctx.fill();
                ctx.lineWidth = 2;
                ctx.strokeStyle = root.accent;
                ctx.stroke();
            }

            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillStyle = WeatherStyle.colSubtext;
            ctx.font = `500 9px "${WeatherStyle.chartFont}"`;
            ctx.fillText("US AQI", centerX, baseline - radius * 0.78);

            ctx.fillStyle = WeatherStyle.colOnSurface;
            ctx.font = `600 28px "${WeatherStyle.chartFont}"`;
            ctx.fillText(hasValue ? String(Math.round(Number(root.value))) : "--", centerX, baseline - 22);

            ctx.fillStyle = root.accent;
            ctx.font = `500 10px "${WeatherStyle.chartFont}"`;
            ctx.fillText(root.category.short, centerX, baseline + 2);

            ctx.fillStyle = WeatherStyle.colSubtext;
            ctx.font = `400 8px "${WeatherStyle.chartFont}"`;
            ctx.textAlign = "left";
            ctx.fillText("0", centerX - radius - 2, baseline + 15);
            ctx.textAlign = "right";
            ctx.fillText("300+", centerX + radius + 2, baseline + 15);
        }
    }
}
