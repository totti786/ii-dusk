import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.grit.components

/**
 * A donut of focus time. Each slice is a tag, each slice keeps the tag's colour,
 * and the middle carries the total for the selected range.
 */
Item {
    id: root

    property var slices: []
    property real thickness: 24
    property color colTrack: GritStyle.colField
    property string centerValue: ""
    property string centerLabel: ""

    implicitWidth: 190
    implicitHeight: 190

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        renderTarget: Canvas.FramebufferObject

        function repaint() {
            canvas.requestPaint();
        }

        onWidthChanged: repaint()
        onHeightChanged: repaint()
        onVisibleChanged: if (visible) repaint()

        Connections {
            target: root
            function onSlicesChanged() { canvas.repaint(); }
            function onColTrackChanged() { canvas.repaint(); }
            function onThicknessChanged() { canvas.repaint(); }
        }

        onPaint: {
            const ctx = canvas.getContext("2d");
            ctx.clearRect(0, 0, canvas.width, canvas.height);
            const size = Math.min(canvas.width, canvas.height);
            const cx = canvas.width / 2;
            const cy = canvas.height / 2;
            const radius = Math.max(0, size / 2 - root.thickness / 2 - 2);
            if (radius <= 0)
                return;

            ctx.lineWidth = root.thickness;
            ctx.lineCap = "butt";
            ctx.strokeStyle = root.colTrack;
            ctx.beginPath();
            ctx.arc(cx, cy, radius, 0, Math.PI * 2);
            ctx.stroke();

            let total = 0;
            for (const slice of Array.from(root.slices ?? []))
                total += Math.max(0, Number(slice.value ?? 0));
            if (total <= 0)
                return;

            let start = -Math.PI / 2;
            for (const slice of Array.from(root.slices ?? [])) {
                const value = Math.max(0, Number(slice.value ?? 0));
                if (value <= 0)
                    continue;
                const sweep = value / total * Math.PI * 2;
                ctx.strokeStyle = slice.color ?? GritStyle.colPrimary;
                ctx.beginPath();
                ctx.arc(cx, cy, radius, start, start + sweep);
                ctx.stroke();
                start += sweep;
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 0

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: root.centerValue
            font.family: GritStyle.fontNumbers
            font.variableAxes: GritStyle.axesDigitsBold
            font.pixelSize: Math.max(20, Math.min(34, root.width * 0.18))
            color: GritStyle.colOnSurface
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            visible: root.centerLabel.length > 0
            text: root.centerLabel
            font.pixelSize: GritStyle.textSmall
            color: GritStyle.colSubtext
        }
    }
}
