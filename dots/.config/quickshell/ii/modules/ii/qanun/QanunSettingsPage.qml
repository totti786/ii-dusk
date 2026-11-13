import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.qanun

/**
 * Qanun settings, grouped by the part of the app they change. Every control
 * writes through QanunStore immediately, so closing the page never discards a
 * choice.
 */
FocusScope {
    id: root

    property bool compact: false
    property bool wide: false
    property real layoutWidth: 0

    signal closeRequested()

    readonly property var general: QanunStore.settings.general ?? ({})
    readonly property var tuner: QanunStore.settings.tuner ?? ({})
    readonly property var metronome: QanunStore.settings.metronome ?? ({})
    readonly property var flashcards: QanunStore.settings.flashcards ?? ({})

    function setGeneral(key, value) {
        QanunStore.setGeneral(key, value);
    }
    function setTuner(key, value) {
        QanunStore.setTuner(key, value);
    }
    function setMetronome(key, value) {
        const patch = {};
        patch[key] = value;
        QanunStore.setMetronome(patch);
    }
    function setFlash(key, value) {
        const patch = {};
        patch[key] = value;
        QanunStore.setFlashcards(patch);
    }
    function setEar(key, value) {
        const patch = {};
        patch[key] = value;
        QanunStore.setEarTraining(patch);
    }

    focus: true
    Keys.onEscapePressed: root.closeRequested()

    Rectangle {
        anchors.fill: parent
        color: ClockStyle.colBackground
    }

    StyledFlickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: settingsColumn.implicitHeight + ClockStyle.gapHuge * 2
        clip: true

        ColumnLayout {
            id: settingsColumn
            width: Math.min(880, parent.width)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: ClockStyle.gap
            spacing: ClockStyle.gapHuge

            // ── Names & pitch ───────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Notes & pitch")
                symbol: "music_note"

                ClockSettingsRow {
                    first: true
                    symbol: "translate"
                    title: Translation.tr("Note names")
                    description: Translation.tr("Use letters, fixed solfège, or show both on note cards.")
                    Flow {
                        spacing: 4
                        Repeater {
                            model: QanunData.notationOptions
                            ClockChip {
                                required property var modelData
                                label: modelData.label
                                selected: String(root.general.notation ?? "letters") === modelData.id
                                height_: 30
                                onClicked: root.setGeneral("notation", modelData.id)
                            }
                        }
                    }
                }

                ClockSettingsRow {
                    symbol: "piano"
                    title: Translation.tr("Sharps or flats")
                    description: Translation.tr("How black-key notes are spelled away from a key signature.")
                    Flow {
                        spacing: 4
                        ClockChip {
                            label: "♯ Sharps"
                            selected: String(root.general.accidentalStyle ?? "sharps") === "sharps"
                            height_: 30
                            onClicked: root.setGeneral("accidentalStyle", "sharps")
                        }
                        ClockChip {
                            label: "♭ Flats"
                            selected: String(root.general.accidentalStyle ?? "sharps") === "flats"
                            height_: 30
                            onClicked: root.setGeneral("accidentalStyle", "flats")
                        }
                    }
                }

                ClockSettingsRow {
                    last: true
                    symbol: "graphic_eq"
                    title: Translation.tr("Reference pitch")
                    description: Translation.tr("Concert pitch for A4. The qanun and tuner both follow it.")
                    ClockStepper {
                        value: Math.round(Number(root.general.a4 ?? 440))
                        from: 415
                        to: 466
                        stepSize: 1
                        format: value => String(value) + " Hz"
                        onMoved: value => root.setGeneral("a4", value)
                    }
                }
            }

            // ── Tuner ───────────────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Tuner")
                symbol: "tune"

                ClockSettingsRow {
                    first: true
                    symbol: "mic"
                    title: Translation.tr("Start listening on open")
                    description: Translation.tr("Open the microphone when the Tuner tab appears. It stops when you leave the tab.")
                    StyledSwitch {
                        checked: Boolean(root.tuner.autoStart ?? true)
                        onClicked: root.setTuner("autoStart", !Boolean(root.tuner.autoStart ?? true))
                    }
                }

                ClockSettingsRow {
                    symbol: "straighten"
                    title: Translation.tr("In-tune window")
                    description: Translation.tr("Cents either side of the target that count as green.")
                    ClockStepper {
                        value: Number(root.tuner.inTuneCents ?? 5)
                        from: 2
                        to: 20
                        stepSize: 1
                        format: value => "±" + String(value) + " ¢"
                        onMoved: value => root.setTuner("inTuneCents", value)
                    }
                }

                ClockSettingsRow {
                    last: true
                    symbol: "history"
                    title: Translation.tr("Graph history")
                    description: Translation.tr("Seconds of pitch trace kept on the tuner graph.")
                    ClockStepper {
                        value: Number(root.tuner.historySeconds ?? 14)
                        from: 5
                        to: 30
                        stepSize: 1
                        format: value => String(value) + " s"
                        onMoved: value => root.setTuner("historySeconds", value)
                    }
                }
            }

            // ── Metronome ───────────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Metronome")
                symbol: "speed"

                ClockSettingsRow {
                    first: true
                    symbol: "speed"
                    title: Translation.tr("Default tempo")
                    description: Translation.tr("The tempo a new metronome page starts at.")
                    ClockStepper {
                        value: Number(root.metronome.bpm ?? 96)
                        from: 20
                        to: 320
                        stepSize: 1
                        format: value => String(value) + " BPM"
                        onMoved: value => QanunStore.setMetronome({ bpm: value })
                    }
                }

                ClockSettingsRow {
                    symbol: "volume_up"
                    title: Translation.tr("Click volume")
                    description: Translation.tr("Master level for both click tracks.")
                    RowLayout {
                        StyledSlider {
                            Layout.preferredWidth: 160
                            from: 0
                            to: 1
                            value: Number(root.metronome.volume ?? 0.8)
                            configuration: StyledSlider.Configuration.XS
                            onMoved: QanunStore.setMetronome({ volume: value })
                        }
                        StyledText {
                            text: Math.round(Number(root.metronome.volume ?? 0.8) * 100) + "%"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.numbers
                            color: QanunStyle.colSubtext
                        }
                    }
                }

                ClockSettingsRow {
                    symbol: "touch_app"
                    title: Translation.tr("Tap reset window")
                    description: Translation.tr("A pause longer than this starts a new tap-tempo measurement.")
                    ClockStepper {
                        value: Math.max(1, Math.min(5, Math.round(Number(root.metronome.tapResetMs ?? 2600) / 1000)))
                        from: 1
                        to: 5
                        stepSize: 1
                        format: value => String(value) + " s"
                        onMoved: value => QanunStore.setMetronome({ tapResetMs: Math.round(value * 1000) })
                    }
                }

                ClockSettingsRow {
                    symbol: "flare"
                    title: Translation.tr("Flash the beat")
                    description: Translation.tr("Pulse the metronome face on every beat.")
                    StyledSwitch {
                        checked: Boolean(root.metronome.flash ?? true)
                        onClicked: QanunStore.setMetronome({ flash: !Boolean(root.metronome.flash ?? true) })
                    }
                }

                ClockSettingsRow {
                    last: true
                    symbol: "timer"
                    title: Translation.tr("Count-in")
                    description: Translation.tr("Two bars of clicks before the click tracks begin.")
                    StyledSwitch {
                        checked: Boolean(root.metronome.countIn ?? false)
                        onClicked: QanunStore.setMetronome({ countIn: !Boolean(root.metronome.countIn ?? false) })
                    }
                }
            }

            // ── Flashcards ──────────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Flashcards")
                symbol: "school"

                ClockSettingsRow {
                    first: true
                    symbol: "text_fields"
                    title: Translation.tr("Answer style")
                    description: Translation.tr("Name the note, or play it on your instrument and let the microphone check it.")
                    Flow {
                        spacing: 4
                        ClockChip {
                            label: Translation.tr("Name")
                            selected: String(root.flashcards.answerMode ?? "name") === "name"
                            height_: 30
                            onClicked: root.setFlash("answerMode", "name")
                        }
                        ClockChip {
                            label: Translation.tr("Play (microphone)")
                            symbol: "mic"
                            selected: String(root.flashcards.answerMode ?? "name") === "mic"
                            height_: 30
                            onClicked: root.setFlash("answerMode", "mic")
                        }
                    }
                }

                ClockSettingsRow {
                    symbol: "piano"
                    title: Translation.tr("Clef")
                    description: Translation.tr("Which staff to draw for each question.")
                    Flow {
                        spacing: 4
                        Repeater {
                            model: [{ id: "treble", label: "Treble" }, { id: "bass", label: "Bass" }, { id: "both", label: "Both" }]
                            ClockChip {
                                required property var modelData
                                label: modelData.label
                                selected: String(root.flashcards.clef ?? "both") === modelData.id
                                height_: 30
                                onClicked: root.setFlash("clef", modelData.id)
                            }
                        }
                    }
                }

                ClockSettingsRow {
                    symbol: "tag"
                    title: Translation.tr("Accidentals")
                    description: Translation.tr("Include black-key notes in the question pool.")
                    StyledSwitch {
                        checked: Boolean(root.flashcards.accidentals ?? false)
                        onClicked: root.setFlash("accidentals", !Boolean(root.flashcards.accidentals ?? false))
                    }
                }

                ClockSettingsRow {
                    symbol: "mic"
                    title: Translation.tr("Microphone answers")
                    description: Translation.tr("Match the octave as well as the pitch, and how far from centre counts as the note.")
                    RowLayout {
                        spacing: 8
                        StyledText {
                            text: Translation.tr("Octave")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: QanunStyle.colSubtext
                        }
                        StyledSwitch {
                            checked: Boolean(root.flashcards.matchOctave ?? false)
                            onClicked: root.setFlash("matchOctave", !Boolean(root.flashcards.matchOctave ?? false))
                        }
                        ClockStepper {
                            value: Number(root.flashcards.micTolerance ?? 35)
                            from: 10
                            to: 60
                            stepSize: 5
                            format: value => "±" + String(value) + " ¢"
                            onMoved: value => root.setFlash("micTolerance", value)
                        }
                    }
                }

                ClockSettingsRow {
                    symbol: "volume_up"
                    title: Translation.tr("Play the answer")
                    description: Translation.tr("Sound the note when it is revealed.")
                    StyledSwitch {
                        checked: Boolean(root.flashcards.sound ?? true)
                        onClicked: root.setFlash("sound", !Boolean(root.flashcards.sound ?? true))
                    }
                }

                ClockSettingsRow {
                    symbol: "skip_next"
                    title: Translation.tr("Auto-advance")
                    description: Translation.tr("Move to the next card after a correct answer.")
                    StyledSwitch {
                        checked: Boolean(root.flashcards.autoAdvance ?? true)
                        onClicked: root.setFlash("autoAdvance", !Boolean(root.flashcards.autoAdvance ?? true))
                    }
                }

                ClockSettingsRow {
                    last: true
                    symbol: "restart_alt"
                    title: Translation.tr("Practice statistics")
                    description: Translation.tr("%1 answered · %2% correct · best streak %3")
                        .arg(String(QanunStore.stats.answered ?? 0))
                        .arg(String(QanunStore.accuracyPercent()))
                        .arg(String(QanunStore.stats.bestStreak ?? 0))
                    ClockButton {
                        symbol: "restart_alt"
                        label: Translation.tr("Reset")
                        variant: "text"
                        onClicked: QanunStore.resetStats()
                    }
                }
            }

            // ── Ear training ────────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Ear training")
                symbol: "hearing"

                ClockSettingsRow {
                    first: true
                    symbol: "category"
                    title: Translation.tr("Default exercise")
                    description: Translation.tr("Intervals, scales and maqamat, or chord qualities.")
                    Flow {
                        spacing: 4
                        Repeater {
                            model: [
                                { id: "intervals", label: Translation.tr("Intervals") },
                                { id: "notes", label: Translation.tr("Single note") },
                                { id: "scales", label: Translation.tr("Scales") },
                                { id: "chords", label: Translation.tr("Chords") }
                            ]
                            ClockChip {
                                required property var modelData
                                label: modelData.label
                                selected: String(QanunStore.settings.earTraining?.mode ?? "intervals") === modelData.id
                                height_: 30
                                onClicked: root.setEar("mode", modelData.id)
                            }
                        }
                    }
                }

                ClockSettingsRow {
                    symbol: "music_note"
                    title: Translation.tr("Single-note pool")
                    description: Translation.tr("Naturals only, or all twelve chromatic notes.")
                    Flow {
                        spacing: 4
                        ClockChip {
                            label: Translation.tr("Naturals")
                            selected: !Boolean(QanunStore.settings.earTraining?.singleNoteAccidentals ?? false)
                            height_: 30
                            onClicked: root.setEar("singleNoteAccidentals", false)
                        }
                        ClockChip {
                            label: Translation.tr("Chromatic")
                            selected: Boolean(QanunStore.settings.earTraining?.singleNoteAccidentals ?? false)
                            height_: 30
                            onClicked: root.setEar("singleNoteAccidentals", true)
                        }
                    }
                }

                ClockSettingsRow {
                    symbol: "play_circle"
                    title: Translation.tr("Play automatically")
                    description: Translation.tr("Play a new question as soon as it is shown.")
                    StyledSwitch {
                        checked: Boolean(QanunStore.settings.earTraining?.autoPlay ?? true)
                        onClicked: root.setEar("autoPlay", !Boolean(QanunStore.settings.earTraining?.autoPlay ?? true))
                    }
                }

                ClockSettingsRow {
                    symbol: "skip_next"
                    title: Translation.tr("Auto-advance")
                    description: Translation.tr("Move to the next question after a correct answer.")
                    StyledSwitch {
                        checked: Boolean(QanunStore.settings.earTraining?.autoAdvance ?? true)
                        onClicked: root.setEar("autoAdvance", !Boolean(QanunStore.settings.earTraining?.autoAdvance ?? true))
                    }
                }

                ClockSettingsRow {
                    last: true
                    symbol: "restart_alt"
                    title: Translation.tr("Ear training statistics")
                    description: Translation.tr("%1 answered · %2% correct · best streak %3")
                        .arg(String(QanunStore.earStats.answered ?? 0))
                        .arg(String(QanunStore.earAccuracyPercent()))
                        .arg(String(QanunStore.earStats.bestStreak ?? 0))
                    ClockButton {
                        symbol: "restart_alt"
                        label: Translation.tr("Reset")
                        variant: "text"
                        onClicked: QanunStore.resetEarTrainingStats()
                    }
                }
            }

            // ── Library & storage ───────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Library & recordings")
                symbol: "folder_open"

                ClockSettingsRow {
                    first: true
                    symbol: "public"
                    title: Translation.tr("Sheet music provider")
                    description: Translation.tr("OpenScore String Quartets is a CC0 corpus hosted on GitHub. Downloaded .mscx files stay in Documents/Qanun Scores.")
                    ClockButton {
                        symbol: "open_in_new"
                        label: Translation.tr("OpenScore")
                        variant: "text"
                        onClicked: QanunStore.openExternal("https://github.com/OpenScore/StringQuartets")
                    }
                }

                ClockSettingsRow {
                    symbol: "folder"
                    title: Translation.tr("Score folder")
                    description: Translation.tr("Downloaded scores and their cached previews.")
                    ClockButton {
                        symbol: "folder_open"
                        label: Translation.tr("Open folder")
                        variant: "tonal"
                        onClicked: QanunStore.openScoresFolder()
                    }
                }

                ClockSettingsRow {
                    last: true
                    symbol: "mic"
                    title: Translation.tr("Recordings")
                    description: Translation.tr("Takes are 48 kHz stereo WAV files in ~/Music/Recordings.")
                    ClockButton {
                        symbol: "folder_open"
                        label: Translation.tr("Open recordings")
                        variant: "tonal"
                        onClicked: AudioRecorderService.openFolder()
                    }
                }
            }

            // ── About ───────────────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("About")
                symbol: "info"

                ClockSettingsRow {
                    first: true
                    last: true
                    symbol: "auto_awesome"
                    title: Translation.tr("Qanun")
                    description: Translation.tr("A shell-native tuner, metronome, maqam and scale reference, sheet-music library and composer, recorder, and note-reading trainer. Built from the shell's Material tokens and the shared clock components.")
                    StyledText {
                        text: "CC0 · OpenScore"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: QanunStyle.colSubtext
                    }
                }
            }

            Item { Layout.preferredHeight: 8 }
        }
    }

    Component.onCompleted: root.forceActiveFocus()
}
