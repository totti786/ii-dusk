import QtQuick

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// A 270° gauge with the value in the middle. The arc eases to each new reading.
Item {
    id: root

    property real value: 0
    property real maxValue: 100
    property color color: ClockStyle.colPrimary
    property string text: ""
    property string caption: ""
    property real thickness: 12

    property real shown: 0
    readonly property real sweep: Math.PI * 1.5
    readonly property real start: Math.PI * 0.75

    Behavior on shown {
        enabled: !ClockStyle.reducedMotion
        NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
    }
    onValueChanged: root.shown = Math.max(0, Math.min(1, root.value / root.maxValue))
    Component.onCompleted: root.shown = Math.max(0, Math.min(1, root.value / root.maxValue))
    onShownChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            const r = Math.min(width, height) / 2 - root.thickness / 2 - 1;
            const cx = width / 2, cy = height / 2;
            ctx.lineCap = "round";
            ctx.lineWidth = root.thickness;
            const t = ClockStyle.colSurfaceHighest;
            ctx.strokeStyle = `rgb(${Math.round(t.r * 255)},${Math.round(t.g * 255)},${Math.round(t.b * 255)})`;
            ctx.beginPath();
            ctx.arc(cx, cy, r, root.start, root.start + root.sweep);
            ctx.stroke();
            if (root.shown > 0.002) {
                const c = root.color;
                ctx.strokeStyle = `rgb(${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)})`;
                ctx.beginPath();
                ctx.arc(cx, cy, r, root.start, root.start + root.sweep * root.shown);
                ctx.stroke();
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 0
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.text
            color: ClockStyle.colOnBackground
            font.pixelSize: Math.max(18, root.width * 0.2)
            font.weight: Font.DemiBold
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.caption !== ""
            text: root.caption
            color: ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textSmall
        }
    }
}
