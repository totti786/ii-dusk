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
 * The tuner page: pitch history and the note/frequency card on the left, the
 * cents ruler and tuning controls on the right. Real-time pitch comes from the
 * small YIN helper, so this is a microphone tuner rather than a simulated dial.
 */
Item {
    id: root

    property bool compact: false
    property bool wide: false

    readonly property bool horizontal: !root.compact && root.width >= 760
    readonly property bool listening: tunerProcess.running
    readonly property var general: QanunStore.settings.general ?? ({})
    readonly property var tunerSettings: QanunStore.settings.tuner ?? ({})
    readonly property var instrument: QanunData.tunerInstruments.find(item => item.id === (root.general.instrument ?? "concert")) ?? QanunData.tunerInstruments[0]
    readonly property real a4: Number(root.general.a4 ?? 440)
    readonly property bool preferFlats: String(root.general.accidentalStyle ?? "sharps") === "flats"
    readonly property string notation: String(root.general.notation ?? "letters")

    property var reading: ({ valid: false, freq: 0, cents: 0, label: "—", octave: 0, target: 0, midi: -1 })
    property var history: []
    property real level: 0
    property string error: ""
    property bool wasListening: false
    property var recentFreqs: []
    property int invalidFrames: 0
    property int candidateMidi: -1
    property int candidateFrames: 0
    property real lastHistoryAt: 0
    property real lastInvalidHistoryAt: 0

    readonly property color statusColor: root.reading.valid
        ? QanunStyle.tuningColor(root.reading.cents, Number(root.tunerSettings.inTuneCents ?? 5))
        : QanunStyle.colSubtext
    readonly property string writtenNote: {
        if (!root.reading.valid)
            return "";
        const midi = Number(root.reading.midi) - Number(root.instrument.transpose ?? 0);
        return QanunData.midiLabel(midi, root.notation, root.preferFlats);
    }
    readonly property string pageSubtitle: {
        if (root.listening && root.reading.valid)
            return QanunStyle.tuningWord(root.reading.cents, Number(root.tunerSettings.inTuneCents ?? 5))
                + " · " + QanunData.midiLabel(root.reading.midi, root.notation, root.preferFlats);
        if (root.listening)
            return Translation.tr("Listening for a clear note");
        return Translation.tr("Microphone is off");
    }

    function startListening(): void {
        if (tunerProcess.running)
            return;
        root.history = [];
        root.reading = { valid: false, freq: 0, cents: 0, label: "—", octave: 0, target: 0, midi: -1 };
        root.error = "";
        root.recentFreqs = [];
        root.invalidFrames = 0;
        root.candidateMidi = -1;
        root.candidateFrames = 0;
        root.lastHistoryAt = 0;
        root.lastInvalidHistoryAt = 0;
        root.wasListening = true;
        tunerProcess.command = ["python3", QanunStore.tunerScript];
        tunerProcess.running = true;
    }

    function stopListening(): void {
        root.wasListening = false;
        if (tunerProcess.running)
            tunerProcess.running = false;
        root.recentFreqs = [];
        root.candidateFrames = 0;
    }

    function toggleListening(): void {
        if (root.listening)
            root.stopListening();
        else
            root.startListening();
    }

    function appendHistory(now, cents, valid): void {
        if (now - root.lastHistoryAt < 90 && valid)
            return;
        if (!valid && now - root.lastInvalidHistoryAt < 260)
            return;
        root.lastHistoryAt = now;
        if (!valid)
            root.lastInvalidHistoryAt = now;
        const next = root.history.slice(-240);
        next.push({ t: now, cents: cents, valid: valid, level: root.level });
        root.history = next;
    }

    function holdPreviousReading(freq, clarity): void {
        if (!root.reading.valid)
            return;
        const prevMidi = Number(root.reading.midi);
        const target = QanunData.frequencyForMidi(prevMidi, root.a4);
        const deviation = QanunData.centsOff(freq, target);
        // Do not print a frequency that belongs to another note while holding
        // the previous label. A large jump means a new note is arriving; keep
        // the old card frozen for the few frames it takes to confirm it.
        if (Math.abs(deviation) > 60)
            return;
        const info = QanunData.spellMidi(prevMidi, root.preferFlats, root.notation);
        const smoothed = root.reading.cents * 0.7 + deviation * 0.3;
        root.reading = {
            valid: true, freq: freq, cents: smoothed, target: target, midi: prevMidi,
            label: info.label, letter: info.letter, alter: info.alter, octave: info.octave,
            clarity: clarity
        };
    }

    function handleLine(line): void {
        if (!root.listening || !line || line.length === 0)
            return;
        let payload = null;
        try {
            payload = JSON.parse(line);
        } catch (error) {
            return;
        }
        if (!payload)
            return;
        const now = Date.now();
        root.level = Number(payload.level ?? 0);
        const freq = Number(payload.freq ?? 0);
        const clarity = Number(payload.clarity ?? 0);
        const usable = freq > 0 && clarity >= 0.55 && root.level >= 0.0025;
        if (!usable) {
            root.invalidFrames++;
            if (root.invalidFrames >= 7) {
                if (root.reading.valid) {
                    root.reading = { valid: false, freq: 0, cents: 0, label: "—", octave: 0, target: 0, midi: -1 };
                    root.candidateFrames = 0;
                }
                root.appendHistory(now, 0, false);
            }
            return;
        }

        root.invalidFrames = 0;
        root.recentFreqs.push(freq);
        if (root.recentFreqs.length > 5)
            root.recentFreqs.shift();
        const sorted = Array.from(root.recentFreqs).sort((a, b) => a - b);
        const median = sorted[Math.floor(sorted.length / 2)];
        let candidate = QanunData.tunerReading(median, root.a4, root.preferFlats, root.notation);
        candidate.clarity = clarity;

        if (!root.reading.valid && root.candidateMidi !== candidate.midi) {
            root.candidateMidi = candidate.midi;
            root.candidateFrames = 1;
        }
        if (!root.reading.valid && root.candidateMidi === candidate.midi) {
            root.candidateFrames++;
            if (root.candidateFrames < 2)
                return;
        }

        if (root.reading.valid && Number(root.reading.midi) !== candidate.midi) {
            // Hold the previous note until the new pitch has been stable for a
            // few frames. This is what stops a pluck's attack from throwing the
            // whole tuner across the screen.
            if (root.candidateMidi === candidate.midi) {
                root.candidateFrames++;
            } else {
                root.candidateMidi = candidate.midi;
                root.candidateFrames = 1;
            }
            if (root.candidateFrames < 3) {
                root.holdPreviousReading(median, clarity);
                return;
            }
        } else {
            root.candidateMidi = candidate.midi;
            root.candidateFrames = 0;
        }

        const previousMidi = root.reading.valid ? Number(root.reading.midi) : -1;
        const smoothedCents = previousMidi === candidate.midi
            ? root.reading.cents * 0.62 + candidate.cents * 0.38
            : candidate.cents;
        const target = QanunData.frequencyForMidi(candidate.midi, root.a4);
        const smoothedFreq = target * Math.pow(2, smoothedCents / 1200);
        root.reading = {
            valid: true,
            freq: smoothedFreq,
            cents: smoothedCents,
            target: target,
            midi: candidate.midi,
            label: candidate.label,
            letter: candidate.letter,
            alter: candidate.alter,
            octave: candidate.octave,
            clarity: clarity
        };
        root.appendHistory(now, smoothedCents, true);
    }

    function playReference(): void {
        QanunStore.playTone(69, 1.6);
    }

    function playCurrent(): void {
        if (root.reading.valid)
            QanunStore.playTone(root.reading.midi, 1.3);
        else
            root.playReference();
    }

    Component.onCompleted: {
        if (Boolean(root.tunerSettings.autoStart ?? true))
            Qt.callLater(() => root.startListening());
    }

    Component.onDestruction: root.stopListening()

    Process {
        id: tunerProcess
        stdout: SplitParser {
            onRead: line => root.handleLine(line)
        }
        stderr: SplitParser {
            onRead: line => {
                if (line && line.length > 0)
                    root.error = line;
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && root.wasListening)
                root.error = Translation.tr("The microphone could not be opened. Check the input device.");
            root.wasListening = false;
        }
    }

    Loader {
        anchors.fill: parent
        active: root.compact
        sourceComponent: StyledFlickable {
            contentWidth: width
            contentHeight: compactColumn.implicitHeight + 24
            clip: true

            ColumnLayout {
                id: compactColumn
                width: parent.width
                spacing: ClockStyle.gap
                anchors.margins: ClockStyle.gap
                TunerGraphPane { Layout.fillWidth: true; height: 210 }
                NotePane { Layout.fillWidth: true; Layout.preferredHeight: 240 }
                TunerControlsPane { Layout.fillWidth: true; Layout.preferredHeight: 430 }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.gap
        spacing: ClockStyle.gap
        visible: !root.compact

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: ClockStyle.gap

            TunerGraphPane {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 220
            }

            NotePane {
                Layout.fillWidth: true
                Layout.preferredHeight: root.horizontal ? 222 : 238
            }
        }

        TunerControlsPane {
            Layout.fillHeight: true
            Layout.preferredWidth: root.horizontal ? Math.max(408, Math.min(530, root.width * 0.38)) : 320
            Layout.minimumWidth: 320
        }
    }

    // ── Reusable panes ──────────────────────────────────────────────────
    component TunerGraphPane: Rectangle {
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
                    size: 36
                    text: "show_chart"
                    shape: MaterialShape.Shape.Cookie7Sided
                    color: ClockStyle.colPrimaryContainer
                    colSymbol: ClockStyle.colOnPrimaryContainer
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: Translation.tr("Pitch history")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: QanunStyle.colOnSurface
                    }
                    StyledText {
                        text: root.reading.valid
                            ? QanunStyle.centsLabel(root.reading.cents) + "  ·  " + QanunData.midiLabel(root.reading.midi, root.notation, root.preferFlats)
                            : (root.listening ? Translation.tr("Listening…") : Translation.tr("Start listening to trace a note"))
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: root.reading.valid ? root.statusColor : QanunStyle.colSubtext
                    }
                }

                RowLayout {
                    spacing: 3
                    Repeater {
                        model: 8
                        Rectangle {
                            required property int index
                            width: 4
                            height: 10 + Math.round(Math.min(1, root.level * 16) * 14 * ((index + 2) % 4 + 1) / 4)
                            radius: 2
                            color: index < Math.round(Math.min(1, root.level * 16) * 8)
                                ? QanunStyle.colInTune : Qt.alpha(QanunStyle.colOnSurface, 0.12)
                        }
                    }
                }
            }

            TunerGraph {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 140
                history: root.history
                maxSeconds: Number(root.tunerSettings.historySeconds ?? 14)
                inTuneCents: Number(root.tunerSettings.inTuneCents ?? 5)
                active: root.listening
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                MaterialSymbol {
                    text: root.listening ? "mic" : "mic_off"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.listening ? QanunStyle.colInTune : QanunStyle.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.error.length > 0 ? root.error
                        : root.listening ? Translation.tr("Live from the default input · 48 kHz")
                        : Translation.tr("Microphone off — no audio leaves this machine")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: root.error.length > 0 ? QanunStyle.colError : QanunStyle.colSubtext
                    elide: Text.ElideRight
                }

                ClockButton {
                    symbol: root.listening ? "stop_circle" : "mic"
                    label: root.listening ? Translation.tr("Stop") : Translation.tr("Listen")
                    variant: root.listening ? "tonal" : "filled"
                    onClicked: root.toggleListening()
                }
            }
        }
    }

    component NotePane: Rectangle {
        radius: ClockStyle.radiusCard
        color: ClockStyle.colPane
        implicitHeight: 238
        implicitWidth: 420
        clip: true

        RowLayout {
            anchors.fill: parent
            anchors.margins: ClockStyle.gapLarge
            spacing: ClockStyle.gapLarge

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                spacing: 0

                StyledText {
                    text: root.reading.valid ? root.reading.label : "—"
                    font.family: Appearance.font.family.title
                    font.variableAxes: ({ "wght": 780, "wdth": 60, "ROND": 100 })
                    font.pixelSize: Math.min(76, Math.max(48, root.height * 0.38))
                    color: root.statusColor
                    animateChange: true
                }

                StyledText {
                    text: root.reading.valid
                        ? (root.notation === "solfege" ? "" : (QanunData.solfegeNames[QanunData.letterNames.indexOf(root.reading.letter)] ?? ""))
                        : (root.listening ? Translation.tr("Waiting for a note") : Translation.tr("Tuner is idle"))
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: QanunStyle.colSubtext
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: false
                    spacing: ClockStyle.gapSmall
                    StyledText {
                        text: root.reading.valid ? root.reading.freq.toFixed(2) : "—"
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: Math.min(38, Math.max(26, root.height * 0.16))
                        font.variableAxes: ({ "wght": 620, "wdth": 38, "ROND": 100 })
                        color: QanunStyle.colOnSurface
                    }
                    StyledText {
                        text: "Hz"
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: QanunStyle.colSubtext
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: 6
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                Layout.maximumHeight: 110
                Layout.alignment: Qt.AlignVCenter
                color: Qt.alpha(QanunStyle.colOnSurface, 0.10)
            }

            ColumnLayout {
                Layout.preferredWidth: 180
                Layout.fillHeight: true
                spacing: 5

                InfoLine {
                    label: Translation.tr("Target")
                    value: root.reading.valid ? root.reading.target.toFixed(2) + " Hz" : "—"
                }
                InfoLine {
                    label: Translation.tr("Cents")
                    value: root.reading.valid ? QanunStyle.centsLabel(root.reading.cents) : "—"
                    valueColor: root.statusColor
                }
                InfoLine {
                    label: Translation.tr("Reference")
                    value: "A4 = " + root.a4.toFixed(0) + " Hz"
                }
                InfoLine {
                    label: root.instrument.id === "concert" ? Translation.tr("Concert") : Translation.tr("Written")
                    value: root.instrument.id === "concert" ? root.instrument.name : root.writtenNote
                }
                InfoLine {
                    label: Translation.tr("Status")
                    value: root.reading.valid
                        ? QanunStyle.tuningWord(root.reading.cents, Number(root.tunerSettings.inTuneCents ?? 5))
                        : (root.listening ? Translation.tr("Listening") : Translation.tr("Off"))
                    valueColor: root.statusColor
                }
            }
        }
    }

    component InfoLine: RowLayout {
        property string label: ""
        property string value: ""
        property color valueColor: QanunStyle.colOnSurface
        Layout.fillWidth: true
        spacing: ClockStyle.gapSmall

        StyledText {
            text: label
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: QanunStyle.colSubtext
        }
        Item { Layout.fillWidth: true }
        StyledText {
            text: value
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.DemiBold
            color: parent.valueColor
            elide: Text.ElideRight
        }
    }

    component TunerControlsPane: Rectangle {
        radius: ClockStyle.radiusCard
        color: ClockStyle.colPane

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: ClockStyle.gapLarge
            spacing: ClockStyle.gapSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                ClockBadge {
                    size: 38
                    text: "tune"
                    shape: MaterialShape.Shape.Sunny
                    color: ClockStyle.colTertiary
                    colSymbol: ClockStyle.colOnTertiary
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: Translation.tr("Tuner")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: QanunStyle.colOnSurface
                    }
                    StyledText {
                        text: root.instrument.name
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: QanunStyle.colSubtext
                        elide: Text.ElideRight
                    }
                }
                ClockIconButton {
                    symbol: root.listening ? "mic" : "mic_off"
                    tooltip: root.listening ? Translation.tr("Stop listening") : Translation.tr("Start listening")
                    toggled: root.listening
                    onClicked: root.toggleListening()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: ClockStyle.gapSmall

                TunerRuler {
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                    Layout.fillHeight: true
                    Layout.preferredWidth: 118
                    Layout.maximumWidth: 140
                    cents: root.reading.valid ? root.reading.cents : 0
                    inTuneCents: Number(root.tunerSettings.inTuneCents ?? 5)
                    noteLabel: root.reading.label
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 4

                    TuningSpinner {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 62
                        Layout.preferredHeight: 62
                        cents: root.reading.valid ? root.reading.cents : 0
                        active: root.listening
                        statusColor: root.statusColor
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.reading.valid ? root.reading.label : "—"
                        font.family: Appearance.font.family.title
                        font.variableAxes: ({ "wght": 760, "wdth": 60, "ROND": 100 })
                        font.pixelSize: 48
                        color: root.statusColor
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.reading.valid ? QanunStyle.centsLabel(root.reading.cents) : (root.listening ? Translation.tr("waiting") : "off")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.numbers
                        color: root.statusColor
                    }
                    ClockButton {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 6
                        symbol: "volume_up"
                        label: Translation.tr("A4")
                        variant: "tonal"
                        tooltip: Translation.tr("Play the A4 reference tone")
                        onClicked: root.playReference()
                    }
                    ClockButton {
                        Layout.alignment: Qt.AlignHCenter
                        symbol: "music_note"
                        label: Translation.tr("Hear note")
                        variant: "text"
                        enabled: root.reading.valid
                        onClicked: root.playCurrent()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Qt.alpha(QanunStyle.colOnSurface, 0.08)
            }

            StyledComboBox {
                Layout.fillWidth: true
                model: QanunData.tunerInstruments.map(item => item.name)
                currentIndex: Math.max(0, QanunData.tunerInstruments.findIndex(item => item.id === (root.general.instrument ?? "concert")))
                onActivated: index => QanunStore.setGeneral("instrument", QanunData.tunerInstruments[index].id)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                StyledText {
                    text: Translation.tr("A4")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: QanunStyle.colSubtext
                }
                ClockStepper {
                    Layout.fillWidth: true
                    value: Math.round(root.a4)
                    from: 415
                    to: 466
                    stepSize: 1
                    format: value => String(value) + " Hz"
                    onMoved: value => QanunStore.setGeneral("a4", value)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                StyledText {
                    text: Translation.tr("Name")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: QanunStyle.colSubtext
                }
                Item { Layout.fillWidth: true }
                Repeater {
                    model: QanunData.notationOptions
                    ClockChip {
                        required property var modelData
                        label: modelData.label
                        selected: root.notation === modelData.id
                        height_: 28
                        onClicked: QanunStore.setGeneral("notation", modelData.id)
                    }
                }
            }
        }
    }
}
