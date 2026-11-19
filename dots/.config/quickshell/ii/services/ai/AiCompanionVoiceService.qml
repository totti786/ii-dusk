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
    property string early: ""
    property string turnText: ""
    // One line per spoken turn, so slowness can be traced to a stage and a route instead of guessed at:
    // ~/.local/state/quickshell/user/ai/voice-timings.jsonl
    // The model that served this turn, as the settings page names them.
    function routeModel() {
        if (root.route === "rule") return "rules";
        if (root.route === "haiku" || root.route === "look") return root.fastModelId();
        return root.escalationModelId() || Ai.currentModelId;
    }
    function logTurn() {
        const t = root.timings;
        const line = JSON.stringify({at: new Date().toISOString(), route: root.route, early: root.early, model: root.routeModel(), text: root.turnText.slice(0, 80),
            captureMs: t.captureMs ?? null, transcriptionMs: t.transcriptionMs ?? null, generationMs: t.generationMs ?? null,
            speechStartMs: t.speechStartMs ?? null,
            afterSpeechEndMs: (t.transcriptionMs ?? 0) + (t.generationMs ?? 0) + (t.speechStartMs ?? 0)});
        Quickshell.execDetached(["bash", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s\\n" "$2" >> "$1"', "_",
            FileUtils.trimFileProtocol(Directories.state) + "/user/ai/voice-timings.jsonl", line]);
    }
    readonly property string state: root.active && root.runId.length > 0
        && (Ai.runCoordinator.runFor(root.runId)?.state === "needsAction" || AiCompanionUi.approval !== null)
        ? "attention" : root.phase

    // ── Personality: a short-lived mood the creature wears ───────────────────────
    property string mood: ""
    function setMood(name, ms) {
        root.mood = name;
        moodTimer.interval = ms;
        moodTimer.restart();
    }
    Timer { id: moodTimer; onTriggered: root.mood = "" }
    AiCompanionActions { id: actions }

    function fail(message) {
        root.active = false;
        root.pendingAsk = "";
        root.phase = "error";
        root.level = 0;
        root.errorText = String(message);
        if (Ai.voiceService.activeSurface === "orb") Ai.voiceService.cancel();
        if (capture.running) capture.signal(15);
        root.submissionId = "";
        root.runId = "";
    }
    function start() {
        if (GlobalStates.screenLocked) return;
        if (Ai.isGenerating && root.runId.length === 0) {
            root.fail("The assistant is already working. Open the sidebar to see its progress.");
            return;
        }
        root.active = true;
        root.phase = "starting";
        root.timings = ({});
        root.transcriptionStarted = 0;
        if (root.quickReady) root.sendAgent({op: "warm"});
        if (Ai.speechService.speaking) Ai.speechService.stop();
        root.errorText = "";
        root.detectionAttempts = 0;
        Ai.voiceService.ensureDetected();
        listenTimer.restart();
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
            listenTimer.restart();
            return;
        }
        const wantsFast = root.agentUseful && Ai.attachmentWorkPending === false
            && Ai.attachments.length === 0 && !Ai.isGenerating;
        if (wantsFast) {
            root.fastAsk(String(text));
            return;
        }
        root.askFull(text);
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
    function askFull(text) {
        if (Ai.attachmentWorkPending) {
            root.active = true;
            root.pendingAsk = String(text);
            root.phase = "reading-files";
            return;
        }
        root.pendingAsk = "";
        root.route = "agent";
        root.turnText = String(text);
        if (Ai.isGenerating) { root.fail("The assistant is already working."); return; }
        root.active = true;
        root.errorText = "";
        root.phase = "thinking";
        root.generationStarted = Date.now();
        const result = Ai.submit(String(text), {
            modelId: root.escalationModelId(),
            attachments: Ai.attachments,
            systemPrompt: Ai.systemPrompt + "\nThis turn is a spoken conversation through the desktop voice orb. Give a natural spoken answer, usually one to three short sentences. Avoid markdown, long lists and code unless explicitly requested. Keep the existing tool and approval rules."
        }, "voice-orb");
        if (!result.accepted) { root.fail("Could not send your voice message. Open the sidebar for details."); return; }
        root.submissionId = String(result.submissionId ?? "");
    }
    // ── Fast path: a warm Claude session, spoken a sentence at a time ───────────
    property string fastId: ""
    property string fastText: ""
    property string fastBuffer: ""
    property int fastSent: 0
    property bool fastWhole: false
    property var fastNotes: []
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
    readonly property bool quickReady: Config.options.ai.voice.fastPath === true && Ai.onlineAllowed
        && root.claudeState !== "missing" && root.claudeState !== "signedOut"
    // Whether anything in the agent can still help: the instant rules need no model at all.
    readonly property bool agentUseful: root.quickReady || Config.options.ai.voice.rules !== false
    Connections {
        target: Ai
        // Switching remote AI off ends the warm Claude session and drops any turn it was answering.
        function onOnlineAllowedChanged() {
            if (Ai.onlineAllowed) return;
            if (root.fastId.length > 0) root.fastFallback("remote AI turned off");
            root.sendAgent({op: "reset"});
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
    readonly property string rulesConfig: JSON.stringify({op: "config",
        rulesOff: Array.from(Config.options.ai.voice.rulesOff ?? []),
        custom: Array.from(Config.options.ai.voice.customRules ?? [])})
    onRulesConfigChanged: if (voiceAgent.running && root.agentReady) voiceAgent.write(root.rulesConfig + "\n")
    function sendAgent(message) {
        if (voiceAgent.running && root.agentReady) {
            voiceAgent.write(JSON.stringify(message) + "\n");
            return;
        }
        root.agentQueue = root.agentQueue.concat([message]);
        if (!voiceAgent.running) voiceAgent.running = true;
    }
    /** Whether a typed message should take the same route as speech. */
    function canRouteTyped(text) {
        const settings = Config.options.ai.voice;
        return settings.typedRouting !== false && root.agentUseful && Ai.enabled
            && !root.active && root.fastId.length === 0 && !root.typed
            && Ai.attachments.length === 0 && !Ai.attachmentWorkPending && !Ai.isGenerating
            && String(text ?? "").trim().length > 0 && String(text).trim().length < 2000
            && !/^[\/!]/.test(String(text).trim());
    }
    function typedAsk(text) {
        root.typed = true;
        root.fastAsk(String(text));
        Ai.clearDraftIfCurrent();
        return {accepted: true, state: "pending", routed: "quick"};
    }
    /** The typed turn is over: put it in the chat, with what was done, and let the orb rest. */
    function typedFinish(question, answer, notes, rule) {
        const done = notes.length > 0 ? "(" + notes.join("; ") + ")" : "";
        const reply = done.length > 0 && answer.length > 0 ? done + "\n\n" + answer : done + answer;
        root.typed = false;
        root.fastId = "";
        root.fastNotes = [];
        if (root.mood === "curious") root.mood = "";
        root.phase = "idle";
        if (reply.trim().length > 0) {
            Ai.addMessage(question, "user");
            Ai.addMessage(reply, "assistant", {"model": rule ? "rules" : root.fastModelId()});
            Ai.sessions.scheduleSave();
        }
        root.timings = Object.assign({}, root.timings, {generationMs: Date.now() - root.generationStarted});
        if (rule) root.route = "rule";
        root.logTurn();
    }
    function fastAsk(text) {
        root.route = "haiku";
        root.turnText = text;
        root.pendingAsk = "";
        if (!root.typed) root.active = true;
        root.errorText = "";
        root.phase = "thinking";
        root.generationStarted = Date.now();
        root.fastId = "v" + Date.now();
        root.fastText = text;
        root.fastBuffer = "";
        root.fastSent = 0;
        root.fastWhole = false;
        root.fastNotes = [];
        root.sendAgent({op: "ask", id: root.fastId, text: text, context: actions.snapshot(), quick: root.quickReady,
                        via: root.typed ? "typed" : "spoken",
                        screen: root.quickReady && Config.options.ai.voice.screen === true});
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
        if (root.typed) {
            root.typedFinish(root.fastText, String(event.text ?? "").trim(), root.fastNotes, !!event.rule);
            return;
        }
        const chime = root.chimeAllowed(event);
        // A rule hit carries its confirmation in `text` only; speak it unless chiming instead.
        if (event.rule && !chime) root.fastBuffer = String(event.text ?? "");
        root.drainSpeech(true);
        if (event.rule) root.route = "rule";
        else if (root.mood === "curious") root.route = "look";
        root.timings = Object.assign({}, root.timings, {
            generationMs: Date.now() - root.generationStarted, firstTokenMs: event.firstTokenMs ?? 0});
        const answer = String(event.text ?? "").trim();
        const notes = root.fastNotes;
        root.fastId = "";
        root.fastNotes = [];
        if (root.mood === "curious") root.mood = "";
        if (answer.length > 0 || notes.length > 0) {
            // The exchange belongs in the chat the sidebar shows, and in what the full
            // agent reads as history on the next tool turn, including what was done.
            const done = notes.length > 0 ? "(" + notes.join("; ") + ")" : "";
            Ai.addMessage(root.fastText, "user");
            Ai.addMessage(done.length > 0 && answer.length > 0 ? done + "\n\n" + answer : done + answer,
                          "assistant", {"model": root.fastModelId()});
            Ai.sessions.scheduleSave();
        }
        if (chime) {
            Quickshell.execDetached(["pw-play", "--volume", "0.5", root.chimeFile]);
            root.timings = Object.assign({}, root.timings, {speechStartMs: 0});
            root.logTurn();
            root.phase = "idle";
            root.level = 0;
            // Listen again once the chime is over, so the microphone does not hear it.
            if (AiCompanionUi.approval === null) chimeTimer.restart();
            return;
        }
        if (Ai.speechService.streamOpen) Ai.speechService.endStream();
        else if (answer.length === 0) root.stop();
    }
    // The model that really answered, as the catalog names it, so the chat does not
    // label a warm Haiku reply with whichever model is selected for the full agent.
    function fastModelId() {
        const alias = String(Config.options.ai.voice.fastModel);
        const key = Object.keys(Ai.models).find(id => id.indexOf("claude") === 0 && id.endsWith(":" + alias));
        return key ?? ("claude:" + alias);
    }
    // A marker the shell could not carry out. Nothing was spoken yet, so the full agent
    // can take the turn; if something already ran, say so instead of redoing it.
    function fastAction(event) {
        const result = actions.run(event.verb, event.args);
        if (result.ok) {
            root.fastNotes = root.fastNotes.concat([result.note]);
            root.setMood("delighted", 2200);
            return;
        }
        console.log("[voice] action refused:", event.verb, result.note);
        root.sendAgent({op: "cancel"});
        if (root.fastNotes.length === 0) { root.fastFallback("action: " + result.note); return; }
        const done = root.fastNotes.join(", ");
        if (root.typed) {
            root.typedFinish(root.fastText, Translation.tr("%1, but the rest didn't work.").arg(done), [], false);
            return;
        }
        root.fastId = "";
        root.fastNotes = [];
        if (Ai.speechService.streamOpen) Ai.speechService.stop();
        Ai.speechService.speak(Translation.tr("%1, but the rest didn't work.").arg(done), "orb:action-" + Date.now());
        root.phase = "preparing";
    }
    function fastFallback(reason) {
        // The agent says so when the CLI vanished after the check: stop offering the stage.
        if (/not installed/i.test(String(reason))) root.claudeState = "missing";
        else if (/log ?in|sign ?in|authenticat|api key|credentials|unauthori[sz]ed|oauth/i.test(String(reason))) root.claudeState = "signedOut";
        const text = root.fastText;
        const typed = root.typed;
        root.fastId = "";
        root.fastNotes = [];
        root.typed = false;
        if (typed) {
            // The ordinary chat turn, on the desktop-tasks model, as a spoken request would get.
            console.log("[voice] typed turn handed over:", reason);
            root.route = "agent";
            root.phase = "idle";
            const result = Ai.submit(text, {modelId: root.escalationModelId(), attachments: Ai.attachments}, "chat");
            if (!result.accepted) console.log("[voice] typed handover rejected:", result.errorCode);
            return;
        }
        if (Ai.speechService.streamOpen) Ai.speechService.stop();
        console.log("[voice] fast path handed over:", reason);
        root.askFull(text);
    }
    Process {
        id: voiceAgent
        command: ["env", "II_VOICE_MODEL=" + Config.options.ai.voice.fastModel,
                  "II_VOICE_SCREEN=" + (Config.options.ai.voice.screen === true ? "1" : "0"),
                  "II_VOICE_RULES=" + (Config.options.ai.voice.rules === false ? "0" : "1"),
                  "II_VOICE_LANGUAGE=" + String(Config.options.ai.voice.language ?? "en"),
                  "python3", Directories.scriptPath + "/ai/voice_agent.py"]
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
                if (event.id !== root.fastId || root.fastId.length === 0) return;
                if (event.event === "delta") {
                    root.fastBuffer += String(event.text);
                    root.drainSpeech(false);
                } else if (event.event === "done") root.fastDone(event);
                else if (event.event === "action") root.fastAction(event);
                else if (event.event === "looking") root.setMood("curious", 15000);
                else if (event.event === "escalate") root.fastFallback("needs the desktop");
                else if (event.event === "error") root.fastFallback(event.message);
            }
        }
        onExited: {
            root.agentReady = false;
            if (root.fastId.length > 0) root.fastFallback("the voice agent exited");
        }
    }

    function stop() {
        root.typed = false;
        if (root.fastId.length > 0) {
            root.sendAgent({op: "cancel"});
            root.fastId = "";
            Ai.speechService.stop();
        }
        root.active = false;
        root.pendingAsk = "";
        listenTimer.stop();
        if (capture.running) capture.signal(15);
        if (Ai.voiceService.activeSurface === "orb") Ai.voiceService.cancel();
        if (root.submissionId.length > 0 || root.runId.length > 0) Ai.stopGeneration();
        if (Ai.speechService.messageId.indexOf("orb:") === 0) Ai.speechService.stop();
        root.submissionId = "";
        root.runId = "";
        root.phase = "idle";
        root.level = 0;
    }
    function toggle() {
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
            // Mark the handoff first: the cancelled player's finished(false)
            // must not turn an intentional interruption into an error.
            root.phase = "starting";
            Ai.speechService.stop();
            root.active = true;
            listenTimer.restart();
        } else if (root.active) {
            root.stop();
        } else {
            root.start();
        }
    }
    function beginListening() {
        if (!root.active || GlobalStates.screenLocked) return;
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
        if (Ai.speechService.speaking) { listenTimer.restart(); return; }
        if (Ai.voiceService.state !== "idle") {
            root.fail("Another dictation is active. Finish it before speaking to the orb.");
            return;
        }
        root.phase = "listening";
        root.level = 0;
        root.listenStarted = Date.now();
        root.recordingPath = Ai.voiceService.voiceDir + "/orb-" + Date.now() + ".wav";
        capture.command = ["env",
            "II_ORB_END_SILENCE=" + String(Config.options.ai.voice.endSilence ?? 0.6),
            "II_ORB_VAD=" + ((Config.options.ai.voice.vad ?? true) ? "1" : "0"),
            "II_ORB_LANGUAGE=" + String(Config.options.ai.voice.language ?? "en"),
            "II_ORB_STT_MODEL=" + String(Config.options.ai.voice.sttModel ?? "auto"),
            "python3", Directories.scriptPath + "/ai/orb_audio.py", "capture", root.recordingPath];
        capture.running = true;
    }
    // What was said, however it was transcribed.
    function heard(text) {
        if (!text.length) {
            if (AiCompanionUi.approval !== null) root.phase = "idle";
            else root.stop();
            return;
        }
        root.ask(text);
    }
    Timer { id: listenTimer; interval: 120; onTriggered: root.beginListening() }
    Process {
        id: capture
        stdout: SplitParser {
            onRead: line => {
                let event;
                try { event = JSON.parse(line); } catch (e) { return; }
                if (!root.active) return;
                if (event.event === "level") root.level = event.level;
                else if (event.event === "captured") {
                    root.timings = Object.assign({}, root.timings, {captureMs: Date.now() - root.listenStarted});
                    root.level = 0;
                    if (event.text !== undefined) {
                        // Transcribed while the pause was still being waited out (orb_audio.py), and
                        // the audio already removed: no second transcription.
                        root.early = String(event.early ?? "reuse");
                        root.timings = Object.assign({}, root.timings, {transcriptionMs: 0});
                        root.heard(String(event.text).trim());
                        return;
                    }
                    root.early = "none";
                    root.phase = "transcribing";
                    root.transcriptionStarted = Date.now();
                    if (!Ai.voiceService.transcribeFile(event.path, "orb"))
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
                root.fail(message?.errorText ?? "The assistant could not answer. Open the sidebar for details.");
                return;
            }
            root.phase = "preparing";
            root.timings = Object.assign({}, root.timings, {generationMs: Date.now()-root.generationStarted});
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
            if (root.active && Ai.speechService.phase === "speaking" && root.speechRequested > 0) {
                root.timings = Object.assign({}, root.timings, {speechStartMs: Date.now()-root.speechRequested});
                root.speechRequested = 0;
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
            if (!ok) root.fail(Ai.speechService.errorText);
            else {
                root.phase = "idle";
                root.level = 0;
                // Not after an approval prompt: the open microphone would hear the orb's own
                // "yes or no" and answer for you. The card has buttons; tap the orb to speak.
                if (AiCompanionUi.approval === null) listenTimer.restart();
            }
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
    Component.onDestruction: {
        if (capture.running) capture.signal(15);
        if (Ai.voiceService.activeSurface === "orb") Ai.voiceService.cancel();
        if (Ai.speechService.messageId.indexOf("orb:") === 0) Ai.speechService.stop();
    }
}
