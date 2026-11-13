pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common

/**
 * The Quick Share app: its lifecycle and its ways in. The open state is
 * GlobalStates.quickShareAppOpen, so Search's shell-app list and the IPC target end in the
 * same flag. The window is built only while open; the daemon keeps running without it.
 */
Scope {
    id: root

    function requestOpen(): void { GlobalStates.openQuickShareApp(); }
    function requestClose(): void { GlobalStates.quickShareAppOpen = false; }
    function requestToggle(): void {
        if (GlobalStates.quickShareAppOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    Loader {
        active: GlobalStates.quickShareAppOpen
        sourceComponent: QuickShareWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "quickShareToggle"
        description: "Toggles Quick Share"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "quickshare"
        function open(): void { root.requestOpen(); }
        function close(): void { root.requestClose(); }
        function toggle(): void { root.requestToggle(); }
        // Share files from anywhere (file manager, scripts): the island's bubble takes them and
        // lists the nearby phones to pick from.
        function share(path: string): void {
            QuickShareService.stage([path]);
        }
        function clear(): void { QuickShareService.pending = []; }
        function clipboard(): void { QuickShareService.shareClipboard(); }
        function screenshot(): void { QuickShareService.shareLastScreenshot(); }
    }
}
