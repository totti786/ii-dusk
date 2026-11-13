pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * The long lived NDJSON owner for the Discordo Voice applet.
 *
 * Starting the helper is deliberately separate from Connect: an app/window
 * reload cannot authenticate or join a channel by itself. Once Connect has
 * been requested, the helper owns the gateway and voice devices until the
 * user explicitly Disconnects or the helper process exits.
 */
Singleton {
    id: root

    readonly property string helperPath: FileUtils.trimFileProtocol(
        Directories.home + "/.local/share/quickshell-ii/bin/"
        + (Quickshell.env("II_DISCORDO_RUST") === "0" ? "discordo-voice" : "discordo-voice-rs"))
    property bool helperAvailable: false
    property bool helperChecking: true
    readonly property bool helperRunning: helper.running

    property string connectionState: "idle"
    property string statusMessage: ""
    property string errorMessage: ""
    property bool operationBusy: false
    property string pendingCommand: ""
    property bool _stopping: false
    property bool _preserveExitError: false
    property bool _startRequested: false
    property bool _ready: false
    property bool _resyncRequested: true
    property var _pendingCommands: []

    property var guilds: []
    property var channels: []
    property var participants: []
    property var speakingIds: []
    // Camera streams in the call: person id to the url the helper serves it on
    property var remoteVideo: ({})

    // ── Audio ─────────────────────────────────────────────────────────────────────────────
    // Only the Rust helper has these controls; it says so in its ready event.
    property bool audioSupported: false
    // The helper can read and write text chat (chat_* commands); the Go fallback cannot.
    property bool messagesSupported: false
    /// Every chat line from the helper, for DiscordoChatService
    signal chatLine(var message)

    // ── Screen share ──────────────────────────────────────────────────────────────────────
    // Only the Rust helper can share; it says so in its ready event. The portal's own picker asks the user what to share.
    //   shareState: idle, picking (the portal's picker is open), starting, live
    property bool videoSupported: false
    property string shareState: "idle"
    property string shareMessage: ""
    // cameraState: idle, starting, live
    property bool cameraSupported: false
    property string cameraState: "idle"
    property string cameraMessage: ""
    readonly property bool cameraBusy: root.cameraState !== "idle"
    readonly property bool sharing: root.shareState === "picking" || root.shareState === "starting" || root.shareState === "live"
    property var audioInputs: []
    property var audioOutputs: []
    readonly property string audioInput: Persistent.ready ? Persistent.states.discordoVoice.input : ""
    readonly property string audioOutput: Persistent.ready ? Persistent.states.discordoVoice.output : ""
    readonly property int micGain: Persistent.ready ? Persistent.states.discordoVoice.micGain : 100
    readonly property real sensitivityDb: Persistent.ready ? Persistent.states.discordoVoice.sensitivityDb : -40
    readonly property int videoSyncMs: Persistent.ready ? Persistent.states.discordoVoice.videoSyncMs : 80
    readonly property bool joinSounds: Persistent.ready ? Persistent.states.discordoVoice.joinSounds : true
    readonly property var userVolumes: {
        if (!Persistent.ready)
            return ({});
        try {
            const v = JSON.parse(Persistent.states.discordoVoice.userVolumes);
            return v && typeof v === "object" ? v : ({});
        } catch (error) {
            return ({});
        }
    }

    property string selectedGuildId: ""
    property string selectedChannelId: ""
    property string joinedGuildId: ""
    property string joinedChannelId: ""
    property string joinedChannelName: ""
    property bool joined: false
    property bool channelLoading: false
    property bool muted: false
    property bool deafened: false

    // ── Sign-in ──────────────────────────────────────────────────────────────────────────
    // The token never reaches this file: the helper reads, checks and saves it. What arrives is
    // the outcome of asking Discord who it belongs to.
    //   authState: unknown (not asked yet), signed_in, missing, invalid (Discord refused the saved
    //   token), offline (Discord could not be reached: says nothing about the token), rate_limited
    property string authState: "unknown"
    property var authUser: null          // { id, name, avatar } while signed in
    property real authCheckedAt: 0
    property bool authChecking: false
    property bool authBusy: false        // a paste or a removal is running
    property string authBusyAction: ""
    property var authProblem: null       // { action, code, message } of the last failed add or removal
    property string authNotice: ""       // a one-line confirmation: "Signed in as ..."
    property bool authAppliesAfterCall: false
    property bool awaitingTerminalSignIn: false
    property bool _authStart: false      // the helper was started only to check the sign-in
    property var qr: ({ "state": "idle", "matrix": [], "user": null, "message": "" })
    readonly property bool qrActive: ["connecting", "waiting", "scanned", "saving"].indexOf(root.qr.state) >= 0
    readonly property bool signedIn: root.authState === "signed_in"
    readonly property bool needsSignIn: root.authState === "missing" || root.authState === "invalid"
        || root.connectionState === "auth_required"

    readonly property bool connected: root.connectionState === "connected"
    readonly property bool authRequired: root.connectionState === "auth_required"
    readonly property bool canBrowse: root.connected
    readonly property bool hasVoiceSelection: root.selectedGuildId.length > 0
        && root.selectedChannelId.length > 0

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready)
                root.applyAudio();
        }
    }

    function clearData(): void {
        root.guilds = [];
        root.channels = [];
        root.participants = [];
        root.speakingIds = [];
        root.remoteVideo = ({});
        root.selectedGuildId = "";
        root.selectedChannelId = "";
        root.joinedGuildId = "";
        root.joinedChannelId = "";
        root.joinedChannelName = "";
        root.joined = false;
        root.channelLoading = false;
        root.muted = false;
        root.deafened = false;
        root.shareState = "idle";
        root.shareMessage = "";
        root.cameraState = "idle";
        root.cameraMessage = "";
    }

    function _setError(message): void {
        const text = String(message ?? "").trim();
        if (text.length > 0)
            root.errorMessage = text;
    }

    function _snowflake(value): string {
        if (typeof value !== "string" || !/^[1-9][0-9]{0,19}$/.test(value))
            return "";
        return value;
    }

    function _validObject(value): bool {
        return value !== null && typeof value === "object" && !Array.isArray(value);
    }

    function _normaliseItems(values, guildId = "") {
        if (!Array.isArray(values))
            return [];
        const result = [];
        for (const value of values) {
            if (!root._validObject(value))
                continue;
            const id = root._snowflake(value.id);
            const hasGuildId = value.guild_id !== undefined && value.guild_id !== null
                && value.guild_id !== "";
            const itemGuildId = hasGuildId ? root._snowflake(value.guild_id) : "";
            if (id.length === 0 || (hasGuildId && itemGuildId.length === 0)
                    || (guildId.length > 0 && itemGuildId !== guildId))
                continue;
            const item = Object.assign({}, value);
            item.id = id;
            if (hasGuildId)
                item.guild_id = itemGuildId;
            result.push(item);
        }
        return result;
    }

    function _queue(message, expectsAck = true): bool {
        if (root._stopping)
            return false;
        if (expectsAck && root.operationBusy)
            return false;
        if (expectsAck) {
            root.operationBusy = true;
            root.pendingCommand = String(message.cmd || "");
            root.errorMessage = "";
            operationTimeout.restart();
        }
        if (root.helperRunning && root._ready) {
            helper.write(JSON.stringify(message) + "\n");
            root._startRequested = false;
		} else {
			const pending = root._pendingCommands.slice();
			pending.push(message);
            // The backend itself has a bounded command queue. Keep the QML side
            // bounded too if the process is still being checked.
            if (pending.length > 32)
				pending.splice(0, pending.length - 32);
			root._pendingCommands = pending;
			root._startRequested = true;
			root._ensureStarted();
		}
		return true;
	}

    // The helper runs under a small daemon (scripts/discordoVoice/broker.py) so a shell reload
    // only detaches from it: the call stays up and the next session attaches and resyncs.
    readonly property string brokerPath: Quickshell.shellPath("scripts/discordoVoice/broker.py")
    readonly property string brokerSocket: String(Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ii-discordo-voice.sock"

    // An explicit end of the helper: detaching alone would leave it running under the daemon
    function _killHelper(): void {
        Quickshell.execDetached(["python3", "-I", root.brokerPath, "stop"]);
        helper.running = false;
    }

    function _ensureStarted(): void {
        if (root.helperRunning || root.helperChecking)
            return;
        root.helperChecking = true;
        helperCheck.running = true;
    }

    function _flush(): void {
        if (!root.helperRunning || !root._ready)
            return;
        const queued = root._pendingCommands.slice();
        root._pendingCommands = [];
        for (const message of queued)
            helper.write(JSON.stringify(message) + "\n");
    }

	function _resetAfterExit(code): void {
        const preserveError = root._preserveExitError;
        root.operationBusy = false;
        root.pendingCommand = "";
        root._ready = false;
        root._pendingCommands = [];
        root._startRequested = false;
        operationTimeout.stop();
        root.joined = false;
        root.channelLoading = false;
        root.joinedGuildId = "";
        root.joinedChannelId = "";
        root.joinedChannelName = "";
		root.participants = [];
		root.speakingIds = [];
		root.remoteVideo = ({});
		root.muted = false;
		root.deafened = false;
		root.clearData();
		if (root._stopping && !preserveError) {
			root.connectionState = "idle";
			root.statusMessage = "";
			root.errorMessage = "";
		} else if (preserveError) {
			root.connectionState = "error";
		} else if (code !== 0) {
			root.connectionState = "error";
			if (root.errorMessage.length === 0)
				root._setError("The Discordo Voice helper stopped. Try Connect again.");
		} else {
			root.connectionState = "idle";
		}
        root._stopping = false;
        root._preserveExitError = false;
    }

    function handleLine(line): void {
        let message;
        try {
            message = JSON.parse(String(line));
        } catch (error) {
            return;
        }
        if (!root._validObject(message))
            return;
        switch (String(message.type || "")) {
        case "ready":
            root._ready = true;
            root.audioSupported = message.audio === true;
            root.messagesSupported = message.messages === true;
            root.videoSupported = message.video === true;
            root.cameraSupported = message.camera === true;
            if (root.audioSupported)
                root.applyAudio();
            root.connectionState = "ready";
            root._flush();
            if (root._resyncRequested) {
                root._resyncRequested = false;
                root._queue({ "cmd": "status" }, false);
            }
            break;
		case "connection":
			root.connectionState = String(message.state || "idle");
			root.statusMessage = String(message.message || "");
			// A reload left the helper connected but this session has not seen the server list
			if (root.connectionState === "connected" && root.guilds.length === 0
					&& !root.operationBusy && !root._stopping)
				Qt.callLater(() => { if (root.connected && root.guilds.length === 0) root.requestGuilds(); });
 			if (root.connectionState === "auth_required") {
				root.operationBusy = false;
				root.pendingCommand = "";
				operationTimeout.stop();
			}
            break;
        case "auth":
            root._handleAuth(message);
            break;
        case "auth_error":
            root.authBusy = false;
            authBusyTimeout.stop();
            root.authProblem = { "action": String(message.action || ""), "code": String(message.code || ""),
                "message": String(message.message || "") };
            break;
        case "auth_qr":
            root._handleAuthQr(message);
            break;
        case "guilds":
            root.guilds = root._normaliseItems(message.guilds);
            break;
        case "channels": {
            const guildId = root._snowflake(message.guild_id);
            if (guildId === root.selectedGuildId) {
                root.channels = root._normaliseItems(message.channels, guildId);
                root.channelLoading = false;
            }
            break;
        }
        case "channel": {
            const rawGuildId = message.guild_id ?? "";
            const rawChannelId = message.channel_id ?? "";
            const guildId = root._snowflake(rawGuildId);
            const channelId = root._snowflake(rawChannelId);
            if ((rawGuildId !== "" && guildId.length === 0)
                    || (rawChannelId !== "" && channelId.length === 0)
                    || (message.joined === true && (guildId.length === 0 || channelId.length === 0)))
                break;
            root.channelLoading = message.loading === true;
            root.joined = message.joined === true;
            if (root.joined) {
                root.joinedGuildId = guildId;
                root.joinedChannelId = channelId;
                root.joinedChannelName = String(message.name || "Voice channel");

            } else if (channelId.length === 0) {
                root.joinedGuildId = "";
                root.joinedChannelId = "";
                root.joinedChannelName = "";
                root.participants = [];
                root.speakingIds = [];
                root.remoteVideo = ({});
            }
            break;
        }
        case "participants": {
            const guildId = root._snowflake(message.guild_id);
            const channelId = root._snowflake(message.channel_id);
            if (guildId === root.joinedGuildId && channelId === root.joinedChannelId)
                root.participants = root._normaliseItems(message.participants);
            break;
        }
        case "speaking": {
            const guildId = root._snowflake(message.guild_id);
            const channelId = root._snowflake(message.channel_id);
            if (guildId === root.joinedGuildId && channelId === root.joinedChannelId)
                root.speakingIds = Array.isArray(message.speaking)
                    ? message.speaking.map(id => root._snowflake(id)).filter(id => id.length > 0) : [];
            break;
        }
        case "remote_video": {
            // `on` carries the url to play; `off` (or `on` without a url, from the window fallback) removes it
            // The helper repeats `on` every few seconds, so ignore it when nothing changes
            const userId = root._snowflake(message.user_id);
            const url = String(message.state || "") === "on" ? String(message.url || "") : "";
            if (userId.length === 0 || (root.remoteVideo[userId] ?? "") === url)
                break;
            const next = Object.assign({}, root.remoteVideo);
            if (url.length > 0)
                next[userId] = url;
            else
                delete next[userId];
            root.remoteVideo = next;
            break;
        }
        case "share": {
            const state = String(message.state || "");
            root.shareState = state === "stopped" || state === "" ? "idle" : state;
            root.shareMessage = state === "stopped" ? String(message.message || "") : "";
            break;
        }
        case "camera": {
            const state = String(message.state || "");
            root.cameraState = state === "stopped" || state === "" ? "idle" : state;
            root.cameraMessage = state === "stopped" ? String(message.message || "") : "";
            break;
        }
        case "audio_devices":
            root.audioInputs = root._devices(message.inputs);
            root.audioOutputs = root._devices(message.outputs);
            break;
        case "voice_settings":
            if (typeof message.muted === "boolean")
                root.muted = message.muted;
            if (typeof message.deafened === "boolean")
                root.deafened = message.deafened;
            break;
        case "diagnostic":
            if (String(message.level || "") === "error" && root.errorMessage.length === 0)
                root._setError(message.message);
            else if (String(message.level || "") === "warning")
                root.statusMessage = String(message.message || "");
            break;
        case "error":
            root._setError(message.message);
            break;
        case "chat_dms":
        case "chat_channels":
        case "chat_unreads":
        case "chat_unread":
        case "chat_history":
        case "chat":
        case "chat_sent":
        case "chat_error":
        case "chat_typing":
        case "chat_pins":
        case "chat_search":
        case "notice":
            root.chatLine(message);
            break;
        case "ack": {
            const command = String(message.cmd || "");
            // chat commands report their own failures as chat_error; they must not land in the voice banner
            if (command.indexOf("chat_") === 0)
                break;
            if (command === root.pendingCommand) {
                root.operationBusy = false;
                root.pendingCommand = "";
                operationTimeout.stop();
            }
            if (command === "join")
                root.channelLoading = false;
            if (message.ok !== true) {
                root._setError(message.message);
                if (command === "channels")
                    root.channelLoading = false;
            } else if (command === "connect") {
                // Browse only after the explicit Connect has succeeded. This
                // does not authenticate or join on app/window open.
                Qt.callLater(() => root.requestGuilds());
            }
            break;
        }
        }
    }

    function connect(): void {
        root._authStart = false;
        root._queue({ "cmd": "connect" });
    }

    function requestGuilds(): void {
        root._queue({ "cmd": "guilds" });
    }

    function requestStatus(): void {
        if (root._stopping)
            return;
        root._resyncRequested = true;
        if (root.helperRunning) {
            root._resyncRequested = false;
            helper.write(JSON.stringify({ "cmd": "status" }) + "\n");
        }
    }

    function requestChannels(guildId): void {
        const id = root._snowflake(guildId);
        if (id.length === 0)
            return;
        if (root.operationBusy)
            return;
        if (root._queue({ "cmd": "channels", "guild_id": id })) {
            root.selectedGuildId = id;
            root.channels = [];
            root.channelLoading = true;
        }
    }

    function join(guildId, channelId): void {
        const guild = root._snowflake(guildId);
        const channel = root._snowflake(channelId);
        if (guild.length === 0 || channel.length === 0)
            return;
        if (root.operationBusy)
            return;
        if (root._queue({ "cmd": "join", "guild_id": guild, "channel_id": channel })) {
            root.selectedGuildId = guild;
            root.selectedChannelId = channel;
            root._unmuteOnJoin = !root.joinMuted && !root.pushToTalk;
        }
    }

    function leave(): void {
        root._queue({ "cmd": "leave" });
    }

    // Sends what is saved to the helper, which keeps it only until it exits.
    function applyAudio(): void {
        if (!root.audioSupported || !Persistent.ready)
            return;
        root._queue({ "cmd": "set_audio", "input": root.audioInput, "output": root.audioOutput,
            "volume": root.micGain, "sensitivity_db": root.sensitivityDb, "sync_ms": root.videoSyncMs, "cues": root.joinSounds }, false);
        const volumes = root.userVolumes;
        for (const id of Object.keys(volumes))
            root._queue({ "cmd": "user_volume", "user_id": id, "volume": volumes[id] }, false);
        root._queue({ "cmd": "audio_devices" }, false);
    }

    function _devices(values): var {
        if (!Array.isArray(values))
            return [];
        return values.filter(d => d && typeof d.name === "string" && d.name.length > 0)
            .map(d => ({ "name": d.name, "label": String(d.label || d.name) }));
    }

    // A slider sends many values a second; the helper gets the last one shortly after it stops
    property var _audioChanges: ({})
    property var _volumeChanges: ({})
    Timer {
        id: audioFlush
        interval: 120
        onTriggered: {
            const changes = root._audioChanges;
            const volumes = root._volumeChanges;
            root._audioChanges = ({});
            root._volumeChanges = ({});
            if (Object.keys(changes).length > 0)
                root._queue(Object.assign({ "cmd": "set_audio" }, changes), false);
            for (const id of Object.keys(volumes))
                root._queue({ "cmd": "user_volume", "user_id": id, "volume": volumes[id] }, false);
        }
    }

    // preset: "720p30" (default), "480p30" … "2160p60" (see the helper README); windows also offers single windows
    function startShare(preset, windows): void {
        if (!root.videoSupported || !root.joined || root.sharing)
            return;
        root.shareMessage = "";
        root._queue({ "cmd": "share_start", "preset": String(preset || ""), "value": windows === true }, false);
    }

    // preset: "720p30" (default), "480p30", "1080p30": the camera does not go above 1080p30
    function startCamera(preset): void {
        if (!root.cameraSupported || !root.joined || root.cameraBusy)
            return;
        root.cameraMessage = "";
        root._queue({ "cmd": "camera_start", "preset": String(preset || ""), "mirror": Persistent.ready && Persistent.states.discordoVoice.mirrorSent }, false);
    }

    function stopCamera(): void {
        if (root.cameraSupported)
            root._queue({ "cmd": "camera_stop" }, false);
    }

    function stopShare(): void {
        if (root.videoSupported)
            root._queue({ "cmd": "share_stop" }, false);
    }

    function refreshAudioDevices(): void {
        if (root.audioSupported)
            root._queue({ "cmd": "audio_devices" }, false);
    }

    // Any of input, output, micGain, sensitivityDb
    function setAudio(changes): void {
        if (!root.audioSupported || !Persistent.ready)
            return;
        const state = Persistent.states.discordoVoice;
        const message = {};
        if (changes.input !== undefined) {
            state.input = String(changes.input);
            message.input = state.input;
        }
        if (changes.output !== undefined) {
            state.output = String(changes.output);
            message.output = state.output;
        }
        if (changes.micGain !== undefined) {
            state.micGain = Math.max(0, Math.min(200, Math.round(changes.micGain)));
            message.volume = state.micGain;
        }
        if (changes.sensitivityDb !== undefined) {
            state.sensitivityDb = Math.max(-100, Math.min(0, changes.sensitivityDb));
            message.sensitivity_db = state.sensitivityDb;
        }
        if (changes.joinSounds !== undefined) {
            state.joinSounds = changes.joinSounds === true;
            message.cues = state.joinSounds;
        }
        if (changes.videoSyncMs !== undefined) {
            state.videoSyncMs = Math.max(0, Math.min(240, Math.round(changes.videoSyncMs / 20) * 20));
            message.sync_ms = state.videoSyncMs;
        }
        root._audioChanges = Object.assign({}, root._audioChanges, message);
        audioFlush.restart();
    }

    function userVolume(id): int {
        const v = root.userVolumes[String(id)];
        return typeof v === "number" ? v : 100;
    }

    function setUserVolume(id, percent): void {
        const user = root._snowflake(String(id));
        if (!root.audioSupported || !Persistent.ready || user.length === 0)
            return;
        const value = Math.max(0, Math.min(200, Math.round(percent)));
        const volumes = Object.assign({}, root.userVolumes);
        if (value === 100)
            delete volumes[user];
        else
            volumes[user] = value;
        Persistent.states.discordoVoice.userVolumes = JSON.stringify(volumes);
        const pending = Object.assign({}, root._volumeChanges);
        pending[user] = value;
        root._volumeChanges = pending;
        audioFlush.restart();
    }

    function setMuted(value): void {
        root._queue({ "cmd": "mute", "muted": value === true });
    }

    function toggleMute(): void {
        root._queue({ "cmd": "toggle_mute" });
    }

    function setDeafened(value): void {
        root._queue({ "cmd": "deafen", "deafened": value === true });
    }

    function toggleDeafen(): void {
        root._queue({ "cmd": "toggle_deafen" });
    }

    function disconnect(): void {
        if (!root.helperRunning) {
            root._stopping = false;
            root._preserveExitError = false;
            root._ready = false;
            root._pendingCommands = [];
            root._startRequested = false;
            root.operationBusy = false;
            root.pendingCommand = "";
            operationTimeout.stop();
            helperCheck.running = false;
            root.helperChecking = false;
            root.connectionState = "idle";
            root.statusMessage = "";
            root.errorMessage = "";
            root.clearData();
            return;
        }
        root._stopping = true;
        root._preserveExitError = false;
        root._pendingCommands = [];
        if (root.operationBusy) {
            // An explicit disconnect always wins over a slow HTTP/gateway
            // command. Killing this helper is safe because it is the owner
            // of the voice devices and a later Connect starts a fresh one.
            root.operationBusy = false;
            root.pendingCommand = "";
            operationTimeout.stop();
            root._killHelper();
        } else {
            root.operationBusy = true;
            root.pendingCommand = "disconnect";
            operationTimeout.restart();
            helper.write(JSON.stringify({ "cmd": "disconnect" }) + "\n");
        }
    }

    // Ask the helper whether the saved sign-in still works. Not on a timer: each check is a request to
    // Discord with the user's own token, so it happens when the window opens, after a change and on
    // demand, and a fresh answer is reused for a few minutes.
    function checkAuth(force = false): void {
        if (root.authChecking || root._stopping)
            return;
        const fresh = root.authState === "signed_in" && Date.now() - root.authCheckedAt < 5 * 60000;
        if (!force && fresh)
            return;
        root.authChecking = true;
        authCheckTimeout.restart();
        if (!root.helperRunning)
            root._authStart = true;
        root._queue({ "cmd": "auth_status" }, false);
    }

    function _authCommand(cmd: string, action: string): void {
        root.authProblem = null;
        root.authNotice = "";
        root.authBusy = true;
        root.authBusyAction = action;
        authBusyTimeout.restart();
        if (!root.helperRunning)
            root._authStart = true;
        root._queue({ "cmd": cmd }, false);
    }

    /// Add or replace the token with whatever is on the clipboard. The helper reads the clipboard itself.
    function pasteToken(): void { root._authCommand("auth_paste", "paste"); }
    /// Remove the saved token. It is shared with the Discordo client, which is signed out too.
    function removeToken(): void { root._authCommand("auth_remove", "remove"); }

    function startQr(): void {
        root.authProblem = null;
        root.qr = { "state": "connecting", "matrix": [], "user": null, "message": "" };
        if (!root.helperRunning)
            root._authStart = true;
        root._queue({ "cmd": "auth_qr" }, false);
    }

    function cancelQr(): void {
        if (!root.qrActive)
            return;
        root.qr = { "state": "idle", "matrix": [], "user": null, "message": "" };
        root._queue({ "cmd": "auth_qr_cancel" }, false);
    }

    /// Discordo's own sign-in (password, QR or token) in a terminal. The window checks again when it
    /// is focused afterwards.
    function signInInTerminal(): void {
        root.awaitingTerminalSignIn = true;
        HealthService.openTerminal(["discordo"]);
    }

    function signIn(): void { root.signInInTerminal(); }

    function _handleAuth(message): void {
        const state = String(message.state || "");
        if (["signed_in", "missing", "invalid", "offline", "rate_limited"].indexOf(state) < 0)
            return;
        root.authState = state;
        const u = message.user;
        root.authUser = root._validObject(u)
            ? { "id": String(u.id || ""), "name": String(u.name || ""), "avatar": String(u.avatar || "") } : null;
        root.authCheckedAt = Number(message.checked_at) || Date.now();
        root.authChecking = false;
        root.authBusy = false;
        authCheckTimeout.stop();
        authBusyTimeout.stop();
        root.authProblem = null;
        root.authAppliesAfterCall = message.applies_after_call === true;
        if (message.saved === true)
            root.authNotice = root.authUser ? Translation.tr("Signed in as %1").arg(root.authUser.name) : Translation.tr("Signed in");
        else if (message.removed === true)
            root.authNotice = Translation.tr("Signed out");
        if (state === "signed_in") {
            root.awaitingTerminalSignIn = false;
            if (root.connectionState === "auth_required") {
                root.connectionState = "idle";
                root.statusMessage = "";
            }
            root.errorMessage = "";
        }
    }

    function _handleAuthQr(message): void {
        const state = String(message.state || "");
        if (["connecting", "waiting", "scanned", "saving", "done", "declined", "expired", "cancelled", "error"].indexOf(state) < 0)
            return;
        let matrix = root.qr.matrix;
        if (Array.isArray(message.matrix) && message.matrix.length > 0 && message.matrix.length <= 200) {
            const rows = message.matrix.map(r => String(r));
            if (rows.every(r => r.length === rows.length && /^[01]+$/.test(r)))
                matrix = rows;
        }
        const u = message.user;
        root.qr = {
            "state": state,
            "matrix": state === "connecting" ? [] : matrix,
            "user": root._validObject(u) ? { "name": String(u.name || ""), "avatar": String(u.avatar || "") } : root.qr.user,
            "message": String(message.message || "")
        };
    }

    Timer {
        id: authCheckTimeout
        interval: 20000
        onTriggered: root.authChecking = false
    }

    Timer {
        id: authBusyTimeout
        interval: 25000
        onTriggered: {
            if (!root.authBusy)
                return;
            root.authBusy = false;
            root.authProblem = { "action": root.authBusyAction, "code": "timeout",
                "message": Translation.tr("Discordo Voice did not answer. Try again.") };
        }
    }

    Connections {
        target: GlobalStates
        function onDiscordoVoiceOpenChanged() {
            if (GlobalStates.discordoVoiceOpen)
                root.checkAuth(false);
        }
    }

    Component.onCompleted: {
        root._resyncRequested = true;
        helperCheck.running = true;
        Qt.callLater(root.requestStatus);
        // A call may still be up from before this reload: attach and ask for its state
        brokerProbe.running = true;
    }

    Process {
        id: brokerProbe
        command: ["test", "-S", root.brokerSocket]
        onExited: code => {
            if (code === 0 && !root.helperRunning) {
                root._resyncRequested = true;
                root._startRequested = true;
                root._ensureStarted();
            }
        }
    }

    // The helper outlives shell reloads on purpose (a call must survive them), but a signed-in
    // helper that is not in a channel and that nobody is looking at is only a gateway
    // connection and ~50 MB. Let it go after a while; Connect starts a fresh one.
    readonly property int idleDisconnectMinutes: Config.options?.discordoVoice?.idleDisconnectMinutes ?? 10
    Timer {
        id: idleDisconnect
        interval: Math.max(1, root.idleDisconnectMinutes) * 60000
        running: root.idleDisconnectMinutes > 0 && root.helperRunning && root._ready && !root.joined
            && !root.operationBusy && !root._stopping && !GlobalStates.discordoVoiceOpen
            && !GlobalStates.discordoChatOpen
            // notifications for DMs and mentions need the connection to stay
            && !(Persistent.ready && Persistent.states.discordoVoice.chatNotices)
        onTriggered: root.disconnect()
    }

    // ── Push to talk ─────────────────────────────────────────────────────────────────────
    // A GlobalShortcut bound to a key in the compositor (hl.bind(..., hl.dsp.global(
    // "quickshell:discordoVoicePtt"))). Held = mic open, released = muted. The shortcut only
    // records the key; a timer reconciles the helper with it, so a press or release that
    // lands while the helper is still busy with the previous mute is applied afterwards
    // instead of being dropped (which would leave the mic stuck open).
    readonly property bool pushToTalk: Persistent.ready ? Persistent.states.discordoVoice.pushToTalk : false

    function setPushToTalk(value): void {
        if (!Persistent.ready)
            return;
        Persistent.states.discordoVoice.pushToTalk = value === true;
        // leaving push to talk must not strand the mic muted
        if (value !== true && root.joined && root.muted)
            root.setMuted(false);
    }
    property bool pttHeld: false

    GlobalShortcut {
        name: "discordoVoicePtt"
        description: "Discordo Voice: push to talk (hold to speak)"
        onPressed: root.pttHeld = true
        onReleased: root.pttHeld = false
    }

    Timer {
        interval: 100
        repeat: true
        running: root.pushToTalk && root.joined && root.helperRunning && root._ready
        onTriggered: {
            if (!root.operationBusy && root.muted === root.pttHeld)
                root.setMuted(!root.pttHeld);
        }
    }

    // ── Join and leave cues ──────────────────────────────────────────────────────────────
    // A short sound when somebody else enters or leaves the channel you are in. The first
    // participant list after joining is the baseline, so joining a full room is silent.
    readonly property bool joinLeaveSounds: Config.options?.discordoVoice?.joinLeaveSounds ?? true
    property var _knownParticipants: ({})
    property bool _participantsPrimed: false

    // When the call started, for the elapsed time the window shows
    property real joinedAt: 0

    onJoinedChanged: {
        root._knownParticipants = ({});
        root._participantsPrimed = false;
        root.joinedAt = root.joined ? Date.now() : 0;
        if (!root.joined)
            root._unmuteOnJoin = false;
    }

    // Discordo joins every channel muted: the microphone is not opened until asked. Joining
    // is already an explicit act, so by default we ask right after it settles.
    // `discordoVoice.joinMuted: true` keeps the upstream behaviour. Only a join made from here
    // does this: re-attaching to a call after a reload must not touch a mute you chose.
    readonly property bool joinMuted: Config.options?.discordoVoice?.joinMuted ?? false
    property bool _unmuteOnJoin: false

    Timer {
        interval: 150
        repeat: true
        running: root._unmuteOnJoin && root.joined && root._ready
        onTriggered: {
            if (root.operationBusy)
                return;
            root._unmuteOnJoin = false;
            if (root.muted)
                root.setMuted(false);
        }
    }

    onParticipantsChanged: {
        if (!root.joined)
            return;
        const next = ({});
        let arrived = false;
        let departed = false;
        for (const p of root.participants) {
            next[p.id] = true;
            if (root._participantsPrimed && p.self !== true && !root._knownParticipants[p.id])
                arrived = true;
        }
        if (root._participantsPrimed) {
            const selfIds = root.participants.filter(p => p.self === true).map(p => p.id);
            for (const id in root._knownParticipants) {
                if (!next[id] && selfIds.indexOf(id) < 0)
                    departed = true;
            }
        }
        root._knownParticipants = next;
        root._participantsPrimed = true;
        if (root.joinLeaveSounds && (arrived || departed))
            SoundService.playEvent("devices", arrived ? "device-added" : "device-removed");
    }

    // Attached to a call from before a reload: open on its server instead of an empty pane.
    // A timer, not a one-shot, because the server list may still be loading (busy) at first.
    Timer {
        interval: 300
        repeat: true
        running: root.joined && root.selectedGuildId.length === 0 && root.joinedGuildId.length > 0
        onTriggered: {
            if (!root.operationBusy && root.guilds.length > 0)
                root.requestChannels(root.joinedGuildId);
        }
    }

    Timer {
        id: operationTimeout
        interval: 50000
        repeat: false
        onTriggered: {
            if (!root.operationBusy)
                return;
            root.operationBusy = false;
            root.pendingCommand = "";
            root.channelLoading = false;
            root.connectionState = "error";
            root._setError("Discordo Voice took too long to respond. Try Connect again.");
            root._stopping = true;
            root._preserveExitError = true;
            root._ready = false;
            root._pendingCommands = [];
            root._startRequested = false;
            if (root.helperRunning) {
                root._killHelper();
            } else {
                // A slow helper availability check has no Process exit event
                // to reset the stopping guard. Leave the error visible while
                // allowing an explicit later Connect to retry.
                root._stopping = false;
                root._preserveExitError = false;
            }
        }
    }

    Process {
        id: helperCheck
        command: ["test", "-x", root.helperPath]
        onStarted: root.helperChecking = true
        onExited: (code, status) => {
            root.helperChecking = false;
            root.helperAvailable = code === 0;
            if (root.helperAvailable && root._startRequested && !root.helperRunning) {
                root._stopping = false;
                root.connectionState = root._authStart ? "idle" : "starting";
                helper.running = true;
            } else if (!root.helperAvailable && root._startRequested) {
                root.connectionState = "missing";
                root._setError("Build the Discordo Voice helper before connecting.");
                root._startRequested = false;
                root._pendingCommands = [];
                root._ready = false;
                root.operationBusy = false;
                root.pendingCommand = "";
                operationTimeout.stop();
            }
        }
    }

    Process {
        id: helper
        command: ["python3", "-I", root.brokerPath, "attach", root.helperPath]
        stdinEnabled: true
        stdout: SplitParser { onRead: data => root.handleLine(data) }
        // The helper routes known, sanitized runtime diagnostics through
        // NDJSON. Ignore incidental stderr so dependency diagnostics cannot
        // overwrite a successful connection; a nonzero exit is handled below.
        stderr: SplitParser {}
        onStarted: {
            root._stopping = false;
            root._preserveExitError = false;
            root._startRequested = false;
            root._ready = false;
            // Started only to check or change the sign-in: nothing is being connected
            root.connectionState = root._authStart ? "idle" : "starting";
            root._authStart = false;
        }
        onExited: (code, status) => root._resetAfterExit(code)
    }
}
