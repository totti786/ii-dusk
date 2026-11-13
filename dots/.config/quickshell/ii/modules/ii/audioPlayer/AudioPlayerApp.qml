pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs

/**
 * The audio player: the keybind, the IPC target and the window, built only while open.
 * `qs -c ii ipc call audioPlayer open <path>` plays a file (or a folder) in it.
 */
Scope {
    id: root

    function requestToggle(): void {
        GlobalStates.audioPlayerOpen = !GlobalStates.audioPlayerOpen;
    }

    // Built a few seconds after the shell starts and kept hidden while closed, so the
    // first open does not wait for the window to compile
    property bool warm: false
    Timer {
        interval: 5000
        running: true
        onTriggered: root.warm = true
    }

    Loader {
        active: root.warm || GlobalStates.audioPlayerOpen
        asynchronous: !GlobalStates.audioPlayerOpen
        sourceComponent: AudioPlayerWindow {
            onCloseRequested: GlobalStates.audioPlayerOpen = false
        }
    }

    GlobalShortcut {
        name: "audioPlayerToggle"
        description: "Toggles the Audio Player"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "audioPlayer"

        function open(path: string): void {
            GlobalStates.openAudioPlayerApp(path);
        }

        function rescan(): void {
            GlobalStates.audioPlayerRescan += 1;
        }

        function close(): void {
            GlobalStates.audioPlayerOpen = false;
        }

        function toggle(): void {
            root.requestToggle();
        }

        function isOpen(): bool {
            return GlobalStates.audioPlayerOpen;
        }
    }
}
