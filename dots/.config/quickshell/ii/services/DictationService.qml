pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions
import qs.services
import "../modules/settings/configs/dictation/voxtypeSchema.js" as VoxSchema

/**
 * Speech typed straight into whatever window has focus, through voxtype or Hex.
 *
 * Two engines sit behind the same keys, bar indicator and notch: `engine` picks Voxtype (a
 * daemon the shell owns) or Hex (its own app, which pastes the text itself and keeps its own
 * settings, see `HexSettings`;
 * the shell only starts it, sends `hex dictation start|stop|toggle|cancel` and follows the
 * state events it appends to its live log). Everything below that says voxtype is the
 * Voxtype half.
 *
 *     idle → recording → transcribing → (text typed into the focused app)
 *
 * Unlike `AiVoiceService`, which records into an editable draft the user still
 * has to send, nothing here comes back to the shell: voxtype types the finished
 * text where the cursor already is. The shell only presses the button and shows
 * what is happening — the notch and the bar indicator both read the state below.
 *
 * The daemon is owned by the shell rather than by systemd. voxtype's own unit is
 * `WantedBy=graphical-session.target`, a target plenty of Hyprland sessions never
 * reach, so enabling it there is a switch that silently does nothing at the next
 * login. A `Process` tied to `Config.options.dictation.enabled` starts with the
 * shell, dies with it, and means "off" is actually off. A voxtype.service that is
 * already running is left alone and simply used — see `externalDaemon`.
 *
 * State is read from the file the daemon rewrites on every transition
 * (`$XDG_RUNTIME_DIR/voxtype/state`), watched rather than polled, so the notch
 * reacts the moment recording starts instead of up to a second later.
 */
Singleton {
    id: root

    readonly property string runtimeDir: {
        const xdg = Quickshell.env("XDG_RUNTIME_DIR");
        if (xdg && xdg.length > 0)
            return `${xdg}/voxtype`;
        return `/run/user/1000/voxtype`;
    }
    readonly property string statePath: `${root.runtimeDir}/state`
    readonly property string configScript: FileUtils.trimFileProtocol(`${Directories.scriptPath}/dictation/voxtype_config.py`)
    /** Download bookkeeping: an in-flight marker, its log, and a failure flag. */
    readonly property string stateDir: FileUtils.trimFileProtocol(`${Directories.state}/user/dictation`)

    // ── Options ───────────────────────────────────────────────────────────
    readonly property bool enabled: Config.options?.dictation?.enabled ?? false
    /** "hex" or "voxtype". Hex falls back to Voxtype while it is not installed. */
    readonly property string engine: Config.options?.dictation?.engine ?? "hex"
    /** Minutes without use after which Hex is quit (0 keeps it running). */
    readonly property int hexIdleMinutes: Config.options?.dictation?.hexIdleMinutes ?? 10
    /** The most recording either engine does in one go. */
    readonly property int maxDurationSecs: Config.options?.dictation?.maxDurationSecs ?? 60
    /** Voxtype loads its model when a recording starts instead of holding it. */
    readonly property bool voxtypeOnDemand: Config.options?.dictation?.voxtypeOnDemand ?? true
    readonly property bool voxtypeTrayIcon: Config.options?.dictation?.voxtypeTrayIcon ?? false

    // ── Models ────────────────────────────────────────────────────────────
    /** The model Voxtype's config selects; empty until its settings are read. */
    readonly property string requiredModel: VoxtypeSettings.model
    /** Short name of what Voxtype transcribes with. */
    readonly property string modelLabel: VoxtypeSettings.engine === "whisper"
        ? `Whisper · ${root.requiredModel}` : root.requiredModel

    /**
     * Models whose download was cut short. `voxtype setup --download` skips any
     * model file that merely exists — it prints "Model ready" and returns — so a
     * half-written file would never be re-fetched and would instead fail deep
     * inside the daemon at load time. These are therefore not installed.
     */
    property var incompleteModels: []
    // A custom model given by path is Voxtype's to check, and so is everything on
    // a Voxtype too old to list its settings.
    readonly property bool modelReady: VoxtypeSettings.unsupported
        || (VoxtypeSettings.loaded && (root.requiredModel.startsWith("/")
            || root.modelInstalled(VoxtypeSettings.engine, root.requiredModel)))
    readonly property bool requiredModelIncomplete: root.incompleteModels.indexOf(root.requiredModel) !== -1

    function modelInstalled(engine: string, name: string): bool {
        return root.incompleteModels.indexOf(name) === -1
            && VoxtypeSettings.models.some(model => model.engine === engine && model.name === name && model.installed);
    }

    // ── Performance ───────────────────────────────────────────────────────
    /** How voxtype is computing right now, e.g. "CPU (AVX2)" or "GPU (Vulkan)". */
    property string backend: ""
    /** A GPU build is installed and could be switched to, but is not active. */
    property bool gpuAvailable: false
    property int cpuCount: 4
    property bool cpuCounted: false
    readonly property bool onGpu: root.backend.indexOf("GPU") === 0

    /**
     * Switches voxtype to its Vulkan build, which is a root-owned symlink swap —
     * hence pkexec, which the shell's own polkit agent answers. Worth offering
     * in the UI rather than leaving in the release notes: on an integrated Arc
     * GPU it took a five-second dictation from 45 s to under 2 s.
     */
    function enableGpu() {
        if (!root.gpuAvailable)
            return;
        gpuEnableProc.running = true;
    }

    // ── Capability ────────────────────────────────────────────────────────
    property bool installed: false
    property bool bridgeInstalled: false
    property bool binaryChecked: false
    /** A voxtype.service someone else already runs; the shell then stays out of the way. */
    property bool externalDaemon: false
    /**
     * True once the shell's settings have actually reached voxtype's config
     * file. The daemon waits for this: started against the stock config it
     * would grab Scroll Lock for its own hotkey and spawn its own on-screen
     * display, both of which this shell replaces, and the user would see a
     * flash of the wrong behaviour on the very first run before the restart
     * that fixes it.
     */
    property bool configApplied: false

    /** The Hex binary: ~/hex, or `hex` on the PATH. Empty when neither exists. */
    property string hexBin: ""
    readonly property bool hexInstalled: root.hexBin.length > 0
    /** The engine actually in use. Until the lookup has finished Hex is trusted, so a Voxtype
     *  daemon is not started and torn down again at every login. */
    readonly property string activeEngine: root.engine === "hex" && (root.hexInstalled || !root.binaryChecked) ? "hex" : "voxtype"
    readonly property bool useHex: root.activeEngine === "hex"
    readonly property bool engineReady: root.useHex ? root.hexInstalled : (root.installed && root.modelReady)
    readonly property bool available: root.enabled && root.engineReady

    /** Why dictation cannot run right now, empty when it can. */
    function unavailableReason(): string {
        if (!root.binaryChecked)
            return Translation.tr("Looking for the dictation engine…");
        if (root.useHex)
            return !root.hexInstalled ? Translation.tr("Hex was not found on this system.")
                : !root.enabled ? Translation.tr("Dictation is turned off.") : "";
        if (!root.installed)
            return Translation.tr("Voxtype is not installed.");
        if (!root.enabled)
            return Translation.tr("Dictation is turned off.");
        if (!VoxtypeSettings.loaded && !VoxtypeSettings.unsupported)
            return VoxtypeSettings.error.length > 0 ? VoxtypeSettings.error : Translation.tr("Looking for the dictation engine…");
        if (root.requiredModelIncomplete)
            return Translation.tr("The %1 speech model is still downloading.").arg(root.requiredModel);
        if (!root.modelReady)
            return Translation.tr("The %1 speech model has not been downloaded yet.").arg(root.requiredModel);
        return "";
    }

    // ── Live state ────────────────────────────────────────────────────────
    /** stopped | idle | recording | streaming | transcribing */
    property string voxState: "stopped"
    property string hexState: "stopped"
    readonly property string state: root.useHex ? root.hexState : root.voxState
    readonly property bool recording: root.state === "recording" || root.state === "streaming"
    readonly property bool transcribing: root.state === "transcribing"
    readonly property bool busy: root.recording || root.transcribing
    readonly property bool starting: !root.busy && (root.hexPending.length > 0 || pendingToggleTimer.running || hexCommandProc.starting)
    readonly property bool engaged: root.starting || root.busy
    readonly property string statusLabel: root.starting ? Translation.tr("Starting dictation…")
        : root.transcribing ? Translation.tr("Transcribing…")
        : root.recording ? Translation.tr("Listening…") : Translation.tr("Dictate")
    readonly property bool daemonUp: root.state !== "stopped"

    property real recordingStartedAt: 0
    property int elapsedMs: 0

    /** Latest mic level, 0..1, smoothed for the notch's meter. */
    property real level: 0
    /** Recent levels, oldest first — the notch draws this as a waveform. */
    property var waveform: []
    readonly property int waveformLength: 40

    signal dictationStarted
    signal dictationFinished

    onRecordingChanged: {
        if (root.recording) {
            root.recordingStartedAt = Date.now();
            root.elapsedMs = 0;
            root.dictationStarted();
            return;
        }
        root.level = 0;
        root.waveform = [];
    }

    onStateChanged: {
        if (root.state === "idle" || root.state === "stopped") {
            root.dictationFinished();
            if (root.restartWanted)
                root.requestRestart();
            // A recording was running when the engine or the feature was turned off: stop
            // Hex once the turn is done instead of leaving it resident.
            if (root.hexQuitPending && !root.busy) {
                root.hexQuitPending = false;
                root.quitHex();
            }
        }
    }

    // ── Actions ───────────────────────────────────────────────────────────
    function hexCmd(action: string): void {
        if (hexCommandProc.action.length > 0) {
            hexCommandProc.nextAction = action;
            return;
        }
        hexCommandProc.action = action;
        hexCommandProc.running = true;
    }

    Process {
        id: hexCommandProc
        property string action: ""
        property string nextAction: ""
        readonly property bool starting: action === "start" || action === "toggle"
        command: ["bash", "-c",
            'timeout 5 "$1" dictation "$2" >/dev/null 2>&1; result=$?; '
            + 'if [ "$2" = cancel ] && [ "$result" = 2 ]; then exec timeout 25 "$1" dictation stop --print >/dev/null 2>&1; fi; exit "$result"',
            "--", root.hexBin, action]
        onExited: code => {
            const completed = action;
            const queued = nextAction;
            action = queued;
            nextAction = "";
            if (code === 0) root.lastError = "";
            else root.reportError(completed === "start" || completed === "toggle"
                ? Translation.tr("Hex couldn’t start dictation. Check the microphone and Hex permissions.")
                : Translation.tr("Hex couldn’t finish the dictation command."));
            if (queued.length > 0)
                Qt.callLater(() => { if (action === queued) running = true; });
        }
    }

    function cancelPendingStart(): bool {
        if (root.hexPending.length > 0) {
            if (root.hexPending === "start")
                root.holdPressedAt = 0;
            root.hexPending = "";
            return true;
        }
        if (pendingToggleTimer.running) {
            pendingToggleTimer.stop();
            return true;
        }
        return false;
    }

    function voiceCaptureBusy(): bool {
        return Ai.companionVoice.capturing || ["pending-start", "recording"].includes(Ai.voiceService.state);
    }

    function toggle() {
        if (root.holdPressedAt > 0 || holdStopTimer.running)
            return;
        if (root.cancelPendingStart())
            return;
        if (hexCommandProc.starting) {
            root.hexCmd("cancel");
            return;
        }
        if (!root.busy && root.voiceCaptureBusy()) {
            root.reportError(Translation.tr("The AI assistant is using the microphone. Stop it to start dictation."));
            return;
        }
        if (!root.available) {
            root.complain();
            return;
        }
        if (root.useHex) {
            if (root.hexStarting)
                root.hexPending = "";
            else if (root.busy)
                root.hexCmd("toggle");
            else
                // The cached state can be seconds old (Hex may have just been quit), so a start
                // always asks Hex itself first.
                root.ensureHex("toggle");
            return;
        }
        if (!root.daemonUp) {
            // The daemon is still coming up (first toggle right after the
            // shell started, or straight after a config change restarted it).
            // Waiting for it beats dropping the keypress.
            pendingToggleTimer.restart();
            return;
        }
        recordProc.exec(["voxtype", "record", "toggle"]);
    }

    function stop() {
        if (root.cancelPendingStart())
            return;
        if (!root.busy && !hexCommandProc.starting)
            return;
        if (root.useHex) {
            root.hexCmd("stop");
            return;
        }
        recordProc.exec(["voxtype", "record", "stop"]);
    }

    /** Throws the recording away: nothing is transcribed and nothing is typed. */
    function discard() {
        if (root.cancelPendingStart())
            return;
        if (!root.recording && !hexCommandProc.starting)
            return;
        if (root.useHex) {
            root.hexCmd("cancel");
            return;
        }
        recordProc.exec(["voxtype", "record", "cancel"]);
    }

    /**
     * Stops the Hex daemon so nothing stays resident when dictation is turned off or the
     * engine changes. A recording already in flight is allowed to finish first.
     */
    property bool hexQuitPending: false
    function quitHex(): void {
        if (root.busy) {
            root.hexQuitPending = true;
            return;
        }
        if (!root.hexInstalled)
            return;
        Quickshell.execDetached([root.hexBin, "quit"]);
        root.hexState = "stopped";
    }

    /** Short label for the language in use, for the bar and the popup. */
    readonly property string languageBadge: root.useHex ? String(HexSettings.get("transcription.language") ?? "en").toUpperCase()
        : root.voxtypeLanguage === "auto"
        ? Translation.tr("AUTO")
        : root.voxtypeLanguage.split(",")[0].trim().toUpperCase()
    readonly property string voxtypeLanguage: String(VoxtypeSettings.get(`${VoxtypeSettings.engine}.language`) ?? "auto")
    /** Whether finished text only reaches the clipboard. */
    readonly property bool copiesOnly: !root.useHex && VoxtypeSettings.get("output.mode") === "clipboard"

    property double lastErrorNotifiedAt: 0
    function reportError(message: string): void {
        if (message.length === 0)
            return;
        const now = Date.now();
        if (message !== root.lastError || now - root.lastErrorNotifiedAt >= 4000) {
            root.lastErrorNotifiedAt = now;
            Quickshell.execDetached(["notify-send", Translation.tr("Dictation"), message, "-a", "Shell", "-i", "mic"]);
        }
        root.lastError = message;
    }

    function complain() { root.reportError(root.unavailableReason()); }

    function redetect() {
        root.binaryChecked = false;
        binaryCheckProc.running = true;
        modelListProc.running = true;
        VoxtypeSettings.refresh();
        externalDaemonProc.running = true;
        backendCheckProc.running = true;
    }

    /** True while the shell itself is rewriting voxtype's config. */
    readonly property bool configWriting: configProc.running

    /**
     * Writes the keys the shell depends on into voxtype's config file: the
     * compositor owns the hotkey, the shell draws the indicator and reads the
     * state file, and the recording cap is shared with Hex. Everything else is
     * voxtype's, edited through `VoxtypeSettings`.
     *
     * The first time, the choices the shell used to keep itself are written too,
     * which also gives a new install pasting, a language and a punctuation sample.
     */
    function applySettings() {
        if (!root.installed)
            return;
        const options = Config.options.dictation;
        // One writer at a time, and the first write needs the core count.
        if (configProc.running || VoxtypeSettings.writing || (!options.voxtypeSeeded && !root.cpuCounted)) {
            applyTimer.restart();
            return;
        }
        const pairs = ["state_file=auto", "hotkey.enabled=false", "osd.enabled=false",
            `audio.max_duration_secs=${root.maxDurationSecs}`];
        configProc.seeding = !options.voxtypeSeeded;
        if (configProc.seeding) {
            const language = options.language;
            const model = options.quality === "accurate" ? "large-v3-turbo" : language === "en" ? "base.en" : "base";
            pairs.push(`whisper.model=${model}`,
                `whisper.language=${language.indexOf(",") === -1 ? language : `[${language}]`}`,
                // Whisper uses four threads however many there are; one core is kept back.
                `whisper.threads=${options.threads > 0 ? options.threads : Math.max(2, root.cpuCount - 1)}`,
                `whisper.initial_prompt=${options.punctuationHint || VoxSchema.sampleFor(language)}`,
                `whisper.translate=${options.translateToEnglish}`,
                `output.mode=${options.outputMode}`,
                `output.type_delay_ms=${options.typeDelayMs}`,
                // Paste mode goes through the clipboard; without this, dictating
                // destroys whatever the user had copied.
                "output.restore_clipboard=true",
                `output.notification.on_transcription=${options.notifyOnTranscription}`,
                // The bar and the notch already announce start and stop.
                "output.notification.on_recording_start=false",
                "output.notification.on_recording_stop=false",
                `audio.pause_media=${options.pauseMedia}`,
                `audio.feedback.enabled=${options.soundFeedback}`);
        }
        configProc.command = ["python3", root.configScript, "set"].concat(pairs);
        configProc.running = true;
    }

    function scheduleApply() {
        if (!root.installed || !Config.ready)
            return;
        applyTimer.restart();
    }

    /** Restarts the daemon once changes have settled and no dictation is running. */
    property bool restartWanted: false
    function requestRestart() {
        restartRequestTimer.restart();
    }

    Timer {
        id: restartRequestTimer
        interval: 700
        onTriggered: {
            if (root.busy && !root.useHex) {
                root.restartWanted = true;
                return;
            }
            root.restartWanted = false;
            root.restartDaemon();
        }
    }

    /** Restarts our own daemon; a foreign systemd one is left for systemd to manage. */
    function restartDaemon() {
        if (root.externalDaemon) {
            Quickshell.execDetached(["systemctl", "--user", "restart", "voxtype.service"]);
            return;
        }
        // One that gave up on a bad setting has to be started again.
        if (!daemonProc.running) {
            daemonRestartTimer.restart();
            return;
        }
        daemonProc.restarting = true;
        daemonProc.running = false;
    }

    // ── Model management ──────────────────────────────────────────────────
    property string downloadingModel: ""
    property real downloadProgress: 0
    property string lastError: ""

    /**
     * Runs the download outside the shell's process tree, on purpose. A model is
     * up to 2 GB, and a `Process` owned by the shell dies with the next config
     * reload — which used to abandon the download half-written. Detached, the
     * transfer finishes regardless, and the marker file it leaves behind is what
     * this service watches; a reload simply reconnects to the progress.
     */
    function downloadModel(engine: string, model: string, downloadArg: string) {
        if (root.downloadingModel.length > 0)
            return;
        root.lastError = "";
        root.downloadProgress = 0;
        root.downloadingModel = model;
        Quickshell.execDetached(["bash", "-c", root.downloadScript, "--", root.stateDir, model,
            downloadArg, VoxSchema.modelFile(engine, model)]);
        downloadWatchTimer.restart();
    }

    readonly property string downloadScript: [
        "set -u",
        "state=\"$1\"; model=\"$2\"; arg=\"$3\"; file=\"$4\"",
        "models=\"${XDG_DATA_HOME:-$HOME/.local/share}/voxtype/models\"",
        "mkdir -p \"$state\"",
        "rm -f \"$state/failed-$model\" \"$state/log-$model\"",
        ": > \"$state/incomplete-$model\"",
        // Any leftover file has to go first: voxtype reports an existing one as
        // "Model ready" and downloads nothing, so a retry after a failure would
        // otherwise keep the broken file forever.
        "[ -n \"$file\" ] && rm -f \"$models/$file\"",
        "if voxtype setup --download --model \"$arg\" --no-post-install --progress-format json > \"$state/log-$model\" 2>&1; then",
        "    rm -f \"$state/incomplete-$model\"",
        "else",
        "    [ -n \"$file\" ] && rm -f \"$models/$file\"",
        "    rm -f \"$state/incomplete-$model\"",
        "    : > \"$state/failed-$model\"",
        "fi"
    ].join("\n")

    function removeModel(engine: string, model: string) {
        const file = VoxSchema.modelFile(engine, model);
        if (file.length === 0)
            return;
        const dataHome = Quickshell.env("XDG_DATA_HOME");
        const base = (dataHome && dataHome.length > 0) ? dataHome : `${Quickshell.env("HOME")}/.local/share`;
        removeProc.command = ["bash", "-c",
            "rm -f -- \"$1/voxtype/models/$4\" \"$2/incomplete-$3\" \"$2/log-$3\" \"$2/failed-$3\"",
            "--", base, root.stateDir, model, file];
        removeProc.running = true;
    }

    // ── Detection ─────────────────────────────────────────────────────────
    Component.onCompleted: root.redetect()

    Process {
        id: binaryCheckProc
        command: ["bash", "-c",
            "command -v voxtype >/dev/null 2>&1 && echo yes || echo no; " +
            "command -v voxtype-audio-bridge >/dev/null 2>&1 && echo yes || echo no; " +
            "h=$(command -v hex 2>/dev/null); [ -n \"$h\" ] || { [ -x \"$HOME/hex\" ] && h=\"$HOME/hex\"; }; echo \"${h:-none}\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.installed = (lines[0] ?? "no").trim() === "yes";
                root.bridgeInstalled = (lines[1] ?? "no").trim() === "yes";
                const hex = (lines[2] ?? "none").trim();
                root.hexBin = hex === "none" ? "" : hex;
                root.binaryChecked = true;
                if (root.installed && root.enabled)
                    root.scheduleApply();
            }
        }
    }

    /**
     * Cores, the active compute backend, and whether a GPU build is sitting
     * there unused. `voxtype status` reports the backend even with no daemon
     * running, so this needs nothing to be up.
     */
    Process {
        id: backendCheckProc
        command: ["bash", "-c",
            "nproc; " +
            "voxtype status --format json --extended 2>/dev/null " +
            "| sed -n 's/.*\"backend\": *\"\\([^\"]*\\)\".*/\\1/p'; " +
            "voxtype setup gpu 2>/dev/null | grep -q 'GPU (Vulkan) - installed' && echo gpu-available || echo gpu-none"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").map(line => line.trim());
                const cores = parseInt(lines[0]);
                if (!isNaN(cores) && cores > 0)
                    root.cpuCount = cores;
                root.cpuCounted = true;
                root.backend = lines[1] ?? "";
                root.gpuAvailable = lines.indexOf("gpu-available") !== -1;
            }
        }
    }

    Process {
        id: gpuEnableProc
        command: ["pkexec", "voxtype", "setup", "gpu", "--enable"]
        stderr: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (line.length > 0)
                    root.lastError = line;
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                // 126/127 is the user dismissing the polkit prompt, which is an
                // answer rather than a failure worth shouting about.
                if (exitCode !== 126 && exitCode !== 127)
                    root.lastError = Translation.tr("Switching to the GPU backend failed.");
                return;
            }
            root.lastError = "";
            backendCheckProc.running = true;
            root.restartDaemon();
        }
    }

    Process {
        id: externalDaemonProc
        command: ["systemctl", "--user", "is-active", "--quiet", "voxtype.service"]
        onExited: exitCode => root.externalDaemon = (exitCode === 0)
    }

    /** Downloads left unfinished; what is installed comes from voxtype itself. */
    Process {
        id: modelListProc
        command: ["bash", "-c",
            "for f in \"$1\"/incomplete-*; do [ -e \"$f\" ] || continue; b=$(basename \"$f\"); echo \"${b#incomplete-}\"; done",
            "--", root.stateDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const partial = text.trim().split("\n").map(line => line.trim()).filter(line => line.length > 0);
                root.incompleteModels = partial;
                // A download still running from before this shell reloaded:
                // pick it back up rather than leaving the page on "Download".
                if (partial.length > 0 && root.downloadingModel.length === 0) {
                    root.downloadingModel = partial[0];
                    downloadWatchTimer.restart();
                }
            }
        }
    }

    // ── The daemon ────────────────────────────────────────────────────────
    Process {
        id: daemonProc
        property bool restarting: false
        running: Config.ready && !root.useHex && root.enabled && root.installed && root.modelReady
            && root.configApplied && !root.externalDaemon
        // On demand, the model loads when a recording starts, while the audio is
        // already being captured, instead of holding ~60 MB of RAM and ~150 MB of
        // VRAM all session.
        command: ProcUtils.pdeath(["voxtype"].concat(root.voxtypeOnDemand ? ["--on-demand-loading"] : [],
            [`--tray=${root.voxtypeTrayIcon}`, "daemon"]))
        stderr: SplitParser {
            onRead: data => {
                // voxtype logs to stderr; only the failures are worth keeping.
                data.split("\n").forEach(line => {
                    if (line.indexOf("ERROR") !== -1)
                        root.lastError = line.trim();
                });
            }
        }
        onExited: {
            if (!daemonProc.restarting)
                return;
            daemonProc.restarting = false;
            daemonRestartTimer.restart();
        }
    }

    Timer {
        id: daemonRestartTimer
        interval: 250
        onTriggered: daemonProc.running = Qt.binding(() => Config.ready && !root.useHex && root.enabled && root.installed
            && root.modelReady && root.configApplied && !root.externalDaemon)
    }

    // ── Live state file ───────────────────────────────────────────────────
    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const next = (text() || "").trim();
            root.voxState = next.length > 0 ? next : "idle";
        }
        // The daemon deletes the file on the way out, so a failed load is how
        // "not running" arrives — not an error worth reporting.
        onLoadFailed: root.voxState = "stopped"
    }

    /**
     * The state file only exists once a daemon has run, and FileView cannot
     * watch a path that was never there — so a shell that started before the
     * daemon would sit on "stopped" forever. Re-pointing the path is what makes
     * it pick the file up.
     */
    Timer {
        interval: 1000
        repeat: true
        running: !root.useHex && root.enabled && root.installed && root.modelReady && root.voxState === "stopped"
        onTriggered: {
            stateFile.path = "";
            stateFile.path = root.statePath;
        }
    }

    Timer {
        id: pendingToggleTimer
        interval: 400
        onTriggered: {
            if (!root.available || root.useHex) return;
            if (root.voiceCaptureBusy()) {
                root.reportError(Translation.tr("The AI assistant is using the microphone. Stop it to start dictation."));
                return;
            }
            if (!root.daemonUp) {
                root.reportError(Translation.tr("The dictation daemon did not start."));
                return;
            }
            recordProc.exec(["voxtype", "record", "toggle"]);
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: root.recording
        onTriggered: {
            root.elapsedMs = Date.now() - root.recordingStartedAt;
            // Hex has no duration setting of its own, so the cap is enforced here for both
            // engines rather than only in Voxtype's config.
            if (root.maxDurationSecs > 0 && root.elapsedMs >= root.maxDurationSecs * 1000)
                root.stop();
        }
    }

    Process {
        id: recordProc
        function exec(argv) {
            recordProc.running = false;
            recordProc.command = argv;
            recordProc.running = true;
        }
    }

    // ── Hex: keeping it up, and following what it does ──────────────────────
    /**
     * Hex keeps itself running once started, so the shell only makes sure it exists: a probe
     * every few seconds both reports whether it is up and starts it when it is not. It is
     * started with `hex start`, which is the entry point that gets the desktop permission
     * the dictation commands need (`hex service` alone ends up "not listening").
     */
    Process {
        id: hexProbeProc
        // Only looks: Hex is started by a key press (see ensureHex), never by this probe. It
        // counts as up only when it answers `hex status`, so a frozen daemon reads as down.
        command: ["bash", "-c",
            // The path is looked up again each time: Hex can be installed (or replaced) while the shell runs
            "h=$(command -v hex 2>/dev/null); [ -n \"$h\" ] || { [ -x \"$HOME/hex\" ] && h=\"$HOME/hex\"; }; " +
            "if [ -z \"$h\" ]; then echo none; elif timeout 2 \"$h\" status >/dev/null 2>&1; then echo \"up $h\"; " +
            "else echo \"down $h\"; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(" ");
                if (parts[0] === "none") {
                    root.hexBin = "";
                    root.hexState = "stopped";
                    return;
                }
                if (parts[1] && parts[1] !== root.hexBin)
                    root.hexBin = parts[1];
                const up = parts[0] === "up";
                if (up && root.hexState === "stopped")
                    root.hexState = "idle";
                else if (!up)
                    root.hexState = "stopped";
            }
        }
    }

    Timer {
        interval: 4000
        repeat: true
        triggeredOnStart: true
        running: root.useHex && root.enabled && root.hexInstalled && Config.ready && !root.hexStarting
        onTriggered: {
            if (!hexProbeProc.running)
                hexProbeProc.running = true;
        }
    }

    /** True while a key press is waiting for Hex to come up. */
    property bool hexStarting: false
    /** What to do once Hex answers: "start" (hold to talk), "toggle", or "" (cancelled). */
    property string hexPending: ""

    /**
     * Runs `action` once Hex answers, starting it first when it is down. A daemon that is alive
     * but does not answer is restarted through its unit; otherwise `hex start` brings it up
     * (the entry point that gets the desktop permission the dictation commands need).
     */
    function ensureHex(action: string): void {
        root.hexPending = action;
        if (root.hexStarting)
            return;
        root.hexStarting = true;
        hexReadyProc.running = true;
    }

    Process {
        id: hexReadyProc
        command: ["timeout", "12", "bash", "-c",
            "h=\"$1\"; [ -n \"$h\" ] || h=$(command -v hex); " +
            // Answering is not enough: dictation commands are refused until the listener is enabled
            "ready() { timeout 2 \"$h\" status 2>&1 | grep -q 'running: Enabled'; }; " +
            "ready && exit 0; " +
            "if systemctl --user is-active -q hex.service; then systemctl --user restart hex.service; " +
            "else setsid -f \"$h\" start >/dev/null 2>&1 </dev/null; fi; " +
            "for i in $(seq 80); do ready && exit 0; sleep 0.5; done; exit 1",
            "--", root.hexBin]
        onExited: (code, status) => {
            const action = root.hexPending;
            root.hexStarting = false;
            root.hexPending = "";
            if (code !== 0) {
                root.hexState = "stopped";
                if (action.length > 0)
                    root.reportError(Translation.tr("Hex did not get ready for dictation. Try the shortcut again."));
                return;
            }
            if (root.hexState === "stopped")
                root.hexState = "idle";
            if ((action === "start" || action === "toggle") && root.available && root.useHex) {
                if (root.voiceCaptureBusy())
                    root.reportError(Translation.tr("The AI assistant is using the microphone. Stop it to start dictation."));
                else
                    root.hexCmd(action);
            }
            idleQuitTimer.restart();
        }
    }

    /** Quits Hex after a quiet spell; the next key press starts it again. */
    Timer {
        id: idleQuitTimer
        interval: Math.max(1, root.hexIdleMinutes) * 60000
        running: root.useHex && root.enabled && root.hexIdleMinutes > 0 && root.state === "idle" && !root.hexStarting
            && HexSettings.installingModel.length === 0
        onTriggered: {
            if (root.busy || root.hexStarting)
                return;
            Quickshell.execDetached([root.hexBin, "quit"]);
            root.hexState = "stopped";
        }
    }

    /**
     * Hex appends every state change to a log of JSON lines; following it gives the same
     * instant reaction the Voxtype state file does.
     */
    Process {
        id: hexLiveProc
        running: root.useHex && root.enabled && root.hexInstalled
        command: ["tail", "-n", "0", "-F",
            `${Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share"}/hex/logs/live.ndjson`]
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf('"kind":"state"') === -1)
                    return;
                try {
                    const st = JSON.parse(line).state;
                    root.hexState = st === "dictating" ? "recording"
                        : st === "transcribing" ? "transcribing" : "idle";
                } catch (e) {}
            }
        }
    }

    // ── Mic levels ────────────────────────────────────────────────────────
    /** Hex has no level feed: listen to the default microphone while it records. */
    Process {
        id: hexLevelProc
        running: root.recording && root.useHex
        command: ProcUtils.pdeath(["bash", "-c",
            "parec --raw --format=s16le --rate=16000 --channels=1 --latency-msec=30 2>/dev/null | python3 -u \"$1\"",
            "--", FileUtils.trimFileProtocol(`${Directories.scriptPath}/dictation/mic_level.py`)])
        stdout: SplitParser {
            onRead: data => root.handleFrame(data)
        }
    }

    /**
     * voxtype's own sidecar, reading the daemon's capture over its audio
     * socket. The alternative — pointing cava at the microphone — opens a
     * second capture stream on a device that is already being recorded, and
     * shows the room rather than what the daemon actually hears.
     */
    Process {
        id: bridgeProc
        running: root.recording && root.bridgeInstalled && !root.useHex
        command: ProcUtils.pdeath(["voxtype-audio-bridge"])
        stdout: SplitParser {
            // One read can carry several frames at once, so never treat the
            // payload as a single line.
            onRead: data => data.split("\n").forEach(line => root.handleFrame(line))
        }
    }

    function handleFrame(line: string) {
        const trimmed = String(line ?? "").trim();
        if (trimmed.length === 0 || trimmed.charAt(0) !== "{")
            return;
        let frame;
        try {
            frame = JSON.parse(trimmed);
        } catch (e) {
            return;
        }
        if (frame.status !== undefined)
            return;
        const rms = Math.max(0, Math.min(1, Number(frame.rms ?? 0)));
        const peak = Math.max(0, Math.min(1, Number(frame.peak ?? 0)));
        // Speech sits low in a linear 0..1 scale; the curve is what makes a
        // normal speaking voice fill the meter instead of nudging it.
        const shaped = Math.min(1, Math.pow(Math.max(rms, peak * 0.6), 0.55) * 1.4);
        root.level = root.level * 0.55 + shaped * 0.45;
        const next = root.waveform.slice(-(root.waveformLength - 1));
        next.push(root.level);
        root.waveform = next;
    }

    // ── Settings → voxtype's config file ──────────────────────────────────
    Timer {
        id: applyTimer
        interval: 500
        onTriggered: root.applySettings()
    }

    Process {
        id: configProc
        property bool seeding: false
        stdout: StdioCollector {}
        stderr: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (line.length > 0)
                    root.lastError = line;
            }
        }
        onExited: exitCode => {
            Qt.callLater(() => VoxtypeSettings.flush());
            if (exitCode !== 0)
                return;
            if (configProc.seeding)
                Config.options.dictation.voxtypeSeeded = true;
            VoxtypeSettings.refresh();
            if (!root.configApplied) {
                // First write of the session: the binding above starts the
                // daemon on its own, so restarting here would only fight it.
                root.configApplied = true;
                return;
            }
            root.requestRestart();
        }
    }

    Connections {
        target: Config.options?.dictation ?? null
        enabled: target !== null
        function onMaxDurationSecsChanged() { root.scheduleApply(); }
        // Flags on the daemon's command line.
        function onVoxtypeOnDemandChanged() { root.requestRestart(); }
        function onVoxtypeTrayIconChanged() { root.requestRestart(); }
        function onEngineChanged() {
            // One engine at a time: leaving Hex for Voxtype stops the Hex daemon instead of
            // leaving it resident. The Voxtype daemon's own binding starts and stops it.
            if (!root.useHex)
                root.quitHex();
        }
        function onEnabledChanged() {
            if (Config.options.dictation.enabled) {
                root.scheduleApply();
            } else {
                root.cancelPendingStart();
                // Nothing to dictate with: do not leave Hex resident while the feature is off.
                root.quitHex();
            }
        }
    }

    // ── Downloads ─────────────────────────────────────────────────────────
    Timer {
        id: downloadWatchTimer
        interval: 900
        repeat: true
        running: false
        triggeredOnStart: true
        onTriggered: {
            if (root.downloadingModel.length === 0) {
                stop();
                return;
            }
            if (downloadWatchProc.running)
                return;
            downloadWatchProc.command = ["bash", "-c", root.downloadWatchScript,
                "--", root.stateDir, root.downloadingModel];
            downloadWatchProc.running = true;
        }
    }

    /**
     * Prints the download's state on the first line and its latest percentage on
     * the second, taken from the progress events the download logs.
     */
    readonly property string downloadWatchScript: [
        "set -u",
        "state=\"$1\"; model=\"$2\"",
        "if [ -f \"$state/failed-$model\" ]; then echo failed",
        "elif [ -f \"$state/incomplete-$model\" ]; then echo running",
        "else echo done; fi",
        "grep -o '\"pct\":[0-9.]*' \"$state/log-$model\" 2>/dev/null | tail -1 | cut -d: -f2"
    ].join("\n")

    Process {
        id: downloadWatchProc
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const status = (lines[0] ?? "").trim();
                const percent = parseFloat(lines[1] ?? "");
                if (!isNaN(percent))
                    root.downloadProgress = Math.max(0, Math.min(100, percent)) / 100;
                if (status === "running")
                    return;
                const model = root.downloadingModel;
                downloadWatchTimer.stop();
                root.downloadingModel = "";
                root.downloadProgress = 0;
                if (status === "failed")
                    root.lastError = Translation.tr("Downloading the %1 model failed. See the log for what voxtype said.").arg(model);
                Quickshell.execDetached(["rm", "-f", `${root.stateDir}/failed-${model}`, `${root.stateDir}/log-${model}`]);
                modelListProc.running = true;
                VoxtypeSettings.refresh();
            }
        }
    }

    Process {
        id: removeProc
        onExited: {
            modelListProc.running = true;
            VoxtypeSettings.refresh();
        }
    }

    // ── Keybind ───────────────────────────────────────────────────────────
    GlobalShortcut {
        name: "dictationToggle"
        description: "Start or stop dictation"
        onPressed: root.toggle()
    }

    // ── Hold to talk ──
    // Hyprland hands a global shortcut its release even when the modifiers were let go first,
    // which a plain exec bind cannot do. Recording lasts exactly as long as the keys are held.
    // A release that comes right after the press waits a moment, so the stop cannot overtake
    // the start (two separate processes) and leave a recording running.
    property real holdPressedAt: 0

    function holdStart(): void {
        if (root.holdPressedAt > 0 || holdStopTimer.running || root.engaged || root.hexStarting)
            return;
        if (root.voiceCaptureBusy()) {
            root.reportError(Translation.tr("The AI assistant is using the microphone. Stop it to start dictation."));
            return;
        }
        if (!root.available) {
            root.complain();
            return;
        }
        if (!root.useHex && !root.daemonUp) {
            root.reportError(Translation.tr("Dictation is starting. Hold the shortcut again when it is ready."));
            return;
        }
        root.holdPressedAt = Date.now();
        if (root.useHex)
            root.ensureHex("start");
        else
            recordProc.exec(["voxtype", "record", "start"]);
    }

    function holdStop(): void {
        const pressedAt = root.holdPressedAt;
        if (pressedAt === 0)
            return;
        root.holdPressedAt = 0;
        // A queued start that has not run must never stop another recording.
        if (root.hexStarting && root.hexPending === "start") {
            root.hexPending = "";
            return;
        }
        holdStopTimer.interval = Math.max(1, 300 - (Date.now() - pressedAt));
        holdStopTimer.restart();
    }

    Timer {
        id: holdStopTimer
        onTriggered: {
            if (root.useHex)
                root.hexCmd("stop");
            else if (root.busy)
                recordProc.exec(["voxtype", "record", "stop"]);
        }
    }

    GlobalShortcut {
        name: "dictationHold"
        description: "Dictate while the keys are held"
        onPressed: root.holdStart()
        onReleased: root.holdStop()
    }

    GlobalShortcut {
        name: "dictationStop"
        description: "Stop dictation without transcribing further speech"
        onPressed: root.stop()
    }
}
