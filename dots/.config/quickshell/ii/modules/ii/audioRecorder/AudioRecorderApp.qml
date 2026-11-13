pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.services

/**
 * The Audio Recorder app: the keybind, the IPC target and the window, built only while open.
 */
Scope {
    id: root

    function requestOpen(): void {
        GlobalStates.openAudioRecorderApp();
    }

    function requestClose(): void {
        GlobalStates.audioRecorderOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.audioRecorderOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    Loader {
        active: GlobalStates.audioRecorderOpen
        sourceComponent: AudioRecorderWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "audioRecorderToggle"
        description: "Toggles the Audio Recorder"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "audioRecorder"

        function open(): void {
            root.requestOpen();
        }

        function close(): void {
            root.requestClose();
        }

        function toggle(): void {
            root.requestToggle();
        }

        function start(): void {
            AudioRecorderService.startRecording();
        }

        function stop(): void {
            AudioRecorderService.stopRecording();
        }

        function pause(): void {
            AudioRecorderService.togglePause();
        }

        function status(): string {
            if (!AudioRecorderService.recording)
                return "idle";
            return AudioRecorderService.paused ? "paused" : "recording";
        }

        function isOpen(): bool {
            return GlobalStates.audioRecorderOpen;
        }

        function screenLocked(): bool {
            return GlobalStates.screenLocked;
        }

        function file(): string {
            return AudioRecorderService.currentFile;
        }
    }
}
