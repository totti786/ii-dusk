pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.services

/**
 * The Anki reviewer's lifecycle and entry points.
 *
 * The window is built only while GlobalStates.ankiOpen is true. Closing it releases the
 * collection so Anki desktop can open the profile normally.
 */
Scope {
    id: root

    /// Test/development hook; the app leaves this empty.
    property string collectionOverride: ""

    function requestOpen(deckId = ""): void {
        GlobalStates.openAnkiApp(deckId);
    }

    function requestClose(): void {
        GlobalStates.ankiOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.ankiOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    Loader {
        active: GlobalStates.ankiOpen
        sourceComponent: AnkiWindow {
            collectionOverride: root.collectionOverride
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "ankiToggle"
        description: "Toggles the built-in Anki reviewer"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "anki"

        function open(deckId: string): void {
            root.requestOpen(deckId);
        }

        function close(): void {
            root.requestClose();
        }

        function toggle(): void {
            root.requestToggle();
        }
    }
}
