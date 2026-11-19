import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions

QtObject {
    id: root
    readonly property bool speaking: speaker.running || root.streamOpen || root.queue.length > 0
    // Sentence streaming: text arrives while the model is still writing, and each
    // sentence is spoken as soon as the one before it ends.
    property bool streamOpen: false
    property var queue: []
    property string messageId: ""
    property string errorText: ""
    property string pendingText: ""
    // A streamed reply runs on one helper process and one local-voice connection: sentences are
    // written to it as they arrive, so the next is already being synthesised while the last plays
    // and nothing restarts between them.
    property bool streaming: false
    property bool streamReady: false
    property bool streamEnded: false
    readonly property real speechSpeed: Math.max(0.5, Math.min(2, Number(Config.options.ai.voice.speechSpeed ?? 1.25)))
    readonly property int speechGapMs: Math.max(0, Math.min(600, Number(Config.options.ai.voice.speechGapMs ?? 130)))
    property string phase: ""
    property real level: 0
    signal finished(bool ok)

    function clean(text: string): string {
        return String(text).replace(/<think>[\s\S]*?<\/think>/g, "")
            .replace(/```[\s\S]*?```/g, " Code block omitted. ")
            .replace(/!\[[^\]]*\]\([^)]*\)/g, "")
            .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
            .replace(/[#*_`>]/g, "").trim().slice(0, 4000);
    }

    function beginStream(id: string): bool {
        if (speaker.running || root.streamOpen)
            return false;
        root.messageId = id;
        root.errorText = "";
        root.queue = [];
        root.streamOpen = true;
        root.streaming = true;
        root.streamReady = false;
        root.streamEnded = false;
        root.phase = "preparing";
        root.level = 0;
        speaker.stdinEnabled = true;
        speaker.running = true;
        return true;
    }
    function sendLine(object) {
        speaker.write(JSON.stringify(object) + "\n");
    }
    function pushText(text: string) {
        const plain = root.clean(text);
        if (!root.streamOpen || !plain.length)
            return;
        if (root.streamReady)
            root.sendLine({text: plain});
        else
            root.queue = root.queue.concat([plain]);
    }
    function endStream() {
        root.streamOpen = false;
        root.streamEnded = true;
        if (root.streamReady)
            root.sendLine({end: true});
        else if (!speaker.running && root.queue.length === 0)
            root.finish(root.errorText.length === 0);
    }
    function next() {
        if (speaker.running || root.queue.length === 0)
            return;
        root.pendingText = root.queue[0];
        root.queue = root.queue.slice(1);
        speaker.stdinEnabled = true;
        speaker.running = true;
    }
    function finish(ok: bool) {
        root.messageId = "";
        root.phase = "";
        root.level = 0;
        root.finished(ok);
    }

    function speak(text: string, id: string) {
        if (speaker.running || root.streamOpen)
            return;
        const plain = root.clean(text);
        if (!plain.length)
            return;
        root.messageId = id;
        root.errorText = "";
        root.pendingText = plain;
        root.phase = "preparing";
        root.level = 0;
        speaker.stdinEnabled = true;
        speaker.running = true;
    }

    function stop() {
        root.streamOpen = false;
        root.streamEnded = true;
        root.queue = [];
        if (!speaker.running && root.messageId.length > 0) {
            root.messageId = "";
            root.phase = "";
            root.level = 0;
        }
        if (speaker.running)
            speaker.signal(15);
    }

    property Process speaker: Process {
        id: speaker
        command: ["env", "II_LOCAL_ONLY=" + (Ai.onlineAllowed ? "0" : "1"), "python3", Directories.scriptPath + "/ai/companion_tools.py"]
            .concat(root.streaming ? ["--stream"] : [])
        stdinEnabled: true
        onStarted: {
            if (root.streaming) {
                root.sendLine({speed: root.speechSpeed, gapMs: root.speechGapMs, language: String(Config.options.ai.voice.language ?? "en")});
                for (const line of root.queue)
                    root.sendLine({text: line});
                root.queue = [];
                root.streamReady = true;
                if (root.streamEnded)
                    root.sendLine({end: true});
                return;
            }
            speaker.write(JSON.stringify({text: root.pendingText, speed: root.speechSpeed, gapMs: root.speechGapMs}) + "\n");
            speaker.stdinEnabled = false;
        }
        stdout: SplitParser {
            onRead: line => {
                try {
                    const result = JSON.parse(line);
                    if (result.event === "phase") root.phase = String(result.phase);
                    if (result.event === "level") root.level = Number(result.level);
                    if (result.isError)
                        root.errorText = String(result.text);
                } catch (e) {}
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && root.errorText.length === 0)
                root.errorText = "Speech could not play. Check the local companion voice service and audio output.";
            const ok = code === 0 && root.errorText.length === 0;
            if (root.streaming) {
                root.streaming = false;
                root.streamReady = false;
                root.streamOpen = false;
                root.queue = [];
                root.finish(ok);
                return;
            }
            if (ok && (root.queue.length > 0 || root.streamOpen)) {
                // The next sentence, or the model still writing: hold the phase.
                root.next();
                return;
            }
            root.streamOpen = false;
            root.queue = [];
            root.finish(ok);
        }
    }
}
