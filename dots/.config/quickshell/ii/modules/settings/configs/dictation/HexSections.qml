pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Hex's dictation settings on the shell's Dictation page. Every control reads and
 * writes Hex's own settings through `HexSettings`; the one exception is the idle
 * quit, which is the shell's.
 */
ColumnLayout {
    id: root
    spacing: 12

    readonly property string idleMode: Config.options.dictation.hexIdleMinutes > 0 ? "quit"
        : HexSettings.on("labs.unload_idle") ? "unload" : "keep"

    function setIdleMode(mode: string): void {
        HexSettings.set("labs.unload_idle", mode === "unload");
        if (mode !== "quit")
            Config.options.dictation.hexIdleMinutes = 0;
        else if (Config.options.dictation.hexIdleMinutes <= 0)
            Config.options.dictation.hexIdleMinutes = 10;
    }

    // Hebrew-only models are left out, as in the shell's other language lists.
    readonly property var models: HexSettings.models.filter(model => !(model.languages.length === 1 && model.languages[0] === "he"))
    readonly property var installedModels: root.models.filter(model => model.installed)
    readonly property string selectedModel: HexSettings.get("transcription.model") ?? ""
    readonly property string selectedLanguage: HexSettings.get("transcription.language") ?? ""
    readonly property var selectedEntry: root.models.find(model => model.id === root.selectedModel) ?? null

    function languageName(code: string): string {
        if (code === "auto")
            return Translation.tr("Auto-detect");
        if (code === "*")
            return Translation.tr("Many languages");
        const name = Qt.locale(code).nativeLanguageName;
        return Qt.locale(code).name.startsWith(code) && name.length > 0 ? name : code;
    }

    function languageSummary(languages: var): string {
        if (languages.length > 3)
            return Translation.tr("%1 languages").arg(languages.filter(code => code !== "auto" && code !== "*").length);
        return languages.map(code => root.languageName(code)).join(", ");
    }

    function useModel(model: var): void {
        const languages = model.languages.filter(code => code !== "*");
        const language = [root.selectedLanguage, "en", "auto", languages[0]].find(code => languages.indexOf(code) !== -1);
        const changes = {
            "transcription.model": model.id
        };
        if (language !== undefined)
            changes["transcription.language"] = language;
        HexSettings.setMany(changes);
    }

    component Note: StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    component VolumeSlider: ConfigSlider {
        id: slider
        required property string hexKey
        enabled: HexSettings.loaded
        from: 0
        to: 1
        Binding on value {
            value: Number(HexSettings.get(slider.hexKey) ?? 0)
        }
        // Saved once the handle has settled, not on every step of a drag.
        onValueChanged: saveTimer.restart()
        Timer {
            id: saveTimer
            interval: 400
            onTriggered: {
                if (slider.pressed)
                    restart();
                else
                    HexSettings.set(slider.hexKey, Math.round(slider.value * 100) / 100);
            }
        }
    }

    Note {
        visible: HexSettings.error.length > 0
        text: HexSettings.error
        color: Appearance.colors.colError
    }

    // ── Running ──────────────────────────────────────────────────────────────
    ContentSection {
        icon: "bolt"
        title: Translation.tr("Hex")

        Note {
            visible: !HexSettings.loaded
            text: Translation.tr("Hex has not saved any settings yet. Open it once and they appear here.")
        }

        ContentSubsection {
            title: Translation.tr("After a quiet spell")
            icon: "timer"
            Layout.fillWidth: true

            ConfigSelectionArray {
                enabled: HexSettings.loaded
                currentValue: root.idleMode
                onSelected: newValue => root.setIdleMode(newValue)
                options: [
                    {
                        displayName: Translation.tr("Free the model"),
                        icon: "memory",
                        value: "unload"
                    },
                    {
                        displayName: Translation.tr("Quit Hex"),
                        icon: "power_settings_new",
                        value: "quit"
                    },
                    {
                        displayName: Translation.tr("Keep it ready"),
                        icon: "bolt",
                        value: "keep"
                    }
                ]
            }

            Note {
                text: root.idleMode === "unload"
                    ? Translation.tr("Hex keeps running and unloads only the speech model. The next dictation loads it again.")
                    : root.idleMode === "quit"
                        ? Translation.tr("The shell quits Hex, so nothing stays in memory. The next key press starts it again, which takes a few seconds.")
                        : Translation.tr("Hex and its model stay in memory once started, so dictation begins at once.")
            }

            ConfigSelectionArray {
                visible: root.idleMode === "unload"
                currentValue: HexSettings.get("labs.unload_idle_minutes")
                onSelected: newValue => HexSettings.set("labs.unload_idle_minutes", newValue)
                options: [5, 15, 30, 60].map(minutes => ({
                            displayName: Translation.tr("%1 min").arg(minutes),
                            value: minutes
                        }))
            }
        }

        ConfigSpinBox {
            visible: root.idleMode === "quit"
            icon: "timer"
            text: Translation.tr("Quit Hex after (minutes idle)")
            value: Config.options.dictation.hexIdleMinutes
            from: 0
            to: 120
            stepSize: 1
            onValueChanged: {
                if (visible)
                    Config.options.dictation.hexIdleMinutes = value;
            }
        }

        Note {
            text: Translation.tr("These settings are Hex's own: changes made here or in the Hex window show in both. Only one dictation engine runs at a time.")
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "open_in_new"
            mainText: Translation.tr("Open Hex for modes, replacements and history")
            onClicked: HexSettings.runStarted(["app"])
        }
    }

    // ── Model ────────────────────────────────────────────────────────────────
    ContentSection {
        icon: "graphic_eq"
        title: Translation.tr("Hex speech model")

        Note {
            visible: root.models.length === 0
            text: Translation.tr("The model list comes from Hex itself. Loading it starts Hex.")
        }

        StyledComboBox {
            id: modelBox
            visible: root.installedModels.length > 0
            buttonIcon: "graphic_eq"
            textRole: "displayName"
            model: root.installedModels.map(entry => ({
                        displayName: `${entry.name} · ${entry.size}`,
                        id: entry.id
                    }))
            // Re-asserted when a switch is refused or made in the Hex window.
            readonly property int selectedIndex: root.installedModels.findIndex(entry => entry.id === root.selectedModel)
            Binding on currentIndex {
                value: modelBox.selectedIndex
            }
            // A new list resets the box without the selected index having changed.
            onModelChanged: Qt.callLater(() => modelBox.currentIndex = modelBox.selectedIndex)
            onActivated: index => root.useModel(root.installedModels[index])
        }

        ContentSubsection {
            visible: (root.selectedEntry?.languages.filter(code => code !== "*").length ?? 0) > 1
            title: Translation.tr("Dictation language")
            icon: "translate"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: root.selectedLanguage
                onSelected: newValue => HexSettings.set("transcription.language", newValue)
                options: (root.selectedEntry?.languages ?? []).filter(code => code !== "*").map(code => ({
                            displayName: root.languageName(code),
                            value: code
                        }))
            }
        }

        ContentSubsection {
            visible: root.models.some(model => !model.installed)
            title: Translation.tr("Download another model")
            icon: "cloud_download"
            Layout.fillWidth: true
            collapsible: true
            expanded: false

            Repeater {
                model: root.models.filter(entry => !entry.installed)

                delegate: RowLayout {
                    id: modelRow
                    required property var modelData
                    readonly property bool downloading: HexSettings.installingModel === modelData.id
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: modelRow.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer0
                            wrapMode: Text.Wrap
                        }

                        Note {
                            text: modelRow.downloading ? Translation.tr("Downloading…")
                                : `${modelRow.modelData.size} · ${root.languageSummary(modelRow.modelData.languages)}`
                        }
                    }

                    RippleButtonWithIcon {
                        enabled: modelRow.downloading || HexSettings.installingModel.length === 0
                        materialIcon: modelRow.downloading ? "close" : "download"
                        mainText: modelRow.downloading ? Translation.tr("Cancel") : Translation.tr("Download")
                        onClicked: modelRow.downloading ? HexSettings.cancelInstall()
                            : HexSettings.installModel(modelRow.modelData.id)
                    }
                }
            }
        }

        StyledIndeterminateProgressBar {
            Layout.fillWidth: true
            visible: HexSettings.installingModel.length > 0
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            enabled: !HexSettings.busy
            materialIcon: "refresh"
            mainText: root.models.length === 0 ? Translation.tr("Load the model list") : Translation.tr("Refresh the model list")
            onClicked: HexSettings.loadModels()
        }

        ContentSubsection {
            title: Translation.tr("Run the model on")
            icon: "developer_board"
            Layout.fillWidth: true

            ConfigSelectionArray {
                enabled: HexSettings.loaded
                currentValue: HexSettings.get("transcription_device")
                onSelected: newValue => HexSettings.set("transcription_device", newValue)
                options: [
                    {
                        displayName: Translation.tr("Automatic"),
                        icon: "auto_awesome",
                        value: "auto"
                    },
                    {
                        displayName: Translation.tr("Graphics"),
                        icon: "developer_board",
                        value: "gpu"
                    },
                    {
                        displayName: Translation.tr("Processor"),
                        icon: "memory",
                        value: "cpu"
                    }
                ]
            }
        }
    }

    // ── Microphone ───────────────────────────────────────────────────────────
    ContentSection {
        icon: "mic"
        title: Translation.tr("Microphone")

        ConfigSwitch {
            buttonIcon: "mic_off"
            text: Translation.tr("Turn the microphone off between dictations")
            enabled: HexSettings.loaded
            Binding on checked {
                value: HexSettings.on("release_microphone_while_idle")
            }
            onCheckedChanged: HexSettings.set("release_microphone_while_idle", checked)
        }

        ConfigSwitch {
            buttonIcon: "hourglass_top"
            text: Translation.tr("Keep the microphone open for a while after dictating")
            description: Translation.tr("The next dictation starts at once")
            enabled: HexSettings.loaded && HexSettings.on("release_microphone_while_idle")
            Binding on checked {
                value: HexSettings.on("labs.keep_microphone_open")
            }
            onCheckedChanged: HexSettings.set("labs.keep_microphone_open", checked)
        }

        ConfigSelectionArray {
            visible: HexSettings.on("release_microphone_while_idle") && HexSettings.on("labs.keep_microphone_open")
            currentValue: HexSettings.get("labs.keep_microphone_open_seconds")
            onSelected: newValue => HexSettings.set("labs.keep_microphone_open_seconds", newValue)
            options: [
                {
                    displayName: Translation.tr("%1 s").arg(30),
                    value: 30
                }
            ].concat([1, 3, 5, 30].map(minutes => ({
                        displayName: Translation.tr("%1 min").arg(minutes),
                        value: minutes * 60
                    })))
        }

        ConfigSwitch {
            buttonIcon: "bluetooth_disabled"
            text: Translation.tr("Don't record from a Bluetooth headset")
            description: Translation.tr("With the default input, use the built-in or a wired microphone")
            enabled: HexSettings.loaded
            Binding on checked {
                value: HexSettings.on("avoid_bluetooth_microphone")
            }
            onCheckedChanged: HexSettings.set("avoid_bluetooth_microphone", checked)
        }
    }

    // ── Sounds and other audio ───────────────────────────────────────────────
    ContentSection {
        icon: "volume_up"
        title: Translation.tr("Sound")

        ConfigSwitch {
            buttonIcon: "notifications_active"
            text: Translation.tr("Recording and error tones")
            enabled: HexSettings.loaded
            Binding on checked {
                value: HexSettings.on("sound_effects")
            }
            onCheckedChanged: HexSettings.set("sound_effects", checked)
        }

        VolumeSlider {
            visible: HexSettings.on("sound_effects")
            buttonIcon: "volume_up"
            text: Translation.tr("Tone volume")
            hexKey: "sound_effect_volume"
        }

        ContentSubsection {
            visible: HexSettings.on("sound_effects")
            title: Translation.tr("Tones")
            icon: "music_note"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: HexSettings.get("sound_theme")
                onSelected: newValue => HexSettings.set("sound_theme", newValue)
                options: [
                    {
                        displayName: Translation.tr("Classic keys"),
                        value: "classic"
                    },
                    {
                        displayName: Translation.tr("Kalimba"),
                        value: "signature"
                    },
                    {
                        displayName: Translation.tr("Click"),
                        value: "click"
                    },
                    {
                        displayName: Translation.tr("Soft"),
                        value: "soft"
                    },
                    {
                        displayName: Translation.tr("Wood"),
                        value: "wood"
                    },
                    {
                        displayName: Translation.tr("Analog"),
                        value: "analog"
                    },
                    {
                        displayName: Translation.tr("Thock"),
                        value: "thock"
                    }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Other audio while you dictate")
            icon: "music_off"
            Layout.fillWidth: true

            ConfigSelectionArray {
                enabled: HexSettings.loaded
                currentValue: HexSettings.get("recording_audio_behavior")
                onSelected: newValue => HexSettings.set("recording_audio_behavior", newValue)
                options: [
                    {
                        displayName: Translation.tr("Pause media"),
                        icon: "pause",
                        value: "pause_media"
                    },
                    {
                        displayName: Translation.tr("Lower it"),
                        icon: "volume_down",
                        value: "duck"
                    },
                    {
                        displayName: Translation.tr("Mute it"),
                        icon: "volume_off",
                        value: "mute"
                    },
                    {
                        displayName: Translation.tr("Leave it"),
                        icon: "volume_up",
                        value: "do_nothing"
                    }
                ]
            }
        }

        VolumeSlider {
            visible: HexSettings.get("recording_audio_behavior") === "duck"
            buttonIcon: "volume_down"
            text: Translation.tr("Volume while dictating")
            hexKey: "recording_duck_volume"
        }

        ConfigSwitch {
            buttonIcon: "headphones"
            text: Translation.tr("Only do this when playing through speakers")
            enabled: HexSettings.loaded && HexSettings.get("recording_audio_behavior") !== "do_nothing"
            Binding on checked {
                value: HexSettings.on("labs.speakers_only")
            }
            onCheckedChanged: HexSettings.set("labs.speakers_only", checked)
        }
    }

    // ── Output ───────────────────────────────────────────────────────────────
    ContentSection {
        icon: "keyboard"
        title: Translation.tr("Typing the text")

        ConfigSwitch {
            buttonIcon: "edit_note"
            text: Translation.tr("Show words in the text box as you speak")
            enabled: HexSettings.loaded
            Binding on checked {
                value: HexSettings.on("labs.live_typing")
            }
            onCheckedChanged: HexSettings.set("labs.live_typing", checked)
        }

        ConfigSwitch {
            buttonIcon: "terminal"
            text: Translation.tr("Paste with Ctrl + Shift + V")
            description: Translation.tr("The paste shortcut terminals expect")
            enabled: HexSettings.loaded
            Binding on checked {
                value: HexSettings.on("paste_with_shift")
            }
            onCheckedChanged: HexSettings.set("paste_with_shift", checked)
        }

        ConfigSwitch {
            buttonIcon: "content_paste"
            text: Translation.tr("Leave the dictation on the clipboard")
            enabled: HexSettings.loaded
            Binding on checked {
                value: HexSettings.on("labs.keep_on_clipboard")
            }
            onCheckedChanged: HexSettings.set("labs.keep_on_clipboard", checked)
        }

        ConfigSwitch {
            buttonIcon: "keyboard_return"
            text: Translation.tr("Press Enter after pasting")
            description: Translation.tr("Messages send themselves")
            enabled: HexSettings.loaded
            Binding on checked {
                value: HexSettings.on("labs.yolo_mode")
            }
            onCheckedChanged: HexSettings.set("labs.yolo_mode", checked)
        }
    }

    // ── Cleanup ──────────────────────────────────────────────────────────────
    ContentSection {
        icon: "auto_fix_high"
        title: Translation.tr("Tidying the text")

        ConfigSwitch {
            buttonIcon: "filter_alt"
            text: Translation.tr("Remove filler words such as um and uh")
            enabled: HexSettings.loaded
            Binding on checked {
                value: HexSettings.on("labs.filler_words")
            }
            onCheckedChanged: HexSettings.set("labs.filler_words", checked)
        }

        ConfigSwitch {
            buttonIcon: "format_line_spacing"
            text: Translation.tr("Spoken formatting")
            description: Translation.tr("“New line”, “new paragraph” and “open quote” become what they say")
            enabled: HexSettings.loaded
            Binding on checked {
                value: HexSettings.on("labs.spoken_formatting")
            }
            onCheckedChanged: HexSettings.set("labs.spoken_formatting", checked)
        }

        ConfigSwitch {
            buttonIcon: "tag"
            text: Translation.tr("Spoken symbols")
            description: Translation.tr("“Comma”, “colon”, “hashtag” and similar words become symbols")
            enabled: HexSettings.loaded
            Binding on checked {
                value: HexSettings.on("labs.spoken_symbols")
            }
            onCheckedChanged: HexSettings.set("labs.spoken_symbols", checked)
        }

        ConfigSwitch {
            buttonIcon: "fast_forward"
            text: Translation.tr("Skip long pauses")
            description: Translation.tr("Pastes sooner on slow computers")
            enabled: HexSettings.loaded
            Binding on checked {
                value: HexSettings.on("labs.skip_pauses")
            }
            onCheckedChanged: HexSettings.set("labs.skip_pauses", checked)
        }

        ConfigSwitch {
            buttonIcon: "style"
            text: Translation.tr("Write dictations in a set style")
            enabled: HexSettings.loaded
            Binding on checked {
                value: HexSettings.on("labs.dictation_style")
            }
            onCheckedChanged: HexSettings.set("labs.dictation_style", checked)
        }

        ConfigSelectionArray {
            visible: HexSettings.on("labs.dictation_style")
            currentValue: HexSettings.get("labs.dictation_style_choice")
            onSelected: newValue => HexSettings.set("labs.dictation_style_choice", newValue)
            options: [
                {
                    displayName: Translation.tr("Polished"),
                    value: "polished"
                },
                {
                    displayName: Translation.tr("Casual"),
                    value: "casual"
                },
                {
                    displayName: Translation.tr("Notes"),
                    value: "notes"
                },
                {
                    displayName: Translation.tr("Verbatim"),
                    value: "verbatim"
                }
            ]
        }

        ConfigSwitch {
            buttonIcon: "front_hand"
            text: Translation.tr("Finish hands-free dictation with a spoken phrase")
            enabled: HexSettings.loaded
            Binding on checked {
                value: HexSettings.on("labs.stop_phrase")
            }
            onCheckedChanged: HexSettings.set("labs.stop_phrase", checked)
        }

        ConfigTextField {
            id: stopPhrase
            visible: HexSettings.on("labs.stop_phrase")
            icon: "record_voice_over"
            text: Translation.tr("Stop phrase")
            placeholderText: Translation.tr("At least two words; press Enter to save")
            Binding on inputText {
                value: String(HexSettings.get("labs.stop_phrase_text") ?? "")
            }
            Connections {
                target: stopPhrase.textField
                function onAccepted() {
                    HexSettings.set("labs.stop_phrase_text", stopPhrase.inputText.trim());
                }
            }
        }
    }

    // ── Vocabulary ───────────────────────────────────────────────────────────
    ContentSection {
        icon: "dictionary"
        title: Translation.tr("Vocabulary")

        Note {
            text: Translation.tr("Names and terms Hex should recognise. Select a word to remove it. Adding or removing starts Hex.")
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: HexSettings.vocabulary

                delegate: RippleButtonWithIcon {
                    required property string modelData
                    enabled: !HexSettings.busy
                    materialIcon: "close"
                    mainText: modelData
                    onClicked: HexSettings.removeTerm(modelData)
                }
            }
        }

        RowLayout {
            id: addRow
            Layout.fillWidth: true
            spacing: 8

            function submit(): void {
                const term = termField.text.trim();
                if (term.length === 0 || HexSettings.busy)
                    return;
                HexSettings.addTerm(term, soundsField.text.trim());
                termField.text = "";
                soundsField.text = "";
            }

            MaterialTextField {
                id: termField
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                placeholderText: Translation.tr("New word")
                onAccepted: addRow.submit()
            }

            MaterialTextField {
                id: soundsField
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                placeholderText: Translation.tr("Sounds like (optional, comma-separated)")
                onAccepted: addRow.submit()
            }

            RippleButtonWithIcon {
                enabled: !HexSettings.busy && termField.text.trim().length > 0
                materialIcon: "add"
                mainText: Translation.tr("Add")
                onClicked: addRow.submit()
            }
        }

        ContentSubsection {
            title: Translation.tr("How readily Hex swaps in these words")
            icon: "tune"
            Layout.fillWidth: true

            ConfigSelectionArray {
                enabled: HexSettings.loaded
                currentValue: HexSettings.get("vocabulary_boost")
                onSelected: newValue => HexSettings.set("vocabulary_boost", newValue)
                options: [
                    {
                        displayName: Translation.tr("Off"),
                        value: "off"
                    },
                    {
                        displayName: Translation.tr("Lightly"),
                        value: "light"
                    },
                    {
                        displayName: Translation.tr("Normally"),
                        value: "normal"
                    },
                    {
                        displayName: Translation.tr("Strongly"),
                        value: "strong"
                    }
                ]
            }
        }
    }

    // ── Hex's indicator and history ──────────────────────────────────────────
    ContentSection {
        icon: "history"
        title: Translation.tr("Hex indicator and history")

        ContentSubsection {
            title: Translation.tr("Hex's own recording indicator")
            icon: "picture_in_picture"
            tooltip: Translation.tr("Separate from the shell's bar microphone and island waveform")
            Layout.fillWidth: true

            ConfigSelectionArray {
                enabled: HexSettings.loaded
                currentValue: HexSettings.get("indicator_position")
                onSelected: newValue => HexSettings.set("indicator_position", newValue)
                options: [
                    {
                        displayName: Translation.tr("Hidden"),
                        icon: "visibility_off",
                        value: "hidden"
                    },
                    {
                        displayName: Translation.tr("Top"),
                        icon: "vertical_align_top",
                        value: "top"
                    },
                    {
                        displayName: Translation.tr("Bottom"),
                        icon: "vertical_align_bottom",
                        value: "bottom"
                    }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "subtitles"
            text: Translation.tr("Show live words beside it")
            enabled: HexSettings.loaded && HexSettings.get("indicator_position") !== "hidden"
            Binding on checked {
                value: HexSettings.on("labs.live_text")
            }
            onCheckedChanged: HexSettings.set("labs.live_text", checked)
        }

        ConfigSwitch {
            buttonIcon: "error"
            text: Translation.tr("Show why a dictation failed beside it")
            enabled: HexSettings.loaded && HexSettings.get("indicator_position") !== "hidden"
            Binding on checked {
                value: HexSettings.on("labs.failure_notices")
            }
            onCheckedChanged: HexSettings.set("labs.failure_notices", checked)
        }

        ContentSubsection {
            title: Translation.tr("Keep dictation history")
            icon: "history"
            Layout.fillWidth: true

            ConfigSelectionArray {
                enabled: HexSettings.loaded
                currentValue: HexSettings.get("history_retention")
                onSelected: newValue => HexSettings.set("history_retention", newValue)
                options: [
                    {
                        displayName: Translation.tr("Off"),
                        value: "off"
                    },
                    {
                        displayName: Translation.tr("A day"),
                        value: "day"
                    },
                    {
                        displayName: Translation.tr("A week"),
                        value: "week"
                    },
                    {
                        displayName: Translation.tr("A month"),
                        value: "month"
                    },
                    {
                        displayName: Translation.tr("Forever"),
                        value: "forever"
                    }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "audio_file"
            text: Translation.tr("Keep the audio of dictations in history")
            enabled: HexSettings.loaded && HexSettings.get("history_retention") !== "off"
            Binding on checked {
                value: HexSettings.on("labs.keep_recordings")
            }
            onCheckedChanged: HexSettings.set("labs.keep_recordings", checked)
        }
    }
}
