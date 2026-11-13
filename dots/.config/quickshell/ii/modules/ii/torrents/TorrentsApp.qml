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
 * The torrent client in the shell: the keybind, the IPC target and the app window, a front
 * end for qBittorrent's web interface. Same shape as the Mixer app: the window is built when
 * the app opens and kept hidden for 30 s after it closes. The torrents themselves live in
 * qBittorrent, so closing the window stops nothing.
 */
Scope {
    id: root

    readonly property var tabIds: ["torrents", "search", "add", "settings"]

    function requestOpen(tab = ""): void {
        GlobalStates.openTorrentsApp(root.tabIds.includes(tab) ? tab : "");
    }

    function requestClose(): void {
        GlobalStates.torrentsOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.torrentsOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    RetainedLoader {
        requested: GlobalStates.torrentsOpen
        retainFor: 30000
        sourceComponent: TorrentsWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "torrentsToggle"
        description: "Toggles the torrent client"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "torrents"

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
