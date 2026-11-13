import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtMultimedia
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.qanun
import qs.modules.ii.qanun.components

/**
 * The metronome: a circular two-track display, a tempo dial that also accepts
 * dragging and tapping, count-in, accent pattern, per-track divisions and sound
 * packs, and a session timer. It follows Chronal's idea of two synchronized
 * click tracks rather than one fixed click.
 */
Item {
    id: root

    property bool compact: false
    property bool wide: false

    property int bpm: 96
    property int numerator: 4
    property int denominator: 4
    property var tracks: []
    property var accents: []
    property bool countIn: false
    property int countInBars: 1
    property bool accentFirst: true
    property bool flashEnabled: true
    property real volume: 0.8
    property int stopAfter: 0

    property bool running: false
    property bool counting: false
    property int countInRemaining: 0
    property int tickCounter: 0
    property int beatIndex: 0
    property real phase: 0
    property int flashSerial: 0
    property int sessionSeconds: 0
    property var tapTimes: []
    property bool tapPulse: false
    property bool settingsLoaded: false

    readonly property string pageSubtitle: root.bpm + " BPM · " + QanunData.tempoMarking(root.bpm)
        + " · " + root.numerator + "/" + root.denominator
    readonly property real beatInterval: 60000 / Math.max(20, root.bpm)
    readonly property real tickInterval: Math.max(4, root.beatInterval / 24)

    function applyTempoIntervals(): void {
        const beat = 60000 / Math.max(20, root.bpm);
        engineTimer.interval = Math.max(4, beat / 24);
        countInTimer.interval = beat;
        if (root.running && engineTimer.running)
            engineTimer.restart();
        if (root.counting && countInTimer.running)
            countInTimer.restart();
    }
    readonly property var activeTracks: root.tracks.filter(track => track && track.enabled !== false)

    signal closeRequested()

    function loadSettings(): void {
        const met = QanunStore.settings.metronome ?? {};
        root.bpm = Math.max(20, Math.min(320, Number(met.bpm ?? 96)));
        root.numerator = Math.max(1, Math.min(12, Number(met.numerator ?? 4)));
        root.denominator = [2, 4, 8, 16].includes(Number(met.denominator)) ? Number(met.denominator) : 4;
        root.tracks = JSON.parse(JSON.stringify(met.tracks ?? [
            { id: "pulse", name: "Pulse", enabled: true, division: 1, sound: "wood", volume: 0.85 },
            { id: "subdivision", name: "Subdivision", enabled: false, division: 2, sound: "click", volume: 0.55 }
        ]));
        root.accents = Array.from(met.accents ?? [1, 0, 0, 0]).slice(0, root.numerator);
        while (root.accents.length < root.numerator)
            root.accents.push(0);
        root.countIn = Boolean(met.countIn ?? false);
        root.countInBars = Math.max(1, Number(met.countInBars ?? 1));
        root.accentFirst = Boolean(met.accentFirst ?? true);
        root.flashEnabled = Boolean(met.flash ?? true);
        root.volume = Number(met.volume ?? 0.8);
        root.settingsLoaded = true;
    }

    function persist(): void {
        if (!root.settingsLoaded)
            return;
        QanunStore.setMetronome({
            bpm: root.bpm,
            numerator: root.numerator,
            denominator: root.denominator,
            tracks: JSON.parse(JSON.stringify(root.tracks)),
            accents: Array.from(root.accents),
            countIn: root.countIn,
            countInBars: root.countInBars,
            accentFirst: root.accentFirst,
            flash: root.flashEnabled,
            volume: root.volume
        });
    }

    function setBpm(value: int): void {
        const next = Math.max(20, Math.min(320, Math.round(Number(value) || 96)));
        if (next === root.bpm)
            return;
        root.bpm = next;
        root.persist();
    }

    function minutesLabel(seconds): string {
        const safe = Math.max(0, Math.floor(seconds));
        const minutes = Math.floor(safe / 60);
        const secs = safe % 60;
        return String(minutes).padStart(2, "0") + ":" + String(secs).padStart(2, "0");
    }

    function soundUrl(pack, kind): url {
        const safePack = ["click", "wood", "beep"].includes(String(pack)) ? String(pack) : "wood";
        return Qt.resolvedUrl("../assets/audio/" + safePack + "-" + kind + ".wav");
    }

    function trackSound(index): string {
        return String(root.tracks[index]?.sound ?? "wood");
    }

    function trackVolume(index): real {
        const trackVolume = Number(root.tracks[index]?.volume ?? 0.7);
        return Math.max(0, Math.min(1, trackVolume * root.volume));
    }

    function playTrack(index, kind): void {
        const effects = [
            [track0Accent, track0Beat, track0Sub],
            [track1Accent, track1Beat, track1Sub]
        ];
        const bank = effects[index];
        if (!bank)
            return;
        const effect = kind === "accent" ? bank[0] : kind === "sub" ? bank[2] : bank[1];
        try {
            effect.play();
        } catch (error) {
            // SoundEffect may not have a ready source on the first frame; the
            // next tick will try again.
        }
    }

    function onBeat(): void {
        root.beatIndex = root.tickCounter % (root.numerator * 24) / 24;
        root.phase = 0;
        root.flashSerial++;
        const accent = root.beatIndex === 0 ? (root.accentFirst ? 1 : Number(root.accents[0] ?? 0))
            : Number(root.accents[root.beatIndex] ?? 0);
        for (let i = 0; i < root.tracks.length; ++i) {
            const track = root.tracks[i];
            if (!track || track.enabled === false)
                continue;
            root.playTrack(i, accent ? "accent" : "beat");
        }
    }

    function onTick(): void {
        const beatTick = root.tickCounter % 24;
        root.phase = beatTick / 24;
        if (beatTick === 0)
            root.onBeat();
        // Subdivision dots for each track.
        for (let i = 0; i < root.tracks.length; ++i) {
            const track = root.tracks[i];
            if (!track || track.enabled === false)
                continue;
            const division = Math.max(1, Math.min(8, Number(track.division ?? 1)));
            if (division <= 1)
                continue;
            const step = 24 / division;
            if (Math.abs(Math.round(step) - step) > 0.01)
                continue;
            if (beatTick !== 0 && beatTick % Math.round(step) === 0)
                root.playTrack(i, "sub");
        }
        root.tickCounter = (root.tickCounter + 1) % (root.numerator * 24);
    }

    function beginEngine(): void {
        root.counting = false;
        root.running = true;
        root.tickCounter = 0;
        root.beatIndex = 0;
        root.phase = 0;
        root.sessionSeconds = 0;
        root.applyTempoIntervals();
        sessionTimer.start();
        engineTimer.start();
        if (root.accentFirst && root.accents[0] !== 1) {
            root.accents[0] = 1;
            root.persist();
        }
    }

    function start(): void {
        if (root.running || root.counting)
            return;
        if (root.countIn) {
            root.counting = true;
            root.countInRemaining = Math.max(1, root.countInBars) * root.numerator;
            root.beatIndex = 0;
            root.phase = 0;
            countInTimer.start();
            root.playTrack(0, "accent");
        } else {
            root.beginEngine();
        }
    }

    function stop(): void {
        root.running = false;
        root.counting = false;
        root.countInRemaining = 0;
        engineTimer.stop();
        countInTimer.stop();
        sessionTimer.stop();
        root.phase = 0;
        try {
            track0Accent.stop();
            track0Beat.stop();
            track0Sub.stop();
            track1Accent.stop();
            track1Beat.stop();
            track1Sub.stop();
        } catch (error) {
            // Effects may not have loaded yet.
        }
    }

    function toggle(): void {
        if (root.running || root.counting)
            root.stop();
        else
            root.start();
    }

    function tap(): void {
        const now = Date.now();
        const reset = Number(QanunStore.settings.metronome.tapResetMs ?? 2600);
        if (root.tapTimes.length > 0 && now - root.tapTimes[root.tapTimes.length - 1] > reset)
            root.tapTimes = [];
        root.tapTimes.push(now);
        if (root.tapTimes.length > 6)
            root.tapTimes.shift();
        root.tapPulse = false;
        root.tapPulse = true;
        if (root.tapTimes.length >= 2) {
            let total = 0;
            for (let i = 1; i < root.tapTimes.length; ++i)
                total += root.tapTimes[i] - root.tapTimes[i - 1];
            const average = total / (root.tapTimes.length - 1);
            if (average > 100)
                root.setBpm(Math.round(60000 / average));
        }
    }

    function setNumerator(value: int): void {
        const next = Math.max(1, Math.min(12, value));
        root.numerator = next;
        const nextAccents = Array.from(root.accents).slice(0, next);
        while (nextAccents.length < next)
            nextAccents.push(0);
        if (nextAccents[0] !== 1 && root.accentFirst)
            nextAccents[0] = 1;
        root.accents = nextAccents;
        root.persist();
    }

    function toggleAccent(index: int): void {
        const next = Array.from(root.accents);
        next[index] = next[index] ? 0 : 1;
        root.accents = next;
        root.persist();
    }

    function updateTrack(index: int, patch): void {
        const next = JSON.parse(JSON.stringify(root.tracks));
        if (!next[index])
            return;
        next[index] = Object.assign({}, next[index], patch);
        root.tracks = next;
        root.persist();
    }

    function addTrack(): void {
        if (root.tracks.length >= 2)
            return;
        const next = JSON.parse(JSON.stringify(root.tracks));
        next.push({
            id: "track" + (next.length + 1), name: "Track " + (next.length + 1),
            enabled: true, division: 2, sound: "click", volume: 0.58
        });
        root.tracks = next;
        root.persist();
    }

    function removeTrack(index: int): void {
        if (root.tracks.length <= 1)
            return;
        const next = JSON.parse(JSON.stringify(root.tracks));
        next.splice(index, 1);
        root.tracks = next;
        root.persist();
    }

    Component.onCompleted: root.loadSettings()
    Component.onDestruction: root.stop()

    Connections {
        target: QanunStore
        function onAudioStopRequested() {
            root.stop();
        }
    }

    onBpmChanged: {
        root.applyTempoIntervals();
    }

    Timer {
        id: engineTimer
        interval: 26
        repeat: true
        onTriggered: root.onTick()
    }

    Timer {
        id: countInTimer
        interval: 625
        repeat: true
        onTriggered: {
            if (!root.counting) {
                stop();
                return;
            }
            root.countInRemaining -= 1;
            if (root.countInRemaining <= 0) {
                countInTimer.stop();
                root.beginEngine();
            } else {
                root.playTrack(0, root.countInRemaining % root.numerator === 0 ? "accent" : "beat");
            }
        }
    }

    Timer {
        id: sessionTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (!root.running)
                return;
            root.sessionSeconds += 1;
            if (root.stopAfter > 0 && root.sessionSeconds >= root.stopAfter * 60)
                root.stop();
        }
    }

    SoundEffect { id: track0Accent; source: root.soundUrl(root.trackSound(0), "accent"); volume: root.trackVolume(0) }
    SoundEffect { id: track0Beat; source: root.soundUrl(root.trackSound(0), "beat"); volume: root.trackVolume(0) }
    SoundEffect { id: track0Sub; source: root.soundUrl(root.trackSound(0), "sub"); volume: root.trackVolume(0) }
    SoundEffect { id: track1Accent; source: root.soundUrl(root.trackSound(1), "accent"); volume: root.trackVolume(1) }
    SoundEffect { id: track1Beat; source: root.soundUrl(root.trackSound(1), "beat"); volume: root.trackVolume(1) }
    SoundEffect { id: track1Sub; source: root.soundUrl(root.trackSound(1), "sub"); volume: root.trackVolume(1) }

    // ── Layout ──────────────────────────────────────────────────────────
    Loader {
        anchors.fill: parent
        active: root.compact
        sourceComponent: StyledFlickable {
            contentWidth: width
            contentHeight: compactBody.implicitHeight + ClockStyle.gap * 2
            clip: true

            ColumnLayout {
                id: compactBody
                width: parent.width
                anchors.margins: ClockStyle.gap
                spacing: ClockStyle.gap

                MetronomeFace { Layout.fillWidth: true; Layout.preferredHeight: 390 }
                ControlPane { Layout.fillWidth: true }
                TracksPane { Layout.fillWidth: true }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.gap
        spacing: ClockStyle.gap
        visible: !root.compact

        MetronomeFace {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 340
        }

        ColumnLayout {
            Layout.preferredWidth: root.wide ? 370 : 330
            Layout.minimumWidth: 300
            Layout.fillHeight: true
            spacing: ClockStyle.gap

            ControlPane {
                Layout.fillWidth: true
            }
            TracksPane {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }

    // ── Face: dial, beats, transport ────────────────────────────────────
    component MetronomeFace: Rectangle {
        radius: ClockStyle.radiusCard
        color: ClockStyle.colPane
        clip: true

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: root.flashEnabled && root.running ? 2 : 0
            border.color: Qt.alpha(QanunStyle.colPrimary, Math.max(0, 0.5 - root.phase * 0.5))
            opacity: root.flashEnabled ? 1 : 0
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: ClockStyle.gap
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: ClockStyle.gapSmall
                Layout.rightMargin: ClockStyle.gapSmall
                Layout.topMargin: ClockStyle.gapTiny

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: root.counting ? Translation.tr("Count in") : Translation.tr("Metronome")
                        font.family: Appearance.font.family.title
                        font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: QanunStyle.colOnSurface
                    }
                    StyledText {
                        text: root.running ? Translation.tr("Playing") : (root.counting ? String(root.countInRemaining) : Translation.tr("Ready"))
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: root.running ? QanunStyle.colInTune : QanunStyle.colSubtext
                    }
                }

                RowLayout {
                    spacing: 2
                    Repeater {
                        model: root.numerator
                        Rectangle {
                            required property int index
                            readonly property bool active: root.running && index === root.beatIndex
                            width: active ? 18 : 8
                            height: 8
                            radius: 4
                            color: active ? QanunStyle.colPrimary
                                : (root.accents[index] ? Qt.alpha(QanunStyle.colPrimary, 0.55) : Qt.alpha(QanunStyle.colOnSurface, 0.15))
                            Behavior on width {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                MetronomeDial {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height)
                    height: width
                    bpm: root.bpm
                    numerator: root.numerator
                    denominator: root.denominator
                    playing: root.running
                    beatIndex: root.beatIndex
                    phase: root.phase
                    divisions: root.tracks.map(track => Number(track.division ?? 1))
                    accents: root.accents
                    flashSerial: root.flashSerial
                    counting: root.counting
                    onTempoDragged: value => root.setBpm(value)
                }

                // The count-in number is too important to hide inside the dial.
                StyledText {
                    visible: root.counting
                    anchors.centerIn: parent
                    text: String(root.countInRemaining)
                    font.family: Appearance.font.family.numbers
                    font.variableAxes: ({ "wght": 760, "wdth": 40, "ROND": 100 })
                    font.pixelSize: 120
                    color: Qt.alpha(QanunStyle.colPrimary, 0.24)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: ClockStyle.gap
                spacing: ClockStyle.gapSmall

                ClockIconButton {
                    symbol: "remove"
                    tooltip: Translation.tr("Tempo down")
                    size: 36
                    onClicked: root.setBpm(root.bpm - 1)
                }

                PlayPauseButton {
                    Layout.alignment: Qt.AlignHCenter
                    size: 72
                    playing: root.running
                    counting: root.counting
                    onClicked: root.toggle()
                }

                ClockIconButton {
                    symbol: "add"
                    tooltip: Translation.tr("Tempo up")
                    size: 36
                    onClicked: root.setBpm(root.bpm + 1)
                }

                Item { Layout.fillWidth: true }

                ColumnLayout {
                    spacing: 0
                    StyledText {
                        Layout.alignment: Qt.AlignRight
                        text: root.minutesLabel(root.sessionSeconds)
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: QanunStyle.colOnSurface
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignRight
                        text: Translation.tr("session")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: QanunStyle.colSubtext
                    }
                }

                ClockButton {
                    symbol: "touch_app"
                    label: Translation.tr("Tap")
                    variant: "tonal"
                    onClicked: root.tap()
                }
            }
        }
    }

    // ── Tempo / time signature pane ─────────────────────────────────────
    component ControlPane: Rectangle {
        radius: ClockStyle.radiusCard
        color: ClockStyle.colPane
        implicitHeight: controlColumn.implicitHeight + ClockStyle.gapLarge * 2

        ColumnLayout {
            id: controlColumn
            anchors.fill: parent
            anchors.margins: ClockStyle.gapLarge
            spacing: ClockStyle.gapSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall
                ClockBadge {
                    size: 34
                    text: "speed"
                    shape: MaterialShape.Shape.Cookie7Sided
                    color: ClockStyle.colPrimaryContainer
                    colSymbol: ClockStyle.colOnPrimaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Tempo & meter")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: QanunStyle.colOnSurface
                }
                StyledText {
                    text: QanunData.tempoMarking(root.bpm)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: QanunStyle.colTertiary
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                ClockIconButton {
                    symbol: "remove"
                    tooltip: Translation.tr("Decrease tempo")
                    size: 36
                    onClicked: root.setBpm(root.bpm - 1)
                }

                MaterialTextField {
                    id: bpmField
                    Layout.fillWidth: true
                    Layout.minimumWidth: 80
                    text: String(root.bpm)
                    horizontalAlignment: TextInput.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.numbers
                    inputMethodHints: Qt.ImhDigitsOnly
                    onAccepted: {
                        const value = Number(bpmField.text);
                        if (!isNaN(value))
                            root.setBpm(value);
                        bpmField.text = String(root.bpm);
                        root.forceActiveFocus();
                    }
                    onEditingFinished: {
                        const value = Number(bpmField.text);
                        if (!isNaN(value) && String(Math.round(value)) !== String(root.bpm))
                            root.setBpm(value);
                        bpmField.text = String(root.bpm);
                    }
                }

                ClockIconButton {
                    symbol: "add"
                    tooltip: Translation.tr("Increase tempo")
                    size: 36
                    onClicked: root.setBpm(root.bpm + 1)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                StyledText {
                    text: Translation.tr("Time")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: QanunStyle.colSubtext
                }

                ClockStepper {
                    Layout.fillWidth: true
                    value: root.numerator
                    from: 1
                    to: 12
                    format: value => String(value)
                    onMoved: value => root.setNumerator(value)
                }

                Repeater {
                    model: [2, 4, 8, 16]
                    ClockChip {
                        required property int modelData
                        label: "/" + String(modelData)
                        selected: root.denominator === modelData
                        height_: 28
                        onClicked: {
                            root.denominator = modelData;
                            root.persist();
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                StyledText {
                    text: Translation.tr("Accents")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: QanunStyle.colSubtext
                }
                Item { Layout.fillWidth: true }
                Repeater {
                    model: root.numerator
                    Rectangle {
                        required property int index
                        width: 28
                        height: 28
                        radius: Appearance.rounding.full
                        color: root.accents[index] ? QanunStyle.colPrimary : Qt.alpha(QanunStyle.colOnSurface, 0.10)
                        StyledText {
                            anchors.centerIn: parent
                            text: String(index + 1)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: root.accents[index] ? QanunStyle.colOnPrimary : QanunStyle.colOnSurfaceVariant
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleAccent(index)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall
                StyledText {
                    text: Translation.tr("Count-in")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: QanunStyle.colSubtext
                }
                StyledSwitch {
                    checked: root.countIn
                    onClicked: {
                        root.countIn = !root.countIn;
                        root.persist();
                    }
                }
                Item { Layout.fillWidth: true }
                Repeater {
                    model: [1, 2]
                    ClockChip {
                        required property int modelData
                        label: Translation.tr("%1 bar").arg(String(modelData))
                        selected: root.countInBars === modelData
                        height_: 28
                        onClicked: {
                            root.countInBars = modelData;
                            root.persist();
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall
                StyledText {
                    text: Translation.tr("Stop after")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: QanunStyle.colSubtext
                }
                Item { Layout.fillWidth: true }
                Repeater {
                    model: [0, 5, 10, 30]
                    ClockChip {
                        required property int modelData
                        label: modelData === 0 ? Translation.tr("Off") : String(modelData) + "m"
                        selected: root.stopAfter === modelData
                        height_: 28
                        onClicked: root.stopAfter = modelData
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                MaterialSymbol {
                    text: "volume_up"
                    iconSize: Appearance.font.pixelSize.normal
                    color: QanunStyle.colSubtext
                }
                StyledSlider {
                    Layout.fillWidth: true
                    from: 0
                    to: 1
                    value: root.volume
                    configuration: StyledSlider.Configuration.XS
                    onMoved: {
                        root.volume = value;
                        root.persist();
                    }
                }
                StyledText {
                    Layout.preferredWidth: 36
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(root.volume * 100) + "%"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.family: Appearance.font.family.numbers
                    color: QanunStyle.colSubtext
                }
            }
        }
    }

    // ── Click tracks ────────────────────────────────────────────────────
    component TracksPane: Rectangle {
        radius: ClockStyle.radiusCard
        color: ClockStyle.colPane
        implicitHeight: tracksColumn.implicitHeight + ClockStyle.gapLarge * 2

        ColumnLayout {
            id: tracksColumn
            anchors.fill: parent
            anchors.margins: ClockStyle.gapLarge
            spacing: ClockStyle.gapSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall
                ClockBadge {
                    size: 34
                    text: "graphic_eq"
                    shape: MaterialShape.Shape.Cookie9Sided
                    color: ClockStyle.colTertiaryContainer
                    colSymbol: ClockStyle.colOnTertiaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Click tracks")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: QanunStyle.colOnSurface
                }
                ClockIconButton {
                    visible: root.tracks.length < 2
                    symbol: "add"
                    tooltip: Translation.tr("Add a second click track")
                    size: 32
                    onClicked: root.addTrack()
                }
            }

            Repeater {
                model: root.tracks.length
                MetronomeTrackRow {
                    required property int index
                    Layout.fillWidth: true
                    track: root.tracks[index]
                    accent: index === 0 ? QanunStyle.colTrackPulse : QanunStyle.colTrackSubdivision
                    expanded: index === 0 ? track0Expanded : track1Expanded
                    removable: root.tracks.length > 1
                    onPatchRequested: patch => root.updateTrack(index, patch)
                    onRemoveRequested: root.removeTrack(index)
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Each track can divide the beat independently. Dots on the dial follow the division.")
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: QanunStyle.colSubtext
            }

            Item { Layout.fillHeight: true }
        }

        property bool track0Expanded: true
        property bool track1Expanded: false
    }

    // Store per-track expansion outside the Repeater delegates so the rows do
    // not collapse when the model array is replaced.
    property bool track0Expanded: true
    property bool track1Expanded: false
}
