import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/// A smooth area chart of one number per week, with a readout that follows the pointer.
Item {
    id: root

    property var values: []
    property var dates: []
    property color tone: Appearance.colors.colPrimary
    property int hoverIndex: -1
    readonly property real peak: Math.max(1, ...root.values)
    readonly property var ticks: [0, Math.round(root.peak / 2), root.peak]
    readonly property int peakIndex: root.values.indexOf(Math.max(...root.values))

    onValuesChanged: canvas.requestPaint()
    onHoverIndexChanged: canvas.requestPaint()
    onToneChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    // The line grows from the left when the data arrives
    property real draw: 0
    NumberAnimation on draw { id: grow; from: 0; to: 1; duration: 1100; easing.type: Easing.OutCubic; running: root.values.length > 0 }
    onDrawChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors { fill: parent; leftMargin: 34; topMargin: 22; bottomMargin: 20 }
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const v = root.values, n = v.length;
            if (n < 2) return;
            const w = width, h = height - 6, step = w / (n - 1);
            const x = i => i * step;
            const y = i => 4 + h - (v[i] / root.peak) * (h - 8);
            const y2 = t => 4 + h - (t / root.peak) * (h - 8);
            const shown = Math.max(1, Math.round((n - 1) * root.draw));
            ctx.lineWidth = 1;
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.08);
            for (const t of root.ticks) {
                const ty = Math.round(y2(t)) + 0.5;
                ctx.beginPath();
                ctx.moveTo(0, ty);
                ctx.lineTo(w, ty);
                ctx.stroke();
            }
            const c = root.tone;
            const grad = ctx.createLinearGradient(0, 0, 0, h);
            grad.addColorStop(0, Qt.rgba(c.r, c.g, c.b, 0.38));
            grad.addColorStop(1, Qt.rgba(c.r, c.g, c.b, 0.02));
            ctx.beginPath();
            ctx.moveTo(0, h + 4);
            ctx.lineTo(x(0), y(0));
            for (let i = 1; i <= shown; i++) {
                const mx = (x(i - 1) + x(i)) / 2;
                ctx.bezierCurveTo(mx, y(i - 1), mx, y(i), x(i), y(i));
            }
            ctx.lineTo(x(shown), h + 4);
            ctx.closePath();
            ctx.fillStyle = grad;
            ctx.fill();
            ctx.beginPath();
            ctx.moveTo(x(0), y(0));
            for (let i = 1; i <= shown; i++) {
                const mx = (x(i - 1) + x(i)) / 2;
                ctx.bezierCurveTo(mx, y(i - 1), mx, y(i), x(i), y(i));
            }
            ctx.lineWidth = 2.5;
            ctx.lineJoin = "round";
            ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 1);
            ctx.stroke();
            if (root.hoverIndex >= 0 && root.hoverIndex <= shown) {
                const hx = x(root.hoverIndex), hy = y(root.hoverIndex);
                ctx.beginPath();
                ctx.moveTo(hx, 0);
                ctx.lineTo(hx, h + 4);
                ctx.lineWidth = 1;
                ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.35);
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(hx, hy, 5, 0, Math.PI * 2);
                ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 1);
                ctx.fill();
            }
        }
    }

    StyledText {
        anchors { left: parent.left; top: parent.top }
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: root.hoverIndex >= 0 ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant
        text: {
            if (root.hoverIndex < 0 || root.hoverIndex >= root.values.length)
                return Translation.tr("Contributions per week");
            const d = root.dates[root.hoverIndex]?.[0] ?? "";
            const when = d ? new Date(d + "T00:00:00").toLocaleDateString(Qt.locale(), "d MMM yyyy") : "";
            return Translation.tr("Week of %1 · %2 contributions").arg(when).arg(root.values[root.hoverIndex]);
        }
    }

    // y axis: the same numbers the grid lines sit at
    Repeater {
        model: root.ticks
        delegate: StyledText {
            required property real modelData
            x: 0
            width: 28
            horizontalAlignment: Text.AlignRight
            y: canvas.y + 4 + (canvas.height - 6) - (modelData / root.peak) * ((canvas.height - 6) - 8) - height / 2
            text: String(modelData)
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    // x axis: a label where each month starts
    Repeater {
        model: root.values.length
        delegate: StyledText {
            required property int index
            readonly property string d: root.dates[index]?.[0] ?? ""
            readonly property var dt: d ? new Date(d + "T00:00:00") : null
            readonly property var prev: index > 0 && root.dates[index - 1]?.[0] ? new Date(root.dates[index - 1][0] + "T00:00:00") : null
            visible: dt !== null && (index === 0 || (prev && prev.getMonth() !== dt.getMonth())) && x + width <= root.width
            x: canvas.x + (root.values.length > 1 ? index / (root.values.length - 1) : 0) * canvas.width
            anchors.bottom: parent.bottom
            text: dt ? dt.toLocaleDateString(Qt.locale(), "MMM") : ""
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    // the best week, called out on the line
    StyledText {
        visible: root.hoverIndex < 0 && root.values.length > 1 && root.draw >= 1
        x: Math.max(canvas.x, Math.min(root.width - width, canvas.x + root.peakIndex / (root.values.length - 1) * canvas.width - width / 2))
        y: canvas.y + 4 - height - 1
        text: Translation.tr("best: %1").arg(root.peak)
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Bold
        color: Appearance.colors.colPrimary
    }

    MouseArea {
        anchors.fill: canvas
        hoverEnabled: true
        onPositionChanged: mouse => {
            const n = root.values.length;
            root.hoverIndex = n < 2 ? -1 : Math.max(0, Math.min(n - 1, Math.round(mouse.x / width * (n - 1))));
        }
        onExited: root.hoverIndex = -1
    }
}
