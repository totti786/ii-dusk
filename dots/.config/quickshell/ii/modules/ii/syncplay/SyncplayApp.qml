pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.modules.common

/**
 * The Syncplay app: its lifecycle and its ways in.
 *
 * Same shape as the calculator: the open state is GlobalStates.syncplayAppOpen, so Search's
 * shell-app list and the IPC target both end in the same flag. The window is built only while
 * it is open. Closing it does not end a call: the session lives in its own process (see
 * SyncplayService) and the window attaches to it again on the next open.
 */
Scope {
    id: root

    function requestOpen(): void {
        GlobalStates.openSyncplayApp();
    }

    function requestClose(): void {
        GlobalStates.syncplayAppOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.syncplayAppOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    Loader {
        id: windowLoader
        active: GlobalStates.syncplayAppOpen
        sourceComponent: SyncplayWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "syncplayToggle"
        description: "Toggles Syncplay"
        onPressed: root.requestToggle()
    }

    GlobalShortcut {
        name: "syncplayOpen"
        description: "Opens Syncplay"
        onPressed: root.requestOpen()
    }

    GlobalShortcut {
        name: "syncplayClose"
        description: "Closes Syncplay"
        onPressed: root.requestClose()
    }

    IpcHandler {
        target: "syncplay"

        function open(): void {
            root.requestOpen();
        }

        function close(): void {
            root.requestClose();
        }

        function toggle(): void {
            root.requestToggle();
        }
    }
}
