pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions

Scope {
    id: root
    property bool active: false
    property bool oneShot: false
    property bool holdHeld: false
    property bool captureReady: false
    property string phase: "idle"
    property real level: 0
    property string errorText: ""
    property string submissionId: ""
    property string runId: ""
    property string recordingPath: ""
    property int detectionAttempts: 0
    property string pendingAsk: ""
    property var timings: ({})
    property double transcriptionStarted: 0
    property double generationStarted: 0
    property double speechRequested: 0
    property double listenStarted: 0
    property string route: ""
    property double captureEndedAt: 0
    property double firstAudioAt: 0
    property var lastReceipt: null
    property var turnActions: []
    property var sharedContextFields: []
    property bool loggedTurn: false
    readonly property string timingLog: FileUtils.trimFileProtocol(Directories.state) + "/user/ai/voice-timings.jsonl"
    readonly property string timingScript: Directories.scriptPath + "/ai/voice_metrics.py"

    function routeModel() {
        if (root.route === "rule") return "rules";
        if (root.route === "haiku") return root.fastModelId();
        if (root.route === "quick") return root.quickModelId();
        return root.escalationModelId() || Ai.currentModelId;
    }
    function metricsCommand(operation, data = null) {
        const command = ["python3", root.timingScript, operation, root.timingLog];
        if (data !== null) command.push(JSON.stringify(data));
        Quickshell.execDetached(command);
    }
    function clearTimings() { root.lastReceipt = null; root.metricsCommand("clear"); }
    function logTurn(outcome = "completed") {
        if (root.loggedTurn) return;
        root.loggedTurn = true;
        const t = root.timings;
        const data = {
            at: new Date().toISOString(), route: root.route, model: root.routeModel(), outcome: outcome,
            input: root.captureEndedAt > 0 ? "voice" : "text", captureMs: t.captureMs ?? null,
            transcriptionMs: t.transcriptionMs ?? null, generationMs: t.generationMs ?? null,
            firstTokenMs: t.firstTokenMs ?? null, speechStartMs: t.speechStartMs ?? null,
            captureToAudioMs: root.captureEndedAt > 0 && root.firstAudioAt >= root.captureEndedAt
                ? root.firstAudioAt - root.captureEndedAt : null
        };
        root.lastReceipt = Object.assign({}, data, {actions: root.turnActions.slice(), context: root.sharedContextFields.slice()});
        root.metricsCommand("record", data);
    }
    function resetTimings() {
        root.loggedTurn = false;
        root.timings = ({});
        root.captureEndedAt = 0;
        root.firstAudioAt = 0;
        root.speechRequested = 0;
        root.turnActions = [];
        root.sharedContextFields = [];
    }
    readonly property string state: root.active && root.runId.length > 0
        && (Ai.runCoordinator.runFor(root.runId)?.state === "needsAction" || AiCompanionUi.approval !== null)
        ? "attention" : root.phase

    // ── Personality: a short-lived mood the creature wears ───────────────────────
    property string mood: ""
    // Counts wake-word hits, so the orb can show it heard you.
    property int wakeCount: 0
    function setMood(name, ms) {
        root.mood = name;
        moodTimer.interval = ms;
        moodTimer.restart();
    }
    Timer { id: moodTimer; onTriggered: root.mood = "" }
    AiCompanionActions { id: actions }

    function fail(message) {
        root.abortAgentTurn();
        if (root.fastId.length > 0) root.releaseQuickTurn();
        root.active = false;
        root.oneShot = false;
        root.holdHeld = false;
        root.pendingAsk = "";
        root.phase = "error";
        root.level = 0;
        root.errorText = String(message);
        if (Ai.voiceService.activeSurface === "orb") Ai.voiceService.cancel();
        if (capture.running) capture.signal(15);
        root.submissionId = "";
        root.runId = "";
    }
    // The Settings switch for the orb as a whole.
    readonly property bool orbEnabled: Config.options.ai.voice.orbEnabled !== false
    onOrbEnabledChanged: {
        if (root.orbEnabled) return;
        root.stop();
        root.agentQueue = [];
        voiceAgent.running = false;
        // Forget the session list too: switching back on must not announce what changed meanwhile.
        sessionProc.running = false;
        sessionSpeakTimer.stop();
        root.sessionAlertQueue = [];
        root.sessionStates = ({});
        root.sessionBaseline = false;
    }
    function start(hold = false) {
        if (!root.orbEnabled || GlobalStates.screenLocked) return;
        if (Ai.isGenerating && root.runId.length === 0) {
            root.fail("The assistant is already working. Open the sidebar to see its progress.");
            return;
        }
        root.oneShot = hold;
        root.active = true;
        root.phase = "starting";
        root.resetTimings();
        root.transcriptionStarted = 0;
        if (root.quickReady) root.sendAgent({op: "warm", session: Ai.sessions.currentId});
        if (Ai.speechService.speaking) Ai.speechService.stop();
        root.pauseMediaForTurn();
        root.errorText = "";
        root.detectionAttempts = 0;
        Ai.voiceService.ensureDetected();
        if (hold) root.beginListening();
        else listenTimer.restart();
    }

    // Music is paused while you talk to the orb, like dictation does, and comes back once the whole
    // turn (the reply too) is over. Only music this paused is resumed, never one you paused yourself.
    property bool mediaPausedByOrb: false
    function pauseMediaForTurn() {
        if (Config.options.ai.voice.pauseMedia === false || root.mediaPausedByOrb) return;
        if (MprisController.activePlayer && MprisController.isPlaying) {
            MprisController.togglePlaying();
            root.mediaPausedByOrb = true;
            mediaResume.restart();
        }
    }
    Timer {
        id: mediaResume
        interval: 600; repeat: true
        onTriggered: {
            if (!root.mediaPausedByOrb) { mediaResume.stop(); return; }
            if (root.active || Ai.speechService.speaking || capture.running) return;
            root.mediaPausedByOrb = false;
            mediaResume.stop();
            if (MprisController.activePlayer && !MprisController.isPlaying) MprisController.togglePlaying();
        }
    }

    function holdStart() {
        if (!root.orbEnabled || root.holdHeld || GlobalStates.screenLocked) return;
        // Push to talk interrupts: whatever the orb is saying or working on stops, and it listens.
        if (root.active || capture.running || Ai.speechService.speaking) root.stop();
        else if (Ai.isGenerating) return;
        root.holdHeld = true;
        root.start(true);
    }

    function holdRelease() {
        if (!root.holdHeld)
            return;
        root.holdHeld = false;
        if (root.captureReady && capture.running)
            capture.signal(10);
        else
            root.stop();
    }

    function finishSpokenTurn(afterChime = false) {
        root.phase = "idle";
        root.level = 0;
        if (AiCompanionUi.approval !== null)
            return;
        if (root.oneShot) {
            root.oneShot = false;
            root.active = false;
        } else if (afterChime) {
            chimeTimer.restart();
        } else {
            listenTimer.restart();
        }
    }
    // Also accepts an explicit prompt from local IPC; it follows the same
    // correlated response path as a transcribed utterance.
    // ── Approvals by voice ───────────────────────────────────────────────────────
    property string announcedCall: ""
    readonly property var yesWords: /\b(yes|yeah|yep|yup|ok|okay|sure|allow|approve|go ahead|do it|proceed|confirm)\b|نعم|أجل|موافق|تمام|اوكي/i
    readonly property var noWords: /\b(no|nope|nah|deny|don'?t|do not|stop|cancel|reject|refuse|never)\b|^\s*لا\b|ارفض|توقف|الغ/i
    function announceApproval() {
        const pending = AiCompanionUi.approval;
        if (!pending || root.announcedCall === pending.callId) return;
        root.announcedCall = pending.callId;
        const about = AiCompanionUi.describe(pending);
        const how = about.strict ? Translation.tr("Tap Allow on the card to confirm.") : Translation.tr("Tap Allow or Deny, or tap me and answer.");
        // A short sentence: the card has the detail, and reading a command aloud is no use.
        Ai.speechService.speak(Translation.tr("I need your approval to %1. %2").arg(about.spoken).arg(how), "orb:approval-" + pending.callId);
        root.phase = "preparing";
    }
    function approvalAnswered(allow) {
        // The run carries on by itself: wait for it, then the answer is spoken as usual.
        root.phase = "thinking";
        if (capture.running) capture.signal(15);
        if (Ai.speechService.speaking) Ai.speechService.stop();
    }
    /** 1 yes, -1 no, 0 neither. A "no" wins when both are heard. */
    function approvalVerdict(text) {
        const said = String(text);
        if (root.noWords.test(said)) return -1;
        return root.yesWords.test(said) ? 1 : 0;
    }

    function ask(text) {
        if (!root.orbEnabled) return;
        if (AiCompanionUi.approval !== null) {
            const pending = AiCompanionUi.approval;
            const about = AiCompanionUi.describe(pending);
            const verdict = root.approvalVerdict(text);
            // An administrator command is never approved by a voice: a stray "ok" from a
            // video or a neighbour must not run something as root.
            if (verdict !== 0 && !(about.strict && verdict > 0)) {
                AiCompanionUi.answerApproval(verdict > 0);
                return;
            }
            root.phase = "idle";
            if (!root.oneShot) listenTimer.restart();
            return;
        }
        const wantsFast = root.agentUseful && Ai.attachmentWorkPending === false
            && Ai.attachments.length === 0 && !Ai.isGenerating;
        if (wantsFast && root.fastAsk(String(text)))
            return;
        root.askFull(text, !root.quickReady && Ai.attachments.length === 0);
    }
    // The model for turns that need the desktop. Empty keeps whatever the sidebar has selected. Claude Haiku
    // did the same tool turn in 3.7 s against 21.6 s on Codex (2026-11-18), but it is a different
    // model and subscription, so it is an opt-in: ai.voice.escalationModel = "haiku" (or "sonnet").
    function escalationModelId() {
        const alias = String(Config.options.ai.voice.escalationModel ?? "").trim();
        if (alias.length === 0) return "";
        const id = alias.indexOf(":") > 0 ? alias : "claude:" + alias;
        // Local only: a pinned remote model is not used; the chat model (which must be local) takes over.
        if (Ai.localOnly && Ai.catalog.models[id] && !Ai.catalog.isModelLocal(Ai.catalog.models[id])) return "";
        return Ai.catalog.models[id] ? id : "";
    }
    // When the warm Claude stage cannot answer, a plain question goes to the chosen fallback model with a
    // short-answer prompt; anything that sounds like desktop work keeps the desktop-tasks model.
    readonly property var desktopWords: /\b(open|close|launch|quit|kill|click|type|send|play|pause|resume|skip|search|find|show|switch|move|resize|set|turn|enable|disable|change|install|run|download|screenshot|record|list|which|windows?|files?|folders?|wallpaper|settings?|telegram|browser|terminal|mediator)\b/i;
    // The quick-answers model is one setting. A Claude model runs as the warm resident session; any other
    // catalog model answers through an ordinary short-answer turn, and a Claude model that cannot run
    // (CLI missing or signed out) falls through to the desktop-tasks model.
    readonly property string quickValue: String(Config.options.ai.voice.fastModel ?? "").trim()
    readonly property bool quickIsClaude: root.quickValue.indexOf(":") < 0 || root.quickValue.indexOf("claude:") === 0
    function quickModelId() {
        if (Config.options.ai.voice.fastPath !== true || root.quickIsClaude) return "";
        const id = root.quickValue;
        if (Ai.localOnly && Ai.catalog.models[id] && !Ai.catalog.isModelLocal(Ai.catalog.models[id])) return "";
        return Ai.catalog.models[id] ? id : "";
    }
    // The model for a turn that left the quick stage. `unavailable` is true when the stage could not run,
    // false when Claude itself asked for the desktop.
    function handoverModelId(text, unavailable) {
        if (unavailable && !root.desktopWords.test(String(text))) {
            const quick = root.quickModelId();
            if (quick.length > 0) return quick;
        }
        return root.escalationModelId();
    }
    function askFull(text, unavailable, toolRequired = false) {
        if (Ai.attachmentWorkPending) {
            root.active = true;
            root.pendingAsk = String(text);
            root.phase = "reading-files";
            return;
        }
        root.pendingAsk = "";
        root.route = "agent";
        root.agentStreaming = false;
        root.fastBuffer = "";
        root.fastSent = 0;
        root.fastWhole = false;
        if (Ai.isGenerating) { root.fail("The assistant is already working."); return; }
        // With the chat's Tools switch off the model is offered nothing, and some models then act out
        // tool calls in plain text. Say so instead of sending the turn.
        if (Ai.functionExposure === "none" && toolRequired) {
            root.fail(Translation.tr("Tools are switched off in the chat, so I can't do desktop tasks. Turn Tools on in the sidebar."));
            return;
        }
        root.active = true;
        root.errorText = "";
        root.phase = "thinking";
        root.generationStarted = Date.now();
        root.route = (unavailable === true && root.handoverModelId(text, true) !== root.escalationModelId()) ? "quick" : "agent";
        const result = Ai.submit(String(text), {
            modelId: root.handoverModelId(text, unavailable === true),
            attachments: Ai.attachments,
            denyScreenCapture: true,
            systemPrompt: Ai.systemPrompt + "\nThis turn is a spoken conversation through the desktop voice orb. Give a natural spoken answer, usually one to three short sentences. Avoid markdown, long lists and code unless explicitly requested. Keep the existing tool and approval rules. For visual questions, ask the user to attach a screen region."
        }, "voice-orb");
        if (!result.accepted) { root.fail("Could not send your voice message. Open the sidebar for details."); return; }
        root.submissionId = String(result.submissionId ?? "");
    }
    // ── Fast path: a warm Claude session, spoken a sentence at a time ───────────
    property string fastId: ""
    property string fastSessionId: ""
    property int fastSerial: 0
    property var sttSettings: null
    readonly property bool capturing: capture.running || (root.active && root.phase === "listening")
    Timer {
        id: quickDeadline
        interval: 42000
        onTriggered: {
            root.abortAgentTurn();
            root.fastFallback("The quick model timed out.");
        }
    }
    property string fastText: ""
    property string fastBuffer: ""
    property int fastSent: 0
    property bool fastWhole: false
    property var fastNotes: []
    property bool fastLooked: false   // this quick turn sent a screenshot to the model
    // What the chat records beside a quick reply: that the screen was looked at, and what was done.
    function turnMarks(notes) {
        return (root.fastLooked ? [Translation.tr("Looked at your screen")] : []).concat(notes);
    }
    property bool agentReady: false
    // A message typed in the sidebar, routed like a spoken one (instant rules, then the warm
    // quick-answer session, then the desktop-tasks model) but answered in text, never aloud.
    property bool typed: false
    // The quick-answer stage is a resident `claude` process: without the CLI, or without a signed-in account,
    // it cannot run, so every surface that would promise it (typed routing, the chip, the settings page)
    // checks this first. `claudeState`: "checking", "ready", "missing" (not installed) or "signedOut".
    property string claudeState: "checking"
    readonly property bool claudeFound: root.claudeState !== "missing"
    // Claude is a remote model, so it also needs the global AI policy (Settings > Sidebars) to allow online use:
    // "Local only" and "Off" both rule it out, along with the screenshot it can be sent.
    readonly property bool quickReady: Config.options.ai.voice.fastPath === true && Ai.onlineAllowed && root.quickIsClaude
        && root.claudeState !== "missing" && root.claudeState !== "signedOut"
    // The quick model may capture the screen when asked about it. Off until the user switches it on (the
    // agent cannot: ai.* settings are protected), and only while the remote model itself may be used.
    readonly property bool autoScreen: Config.options.ai.voice.autoScreen === true && root.quickReady
    // Whether anything in the agent can still help: the instant rules need no model at all.
    readonly property bool agentUseful: root.quickReady || Config.options.ai.voice.rules !== false
    Connections {
        target: Ai
        // Switching remote AI off ends the warm Claude session and drops any turn it was answering.
        function onOnlineAllowedChanged() {
            if (Ai.onlineAllowed) return;
            root.stop();
            root.resetAgent();
        }
    }
    function recheckClaude() { if (!claudeCheck.running) claudeCheck.running = true; }
    // The plan-usage service already watches Claude's credentials file (and runs the terminal sign-in):
    // when it sees a sign-in finish or change, ask again instead of waiting for a click.
    Connections {
        target: AiPlanUsage
        function onClaudeSignInPendingChanged() { if (!AiPlanUsage.claudeSignInPending) root.recheckClaude(); }
        function onClaudeNeedsSignInChanged() { root.recheckClaude(); }
    }
    // Asked the way the agent runs it (without the API-key variables it strips), so the answer matches.
    Process {
        id: claudeCheck
        command: ["sh", "-c", "command -v claude >/dev/null 2>&1 || { echo missing; exit 0; }; "
            + "env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u CLAUDE_CODE_OAUTH_TOKEN -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT "
            + "-u ANTHROPIC_BASE_URL -u CLAUDE_CODE_USE_BEDROCK -u CLAUDE_CODE_USE_VERTEX timeout 15 claude auth status 2>/dev/null"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const said = String(text);
                if (said.indexOf("missing") === 0) root.claudeState = "missing";
                else if (/"loggedIn"\s*:\s*true/.test(said)) root.claudeState = "ready";
                else if (/"loggedIn"\s*:\s*false/.test(said)) root.claudeState = "signedOut";
                // Anything else (a timeout, an older CLI with no `auth status`): do not block the stage.
                else root.claudeState = "ready";
            }
        }
    }
    property var agentQueue: []
    readonly property var nonLatin: /[\u0400-\u052f\u0590-\u08ff\u0900-\u0dff\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]/

    // The instant-command settings, sent when the agent starts and whenever they change.
    readonly property string agentModel: root.quickIsClaude ? root.quickValue.replace(/^claude:/, "") : "haiku"
    readonly property string agentLanguage: String(Config.options.ai.voice.language ?? "en")
    readonly property bool localRulesEnabled: Config.options.ai.voice.rules !== false
    readonly property string agentSettings: JSON.stringify([root.agentModel, root.agentLanguage, root.localRulesEnabled, root.autoScreen])
    onAgentSettingsChanged: {
        if (root.fastId.length > 0) root.stop();
        root.resetAgent();
    }
    readonly property string rulesConfig: JSON.stringify({op: "config", model: root.agentModel,
        language: root.agentLanguage, rulesEnabled: root.localRulesEnabled, screen: root.autoScreen,
        rulesOff: Array.from(Config.options.ai.voice.rulesOff ?? []),
        custom: Array.from(Config.options.ai.voice.customRules ?? []),
        learned: Array.from(Config.options.ai.voice.learnedRules ?? []),
        learn: Config.options.ai.voice.learn !== false})
    onRulesConfigChanged: if (voiceAgent.running && root.agentReady) voiceAgent.write(root.rulesConfig + "\n")
    function sendAgent(message) {
        if (voiceAgent.running && root.agentReady) {
            voiceAgent.write(JSON.stringify(message) + "\n");
            return;
        }
        root.agentQueue = root.agentQueue.concat([message]);
        if (!voiceAgent.running) voiceAgent.running = true;
    }
    function abortAgentTurn() {
        root.agentQueue = [];
        if (voiceAgent.running && root.agentReady)
            voiceAgent.write(JSON.stringify({op: "cancel", id: root.fastId}) + "\n");
    }
    function resetAgent() {
        root.agentQueue = [];
        if (voiceAgent.running && root.agentReady)
            voiceAgent.write('{"op":"reset"}\n');
    }
    // A turn that is "thinking" with nothing behind it (no quick turn, no run, no submission) for this long
    // is stuck: let go of it rather than leave the orb waiting forever.
    property double thinkingSince: 0
    onPhaseChanged: root.thinkingSince = root.phase === "thinking" ? Date.now() : 0
    Timer {
        interval: 10000; repeat: true
        running: root.phase === "thinking"
        onTriggered: {
            const orphan = root.fastId.length === 0 && root.runId.length === 0 && root.submissionId.length === 0 && !Ai.isGenerating;
            if (orphan && root.thinkingSince > 0 && Date.now() - root.thinkingSince > 30000) {
                console.log("[voice] stuck thinking for 30 s with no turn behind it; stopping");
                root.stop();
            }
        }
    }
    // The id of what was said, already shown in the chat while the answer is still being worked out.
    property string postedUserId: ""
    function takePosted() { const id = root.postedUserId; root.postedUserId = ""; return id; }
    function releaseQuickTurn() {
        root.postedUserId = "";
        quickDeadline.stop();
        const id = root.fastId;
        root.fastId = "";
        root.fastSessionId = "";
        root.typed = false;
        Ai.endSharedTask(id);
    }
    function resetForChatChange() {
        if (root.fastId.length > 0 || (root.active && !root.runId && !root.submissionId))
            root.stop();
        root.resetAgent();
    }
    Connections {
        target: Ai.sessions
        function onCurrentIdChanged() {
            if (root.fastId.length > 0 && root.fastSessionId !== Ai.sessions.currentId)
                root.resetForChatChange();
        }
    }
    // Picking a model in the sidebar pins it for this session: typed messages go to it instead of being
    // routed. Choosing "Auto" in the picker hands them back to the router. Not saved; a restart starts on Auto.
    property bool pinnedChatModel: false
    /** Whether a typed message should take the same route as speech. */
    function canRouteTyped(text) {
        const settings = Config.options.ai.voice;
        return root.orbEnabled && settings.typedRouting === true && !root.pinnedChatModel && root.agentUseful && Ai.enabled
            && !root.active && root.fastId.length === 0 && !root.typed
            && Ai.attachments.length === 0 && !Ai.attachmentWorkPending && !Ai.isGenerating
            && String(text ?? "").trim().length > 0 && String(text).trim().length < 2000
            && !/^[\/!]/.test(String(text).trim());
    }
    function typedAsk(text) {
        root.resetTimings();
        root.typed = true;
        if (!root.fastAsk(String(text))) {
            root.typed = false;
            return {accepted: false, state: "rejected", errorCode: "busy"};
        }
        Ai.clearDraftIfCurrent(text);
        return {accepted: true, state: "pending", routed: "quick"};
    }
    /** The typed turn is over: put it in the chat, with what was done, and let the orb rest. */
    function typedFinish(question, answer, notes, rule) {
        const marks = root.turnMarks(notes);
        root.fastLooked = false;
        const done = marks.length > 0 ? "(" + marks.join("; ") + ")" : "";
        const reply = done.length > 0 && answer.length > 0 ? done + "\n\n" + answer : done + answer;
        const inChat = root.fastSessionId === Ai.sessions.currentId;
        root.releaseQuickTurn();
        root.fastNotes = [];
        if (root.mood === "curious") root.mood = "";
        root.phase = "idle";
        if (inChat && reply.trim().length > 0) {
            Ai.addMessage(question, "user");
            Ai.addMessage(reply, "assistant", {"model": rule ? "rules" : root.fastModelId()});
            Ai.sessions.scheduleSave();
        }
        root.timings = Object.assign({}, root.timings, {generationMs: Date.now() - root.generationStarted});
        if (rule) root.route = "rule";
        root.logTurn();
    }
    // The context block the quick-answer model is given with each turn (read-only; used by `aitools orbContext`).
    function contextText() { return actions.snapshot(); }
    function fastAsk(text) {
        const activeRun = Ai.runCoordinator.runFor(Ai.runCoordinator.activeRunId);
        if (Ai.isGenerating || Ai.runCoordinator.activeStates.includes(activeRun?.state) || !Ai.enabled || GlobalStates.screenLocked)
            return false;
        const id = "orb-quick:" + Date.now() + ":" + (++root.fastSerial);
        if (!Ai.beginSharedTask(id))
            return false;
        root.fastSessionId = Ai.ensureOrbChatId();
        root.route = "haiku";
        root.pendingAsk = "";
        if (!root.typed) root.active = true;
        root.errorText = "";
        root.phase = "thinking";
        root.generationStarted = Date.now();
        root.fastId = id;
        root.chosenActions = [];
        root.chosenAllRan = true;
        root.fastText = text;
        // A spoken request shows in the chat at once, not only when the reply is done.
        root.postedUserId = "";
        if (!root.typed && root.fastSessionId === Ai.sessions.currentId && text.trim().length > 0) {
            Ai.addMessage(text, "user");
            root.postedUserId = Ai.messageIDs[Ai.messageIDs.length - 1] ?? "";
            Ai.sessions.scheduleSave();
        }
        root.fastBuffer = "";
        root.fastSent = 0;
        root.fastWhole = false;
        root.fastNotes = [];
        root.fastLooked = false;
        const remoteContext = root.quickReady ? actions.contextForModel(text) : "";
        root.sharedContextFields = remoteContext ? remoteContext.split("\n").map(line => line.split(":")[0]) : [];
        root.sendAgent({op: "ask", id: id, text: text,
                        context: root.localRulesEnabled ? actions.snapshot() : "",
                        remoteContext: remoteContext, quick: root.quickReady,
                        via: root.typed ? "typed" : "spoken", session: root.fastSessionId,
                        screen: root.autoScreen && !GlobalStates.screenLocked,
                        target: actions.focusedWindowId()});
        quickDeadline.restart();
        return true;
    }
    // Hand off whole sentences to the speaker. The first may be a clause: waiting for
    // a full stop is what makes a long reply feel slow to start.
    function drainSpeech(final) {
        if (root.typed) return;
        if (root.fastWhole && !final) return;
        while (true) {
            const rest = root.fastBuffer.slice(root.fastSent);
            if (rest.trim().length === 0) return;
            if (!root.fastWhole && root.fastSent === 0 && root.nonLatin.test(root.fastBuffer)) {
                // Scripts the local voice cannot say go to the cloud voice, which wants the
                // whole text: speak it once the reply is complete.
                root.fastWhole = true;
                if (!final) return;
            }
            let cut = -1;
            const stop = /[.!?\u061f\u2026\u3002]+["'\u201d)\]]*\s/.exec(rest);
            if (stop) cut = stop.index + stop[0].length;
            else if (root.fastSent === 0 && rest.length > 60) {
                const clause = /[,;:\u060c]\s/.exec(rest.slice(20));
                if (clause) cut = 20 + clause.index + clause[0].length;
            }
            if (root.fastWhole) cut = final ? rest.length : -1;
            if (cut < 0 && final) cut = rest.length;
            if (cut < 0) return;
            root.speakChunk(rest.slice(0, cut));
            root.fastSent += cut;
        }
    }
    // ── Desktop-task replies, spoken while they are still being written ─────────
    // The full agent answers through the chat, so its reply used to be spoken only once complete.
    // This reads the growing reply and hands finished sentences to the same sentence-streamed
    // speaker the quick path uses. A reply that shrinks (a new segment after a tool call) starts over.
    property bool agentStreaming: false
    function agentReply() {
        const run = Ai.runCoordinator.runFor(root.runId);
        const id = String(run?.responseMessageId ?? "");
        // The reply being written lives in the running set until the run ends.
        const message = id.length > 0 ? (Ai.runningMessageByID[id] ?? Ai.messageByID[id]) : null;
        return String(message?.content ?? "");
    }
    function agentStreamTick() {
        if (root.typed || !root.active || root.runId.length === 0) return;
        const text = root.agentReply();
        if (text.length === 0) return;
        if (text.length < root.fastSent) root.fastSent = 0;
        root.fastBuffer = text;
        const before = Ai.speechService.streamOpen;
        root.drainSpeech(false);
        if (Ai.speechService.streamOpen && !before) root.agentStreaming = true;
    }
    Timer {
        interval: 250
        repeat: true
        running: root.active && root.route === "agent" && root.runId.length > 0 && !root.typed
        onTriggered: root.agentStreamTick()
    }
    function speakChunk(chunk) {
        if (!Ai.speechService.streamOpen) {
            if (!Ai.speechService.beginStream("orb:" + root.fastId)) return;
            root.phase = "preparing";
            root.speechRequested = Date.now();
        }
        Ai.speechService.pushText(chunk);
    }
    // A pattern-matched command that ran: the screen already shows the result (OSD, timer, app), so a
    // short chime says "done" in 0.14 s where a sentence takes 0.7 s to even start. Not when the
    // user has shell sounds off, or switched this off: then it is spoken as before.
    readonly property string chimeFile: "/usr/share/sounds/freedesktop/stereo/bell.oga"
    function chimeAllowed(event) {
        return !!event.rule && root.fastNotes.length > 0 && Config.options.ai.voice.chime !== false
            && Config.options.sounds.enable === true;
    }
    Timer { id: chimeTimer; interval: 420; onTriggered: root.beginListening() }
    function fastDone(event) {
        root.timings = Object.assign({}, root.timings, {firstTokenMs: event.firstTokenMs ?? null});
        if (event.rule) root.sharedContextFields = [];
        if (root.typed) {
            root.typedFinish(root.fastText, String(event.text ?? "").trim(), root.fastNotes, !!event.rule);
            return;
        }
        const chime = root.chimeAllowed(event);
        // A rule hit carries its confirmation in `text` only; speak it unless chiming instead.
        if (event.rule && !chime) root.fastBuffer = String(event.text ?? "");
        root.drainSpeech(true);
        if (event.rule) root.route = "rule";
        else if (root.fastLooked) root.route = "look";
        root.timings = Object.assign({}, root.timings, {
            generationMs: Date.now() - root.generationStarted, firstTokenMs: event.firstTokenMs ?? 0});
        const answer = String(event.text ?? "").trim();
        const notes = root.fastNotes;
        const marks = root.turnMarks(notes);
        root.fastLooked = false;
        // The model turned a sentence no rule knew into actions that all ran: let the agent weigh remembering it.
        if (!event.rule && root.chosenAllRan && root.chosenActions.length > 0 && Config.options.ai.voice.learn !== false)
            root.sendAgent({op: "learn", text: root.fastText, actions: root.chosenActions});
        root.chosenActions = [];
        root.chosenAllRan = true;
        const inChat = root.fastSessionId === Ai.sessions.currentId;
        const alreadyPosted = root.takePosted().length > 0;
        root.releaseQuickTurn();
        root.fastNotes = [];
        if (root.mood === "curious") root.mood = "";
        if (inChat && (answer.length > 0 || marks.length > 0)) {
            // The exchange belongs in the chat the sidebar shows, and in what the full
            // agent reads as history on the next tool turn, including what was done.
            const done = marks.length > 0 ? "(" + marks.join("; ") + ")" : "";
            if (!alreadyPosted) Ai.addMessage(root.fastText, "user");
            Ai.addMessage(done.length > 0 && answer.length > 0 ? done + "\n\n" + answer : done + answer,
                          "assistant", {"model": root.fastModelId()});
            Ai.sessions.scheduleSave();
        }
        if (chime) {
            Quickshell.execDetached(["pw-play", "--volume", "0.5", root.chimeFile]);
            root.timings = Object.assign({}, root.timings, {speechStartMs: 0});
            root.logTurn();
            root.finishSpokenTurn(true);
            return;
        }
        if (Ai.speechService.streamOpen) Ai.speechService.endStream();
        else if (answer.length === 0) root.stop();
        else if (root.oneShot) {
            root.logTurn();
            root.finishSpokenTurn();
        }
        if (root.firstAudioAt > 0) root.logTurn();
    }
    // The model that really answered, as the catalog names it, so the chat does not
    // label a warm Haiku reply with whichever model is selected for the full agent.
    function fastModelId() {
        if (!root.quickIsClaude) return root.quickValue;
        const alias = root.quickValue.replace(/^claude:/, "");
        const key = Object.keys(Ai.models).find(id => id.indexOf("claude") === 0 && id.endsWith(":" + alias));
        return key ?? ("claude:" + alias);
    }
    // A phrase the agent decided to remember. Kept in the config, where Settings lists it.
    function keepLearned(rule) {
        if (!rule || String(rule.phrase ?? "").length === 0 || String(rule.do ?? "").length === 0) return;
        const list = Array.from(Config.options.ai.voice.learnedRules ?? []);
        if (list.some(item => item.phrase === rule.phrase)) return;
        Config.options.ai.voice.learnedRules = list.concat([rule]).slice(-100);

    }
    // A marker the shell could not carry out. Nothing was spoken yet, so the full agent
    // can take the turn; if something already ran, say so instead of redoing it.
    // Actions the quick model chose this turn (not a rule), for learning: all must run for the sentence to count.
    property var chosenActions: []
    property bool chosenAllRan: true
    function fastAction(event) {
        if (event.source === "model" && event.verb === "capture") {
            root.abortAgentTurn();
            const reply = Translation.tr("Use Attach screen region to choose what to share.");
            root.fastBuffer = reply;
            root.fastDone({text: reply});
            return;
        }
        if (event.source === "model" && Ai.functionExposure === "none") {
            root.abortAgentTurn();
            root.fastFallback("needs the desktop");
            return;
        }
        if (event.confirmed === true && event.verb === "close" && (!event.target || event.target !== actions.focusedWindowId())) {
            root.abortAgentTurn();
            const reply = Translation.tr("The focused window changed. Ask again on the window you want to close.");
            root.fastBuffer = reply;
            root.fastDone({text: reply});
            return;
        }
        const result = actions.run(event.verb, event.args, event.confirmed === true);
        if (event.source === "model") {
            if (result.ok) root.chosenActions = root.chosenActions.concat([[String(event.verb), Array.from(event.args ?? []).map(a => String(a))]]);
            else root.chosenAllRan = false;
        }
        if (result.ok) {
            root.fastNotes = root.fastNotes.concat([result.note]);
            root.turnActions = root.turnActions.concat([result.note]);
            root.setMood("delighted", 2200);
            return;
        }
        root.abortAgentTurn();
        root.fastFallback("action refused");
    }
    function fastFallback(reason) {
        // The agent says so when the CLI vanished after the check: stop offering the stage.
        if (/not installed/i.test(String(reason))) root.claudeState = "missing";
        else if (/log ?in|sign ?in|authenticat|api key|credentials|unauthori[sz]ed|oauth/i.test(String(reason))) root.claudeState = "signedOut";
        if (root.fastId.length === 0 || root.fastSessionId !== Ai.sessions.currentId) {
            root.stop();
            return;
        }
        if (root.fastNotes.length > 0) {
            const reply = Translation.tr("Some actions completed. I stopped before retrying the rest.");
            if (root.typed) {
                root.typedFinish(root.fastText, reply, root.fastNotes, false);
            } else {
                root.chosenAllRan = false;
                root.fastBuffer = reply;
                root.fastSent = 0;
                root.fastDone({text: reply});
            }
            return;
        }
        const text = root.fastText;
        const typed = root.typed;
        // The full agent posts the request again itself.
        const early = root.takePosted();
        if (early.length > 0) Ai.removeMessage(early);
        const needsTools = ["needs the desktop", "action refused"].includes(String(reason));
        root.chosenActions = [];
        root.chosenAllRan = true;
        root.releaseQuickTurn();
        if (typed) {
            root.phase = "idle";
            const result = Ai.submit(text, {
                modelId: root.handoverModelId(text, !needsTools), attachments: [],
                denyScreenCapture: true
            }, "chat");
            if (!result.accepted) root.fail(Translation.tr("The assistant could not continue this turn."));
            return;
        }
        if (Ai.speechService.streamOpen) Ai.speechService.stop();
        root.askFull(text, !needsTools, needsTools);
    }
    Process {
        id: voiceAgent
        command: ["python3", Directories.scriptPath + "/ai/voice_agent.py"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                let event;
                try { event = JSON.parse(line); } catch (e) { return; }
                if (event.event === "ready") {
                    root.agentReady = true;
                    voiceAgent.write(root.rulesConfig + "\n");
                    const queued = root.agentQueue;
                    root.agentQueue = [];
                    for (const message of queued) voiceAgent.write(JSON.stringify(message) + "\n");
                    return;
                }
                if (event.event === "learned") { root.keepLearned(event.rule); return; }
                if (event.id !== root.fastId || root.fastId.length === 0 || root.fastSessionId !== Ai.sessions.currentId) return;
                if (event.event === "delta") {
                    root.fastBuffer += String(event.text);
                    root.drainSpeech(false);
                } else if (event.event === "done") root.fastDone(event);
                else if (event.event === "action") root.fastAction(event);
                else if (event.event === "looking") {
                    root.fastLooked = true;
                    root.sharedContextFields = root.sharedContextFields.concat(["screenshot"]);
                    root.setMood("curious", 40000);
                    quickDeadline.restart();
                }
                else if (event.event === "look-required") {
                    const reply = Translation.tr("To let me look, switch on Allow automatic screen capture in the Voice orb settings, or use Attach screen region.");
                    root.fastBuffer = reply;
                    root.fastDone({text: reply});
                }
                else if (event.event === "escalate") root.fastFallback("needs the desktop");
                else if (event.event === "error") root.fastFallback(event.message);
            }
        }
        onExited: {
            root.agentReady = false;
            root.agentQueue = [];
            if (root.fastId.length > 0) root.fastFallback("the voice agent exited");
        }
    }

    // ── Coding-session alerts ─────────────────────────────────────────────────────────────────────
    // Polls scripts/ai/agent_sessions.py and alerts on a change that matters: a session that was working
    // is now idle (finished), or any session now waits for the user (a question, an approval).
    property var sessionStates: ({})
    property bool sessionBaseline: false
    property var sessionAlertQueue: []
    property Timer sessionPoll: Timer {
        interval: 7000; repeat: true; triggeredOnStart: true
        running: root.orbEnabled && Config.options.ai.voice.sessionAlerts !== false
        onTriggered: if (!sessionProc.running) sessionProc.running = true
    }
    property Process sessionProc: Process {
        command: ["python3", Quickshell.shellPath("scripts/ai/agent_sessions.py"), "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try { list = JSON.parse(text); } catch (e) { return; }
                if (root.orbEnabled) root.noteSessions(list);
            }
        }
    }
    function toolLabel(tool) { return ({claude: "Claude", codex: "Codex", opencode: "OpenCode"})[tool] ?? tool; }
    function noteSessions(list) {
        const next = {};
        for (const item of list) {
            const key = item.tool + ":" + item.id;
            next[key] = item.status;
            const before = root.sessionStates[key];
            if (!root.sessionBaseline || before === undefined || before === item.status) continue;
            const name = String(item.name).slice(0, 50);
            const who = root.toolLabel(item.tool) + " \"" + name + "\"";
            if (item.status === "waiting")
                root.raiseSessionAlert("question", who + " " + (item.why || "needs you") + ".",
                    root.sessionWaitingText(item.why).arg(root.toolLabel(item.tool)).arg(name));
            else if (item.status === "idle" && before === "working")
                root.raiseSessionAlert("done", who + " finished.",
                    Translation.tr("%1 \"%2\" finished.").arg(root.toolLabel(item.tool)).arg(name));
        }
        root.sessionStates = next;
        root.sessionBaseline = true;
    }
    // `why` comes from agent_sessions.py as an English phrase.
    function sessionWaitingText(why) {
        switch (why) {
        case "asked a question": return Translation.tr("%1 \"%2\" asked a question.");
        case "has a question": return Translation.tr("%1 \"%2\" has a question.");
        case "has a plan for you to approve": return Translation.tr("%1 \"%2\" has a plan for you to approve.");
        case "needs your approval": return Translation.tr("%1 \"%2\" needs your approval.");
        default: return Translation.tr("%1 \"%2\" needs you.");
        }
    }
    // `text` stays English for the voice; `body` is what the popup shows. The icons are Material Symbols.
    function raiseSessionAlert(kind, text, body) {
        console.log("[voice] session alert:", text);
        Quickshell.execDetached(["notify-send", "-a", Translation.tr("Coding sessions"),
                                 "-i", kind === "done" ? "check_circle" : "contact_support",
                                 kind === "done" ? Translation.tr("Session finished") : Translation.tr("Session needs you"), body]);
        root.sessionAlertQueue = root.sessionAlertQueue.concat([text]).slice(-4);
        sessionSpeakTimer.restart();
    }
    // Wait for the orb to be free (and group alerts that arrive together), then say them.
    property Timer sessionSpeakTimer: Timer {
        interval: 1500; repeat: true
        onTriggered: {
            if (root.sessionAlertQueue.length === 0) { running = false; return; }
            if (root.active || Ai.speechService.speaking) return;
            const lines = root.sessionAlertQueue;
            root.sessionAlertQueue = [];
            running = false;
            if (Config.options.ai.voice.sessionAlertsSpeak === false)
                Quickshell.execDetached(["pw-play", "--volume", "0.5", root.chimeFile]);
            else
                Ai.speechService.speak(lines.join(" "), "session-alert");
        }
    }

    function stop() {
        root.abortAgentTurn();
        if (root.typed && root.fastSessionId === Ai.sessions.currentId && !Ai.draft)
            Ai.draft = root.fastText;
        if (root.fastId.length > 0)
            root.releaseQuickTurn();
        root.typed = false;
        root.active = false;
        root.oneShot = false;
        root.holdHeld = false;
        root.captureReady = false;
        root.pendingAsk = "";
        listenTimer.stop();
        chimeTimer.stop();
        if (capture.running) capture.signal(15);
        if (Ai.voiceService.activeSurface === "orb") Ai.voiceService.cancel();
        const stopFullRun = root.submissionId.length > 0 || root.runId.length > 0;
        root.submissionId = "";
        root.runId = "";
        if (stopFullRun) Ai.stopGeneration();
        if (Ai.speechService.messageId.indexOf("orb:") === 0) Ai.speechService.stop();
        root.phase = "idle";
        root.level = 0;
    }
    function toggle() {
        if (root.holdHeld) {
            root.stop();
            return;
        }
        if (AiCompanionUi.approval !== null && root.phase !== "listening") {
            // Answer the approval by voice: tap, then say yes or no. The conversation is one
            // chat orbit button away.
            if (Ai.speechService.speaking) Ai.speechService.stop();
            root.phase = "starting";
            listenTimer.restart();
        } else if (root.state === "attention") {
            Ai.surfaceRouter.open({surface: "sidebar", focusIntent: "composer"});
        } else if (root.phase === "listening") {
            capture.signal(10); // finish this utterance, then send it
        } else if (root.phase === "speaking" || root.phase === "preparing") {
            root.stop();
            root.start();
        } else if (root.active) {
            root.stop();
        } else {
            root.start();
        }
    }
    function beginListening() {
        if (!root.active || GlobalStates.screenLocked || (root.oneShot && !root.holdHeld)) return;
        if (!Ai.voiceService.detectionSettled) {
            if (++root.detectionAttempts > 30) {
                root.fail("Microphone detection timed out.");
                return;
            }
            listenTimer.restart();
            return;
        }
        if (!Ai.voiceService.available) {
            root.fail(Ai.voiceService.unavailableReason());
            return;
        }
        if (Ai.speechService.speaking || (root.oneShot && wake.running)) { listenTimer.restart(); return; }
        if (capture.running || DictationService.recording || Ai.voiceService.state !== "idle") {
            root.fail("Another dictation is active. Finish it before speaking to the orb.");
            return;
        }
        root.resetTimings();
        root.sttSettings = Ai.voiceService.orbTranscriptionSettings();
        root.phase = "listening";
        root.captureReady = false;
        root.level = 0;
        root.listenStarted = Date.now();
        root.recordingPath = Ai.voiceService.voiceDir + "/orb-" + Date.now() + ".wav";
        capture.command = ["env",
            "II_ORB_PUSH_TO_TALK=" + (root.oneShot ? "1" : "0"),
            "II_ORB_END_SILENCE=" + String(Config.options.ai.voice.endSilence ?? 0.6),
            "II_ORB_VAD=" + ((Config.options.ai.voice.vad ?? true) ? "1" : "0"),
            ...Ai.voiceService.transcriptionEnvironment(root.sttSettings),
            "python3", Directories.scriptPath + "/ai/orb_audio.py", "capture", root.recordingPath];
        capture.running = true;
    }
    // A bare "stop", "stop listening", "never mind", "be quiet"… ends the session. The whole utterance
    // must be the phrase, so "stop the music" and "don't stop believing" still go to the assistant.
    readonly property var stopPhrase: new RegExp("^\\s*(?:(?:ok|okay|hey|please|orb|borb|just|alright)[ ,]+)*"
        + "(?:stop(?: it| that| now| talking| listening| speaking| please| everything)*|cancel(?: that| it| this)?"
        + "|never ?mind|forget it|be quiet|quiet|shut up|silence|that'?s enough|enough|go away|go to sleep|that'?s all|nothing"
        + "|اسكت|توقف|كفى|الغ[ِيى]?|خلاص)"
        + "(?:[ ,]+(?:please|now|orb|borb|thanks|thank you))*\\s*[.!?]*\\s*$", "i")
    // What was said, however it was transcribed.
    function heard(text) {
        if (!text.length) {
            if (AiCompanionUi.approval !== null) root.phase = "idle";
            else root.stop();
            return;
        }
        if (AiCompanionUi.approval === null && root.stopPhrase.test(text)) {
            console.log("[voice] stopped by voice");
            root.stop();
            if (Config.options.ai.voice.chime !== false)
                Quickshell.execDetached(["pw-play", "--volume", "0.5", "/usr/share/sounds/freedesktop/stereo/service-logout.oga"]);
            return;
        }
        root.ask(text);
    }
    // After the wake chime the mic waits for it to finish, so the chime is not transcribed.
    property bool wakeChimed: false
    Timer { id: listenTimer; interval: root.wakeChimed ? 450 : 120; onTriggered: { root.wakeChimed = false; root.beginListening(); } }
    Process {
        id: capture
        stdout: SplitParser {
            onRead: line => {
                let event;
                try { event = JSON.parse(line); } catch (e) { return; }
                if (!root.active) return;
                if (event.event === "recording") root.captureReady = true;
                else if (event.event === "level") root.level = event.level;
                else if (event.event === "captured") {
                    root.captureEndedAt = Number(event.endedAt) || Date.now();
                    root.timings = Object.assign({}, root.timings, {captureMs: root.captureEndedAt - root.listenStarted});
                    root.level = 0;
                    if (event.text !== undefined) {
                        // Transcribed while the pause was still being waited out (orb_audio.py), and
                        // the audio already removed: no second transcription.
                        root.timings = Object.assign({}, root.timings, {transcriptionMs: 0});
                        root.heard(String(event.text).trim());
                        return;
                    }
                    root.phase = "transcribing";
                    root.transcriptionStarted = Date.now();
                    if (!Ai.voiceService.transcribeFile(event.path, "orb", root.sttSettings))
                        root.fail("Could not start transcription.");
                } else if (event.event === "no-speech") {
                    // Nobody answered the approval: leave the card up and the run waiting
                    // instead of cancelling it. Tap the card, or the orb to speak.
                    if (AiCompanionUi.approval !== null) root.phase = "idle";
                    else root.stop();
                }
                else if (event.event === "error") root.fail(event.message);
            }
        }
        onExited: code => {
            root.captureReady = false;
            if (root.active && root.phase === "listening")
                root.fail("The microphone stopped. Check your input device.");
        }
    }
    Connections {
        target: Ai.voiceService
        function onStateChanged() {
            if (Ai.voiceService.activeSurface !== "orb" || !root.active) return;
            if (Ai.voiceService.state === "error") { root.fail(Ai.voiceService.errorText); return; }
            if (Ai.voiceService.state !== "review") return;
            root.timings = Object.assign({}, root.timings, {transcriptionMs: Date.now()-root.transcriptionStarted});
            root.transcriptionStarted = 0;
            const text = Ai.voiceService.draftText.trim();
            Ai.voiceService.attachDraft("");
            root.heard(text);
        }
    }
    Connections {
        target: Ai
        function onAttachmentWorkPendingChanged() {
            // Probe completion can queue extraction in the same event. Wait
            // until those mutations settle before deciding the files are ready.
            Qt.callLater(() => {
                if (Ai.attachmentWorkPending || !root.active || !root.pendingAsk.length) return;
                const text = root.pendingAsk;
                root.pendingAsk = "";
                if (Ai.attachments.length === 0 && Ai.attachmentNotice.length > 0)
                    root.fail(Ai.attachmentNotice);
                else root.ask(text);
            });
        }
        function onSubmissionStarted(id, run, session) {
            if (id !== root.submissionId || !root.active) return;
            root.submissionId = "";
            root.runId = run;
        }
        function onSubmissionFailed(id, operation, error, recovery) {
            if (id === root.submissionId) root.fail("Voice request failed: " + error);
        }
        function onSubmissionCancelled(id, reason) {
            if (id !== root.submissionId) return;
            root.submissionId = "";
            root.stop();
        }
        function onResponseFinished(result) {
            if (!root.active || String(result.runId) !== root.runId) return;
            const message = Ai.messageByID[String(result.responseMessageId)];
            root.runId = "";
            if (result.state !== "completed" || !message?.content) {
                if (root.agentStreaming) { root.agentStreaming = false; Ai.speechService.stop(); }
                root.fail(message?.errorText ?? "The assistant could not answer. Open the sidebar for details.");
                return;
            }
            root.timings = Object.assign({}, root.timings, {generationMs: Date.now()-root.generationStarted});
            if (root.agentStreaming && Ai.speechService.streamOpen) {
                // Already speaking: say the rest of the reply and close the stream.
                if (String(message.content).length < root.fastSent) root.fastSent = 0;
                root.fastBuffer = String(message.content);
                root.drainSpeech(true);
                root.agentStreaming = false;
                if (Ai.speechService.streamOpen) Ai.speechService.endStream();
                if (root.firstAudioAt > 0) root.logTurn();
                return;
            }
            root.agentStreaming = false;
            root.phase = "preparing";
            root.speechRequested = Date.now();
            Ai.speechService.speak(String(message.content), "orb:" + result.responseMessageId);
        }
    }
    Connections {
        target: Ai.runCoordinator
        function onRunFinished(run) {
            if (String(run.runId) !== root.runId || !root.active) return;
            if (run.state === "cancelled" || run.state === "interrupted") {
                root.runId = "";
                root.stop();
            }
        }
    }
    Connections {
        target: Ai.speechService
        function onPhaseChanged() {
            if (root.active && Ai.speechService.messageId.startsWith("orb:")
                    && Ai.speechService.phase === "speaking" && root.speechRequested > 0) {
                root.firstAudioAt = Date.now();
                root.timings = Object.assign({}, root.timings, {speechStartMs: root.firstAudioAt - root.speechRequested});
                root.speechRequested = 0;
                if (root.fastId.length === 0 && root.runId.length === 0)
                    root.logTurn();
            }
            if (root.active && Ai.speechService.messageId.indexOf("orb:") === 0)
                root.phase = Ai.speechService.phase || root.phase;
        }
        function onLevelChanged() {
            if (Ai.speechService.messageId.indexOf("orb:") === 0) root.level = Ai.speechService.level;
        }
        function onFinished(ok) {
            if (!root.active || (root.phase !== "speaking" && root.phase !== "preparing")) return;
            if (!ok) { root.logTurn("speech-error"); root.fail(Ai.speechService.errorText); }
            else root.finishSpokenTurn();
        }
    }
    Connections {
        target: AiCompanionUi
        function onApprovalChanged() { if (root.active) root.announceApproval(); }
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() { if (GlobalStates.screenLocked) root.stop(); }
    }
    // The orb's helper daemons (warm Kokoro voice, private ydotoold) are started by the shell, not by
    // systemd. The script only starts what is not running, so this also revives a crashed one.
    // The Kokoro model is ~440 MiB of resident and swapped memory, so it is held only while the orb
    // can be heard: a hidden orb stops it after a grace period instead of paying for it all day.
    readonly property bool voiceWanted: (root.orbEnabled && AiCompanionUi.saved.visible) || root.active || Ai.speechService.speaking
    Timer {
        interval: 60000; repeat: true; triggeredOnStart: true
        running: root.voiceWanted
        onTriggered: Quickshell.execDetached([Directories.scriptPath + "/ai/ensure_daemons.sh"])
    }
    // Hiding the orb does not throw the model away at once: a short grace period covers a quick
    // hide-and-show, and speech in progress keeps voiceWanted true so nothing is cut off.
    Timer {
        interval: 90000
        running: !root.voiceWanted
        onTriggered: Quickshell.execDetached([Directories.scriptPath + "/ai/ensure_daemons.sh", "stop-voice"])
    }
    // ── Wake word ────────────────────────────────────────────────────────────────
    // The detector owns the microphone only while the orb is idle; a session, the lock screen,
    // or the dictation key stops it so one thing owns the microphone at a time. A hidden orb
    // stops it too: closed means the microphone is off, not silently listening.
    readonly property bool wakeWanted: root.orbEnabled && (Config.options.ai.voice.wakeWord ?? false)
        && !root.active && root.phase === "idle" && !GlobalStates.screenLocked
        && !Ai.speechService.speaking && Ai.voiceService.state === "idle"
        && !DictationService.recording
        && AiCompanionUi.saved.visible
    property string wakeError: ""
    onWakeWantedChanged: {
        if (root.wakeWanted) wakeRestart.restart();
        else { wakeRestart.stop(); wakeRetry.stop(); if (wake.running) wake.signal(15); }
    }
    Component.onCompleted: {
        root.metricsCommand("scrub");
        if (root.wakeWanted) wakeRestart.restart();
    }
    // The detector reads its word and threshold once at start, so a settings change restarts it.
    Connections {
        target: Config.options.ai.voice
        function onWakeWordModelChanged() { root.wakeReload(); }
        function onWakeWordThresholdChanged() { root.wakeReload(); }
    }
    // Set while the detector is being restarted on purpose, so its exit brings it straight back instead of
    // waiting out the 15 s crash-loop guard.
    property bool wakeReloading: false
    function wakeReload() {
        if (wake.running) { root.wakeReloading = true; wake.signal(15); }
        else if (root.wakeWanted) wakeRestart.restart();
    }
    Timer {
        id: wakeRestart
        interval: 600   // lets the previous capture release the mic before the detector takes it
        onTriggered: if (root.wakeWanted && !wake.running) wake.running = true
    }
    Timer { id: wakeRetry; interval: 15000; onTriggered: if (root.wakeWanted && !wake.running) wake.running = true }
    Process {
        id: wake
        command: ["env",
            "II_WAKE_WORD=" + String(Config.options.ai.voice.wakeWordModel ?? "hey_jarvis"),
            "II_WAKE_THRESHOLD=" + String(Config.options.ai.voice.wakeWordThreshold ?? 0.5),
            "OMP_NUM_THREADS=1",
            "nice", "-n", "5",
            "python3", Directories.scriptPath + "/ai/wake_word.py"]
        stdout: SplitParser {
            onRead: line => {
                let event;
                try { event = JSON.parse(line); } catch (e) { return; }
                if (event.event === "ready") root.wakeError = "";
                else if (event.event === "error") root.wakeError = String(event.message);
                else if (event.event === "wake" && root.wakeWanted) {
                    wake.signal(15);
                    root.wakeCount++;
                    root.setMood("startled", 1100);
                    root.start();
                    if (Config.options.ai.voice.chime !== false) {
                        root.wakeChimed = true;
                        listenTimer.restart();
                        Quickshell.execDetached(["pw-play", "--volume", "0.6", "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga"]);
                    }
                }
            }
        }
        onExited: {
            const reloading = root.wakeReloading;
            root.wakeReloading = false;
            if (root.wakeWanted) (reloading ? wakeRestart : wakeRetry).restart();
        }
    }
    Component.onDestruction: {
        if (wake.running) wake.signal(15);
        if (capture.running) capture.signal(15);
        if (Ai.voiceService.activeSurface === "orb") Ai.voiceService.cancel();
        if (Ai.speechService.messageId.indexOf("orb:") === 0) Ai.speechService.stop();
    }
}
