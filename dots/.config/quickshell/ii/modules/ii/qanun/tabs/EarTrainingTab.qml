import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.qanun

/**
 * Ear training: intervals, scales/maqamat and chord quality, answered by ear.
 * The page uses the same shape language as the flashcards, but the question is
 * only in sound; the answer grid is the visual part.
 */
Item {
    id: root

    property bool compact: false
    property bool wide: false

    readonly property var config: QanunStore.settings.earTraining ?? ({})
    readonly property string mode: String(root.config.mode ?? "intervals")
    readonly property string intervalDirection: String(root.config.intervalDirection ?? "ascending")
    readonly property string scaleSource: String(root.config.scaleSource ?? "maqams")
    readonly property string scaleDirection: String(root.config.scaleDirection ?? "ascending")
    readonly property string chordSet: String(root.config.chordSet ?? "triads")
    readonly property bool singleNoteAccidentals: Boolean(root.config.singleNoteAccidentals ?? false)
    readonly property bool autoPlay: Boolean(root.config.autoPlay ?? true)
    readonly property bool autoAdvance: Boolean(root.config.autoAdvance ?? true)
    readonly property string notation: String(QanunStore.settings.general.notation ?? "letters")

    property var question: null
    property var choices: []
    property var feedback: null
    property bool answering: false
    property bool playing: false
    property int questionNumber: 0
    property string lastIntervalId: ""
    property string lastScaleId: ""
    property string lastChordId: ""
    property int lastNotePc: -1

    readonly property var stats: QanunStore.earStats
    readonly property real accuracy: Number(root.stats.answered ?? 0) > 0
        ? Number(root.stats.correct ?? 0) / Number(root.stats.answered) : 0
    readonly property int strength: Number(root.stats.streak ?? 0)
    readonly property string modeLabel: root.mode === "intervals"
        ? Translation.tr("Intervals")
        : root.mode === "notes" ? Translation.tr("Single note")
        : root.mode === "scales" ? Translation.tr("Scales & maqamat") : Translation.tr("Chords")
    readonly property string pageSubtitle: Translation.tr("%1 · %2 correct · %3% accuracy · best streak %4")
        .arg(root.modeLabel).arg(String(root.stats.correct ?? 0))
        .arg(String(Math.round(root.accuracy * 100))).arg(String(root.stats.bestStreak ?? 0))
    readonly property int choiceColumns: root.mode === "scales" || root.mode === "chords" ? 2 : 3

    function intervalTable(): var {
        return [
            { id: "m2", semitones: 1, label: "m2", name: Translation.tr("Minor 2nd") },
            { id: "M2", semitones: 2, label: "M2", name: Translation.tr("Major 2nd") },
            { id: "m3", semitones: 3, label: "m3", name: Translation.tr("Minor 3rd") },
            { id: "M3", semitones: 4, label: "M3", name: Translation.tr("Major 3rd") },
            { id: "P4", semitones: 5, label: "P4", name: Translation.tr("Perfect 4th") },
            { id: "TT", semitones: 6, label: "TT", name: Translation.tr("Tritone") },
            { id: "P5", semitones: 7, label: "P5", name: Translation.tr("Perfect 5th") },
            { id: "m6", semitones: 8, label: "m6", name: Translation.tr("Minor 6th") },
            { id: "M6", semitones: 9, label: "M6", name: Translation.tr("Major 6th") },
            { id: "m7", semitones: 10, label: "m7", name: Translation.tr("Minor 7th") },
            { id: "M7", semitones: 11, label: "M7", name: Translation.tr("Major 7th") },
            { id: "P8", semitones: 12, label: "P8", name: Translation.tr("Octave") }
        ];
    }

    function chordTable(): var {
        if (root.chordSet === "sevenths") {
            return [
                { id: "maj7", name: Translation.tr("Major 7th"), intervals: [0, 4, 7, 11] },
                { id: "min7", name: Translation.tr("Minor 7th"), intervals: [0, 3, 7, 10] },
                { id: "dom7", name: Translation.tr("Dominant 7th"), intervals: [0, 4, 7, 10] },
                { id: "halfDim", name: Translation.tr("Half-diminished 7th"), intervals: [0, 3, 6, 10] }
            ];
        }
        return [
            { id: "major", name: Translation.tr("Major"), intervals: [0, 4, 7] },
            { id: "minor", name: Translation.tr("Minor"), intervals: [0, 3, 7] },
            { id: "dim", name: Translation.tr("Diminished"), intervals: [0, 3, 6] },
            { id: "aug", name: Translation.tr("Augmented"), intervals: [0, 4, 8] }
        ];
    }

    function shuffle(items): var {
        const list = Array.from(items);
        for (let i = list.length - 1; i > 0; --i) {
            const j = Math.floor(Math.random() * (i + 1));
            const value = list[i];
            list[i] = list[j];
            list[j] = value;
        }
        return list;
    }

    function noteDetail(notes): string {
        return notes.map(note => {
            const midi = note.midi !== undefined ? note.midi : note;
            return QanunData.midiLabel(Math.round(midi), root.notation, false);
        }).join(" · ");
    }

    function newQuestion(): void {
        root.stopPlayback();
        nextTimer.stop();
        root.feedback = null;
        root.answering = false;
        root.questionNumber++;
        if (root.mode === "intervals")
            root.makeIntervalQuestion();
        else if (root.mode === "notes")
            root.makeNoteQuestion();
        else if (root.mode === "scales")
            root.makeScaleQuestion();
        else
            root.makeChordQuestion();
        if (root.autoPlay)
            autoPlayTimer.restart();
    }

    function makeIntervalQuestion(): void {
        const table = root.intervalTable();
        let item = table[Math.floor(Math.random() * table.length)];
        if (table.length > 1 && item.id === root.lastIntervalId)
            item = table[(table.indexOf(item) + 1) % table.length];
        root.lastIntervalId = item.id;
        const rootMidi = 55 + Math.floor(Math.random() * 13);
        const midis = [rootMidi, rootMidi + item.semitones];
        root.question = {
            kind: "interval",
            answerId: item.id,
            answer: item.name,
            detail: item.label,
            prompt: Translation.tr("Which interval did you hear?"),
            midis: midis,
            notes: null
        };
        root.choices = table.map(choice => ({
            id: choice.id,
            label: choice.label,
            sub: choice.name
        }));
    }

    function makeNoteQuestion(): void {
        const pcs = root.singleNoteAccidentals
            ? [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
            : [0, 2, 4, 5, 7, 9, 11];
        let pc = pcs[Math.floor(Math.random() * pcs.length)];
        if (pcs.length > 1 && pc === root.lastNotePc)
            pc = pcs[(pcs.indexOf(pc) + 1) % pcs.length];
        root.lastNotePc = pc;
        const midi = 60 + pc;
        const info = QanunData.spellMidi(midi, false, root.notation);
        root.question = {
            kind: "note",
            answerId: String(pc),
            answer: info.label + String(info.octave),
            detail: QanunData.frequencyForMidi(midi, Number(QanunStore.settings.general.a4 ?? 440)).toFixed(2)
                + " Hz",
            prompt: Translation.tr("Which note did you hear?"),
            midis: [midi],
            notes: null
        };
        root.choices = pcs.map(itemPc => ({
            id: String(itemPc),
            label: QanunData.midiLabel(60 + itemPc, root.notation, false),
            sub: ""
        }));
    }

    function makeScaleQuestion(): void {
        let pool = QanunData.allScales(root.scaleSource === "maqams" ? "maqam"
            : root.scaleSource === "western" ? "western" : "all");
        if (pool.length === 0)
            pool = QanunData.allScales("all");
        let correct = pool[Math.floor(Math.random() * pool.length)];
        if (pool.length > 1 && String(correct.id) === root.lastScaleId)
            correct = pool[(pool.indexOf(correct) + 1) % pool.length];
        root.lastScaleId = String(correct.id);

        const rootPc = correct.category === "maqam" ? Number(correct.rootPc ?? 0) : 0;
        const degrees = QanunData.scaleNotes(correct, rootPc, root.notation);
        const notes = degrees.map(note => note.midi);
        const options = [correct];
        while (options.length < 4 && options.length < pool.length) {
            const candidate = pool[Math.floor(Math.random() * pool.length)];
            if (!options.some(item => String(item.id) === String(candidate.id)))
                options.push(candidate);
        }
        root.question = {
            kind: "scale",
            answerId: String(correct.id),
            answer: correct.name,
            detail: degrees.map(note => note.name).join(" · "),
            prompt: Translation.tr("Which maqam or scale did you hear?"),
            midis: null,
            notes: notes
        };
        root.choices = root.shuffle(options).map(scale => ({
            id: String(scale.id),
            label: scale.name,
            sub: scale.kind ?? ""
        }));
    }

    function makeChordQuestion(): void {
        const table = root.chordTable();
        let chord = table[Math.floor(Math.random() * table.length)];
        if (table.length > 1 && chord.id === root.lastChordId)
            chord = table[(table.indexOf(chord) + 1) % table.length];
        root.lastChordId = chord.id;
        const rootMidi = 55 + Math.floor(Math.random() * 10);
        const midis = chord.intervals.map(interval => rootMidi + interval);
        root.question = {
            kind: "chord",
            answerId: chord.id,
            answer: chord.name,
            detail: root.noteDetail(midis),
            prompt: Translation.tr("Which chord quality did you hear?"),
            midis: midis,
            notes: null
        };
        root.choices = table.map(item => ({
            id: item.id,
            label: item.name,
            sub: ""
        }));
    }

    function playPrompt(): void {
        if (!root.question)
            return;
        root.stopPlayback();
        root.playing = true;
        if (root.mode === "notes") {
            QanunStore.playTone(root.question.midis[0], 2.1);
            playbackTimer.interval = 2300;
        } else if (root.mode === "intervals") {
            const midis = root.question.midis;
            if (root.intervalDirection === "harmonic") {
                QanunStore.playChord(midis, 2.3);
                playbackTimer.interval = 2500;
            } else {
                const ordered = root.intervalDirection === "descending" ? [midis[1], midis[0]] : midis;
                QanunStore.playMidiSequence(ordered.map(midi => ({ midi: midi, beats: 1 })), 86,
                    Translation.tr("Ear training · interval"));
                playbackTimer.interval = 2300;
            }
        } else if (root.mode === "scales") {
            let notes = Array.from(root.question.notes ?? []);
            if (root.scaleDirection === "descending")
                notes.reverse();
            QanunStore.playMidiSequence(notes.map(midi => ({ midi: midi, beats: 0.8 })), 120,
                Translation.tr("Ear training · scale"));
            playbackTimer.interval = 4200;
        } else {
            QanunStore.playChord(root.question.midis, 2.4);
            playbackTimer.interval = 2600;
        }
        playbackTimer.restart();
    }

    function stopPlayback(): void {
        playbackTimer.stop();
        root.playing = false;
        QanunStore.stopSequence();
        QanunStore.stopChordPlayback();
    }

    function choose(choice): void {
        if (!root.question || root.feedback !== null || root.answering)
            return;
        root.answering = true;
        const correct = String(choice.id) === String(root.question.answerId);
        root.feedback = {
            correct: correct,
            chosenId: String(choice.id),
            chosen: choice.label,
            answer: root.question.answer,
            detail: root.question.detail
        };
        QanunStore.recordEarTraining(correct, root.mode, root.question.answer);
        if (correct && root.autoAdvance)
            nextTimer.restart();
    }

    function revealAnswer(): void {
        if (!root.question || root.feedback !== null || root.answering)
            return;
        root.answering = true;
        root.feedback = {
            correct: false,
            chosenId: "",
            chosen: "",
            answer: root.question.answer,
            detail: root.question.detail
        };
        QanunStore.recordEarTraining(false, root.mode, root.question.answer);
        root.stopPlayback();
    }

    function setMode(next: string): void {
        QanunStore.setEarTraining({ mode: next });
        Qt.callLater(() => root.newQuestion());
    }

    function setOption(key: string, value): void {
        const patch = {};
        patch[key] = value;
        QanunStore.setEarTraining(patch);
        if (key !== "autoPlay" && key !== "autoAdvance")
            Qt.callLater(() => root.newQuestion());
    }

    function choiceIsCorrect(choiceId): bool {
        return root.feedback !== null && String(choiceId) === String(root.question?.answerId ?? "");
    }

    function choiceIsWrong(choiceId): bool {
        return root.feedback !== null && !root.feedback.correct
            && String(choiceId) === String(root.feedback.chosenId ?? "");
    }

    Component.onCompleted: root.newQuestion()
    Component.onDestruction: root.stopPlayback()

    Connections {
        target: QanunStore
        function onAudioStopRequested() {
            root.stopPlayback();
        }
    }

    Timer {
        id: autoPlayTimer
        interval: 260
        repeat: false
        onTriggered: root.playPrompt()
    }

    Timer {
        id: nextTimer
        interval: 900
        repeat: false
        onTriggered: {
            if (root.feedback?.correct)
                root.newQuestion();
        }
    }

    Timer {
        id: playbackTimer
        interval: 2400
        repeat: false
        onTriggered: root.playing = false
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.gap
        spacing: ClockStyle.gap

        // ── Exercise settings ───────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: settingsFlow.implicitHeight + 24
            radius: ClockStyle.radiusCard
            color: ClockStyle.colPane

            Flow {
                id: settingsFlow
                anchors {
                    fill: parent
                    margins: 12
                }
                spacing: 6

                StyledText {
                    text: Translation.tr("Exercise")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: QanunStyle.colSubtext
                    height: 32
                    verticalAlignment: Text.AlignVCenter
                }
                Repeater {
                    model: [
                        { id: "intervals", label: Translation.tr("Intervals"), symbol: "straighten" },
                        { id: "notes", label: Translation.tr("Single note"), symbol: "music_note" },
                        { id: "scales", label: Translation.tr("Scales"), symbol: "auto_awesome" },
                        { id: "chords", label: Translation.tr("Chords"), symbol: "piano" }
                    ]
                    ClockChip {
                        required property var modelData
                        label: modelData.label
                        symbol: modelData.symbol
                        selected: root.mode === modelData.id
                        height_: 32
                        onClicked: root.setMode(modelData.id)
                    }
                }

                Rectangle { width: 1; height: 28; color: Qt.alpha(QanunStyle.colOnSurface, 0.12) }

                StyledText {
                    text: Translation.tr("Direction")
                    visible: root.mode === "intervals" || root.mode === "scales"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: QanunStyle.colSubtext
                    height: 32
                    verticalAlignment: Text.AlignVCenter
                }
                Repeater {
                    model: root.mode === "intervals"
                        ? [
                            { id: "ascending", label: Translation.tr("Up") },
                            { id: "descending", label: Translation.tr("Down") },
                            { id: "harmonic", label: Translation.tr("Together") }
                        ]
                        : [
                            { id: "ascending", label: Translation.tr("Up") },
                            { id: "descending", label: Translation.tr("Down") }
                        ]
                    ClockChip {
                        required property var modelData
                        visible: root.mode === "intervals" || root.mode === "scales"
                        label: modelData.label
                        selected: root.mode === "intervals"
                            ? root.intervalDirection === modelData.id
                            : root.scaleDirection === modelData.id
                        height_: 32
                        onClicked: root.setOption(root.mode === "intervals" ? "intervalDirection" : "scaleDirection", modelData.id)
                    }
                }

                StyledText {
                    visible: root.mode === "notes"
                    text: Translation.tr("Notes")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: QanunStyle.colSubtext
                    height: 32
                    verticalAlignment: Text.AlignVCenter
                }
                ClockChip {
                    visible: root.mode === "notes"
                    label: Translation.tr("Naturals")
                    selected: !root.singleNoteAccidentals
                    height_: 32
                    onClicked: root.setOption("singleNoteAccidentals", false)
                }
                ClockChip {
                    visible: root.mode === "notes"
                    label: Translation.tr("Chromatic")
                    selected: root.singleNoteAccidentals
                    height_: 32
                    onClicked: root.setOption("singleNoteAccidentals", true)
                }

                StyledText {
                    visible: root.mode === "scales"
                    text: Translation.tr("Source")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: QanunStyle.colSubtext
                    height: 32
                    verticalAlignment: Text.AlignVCenter
                }
                Repeater {
                    model: [
                        { id: "maqams", label: Translation.tr("Maqams") },
                        { id: "western", label: Translation.tr("Western") },
                        { id: "both", label: Translation.tr("Both") }
                    ]
                    ClockChip {
                        required property var modelData
                        visible: root.mode === "scales"
                        label: modelData.label
                        selected: root.scaleSource === modelData.id
                        height_: 32
                        onClicked: root.setOption("scaleSource", modelData.id)
                    }
                }

                StyledText {
                    visible: root.mode === "chords"
                    text: Translation.tr("Set")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: QanunStyle.colSubtext
                    height: 32
                    verticalAlignment: Text.AlignVCenter
                }
                Repeater {
                    model: [
                        { id: "triads", label: Translation.tr("Triads") },
                        { id: "sevenths", label: Translation.tr("Sevenths") }
                    ]
                    ClockChip {
                        required property var modelData
                        visible: root.mode === "chords"
                        label: modelData.label
                        selected: root.chordSet === modelData.id
                        height_: 32
                        onClicked: root.setOption("chordSet", modelData.id)
                    }
                }

                Rectangle { width: 1; height: 28; color: Qt.alpha(QanunStyle.colOnSurface, 0.12) }

                ClockChip {
                    label: Translation.tr("Auto play")
                    symbol: "play_circle"
                    selected: root.autoPlay
                    height_: 32
                    onClicked: root.setOption("autoPlay", !root.autoPlay)
                }
                ClockChip {
                    label: Translation.tr("Auto next")
                    symbol: "skip_next"
                    selected: root.autoAdvance
                    height_: 32
                    onClicked: root.setOption("autoAdvance", !root.autoAdvance)
                }
                ClockChip {
                    label: Translation.tr("Reset stats")
                    symbol: "restart_alt"
                    height_: 32
                    onClicked: QanunStore.resetEarTrainingStats()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: ClockStyle.gap

            // ── Listen card ─────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: ClockStyle.radiusCard
                color: ClockStyle.colPane
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: ClockStyle.gapLarge
                    spacing: ClockStyle.gapSmall

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall
                        ClockBadge {
                            size: 38
                            text: "hearing"
                            shape: MaterialShape.Shape.Cookie9Sided
                            color: ClockStyle.colPrimaryContainer
                            colSymbol: ClockStyle.colOnPrimaryContainer
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: root.modeLabel
                                font.family: Appearance.font.family.title
                                font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                                font.pixelSize: Appearance.font.pixelSize.large
                                color: QanunStyle.colOnSurface
                            }
                            StyledText {
                                text: root.question?.prompt ?? ""
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: QanunStyle.colSubtext
                            }
                        }
                        Rectangle {
                            implicitWidth: streakRow.implicitWidth + 20
                            implicitHeight: 32
                            radius: Appearance.rounding.full
                            color: QanunStyle.colField
                            RowLayout {
                                id: streakRow
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol {
                                    text: "local_fire_department"
                                    iconSize: 16
                                    fill: root.strength > 0 ? 1 : 0
                                    color: root.strength > 0 ? QanunStyle.colTertiary : QanunStyle.colSubtext
                                }
                                StyledText {
                                    text: Translation.tr("%1 streak").arg(String(root.strength))
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    color: QanunStyle.colOnSurface
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            Item {
                                Layout.alignment: Qt.AlignHCenter
                                width: 190
                                height: 190

                                Rectangle {
                                    id: listenHalo
                                    anchors.centerIn: parent
                                    width: 164
                                    height: 164
                                    radius: Appearance.rounding.full
                                    color: "transparent"
                                    border.width: 2
                                    border.color: QanunStyle.colPrimary
                                    opacity: 0
                                    scale: 1
                                    SequentialAnimation {
                                        loops: Animation.Infinite
                                        running: root.playing && !Appearance.reducedMotion
                                        PauseAnimation { duration: 180 }
                                        ParallelAnimation {
                                            NumberAnimation { target: listenHalo; property: "scale"; from: 1; to: 1.22; duration: 900; easing.type: Easing.OutCubic }
                                            NumberAnimation { target: listenHalo; property: "opacity"; from: 0.35; to: 0; duration: 900; easing.type: Easing.OutCubic }
                                        }
                                        onRunningChanged: if (!running) { listenHalo.scale = 1; listenHalo.opacity = 0; }
                                    }
                                }

                                MaterialShape {
                                    anchors.fill: parent
                                    shapeString: root.playing ? "Cookie9Sided" : "Cookie7Sided"
                                    color: root.playing
                                        ? Qt.alpha(QanunStyle.colPrimary, 0.22)
                                        : QanunStyle.colPrimaryContainer
                                    rotation: root.playing ? 8 : 0
                                    Behavior on rotation {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: root.playing ? "graphic_eq" : "hearing"
                                    iconSize: 70
                                    fill: 1
                                    color: QanunStyle.colOnPrimaryContainer
                                }

                                RippleButton {
                                    anchors.fill: parent
                                    buttonRadius: width / 2
                                    colBackground: "transparent"
                                    colBackgroundHover: Qt.alpha(QanunStyle.colOnSurface, 0.05)
                                    colBackgroundActive: Qt.alpha(QanunStyle.colOnSurface, 0.1)
                                    colRipple: Qt.alpha(QanunStyle.colOnSurface, 0.12)
                                    Accessible.name: Translation.tr("Play the question")
                                    onClicked: root.playPrompt()
                                }
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.question?.prompt ?? ""
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: QanunStyle.colOnSurface
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.mode === "intervals"
                                    ? Translation.tr("Listen for the distance between two notes.")
                                    : root.mode === "notes"
                                        ? Translation.tr("Listen to one note, then name its pitch.")
                                        : root.mode === "scales"
                                            ? Translation.tr("Listen to the whole scale, then name it.")
                                            : Translation.tr("Listen to the notes sounding together.")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: QanunStyle.colSubtext
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.playing ? Translation.tr("Playing…") : Translation.tr("Ready to replay")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: root.playing ? QanunStyle.colPrimary : QanunStyle.colSubtext
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall
                        ClockButton {
                            Layout.fillWidth: true
                            symbol: root.playing ? "graphic_eq" : "replay"
                            label: root.playing ? Translation.tr("Playing") : Translation.tr("Replay")
                            variant: "filled"
                            onClicked: root.playPrompt()
                        }
                        ClockButton {
                            symbol: "visibility"
                            label: Translation.tr("Show answer")
                            variant: "tonal"
                            enabled: root.feedback === null
                            onClicked: root.revealAnswer()
                        }
                        ClockButton {
                            symbol: "skip_next"
                            label: Translation.tr("Skip")
                            variant: "text"
                            onClicked: root.newQuestion()
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.mode === "intervals"
                            ? Translation.tr("Interval recognition")
                            : root.mode === "notes"
                                ? Translation.tr("Single-note recognition")
                                : root.mode === "scales"
                                    ? Translation.tr("Maqam and scale recognition")
                                    : Translation.tr("Chord quality recognition")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: QanunStyle.colSubtext
                    }
                }
            }

            // ── Answers card ────────────────────────────────────────────
            Rectangle {
                Layout.preferredWidth: root.compact ? 330 : (root.wide ? 430 : 360)
                Layout.minimumWidth: root.compact ? 280 : 320
                Layout.fillHeight: true
                radius: ClockStyle.radiusCard
                color: ClockStyle.colPane
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: ClockStyle.gapLarge
                    spacing: ClockStyle.gapSmall

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall
                        ClockBadge {
                            size: 34
                            text: "quiz"
                            shape: MaterialShape.Shape.Sunny
                            color: ClockStyle.colTertiary
                            colSymbol: ClockStyle.colOnTertiary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Answers")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: QanunStyle.colOnSurface
                        }
                        StyledText {
                            text: Translation.tr("choose what you hear")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: QanunStyle.colSubtext
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        columns: root.choiceColumns
                        rowSpacing: 8
                        columnSpacing: 8

                        Repeater {
                            model: root.choices
                            RippleButton {
                                id: choiceButton
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                implicitHeight: 84
                                enabled: root.feedback === null
                                buttonRadius: ClockStyle.radiusNormal
                                buttonRadiusPressed: ClockStyle.radiusSmall
                                readonly property bool isCorrect: root.choiceIsCorrect(choiceButton.modelData.id)
                                readonly property bool isWrong: root.choiceIsWrong(choiceButton.modelData.id)
                                colBackground: choiceButton.isCorrect
                                    ? Qt.alpha(QanunStyle.colInTune, 0.16)
                                    : choiceButton.isWrong ? Qt.alpha(QanunStyle.colError, 0.14)
                                    : QanunStyle.colField
                                colBackgroundHover: choiceButton.isCorrect
                                    ? Qt.alpha(QanunStyle.colInTune, 0.22)
                                    : QanunStyle.colFieldHover
                                colRipple: Qt.alpha(QanunStyle.colPrimary, 0.14)
                                onClicked: root.choose(choiceButton.modelData)

                                contentItem: ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 1
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: choiceButton.modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.large
                                        font.family: Appearance.font.family.title
                                        font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                                        color: choiceButton.isCorrect ? QanunStyle.colInTune
                                            : choiceButton.isWrong ? QanunStyle.colError
                                            : QanunStyle.colOnSurface
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        visible: String(choiceButton.modelData.sub ?? "").length > 0
                                        text: choiceButton.modelData.sub
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: QanunStyle.colSubtext
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.feedback === null ? 0 : 78
                        visible: root.feedback !== null
                        radius: Appearance.rounding.normal
                        color: root.feedback?.correct ? Qt.alpha(QanunStyle.colInTune, 0.14)
                            : Qt.alpha(QanunStyle.colError, 0.14)
                        clip: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 1
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                MaterialSymbol {
                                    text: root.feedback?.correct ? "check_circle" : "cancel"
                                    iconSize: 22
                                    fill: 1
                                    color: root.feedback?.correct ? QanunStyle.colInTune : QanunStyle.colError
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.feedback?.correct ? Translation.tr("Correct") : Translation.tr("Not quite")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Bold
                                    color: root.feedback?.correct ? QanunStyle.colInTune : QanunStyle.colError
                                }
                                ClockButton {
                                    visible: !root.autoAdvance || !root.feedback?.correct
                                    symbol: "arrow_forward"
                                    label: Translation.tr("Next")
                                    variant: "filled"
                                    onClicked: root.newQuestion()
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.feedback === null ? ""
                                    : Translation.tr("%1%2").arg(String(root.feedback.answer ?? ""))
                                        .arg(String(root.feedback.detail ?? "").length > 0
                                            ? "  ·  " + String(root.feedback.detail) : "")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: QanunStyle.colSubtext
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Qt.alpha(QanunStyle.colOnSurface, 0.08)
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gap
                        StatCell { label: Translation.tr("Answered"); value: String(root.stats.answered ?? 0) }
                        StatCell { label: Translation.tr("Accuracy"); value: Math.round(root.accuracy * 100) + "%" }
                        StatCell { label: Translation.tr("Best streak"); value: String(root.stats.bestStreak ?? 0) }
                    }
                }
            }
        }
    }

    component StatCell: ColumnLayout {
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: 0
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: parent.value
            font.family: Appearance.font.family.numbers
            font.pixelSize: Appearance.font.pixelSize.large
            color: QanunStyle.colOnSurface
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: parent.label
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: QanunStyle.colSubtext
        }
    }
}
