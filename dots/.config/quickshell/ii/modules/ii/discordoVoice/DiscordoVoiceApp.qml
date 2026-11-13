pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.services

/** Discordo Voice applet: the window is disposable while the service is retained. */
Scope {
    id: root

    function requestOpen(): void {
        GlobalStates.openDiscordoVoiceApp();
    }

    function requestClose(): void {
        GlobalStates.discordoVoiceOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.discordoVoiceOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    function toggleChat(): void {
        if (GlobalStates.discordoChatOpen)
            root.requestClose();
        else
            GlobalStates.openDiscordoChat();
    }

    Loader {
        active: GlobalStates.discordoVoiceOpen
        sourceComponent: DiscordoVoiceWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "discordoChatToggle"
        description: "Toggles Discord chat"
        onPressed: root.toggleChat()
    }

    GlobalShortcut {
        name: "discordoVoiceToggle"
        description: "Toggles Discordo Voice"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "discordoVoice"

        function open(): void {
            root.requestOpen();
        }

        function close(): void {
            root.requestClose();
        }

        function toggle(): void {
            root.requestToggle();
        }

        function chat(): void {
            GlobalStates.openDiscordoChat();
        }

        function chatToggle(): void {
            root.toggleChat();
        }
    }
}
