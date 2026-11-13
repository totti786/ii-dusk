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
 * The sound mixer in the shell: the keybind, the IPC target and the app window, a native
 * stand-in for pavucontrol. Same shape as the Downloads app: the window is built when the
 * app opens and kept hidden for 30 s after it closes. Nothing depends on it, the volumes
 * live in PipeWire.
 */
Scope {
    id: root

    readonly property var tabIds: ["playback", "recording", "devices", "config"]

    function requestOpen(tab = ""): void {
        GlobalStates.openMixerApp(root.tabIds.includes(tab) ? tab : "");
    }

    function requestClose(): void {
        GlobalStates.mixerOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.mixerOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    RetainedLoader {
        requested: GlobalStates.mixerOpen
        retainFor: 30000
        sourceComponent: MixerWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "mixerToggle"
        description: "Toggles the sound mixer"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "mixer"

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
