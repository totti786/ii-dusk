import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.ii.qanun

/**
 * A compact staff renderer used by the library preview, the composer and the
 * flashcards. It is deliberately not a full notation engine: one voice, one
 * staff, bar lines, accidentals, dots, flags and ties.
 *
 * Notes are objects {letter, octave, alter, duration, rest, dotted, tie}.
 * Clicking the staff emits the natural letter/octave under the pointer so the
 * composer can append a note with whatever accidental is selected.
 */
Item {
    id: root

    property var notes: []
    property string clef: "treble"
    property int keySignature: 0
    property var timeSignature: [4, 4]
    property bool editable: false
    property bool centerSingle: false
    property bool showBarLines: true
    property bool showTimeSignature: true
    property real preferredBeatWidth: 34
    property real lineSpacing: 11
    property real desiredSystemHeight: 118
    property color lineColor: Qt.alpha(QanunStyle.colOnSurface, 0.52)
    property color noteColor: QanunStyle.colOnSurface
    property color accentColor: QanunStyle.colPrimary
    property color selectionColor: QanunStyle.colTertiary
    property int accentIndex: -1
    property bool animate: true

    signal staffClicked(string letter, int octave, real y)
    signal noteActivated(int index)

    readonly property var notesArray: Array.from(root.notes ?? [])
    readonly property real measureBeats: Math.max(1, Number(root.timeSignature?.[0] ?? 4) * 4 / Math.max(1, Number(root.timeSignature?.[1] ?? 4)))
    readonly property real totalBeats: {
        let sum = 0;
        for (const note of root.notesArray)
            sum += Math.max(0.05, Number(note.duration ?? 1));
        return sum;
    }
    readonly property int totalMeasures: Math.max(1, Math.ceil(root.totalBeats / root.measureBeats - 0.0001))

    readonly property var geometry: {
        const left = 72;
        const right = 22;
        const canFit = Math.max(180, root.width - left - right);
        const measureWidth = Math.max(112, root.measureBeats * root.preferredBeatWidth);
        let perSystem = Math.max(1, Math.floor(canFit / measureWidth));
        if (root.centerSingle)
            perSystem = 1;
        const systems = root.centerSingle ? 1 : Math.max(1, Math.ceil(root.totalMeasures / perSystem));
        const beatsPerSystem = perSystem * root.measureBeats;
        const beatWidth = root.centerSingle
            ? canFit / Math.max(1, root.measureBeats)
            : canFit / Math.max(1, beatsPerSystem);
        const systemHeight = Math.max(root.desiredSystemHeight, root.lineSpacing * 13);
        const top = 20;
        return {
            left: left, right: right, canFit: canFit,
            perSystem: perSystem, systems: systems,
            beatWidth: beatWidth, systemHeight: systemHeight,
            top: top, beatsPerSystem: beatsPerSystem,
            width: root.width,
            height: top * 2 + systems * systemHeight
        };
    }

    implicitHeight: root.geometry.height
    implicitWidth: 420

    function staffTop(system): real {
        return root.geometry.top + system * root.geometry.systemHeight + 18;
    }

    function bottomLineY(system): real {
        return root.staffTop(system) + root.lineSpacing * 4;
    }

    function bottomStep(): int {
        return root.clef === "bass" ? 18 : 30; // G2 / E4
    }

    function stepForNote(note): int {
        const letters = ["C", "D", "E", "F", "G", "A", "B"];
        const index = letters.indexOf(String(note.letter ?? "C").toUpperCase());
        return Number(note.octave ?? 4) * 7 + Math.max(0, index);
    }

    function yForStep(step, system): real {
        return root.bottomLineY(system) - (Number(step) - root.bottomStep()) * root.lineSpacing / 2;
    }

    function noteX(note, index, system): real {
        if (root.centerSingle)
            return root.width / 2;
        let before = 0;
        for (let i = 0; i < index; ++i)
            before += Math.max(0.05, Number(root.notesArray[i].duration ?? 1));
        const inSystem = before - system * root.geometry.beatsPerSystem;
        return root.geometry.left + 8 + inSystem * root.geometry.beatWidth;
    }

    function noteSystem(index): int {
        if (root.centerSingle)
            return 0;
        let before = 0;
        for (let i = 0; i < index; ++i)
            before += Math.max(0.05, Number(root.notesArray[i].duration ?? 1));
        return Math.floor(before / root.geometry.beatsPerSystem);
    }

    function clickPitch(mouseY): var {
        const system = Math.max(0, Math.min(root.geometry.systems - 1,
            Math.floor((mouseY - root.geometry.top) / root.geometry.systemHeight)));
        const bottom = root.bottomLineY(system);
        const half = root.lineSpacing / 2;
        let step = root.bottomStep() + Math.round((bottom - mouseY) / half);
        step = Math.max(0, Math.min(120, step));
        const letters = ["C", "D", "E", "F", "G", "A", "B"];
        return {
            letter: letters[step % 7],
            octave: Math.floor(step / 7),
            step: step,
            system: system
        };
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        renderTarget: Canvas.FramebufferObject

        function drawStaff(system) {
            const ctx = getContext("2d");
            const top = root.staffTop(system);
            const left = root.geometry.left;
            const right = root.width - root.geometry.right;
            ctx.save();
            ctx.strokeStyle = root.lineColor;
            ctx.lineWidth = 1;
            for (let i = 0; i < 5; ++i) {
                const y = Math.round(top + i * root.lineSpacing) + 0.5;
                ctx.beginPath();
                ctx.moveTo(left, y);
                ctx.lineTo(right, y);
                ctx.stroke();
            }
            // Bar lines. Each system starts at a bar line and closes at its end.
            if (root.showBarLines) {
                ctx.globalAlpha = 0.72;
                for (let measure = 0; measure <= root.geometry.perSystem; ++measure) {
                    const x = left + measure * root.measureBeats * root.geometry.beatWidth;
                    if (x > right + 1)
                        break;
                    ctx.beginPath();
                    ctx.moveTo(Math.round(x) + 0.5, top);
                    ctx.lineTo(Math.round(x) + 0.5, top + root.lineSpacing * 4);
                    ctx.stroke();
                }
                ctx.globalAlpha = 1;
            }

            // Clef.
            ctx.fillStyle = root.lineColor;
            ctx.font = "42px 'Noto Music'";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillText(root.clef === "bass" ? "\uD834\uDD22" : "\uD834\uDD1E",
                left - 25, top + root.lineSpacing * 2 + 2);

            // Key signature.
            const sharps = [3, 0, 4, 1, 5, 2, 6];
            const flats = [6, 2, 5, 1, 4, 0, 3];
            const count = Math.min(7, Math.abs(Number(root.keySignature) || 0));
            if (count > 0) {
                const order = Number(root.keySignature) > 0 ? sharps : flats;
                ctx.font = "15px 'Noto Sans'";
                for (let i = 0; i < count; ++i) {
                    const letterIndex = order[i];
                    const octave = root.clef === "bass"
                        ? (letterIndex >= 4 ? 3 : 2)
                        : (letterIndex >= 4 ? 5 : 4);
                    const step = octave * 7 + letterIndex;
                    const y = root.yForStep(step, system);
                    ctx.fillText(Number(root.keySignature) > 0 ? "♯" : "♭",
                        left - 3 + i * 9, y + 1);
                }
            }

            // Time signature.
            if (root.showTimeSignature) {
                const numerator = Number(root.timeSignature?.[0] ?? 4);
                const denominator = Number(root.timeSignature?.[1] ?? 4);
                ctx.font = "bold 15px 'Noto Sans'";
                ctx.fillStyle = root.lineColor;
                ctx.fillText(String(numerator), left + 17, top + root.lineSpacing * 1.35);
                ctx.fillText(String(denominator), left + 17, top + root.lineSpacing * 3.05);
            }
            ctx.restore();
        }

        function drawAccidental(note, x, y) {
            const ctx = getContext("2d");
            const alter = Number(note.alter ?? 0);
            if (Math.abs(alter) < 0.01)
                return;
            ctx.save();
            ctx.fillStyle = root.noteColor;
            ctx.font = "15px 'Noto Sans'";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            let text = "";
            if (Math.abs(alter - 0.5) < 0.01) text = "½♯";
            else if (Math.abs(alter + 0.5) < 0.01) text = "½♭";
            else if (Math.abs(alter - 1) < 0.01) text = "♯";
            else if (Math.abs(alter + 1) < 0.01) text = "♭";
            else if (Math.abs(alter - 2) < 0.01) text = "𝄪";
            else if (Math.abs(alter + 2) < 0.01) text = "𝄫";
            if (text)
                ctx.fillText(text, x - 13, y + 1);
            ctx.restore();
        }

        function drawLedgerLines(x, y, system) {
            const ctx = getContext("2d");
            const top = root.staffTop(system);
            const bottom = top + root.lineSpacing * 4;
            if (y < top - 1) {
                ctx.strokeStyle = root.lineColor;
                ctx.lineWidth = 1;
                for (let ly = top - root.lineSpacing; ly >= y - 1; ly -= root.lineSpacing) {
                    ctx.beginPath();
                    ctx.moveTo(x - 10, Math.round(ly) + 0.5);
                    ctx.lineTo(x + 10, Math.round(ly) + 0.5);
                    ctx.stroke();
                }
            } else if (y > bottom + 1) {
                ctx.strokeStyle = root.lineColor;
                ctx.lineWidth = 1;
                for (let ly = bottom + root.lineSpacing; ly <= y + 1; ly += root.lineSpacing) {
                    ctx.beginPath();
                    ctx.moveTo(x - 10, Math.round(ly) + 0.5);
                    ctx.lineTo(x + 10, Math.round(ly) + 0.5);
                    ctx.stroke();
                }
            }
        }

        function drawNote(note, index, system) {
            const ctx = getContext("2d");
            const x = root.noteX(note, index, system);
            if (x > root.width - root.geometry.right + 16)
                return;
            if (!note || note.rest) {
                ctx.save();
                ctx.fillStyle = root.lineColor;
                ctx.font = "22px 'Noto Music'";
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";
                const restY = root.staffTop(system) + root.lineSpacing * 2;
                ctx.fillText("\uD834\uDD3D", x, restY);
                ctx.restore();
                return;
            }
            const step = root.stepForNote(note);
            const y = root.yForStep(step, system);
            drawLedgerLines(x, y, system);
            const duration = Number(note.duration ?? 1);
            const hollow = duration >= 2;
            const hasStem = duration < 4;
            const flags = duration <= 0.25 ? 2 : duration <= 0.5 ? 1 : 0;
            const stemUp = y > root.staffTop(system) + root.lineSpacing * 2;
            const col = index === root.accentIndex ? root.accentColor
                : index === root.accentIndex ? root.accentColor : root.noteColor;

            ctx.save();
            ctx.strokeStyle = col;
            ctx.fillStyle = col;
            ctx.lineWidth = 1.6;
            // Notehead.
            ctx.save();
            ctx.translate(x, y);
            ctx.rotate(-0.32);
            ctx.scale(1.0, 0.72);
            ctx.beginPath();
            ctx.arc(0, 0, 5.9, 0, Math.PI * 2);
            if (hollow) {
                ctx.fillStyle = QanunStyle.colBackground;
                ctx.fill();
                ctx.stroke();
            } else {
                ctx.fill();
            }
            ctx.restore();

            // Stem.
            const stemLength = root.lineSpacing * 3.1;
            const stemX = x + (stemUp ? 5.3 : -5.3);
            if (hasStem) {
                ctx.beginPath();
                ctx.moveTo(stemX, y + (stemUp ? -1.2 : 1.2));
                ctx.lineTo(stemX, y + (stemUp ? -stemLength : stemLength));
                ctx.stroke();
            }
            // Flags.
            for (let flag = 0; flag < flags; ++flag) {
                const fy = y + (stemUp ? -stemLength + flag * 7 : stemLength - flag * 7);
                ctx.beginPath();
                ctx.moveTo(stemX, fy);
                ctx.quadraticCurveTo(stemX + (stemUp ? 12 : 12), fy + (stemUp ? 5 : -5),
                    stemX + 8, fy + (stemUp ? 13 : -13));
                ctx.stroke();
            }
            // Dot.
            if (note.dotted) {
                ctx.beginPath();
                ctx.arc(x + 11, y - (Math.floor(step / 2) % 2 === 0 ? 0 : root.lineSpacing / 2), 1.9, 0, Math.PI * 2);
                ctx.fill();
            }
            ctx.restore();
            drawAccidental(note, x, y);
            if (note.tie && index > 0) {
                const previous = root.notesArray[index - 1];
                if (previous && previous.letter === note.letter && previous.octave === note.octave) {
                    const px = root.noteX(previous, index - 1, system);
                    const py = root.yForStep(root.stepForNote(previous), system);
                    ctx.save();
                    ctx.strokeStyle = col;
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    ctx.moveTo(px + 7, py + 7);
                    ctx.quadraticCurveTo((px + x) / 2, py + 15, x - 7, y + 7);
                    ctx.stroke();
                    ctx.restore();
                }
            }
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            const g = root.geometry;
            const count = g.systems;
            for (let system = 0; system < count; ++system)
                drawStaff(system);
            if (root.centerSingle) {
                if (root.notesArray.length > 0)
                    drawNote(root.notesArray[0], 0, 0);
            } else {
                for (let i = 0; i < root.notesArray.length; ++i) {
                    const system = root.noteSystem(i);
                    if (system < g.systems)
                        drawNote(root.notesArray[i], i, system);
                }
            }
        }
    }

    onNotesChanged: canvas.requestPaint()
    onClefChanged: canvas.requestPaint()
    onKeySignatureChanged: canvas.requestPaint()
    onTimeSignatureChanged: canvas.requestPaint()
    onAccentIndexChanged: canvas.requestPaint()
    onAccentColorChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    MouseArea {
        anchors.fill: parent
        enabled: root.editable
        hoverEnabled: root.editable
        cursorShape: root.editable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: mouse => {
            if (!root.editable)
                return;
            const pitch = root.clickPitch(mouse.y);
            root.staffClicked(pitch.letter, pitch.octave, mouse.y);
        }
    }
}
