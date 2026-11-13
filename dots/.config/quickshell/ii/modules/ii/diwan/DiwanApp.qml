pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs

/**
 * The poetry reader: its lifecycle and its ways in. Same shape as the Quran reader, the open
 * state is GlobalStates.diwanOpen and the overlay exists only while it is true.
 */
Scope {
    id: root

    Loader {
        active: GlobalStates.diwanOpen && !GlobalStates.diwanWindowed
        sourceComponent: DiwanOverlay {
            onCloseRequested: GlobalStates.diwanOpen = false
            onWindowRequested: GlobalStates.diwanWindowed = true
        }
    }

    Loader {
        active: GlobalStates.diwanOpen && GlobalStates.diwanWindowed
        sourceComponent: DiwanWindow {
            onCloseRequested: GlobalStates.diwanOpen = false
            onOverlayRequested: GlobalStates.diwanWindowed = false
        }
    }

    GlobalShortcut {
        name: "diwanToggle"
        description: "Toggles the poetry reader"
        onPressed: {
            if (GlobalStates.diwanOpen)
                GlobalStates.diwanOpen = false;
            else
                GlobalStates.openDiwanApp();
        }
    }

    GlobalShortcut {
        name: "diwanWindowToggle"
        description: "Toggles the poetry reader as a window"
        onPressed: {
            if (GlobalStates.diwanOpen)
                GlobalStates.diwanOpen = false;
            else
                GlobalStates.openDiwanApp(true);
        }
    }

    IpcHandler {
        target: "diwan"

        function toggle(): void {
            if (GlobalStates.diwanOpen)
                GlobalStates.diwanOpen = false;
            else
                GlobalStates.openDiwanApp();
        }

        function open(): void {
            GlobalStates.openDiwanApp();
        }

        /// Open as an ordinary window
        function window(): void {
            GlobalStates.openDiwanApp(true);
        }

        /// Open as the full-screen overlay
        function overlay(): void {
            GlobalStates.openDiwanApp(false);
        }

        function close(): void {
            GlobalStates.diwanOpen = false;
        }

        /// Open on a random poem
        function random(): void {
            GlobalStates.diwanPendingAction = "random";
            GlobalStates.openDiwanApp(GlobalStates.diwanOpen ? GlobalStates.diwanWindowed : null);
        }

        /// Open on a poem by its four-letter address
        function poem(slug: string): void {
            GlobalStates.diwanPendingSlug = slug;
            GlobalStates.openDiwanApp(GlobalStates.diwanOpen ? GlobalStates.diwanWindowed : null);
        }

        /// Open on a poem with one verse (counting from 1) scrolled to and picked
        function verse(slug: string, number: int): void {
            GlobalStates.diwanPendingVerse = number - 1;
            GlobalStates.diwanPendingSlug = slug;
            GlobalStates.openDiwanApp(GlobalStates.diwanOpen ? GlobalStates.diwanWindowed : null);
        }

        /// Open on the results of a search
        function search(query: string): void {
            GlobalStates.diwanPendingQuery = query;
            GlobalStates.openDiwanApp(GlobalStates.diwanOpen ? GlobalStates.diwanWindowed : null);
        }

        /// Open on the saved poems
        function saved(): void {
            GlobalStates.diwanPendingAction = "saved";
            GlobalStates.openDiwanApp(GlobalStates.diwanOpen ? GlobalStates.diwanWindowed : null);
        }
    }
}
