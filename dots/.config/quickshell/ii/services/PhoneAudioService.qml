pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Plays what the phone is playing (music, a video, a call) on this PC, without the
 * mirror window: `scrcpy --no-video --no-window --audio-source=output`, which needs
 * Android 11+. The other half of PhoneMicService, which carries the phone's
 * microphone the other way.
 *
 * scrcpy is detached by scripts/phone/phone_audio.sh, so the stream survives a
 * shell reload and is picked up again from its pid file.
 */
Singleton {
    id: root

    readonly property string script: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/phone/phone_audio.sh`
    readonly property bool available: KdeConnectService.scrcpyAvailable

    property bool running: false
    property bool connecting: false
    property string lastError: ""
    property real startedAt: 0
    property real tick: 0
    readonly property real elapsedMs: { root.tick; return root.running && root.startedAt > 0 ? Date.now() - root.startedAt : 0; }

    readonly property int volume: Config.options?.phone?.audio?.volume ?? 100
    /// Keep the phone's own speaker playing too (scrcpy --audio-dup, Android 13+).
    readonly property bool alsoOnPhone: Config.options?.phone?.audio?.alsoOnPhone ?? false

    function start(): void {
        if (!root.available || root.running || root.connecting)
            return;
        root.lastError = "";
        root.connecting = true;
        KdeConnectService.withAdbTarget(targetArgs => {
            // `output` takes over the phone's whole audio output and silences its speaker;
            // `playback` (Android 13+) only copies app audio, which is what lets it keep playing
            const args = ["scrcpy", "--no-video", "--no-window", "--no-control",
                          root.alsoOnPhone ? "--audio-source=playback" : "--audio-source=output",
                          "--audio-buffer=80"];
            if (root.alsoOnPhone)
                args.push("--audio-dup");
            startProc.command = ["bash", root.script, "start"].concat(args).concat(targetArgs || []);
            startProc.running = true;
        });
    }

    function stop(): void {
        verify.stop();
        stopProc.running = true;
        root.running = false;
        root.connecting = false;
    }

    function toggle(): void {
        if (root.running || root.connecting)
            root.stop();
        else
            root.start();
    }

    function setVolume(v: int): void {
        const clamped = Math.max(0, Math.min(150, Math.round(v)));
        Config.options.phone.audio.volume = clamped;
        volumeProc.command = ["bash", root.script, "volume", String(clamped)];
        volumeProc.running = false;
        volumeProc.running = true;
    }

    function setAlsoOnPhone(on: bool): void {
        Config.options.phone.audio.alsoOnPhone = on;
        // The flag is a launch option: restart a running stream so it takes effect
        if (root.running) {
            root.stop();
            restartTimer.restart();
        }
    }

    Timer {
        id: restartTimer
        interval: 600
        onTriggered: root.start()
    }

    Process {
        id: startProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (String(text).trim().length > 0) {
                    root.startedAt = Date.now();
                    verify.restart();
                } else {
                    root.connecting = false;
                    root.lastError = Translation.tr("scrcpy could not start (is the phone reachable and on Android 11 or newer?)");
                }
            }
        }
    }

    Process { id: stopProc; command: ["bash", root.script, "stop"] }
    Process { id: volumeProc }

    // scrcpy dies on its own when the phone disconnects or refuses audio capture, so the
    // first seconds decide whether the stream is real
    Timer {
        id: verify
        interval: 2500
        onTriggered: {
            statusProc.verifying = true;
            statusProc.running = true;
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: root.tick++
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.running
        onTriggered: statusProc.running = true
    }

    Process {
        id: statusProc
        property bool verifying: false
        command: ["bash", root.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const up = String(text).trim().length > 0;
                if (statusProc.verifying) {
                    statusProc.verifying = false;
                    root.connecting = false;
                    if (!up) {
                        root.lastError = Translation.tr("The phone refused to share its audio (needs Android 11+, and the screen unlocked once)");
                    } else {
                        root.running = true;
                        root.setVolume(root.volume);
                    }
                    return;
                }
                if (root.running && !up) {
                    root.running = false;
                    root.lastError = Translation.tr("The audio stream ended");
                } else if (root.running) {
                    // scrcpy opens its output stream when the phone first makes a sound,
                    // so the volume has to be applied again until it exists
                    root.setVolume(root.volume);
                }
            }
        }
    }

    // Pick a stream up again after a shell reload
    Component.onCompleted: {
        statusProc.verifying = false;
        adoptProc.running = true;
    }
    Process {
        id: adoptProc
        command: ["bash", root.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (String(text).trim().length > 0) {
                    root.startedAt = Date.now();
                    root.running = true;
                }
            }
        }
    }
}
