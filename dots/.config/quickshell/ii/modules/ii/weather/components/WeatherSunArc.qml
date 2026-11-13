import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import ".."
import "../../../../services/WeatherAppLogic.js" as Logic

/**
 * Sun or moon above the horizon, with the two times that bound it. The arc is a real
 * clock: the dot's position is where the body is now, not an animation.
 */
Item {
    id: root

    property real sunrise: 0
    property real sunset: 0
    property real moonrise: 0
    property real moonset: 0
    property real nextSunrise: 0
    property real now: Date.now()
    property bool isDay: true
    property int offset: 0
    property bool use24h: true

    implicitHeight: 158

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.now = Date.now()
    }

    readonly property real progress: {
        if (root.isDay) {
            if (!root.sunrise || !root.sunset || root.sunset <= root.sunrise)
                return 0.5;
            return Math.max(0, Math.min(1, (root.now - root.sunrise) / (root.sunset - root.sunrise)));
        }
        if (root.moonrise && root.moonset) {
            let start = root.moonrise;
            let end = root.moonset;
            if (end < start)
                end += 86400000;
            let time = root.now;
            if (time < start)
                time += 86400000;
            if (time >= start && time <= end)
                return Math.max(0, Math.min(1, (time - start) / (end - start)));
        }
        const next = root.nextSunrise || (root.sunrise + 86400000);
        if (!root.sunset || !next || next <= root.sunset)
            return 0.5;
        return Math.max(0, Math.min(1, (root.now - root.sunset) / (next - root.sunset)));
    }

    Canvas {
        id: canvas
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: parent.height - 32
        antialiasing: true
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            target: root
            function onNowChanged() { canvas.requestPaint(); }
            function onIsDayChanged() { canvas.requestPaint(); }
        }

        onPaint: {
            const ctx = canvas.getContext("2d");
            ctx.clearRect(0, 0, canvas.width, canvas.height);
            const baseline = canvas.height - 4;
            const centerX = canvas.width / 2;
            const radius = Math.max(20, Math.min(canvas.width / 2 - 28, 76));

            ctx.beginPath();
            ctx.lineCap = "round";
            ctx.lineWidth = 1;
            ctx.strokeStyle = WeatherStyle.alpha(WeatherStyle.colOutline, 0.65);
            ctx.setLineDash([3, 5]);
            ctx.arc(centerX, baseline, radius, Math.PI, Math.PI * 2);
            ctx.stroke();
            ctx.setLineDash([]);

            ctx.beginPath();
            ctx.strokeStyle = WeatherStyle.alpha(WeatherStyle.colOutline, 0.9);
            ctx.lineWidth = 1;
            ctx.moveTo(centerX - radius - 14, baseline);
            ctx.lineTo(centerX + radius + 14, baseline);
            ctx.stroke();

            const angle = Math.PI + Math.PI * root.progress;
            const bodyX = centerX + Math.cos(angle) * radius;
            const bodyY = baseline + Math.sin(angle) * radius;
            const accent = root.isDay ? WeatherStyle.colPrimary : WeatherStyle.colTertiary;

            ctx.beginPath();
            ctx.lineWidth = 3;
            ctx.strokeStyle = WeatherStyle.alpha(accent, 0.35);
            ctx.arc(centerX, baseline, radius, Math.PI, angle);
            ctx.stroke();

            const glow = ctx.createRadialGradient(bodyX, bodyY, 1, bodyX, bodyY, 18);
            glow.addColorStop(0, WeatherStyle.alpha(accent, 0.34));
            glow.addColorStop(1, WeatherStyle.alpha(accent, 0));
            ctx.beginPath();
            ctx.arc(bodyX, bodyY, 18, 0, Math.PI * 2);
            ctx.fillStyle = glow;
            ctx.fill();

            ctx.beginPath();
            ctx.arc(bodyX, bodyY, 6, 0, Math.PI * 2);
            ctx.fillStyle = accent;
            ctx.fill();

            if (!root.isDay) {
                ctx.beginPath();
                ctx.arc(bodyX + 3, bodyY - 2, 5.2, 0, Math.PI * 2);
                ctx.fillStyle = WeatherStyle.colSurface;
                ctx.fill();
            }

            ctx.beginPath();
            ctx.arc(centerX - radius, baseline, 3, 0, Math.PI * 2);
            ctx.fillStyle = WeatherStyle.alpha(WeatherStyle.colOnSurfaceVariant, 0.6);
            ctx.fill();
            ctx.beginPath();
            ctx.arc(centerX + radius, baseline, 3, 0, Math.PI * 2);
            ctx.fillStyle = WeatherStyle.alpha(WeatherStyle.colOnSurfaceVariant, 0.6);
            ctx.fill();
        }
    }

    RowLayout {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        spacing: WeatherStyle.gapSmall

        RowLayout {
            spacing: 4
            MaterialSymbol {
                text: "wb_twilight"
                iconSize: 14
                color: WeatherStyle.colTertiary
            }
            StyledText {
                text: root.sunrise ? Logic.formatTime(root.sunrise, root.offset, root.use24h) : "--"
                font.pixelSize: WeatherStyle.textTiny
                color: WeatherStyle.colOnSurfaceVariant
            }
            StyledText {
                text: "rise"
                font.pixelSize: WeatherStyle.textTiny
                color: WeatherStyle.colSubtext
            }
        }

        Item { Layout.fillWidth: true }

        StyledText {
            text: root.sunrise && root.sunset
                ? `Daylight ${Logic.formatDaylight((root.sunset - root.sunrise) / 1000)}`
                : ""
            font.pixelSize: WeatherStyle.textTiny
            color: WeatherStyle.colSubtext
        }

        Item { Layout.fillWidth: true }

        RowLayout {
            spacing: 4
            StyledText {
                text: "set"
                font.pixelSize: WeatherStyle.textTiny
                color: WeatherStyle.colSubtext
            }
            StyledText {
                text: root.sunset ? Logic.formatTime(root.sunset, root.offset, root.use24h) : "--"
                font.pixelSize: WeatherStyle.textTiny
                color: WeatherStyle.colOnSurfaceVariant
            }
            MaterialSymbol {
                text: "nightlight"
                iconSize: 14
                color: WeatherStyle.colPrimary
            }
        }
    }
}
