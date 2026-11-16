pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.services

/** The YouTube app: keybind, IPC target and window. */
Scope {
    id: root

    function requestOpen(): void {
        GlobalStates.openYouTubeApp();
    }

    function requestClose(): void {
        GlobalStates.youtubeOpen = false;
        YouTubeService.cancel();
    }

    function requestToggle(): void {
        if (GlobalStates.youtubeOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    Loader {
        id: deferredWindowLoader
        active: GlobalStates.youtubeOpen
        source: "YouTubeWindow.qml"

        Connections {
            target: deferredWindowLoader.item
            function onCloseRequested() { root.requestClose() }
        }
    }

    GlobalShortcut {
        name: "youTubeToggle"
        description: "Toggles YouTube"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "youtube"

        function open(): void {
            root.requestOpen();
        }

        function close(): void {
            root.requestClose();
        }

        function toggle(): void {
            root.requestToggle();
        }

        function search(query: string): void {
            root.requestOpen();
            YouTubeService.search(query);
        }

        function play(url: string): void {
            root.requestOpen();
            YouTubeService.playFromText(url);
        }
    }
}
