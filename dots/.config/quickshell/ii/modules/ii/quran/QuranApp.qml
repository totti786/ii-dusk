pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.modules.common
import "QuranQcf.js" as Qcf

/**
 * The Quran reader: its lifecycle and its ways in. Same shape as the mediator app, the open
 * state is GlobalStates.quranOpen and the overlay exists only while it is true.
 */
Scope {
    id: root

    function requestToggle(windowed = null): void {
        if (GlobalStates.quranOpen)
            GlobalStates.quranOpen = false;
        else
            GlobalStates.openQuranApp(windowed);
    }

    /// Outlives the overlay: hiding the reader leaves the recitation playing
    QuranPlayer { id: quranPlayer }
    Component.onCompleted: GlobalStates.quranPlayer = quranPlayer
    Component.onDestruction: GlobalStates.quranPlayer = null

    /// The Madani page data is parsed here at start, so the first open does not pay for it
    FileView {
        path: Config.options.quran.pageFonts ? Quickshell.env("HOME") + "/.local/share/ii-quran/qcf/pages.json" : ""
        onLoaded: {
            if (!Qcf.ready()) {
                try {
                    Qcf.set(text(), Quickshell.env("HOME") + "/.local/share/ii-quran/qcf/fonts");
                } catch (e) {
                    console.warn("[Quran] page data unreadable:", e);
                }
            }
        }
    }

    Loader {
        active: GlobalStates.quranOpen && !GlobalStates.quranWindowed
        sourceComponent: QuranOverlay {
            player: quranPlayer
            onCloseRequested: GlobalStates.quranOpen = false
            onWindowRequested: GlobalStates.quranWindowed = true
        }
    }

    Loader {
        active: GlobalStates.quranOpen && GlobalStates.quranWindowed
        sourceComponent: QuranWindow {
            player: quranPlayer
            onCloseRequested: GlobalStates.quranOpen = false
            onOverlayRequested: GlobalStates.quranWindowed = false
        }
    }

    GlobalShortcut {
        name: "quranWindowToggle"
        description: "Toggles the Quran reader as a window"
        onPressed: root.requestToggle(true)
    }

    GlobalShortcut {
        name: "quranToggle"
        description: "Toggles the Quran reader"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "quran"

        function toggle(): void {
            root.requestToggle();
        }

        function open(): void {
            GlobalStates.openQuranApp();
        }

        /// Open as an ordinary window
        function window(): void {
            GlobalStates.openQuranApp(true);
        }

        /// Open as the full-screen overlay
        function overlay(): void {
            GlobalStates.openQuranApp(false);
        }

        function close(): void {
            GlobalStates.quranOpen = false;
        }

        /// Pause or resume the recitation without opening the reader
        function togglePlay(): void {
            quranPlayer.toggle();
        }

        /// Stop the recitation
        function stop(): void {
            quranPlayer.stop();
        }

        /// Open on an ayah ("2:255") and select it
        function goto(ref: string): void {
            GlobalStates.quranPendingPlay = false;
            GlobalStates.quranPendingKey = ref;
            GlobalStates.openQuranApp(GlobalStates.quranOpen ? GlobalStates.quranWindowed : null);
        }

        /// Open on an ayah with its tafsir showing
        function tafsir(ref: string): void {
            GlobalStates.quranPendingPlay = false;
            GlobalStates.quranPendingTafsir = true;
            GlobalStates.quranPendingKey = ref;
            GlobalStates.openQuranApp(GlobalStates.quranOpen ? GlobalStates.quranWindowed : null);
        }

        /// Open on an ayah and recite from it
        function play(ref: string): void {
            GlobalStates.quranPendingPlay = true;
            GlobalStates.quranPendingKey = ref;
            GlobalStates.openQuranApp(GlobalStates.quranOpen ? GlobalStates.quranWindowed : null);
        }
    }
}
