import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Which model does what when you talk to the orb. Three stages, tried in order:
 *
 *   1. Instant commands   pattern rules, no model ("volume 30", "next song")
 *   2. Quick answers      one model for chat and short questions; a Claude model runs as a warm session
 *   3. Desktop tasks      anything that needs tools, the browser, settings or files
 */
Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    readonly property var catalog: Ai.catalog
    readonly property string sidebarModelName: root.catalog.models[Ai.currentModelId]?.name ?? Ai.currentModelId

    // Stage 2: any model. A Claude model is stored as its alias (the warm session takes it), any other as its catalog id.
    readonly property var quickOptions: {
        const options = [];
        for (const providerId of root.catalog.providerIds) {
            const provider = root.catalog.providers[providerId];
            for (const model of provider.models)
                options.push({displayName: provider.name + " \u00b7 " + model.title, value: providerId === "claude" ? model.value : model.id});
        }
        const current = String(Config.options.ai.voice.fastModel);
        if (!options.some(item => item.value === current)) options.unshift({displayName: current, value: current});
        return options;
    }

    // Stage 3: the sidebar's model, or any model that can use tools.
    readonly property var taskOptions: {
        const options = [{displayName: Translation.tr("Same as the sidebar chat (%1)").arg(root.sidebarModelName), value: ""}];
        for (const providerId of root.catalog.providerIds) {
            const provider = root.catalog.providers[providerId];
            for (const model of provider.models)
                if (model.tools) options.push({displayName: provider.name + " · " + model.title, value: model.id});
        }
        const current = root.currentTask;
        if (current.length > 0 && !options.some(item => item.value === current))
            options.push({displayName: current, value: current});
        return options;
    }
    // Older configs hold a bare Claude alias such as "haiku".
    readonly property string currentTask: {
        const value = String(Config.options.ai.voice.escalationModel ?? "").trim();
        return value.length > 0 && value.indexOf(":") < 0 ? "claude:" + value : value;
    }

    // ── Instant commands: groups, the user's own phrases, and a way to try a sentence ──
    readonly property var ruleGroups: [
        {id: "media", icon: "play_pause", name: Translation.tr("Media"), example: Translation.tr("pause, next song, previous")},
        {id: "volume", icon: "volume_up", name: Translation.tr("Volume"), example: Translation.tr("volume 30, louder, mute")},
        {id: "brightness", icon: "brightness_6", name: Translation.tr("Brightness"), example: Translation.tr("brightness 50, dimmer")},
        {id: "theme", icon: "dark_mode", name: Translation.tr("Light / dark mode"), example: Translation.tr("dark mode, light theme")},
        {id: "timers", icon: "timer", name: Translation.tr("Timers"), example: Translation.tr("timer 10 minutes")},
        {id: "alarms", icon: "alarm", name: Translation.tr("Alarms"), example: Translation.tr("alarm at 7:30 am")},
        {id: "notes", icon: "checklist", name: Translation.tr("Reminders & tasks"), example: Translation.tr("remind me to call mum, add milk to my tasks")},
        {id: "workspace", icon: "workspaces", name: Translation.tr("Workspaces"), example: Translation.tr("workspace 3")},
        {id: "apps", icon: "apps", name: Translation.tr("Opening apps"), example: Translation.tr("open firefox")},
        {id: "toggles", icon: "toggle_on", name: Translation.tr("Switches"), example: Translation.tr("turn off wifi, night light on, do not disturb")},
        {id: "power", icon: "battery_saver", name: Translation.tr("Power profile"), example: Translation.tr("power saver mode, performance mode")},
        {id: "capture", icon: "screenshot_region", name: Translation.tr("Screenshots & recording"), example: Translation.tr("take a screenshot, start recording, color picker")},
        {id: "panels", icon: "dashboard", name: Translation.tr("Open shell panels"), example: Translation.tr("open settings, show the cheat sheet, open the clipboard")},
        {id: "sessions", icon: "terminal", name: Translation.tr("Coding sessions"), example: Translation.tr("what are my sessions doing, tell Claude to run the tests, stop OpenCode")},
        {id: "kitten", icon: "pets", name: Translation.tr("The kitten"), example: Translation.tr("good kitty, play with the kitten, hide and seek")},
        {id: "windows", icon: "select_window", name: Translation.tr("Window control"), example: Translation.tr("fullscreen, float this window, switch to firefox")},
        {id: "info", icon: "help", name: Translation.tr("Quick answers"), example: Translation.tr("what time is it, battery, what's playing")},
        {id: "system", icon: "lock", name: Translation.tr("Lock, sleep, restart, shut down, close window"), example: Translation.tr("asks you to say yes first")}
    ]
    readonly property var actionVerbs: ["media", "volume", "brightness", "theme", "open", "timer", "alarm", "remind", "task", "workspace", "toggle", "power", "capture", "panel", "window", "kitten", "session"]
    readonly property var rulesOff: Array.from(Config.options.ai.voice.rulesOff ?? [])
    readonly property var customRules: Array.from(Config.options.ai.voice.customRules ?? [])
    readonly property var learnedRules: Array.from(Config.options.ai.voice.learnedRules ?? [])
    property string customError: ""
    property string tryResult: ""

    function setGroup(id, on) {
        const off = root.rulesOff.filter(item => item !== id);
        if (!on) off.push(id);
        if (off.length !== root.rulesOff.length || off.some(item => !root.rulesOff.includes(item)))
            Config.options.ai.voice.rulesOff = off;
    }
    function addCustom(phrase, action) {
        const words = String(action).split(";").map(part => part.trim().split(/\s+/)[0]).filter(word => word.length > 0);
        if (String(phrase).trim().length < 2) { root.customError = Translation.tr("Say what you will say, e.g. \u201cmovie mode\u201d."); return false; }
        if (words.length === 0) { root.customError = Translation.tr("Add what it should do, e.g. theme dark; volume set 20"); return false; }
        const bad = words.find(word => !root.actionVerbs.includes(word.toLowerCase()));
        if (bad) { root.customError = Translation.tr("\u201c%1\u201d is not an action. Use: %2").arg(bad).arg(root.actionVerbs.join(", ")); return false; }
        root.customError = "";
        Config.options.ai.voice.customRules = root.customRules.concat([{phrase: String(phrase).trim(), do: String(action).trim(), say: ""}]);
        return true;
    }
    function forgetLearned(index) {
        const next = root.learnedRules.slice();
        next.splice(index, 1);
        Config.options.ai.voice.learnedRules = next;
    }
    /** Moves a learned phrase to the user's own commands, which are tried first and can override a built-in. */
    function keepLearned(index) {
        const rule = root.learnedRules[index];
        if (!rule) return;
        Config.options.ai.voice.customRules = root.customRules.concat([{phrase: rule.phrase, do: rule.do, say: rule.say ?? ""}]);
        root.forgetLearned(index);
    }
    function removeCustom(index) {
        const next = root.customRules.slice();
        next.splice(index, 1);
        Config.options.ai.voice.customRules = next;
    }
    function tryPhrase(text) {
        if (String(text).trim().length === 0) { root.tryResult = ""; return; }
        tryProcess.command = ["python3", Directories.scriptPath + "/ai/voice_rules.py", String(text),
            root.rulesOff.join(","), JSON.stringify(root.customRules), JSON.stringify(root.learnedRules)];
        tryProcess.running = true;
    }
    Process {
        id: tryProcess
        stdout: StdioCollector {
            onStreamFinished: {
                let result = null;
                try { result = JSON.parse(text.trim()); } catch (e) { result = undefined; }
                if (result === undefined) root.tryResult = Translation.tr("Could not check that sentence.");
                else if (result === null || !Config.options.ai.voice.rules)
                    root.tryResult = Translation.tr("No instant command matches. It would go on to quick answers.");
                else root.tryResult = Translation.tr("Runs: %1 \u2014 says \u201c%2\u201d").arg(result.actions.map(item => item[0] + " " + item[1].join(" ")).join("; ")).arg(result.say);
            }
        }
    }

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                text: Translation.tr("Voice orb models")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "power_settings_new"
            title: Translation.tr("The orb")

            ConfigSwitch {
                buttonIcon: "graphic_eq"
                text: Translation.tr("Enable the orb")
                checked: Config.options.ai.voice.orbEnabled
                onCheckedChanged: Config.options.ai.voice.orbEnabled = checked
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Translation.tr("Off removes the orb, its kitten and its island bubble, ignores its shortcuts and wake word, and stops coding session alerts. Typed messages go to the sidebar's chat model.")
            }
        }

        ContentSection {
            icon: "cloud_off"
            title: Translation.tr("Remote AI")

            ConfigSelectionArray {
                currentValue: Config.options.policies.ai
                onSelected: newValue => Config.options.policies.ai = newValue
                options: [
                    {"displayName": Translation.tr("On"), "icon": "cloud", "value": 1},
                    {"displayName": Translation.tr("Local only"), "icon": "cloud_off", "value": 2},
                    {"displayName": Translation.tr("Off"), "icon": "block", "value": 0}
                ]
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Config.options.policies.ai === 2
                    ? Translation.tr("Local only: nothing is sent to a remote model. Quick answers (Claude), screen looks and cloud speech for other scripts are off, and only local models answer. Instant commands, local speech and local models still work.")
                    : Config.options.policies.ai === 0
                    ? Translation.tr("Off: no AI model is used at all. Instant commands, timers and the small orbs still work, because they run on this machine.")
                    : Translation.tr("On: spoken and typed requests may use the models you chose below. This is the same switch as the AI policy in Settings > Sidebars.")
            }
        }

        ContentSection {
            icon: "route"
            title: Translation.tr("How a spoken request is answered")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Each request tries three stages in order and stops at the first that can handle it. "
                    + "Instant commands run with no model at all. Quick answers come from a warm Claude session. "
                    + "Anything that needs the desktop goes to the desktop-tasks model.")
            }
        }

        ContentSection {
            icon: "mic"
            title: Translation.tr("Push to talk")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Hold Super + Alt + Space to talk. Release to send one request. The orb ends the conversation after its reply.")
            }
        }

        ContentSection {
            icon: "record_voice_over"
            title: Translation.tr("Trigger word")

            ConfigSwitch {
                buttonIcon: "hearing"
                text: Translation.tr("Start listening when I say the trigger word")
                checked: Config.options.ai.voice.wakeWord
                onCheckedChanged: Config.options.ai.voice.wakeWord = checked
            }
            StyledComboBox {
                id: wakeWordBox
                readonly property var words: [
                    {displayName: Translation.tr("Hey Jarvis"), value: "hey_jarvis"},
                    {displayName: Translation.tr("Alexa"), value: "alexa"},
                    {displayName: Translation.tr("Hey Mycroft"), value: "hey_mycroft"},
                    {displayName: Translation.tr("Hey Rhasspy"), value: "hey_rhasspy"},
                    {displayName: Translation.tr("Hey Borb (custom, new)"), value: "hey_borb"}
                ]
                buttonIcon: "campaign"
                textRole: "displayName"
                model: wakeWordBox.words
                enabled: Config.options.ai.voice.wakeWord
                currentIndex: Math.max(0, wakeWordBox.words.findIndex(item => item.value === String(Config.options.ai.voice.wakeWordModel)))
                onActivated: index => Config.options.ai.voice.wakeWordModel = wakeWordBox.words[index].value
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Translation.tr("A small detector keeps the microphone open while the orb is idle and starts a voice turn when it hears the word. A word is downloaded the first time you pick it. A custom model can be used by putting the path of its .onnx file in ai.voice.wakeWordModel. It runs on this computer, records nothing, and sends nothing anywhere. It stops while you are talking to the orb, while the orb speaks, and when the screen is locked. It uses about 6% of one core and 190 MB.")
            }
            ConfigSpinBox {
                icon: "tune"
                text: Translation.tr("Sensitivity threshold (%)")
                value: Math.round(Config.options.ai.voice.wakeWordThreshold * 100)
                from: 20
                to: 95
                stepSize: 5
                onValueChanged: Config.options.ai.voice.wakeWordThreshold = value / 100
            }
        }

        ContentSection {
            icon: "keyboard"
            title: Translation.tr("Typed messages")

            ConfigSwitch {
                buttonIcon: "alt_route"
                text: Translation.tr("Route typed messages like spoken ones")
                checked: Config.options.ai.voice.typedRouting
                onCheckedChanged: Config.options.ai.voice.typedRouting = checked
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Translation.tr("A message typed in the sidebar goes through the same three stages as speech: instant commands, then quick answers, then the desktop-tasks model. Typing \u201cvolume 30\u201d changes the volume at once. Quick answers are short and use a different model from the chat picker. Messages with attachments, and slash commands, always go the normal way. Turn this off to send every typed message to the chat model.")
            }
        }

        ContentSection {
            icon: "bubble_chart"
            title: Translation.tr("Small orbs")

            ConfigSwitch {
                buttonIcon: "bubble_chart"
                text: Translation.tr("Show a small orb when a background AI task finishes")
                checked: Config.options.ai.voice.satellites
                onCheckedChanged: Config.options.ai.voice.satellites = checked
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Translation.tr("Timers, alarms, reminders and music already have bubbles in the island, so they get no orb. Only a finished AI task does: click it to read the answer. It shows only while the orb floats on the desktop.")
            }
            ConfigSwitch {
                buttonIcon: "pets"
                text: Translation.tr("Show the kitten")
                checked: Config.options.ai.voice.kitten
                onCheckedChanged: Config.options.ai.voice.kitten = checked
            }
        }

        ContentSection {
            icon: "bolt"
            title: Translation.tr("1 · Instant commands")

            ConfigSwitch {
                buttonIcon: "rule"
                text: Translation.tr("Run common commands without a model")
                checked: Config.options.ai.voice.rules
                onCheckedChanged: Config.options.ai.voice.rules = checked
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Translation.tr("These run on this machine in a few milliseconds, with no model and nothing sent anywhere. A command is matched on the whole sentence, so anything chatty goes on to the next stage.")
            }
            ConfigSwitch {
                buttonIcon: "notifications"
                text: Translation.tr("Chime instead of speaking the confirmation")
                checked: Config.options.ai.voice.chime
                onCheckedChanged: Config.options.ai.voice.chime = checked
            }

            ContentSubsection {
                Layout.fillWidth: true
                title: Translation.tr("What it handles instantly")
                icon: "checklist_rtl"

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: Translation.tr("Switching one off does not block it: that kind of request goes on to quick answers instead, which can still do it but takes about a second longer.")
                }

                Repeater {
                    model: root.ruleGroups
                    delegate: ConfigSwitch {
                        id: groupSwitch
                        required property var modelData
                        Layout.fillWidth: true
                        enabled: Config.options.ai.voice.rules
                        buttonIcon: modelData.icon
                        text: modelData.name + " \u2014 " + modelData.example
                        checked: !root.rulesOff.includes(modelData.id)
                        onCheckedChanged: root.setGroup(modelData.id, checked)
                    }
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                title: Translation.tr("Your own commands")
                icon: "add_circle"

                Repeater {
                    model: root.customRules
                    delegate: RowLayout {
                        id: customRow
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: Appearance.sizes.elevationMargin
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnLayer1
                            text: "\u201c" + customRow.modelData.phrase + "\u201d  \u2192  " + customRow.modelData.do
                        }
                        RippleButton {
                            implicitWidth: Appearance.sizes.elevationMargin * 4
                            implicitHeight: implicitWidth
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            onClicked: root.removeCustom(customRow.index)
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }

                MaterialTextField {
                    id: phraseField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("When I say\u2026  (e.g. movie mode)")
                }
                MaterialTextField {
                    id: actionField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Do\u2026  (e.g. theme dark; volume set 20; brightness set 30)")
                    onAccepted: addButton.clicked()
                }
                RippleButton {
                    id: addButton
                    Layout.alignment: Qt.AlignRight
                    buttonText: Translation.tr("Add command")
                    onClicked: {
                        if (root.addCustom(phraseField.text, actionField.text)) {
                            phraseField.text = "";
                            actionField.text = "";
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.customError.length > 0
                    wrapMode: Text.WordWrap
                    color: Appearance.m3colors.m3error
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: root.customError
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: Translation.tr("Actions: %1. Join several with a semicolon. Use {n} for a number you say, e.g. \u201cmake it {n}\u201d \u2192 volume set {n}. Your phrases are tried first.").arg(root.actionVerbs.join(", "))
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                title: Translation.tr("Learned phrases")
                icon: "school"

                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "psychology"
                    text: Translation.tr("Learn phrases from what the quick model does")
                    checked: Config.options.ai.voice.learn
                    onCheckedChanged: Config.options.ai.voice.learn = checked
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: Translation.tr("When a sentence no rule knew becomes the same action twice, it turns into an instant command. Only plain settings are learned, never sentences that depend on context, and never lock, restart or close. Built-in commands always win over these.")
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.learnedRules.length === 0
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Nothing learned yet.")
                }
                Repeater {
                    model: root.learnedRules
                    delegate: RowLayout {
                        id: learnedRow
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: Appearance.sizes.elevationMargin
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnLayer1
                            text: "\u201c" + learnedRow.modelData.phrase + "\u201d  \u2192  " + learnedRow.modelData.do
                        }
                        RippleButton {
                            implicitWidth: Appearance.sizes.elevationMargin * 4
                            implicitHeight: implicitWidth
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            onClicked: root.keepLearned(learnedRow.index)
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "bookmark_add"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledToolTip { text: Translation.tr("Keep as one of my own commands") }
                        }
                        RippleButton {
                            implicitWidth: Appearance.sizes.elevationMargin * 4
                            implicitHeight: implicitWidth
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            onClicked: root.forgetLearned(learnedRow.index)
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledToolTip { text: Translation.tr("Forget this phrase") }
                        }
                    }
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                title: Translation.tr("Try a sentence")
                icon: "science"

                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Type what you would say, then press Enter")
                    onAccepted: root.tryPhrase(text)
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.tryResult.length > 0
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colOnLayer1
                    text: root.tryResult
                }
            }
        }

        ContentSection {
            icon: "chat"
            title: Translation.tr("2 · Quick answers")

            Rectangle {
                Layout.fillWidth: true
                visible: !Ai.onlineAllowed
                implicitHeight: policyNote.implicitHeight + 24
                radius: Appearance.rounding.small
                color: Appearance.colors.colSecondaryContainer
                StyledText {
                    id: policyNote
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colOnSecondaryContainer
                    text: Translation.tr("Skipped because remote AI is %1 (see Remote AI above).").arg(Ai.localOnly ? Translation.tr("local only") : Translation.tr("off"))
                }
            }
            Rectangle {
                Layout.fillWidth: true
                visible: Ai.onlineAllowed && (Ai.companionVoice.claudeState === "missing" || Ai.companionVoice.claudeState === "signedOut")
                implicitHeight: missing.implicitHeight + 24
                radius: Appearance.rounding.small
                color: Appearance.colors.colErrorContainer
                RowLayout {
                    id: missing
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                    spacing: 10
                    MaterialSymbol { text: "warning"; iconSize: 20; color: Appearance.colors.colOnErrorContainer }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colOnErrorContainer
                        text: Ai.companionVoice.claudeState === "signedOut"
                            ? Translation.tr("Claude Code is installed but not signed in, so this stage is skipped and spoken and typed requests go straight to the desktop-tasks model. Sign in, and it is checked again automatically.")
                            : Translation.tr("Claude Code was not found, so this stage is skipped and spoken and typed requests go straight to the desktop-tasks model. Install it and sign in to turn quick answers on.")
                    }
                    RippleButton {
                        visible: Ai.companionVoice.claudeState === "signedOut"
                        buttonText: AiPlanUsage.claudeSignInPending ? Translation.tr("Waiting\u2026") : Translation.tr("Sign in")
                        // The same terminal sign-in the plan usage popup offers; it is re-checked when it finishes.
                        onClicked: AiPlanUsage.refreshClaudeSignIn()
                    }
                    RippleButton {
                        buttonText: Translation.tr("Check again")
                        onClicked: Ai.companionVoice.recheckClaude()
                    }
                }
            }
            ConfigSwitch {
                buttonIcon: "speed"
                text: Translation.tr("Answer chat and simple questions with a quick model")
                checked: Config.options.ai.voice.fastPath
                onCheckedChanged: Config.options.ai.voice.fastPath = checked
            }
            StyledComboBox {
                buttonIcon: "neurology"
                textRole: "displayName"
                model: root.quickOptions
                enabled: Config.options.ai.voice.fastPath
                currentIndex: Math.max(0, root.quickOptions.findIndex(item => item.value === String(Config.options.ai.voice.fastModel)))
                onActivated: index => Config.options.ai.voice.fastModel = root.quickOptions[index].value
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Ai.companionVoice.quickIsClaude
                    ? Translation.tr("A warm Claude session gives quick answers. It can receive battery or volume when you ask about them. Window titles, reminders and tasks stay with local rules.")
                    : Translation.tr("Plain questions go to this model with a short-answer prompt, usually 2 to 5 s. Anything that sounds like desktop work, and anything it cannot answer, goes to the desktop-tasks model.")
            }
            ConfigSwitch {
                buttonIcon: "visibility"
                text: Translation.tr("Allow automatic screen capture")
                enabled: Config.options.ai.voice.fastPath
                checked: Config.options.ai.voice.autoScreen
                onCheckedChanged: Config.options.ai.voice.autoScreen = checked
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Translation.tr("When you ask about your screen, the orb captures the focused monitor and sends it to Claude without showing it to you first. The chat notes each time. Needs quick answers with Claude, and never runs in Local only or on the lock screen.")
            }
            ConfigSwitch {
                buttonIcon: "screenshot_monitor"
                text: Translation.tr("Show Attach screen region on the orb")
                checked: Config.options.ai.voice.screen
                onCheckedChanged: Config.options.ai.voice.screen = checked
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Translation.tr("Choose a window or draw a region to add it to the chat draft. Review the image and selected model before sending. The image is shared for one turn.")
            }
        }

        ContentSection {
            icon: "receipt_long"
            title: Translation.tr("Last orb turn")

            StyledText {
                readonly property var receipt: Ai.companionVoice.lastReceipt
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: receipt === null ? Translation.tr("No recent orb turn.")
                    : Translation.tr("%1 · %2").arg(receipt.model).arg(receipt.outcome)
                        + (receipt.captureToAudioMs === null ? "" : "\n" + Translation.tr("Capture to audio: %1 ms").arg(receipt.captureToAudioMs))
                        + (receipt.context.length > 0 ? "\n" + Translation.tr("Quick model context: %1").arg(receipt.context.join(", ")) : "")
                        + (receipt.actions.length > 0 ? "\n" + receipt.actions.join("\n") : "")
            }
            RippleButton {
                buttonText: Translation.tr("Clear voice timing history")
                onClicked: Ai.companionVoice.clearTimings()
            }
        }

        ContentSection {
            icon: "desktop_windows"
            title: Translation.tr("3 · Desktop tasks")

            StyledComboBox {
                buttonIcon: "build"
                textRole: "displayName"
                model: root.taskOptions
                currentIndex: Math.max(0, root.taskOptions.findIndex(item => item.value === root.currentTask))
                onActivated: index => Config.options.ai.voice.escalationModel = root.taskOptions[index].value
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Translation.tr("Used when a request needs tools, the browser, settings or files. This only changes spoken requests; the sidebar keeps the model you picked there. "
                    + "Measured here on a “list my windows” request (2026-11-18): GLM 5.3 Flash about 2 s, Claude Haiku about 4 s, Codex about 22 s. A small fast model is quick but untested on hard multi-step work.")
            }
            ConfigSwitch {
                buttonIcon: "tune"
                text: Translation.tr("Let it carry out actions itself (timers, volume, opening apps)")
                checked: Config.options.ai.voice.actions
                onCheckedChanged: Config.options.ai.voice.actions = checked
            }
        }

        ContentSection {
            icon: "record_voice_over"
            title: Translation.tr("Voice")

            ConfigSlider {
                buttonIcon: "speed"
                text: Translation.tr("Speaking speed")
                from: 0.6
                to: 2.0
                stepSize: 0.05
                usePercentTooltip: false
                tooltipContent: Number(value).toFixed(2) + "\u00d7"
                value: Config.options.ai.voice.speechSpeed
                onValueChanged: Config.options.ai.voice.speechSpeed = Math.round(value * 100) / 100
            }
            ConfigSlider {
                buttonIcon: "more_horiz"
                text: Translation.tr("Pause between sentences (ms)")
                from: 0
                to: 400
                stepSize: 10
                usePercentTooltip: false
                value: Config.options.ai.voice.speechGapMs
                onValueChanged: Config.options.ai.voice.speechGapMs = Math.round(value)
            }
            RippleButton {
                Layout.alignment: Qt.AlignRight
                buttonText: Ai.speechService.speaking ? Translation.tr("Stop") : Translation.tr("Hear it")
                onClicked: {
                    if (Ai.speechService.speaking) Ai.speechService.stop();
                    else Ai.speechService.speak(Translation.tr("This is how fast I talk. Sentences run together, with a short pause between them."), "settings-test");
                }
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Translation.tr("Applies to the local voice (Kokoro), for the orb and for read-aloud. 1.0 is its natural pace; the default is 1.25. The pause is what is left after the voice's own padding is trimmed, so lowering it makes a reply flow, raising it makes it more deliberate. The voice and the cloud fallback for other scripts are unchanged.")
            }
        }

        ContentSection {
            icon: "mic"
            title: Translation.tr("Listening")

            ConfigSlider {
                buttonIcon: "timer"
                text: Translation.tr("End of speech: wait (s)")
                from: 0.3
                to: 1.5
                stepSize: 0.05
                usePercentTooltip: false
                tooltipContent: Number(value).toFixed(2) + " s"
                value: Config.options.ai.voice.endSilence
                onValueChanged: Config.options.ai.voice.endSilence = Math.round(value * 100) / 100
            }
            ConfigSwitch {
                buttonIcon: "translate"
                text: Translation.tr("English only (faster and more accurate)")
                checked: (Config.options.ai.voice.language ?? "en") === "en"
                onCheckedChanged: Config.options.ai.voice.language = checked ? "en" : "auto"
            }
            ConfigSwitch {
                buttonIcon: "graphic_eq"
                text: Translation.tr("Detect speech with a voice model (better in a noisy room)")
                checked: Config.options.ai.voice.vad
                onCheckedChanged: Config.options.ai.voice.vad = checked
            }
            ConfigSwitch {
                buttonIcon: "music_off"
                text: Translation.tr("Pause the music while I talk to the orb")
                checked: Config.options.ai.voice.pauseMedia
                onCheckedChanged: Config.options.ai.voice.pauseMedia = checked
            }
            ConfigSwitch {
                buttonIcon: "notifications_active"
                text: Translation.tr("Alert me when a coding session finishes or needs me")
                checked: Config.options.ai.voice.sessionAlerts
                onCheckedChanged: Config.options.ai.voice.sessionAlerts = checked
            }
            ConfigSwitch {
                buttonIcon: "record_voice_over"
                enabled: Config.options.ai.voice.sessionAlerts
                text: Translation.tr("Say session alerts out loud")
                checked: Config.options.ai.voice.sessionAlertsSpeak
                onCheckedChanged: Config.options.ai.voice.sessionAlertsSpeak = checked
            }
            StyledComboBox {
                buttonIcon: "hearing"
                textRole: "displayName"
                readonly property var options: [
                    {displayName: Translation.tr("Best installed (small, else base)"), value: "auto"},
                    {displayName: Translation.tr("Small \u00b7 more accurate, slower"), value: "small"},
                    {displayName: Translation.tr("Base \u00b7 fastest"), value: "base"}
                ]
                model: options
                currentIndex: Math.max(0, options.findIndex(item => item.value === String(Config.options.ai.voice.sttModel)))
                onActivated: index => Config.options.ai.voice.sttModel = options[index].value
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Translation.tr("A turn ends after this much quiet; a short phrase gets a little longer and a sentence that looks finished a little less. The voice model hears speech instead of loudness, so a fan or keyboard no longer holds the turn open. English only uses the English builds of the speech models, always answers in English and never sends speech to the cloud voice; turn it off to detect the spoken language. Speech-to-text runs on this machine; model and language changes apply from the next spoken turn.")
            }
        }

        ContentSection {
            id: engines
            icon: "settings_voice"
            title: Translation.tr("Speech engines")
            Component.onCompleted: Ai.voiceService.recheckSetup()

            readonly property var setup: Ai.voiceService.setup
            readonly property var downloading: setup.downloading ?? ({})
            function percent(kind) {
                const d = downloading[kind];
                return d ? Math.min(99, Math.round(d.bytes * 100 / Math.max(1, d.total))) : -1;
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Translation.tr("What the orb needs to hear you and answer aloud. It is using %1 to listen. Anything missing can be fetched here.")
                    .arg(Ai.voiceService.sttEngine === "hex" ? Translation.tr("Hex (the dictation engine)") : Translation.tr("Whisper"))
            }
            StyledComboBox {
                buttonIcon: "hearing"
                textRole: "displayName"
                readonly property var options: [
                    {displayName: Translation.tr("Follow dictation (Hex when it is the dictation engine)"), value: "auto"},
                    {displayName: Translation.tr("Always Hex"), value: "hex"},
                    {displayName: Translation.tr("Always Whisper"), value: "whisper"}
                ]
                model: options
                currentIndex: Math.max(0, options.findIndex(item => item.value === String(Config.options.ai.voice.sttEngine ?? "auto")))
                onActivated: index => Config.options.ai.voice.sttEngine = options[index].value
            }

            // Hex
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                MaterialSymbol {
                    text: engines.setup.hexTranscribe ? "check_circle" : "warning"
                    iconSize: 20
                    color: engines.setup.hexTranscribe ? Appearance.colors.colPrimary : Appearance.colors.colError
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: !engines.setup.hex ? Translation.tr("Hex is not installed. It is the fastest and most accurate option here (install the hex-bin package, then switch dictation to Hex).")
                        : engines.setup.hexTranscribe ? Translation.tr("Hex is ready: the orb reads your speech with the same model as the dictation keys.")
                        : Translation.tr("Hex is installed, but its \u201cTranscribe files\u201d lab is off, so the orb cannot use it yet.")
                }
                RippleButton {
                    visible: engines.setup.hex === true && engines.setup.hexTranscribe !== true
                    buttonText: Translation.tr("Turn on")
                    onClicked: Ai.voiceService.enableHexTranscribe()
                }
            }
            // Whisper
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                readonly property int pct: engines.percent("whisper")
                MaterialSymbol {
                    text: engines.setup.whisperEnglish ? "check_circle" : "warning"
                    iconSize: 20
                    color: engines.setup.whisperEnglish ? Appearance.colors.colPrimary : Appearance.colors.colError
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: parent.pct >= 0 ? Translation.tr("Downloading the Whisper English model\u2026 %1%").arg(parent.pct)
                        : engines.setup.whisperEnglish ? Translation.tr("Whisper is ready (%1).").arg((engines.setup.whisperModels ?? []).map(n => n.replace("ggml-", "").replace(".bin", "")).join(", "))
                        : (engines.setup.whisperModels ?? []).length > 0 ? Translation.tr("Whisper has only the multilingual model (%1); the English model is faster and more accurate.").arg((engines.setup.whisperModels ?? []).map(n => n.replace("ggml-", "").replace(".bin", "")).join(", "))
                        : Translation.tr("No Whisper model is installed, so without Hex the orb cannot hear you.")
                }
                RippleButton {
                    visible: engines.setup.whisperEnglish !== true && parent.pct < 0
                    buttonText: Translation.tr("Download (148 MB)")
                    onClicked: Ai.voiceService.downloadSpeech("whisper")
                }
            }
            // Kokoro
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                readonly property int pct: engines.percent("kokoro")
                MaterialSymbol {
                    text: engines.setup.kokoro ? "check_circle" : "warning"
                    iconSize: 20
                    color: engines.setup.kokoro ? Appearance.colors.colPrimary : Appearance.colors.colError
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: parent.pct >= 0 ? Translation.tr("Downloading the Kokoro voice\u2026 %1%").arg(parent.pct)
                        : engines.setup.kokoro ? Translation.tr("The Kokoro voice is installed: replies are spoken on this machine.")
                        : engines.setup.edgeTts && Ai.onlineAllowed ? Translation.tr("The Kokoro voice is not installed. Replies use the Edge cloud voice meanwhile, which sends the reply text to Microsoft.")
                        : Translation.tr("The Kokoro voice is not installed, so replies are not spoken.")
                }
                RippleButton {
                    visible: engines.setup.kokoro !== true && parent.pct < 0
                    buttonText: Translation.tr("Download (354 MB)")
                    onClicked: Ai.voiceService.downloadSpeech("kokoro")
                }
            }
            RippleButton {
                buttonText: Translation.tr("Check again")
                onClicked: { Ai.voiceService.recheckSetup(); Ai.voiceService.redetect(); }
            }
        }
    }
}
