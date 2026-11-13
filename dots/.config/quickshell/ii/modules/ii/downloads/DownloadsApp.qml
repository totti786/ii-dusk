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
 * Downloads in the shell: the keybinds, the IPC target and the app window, a front for
 * yt-dlp. Same shape as the App usage app: the window is built when the app opens and
 * kept hidden for 30 s after it closes. The downloads do not depend on it, they run in
 * detached workers.
 */
Scope {
    id: root

    readonly property var tabIds: ["download", "queue", "history"]

    function requestOpen(tab = ""): void {
        GlobalStates.openDownloadsApp(root.tabIds.includes(tab) ? tab : "");
    }

    function requestClose(): void {
        GlobalStates.downloadsOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.downloadsOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    RetainedLoader {
        requested: GlobalStates.downloadsOpen
        retainFor: 30000
        sourceComponent: DownloadsWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "downloadsToggle"
        description: "Toggles the Downloads app"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "downloads"

        function toggle(): void {
            root.requestToggle();
        }

        function open(tab: string): void {
            root.requestOpen(tab);
        }

        function close(): void {
            root.requestClose();
        }
    }
}
