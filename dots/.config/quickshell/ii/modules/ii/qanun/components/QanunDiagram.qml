import QtQuick
import qs.services
import qs.modules.common
import qs.modules.ii.qanun

/**
 * A playable qanun diagram: 26 diatonically tuned courses from G2 at the bottom
 * to D6 at the top, with the mandal pattern of the Arabic instrument. Clicking
 * a course previews its pitch; scale degrees light up in the primary colour.
 */
Item {
    id: root

    property var highlightPitchClasses: []
    property var liftedMandals: ({})
    property int selectedIndex: -1
    property bool interactive: true
    property bool showLabels: true
    property color woodColor: QanunStyle.colWood
    property color stringColor: QanunStyle.colString
    property color mandalColor: QanunStyle.colMandala
    property color highlightColor: QanunStyle.colSelectedString

    implicitWidth: 330
    implicitHeight: 560
    clip: true

    // The mandal field is a plain rectangular frame: no tinted fill, no
    // trapezoid body and no shadow behind the dots.
    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(QanunStyle.colOnSurface, 0.10)
    }

    readonly property var strings: QanunData.qanunStrings
    readonly property real insetTop: 28
    readonly property real insetBottom: 28
    readonly property real stringTop: insetTop + 10
    readonly property real stringBottom: height - insetBottom - 10
    readonly property real stringSpacing: (stringBottom - stringTop) / Math.max(1, strings.length - 1)

    function yFor(index): real {
        // The first course is the bottom string (G2); the diagram is played
        // from the bottom up, like the instrument.
        return root.stringBottom - index * root.stringSpacing;
    }

    function indexAt(y): int {
        return Math.max(0, Math.min(root.strings.length - 1, Math.round((root.stringBottom - y) / root.stringSpacing)));
    }

    function isHighlighted(index): bool {
        const item = root.strings[index];
        if (!item)
            return false;
        return root.highlightPitchClasses.some(pc => (item.midi % 12) === ((pc % 12) + 12) % 12);
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        renderTarget: Canvas.FramebufferObject

        function mandalXs(count): var {
            if (count <= 0) return [];
            if (count === 1) return [0.53];
            if (count === 2) return [0.42, 0.65];
            if (count === 3) return [0.32, 0.49, 0.66];
            return [0.25, 0.40, 0.55, 0.70];
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (width < 40 || height < 80)
                return;

            // Strings and mandals. The rectangular frame belongs to the
            // transparent QML border behind this canvas.

            // Strings and mandals.
            for (let i = 0; i < root.strings.length; ++i) {
                const item = root.strings[i];
                const y = root.yFor(i);
                const selected = root.selectedIndex === i;
                const highlighted = root.isHighlighted(i);
                const color = selected ? root.highlightColor
                    : highlighted ? Qt.alpha(root.highlightColor, 0.92) : root.stringColor;
                ctx.strokeStyle = color;
                ctx.lineWidth = selected ? 2.1 : highlighted ? 1.35 : 0.85;
                ctx.beginPath();
                ctx.moveTo(width * 0.12, y);
                ctx.lineTo(width * 0.86, y);
                ctx.stroke();

                // Selecting a course previews its pitch and brightens the
                // string itself, never the un-lifted mandal dots.

                // Mandal dots sit along the course; their count is the
                // instrument's own pattern, not a uniform grid. A lit dot is a
                // mandal engaged by the current scale.
                const xs = mandalXs(Number(item.mandals ?? 0));
                const lifted = root.liftedMandals[i] ?? [];
                for (let dotIndex = 0; dotIndex < xs.length; ++dotIndex) {
                    const unit = xs[dotIndex];
                    const x = width * (0.24 + unit * 0.48);
                    const isLifted = lifted.indexOf(dotIndex) >= 0;
                    ctx.beginPath();
                    ctx.arc(x, y, isLifted ? 4.5 : 2.9, 0, Math.PI * 2);
                    ctx.fillStyle = isLifted ? root.highlightColor
                        : QanunStyle.colMandalOff;
                    ctx.fill();
                    if (isLifted) {
                        ctx.strokeStyle = Qt.alpha(root.highlightColor, 0.42);
                        ctx.lineWidth = 1.6;
                        ctx.beginPath();
                        ctx.arc(x, y, 7.1, 0, Math.PI * 2);
                        ctx.stroke();
                    }
                }

                if (root.showLabels && root.stringSpacing > 8) {
                    ctx.fillStyle = selected ? root.highlightColor
                        : highlighted ? root.highlightColor : Qt.alpha(QanunStyle.colOnSurface, 0.68);
                    ctx.font = (selected ? "600 " : "500 ") + Math.max(7, Math.min(10, root.stringSpacing * 0.58)) + "px 'Noto Sans'";
                    ctx.textAlign = "right";
                    ctx.textBaseline = "middle";
                    ctx.fillText(item.name, width * 0.095, y + 0.5);
                }
            }

            // No bridge/nut rails: they read as dark bars over the dot field.
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: root.interactive
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: mouse => {
            if (!root.interactive)
                return;
            const index = root.indexAt(mouse.y);
            root.selectedIndex = index;
            if (index >= 0 && index < root.strings.length)
                QanunStore.playTone(root.strings[index].midi, 0.8);
        }
    }

    onHighlightPitchClassesChanged: canvas.requestPaint()
    onLiftedMandalsChanged: canvas.requestPaint()
    onSelectedIndexChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
}
