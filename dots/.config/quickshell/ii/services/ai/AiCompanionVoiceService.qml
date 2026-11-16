pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common

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
    readonly property string state: root.active && root.runId.length > 0
        && Ai.runCoordinator.runFor(root.runId)?.state === "needsAction" ? "attention" : root.phase

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
        if (Ai.speechService.speaking) Ai.speechService.stop();
        root.errorText = "";
        root.detectionAttempts = 0;
        Ai.voiceService.ensureDetected();
        listenTimer.restart();
    }
    // Also accepts an explicit prompt from local IPC; it follows the same
    // correlated response path as a transcribed utterance.
    function ask(text) {
        if (Ai.attachmentWorkPending) {
            root.active = true;
            root.pendingAsk = String(text);
            root.phase = "reading-files";
            return;
        }
        root.pendingAsk = "";
        if (Ai.isGenerating) { root.fail("The assistant is already working."); return; }
        root.active = true;
        root.errorText = "";
        root.phase = "thinking";
        root.generationStarted = Date.now();
        const result = Ai.submit(String(text), {
            attachments: Ai.attachments,
            systemPrompt: Ai.systemPrompt + "\nThis turn is a spoken conversation through the desktop voice orb. Give a natural spoken answer, usually one to three short sentences. Avoid markdown, long lists and code unless explicitly requested. Keep the existing tool and approval rules."
        }, "voice-orb");
        if (!result.accepted) { root.fail("Could not send your voice message. Open the sidebar for details."); return; }
        root.submissionId = String(result.submissionId ?? "");
    }
    function stop() {
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
        if (root.state === "attention") {
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
        root.recordingPath = Ai.voiceService.voiceDir + "/orb-" + Date.now() + ".wav";
        capture.command = ["python3", Directories.scriptPath + "/ai/orb_audio.py", "capture", root.recordingPath];
        capture.running = true;
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
                    root.phase = "transcribing";
                    root.transcriptionStarted = Date.now();
                    root.level = 0;
                    if (!Ai.voiceService.transcribeFile(event.path, "orb"))
                        root.fail("Could not start transcription.");
                } else if (event.event === "no-speech") root.stop();
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
            if (!text.length) { root.stop(); return; }
            root.ask(text);
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
            else { root.phase = "idle"; root.level = 0; listenTimer.restart(); }
        }
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
