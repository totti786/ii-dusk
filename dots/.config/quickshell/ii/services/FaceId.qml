pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Face ID authentication service powered by Gaze (com.gundulabs.Gaze).
 *
 * Provides device probing, face profile listing, and authentication.
 * Triggered on the lock screen when the user presses Enter/Return.
 */
Singleton {
    id: root

    // ── Device & Daemon state ───────────────────────────────────────────────
    property bool probed: false
    property bool gazeInstalled: false
    property bool daemonRunning: false
    property bool cameraAvailable: false
    property bool hasCameraHardware: false
    property bool hasEnrolled: false
    property var enrolled: []
    readonly property int enrolledCount: enrolled.length
    readonly property bool available: daemonRunning && cameraAvailable && hasEnrolled
    readonly property bool supported: gazeInstalled && daemonRunning && cameraAvailable

    // ── Authentication state ────────────────────────────────────────────────
    property bool verifying: false
    property string lastResult: "" // "" | "success" | "failure" | "timeout"
    property string lastError: ""
    property string statusMessage: ""

    signal authenticated()
    signal failed()

    // ── Probing ─────────────────────────────────────────────────────────────
    function refresh(): void {
        probeCameraHardwareProc.running = true;
    }

    Component.onCompleted: root.refresh()

    // Step 0: Check camera hardware
    Process {
        id: probeCameraHardwareProc
        command: ["bash", "-c", "test -e /dev/video0 || ls /dev/video* 2>/dev/null | grep -q video"]
        onExited: exitCode => {
            root.hasCameraHardware = (exitCode === 0);
            checkGazeProc.running = true;
        }
    }

    // Step 1: Check if gaze binary is installed
    Process {
        id: checkGazeProc
        command: ["which", "gaze"]
        onExited: exitCode => {
            root.gazeInstalled = (exitCode === 0);
            probeCameraProc.running = true;
        }
    }

    // Step 1: Probe camera availability
    Process {
        id: probeCameraProc
        command: ["busctl", "--system", "--json=short", "call", "com.gundulabs.Gaze", "/com/gundulabs/Gaze", "com.gundulabs.Gaze", "IsCameraAvailable"]
        stdout: StdioCollector {
            id: probeCameraCollector
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(probeCameraCollector.text);
                    root.cameraAvailable = !!(parsed?.data?.[0]);
                    root.daemonRunning = true;
                } catch (e) {
                    root.cameraAvailable = false;
                }
            }
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                probeFacesProc.running = true;
            } else {
                root.daemonRunning = false;
                root.cameraAvailable = false;
                root.hasEnrolled = false;
                root.enrolled = [];
                root.probed = true;
            }
        }
    }

    // Step 2: Probe enrolled faces for the current user
    Process {
        id: probeFacesProc
        command: ["bash", "-c", "busctl --system --json=short call com.gundulabs.Gaze /com/gundulabs/Gaze com.gundulabs.Gaze ListFaces s \"$(whoami)\""]
        stdout: StdioCollector {
            id: probeFacesCollector
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(probeFacesCollector.text);
                    const faces = parsed?.data?.[0] ?? [];
                    const list = [];
                    for (let i = 0; i < faces.length; i++) {
                        if (faces[i] && faces[i][0])
                            list.push(faces[i][0]);
                    }
                    root.enrolled = list;
                    root.hasEnrolled = list.length > 0;
                } catch (e) {
                    root.enrolled = [];
                    root.hasEnrolled = false;
                }
                root.probed = true;
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.enrolled = [];
                root.hasEnrolled = false;
                root.probed = true;
            }
        }
    }

    // ── Authentication execution ────────────────────────────────────────────
    function startAuth(): void {
        if (root.verifying || authProc.running)
            return;
        root.verifying = true;
        root.lastResult = "";
        root.lastError = "";
        root.statusMessage = Translation.tr("Scanning face…");
        authTimeoutTimer.restart();
        authProc.running = true;
    }

    function cancelAuth(): void {
        authTimeoutTimer.stop();
        if (authProc.running) {
            authProc.running = false;
        }
        root.verifying = false;
    }

    Timer {
        id: authTimeoutTimer
        interval: 7000
        onTriggered: {
            if (root.verifying) {
                root.cancelAuth();
                root.lastResult = "timeout";
                root.statusMessage = Translation.tr("Face verification timed out");
                root.failed();
            }
        }
    }

    Process {
        id: authProc
        command: ["gaze", "auth", "-s"]
        onExited: (exitCode, exitStatus) => {
            authTimeoutTimer.stop();
            const wasVerifying = root.verifying;
            root.verifying = false;
            if (!wasVerifying)
                return;

            if (exitCode === 0) {
                root.lastResult = "success";
                root.statusMessage = Translation.tr("Face recognized");
                root.authenticated();
            } else {
                root.lastResult = "failure";
                root.statusMessage = Translation.tr("Face not recognized");
                root.failed();
            }
        }
    }
}
