pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.modules.common

/**
 * The mediator browser: its lifecycle and its ways in. Same shape as the calculator app,
 * the open state is GlobalStates.mediatorAppOpen and the window exists only while it is true.
 * Tabs: all, anime, shows, movies, and streaming.
 */
Scope {
    id: root

    function requestOpen(tab = "", windowed = null): void {
        GlobalStates.openMediatorApp(tab === "" || tab === "all" ? "all" : tab, windowed);
    }

    function requestClose(): void {
        GlobalStates.mediatorAppOpen = false;
    }

    function requestToggle(tab = "", windowed = null): void {
        if (GlobalStates.mediatorAppOpen)
            root.requestClose();
        else
            root.requestOpen(tab, windowed);
    }

    Loader {
        active: GlobalStates.mediatorAppOpen && !GlobalStates.mediatorWindowed
        sourceComponent: MediatorOverlay {
            onCloseRequested: root.requestClose()
            onWindowRequested: GlobalStates.mediatorWindowed = true
        }
    }

    Loader {
        active: GlobalStates.mediatorAppOpen && GlobalStates.mediatorWindowed
        sourceComponent: MediatorWindow {
            onCloseRequested: root.requestClose()
            onOverlayRequested: GlobalStates.mediatorWindowed = false
        }
    }

    GlobalShortcut {
        name: "mediatorToggle"
        description: "Toggles the mediator browser"
        onPressed: root.requestToggle()
    }

    GlobalShortcut {
        name: "mediatorWindowToggle"
        description: "Toggles the mediator as a window"
        onPressed: root.requestToggle("", true)
    }

    IpcHandler {
        target: "mediator"

        function open(tab: string): void {
            root.requestOpen(tab);
        }

        function close(): void {
            root.requestClose();
        }

        function toggle(tab: string): void {
            root.requestToggle(tab);
        }

        function window(tab: string): void {
            root.requestOpen(tab, true);
        }

        /// Open the window on one title's page, by id (mediator list --tsv)
        function title(id: string): void {
            GlobalStates.openMediatorApp("", true, id);
        }

        function overlay(tab: string): void {
            root.requestOpen(tab, false);
        }
    }
}

