pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.ii.qanun

/**
 * Owns the audio-to-score job. The Python helper emits one JSON line per stage,
 * so the page can show stem focus, pitch tracking and engraving as they happen.
 * The process survives leaving the Convert page; its result is kept in memory
 * until another conversion starts.
 */
Singleton {
    id: root

    readonly property string scriptPath: Quickshell.shellPath("scripts/qanun/transcribe.py")
    readonly property string outputDir: QanunStore.scoresDir + "/Conversions"

    property bool running: false
    property string stage: "idle"
    property string message: ""
    property string error: ""
    property string source: ""
    property string title: ""
    property real bpm: 100
    property var stageStates: ({ input: "pending", separate: "pending", transcribe: "pending", engrave: "pending" })
    property var result: null

    signal finished(var result)
    signal failed(string message)

    function reset(): void {
        if (root.running)
            return;
        root.stage = "idle";
        root.message = "";
        root.error = "";
        root.result = null;
        root.source = "";
        root.title = "";
        root.stageStates = ({ input: "pending", separate: "pending", transcribe: "pending", engrave: "pending" });
    }

    function localPath(path): string {
        let value = String(path ?? "");
        if (value.startsWith("file://"))
            value = decodeURIComponent(value.slice(7));
        return value;
    }

    function startFile(path, optionalTitle, tempo): void {
        const file = root.localPath(path);
        if (file.length === 0) {
            root.error = Translation.tr("Choose an audio file first.");
            return;
        }
        root._start(file, "", optionalTitle, tempo);
    }

    function startUrl(url, optionalTitle, tempo): void {
        const link = String(url ?? "").trim();
        if (!link.startsWith("http://") && !link.startsWith("https://")) {
            root.error = Translation.tr("Paste a valid http(s) audio or video link.");
            return;
        }
        root._start("", link, optionalTitle, tempo);
    }

    function _start(inputPath, inputUrl, optionalTitle, tempo): void {
        if (root.running)
            return;
        root.running = true;
        root.error = "";
        root.result = null;
        root.source = inputPath || inputUrl;
        root.title = String(optionalTitle ?? "").trim();
        root.bpm = Math.max(20, Math.min(320, Number(tempo) || 100));
        root.stage = "input";
        root.message = inputUrl ? Translation.tr("Downloading audio…") : Translation.tr("Reading audio…");
        root.stageStates = ({ input: "running", separate: "pending", transcribe: "pending", engrave: "pending" });
        const args = ["python3", root.scriptPath,
            "--out-dir", root.outputDir,
            "--bpm", String(root.bpm)];
        if (root.title.length > 0)
            args.push("--title", root.title);
        if (inputUrl.length > 0)
            args.push("--url", inputUrl);
        else
            args.push("--input", inputPath);
        convertProcess.command = args;
        convertProcess.running = true;
    }

    function cancel(): void {
        if (convertProcess.running)
            convertProcess.running = false;
        root.running = false;
        root.stage = "cancelled";
        root.message = Translation.tr("Conversion cancelled.");
        root.stageStates = ({ input: "cancelled", separate: "cancelled", transcribe: "cancelled", engrave: "cancelled" });
    }

    function handleLine(line): void {
        const raw = String(line ?? "").trim();
        if (raw.length === 0)
            return;
        let payload = null;
        try {
            payload = JSON.parse(raw);
        } catch (error) {
            return;
        }
        if (!payload)
            return;
        if (payload.stage) {
            const itemStage = String(payload.stage);
            const status = String(payload.status ?? "running");
            const next = Object.assign({}, root.stageStates);
            next[itemStage] = status;
            root.stageStates = next;
            root.stage = itemStage;
            if (String(payload.message ?? "").length > 0)
                root.message = String(payload.message);
        }
        if (payload.ok === false) {
            root.error = String(payload.error ?? Translation.tr("The conversion failed."));
            root.running = false;
            root.stage = "error";
            root.failed(root.error);
            return;
        }
        if (payload.ok === true && payload.score) {
            root.result = payload;
            root.running = false;
            root.stage = "done";
            root.message = Translation.tr("Sheet music ready.");
            root.finished(payload);
        }
    }

    function saveToLibrary(): bool {
        if (!root.result || !root.result.score)
            return false;
        const score = JSON.parse(JSON.stringify(root.result.score));
        const composition = Object.assign({}, score, {
            id: "converted-" + Date.now().toString(36),
            title: String(score.title ?? root.title ?? Translation.tr("Converted audio")),
            created: Date.now(),
            modified: Date.now(),
            source: "Audio conversion"
        });
        QanunStore.saveComposition(composition);
        return true;
    }

    function openMusicXML(): void {
        if (root.result && root.result.musicxml)
            Quickshell.execDetached(["xdg-open", String(root.result.musicxml)]);
    }

    function openMIDI(): void {
        if (root.result && root.result.midi)
            Quickshell.execDetached(["xdg-open", String(root.result.midi)]);
    }

    function openFolder(): void {
        Quickshell.execDetached(["mkdir", "-p", root.outputDir]);
        Quickshell.execDetached(["xdg-open", root.outputDir]);
    }

    Process {
        id: convertProcess
        stdout: SplitParser {
            onRead: line => root.handleLine(line)
        }
        stderr: SplitParser {
            onRead: line => {
                const text = String(line ?? "").trim();
                if (text.length > 0)
                    root.message = text;
            }
        }
        onExited: (code, status) => {
            if (root.running) {
                root.running = false;
                if (code !== 0 && root.error.length === 0) {
                    root.error = Translation.tr("The converter stopped unexpectedly.");
                    root.stage = "error";
                    root.failed(root.error);
                }
            }
        }
    }
}
