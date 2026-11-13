pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io

import qs
import qs.modules.common
import qs.services

/**
 * Audio recording behind the Audio Recorder app.
 *
 * The capture process writes one continuous WAV to ~/Music/Recordings. The process is
 * kept here, rather than in the window, so closing the window does not interrupt a take.
 * Playback is also owned here so the player survives view rebuilds and window closes.
 */
Singleton {
    id: root

    readonly property string homeDir: String(Quickshell.env("HOME") || "")
    readonly property string outputDir: root.homeDir + "/Music/Recordings"
    readonly property string currentName: {
        const slash = root.currentFile.lastIndexOf("/");
        return slash >= 0 ? root.currentFile.slice(slash + 1) : root.currentFile;
    }

    property bool recording: false
    property bool paused: false
    property bool starting: false
    property bool stopping: false
    property int elapsed: 0
    property string currentFile: ""
    property string error: ""
    property bool listLoading: false
    property string listError: ""
    property var recordings: []

    // Playback is deliberately service-owned. The content view may be destroyed while
    // the window is closed, but a selected take and its transport continue to exist.
    property var selectedEntry: null
    property bool playbackEnded: false
    property real volume: 0.85
    property string _loadedPath: ""
    property bool _playWhenReady: false
    readonly property string selectedPath: String(root.selectedEntry?.path ?? "")
    readonly property string selectedName: String(root.selectedEntry?.name ?? "")
    readonly property real playbackPosition: Math.max(0, Number(playbackPlayer.position || 0) / 1000)
    readonly property real playbackDuration: Math.max(0, Number(playbackPlayer.duration || 0) / 1000)
    readonly property bool playing: playbackPlayer.playbackState === MediaPlayer.PlayingState
    readonly property bool playbackPaused: playbackPlayer.playbackState === MediaPlayer.PausedState
    readonly property bool loading: playbackPlayer.mediaStatus === MediaPlayer.LoadingMedia
        || playbackPlayer.mediaStatus === MediaPlayer.BufferingMedia
        || playbackPlayer.mediaStatus === MediaPlayer.StalledMedia
    readonly property bool seekable: playbackPlayer.seekable && root.playbackDuration > 0
        && playbackPlayer.mediaStatus !== MediaPlayer.NoMedia
        && playbackPlayer.mediaStatus !== MediaPlayer.InvalidMedia
    readonly property string playbackError: root._playbackError
    property string _playbackError: ""

    function formatElapsed(seconds): string {
        const total = Math.max(0, Math.floor(Number(seconds) || 0));
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        const s = total % 60;
        const mm = (m < 10 ? "0" : "") + m;
        const ss = (s < 10 ? "0" : "") + s;
        return h > 0 ? h + ":" + mm + ":" + ss : mm + ":" + ss;
    }

    function clampSeek(seconds, duration): real {
        const length = Math.max(0, Number(duration) || 0);
        if (length <= 0)
            return 0;
        return Math.max(0, Math.min(length, Number(seconds) || 0));
    }

    // QUrl treats '#', '?', spaces and non-ASCII characters as syntax when they are
    // left in a file URL. Encode each path segment while preserving the separators.
    // The service keeps paths as raw filesystem paths everywhere else.
    function localFileUrl(path): string {
        const raw = String(path ?? "");
        if (raw.length === 0)
            return "";
        if (raw.startsWith("file://"))
            return raw;
        const absolute = raw.startsWith("/") ? raw : "/" + raw;
        return "file://" + absolute.split("/").map((part, index) =>
            index === 0 ? "" : encodeURIComponent(part)).join("/");
    }

    // A paused pw-record process must be continued before SIGINT. Otherwise it never
    // receives the interrupt and the WAV header remains unfinished.
    function stopSignalSequence(isPaused): var {
        return isPaused ? [18, 2] : [2];
    }

    function formatSize(bytes): string {
        const value = Number(bytes) || 0;
        if (value <= 0)
            return "";
        if (value < 1024 * 1024)
            return Math.max(1, Math.round(value / 1024)) + " KB";
        return (value / (1024 * 1024)).toFixed(1) + " MB";
    }

    function formatWhen(timestamp): string {
        if (!timestamp)
            return "";
        const date = new Date(Number(timestamp) * 1000);
        const now = new Date();
        const sameDay = date.toDateString() === now.toDateString();
        const time = Qt.formatTime(date, "HH:mm");
        if (sameDay)
            return Translation.tr("Today, %1").arg(time);
        const yesterday = new Date(now.getTime() - 86400000);
        if (date.toDateString() === yesterday.toDateString())
            return Translation.tr("Yesterday, %1").arg(time);
        return Qt.formatDate(date, "d MMM") + ", " + time;
    }

    function startRecording(): void {
        if (root.recording || root.starting || root.stopping || recordProc.running)
            return;
        // Do not feed the take back into the microphone through the speakers.
        root.stopPlayback();
        root.error = "";
        root.elapsed = 0;
        root.paused = false;
        const now = new Date();
        const pad = value => (value < 10 ? "0" : "") + value;
        const stamp = now.getFullYear() + "-" + pad(now.getMonth() + 1) + "-" + pad(now.getDate())
            + "-" + pad(now.getHours()) + "-" + pad(now.getMinutes()) + "-" + pad(now.getSeconds());
        root.currentFile = root.outputDir + "/recording-" + stamp + ".wav";
        root.starting = true;
        mkdirProc.command = ["mkdir", "-p", root.outputDir];
        mkdirProc.running = true;
    }

    function _beginCapture(): void {
        root.starting = false;
        recordProc.command = ["pw-record", "--rate", "48000", "--channels", "2",
            "--format", "s16", root.currentFile];
        recordProc.running = true;
        root.recording = true;
        root.paused = false;
        elapsedTimer.start();
    }

    function stopRecording(): void {
        if (!root.recording)
            return;
        root.stopping = true;
        for (const signal of root.stopSignalSequence(root.paused))
            recordProc.signal(signal);
        root.recording = false;
        root.paused = false;
        elapsedTimer.stop();
        refreshTimer.restart();
    }

    function togglePause(): void {
        if (!root.recording)
            return;
        if (root.paused) {
            recordProc.signal(18); // SIGCONT
            root.paused = false;
            elapsedTimer.start();
        } else {
            recordProc.signal(19); // SIGSTOP
            root.paused = true;
            elapsedTimer.stop();
        }
    }

    function toggle(): void {
        if (root.recording)
            root.stopRecording();
        else
            root.startRecording();
    }

    function remove(path: string): void {
        const rawPath = String(path ?? "");
        if (rawPath.length === 0)
            return;
        if (rawPath === root.currentFile && (root.recording || root.starting || root.stopping)) {
            root.error = Translation.tr("Finish the recording before deleting it.");
            return;
        }
        if (rawPath === root.selectedPath) {
            root.stopPlayback();
            root.selectedEntry = null;
        }
        Quickshell.execDetached(["rm", "-f", rawPath]);
        refreshTimer.restart();
    }

    function selectRecording(entry): bool {
        if (!entry || !entry.path)
            return false;
        const path = String(entry.path);
        if (path === root.currentFile
                && (root.recording || root.starting || root.stopping)) {
            root.error = Translation.tr("Finish the recording before playing it.");
            return false;
        }
        if (path !== root.selectedPath) {
            // Selection is also a transport boundary: never leave take A playing while
            // the page presents take B as the active row.
            root.stopPlayback();
            playbackPlayer.source = "";
            root._loadedPath = "";
            root._playWhenReady = false;
            root.playbackEnded = false;
            root._playbackError = "";
        }
        root.selectedEntry = entry;
        return true;
    }

    function play(entry): void {
        if (!root.selectRecording(entry))
            return;
        const path = String(entry.path);
        const sameEntry = root.selectedPath === path && root._loadedPath === path;
        const retrying = root._playbackError.length > 0;
        if (!sameEntry || retrying) {
            root.stopPlayback();
            playbackPlayer.source = "";
            root._playbackError = "";
            root.playbackEnded = false;
            root._loadedPath = path;
            root._playWhenReady = true;
            playbackPlayer.source = root.localFileUrl(path);
        } else if (root.playbackEnded || (playbackPlayer.playbackState === MediaPlayer.StoppedState
                    && root.playbackDuration > 0 && root.playbackPosition >= root.playbackDuration)) {
            playbackPlayer.position = 0;
            root.playbackEnded = false;
        }
        // An explicit retry should recover the button after a transient decoder error;
        // MediaPlayer will publish a fresh error if the source is still invalid.
        root._playbackError = "";
        root._playWhenReady = true;
        if (sameEntry && !retrying)
            playbackPlayer.play();
        else
            playbackStartTimer.restart();
    }

    function togglePlayback(entry): void {
        const target = entry || root.selectedEntry;
        if (!target || !target.path)
            return;
        if (root.selectedPath === String(target.path) && root.playing) {
            root.pausePlayback();
            return;
        }
        root.play(target);
    }

    function pausePlayback(): void {
        if (root.playing) {
            root._playWhenReady = false;
            playbackStartTimer.stop();
            playbackPlayer.pause();
        }
    }

    function resumePlayback(): void {
        if (!root.selectedEntry || root.selectedPath.length === 0)
            return;
        root.play(root.selectedEntry);
    }

    function stopPlayback(): void {
        root._playWhenReady = false;
        playbackStartTimer.stop();
        playbackPlayer.stop();
        root.playbackEnded = false;
    }

    function seek(seconds): void {
        if (!root.seekable)
            return;
        const target = root.clampSeek(seconds, root.playbackDuration);
        root.playbackEnded = false;
        playbackPlayer.position = Math.round(target * 1000);
    }

    function skip(deltaSeconds): void {
        root.seek(root.playbackPosition + Number(deltaSeconds || 0));
    }

    function showInFolder(path: string): void {
        const slash = String(path ?? "").lastIndexOf("/");
        Quickshell.execDetached(["xdg-open", slash > 0 ? String(path).slice(0, slash) : root.outputDir]);
    }

    function openFolder(): void {
        Quickshell.execDetached(["xdg-open", root.outputDir]);
    }

    function refresh(): void {
        if (listProc.running)
            return;
        root.listLoading = true;
        root.listError = "";
        listProc.command = ["bash", "-c",
            "find \"$1\" -maxdepth 1 -type f \\( -name '*.wav' -o -name '*.flac' -o -name '*.ogg' -o -name '*.mp3' -o -name '*.m4a' \\) -printf '%T@\\t%s\\t%p\\n' | sort -rn",
            "bash", root.outputDir];
        listProc.running = true;
    }

    Component.onCompleted: root.refresh()

    MediaDevices {
        id: mediaDevices
    }

    AudioOutput {
        id: playbackOutput
        device: mediaDevices.defaultAudioOutput
        volume: Math.max(0, Math.min(1, root.volume))
    }

    MediaPlayer {
        id: playbackPlayer
        audioOutput: playbackOutput
        autoPlay: false

        function publishPlaybackError(message): void {
            root._playWhenReady = false;
            playbackStartTimer.stop();
            root.playbackEnded = false;
            root._playbackError = message || Translation.tr("This recording could not be played.");
        }

        onMediaStatusChanged: {
            if (playbackPlayer.mediaStatus === MediaPlayer.EndOfMedia) {
                root.playbackEnded = true;
                root._playWhenReady = false;
            }
            if ((playbackPlayer.mediaStatus === MediaPlayer.LoadedMedia
                    || playbackPlayer.mediaStatus === MediaPlayer.BufferedMedia)
                    && root._playWhenReady) {
                playbackStartTimer.restart();
            }
            if (playbackPlayer.mediaStatus === MediaPlayer.InvalidMedia
                    && root._playbackError.length === 0) {
                playbackPlayer.publishPlaybackError(playbackPlayer.errorString);
            }
        }

        onErrorChanged: {
            if (playbackPlayer.error !== MediaPlayer.NoError)
                playbackPlayer.publishPlaybackError(playbackPlayer.errorString);
        }

        onErrorOccurred: (error, errorString) => {
            if (error !== MediaPlayer.NoError)
                playbackPlayer.publishPlaybackError(errorString);
        }

        onPlaybackStateChanged: {
            if (playbackPlayer.playbackState === MediaPlayer.PlayingState)
                root._playWhenReady = false;
        }
    }

    Timer {
        id: playbackStartTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (!root._playWhenReady)
                return;
            if (playbackPlayer.mediaStatus !== MediaPlayer.LoadedMedia
                    && playbackPlayer.mediaStatus !== MediaPlayer.BufferedMedia)
                return;
            root._playWhenReady = false;
            playbackPlayer.play();
        }
    }

    Timer {
        id: elapsedTimer
        interval: 1000
        repeat: true
        onTriggered: if (root.recording && !root.paused) root.elapsed += 1
    }

    Timer {
        id: refreshTimer
        interval: 650
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: mkdirProc
        onExited: (code, status) => {
            if (code === 0) {
                root._beginCapture();
            } else {
                root.starting = false;
                root.error = Translation.tr("Could not create %1.").arg(root.outputDir);
            }
        }
    }

    Process {
        id: recordProc
        stderr: StdioCollector {
            id: recordError
            waitForEnd: true
        }
        onExited: (code, status) => {
            root.recording = false;
            root.paused = false;
            root.starting = false;
            elapsedTimer.stop();
            if (!root.stopping && code !== 0 && code !== 130)
                root.error = Translation.tr("The recorder stopped unexpectedly.");
            root.stopping = false;
            refreshTimer.restart();
        }
    }

    Process {
        id: listProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const files = [];
                for (const line of String(text ?? "").split("\n")) {
                    if (line.trim().length === 0)
                        continue;
                    const first = line.indexOf("\t");
                    const second = line.indexOf("\t", first + 1);
                    if (first < 0 || second < 0)
                        continue;
                    const mtime = Number(line.slice(0, first));
                    const size = Number(line.slice(first + 1, second));
                    const path = line.slice(second + 1);
                    const slash = path.lastIndexOf("/");
                    const name = slash >= 0 ? path.slice(slash + 1) : path;
                    files.push({
                        "name": name,
                        "path": path,
                        "size": size,
                        "mtime": mtime,
                        // Duration comes from the native decoder when a take is selected.
                        // File-size estimates become wrong as soon as a different format is added.
                        "seconds": 0
                    });
                }
                root.recordings = files;
                const selected = root.selectedPath.length > 0
                    ? files.find(entry => entry.path === root.selectedPath) : null;
                if (selected) {
                    root.selectedEntry = selected;
                } else if (root.selectedPath.length > 0) {
                    root.stopPlayback();
                    root.selectedEntry = null;
                }
            }
        }
        onExited: (code, status) => {
            root.listLoading = false;
            if (code !== 0)
                root.listError = Translation.tr("Recordings could not be loaded.");
        }
    }
}
