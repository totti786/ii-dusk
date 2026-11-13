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
 * Soundscapes, the ambient sound mixer: the keybind, the IPC target and the window, which
 * is built only while open (and kept a while for a quick reopen). The mix is played by a
 * detached daemon, so the IPC calls below work with the window closed and the sound goes
 * on after it closes.
 *
 *   qs -c ii ipc call soundscapes toggle|open|close
 *   qs -c ii ipc call soundscapes play|pause|togglePlay|stop|surprise
 *   qs -c ii ipc call soundscapes mix <id>        (a built-in or saved mix, e.g. rainy-cafe)
 *   qs -c ii ipc call soundscapes sound <id>      (turn one sound on or off, e.g. rain)
 *   qs -c ii ipc call soundscapes timer <minutes> (0 cancels)
 *   qs -c ii ipc call soundscapes volume <0-100>
 */
Scope {
    id: root

    readonly property var tabIds: ["sounds", "mix", "presets", "settings"]

    function requestOpen(tab = ""): void {
        GlobalStates.openSoundscapesApp(root.tabIds.includes(tab) ? tab : "");
    }

    function requestToggle(): void {
        if (GlobalStates.soundscapesOpen)
            GlobalStates.soundscapesOpen = false;
        else
            root.requestOpen();
    }

    RetainedLoader {
        requested: GlobalStates.soundscapesOpen
        retainFor: 30000
        sourceComponent: SoundscapesWindow {
            onCloseRequested: GlobalStates.soundscapesOpen = false
        }
    }

    GlobalShortcut {
        name: "soundscapesToggle"
        description: "Toggles the Soundscapes ambient mixer"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "soundscapes"

        function open(tab: string): void { root.requestOpen(tab); }
        function close(): void { GlobalStates.soundscapesOpen = false; }
        function toggle(): void { root.requestToggle(); }
        function isOpen(): bool { return GlobalStates.soundscapesOpen; }
        function info(id: string): void {
            GlobalStates.soundscapesPendingSound = id;
            root.requestOpen("sounds");
        }

        function play(): void { SoundscapesService.play(); }
        function pause(): void { SoundscapesService.pause(); }
        function togglePlay(): void { SoundscapesService.togglePlay(); }
        function stop(): void { SoundscapesService.stopAll(); }
        function surprise(): void { SoundscapesService.surprise(); }
        function download(): void { SoundscapesService.download(); }
        function mix(id: string): void { SoundscapesService.loadPreset(id); }
        function sound(id: string): void { SoundscapesService.toggle(id); }
        function timer(minutes: int): void { SoundscapesService.setTimer(minutes); }
        function volume(percent: int): void { SoundscapesService.setMaster(Math.max(0, Math.min(100, percent)) / 100); }
    }
}
