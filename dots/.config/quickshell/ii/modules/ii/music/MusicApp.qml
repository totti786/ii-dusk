pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Music in the shell: the keybind, the IPC target and the app window. Same shape as the
 * Downloads and App usage apps: the window is built when the app opens and kept hidden
 * for 30 s after it closes. Playback does not depend on it, it lives in a daemon.
 */
Scope {
    id: root

    readonly property var tabIds: ["home", "search", "library", "queue"]

    function requestOpen(tab = ""): void {
        GlobalStates.openMusicApp(root.tabIds.includes(tab) ? tab : "");
    }

    function requestClose(): void {
        GlobalStates.musicOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.musicOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    RetainedLoader {
        requested: GlobalStates.musicOpen
        retainFor: 30000
        sourceComponent: MusicWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "musicToggle"
        description: "Toggles the Music app"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "music"

        function toggle(): void {
            root.requestToggle();
        }

        function open(tab: string): void {
            root.requestOpen(tab);
        }

        function close(): void {
            root.requestClose();
        }

        function playpause(): void {
            MusicService.toggle();
        }

        function next(): void {
            MusicService.next();
        }

        function prev(): void {
            MusicService.prev();
        }
    }
}
