pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs
import qs.services
import qs.modules.ii.qanun

/**
 * The Qanun app's keybind, IPC target and lazily built window.
 */
Scope {
    id: root

    function requestOpen(tab = ""): void {
        GlobalStates.openQanunApp(String(tab ?? ""));
    }

    function requestClose(): void {
        QanunStore.stopAllAudio();
        GlobalStates.qanunOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.qanunOpen)
            root.requestClose();
        else
            root.requestOpen("");
    }

    Loader {
        active: GlobalStates.qanunOpen
        sourceComponent: QanunWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "qanunToggle"
        description: "Toggles Qanun — tuner, metronome, maqams and practice"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "qanun"

        function open(tab: string): void {
            root.requestOpen(tab);
        }

        function close(): void {
            root.requestClose();
        }

        function toggle(): void {
            root.requestToggle();
        }

        function tab(name: string): void {
            root.requestOpen(name);
        }

        function isOpen(): bool {
            return GlobalStates.qanunOpen;
        }

        function screenLocked(): bool {
            return GlobalStates.screenLocked;
        }

        function playNote(midi: int): void {
            QanunStore.playTone(midi, 1.2);
        }

        function stopAudio(): void {
            QanunStore.stopAllAudio();
        }

        function resetStats(): void {
            QanunStore.resetStats();
        }

        function resetEarStats(): void {
            QanunStore.resetEarTrainingStats();
        }

        function earMode(mode: string): void {
            QanunStore.setEarTraining({ mode: String(mode ?? "intervals") });
        }
    }
}
