pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common

/**
 * The island-facing voice activity.
 *
 * Discordo Voice is the explicit, standalone owner. The older Discord/Vesktop
 * bridge is loaded only after this session has actually seen a Discord client;
 * opening the Discordo applet therefore cannot wake the desktop bridge.
 */
Singleton {
    id: root

    readonly property bool standaloneJoined: DiscordoVoiceService.joined === true
    readonly property bool desktopSeen: GlobalStates.discordClientSeen === true
    readonly property bool standalone: root.standaloneJoined
    readonly property bool isStandalone: root.standaloneJoined

    // A Loader keeps the desktop bridge out of the object graph until the
    // existing Discord client has been observed. Its singleton starts its own
    // RPC process from Component.onCompleted, so this gate is intentional.
    Loader {
        id: desktopLoader
        active: root.desktopSeen
        sourceComponent: Component {
            QtObject {
                readonly property var service: DiscordVoice
            }
        }
    }

    readonly property var desktopService: desktopLoader.item?.service ?? null
    readonly property bool desktopInVoice: root.desktopSeen
        && root.desktopService?.inVoice === true
    readonly property bool inVoice: root.standaloneJoined || root.desktopInVoice
    readonly property bool active: root.inVoice
    readonly property bool connected: root.standaloneJoined
        ? DiscordoVoiceService.connected : root.desktopInVoice
            && root.desktopService?.status !== "disconnected"
    readonly property bool operationBusy: root.standaloneJoined
        ? DiscordoVoiceService.operationBusy : false
    readonly property bool busy: root.operationBusy
    readonly property string sourceKind: root.standaloneJoined ? "discordo"
        : root.desktopInVoice ? "desktop" : ""
    readonly property string status: root.standaloneJoined
        ? "joined" : (root.desktopService?.status ?? "")
    readonly property string backendLabel: root.standaloneJoined ? "Discordo"
        : (root.desktopService?.backendLabel ?? "")
    readonly property string backend: root.standaloneJoined ? "discordo"
        : (root.desktopService?.backend ?? "")
    readonly property bool muted: root.standaloneJoined
        ? DiscordoVoiceService.muted : (root.desktopService?.muted ?? false)
    readonly property bool deafened: root.standaloneJoined
        ? DiscordoVoiceService.deafened : (root.desktopService?.deafened ?? false)

    readonly property var channel: root.standaloneJoined
        ? ({
            id: DiscordoVoiceService.joinedChannelId,
            guild_id: DiscordoVoiceService.joinedGuildId,
            name: DiscordoVoiceService.joinedChannelName || "Voice channel"
        })
        : (root.desktopInVoice ? root.desktopService.channel : null)

    readonly property var participants: {
        if (root.standaloneJoined) {
            const speaking = {};
            for (const id of DiscordoVoiceService.speakingIds ?? [])
                speaking[String(id)] = true;
            return (DiscordoVoiceService.participants ?? []).map(value => {
                const item = Object.assign({}, value ?? {});
                item.id = String(item.id ?? "");
                item.name = String(item.name ?? item.nick ?? item.id ?? "Participant");
                item.nick = String(item.nick ?? item.name);
                item.speaking = item.speaking === true || speaking[item.id] === true;
                item.volume = DiscordoVoiceService.userVolume(item.id);
                item.localMute = item.volume <= 0;
                return item;
            });
        }
        if (root.desktopInVoice)
            return root.desktopService.participants ?? [];
        return [];
    }

    readonly property var currentUser: {
        if (root.standaloneJoined) {
            // The helper marks the self voice state when the account is present;
            // this also works with preview/native fixtures that provide `self`.
            return root.participants.find(user => user?.self === true) ?? {};
        }
        return root.desktopInVoice ? (root.desktopService.currentUser ?? {}) : {};
    }

    function setMuted(value): void {
        if (root.standaloneJoined)
            DiscordoVoiceService.setMuted(value === true);
        else if (root.desktopInVoice)
            root.desktopService.setMuted(value === true);
    }

    function setDeafened(value): void {
        if (root.standaloneJoined)
            DiscordoVoiceService.setDeafened(value === true);
        else if (root.desktopInVoice)
            root.desktopService.setDeafened(value === true);
    }

    function leave(): void {
        if (root.standaloneJoined)
            DiscordoVoiceService.leave();
    }

    function openApplet(): void {
        GlobalStates.openDiscordoVoiceApp();
    }

    function openChannels(): void {
        root.openApplet();
    }

    function open(): void { root.openApplet(); }
    function openApp(): void { root.openApplet(); }
    function openPicker(): void { root.openApplet(); }
    function openChannelPicker(): void { root.openApplet(); }

    /** Camera streams of the standalone call: person id to the url the helper serves it on. The desktop bridge has none. */
    readonly property var videoUrls: root.standaloneJoined ? (DiscordoVoiceService.remoteVideo ?? ({})) : ({})

    /** The stream to play for this person, or an empty string when their camera is off. */
    function videoUrl(user): string {
        return String(root.videoUrls[String(user?.id ?? "")] ?? "");
    }

    function avatarUrl(user, size = 64): string {
        const direct = String(user?.avatar_url ?? "");
        if (direct.length > 0)
            return direct;
        if (root.desktopInVoice && root.desktopService
                && typeof root.desktopService.avatarUrl === "function")
            return root.desktopService.avatarUrl(user, size);
        return "";
    }

    // ── What the game overlay widget needs (it was written against the desktop bridge) ──
    readonly property string errorMessage: root.standaloneJoined ? DiscordoVoiceService.errorMessage
        : (root.desktopService?.errorMessage ?? "")
    readonly property bool isVencordClient: root.standaloneJoined ? false : (root.desktopService?.isVencordClient ?? false)
    readonly property bool companionOutdated: root.standaloneJoined ? false : (root.desktopService?.companionOutdated ?? false)
    readonly property string selfId: String(root.currentUser?.id ?? "")
    readonly property bool selfSpeaking: root.selfId !== ""
        && root.participants.some(user => String(user?.id ?? "") === root.selfId && user?.speaking === true)
    function recheck(): void { if (root.desktopService) root.desktopService.recheck(); }
    function authorizeAfterFocusRelease(): void { if (root.desktopService) root.desktopService.authorizeAfterFocusRelease(); }

    // Per-person volume (Discord's 0-200 scale) and "muted for you", which is volume 0 here
    readonly property bool supportsUserVoice: root.standaloneJoined ? DiscordoVoiceService.audioSupported
        : (root.desktopService?.supportsUserVoice ?? false)
    function setUserVolume(userId, volume): void {
        if (root.standaloneJoined) DiscordoVoiceService.setUserVolume(userId, volume);
        else if (root.desktopService) root.desktopService.setUserVolume(userId, volume);
    }
    function setUserLocalMute(userId, value): void {
        if (root.standaloneJoined) DiscordoVoiceService.setUserVolume(userId, value === true ? 0 : 100);
        else if (root.desktopService) root.desktopService.setUserLocalMute(userId, value);
    }

    // Push to talk / voice activity. The standalone call binds a compositor key to its GlobalShortcut.
    // Standalone: off until a compositor key is bound to quickshell:discordoVoicePtt (none is today), or
    // the switch would leave the mic muted with nothing to open it.
    readonly property bool supportsInputMode: root.standaloneJoined ? false : (root.desktopService?.supportsInputMode ?? false)
    readonly property bool pushToTalk: root.standaloneJoined ? DiscordoVoiceService.pushToTalk
        : (root.desktopService?.pushToTalk ?? false)
    readonly property string pttShortcut: root.standaloneJoined ? "" : (root.desktopService?.pttShortcut ?? "")
    function togglePushToTalk(): void {
        if (root.standaloneJoined) DiscordoVoiceService.setPushToTalk(!DiscordoVoiceService.pushToTalk);
        else if (root.desktopService) root.desktopService.togglePushToTalk();
    }

    // Rows for the widget's Repeater: one `participant` role per person, like the desktop bridge's model
    ListModel { id: ownRoster }
    readonly property var participantModel: root.standaloneJoined ? ownRoster
        : (root.desktopService?.participantModel ?? ownRoster)
    readonly property int participantCount: root.participantModel.count
    function _syncRoster(): void {
        const users = root.standaloneJoined ? root.participants : [];
        const ids = new Set(users.map(user => String(user.id)));
        for (let i = ownRoster.count - 1; i >= 0; --i)
            if (!ids.has(String(ownRoster.get(i).participant?.id ?? "")))
                ownRoster.remove(i);
        for (const user of users) {
            let at = -1;
            for (let i = 0; i < ownRoster.count; ++i)
                if (String(ownRoster.get(i).participant?.id ?? "") === String(user.id)) { at = i; break; }
            if (at >= 0) ownRoster.setProperty(at, "participant", user);
            else ownRoster.append({ participant: user });
        }
    }

    // Join and leave toasts for the standalone call. The first roster after joining is the baseline,
    // so entering a full room stays quiet; your own entry never produces one.
    ListModel { id: ownNotices }
    readonly property var noticeModel: root.standaloneJoined ? ownNotices
        : (root.desktopService?.noticeModel ?? ownNotices)
    readonly property int noticeExitDuration: 260
    property var _noticeKnown: null
    property int _noticeSerial: 0
    function _diffNotices(): void {
        if (!root.standaloneJoined) { root._noticeKnown = null; return; }
        const now = new Map(root.participants.map(user => [String(user.id), user]));
        const before = root._noticeKnown;
        root._noticeKnown = now;
        if (before === null || !(Config.options?.overlay?.discordVoice?.joinLeaveNotices ?? true))
            return;
        for (const [id, user] of now)
            if (id !== root.selfId && !before.has(id)) root._pushNotice("join", user);
        for (const [id, user] of before)
            if (id !== root.selfId && !now.has(id)) root._pushNotice("leave", user);
    }
    function _pushNotice(kind, user): void {
        ownNotices.append({
            key: ++root._noticeSerial, kind: kind, userId: String(user?.id ?? ""),
            name: String(user?.nick || user?.name || "Someone"), avatar: root.avatarUrl(user, 64),
            born: Date.now(), leaving: false, context: "", text: "", lifetime: 4000
        });
        while (ownNotices.count > 4) ownNotices.remove(0);
        noticeClock.start();
    }
    /// A DM or @mention toast from the standalone chat, shown in the overlay widget while you are in a call
    function pushMessageNotice(m): void {
        if (!root.standaloneJoined)
            return;
        const where = m.guild ? `#${m.channel} · ${m.guild}` : "";
        const preview = Config.options?.overlay?.discordVoice?.messagePreview ?? true;
        ownNotices.append({
            key: ++root._noticeSerial, kind: String(m.kind === "dm" ? "dm" : "mention"), userId: String(m.author?.id ?? ""),
            name: String(m.author?.name ?? "Someone"), avatar: String(m.author?.avatar ?? ""),
            born: Date.now(), leaving: false, context: where, text: preview ? String(m.text ?? "") : "", lifetime: 7000
        });
        while (ownNotices.count > 4) ownNotices.remove(0);
        noticeClock.start();
    }

    Timer {
        id: noticeClock
        interval: 250
        repeat: true
        onTriggered: {
            const now = Date.now();
            for (let i = ownNotices.count - 1; i >= 0; --i) {
                const entry = ownNotices.get(i);
                const age = now - entry.born;
                if (age >= entry.lifetime + root.noticeExitDuration) ownNotices.remove(i);
                else if (age >= entry.lifetime && !entry.leaving) ownNotices.setProperty(i, "leaving", true);
            }
            if (ownNotices.count === 0) stop();
        }
    }
    onParticipantsChanged: { root._syncRoster(); root._diffNotices(); }
}
