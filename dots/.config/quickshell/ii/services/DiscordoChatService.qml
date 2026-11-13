pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.modules.common
import qs.services

/**
 * Text chat for the standalone Discordo helper: the chat list, a channel's history and live messages, unread badges,
 * toasts, and the write side. The helper owns the gateway and shapes every message (see its README); this is only
 * state for the chat window, plus the shell notifications for DMs and mentions.
 *
 * Messages live in `messageModel` for the one open channel, oldest first. Nothing else is kept.
 */
Singleton {
    id: root

    readonly property var voice: DiscordoVoiceService
    readonly property bool supported: root.voice.messagesSupported
    readonly property bool ready: root.supported && root.voice.connected

    // ── Lists ──────────────────────────────────────────────────────────────────────────
    property var dms: []
    property var channelsByGuild: ({})
    /** channel id -> { guild_id, unread, mentions, muted } for everything with a badge */
    property var unreads: ({})
    readonly property int totalMentions: {
        let n = 0;
        for (const id in root.unreads) {
            const u = root.unreads[id];
            if (!u.muted)
                n += Number(u.mentions || 0);
        }
        return n;
    }
    readonly property bool anyUnread: {
        for (const id in root.unreads) {
            const u = root.unreads[id];
            if (!u.muted && (u.unread || u.mentions > 0))
                return true;
        }
        return false;
    }

    function guildBadge(guildId): var {
        let unread = false, mentions = 0;
        for (const id in root.unreads) {
            const u = root.unreads[id];
            if (String(u.guild_id) !== String(guildId) || u.muted)
                continue;
            unread = unread || u.unread === true || u.mentions > 0;
            mentions += Number(u.mentions || 0);
        }
        return { "unread": unread, "mentions": mentions };
    }

    // ── The open channel ───────────────────────────────────────────────────────────────
    property string guildId: Persistent.ready ? Persistent.states.discordoVoice.chatGuild : ""
    property string channelId: Persistent.ready ? Persistent.states.discordoVoice.chatChannel : ""
    readonly property alias messageModel: messages
    property bool loadingHistory: false
    property bool hasMore: false
    property bool historyReady: false
    property string errorMessage: ""
    /** user id -> { name, until } of people typing in the open channel */
    property var typing: ({})
    readonly property var typingNames: {
        const now = root.typingClock;
        const names = [];
        for (const id in root.typing) {
            if (root.typing[id].until > now)
                names.push(root.typing[id].name || Translation.tr("Someone"));
        }
        return names;
    }
    property real typingClock: Date.now()
    property var pins: []
    property var searchResults: []
    property bool searching: false

    ListModel {
        id: messages
        dynamicRoles: true
    }

    function _send(cmd, extra = {}): bool {
        return root.voice._queue(Object.assign({ "cmd": cmd }, extra), false);
    }

    // ── Opening things ─────────────────────────────────────────────────────────────────
    function connectIfNeeded(): void {
        if (!root.voice.connected && !root.voice.operationBusy && root.voice.signedIn !== false)
            root.voice.connect();
    }

    function refreshLists(): void {
        if (!root.ready)
            return;
        root._send("chat_dms");
        root._send("chat_unreads");
        if (root.guildId !== "" && root.guildId !== "0")
            root._send("chat_channels", { "guild_id": root.guildId });
    }

    function selectGuild(id): void {
        root.guildId = String(id);
        if (Persistent.ready)
            Persistent.states.discordoVoice.chatGuild = root.guildId;
        if (root.guildId !== "0" && root.guildId !== "")
            root._send("chat_channels", { "guild_id": root.guildId });
        else
            root._send("chat_dms");
    }

    function openChannel(channel, guild = ""): void {
        const id = String(channel);
        if (id === "")
            return;
        if (guild !== "")
            root.guildId = String(guild);
        root.channelId = id;
        if (Persistent.ready) {
            Persistent.states.discordoVoice.chatChannel = id;
            Persistent.states.discordoVoice.chatGuild = root.guildId;
        }
        messages.clear();
        root.hasMore = false;
        root.historyReady = false;
        root.typing = ({});
        root.pins = [];
        root.searchResults = [];
        root.errorMessage = "";
        root.loadingHistory = true;
        root._send("chat_open", { "channel_id": id });
    }

    function closeChannel(): void {
        root._send("chat_close");
    }

    function loadOlder(): void {
        if (root.loadingHistory || !root.hasMore || messages.count === 0)
            return;
        root.loadingHistory = true;
        root._send("chat_history", { "channel_id": root.channelId, "before": String(messages.get(0).id) });
    }

    function markRead(): void {
        const u = root.unreads[root.channelId];
        if (root.channelId !== "" && u && (u.unread || u.mentions > 0))
            root._send("chat_ack", { "channel_id": root.channelId });
    }

    // ── Writing ────────────────────────────────────────────────────────────────────────
    function sendMessage(text, replyTo = "", ping = true, paths = []): void {
        root._send("chat_send", { "channel_id": root.channelId, "content": text, "reply_to": replyTo, "ping": ping, "paths": paths });
    }

    function editMessage(id, text): void {
        root._send("chat_edit", { "channel_id": root.channelId, "message_id": String(id), "content": text });
    }

    function deleteMessage(id): void {
        root._send("chat_delete", { "channel_id": root.channelId, "message_id": String(id) });
    }

    function react(id, emoji, add): void {
        root._send("chat_react", { "channel_id": root.channelId, "message_id": String(id), "emoji": emoji, "value": add });
    }

    function reactionKey(emoji): string {
        return emoji.id ? `${emoji.name}:${emoji.id}` : String(emoji.name);
    }

    function sendTyping(): void {
        root._send("chat_typing", { "channel_id": root.channelId });
    }

    function loadPins(): void {
        root._send("chat_pins", { "channel_id": root.channelId });
    }

    function search(query): void {
        const q = String(query).trim();
        if (q === "") {
            root.searchResults = [];
            root.searching = false;
            return;
        }
        root.searching = true;
        root._send("chat_search", { "channel_id": root.channelId, "guild_id": root.guildId === "0" ? "" : root.guildId, "query": q });
    }

    // ── Notifications on/off ───────────────────────────────────────────────────────────
    readonly property bool keepConnected: Persistent.ready && Persistent.states.discordoVoice.chatNotices
    function setNotices(on): void {
        if (Persistent.ready)
            Persistent.states.discordoVoice.chatNotices = on === true;
        if (on === true)
            root.connectIfNeeded();
        else if (root.ready)
            root._send("chat_config", { "value": false });
    }

    onKeepConnectedChanged: if (root.keepConnected) root.connectIfNeeded()

    // The first connection after the shell starts, then a patient retry if the helper or Discord goes away.
    property int _retries: 0
    Timer {
        id: startup
        interval: 6000
        running: root.keepConnected && !root.voice.connected
        repeat: true
        onTriggered: {
            if (root.voice.operationBusy || root.voice.connectionState === "connecting"
                    || root.voice.connectionState === "starting" || root.voice.authRequired)
                return;
            root._retries += 1;
            interval = Math.min(300000, 6000 * Math.pow(2, Math.min(root._retries, 6)));
            root.connectIfNeeded();
        }
    }

    Connections {
        target: root.voice
        function onConnectedChanged() {
            if (!root.voice.connected)
                return;
            root._retries = 0;
            startup.interval = 6000;
            root._send("chat_config", { "value": root.keepConnected });
            root.refreshLists();
            if (root.channelId !== "" && GlobalStates.discordoChatOpen)
                root.openChannel(root.channelId, root.guildId);
        }
        function onChatLine(message) {
            root.handleLine(message);
        }
    }

    Connections {
        target: GlobalStates
        function onDiscordoChatOpenChanged() {
            if (GlobalStates.discordoChatOpen) {
                root.connectIfNeeded();
                if (root.ready)
                    root.refreshLists();
            } else {
                root.closeChannel();
            }
        }
    }

    Connections {
        target: Notifications
        function onInternalActionInvoked(identifier, notificationId, payload) {
            if (identifier === "__qs_discordo_open")
                GlobalStates.openDiscordoChat(String(payload?.channel_id ?? ""), String(payload?.guild_id ?? ""));
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: Object.keys(root.typing).length > 0
        onTriggered: root.typingClock = Date.now()
    }

    // ── From the helper ────────────────────────────────────────────────────────────────
    function _indexOf(id): int {
        for (let i = messages.count - 1; i >= 0; --i) {
            if (String(messages.get(i).id) === String(id))
                return i;
        }
        return -1;
    }

    /// Lines reach here through a signal, which hands lists over as array-likes that fail Array.isArray.
    function _list(value): var {
        return value !== null && value !== undefined && typeof value.length === "number" && typeof value !== "string"
            ? Array.from(value) : [];
    }

    function _setUnread(channel, entry): void {
        const next = Object.assign({}, root.unreads);
        if (entry.unread || entry.mentions > 0)
            next[channel] = entry;
        else
            delete next[channel];
        root.unreads = next;
        // the lists carry their own badges: patch them so they update without a reload
        const patch = list => list.map(c => String(c.id) === channel
            ? Object.assign({}, c, { "unread": entry.unread, "mentions": entry.mentions, "muted": entry.muted }) : c);
        root.dms = patch(root.dms);
        const g = Object.assign({}, root.channelsByGuild);
        for (const gid in g)
            g[gid] = patch(g[gid]);
        root.channelsByGuild = g;
    }

    function _append(message): void {
        if (root._indexOf(message.id) >= 0)
            return;
        messages.append(message);
    }

    function _flash(text): void {
        root.errorMessage = text;
        errorClear.restart();
    }

    Timer {
        id: errorClear
        interval: 6000
        onTriggered: root.errorMessage = ""
    }

    function handleLine(m): void {
        switch (String(m.type)) {
        case "chat_dms":
            root.dms = root._list(m.dms);
            break;
        case "chat_channels": {
            const next = Object.assign({}, root.channelsByGuild);
            next[String(m.guild_id)] = root._list(m.channels);
            root.channelsByGuild = next;
            break;
        }
        case "chat_unreads":
            root.unreads = m.unreads ?? ({});
            break;
        case "chat_unread": {
            const batch = (m.channels !== undefined ? root._list(m.channels) : [m]);
            for (const c of batch)
                root._setUnread(String(c.channel_id), { "guild_id": String(c.guild_id), "unread": c.unread === true,
                    "mentions": Number(c.mentions || 0), "muted": c.muted === true });
            break;
        }
        case "chat_history": {
            if (String(m.channel_id) !== root.channelId)
                break;
            const list = root._list(m.messages);
            root.loadingHistory = false;
            root.hasMore = m.more === true;
            if (m.initial === true) {
                messages.clear();
                for (const item of list)
                    messages.append(item);
                root.historyReady = true;
                root.markRead();
            } else {
                // older page: goes in front, in order
                for (let i = list.length - 1; i >= 0; --i) {
                    if (root._indexOf(list[i].id) < 0)
                        messages.insert(0, list[i]);
                }
            }
            break;
        }
        case "chat":
            root._handleLive(m);
            break;
        case "chat_sent":
            if (String(m.channel_id) === root.channelId && m.message)
                root._append(m.message);
            break;
        case "chat_error":
            if (String(m.channel_id) === root.channelId || String(m.channel_id) === "0" || m.channel_id === undefined) {
                root.loadingHistory = false;
                root.searching = false;
                root._flash(String(m.message || ""));
            }
            break;
        case "chat_typing":
            if (String(m.channel_id) === root.channelId) {
                const t = Object.assign({}, root.typing);
                t[String(m.user_id)] = { "name": String(m.name || ""), "until": Date.now() + 9000 };
                root.typing = t;
                root.typingClock = Date.now();
            }
            break;
        case "chat_pins":
            if (String(m.channel_id) === root.channelId)
                root.pins = root._list(m.messages).reverse();
            break;
        case "chat_search":
            if (String(m.channel_id) === root.channelId) {
                root.searchResults = root._list(m.messages);
                root.searching = false;
            }
            break;
        case "notice":
            root._notice(m);
            break;
        }
    }

    function _handleLive(m): void {
        switch (String(m.event)) {
        case "create": {
            const message = m.message;
            if (String(message.channel_id) !== root.channelId)
                break;
            root._append(message);
            // someone who just wrote has stopped typing
            if (root.typing[message.author.id]) {
                const t = Object.assign({}, root.typing);
                delete t[message.author.id];
                root.typing = t;
            }
            break;
        }
        case "update": {
            const i = root._indexOf(m.message.id);
            if (i < 0)
                break;
            for (const key in m.message) {
                if (key !== "id" && key !== "channel_id" && key !== "guild_id")
                    messages.setProperty(i, key, m.message[key]);
            }
            break;
        }
        case "delete":
            for (const id of m.ids ?? []) {
                const i = root._indexOf(id);
                if (i >= 0)
                    messages.remove(i);
            }
            break;
        case "reaction":
            root._reaction(m);
            break;
        case "pins":
            if (String(m.channel_id) === root.channelId)
                root.loadPins();
            break;
        }
    }

    function _reaction(m): void {
        const i = root._indexOf(m.message_id);
        if (i < 0)
            return;
        let list = (messages.get(i).reactions ?? []).slice();
        const key = root.reactionKey(m.emoji);
        const at = list.findIndex(r => root.reactionKey(r.emoji) === key);
        if (m.op === "clear") {
            list = [];
        } else if (m.op === "clear_emoji") {
            if (at >= 0)
                list.splice(at, 1);
        } else if (m.op === "add") {
            if (at >= 0)
                list[at] = Object.assign({}, list[at], { "count": list[at].count + 1, "me": list[at].me || m.mine === true });
            else
                list.push({ "emoji": m.emoji, "count": 1, "me": m.mine === true });
        } else if (m.op === "remove" && at >= 0) {
            const count = list[at].count - 1;
            if (count <= 0)
                list.splice(at, 1);
            else
                list[at] = Object.assign({}, list[at], { "count": count, "me": m.mine === true ? false : list[at].me });
        }
        messages.setProperty(i, "reactions", list);
    }

    // ── Toasts ─────────────────────────────────────────────────────────────────────────
    readonly property bool chatFocused: GlobalStates.discordoChatOpen && root.windowFocused
    property bool windowFocused: false

    function _notice(m): void {
        if (!(Config.options?.overlay?.discordVoice?.messageNotices ?? true))
            return;
        // looking at that very channel: the message is already in front of you
        if (root.chatFocused && String(m.channel_id) === root.channelId)
            return;
        const preview = Config.options?.overlay?.discordVoice?.messagePreview ?? true;
        const where = m.guild ? `#${m.channel} · ${m.guild}` : (m.kind === "dm" && m.channel !== m.author.name ? m.channel : "");
        const text = preview && m.text !== ""
            ? m.text : (m.kind === "mention" ? Translation.tr("Mentioned you") : Translation.tr("New message"));
        Notifications.publishInternalNotification({
            "appName": "Discord",
            "appIcon": "discord",
            "summary": where !== "" ? `${m.author.name} (${where})` : m.author.name,
            "body": text,
            "urgency": m.kind === "message" ? "low" : "normal",
            "actions": [{ "identifier": "__qs_discordo_open", "text": Translation.tr("Open") }],
            "actionPayload": { "channel_id": m.channel_id, "guild_id": m.guild_id },
            "sound": true
        });
        // inside a call the overlay widget shows it too
        DiscordVoiceActivity.pushMessageNotice(m);
    }
}
