import QtQuick
import qs
import qs.services
import qs.modules.common

/**
 * Your microphone in a Discord call: tap to mute, right-click to deafen.
 *
 * Read through DiscordVoiceActivity, which owns the Discordo call and loads the desktop
 * bridge only once a Discord client has had a window (GlobalStates.discordClientSeen), so a
 * tile in the tray never starts it for someone who does not run Discord.
 */
QuickToggleModel {
    id: root

    readonly property bool armed: GlobalStates.discordClientSeen
    readonly property bool inCall: DiscordVoiceActivity.inVoice
    readonly property bool muted: root.inCall && DiscordVoiceActivity.muted
    readonly property bool deafened: root.inCall && DiscordVoiceActivity.deafened

    name: Translation.tr("Discord")
    available: root.inCall
    toggled: root.inCall && !root.muted && !root.deafened
    icon: root.deafened ? "headset_off" : (root.muted ? "mic_off" : "headset_mic")
    statusText: {
        if (!root.inCall)
            return Translation.tr("Not in a call");
        if (root.deafened)
            return Translation.tr("Deafened");
        if (root.muted)
            return Translation.tr("Muted");
        return DiscordVoiceActivity.channel?.name ?? Translation.tr("In a call");
    }
    tooltipText: Translation.tr("Discord voice | Click to mute, right-click to deafen")

    mainAction: () => {
        if (root.inCall)
            DiscordVoiceActivity.setMuted(!DiscordVoiceActivity.muted);
    }
    altAction: () => {
        if (root.inCall)
            DiscordVoiceActivity.setDeafened(!DiscordVoiceActivity.deafened);
    }
}
