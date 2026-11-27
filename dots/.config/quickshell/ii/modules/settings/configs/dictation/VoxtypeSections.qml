pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "voxtypeSchema.js" as VoxSchema

/**
 * Voxtype's dictation settings on the shell's Dictation page. Every control reads
 * and writes Voxtype's own config file through `VoxtypeSettings`; the exception
 * is "load only while dictating", a flag on the daemon the shell runs.
 */
ColumnLayout {
    id: root
    spacing: 12

    readonly property bool loaded: VoxtypeSettings.loaded
    readonly property string engine: VoxtypeSettings.engine
    readonly property bool whisper: root.engine === "whisper"
    readonly property string selectedModel: VoxtypeSettings.model
    readonly property string language: String(VoxtypeSettings.get("whisper.language") ?? "en")
    readonly property string outputMode: String(VoxtypeSettings.get("output.mode") ?? "type")
    readonly property var installedModels: VoxtypeSettings.models.filter(model => DictationService.modelInstalled(model.engine, model.name))
    readonly property var otherModels: VoxtypeSettings.models.filter(model => model.downloadable && !DictationService.modelInstalled(model.engine, model.name))
    readonly property string englishOnlyTwin: root.whisper ? VoxSchema.multilingualTwin(root.selectedModel) : ""
    property bool badLanguage: false

    // The languages worth a one-click entry. Whisper handles 99; the rest are
    // reachable through the code field below rather than a scroll of flags.
    readonly property var languageOptions: [
        { displayName: Translation.tr("Auto-detect"), value: "auto" },
        { displayName: Translation.tr("English"), value: "en" },
        { displayName: Translation.tr("French"), value: "fr" },
        { displayName: Translation.tr("Spanish"), value: "es" },
        { displayName: Translation.tr("German"), value: "de" },
        { displayName: Translation.tr("Italian"), value: "it" },
        { displayName: Translation.tr("Portuguese"), value: "pt" },
        { displayName: Translation.tr("Dutch"), value: "nl" },
        { displayName: Translation.tr("Polish"), value: "pl" },
        { displayName: Translation.tr("Russian"), value: "ru" },
        { displayName: Translation.tr("Ukrainian"), value: "uk" },
        { displayName: Translation.tr("Turkish"), value: "tr" },
        { displayName: Translation.tr("Arabic"), value: "ar" },
        { displayName: Translation.tr("Hindi"), value: "hi" },
        { displayName: Translation.tr("Chinese"), value: "zh" },
        { displayName: Translation.tr("Japanese"), value: "ja" },
        { displayName: Translation.tr("Korean"), value: "ko" },
        { displayName: Translation.tr("Catalan"), value: "ca" },
        { displayName: Translation.tr("Swedish"), value: "sv" },
        { displayName: Translation.tr("Czech"), value: "cs" }
    ]

    function engineName(engine: string): string {
        return engine === "gguf" ? "GGUF" : engine.charAt(0).toUpperCase() + engine.slice(1);
    }

    function useLanguage(text: string): void {
        const language = VoxSchema.languageList(text);
        root.badLanguage = language.length === 0;
        if (root.badLanguage)
            return;
        const prompt = VoxSchema.promptAfterLanguage(String(VoxtypeSettings.get("whisper.initial_prompt") ?? ""), language);
        VoxtypeSettings.set("whisper.language", language);
        if (prompt !== null)
            VoxtypeSettings.set("whisper.initial_prompt", prompt);
        // An English-only model cannot do this: move to its multilingual twin if it is here.
        if (language !== "en" && root.englishOnlyTwin.length > 0 && DictationService.modelInstalled("whisper", root.englishOnlyTwin))
            VoxtypeSettings.selectModel("whisper", root.englishOnlyTwin);
    }

    function choiceLabel(value: string): string {
        return value === "auto" ? Translation.tr("Automatic") : value.split("+").map(part => part.charAt(0).toUpperCase() + part.slice(1)).join(" + ");
    }

    component Note: StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    component SettingSpin: ConfigSpinBox {
        id: spin
        required property string settingKey
        /** 0 means "not set", so the engine's own default applies. */
        property bool unsetAtZero: false
        readonly property real stored: Number(VoxtypeSettings.get(spin.settingKey) ?? 0)
        enabled: VoxtypeSettings.loaded
        from: spin.unsetAtZero ? 0 : (VoxtypeSettings.entries[spin.settingKey]?.min ?? 0)
        to: VoxtypeSettings.entries[spin.settingKey]?.max ?? 100000
        Binding on value {
            value: spin.stored
        }
        // Saved once the number has settled: every save restarts the daemon.
        onValueChanged: spinTimer.restart()
        Timer {
            id: spinTimer
            interval: 600
            onTriggered: {
                if (spin.value !== spin.stored)
                    VoxtypeSettings.set(spin.settingKey, spin.unsetAtZero && spin.value === 0 ? "" : spin.value);
            }
        }
    }

    component SettingSlider: ConfigSlider {
        id: slider
        required property string settingKey
        enabled: VoxtypeSettings.loaded
        from: 0
        to: 1
        Binding on value {
            value: Number(VoxtypeSettings.get(slider.settingKey) ?? 0)
        }
        onValueChanged: sliderTimer.restart()
        Timer {
            id: sliderTimer
            interval: 500
            onTriggered: {
                if (slider.pressed)
                    restart();
                else
                    VoxtypeSettings.set(slider.settingKey, Math.round(slider.value * 100) / 100);
            }
        }
    }

    component SettingField: ConfigTextField {
        id: field
        required property string settingKey
        enabled: VoxtypeSettings.loaded
        Binding on inputText {
            value: String(VoxtypeSettings.get(field.settingKey) ?? "")
        }
        Connections {
            target: field.textField
            function onAccepted() {
                VoxtypeSettings.set(field.settingKey, field.inputText);
            }
        }
    }

    Note {
        visible: VoxtypeSettings.error.length > 0
        text: VoxtypeSettings.error
        color: Appearance.colors.colError
    }

    Note {
        visible: VoxtypeSettings.unsupported
        text: Translation.tr("This version of Voxtype is too old for its settings to be shown here. Update to 1.3 or newer.")
    }

    // ── Model ────────────────────────────────────────────────────────────────
    ContentSection {
        icon: "graphic_eq"
        title: Translation.tr("Voxtype speech model")

        StyledComboBox {
            id: modelBox
            visible: root.installedModels.length > 0
            enabled: root.loaded
            buttonIcon: "graphic_eq"
            textRole: "displayName"
            model: root.installedModels.map(entry => ({
                        displayName: `${root.engineName(entry.engine)} · ${entry.name}`
                    }))
            // Re-asserted when a switch is refused or made outside the shell.
            readonly property int selectedIndex: root.installedModels.findIndex(entry => entry.engine === root.engine && entry.name === root.selectedModel)
            Binding on currentIndex {
                value: modelBox.selectedIndex
            }
            onModelChanged: Qt.callLater(() => modelBox.currentIndex = modelBox.selectedIndex)
            onActivated: index => VoxtypeSettings.selectModel(root.installedModels[index].engine, root.installedModels[index].name)
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.loaded && !DictationService.modelReady
            spacing: 8

            Note {
                text: DictationService.downloadingModel === root.selectedModel
                    ? Translation.tr("Downloading %1… %2%").arg(root.selectedModel).arg(Math.round(DictationService.downloadProgress * 100))
                    : Translation.tr("The %1 speech model has not been downloaded yet.").arg(root.selectedModel)
            }

            RippleButtonWithIcon {
                enabled: DictationService.downloadingModel.length === 0
                materialIcon: "download"
                mainText: Translation.tr("Download")
                onClicked: {
                    const entry = VoxtypeSettings.models.find(model => model.engine === root.engine && model.name === root.selectedModel);
                    DictationService.downloadModel(root.engine, root.selectedModel, entry?.downloadArg ?? root.selectedModel);
                }
            }
        }

        StyledProgressBar {
            Layout.fillWidth: true
            visible: DictationService.downloadingModel.length > 0
            value: DictationService.downloadProgress
            valueBarHeight: 6
            wavy: true
            animateWave: true
        }

        ContentSubsection {
            visible: root.installedModels.length > 1
            title: Translation.tr("Other downloaded models")
            icon: "database"
            Layout.fillWidth: true
            collapsible: true
            expanded: false

            Repeater {
                model: root.installedModels.filter(entry => !(entry.engine === root.engine && entry.name === root.selectedModel))

                delegate: RowLayout {
                    id: keptRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: `${root.engineName(keptRow.modelData.engine)} · ${keptRow.modelData.name}`
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer0
                        wrapMode: Text.Wrap
                    }

                    RippleButtonWithIcon {
                        materialIcon: "delete"
                        mainText: Translation.tr("Remove")
                        onClicked: DictationService.removeModel(keptRow.modelData.engine, keptRow.modelData.name)
                    }
                }
            }
        }

        ContentSubsection {
            visible: root.otherModels.length > 0
            title: Translation.tr("Download another model")
            icon: "cloud_download"
            Layout.fillWidth: true
            collapsible: true
            expanded: false

            Repeater {
                model: root.otherModels

                delegate: RowLayout {
                    id: modelRow
                    required property var modelData
                    readonly property bool downloading: DictationService.downloadingModel === modelData.name
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: `${root.engineName(modelRow.modelData.engine)} · ${modelRow.modelData.name}`
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer0
                        wrapMode: Text.Wrap
                    }

                    RippleButtonWithIcon {
                        enabled: DictationService.downloadingModel.length === 0
                        materialIcon: "download"
                        mainText: modelRow.downloading ? Translation.tr("Downloading…") : Translation.tr("Download")
                        onClicked: DictationService.downloadModel(modelRow.modelData.engine, modelRow.modelData.name, modelRow.modelData.downloadArg)
                    }
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "memory"
            text: Translation.tr("Load the model only while dictating")
            description: Translation.tr("Frees its memory between dictations")
            checked: Config.options.dictation.voxtypeOnDemand
            onCheckedChanged: Config.options.dictation.voxtypeOnDemand = checked
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: DictationService.onGpu ? "bolt" : "memory"
                iconSize: Appearance.font.pixelSize.large
                color: DictationService.onGpu ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }

            Note {
                text: DictationService.gpuAvailable
                    ? Translation.tr("A GPU build of voxtype is installed but not in use.")
                    : DictationService.backend.length > 0
                        ? Translation.tr("Transcribing on %1").arg(DictationService.backend)
                        : Translation.tr("Backend unknown")
            }

            RippleButtonWithIcon {
                visible: DictationService.gpuAvailable
                materialIcon: "bolt"
                mainText: Translation.tr("Use the GPU")
                onClicked: DictationService.enableGpu()
            }
        }

        SettingSpin {
            visible: VoxtypeSettings.entries[`${root.engine}.threads`] !== undefined
            settingKey: `${root.engine}.threads`
            unsetAtZero: true
            icon: "memory"
            text: Translation.tr("Processor threads (0 lets the engine decide)")
        }
    }

    // ── Language ─────────────────────────────────────────────────────────────
    ContentSection {
        visible: root.whisper || VoxtypeSettings.entries[`${root.engine}.language`] !== undefined
        icon: "translate"
        title: Translation.tr("Language")

        StyledComboBox {
            id: languageBox
            visible: root.whisper
            enabled: root.loaded
            buttonIcon: "language"
            textRole: "displayName"
            model: root.languageOptions
            readonly property int selectedIndex: root.languageOptions.findIndex(item => item.value === root.language)
            Binding on currentIndex {
                value: languageBox.selectedIndex
            }
            onActivated: index => root.useLanguage(root.languageOptions[index].value)
        }

        Note {
            visible: root.englishOnlyTwin.length > 0 && root.language !== "en"
            text: Translation.tr("%1 only knows English. Pick or download %2 above.").arg(root.selectedModel).arg(root.englishOnlyTwin)
            color: Appearance.colors.colError
        }

        ConfigTextField {
            id: codes
            visible: root.whisper
            enabled: root.loaded
            icon: "spellcheck"
            text: Translation.tr("Language codes")
            placeholderText: Translation.tr("el, or en,fr to allow either; press Enter to save")
            Binding on inputText {
                value: root.language
            }
            Connections {
                target: codes.textField
                function onAccepted() {
                    root.useLanguage(codes.inputText);
                }
            }
        }

        Note {
            visible: root.badLanguage
            text: Translation.tr("Use two or three letter language codes, separated by commas.")
            color: Appearance.colors.colError
        }

        SettingField {
            visible: !root.whisper
            settingKey: `${root.engine}.language`
            icon: "translate"
            text: Translation.tr("Language codes")
            placeholderText: Translation.tr("Press Enter to save")
        }

        SettingField {
            visible: root.whisper
            settingKey: "whisper.initial_prompt"
            icon: "format_quote"
            text: Translation.tr("Punctuation sample")
            placeholderText: Translation.tr("A sentence punctuated the way you want")
        }

        Note {
            visible: root.whisper
            text: Translation.tr("Whisper is primed with this sample and punctuates in the same style. Picking a language fills in a built-in one unless you wrote your own.")
        }

        ConfigSwitch {
            visible: root.whisper
            buttonIcon: "g_translate"
            text: Translation.tr("Translate what I say into English")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("whisper.translate")
            }
            onCheckedChanged: VoxtypeSettings.set("whisper.translate", checked)
        }
    }

    // ── Output ───────────────────────────────────────────────────────────────
    ContentSection {
        icon: "keyboard"
        title: Translation.tr("Typing the text")

        ConfigSelectionArray {
            enabled: root.loaded
            currentValue: root.outputMode
            onSelected: newValue => VoxtypeSettings.set("output.mode", newValue)
            options: [
                { displayName: Translation.tr("Paste it"), icon: "content_paste", value: "paste" },
                { displayName: Translation.tr("Type it"), icon: "keyboard", value: "type" },
                { displayName: Translation.tr("Copy it"), icon: "content_copy", value: "clipboard" }
            ]
        }

        Note {
            text: root.outputMode === "clipboard"
                ? Translation.tr("The text lands on the clipboard and nothing is typed — paste it yourself.")
                : root.outputMode === "paste"
                    ? Translation.tr("The text is pasted in one piece with the shortcut below.")
                    : root.outputMode === "file"
                        ? Translation.tr("The text is written to a file set in Voxtype's config.")
                        : Translation.tr("Typed one key at a time into the focused window. Some apps drop characters: raise the delay below, or paste instead.")
        }

        ContentSubsection {
            visible: root.outputMode === "paste"
            title: Translation.tr("Paste shortcut")
            icon: "content_paste"
            Layout.fillWidth: true

            ConfigSelectionArray {
                enabled: root.loaded
                currentValue: VoxtypeSettings.get("output.paste_keys") ?? "auto"
                onSelected: newValue => VoxtypeSettings.set("output.paste_keys", newValue)
                options: (VoxtypeSettings.entries["output.paste_keys"]?.choices ?? []).map(choice => ({
                            displayName: root.choiceLabel(choice),
                            value: choice
                        }))
            }
        }

        ContentSubsection {
            visible: root.outputMode === "paste"
            title: Translation.tr("Paste shortcut in terminals")
            icon: "terminal"
            Layout.fillWidth: true

            ConfigSelectionArray {
                enabled: root.loaded
                currentValue: VoxtypeSettings.get("output.paste_keys_terminal") ?? "auto"
                onSelected: newValue => VoxtypeSettings.set("output.paste_keys_terminal", newValue)
                options: (VoxtypeSettings.entries["output.paste_keys_terminal"]?.choices ?? []).map(choice => ({
                            displayName: root.choiceLabel(choice),
                            value: choice
                        }))
            }
        }

        ConfigSwitch {
            visible: root.outputMode === "paste"
            buttonIcon: "settings_backup_restore"
            text: Translation.tr("Put my clipboard back after pasting")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("output.restore_clipboard")
            }
            onCheckedChanged: VoxtypeSettings.set("output.restore_clipboard", checked)
        }

        SettingSpin {
            visible: root.outputMode === "type"
            settingKey: "output.type_delay_ms"
            icon: "keyboard_alt"
            text: Translation.tr("Delay between typed characters (ms)")
        }

        ConfigSwitch {
            buttonIcon: "keyboard_return"
            text: Translation.tr("Press Enter after the text")
            description: Translation.tr("Messages send themselves")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("output.auto_submit")
            }
            onCheckedChanged: VoxtypeSettings.set("output.auto_submit", checked)
        }

        ConfigSwitch {
            buttonIcon: "wrap_text"
            text: Translation.tr("Type new lines as Shift + Enter")
            description: Translation.tr("Chat apps don't send early")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("output.shift_enter_newlines")
            }
            onCheckedChanged: VoxtypeSettings.set("output.shift_enter_newlines", checked)
        }

        ConfigSwitch {
            buttonIcon: "content_copy"
            text: Translation.tr("Copy the text if typing it fails")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("output.fallback_to_clipboard")
            }
            onCheckedChanged: VoxtypeSettings.set("output.fallback_to_clipboard", checked)
        }

        SettingField {
            settingKey: "output.append_text"
            icon: "add"
            text: Translation.tr("Add after every dictation")
            placeholderText: Translation.tr("For example a space; press Enter to save")
        }
    }

    // ── Cleanup ──────────────────────────────────────────────────────────────
    ContentSection {
        icon: "auto_fix_high"
        title: Translation.tr("Tidying the text")

        ConfigSwitch {
            buttonIcon: "filter_alt"
            text: Translation.tr("Remove filler words such as um and uh")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("text.filter_filler_words")
            }
            onCheckedChanged: VoxtypeSettings.set("text.filter_filler_words", checked)
        }

        ConfigSwitch {
            buttonIcon: "tag"
            text: Translation.tr("Spoken punctuation")
            description: Translation.tr("Saying “period” or “new line” writes it")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("text.spoken_punctuation")
            }
            onCheckedChanged: VoxtypeSettings.set("text.spoken_punctuation", checked)
        }

        ConfigSwitch {
            buttonIcon: "pin"
            text: Translation.tr("Write spoken numbers as figures")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("text.format_numbers")
            }
            onCheckedChanged: VoxtypeSettings.set("text.format_numbers", checked)
        }

        ConfigSwitch {
            buttonIcon: "restart_alt"
            text: Translation.tr("Drop restarted phrases and stutters")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("text.collapse_restarts")
            }
            onCheckedChanged: VoxtypeSettings.set("text.collapse_restarts", checked)
        }

        ConfigSwitch {
            buttonIcon: "join"
            text: Translation.tr("Repair broken sentences")
            description: Translation.tr("Joins fragments and adds question marks")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("text.repair_sentence_breaks")
            }
            onCheckedChanged: VoxtypeSettings.set("text.repair_sentence_breaks", checked)
        }

        ConfigSwitch {
            buttonIcon: "send"
            text: Translation.tr("Say “submit” to press Enter")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("text.smart_auto_submit")
            }
            onCheckedChanged: VoxtypeSettings.set("text.smart_auto_submit", checked)
        }

        SettingField {
            settingKey: "output.post_process.command"
            icon: "terminal"
            text: Translation.tr("Clean up with a command")
            placeholderText: Translation.tr("Reads the text, prints the result; press Enter to save")
        }
    }

    // ── Audio ────────────────────────────────────────────────────────────────
    ContentSection {
        icon: "volume_up"
        title: Translation.tr("Sound")

        ConfigSwitch {
            buttonIcon: "pause"
            text: Translation.tr("Pause music while I speak")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("audio.pause_media")
            }
            onCheckedChanged: VoxtypeSettings.set("audio.pause_media", checked)
        }

        ConfigSwitch {
            buttonIcon: "volume_down"
            text: Translation.tr("Lower other audio while I speak")
            description: Translation.tr("An alternative to pausing it")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("audio.duck_media")
            }
            onCheckedChanged: VoxtypeSettings.set("audio.duck_media", checked)
        }

        SettingSpin {
            visible: VoxtypeSettings.on("audio.duck_media")
            settingKey: "audio.duck_media_volume_percent"
            icon: "percent"
            text: Translation.tr("Volume kept while dictating (%)")
        }

        SettingSpin {
            visible: VoxtypeSettings.on("audio.duck_media")
            settingKey: "audio.duck_media_fade_ms"
            icon: "timer"
            text: Translation.tr("Fade time (ms)")
            stepSize: 50
        }

        ConfigSwitch {
            buttonIcon: "notifications_active"
            text: Translation.tr("Play a sound when recording starts and stops")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("audio.feedback.enabled")
            }
            onCheckedChanged: VoxtypeSettings.set("audio.feedback.enabled", checked)
        }

        ContentSubsection {
            visible: VoxtypeSettings.on("audio.feedback.enabled")
            title: Translation.tr("Tones")
            icon: "music_note"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: VoxtypeSettings.get("audio.feedback.theme")
                onSelected: newValue => VoxtypeSettings.set("audio.feedback.theme", newValue)
                options: [
                    { displayName: Translation.tr("Default"), value: "default" },
                    { displayName: Translation.tr("Subtle"), value: "subtle" },
                    { displayName: Translation.tr("Mechanical"), value: "mechanical" }
                ]
            }
        }

        SettingSlider {
            visible: VoxtypeSettings.on("audio.feedback.enabled")
            settingKey: "audio.feedback.volume"
            buttonIcon: "volume_up"
            text: Translation.tr("Tone volume")
        }

        ConfigSwitch {
            buttonIcon: "voice_selection"
            text: Translation.tr("Ignore recordings with no speech")
            description: Translation.tr("Stops Whisper inventing text from silence")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("vad.enabled")
            }
            onCheckedChanged: VoxtypeSettings.set("vad.enabled", checked)
        }

        SettingSlider {
            visible: VoxtypeSettings.on("vad.enabled")
            settingKey: "vad.threshold"
            buttonIcon: "tune"
            text: Translation.tr("How sure it must be that you spoke")
        }
    }

    // ── Replacements ─────────────────────────────────────────────────────────
    ContentSection {
        icon: "dictionary"
        title: Translation.tr("Word replacements")

        Note {
            text: Translation.tr("What Voxtype hears on the left is written as the text on the right. Select one to remove it.")
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: Object.keys(VoxtypeSettings.replacements)

                delegate: RippleButtonWithIcon {
                    required property string modelData
                    materialIcon: "close"
                    mainText: `${modelData} → ${VoxtypeSettings.replacements[modelData] ?? ""}`
                    onClicked: VoxtypeSettings.setReplacement(modelData, "")
                }
            }
        }

        RowLayout {
            id: replaceRow
            Layout.fillWidth: true
            spacing: 8

            function submit(): void {
                const from = heardField.text.trim();
                if (from.length === 0 || writtenField.text.length === 0)
                    return;
                VoxtypeSettings.setReplacement(from, writtenField.text);
                heardField.text = "";
                writtenField.text = "";
            }

            MaterialTextField {
                id: heardField
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                placeholderText: Translation.tr("When it hears")
                onAccepted: replaceRow.submit()
            }

            MaterialTextField {
                id: writtenField
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                placeholderText: Translation.tr("Write")
                onAccepted: replaceRow.submit()
            }

            RippleButtonWithIcon {
                enabled: root.loaded && heardField.text.trim().length > 0 && writtenField.text.length > 0
                materialIcon: "add"
                mainText: Translation.tr("Add")
                onClicked: replaceRow.submit()
            }
        }
    }

    // ── History ──────────────────────────────────────────────────────────────
    ContentSection {
        icon: "history"
        title: Translation.tr("Voxtype history")

        ConfigSwitch {
            buttonIcon: "history"
            text: Translation.tr("Keep dictation history")
            description: Translation.tr("Stored on this machine only")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("history.enabled")
            }
            onCheckedChanged: VoxtypeSettings.set("history.enabled", checked)
        }

        ConfigSelectionArray {
            visible: VoxtypeSettings.on("history.enabled")
            currentValue: VoxtypeSettings.get("history.retention_days")
            onSelected: newValue => VoxtypeSettings.set("history.retention_days", newValue)
            options: [
                { displayName: Translation.tr("A week"), value: 7 },
                { displayName: Translation.tr("A month"), value: 30 },
                { displayName: Translation.tr("A year"), value: 365 },
                { displayName: Translation.tr("Forever"), value: 0 }
            ]
        }

        ConfigSwitch {
            visible: VoxtypeSettings.on("history.enabled")
            buttonIcon: "web_asset"
            text: Translation.tr("Note which app each dictation went to")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("history.record_app")
            }
            onCheckedChanged: VoxtypeSettings.set("history.record_app", checked)
        }

        ConfigSwitch {
            visible: VoxtypeSettings.on("history.enabled")
            buttonIcon: "title"
            text: Translation.tr("Also note the window title")
            description: Translation.tr("Titles can hold names, subjects and addresses")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("history.record_window_title")
            }
            onCheckedChanged: VoxtypeSettings.set("history.record_window_title", checked)
        }

        SettingField {
            visible: VoxtypeSettings.on("history.enabled")
            settingKey: "history.exclude_apps"
            icon: "block"
            text: Translation.tr("Never record these apps")
            placeholderText: Translation.tr("Comma-separated; press Enter to save")
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "open_in_new"
            mainText: Translation.tr("Read the history in a terminal")
            onClicked: Quickshell.execDetached(["bash", "-c",
                `${Config.options.apps.terminal} -e voxtype history view --tui`])
        }
    }

    // ── Notifications ────────────────────────────────────────────────────────
    ContentSection {
        icon: "notifications"
        title: Translation.tr("Voxtype notifications")

        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Show the transcribed text in a notification")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("output.notification.on_transcription")
            }
            onCheckedChanged: VoxtypeSettings.set("output.notification.on_transcription", checked)
        }

        ConfigSwitch {
            buttonIcon: "difference"
            text: Translation.tr("Show what cleanup changed in it")
            enabled: root.loaded && VoxtypeSettings.on("output.notification.on_transcription")
            Binding on checked {
                value: VoxtypeSettings.on("output.notification.show_edits")
            }
            onCheckedChanged: VoxtypeSettings.set("output.notification.show_edits", checked)
        }

        ConfigSwitch {
            buttonIcon: "voice_over_off"
            text: Translation.tr("Say when no speech was found")
            enabled: root.loaded
            Binding on checked {
                value: VoxtypeSettings.on("output.notification.on_no_speech")
            }
            onCheckedChanged: VoxtypeSettings.set("output.notification.on_no_speech", checked)
        }
    }
}
