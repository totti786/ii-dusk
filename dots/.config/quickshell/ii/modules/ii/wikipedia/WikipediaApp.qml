pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.services

/** The Wikipedia app: keybind, IPC target and window. */
Scope {
    id: root

    function requestOpen(): void {
        GlobalStates.openWikipediaApp();
    }

    function requestClose(): void {
        GlobalStates.wikipediaOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.wikipediaOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    Loader {
        active: GlobalStates.wikipediaOpen
        sourceComponent: WikipediaWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "wikipediaToggle"
        description: "Toggles Wikipedia"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "wikipedia"

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
            WikipediaService.search(query);
            // The service owns the requested tab before the window is created. This keeps
            // an IPC search from racing the content frame's initial state consumption.
            root.requestOpen();
        }

        function article(title: string): void {
            WikipediaService.open(title);
            root.requestOpen();
        }

        function random(): void {
            WikipediaService.random();
            root.requestOpen();
        }

        function language(languageCode: string): void {
            if (WikipediaService.setLanguage(languageCode))
                root.requestOpen();
        }
    }
}
