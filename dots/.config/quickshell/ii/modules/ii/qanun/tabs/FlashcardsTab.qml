import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.qanun
import qs.modules.ii.qanun.components

/**
 * Note-reading flashcards. A note appears on a treble or bass staff; answer by
 * naming it, or play it on your instrument and let the microphone check the
 * pitch. Settings cover clef, accidental pool, notation and progression.
 */
Item {
    id: root

    property bool compact: false
    property bool wide: false

    readonly property var config: QanunStore.settings.flashcards ?? ({})
    readonly property string notation: String(root.config.notation ?? "letters")
    readonly property bool preferFlats: String(QanunStore.settings.general.accidentalStyle ?? "sharps") === "flats"
    readonly property bool useAccidentals: Boolean(root.config.accidentals ?? false)
    readonly property string clefMode: String(root.config.clef ?? "both")
    readonly property string answerMode: String(root.config.answerMode ?? "name")
    readonly property bool micAnswer: root.answerMode !== "name"
    readonly property bool autoAdvance: Boolean(root.config.autoAdvance ?? true)
    readonly property bool matchOctave: Boolean(root.config.matchOctave ?? false)
    readonly property int micTolerance: Number(root.config.micTolerance ?? 35)
    readonly property int answerCount: Boolean(root.config.accidentals ?? false) ? 12 : 7
    readonly property real a4: Number(QanunStore.settings.general.a4 ?? 440)
    readonly property var instrument: QanunData.tunerInstruments.find(item =>
        item.id === String(QanunStore.settings.general.instrument ?? "concert")) ?? QanunData.tunerInstruments[0]
    readonly property int expectedMidi: root.currentMidi + Number(root.instrument.transpose ?? 0)
    readonly property string targetPrompt: root.currentInfo.label + String(root.currentInfo.octave)
    readonly property string expectedConcertLabel: QanunData.midiLabel(root.expectedMidi, root.notation, root.preferFlats)
    readonly property bool micListening: micProcess.running

    property int currentMidi: 60
    property int lastMidi: -1
    property string staffClef: "treble"
    property var feedback: null
    property int questionSerial: 0
    property bool answering: false
    property var noteChoices: []

    property var micReading: ({ valid: false, cents: 0, label: "—", midi: -1 })
    property real micLevel: 0
    property int micMatchFrames: 0
    property string micError: ""

    readonly property var stats: QanunStore.stats
    readonly property real accuracy: Number(root.stats.answered ?? 0) > 0
        ? Number(root.stats.correct ?? 0) / Number(root.stats.answered) : 0
    readonly property var currentInfo: QanunData.spellMidi(root.currentMidi, root.preferFlats, root.notation)
    readonly property string currentAnswer: root.currentInfo.label
    readonly property string pageSubtitle: Translation.tr("%1 correct · %2 accuracy · best streak %3")
        .arg(String(root.stats.correct ?? 0)).arg(Math.round(root.accuracy * 100) + "%").arg(String(root.stats.bestStreak ?? 0))

    function chooseNewNote(): void {
        root.answering = false;
        root.feedback = null;
        root.micMatchFrames = 0;
        let pool = QanunData.notePoolForClef(root.clefMode, root.useAccidentals);
        if (pool.length === 0)
            pool = [60];
        let next = pool[Math.floor(Math.random() * pool.length)];
        if (pool.length > 1 && next === root.lastMidi)
            next = pool[(pool.indexOf(next) + 1) % pool.length];
        root.lastMidi = root.currentMidi;
        root.currentMidi = next;
        root.staffClef = root.clefMode === "bass" ? "bass"
            : root.clefMode === "treble" ? "treble" : (next < 60 ? "bass" : "treble");
        root.questionSerial++;
        root.buildChoices();
    }

    function buildChoices(): void {
        const choices = [];
        const pcs = root.useAccidentals
            ? [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
            : [0, 2, 4, 5, 7, 9, 11];
        for (const pc of pcs) {
            choices.push({
                pc: pc,
                midi: 60 + pc,
                label: QanunData.midiLabel(60 + pc, root.notation, root.preferFlats)
            });
        }
        root.noteChoices = choices;
    }

    function answerPitch(pc: int): void {
        if (root.feedback !== null || root.answering)
            return;
        root.answering = true;
        const correct = ((root.currentMidi % 12) + 12) % 12 === ((pc % 12) + 12) % 12;
        root.feedback = {
            correct: correct,
            answer: root.currentAnswer,
            chosen: QanunData.midiLabel(60 + pc, root.notation, root.preferFlats)
        };
        QanunStore.recordAnswer(correct, root.currentMidi, root.currentAnswer);
        if (Boolean(root.config.sound ?? true))
            QanunStore.playTone(root.currentMidi, 1.1);
        if (correct && root.autoAdvance)
            nextTimer.restart();
    }

    function startMic(): void {
        if (!root.micAnswer || micProcess.running || root.feedback !== null)
            return;
        root.micError = "";
        root.micReading = { valid: false, cents: 0, label: "—", midi: -1 };
        micProcess.command = ["python3", QanunStore.tunerScript];
        micProcess.running = true;
    }

    function stopMic(): void {
        root.micMatchFrames = 0;
        if (micProcess.running)
            micProcess.running = false;
    }

    function handleMicLine(line): void {
        if (!root.micListening || !root.micAnswer || root.feedback !== null || !line)
            return;
        let payload = null;
        try {
            payload = JSON.parse(line);
        } catch (error) {
            return;
        }
        if (!payload)
            return;
        root.micLevel = Number(payload.level ?? 0);
        const freq = Number(payload.freq ?? 0);
        const clarity = Number(payload.clarity ?? 0);
        if (!(freq > 0) || clarity < 0.55) {
            root.micReading = { valid: false, cents: 0, label: "—", midi: -1 };
            root.micMatchFrames = 0;
            return;
        }
        const reading = QanunData.tunerReading(freq, root.a4, root.preferFlats, root.notation);
        reading.clarity = clarity;
        root.micReading = reading;
        const pcMatch = ((reading.midi % 12) + 12) % 12 === ((root.expectedMidi % 12) + 12) % 12;
        const octaveMatch = Math.abs(reading.midi - root.expectedMidi) < 1;
        const matches = (root.matchOctave ? octaveMatch : pcMatch)
            && Math.abs(reading.cents) <= root.micTolerance;
        if (matches) {
            root.micMatchFrames++;
            if (root.micMatchFrames >= 6)
                root.completeMicAnswer();
        } else {
            root.micMatchFrames = 0;
        }
    }

    function completeMicAnswer(): void {
        if (root.feedback !== null || root.answering)
            return;
        root.answering = true;
        root.feedback = { correct: true, answer: root.currentAnswer, chosen: "" };
        QanunStore.recordAnswer(true, root.currentMidi, root.currentAnswer);
        root.stopMic();
        if (Boolean(root.config.sound ?? true))
            QanunStore.playTone(root.currentMidi, 1.1);
        if (root.autoAdvance)
            nextTimer.restart();
    }

    function revealMicAnswer(): void {
        if (root.feedback !== null || root.answering)
            return;
        root.answering = true;
        root.feedback = { correct: false, answer: root.currentAnswer, chosen: "" };
        QanunStore.recordAnswer(false, root.currentMidi, root.currentAnswer);
        root.stopMic();
    }

    function nextQuestion(): void {
        nextTimer.stop();
        root.stopMic();
        root.chooseNewNote();
        if (root.micAnswer)
            micRestartTimer.restart();
    }

    function hearNote(): void {
        QanunStore.playTone(root.currentMidi, 1.2);
    }

    function setConfig(key: string, value): void {
        const patch = {};
        patch[key] = value;
        QanunStore.setFlashcards(patch);
    }

    function chooseAnswerMode(mode: string): void {
        root.setConfig("answerMode", mode);
        if (mode === "mic") {
            root.nextQuestion();
        } else {
            root.stopMic();
        }
    }

    Component.onCompleted: {
        root.chooseNewNote();
        if (root.micAnswer)
            micRestartTimer.start();
    }

    Component.onDestruction: root.stopMic()

    Timer {
        id: nextTimer
        interval: 850
        repeat: false
        onTriggered: {
            if (root.feedback?.correct)
                root.nextQuestion();
        }
    }

    Timer {
        id: micRestartTimer
        interval: 360
        repeat: false
        onTriggered: root.startMic()
    }

    Process {
        id: micProcess
        stdout: SplitParser {
            onRead: line => root.handleMicLine(line)
        }
        stderr: SplitParser {
            onRead: line => {
                if (line && line.length > 0)
                    root.micError = line;
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && root.micAnswer && code !== 143)
                root.micError = Translation.tr("The microphone could not be opened.");
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.gap
        spacing: ClockStyle.gap

        // ── Practice settings strip ────────────────────────────────────
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
                    text: Translation.tr("Clef")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: QanunStyle.colSubtext
                    height: 32
                    verticalAlignment: Text.AlignVCenter
                }
                Repeater {
                    model: [{ id: "treble", label: "Treble" }, { id: "bass", label: "Bass" }, { id: "both", label: "Both" }]
                    ClockChip {
                        required property var modelData
                        label: modelData.label
                        selected: root.clefMode === modelData.id
                        height_: 32
                        onClicked: {
                            root.setConfig("clef", modelData.id);
                            root.chooseNewNote();
                        }
                    }
                }

                Rectangle { width: 1; height: 28; color: Qt.alpha(QanunStyle.colOnSurface, 0.12) }

                StyledText {
                    text: Translation.tr("Answer")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: QanunStyle.colSubtext
                    height: 32
                    verticalAlignment: Text.AlignVCenter
                }
                ClockChip {
                    label: Translation.tr("Name it")
                    symbol: "text_fields"
                    selected: root.answerMode === "name"
                    height_: 32
                    onClicked: root.chooseAnswerMode("name")
                }
                ClockChip {
                    label: Translation.tr("Play it")
                    symbol: "mic"
                    selected: root.micAnswer
                    height_: 32
                    onClicked: root.chooseAnswerMode("mic")
                }

                Rectangle { width: 1; height: 28; color: Qt.alpha(QanunStyle.colOnSurface, 0.12) }

                ClockChip {
                    label: Translation.tr("Accidentals")
                    selected: root.useAccidentals
                    height_: 32
                    onClicked: {
                        root.setConfig("accidentals", !root.useAccidentals);
                        root.chooseNewNote();
                    }
                }
                ClockChip {
                    label: Translation.tr("Sound")
                    symbol: Boolean(root.config.sound ?? true) ? "volume_up" : "volume_off"
                    selected: Boolean(root.config.sound ?? true)
                    height_: 32
                    onClicked: root.setConfig("sound", !Boolean(root.config.sound ?? true))
                }
                ClockChip {
                    label: Translation.tr("Auto next")
                    symbol: "skip_next"
                    selected: root.autoAdvance
                    height_: 32
                    onClicked: root.setConfig("autoAdvance", !root.autoAdvance)
                }

                Rectangle { width: 1; height: 28; color: Qt.alpha(QanunStyle.colOnSurface, 0.12) }

                StyledText {
                    text: Translation.tr("Names")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: QanunStyle.colSubtext
                    height: 32
                    verticalAlignment: Text.AlignVCenter
                }
                Repeater {
                    model: QanunData.notationOptions
                    ClockChip {
                        required property var modelData
                        label: modelData.label
                        selected: root.notation === modelData.id
                        height_: 32
                        onClicked: {
                            root.setConfig("notation", modelData.id);
                            root.buildChoices();
                        }
                    }
                }

                Item { width: 4; height: 1 }

                ClockChip {
                    label: Translation.tr("Reset stats")
                    symbol: "restart_alt"
                    height_: 32
                    onClicked: QanunStore.resetStats()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: ClockStyle.gap

            // ── Staff card ──────────────────────────────────────────────
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
                            text: "school"
                            shape: MaterialShape.Shape.Cookie9Sided
                            color: ClockStyle.colPrimaryContainer
                            colSymbol: ClockStyle.colOnPrimaryContainer
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: root.micAnswer ? Translation.tr("Play this note") : Translation.tr("Name this note")
                                font.family: Appearance.font.family.title
                                font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                                font.pixelSize: Appearance.font.pixelSize.large
                                color: QanunStyle.colOnSurface
                            }
                            StyledText {
                                text: root.staffClef === "bass" ? Translation.tr("Bass clef") : Translation.tr("Treble clef")
                                    + "  ·  " + (root.useAccidentals ? Translation.tr("with accidentals") : Translation.tr("naturals only"))
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
                                    fill: Number(root.stats.streak ?? 0) > 0 ? 1 : 0
                                    color: Number(root.stats.streak ?? 0) > 0 ? QanunStyle.colTertiary : QanunStyle.colSubtext
                                }
                                StyledText {
                                    text: Translation.tr("%1 streak").arg(String(root.stats.streak ?? 0))
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    color: QanunStyle.colOnSurface
                                }
                            }
                        }

                        ClockIconButton {
                            symbol: "volume_up"
                            tooltip: Translation.tr("Hear the note")
                            size: 34
                            onClicked: root.hearNote()
                        }
                        ClockIconButton {
                            symbol: "skip_next"
                            tooltip: Translation.tr("Skip this note")
                            size: 34
                            onClicked: root.nextQuestion()
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 210

                        MusicStaff {
                            anchors.fill: parent
                            anchors.topMargin: 4
                            anchors.bottomMargin: 4
                            notes: [{
                                letter: root.currentInfo.letter,
                                alter: root.currentInfo.alter,
                                octave: root.currentInfo.octave,
                                duration: 4, dotted: false, tie: false, rest: false,
                                midi: root.currentMidi
                            }]
                            clef: root.staffClef
                            keySignature: 0
                            timeSignature: [4, 4]
                            showTimeSignature: false
                            showBarLines: false
                            centerSingle: true
                            accentIndex: 0
                            accentColor: root.feedback === null ? QanunStyle.colOnSurface
                                : root.feedback.correct ? QanunStyle.colInTune : QanunStyle.colError
                        }

                        // A quiet "?" until the card is answered.
                        StyledText {
                            visible: root.feedback === null
                            anchors {
                                right: parent.right
                                top: parent.top
                                margins: 4
                            }
                            text: "?"
                            font.family: Appearance.font.family.title
                            font.pixelSize: 42
                            color: Qt.alpha(QanunStyle.colPrimary, 0.18)
                        }
                    }

                    // Feedback row.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.feedback === null ? 0 : 62
                        visible: root.feedback !== null
                        radius: Appearance.rounding.normal
                        color: root.feedback?.correct ? Qt.alpha(QanunStyle.colInTune, 0.14)
                            : Qt.alpha(QanunStyle.colError, 0.14)
                        clip: true

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10
                            MaterialSymbol {
                                text: root.feedback?.correct ? "check_circle" : "cancel"
                                iconSize: 28
                                fill: 1
                                color: root.feedback?.correct ? QanunStyle.colInTune : QanunStyle.colError
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    text: root.feedback?.correct ? Translation.tr("Correct") : Translation.tr("Not quite")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Bold
                                    color: root.feedback?.correct ? QanunStyle.colInTune : QanunStyle.colError
                                }
                                StyledText {
                                    text: root.feedback === null ? ""
                                        : root.feedback.correct
                                            ? Translation.tr("It was %1.").arg(String(root.feedback.answer ?? ""))
                                            : root.feedback.chosen && String(root.feedback.chosen).length > 0
                                                ? Translation.tr("You chose %1 — it is %2.").arg(String(root.feedback.chosen ?? "")).arg(String(root.feedback.answer ?? ""))
                                                : Translation.tr("The note is %1.").arg(String(root.feedback.answer ?? ""))
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: QanunStyle.colOnSurface
                                }
                            }
                            ClockButton {
                                visible: !root.autoAdvance || !root.feedback?.correct
                                symbol: "arrow_forward"
                                label: Translation.tr("Next")
                                variant: "filled"
                                onClicked: root.nextQuestion()
                            }
                        }
                    }
                }
            }

            // ── Answer card ─────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: root.compact
                Layout.preferredWidth: root.compact ? -1 : (root.wide ? 390 : 330)
                Layout.minimumWidth: root.compact ? 0 : 300
                Layout.maximumWidth: root.compact ? 100000 : 430
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
                            text: root.micAnswer ? "mic" : "text_fields"
                            shape: MaterialShape.Shape.Sunny
                            color: ClockStyle.colTertiary
                            colSymbol: ClockStyle.colOnTertiary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.micAnswer ? Translation.tr("Microphone answers") : Translation.tr("Note names")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: QanunStyle.colOnSurface
                        }
                        StyledText {
                            text: root.micAnswer ? Translation.tr("play your instrument") : Translation.tr("click or tap")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: QanunStyle.colSubtext
                        }
                    }

                    // Name answers: a responsive grid of large chips.
                    GridLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.answerMode === "name"
                        columns: 3
                        rowSpacing: 8
                        columnSpacing: 8

                        Repeater {
                            model: root.noteChoices
                            RippleButton {
                                id: answerButton
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                implicitHeight: 56
                                buttonRadius: ClockStyle.radiusNormal
                                buttonRadiusPressed: ClockStyle.radiusSmall
                                colBackground: QanunStyle.colField
                                colBackgroundHover: QanunStyle.colFieldHover
                                colRipple: Qt.alpha(QanunStyle.colPrimary, 0.14)
                                enabled: root.feedback === null
                                opacity: root.feedback !== null
                                    && ((root.currentMidi % 12) + 12) % 12 !== answerButton.modelData.pc ? 0.5 : 1
                                onClicked: root.answerPitch(answerButton.modelData.pc)

                                contentItem: StyledText {
                                    text: answerButton.modelData.label
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: Appearance.font.pixelSize.large
                                    font.family: Appearance.font.family.title
                                    font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                                    color: QanunStyle.colOnSurface
                                }
                            }
                        }
                    }

                    // Microphone answers: the user plays the note on their
                    // instrument; the tuner helper listens for a stable pitch.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.micAnswer
                        radius: Appearance.rounding.normal
                        color: QanunStyle.colField
                        clip: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 8

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Item {
                                        Layout.alignment: Qt.AlignHCenter
                                        width: 104
                                        height: 104

                                        Rectangle {
                                            id: micHalo
                                            anchors.centerIn: parent
                                            width: 94
                                            height: 94
                                            radius: Appearance.rounding.full
                                            color: "transparent"
                                            border.width: 2
                                            border.color: QanunStyle.colPrimary
                                            opacity: 0
                                            scale: 1

                                            SequentialAnimation {
                                                loops: Animation.Infinite
                                                running: root.micListening && root.feedback === null && !Appearance.reducedMotion
                                                PauseAnimation { duration: 180 }
                                                ParallelAnimation {
                                                    NumberAnimation { target: micHalo; property: "scale"; from: 1; to: 1.28; duration: 850; easing.type: Easing.OutCubic }
                                                    NumberAnimation { target: micHalo; property: "opacity"; from: 0.35; to: 0; duration: 850; easing.type: Easing.OutCubic }
                                                }
                                                onRunningChanged: if (!running) { micHalo.scale = 1; micHalo.opacity = 0; }
                                            }
                                        }

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 82
                                            height: 82
                                            radius: Appearance.rounding.full
                                            color: root.micListening
                                                ? Qt.alpha(QanunStyle.colInTune, 0.18) : QanunStyle.colFieldHover
                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: root.micListening ? "mic" : "mic_off"
                                                iconSize: 34
                                                fill: 1
                                                color: root.micListening ? QanunStyle.colInTune : QanunStyle.colSubtext
                                            }
                                        }
                                    }

                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.micListening
                                            ? Translation.tr("Read the staff and play the note")
                                            : Translation.tr("Microphone is off")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: QanunStyle.colOnSurface
                                    }

                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "?"
                                        font.family: Appearance.font.family.title
                                        font.variableAxes: ({ "wght": 760, "wdth": 60, "ROND": 100 })
                                        font.pixelSize: 54
                                        color: Qt.alpha(QanunStyle.colPrimary, 0.28)
                                    }

                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.micReading.valid
                                            ? Translation.tr("Heard %1 · %2")
                                                .arg(root.micReading.label + String(root.micReading.octave))
                                                .arg(QanunStyle.centsLabel(root.micReading.cents))
                                            : (root.micListening ? Translation.tr("Listening…") : "")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.family: Appearance.font.family.numbers
                                        color: root.micReading.valid
                                            ? QanunStyle.tuningColor(root.micReading.cents, root.micTolerance)
                                            : QanunStyle.colSubtext
                                    }

                                    RowLayout {
                                        Layout.alignment: Qt.AlignHCenter
                                        spacing: 3
                                        Repeater {
                                            model: 10
                                            Rectangle {
                                                required property int index
                                                width: 4
                                                height: 8 + Math.round(Math.min(1, root.micLevel * 18) * 14)
                                                radius: 2
                                                color: index < Math.round(Math.min(1, root.micLevel * 18) * 10)
                                                    ? QanunStyle.colInTune : Qt.alpha(QanunStyle.colOnSurface, 0.12)
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ClockStyle.gapSmall
                                ClockButton {
                                    Layout.fillWidth: true
                                    symbol: root.micListening ? "stop_circle" : "mic"
                                    label: root.micListening ? Translation.tr("Stop listening") : Translation.tr("Start listening")
                                    variant: root.micListening ? "tonal" : "filled"
                                    enabled: root.feedback === null
                                    onClicked: {
                                        if (root.micListening)
                                            root.stopMic();
                                        else
                                            root.startMic();
                                    }
                                }
                                ClockButton {
                                    symbol: "visibility"
                                    label: Translation.tr("Show answer")
                                    variant: "text"
                                    enabled: root.feedback === null
                                    onClicked: root.revealMicAnswer()
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.micError.length > 0
                                    ? root.micError
                                    : Translation.tr("The card advances when the pitch is held steadily. Use the tuner's transposition setting for a transposing instrument.")
                                wrapMode: Text.WordWrap
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: root.micError.length > 0 ? QanunStyle.colError : QanunStyle.colSubtext
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall
                        StyledText {
                            Layout.fillWidth: true
                            text: root.feedback === null
                                ? (root.micAnswer
                                    ? Translation.tr("Play the note steadily; the card checks the pitch against the staff.")
                                    : Translation.tr("Pick the note name. C4 is middle C."))
                                : (root.feedback.correct
                                    ? Translation.tr("Keep the streak going.")
                                    : Translation.tr("Use the next card to try another note."))
                            wrapMode: Text.WordWrap
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: QanunStyle.colSubtext
                        }
                        ClockButton {
                            symbol: "arrow_forward"
                            label: Translation.tr("Next")
                            variant: "tonal"
                            onClicked: root.nextQuestion()
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
                        StatCell {
                            label: Translation.tr("Answered")
                            value: String(root.stats.answered ?? 0)
                        }
                        StatCell {
                            label: Translation.tr("Accuracy")
                            value: Math.round(root.accuracy * 100) + "%"
                        }
                        StatCell {
                            label: Translation.tr("Best streak")
                            value: String(root.stats.bestStreak ?? 0)
                        }
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
