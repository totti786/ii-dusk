// Command discordo-voice is the NDJSON adapter used by the Quickshell
// Discordo Voice applet. build.sh copies this file into the pinned Discordo
// module so its internal gateway, HTTP, and voice packages stay available.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/ayn2op/arikawa/v3/discord"
	"github.com/ayn2op/arikawa/v3/gateway"
	"github.com/ayn2op/arikawa/v3/session"
	"github.com/ayn2op/arikawa/v3/state"
	"github.com/ayn2op/arikawa/v3/state/store/defaultstore"
	"github.com/ayn2op/arikawa/v3/utils/handler"
	"github.com/ayn2op/arikawa/v3/utils/httputil"
	"github.com/ayn2op/discordo/internal/consts"
	clientgateway "github.com/ayn2op/discordo/internal/gateway"
	clienthttp "github.com/ayn2op/discordo/internal/http"
	"github.com/ayn2op/discordo/internal/voice"
	"github.com/ayn2op/ningen/v3"
	"github.com/zalando/go-keyring"
)

const (
	keyringUser      = "token"
	voiceSensitivity = -40
	connectTimeout   = 30 * time.Second
	operationTimeout = 45 * time.Second
	cleanupTimeout   = 20 * time.Second
	maxErrorLength   = 240
)

var errVoiceOperationTimedOut = errors.New("voice operation timed out; restarting the helper")

var snowflakePattern = regexp.MustCompile("^[1-9][0-9]{0,19}$")

type request struct {
	Command   string
	GuildID   string
	ChannelID string
	Value     *bool
	Muted     *bool
	Deafened  *bool
}

// UnmarshalJSON keeps the wire names explicit without exposing any credential
// fields to the protocol.
func (r *request) UnmarshalJSON(data []byte) error {
	trimmed := strings.TrimSpace(string(data))
	if len(trimmed) == 0 || trimmed[0] != '{' {
		return errors.New("request must be a JSON object")
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	decodeString := func(name string, target *string) {
		if value, ok := raw[name]; ok {
			_ = json.Unmarshal(value, target)
		}
	}
	decodeBool := func(name string, target **bool) {
		if value, ok := raw[name]; ok {
			var parsed bool
			if json.Unmarshal(value, &parsed) == nil {
				*target = &parsed
			}
		}
	}
	decodeString("cmd", &r.Command)
	decodeString("guild_id", &r.GuildID)
	decodeString("channel_id", &r.ChannelID)
	decodeBool("value", &r.Value)
	decodeBool("muted", &r.Muted)
	decodeBool("deafened", &r.Deafened)
	return nil
}

type output struct {
	mu  sync.Mutex
	enc *json.Encoder
}

func newOutput(w *os.File) *output {
	return &output{enc: json.NewEncoder(w)}
}

func (o *output) send(event map[string]any) {
	o.mu.Lock()
	defer o.mu.Unlock()
	_ = o.enc.Encode(event)
}

// diagnosticHandler keeps upstream slog output inside the NDJSON protocol.
// Attributes are intentionally discarded: they can contain transport details
// or credential-adjacent values that must never reach QML or a shell log.
type diagnosticHandler struct {
	out   *output
	fatal func()
}

func (h *diagnosticHandler) Enabled(_ context.Context, level slog.Level) bool {
	return level >= slog.LevelWarn
}

func (h *diagnosticHandler) Handle(_ context.Context, record slog.Record) error {
	if h == nil || h.out == nil {
		return nil
	}
	level := "warning"
	if record.Level >= slog.LevelError {
		level = "error"
	}
	message := safeDiagnosticMessage(record.Message, record.Level)
	h.out.send(map[string]any{
		"type":    "diagnostic",
		"level":   level,
		"message": message,
	})
	if isFatalDiagnostic(record.Message) && h.fatal != nil {
		h.fatal()
	}
	return nil
}

func (h *diagnosticHandler) WithAttrs(_ []slog.Attr) slog.Handler { return h }

func (h *diagnosticHandler) WithGroup(_ string) slog.Handler { return h }

func safeDiagnosticMessage(message string, level slog.Level) string {
	switch message {
	case "failed to stop voice devices":
		return "Voice devices could not be stopped."
	case "failed to create Opus encoder":
		return "Microphone audio encoder failed to start."
	case "failed to create Opus decoder":
		return "Incoming voice decoder failed."
	default:
		if level >= slog.LevelError {
			return "Discordo Voice reported a runtime error."
		}
		return "Discordo Voice reported a runtime warning."
	}
}

func isFatalDiagnostic(message string) bool {
	return message == "failed to create Opus encoder" || message == "failed to create Opus decoder"
}

type backend struct {
	out *output

	// Commands are handled by one owner goroutine. This keeps gateway/session
	// lifetime and voice device operations ordered; voice.Session.Toggle uses a
	// non-blocking internal lock and cannot be used as our command serializer.
	commands    chan request
	commandDone chan struct{}
	mutationMu  sync.Mutex
	auth        *authManager
	stateMu     sync.RWMutex

	state        *ningen.State
	voice        *voice.Session
	voiceGuild   discord.GuildID
	voiceChannel discord.ChannelID
	muted        bool
	deafened     bool

	voiceWake chan struct{}
	stop      chan struct{}
	stopOnce  sync.Once
	rootCtx   context.Context
	cancel    context.CancelFunc
	workers   sync.WaitGroup
	ended     bool
	fatal     bool
}

func newBackend(out *output) *backend {
	ctx, cancel := context.WithCancel(context.Background())
	b := &backend{
		out:         out,
		commands:    make(chan request, 32),
		commandDone: make(chan struct{}),
		voiceWake:   make(chan struct{}, 1),
		stop:        make(chan struct{}),
		rootCtx:     ctx,
		cancel:      cancel,
	}
	b.auth = newAuthManager(b, systemAuthDeps())
	slog.SetDefault(slog.New(&diagnosticHandler{out: out, fatal: b.fatalDiagnostic}))
	b.workers.Add(1)
	go b.voiceEvents()
	go b.commandLoop()
	return b
}

func (b *backend) fatalDiagnostic() {
	b.stateMu.Lock()
	b.fatal = true
	b.stateMu.Unlock()
	b.signalStop()
}

func (b *backend) fatalError() bool {
	b.stateMu.RLock()
	defer b.stateMu.RUnlock()
	return b.fatal
}

func (b *backend) emit(event map[string]any) {
	b.out.send(event)
}

func (b *backend) connection(stateName, message string) {
	event := map[string]any{"type": "connection", "state": stateName}
	if message != "" {
		event["message"] = message
	}
	b.emit(event)
}

func (b *backend) errorEvent(message string) {
	b.emit(map[string]any{"type": "error", "message": message})
}

func (b *backend) ack(command string, ok bool, message string) {
	event := map[string]any{"type": "ack", "cmd": command, "ok": ok}
	if message != "" {
		event["message"] = message
	}
	b.emit(event)
}

func (b *backend) notifyVoice() {
	select {
	case b.voiceWake <- struct{}{}:
	default:
	}
}

func (b *backend) signalStop() {
	b.stopOnce.Do(func() {
		b.cancel()
		close(b.stop)
	})
}

func (b *backend) voiceEvents() {
	defer b.workers.Done()
	for {
		select {
		case <-b.voiceWake:
			b.emitVoiceSnapshot()
		case <-b.stop:
			return
		}
	}
}

func (b *backend) dispatch(req request) {
	select {
	case b.commands <- req:
	case <-b.stop:
		// The owner is already shutting down. Do not enqueue work behind a
		// disconnect or gateway failure.
	}
}

func (b *backend) commandLoop() {
	defer close(b.commandDone)
	for {
		select {
		case req := <-b.commands:
			select {
			case <-b.stop:
				return
			default:
			}
			b.handleCommand(req)
			select {
			case <-b.stop:
				return
			default:
			}
		case <-b.stop:
			return
		}
	}
}

func (b *backend) handleCommand(req request) {
	command := strings.ToLower(strings.TrimSpace(req.Command))
	switch command {
	case "status", "guilds", "channels":
		b.read(command, req)
	case "connect", "join", "leave", "mute", "toggle_mute", "deafen", "toggle_deafen":
		b.mutate(command, req)
	case "disconnect":
		b.mutate(command, req)
		b.signalStop()
	case "auth_status", "auth_paste", "auth_remove", "auth_qr", "auth_qr_cancel":
		// Their own goroutines: a network check must not queue behind a voice operation
		b.auth.handle(req)
	case "shutdown":
		b.mutationMu.Lock()
		b.leaveAndCloseLocked()
		b.mutationMu.Unlock()
		b.ack(command, true, "")
		b.signalStop()
	default:
		b.errorEvent("Unknown Discordo Voice command.")
		b.ack(command, false, "Unknown command.")
	}
}

func (b *backend) read(command string, req request) {
	b.stateMu.RLock()
	current := b.state
	voiceSession := b.voice
	b.stateMu.RUnlock()
	if command == "status" {
		if current == nil || !current.Session.GatewayIsAlive() {
			b.connection("idle", "")
			b.clearPublishedVoice()
			b.ack(command, true, "")
			return
		}
		b.connection("connected", "")
		if voiceSession != nil {
			b.emitVoiceSnapshot(true)
		} else {
			b.clearPublishedVoice()
		}
		b.ack(command, true, "")
		return
	}
	if current == nil || !current.Session.GatewayIsAlive() {
		b.errorEvent("Connect to Discordo before loading servers or voice channels.")
		b.ack(command, false, "Not connected.")
		return
	}

	switch command {
	case "guilds":
		guilds, err := current.Cabinet.Guilds()
		if err != nil {
			b.errorEvent("Could not load Discord servers.")
			b.ack(command, false, safeError(err))
			return
		}
		ready := current.Ready()
		readyIDs := make([]discord.GuildID, 0, len(ready.Guilds))
		for _, guild := range ready.Guilds {
			readyIDs = append(readyIDs, guild.ID)
		}
		guilds = orderGuilds(ready.UserSettings, readyIDs, guilds)
		items := make([]map[string]string, 0, len(guilds))
		for _, guild := range guilds {
			items = append(items, map[string]string{
				"id": snowflakeString(guild.ID), "name": nonEmpty(guild.Name, "Unnamed server"),
			})
		}
		b.emit(map[string]any{"type": "guilds", "guilds": items})
		b.ack(command, true, "")
	case "channels":
		guildID, err := parseGuildID(req.GuildID)
		if err != nil {
			b.errorEvent("Choose a valid Discord server first.")
			b.ack(command, false, "Invalid server id.")
			return
		}
		channels, err := current.Channels(guildID, []discord.ChannelType{discord.GuildVoice})
		if err != nil {
			b.errorEvent("Could not load voice channels.")
			b.ack(command, false, safeError(err))
			return
		}
		sort.SliceStable(channels, func(i, j int) bool {
			if channels[i].Position == channels[j].Position {
				return channels[i].Name < channels[j].Name
			}
			return channels[i].Position < channels[j].Position
		})
		items := make([]map[string]any, 0, len(channels))
		for _, channel := range channels {
			items = append(items, b.channelData(current, guildID, channel))
		}
		b.emit(map[string]any{"type": "channels", "guild_id": snowflakeString(guildID), "channels": items})
		b.ack(command, true, "")
	}
}

func (b *backend) mutate(command string, req request) {
	b.mutationMu.Lock()
	defer b.mutationMu.Unlock()

	var err error
	switch command {
	case "connect":
		err = b.connectLocked()
	case "join":
		err = b.joinLocked(req)
	case "leave":
		err = b.leaveLocked()
	case "mute", "toggle_mute":
		err = b.setMuteLocked(command, req)
	case "deafen", "toggle_deafen":
		err = b.setDeafenLocked(command, req)
	case "disconnect":
		err = b.disconnectLocked()
	}
	if err != nil {
		message := safeError(err)
		b.errorEvent(message)
		b.ack(command, false, message)
		if errors.Is(err, errVoiceOperationTimedOut) {
			// The upstream voice operation is still in an internal goroutine
			// when our watchdog fires. Poison this helper so no later command
			// can touch the old session; the shell can start a fresh process.
			b.signalStop()
		}
		return
	}
	b.ack(command, true, "")
}

func (b *backend) connectLocked() error {
	b.stateMu.RLock()
	alreadyConnected := b.state != nil && b.state.Session.GatewayIsAlive()
	ended := b.ended
	b.stateMu.RUnlock()
	if alreadyConnected {
		b.connection("connected", "")
		return nil
	}
	if ended {
		return errors.New("the Discordo connection ended; restart the voice applet")
	}

	token, err := keyring.Get(consts.Name, keyringUser)
	if err != nil || strings.TrimSpace(token) == "" {
		b.auth.emitState(authMissing, nil, nil)
		b.connection("auth_required", "Sign in to save a token for Discordo Voice.")
		return errors.New("Discordo is not signed in")
	}

	b.connection("connecting", "")
	identifier := gateway.NewIdentifier(gateway.IdentifyCommand{
		Token: token, Properties: clienthttp.IdentifyProperties(),
		Capabilities: gateway.LazyUserNotes | gateway.VersionedReadStates |
			gateway.VersionedUserGuildSetttings | gateway.DedupeUserObjects |
			gateway.PrioritizedReadyPayload | gateway.MultipleGuildExperimentPopulations |
			gateway.NonChannelReadStates | gateway.AuthTokenRefresh | gateway.DebounceMessageReactions,
	})
	clientSession := session.NewWithGateway(clientgateway.New(identifier), handler.New())
	clientSession.Client = clienthttp.NewClient(token)
	cabinet := defaultstore.New()
	// Voice needs guild/member/channel/voice-state caches, but this helper has
	// no chat surface. Keep message storage disabled so a long-lived call does
	// not retain message history for every channel.
	cabinet.MessageStore = defaultstore.NewMessage(0)
	stateValue := state.NewFromSession(clientSession, cabinet)
	ningenState := ningen.FromState(stateValue)
	ningenState.OnRequest = append(ningenState.OnRequest, httputil.WithHeaders(clienthttp.Headers()))
	ningenState.AddSyncHandler(func(*gateway.VoiceStateUpdateEvent) { b.notifyVoice() })
	ningenState.AddSyncHandler(func(*gateway.ReadySupplementalEvent) { b.notifyVoice() })

	ctx, cancel := context.WithTimeout(b.rootCtx, connectTimeout)
	err = stateValue.Open(ctx)
	cancel()
	if err != nil {
		if b.rootCtx.Err() != nil {
			_ = clientSession.Close()
			return errors.New("connection stopped")
		}
		_ = clientSession.Close()
		// A refused login is a sign-in problem, not a connection one: ask Discord whether the token
		// is still good, and if it is not send the shell to the sign-in panel instead of an error.
		checkCtx, checkCancel := context.WithTimeout(b.rootCtx, authCheckTimeout)
		_, meErr := b.auth.deps.me(checkCtx, token)
		checkCancel()
		if meErr != nil && classify(meErr) == authInvalid {
			b.auth.emitState(authInvalid, nil, nil)
			b.connection("auth_required", "Discord no longer accepts the saved sign-in.")
			return errors.New("Discord rejected the saved sign-in")
		}
		b.connection("error", "Discord rejected or closed the connection.")
		return fmt.Errorf("connect: %w", err)
	}

	b.stateMu.Lock()
	b.state = ningenState
	b.voice = nil
	b.voiceGuild, b.voiceChannel = discord.NullGuildID, discord.NullChannelID
	b.muted, b.deafened = false, false
	b.stateMu.Unlock()
	b.connection("connected", "")
	go b.watchGateway(ningenState)
	return nil
}

func (b *backend) watchGateway(current *ningen.State) {
	_ = current.Session.Wait(b.rootCtx)
	if b.rootCtx.Err() != nil {
		return
	}
	// Wait returns nil for a normal gateway close as well as for an error. A
	// gateway ending makes this helper one-shot: the shell starts a fresh
	// process for a later explicit Connect, which also reaps voice goroutines.
	b.gatewayEnded(current)
}

func (b *backend) gatewayEnded(current *ningen.State) {
	b.signalStop()
	b.mutationMu.Lock()
	defer b.mutationMu.Unlock()
	b.stateMu.RLock()
	currentSession := b.state == current
	b.stateMu.RUnlock()
	if !currentSession {
		return
	}
	b.connection("disconnected", "Discord connection ended.")
	b.errorEvent("Discord connection ended. Restart the voice applet to connect again.")
	b.leaveAndCloseLocked()
}

func (b *backend) joinLocked(req request) error {
	guildID, err := parseGuildID(req.GuildID)
	if err != nil {
		return errors.New("invalid server id")
	}
	channelID, err := parseChannelID(req.ChannelID)
	if err != nil {
		return errors.New("invalid voice channel id")
	}
	b.stateMu.RLock()
	current, voiceSession := b.state, b.voice
	b.stateMu.RUnlock()
	if current == nil || !current.Session.GatewayIsAlive() {
		return errors.New("not connected")
	}

	channel, err := current.Cabinet.Channel(channelID)
	if err != nil {
		channels, fetchErr := current.Channels(guildID, []discord.ChannelType{discord.GuildVoice})
		if fetchErr != nil {
			return fmt.Errorf("load voice channel: %w", fetchErr)
		}
		for i := range channels {
			if channels[i].ID == channelID {
				channel = &channels[i]
				break
			}
		}
	}
	if channel == nil || channel.GuildID != guildID || !isVoiceChannel(channel.Type) {
		return errors.New("that voice channel is no longer available")
	}
	if !current.HasPermissions(channel.ID, discord.PermissionViewChannel|discord.PermissionConnect) {
		return errors.New("you are not permitted to connect to that voice channel")
	}
	states, _ := current.Cabinet.VoiceStates(guildID)
	if channel.VoiceUserLimit > 0 && len(statesInChannel(states, channel.ID)) >= int(channel.VoiceUserLimit) &&
		!current.HasPermissions(channel.ID, discord.PermissionMoveMembers) {
		return errors.New("that voice channel is full")
	}
	if voiceSession == nil {
		voiceSession = voice.New(current.State, voiceSensitivity)
		b.stateMu.Lock()
		b.voice = voiceSession
		b.stateMu.Unlock()
		b.watchVoice(voiceSession)
	}

	b.emit(map[string]any{"type": "channel", "guild_id": snowflakeString(guildID),
		"channel_id": snowflakeString(channel.ID), "name": nonEmpty(channel.Name, "Voice channel"),
		"joined": false, "loading": true})
	if err := boundedVoiceCall(voiceSession.Join, channel.ID); err != nil {
		return fmt.Errorf("join voice channel: %w", err)
	}
	b.stateMu.Lock()
	b.voiceGuild, b.voiceChannel = guildID, channel.ID
	b.muted, b.deafened = true, false
	b.stateMu.Unlock()
	b.emit(map[string]any{"type": "channel", "guild_id": snowflakeString(guildID),
		"channel_id": snowflakeString(channel.ID), "name": nonEmpty(channel.Name, "Voice channel"), "joined": true})
	b.emitVoiceSettings()
	b.notifyVoice()
	return nil
}

func (b *backend) watchVoice(current *voice.Session) {
	b.workers.Add(1)
	go func() {
		defer b.workers.Done()
		updates := current.Updates()
		if updates == nil {
			return
		}
		for {
			select {
			case <-updates:
				b.notifyVoice()
			case <-b.stop:
				return
			}
		}
	}()
}

func (b *backend) leaveLocked() error {
	b.stateMu.RLock()
	voiceSession := b.voice
	joined := voiceSession != nil && voiceSession.Status().ChannelID.IsValid()
	b.stateMu.RUnlock()
	if voiceSession == nil || !joined {
		return nil
	}
	if err := boundedVoiceLeave(voiceSession); err != nil {
		return fmt.Errorf("leave voice channel: %w", err)
	}
	b.stateMu.Lock()
	b.voiceGuild, b.voiceChannel = discord.NullGuildID, discord.NullChannelID
	b.muted, b.deafened = false, false
	b.stateMu.Unlock()
	b.clearPublishedVoice()
	b.notifyVoice()
	return nil
}

func (b *backend) setMuteLocked(command string, req request) error {
	b.stateMu.RLock()
	voiceSession, current, currentState := b.voice, b.muted, b.state
	voiceStatus := voice.Status{}
	if voiceSession != nil {
		voiceStatus = voiceSession.Status()
	}
	channelID := voiceStatus.ChannelID
	joined := voiceSession != nil && voiceStatus.Joined
	b.stateMu.RUnlock()
	if voiceSession == nil || !joined {
		return errors.New("join a voice channel first")
	}
	desired, ok := requestedValue(command, req.Value, req.Muted, current)
	if !ok {
		desired = !current
	}
	if desired == current {
		return nil
	}
	if !desired && (currentState == nil || !currentState.HasPermissions(channelID, discord.PermissionSpeak|discord.PermissionUseVAD)) {
		return errors.New("you are not permitted to use the microphone in this voice channel")
	}
	if err := boundedVoiceToggle(voiceSession, false); err != nil {
		// Toggle may have changed the capture device before Discord rejected
		// the gateway update. Reusing this process would make the next toggle
		// lie about the actual device state, so force a fresh helper.
		b.signalStop()
		return fmt.Errorf("toggle mute: %w", err)
	}
	b.stateMu.Lock()
	b.muted = desired
	if !desired {
		// Voice.Toggle(false) also undeafens by design.
		b.deafened = false
	}
	b.stateMu.Unlock()
	b.emitVoiceSettings()
	b.notifyVoice()
	return nil
}

func (b *backend) setDeafenLocked(command string, req request) error {
	b.stateMu.RLock()
	voiceSession, current := b.voice, b.deafened
	joined := voiceSession != nil && voiceSession.Status().Joined
	b.stateMu.RUnlock()
	if voiceSession == nil || !joined {
		return errors.New("join a voice channel first")
	}
	desired, ok := requestedValue(command, req.Value, req.Deafened, current)
	if !ok {
		desired = !current
	}
	if desired == current {
		return nil
	}
	if err := boundedVoiceToggle(voiceSession, true); err != nil {
		b.signalStop()
		return fmt.Errorf("toggle deafen: %w", err)
	}
	b.stateMu.Lock()
	b.deafened = desired
	if desired {
		b.muted = true
	}
	b.stateMu.Unlock()
	b.emitVoiceSettings()
	b.notifyVoice()
	return nil
}

func (b *backend) disconnectLocked() error {
	b.leaveAndCloseLocked()
	b.connection("disconnected", "")
	return nil
}

func (b *backend) leaveAndCloseLocked() {
	// Leave first so the capture/playback devices are stopped while the voice
	// session still owns them. A process shutdown is the final reap for the
	// internal receive loops, which have no exported Close method upstream.
	_ = b.leaveLocked()
	b.closeSessionLocked()
}

func (b *backend) closeSessionLocked() {
	b.stateMu.Lock()
	current := b.state
	b.state, b.voice = nil, nil
	b.voiceGuild, b.voiceChannel = discord.NullGuildID, discord.NullChannelID
	b.muted, b.deafened = false, false
	b.ended = true
	b.stateMu.Unlock()
	if current != nil {
		_ = current.Session.Close()
	}
	b.clearPublishedVoice()
}

func (b *backend) emitVoiceSettings() {
	b.stateMu.RLock()
	muted, deafened := b.muted, b.deafened
	b.stateMu.RUnlock()
	b.emit(map[string]any{"type": "voice_settings", "muted": muted, "deafened": deafened})
}

func (b *backend) emitVoiceSnapshot(forceChannel ...bool) {
	// Voice updates arrive on their own goroutine. Serialize reconciliation with
	// join/leave/toggle so a stale Status{} cannot clear the local device flags
	// or channel selection after a newer command has established ownership.
	b.mutationMu.Lock()
	defer b.mutationMu.Unlock()

	b.stateMu.RLock()
	current, voiceSession, guildID, channelID := b.state, b.voice, b.voiceGuild, b.voiceChannel
	b.stateMu.RUnlock()
	if current == nil || voiceSession == nil {
		return
	}
	status := voiceSession.Status()
	if !status.ChannelID.IsValid() {
		b.clearPublishedVoice()
		return
	}
	channelName := "Voice channel"
	channelChanged := channelID != status.ChannelID
	channelID = status.ChannelID
	if channel, err := current.Cabinet.Channel(channelID); err == nil {
		guildID = channel.GuildID
		channelName = nonEmpty(channel.Name, channelName)
	}
	if channelChanged || (len(forceChannel) > 0 && forceChannel[0]) {
		b.stateMu.Lock()
		b.voiceGuild, b.voiceChannel = guildID, channelID
		b.stateMu.Unlock()
		b.emit(map[string]any{"type": "channel", "guild_id": snowflakeString(guildID),
			"channel_id": snowflakeString(channelID), "name": channelName,
			"joined": status.Joined, "loading": false})
	}
	if !guildID.IsValid() {
		return
	}
	states, err := current.Cabinet.VoiceStates(guildID)
	if err != nil {
		return
	}
	// Keep the local device flags authoritative. The gateway can echo a stale
	// self-mute/deaf state while Toggle is changing capture/playback; replacing
	// these flags from that echo would make the next explicit command a no-op.
	participants := make([]map[string]any, 0, len(states))
	for _, stateValue := range states {
		if stateValue.ChannelID == channelID {
			participants = append(participants, b.participantData(current, voiceSession, guildID, stateValue))
		}
	}
	sort.SliceStable(participants, func(i, j int) bool {
		return participants[i]["name"].(string) < participants[j]["name"].(string)
	})
	b.emit(map[string]any{"type": "participants", "guild_id": snowflakeString(guildID),
		"channel_id": snowflakeString(channelID), "participants": participants})
	speaking := make([]string, 0)
	for _, participant := range participants {
		if participant["speaking"] == true {
			speaking = append(speaking, participant["id"].(string))
		}
	}
	b.emit(map[string]any{"type": "speaking", "guild_id": snowflakeString(guildID),
		"channel_id": snowflakeString(channelID), "speaking": speaking})
	if status.Joined {
		b.emitVoiceSettings()
	}
}

func (b *backend) clearPublishedVoice() {
	b.stateMu.Lock()
	b.voiceGuild, b.voiceChannel = discord.NullGuildID, discord.NullChannelID
	b.muted, b.deafened = false, false
	b.stateMu.Unlock()
	b.emit(map[string]any{"type": "channel", "guild_id": "", "channel_id": "", "joined": false})
	b.emit(map[string]any{"type": "participants", "guild_id": "", "channel_id": "", "participants": []map[string]any{}})
	b.emit(map[string]any{"type": "speaking", "guild_id": "", "channel_id": "", "speaking": []string{}})
	b.emitVoiceSettings()
}

func (b *backend) participantData(current *ningen.State, voiceSession *voice.Session, guildID discord.GuildID, value discord.VoiceState) map[string]any {
	name := value.UserID.String()
	user := discord.User{}
	if value.Member != nil {
		user = value.Member.User
		name = displayName(value.Member.User, value.Member.Nick)
	} else if member, err := current.Cabinet.Member(guildID, value.UserID); err == nil {
		user = member.User
		name = displayName(member.User, member.Nick)
	} else if storedUser, err := current.Cabinet.User(value.UserID); err == nil {
		name = displayName(*storedUser, "")
		user = *storedUser
	}
	self := false
	if me, err := current.Cabinet.Me(); err == nil && me != nil {
		self = me.ID == value.UserID
	}
	return map[string]any{"id": snowflakeString(value.UserID), "name": nonEmpty(name, value.UserID.String()),
		"self": self, "avatar_url": user.AvatarURL(),
		"muted": value.Mute || value.SelfMute, "deafened": value.Deaf || value.SelfDeaf,
		"speaking": voiceSession.Speaking(value.UserID)}
}

func (b *backend) channelData(current *ningen.State, guildID discord.GuildID, channel discord.Channel) map[string]any {
	states, _ := current.Cabinet.VoiceStates(guildID)
	count := len(statesInChannel(states, channel.ID))
	full := channel.VoiceUserLimit > 0 && count >= int(channel.VoiceUserLimit)
	canJoin := current.HasPermissions(channel.ID, discord.PermissionViewChannel|discord.PermissionConnect)
	if full && !current.HasPermissions(channel.ID, discord.PermissionMoveMembers) {
		canJoin = false
	}
	return map[string]any{"id": snowflakeString(channel.ID), "guild_id": snowflakeString(guildID),
		"name": nonEmpty(channel.Name, "Voice channel"), "stage": false,
		"user_count": count, "user_limit": channel.VoiceUserLimit, "full": full, "can_join": canJoin,
		"can_speak": current.HasPermissions(channel.ID, discord.PermissionSpeak|discord.PermissionUseVAD)}
}

// orderGuilds follows Discord's sidebar metadata rather than alphabetizing
// servers. GuildFolders is already the user's folder/sidebar order; flattening
// it first also keeps the singleton folder-ID=0 entries in their supplied
// position. GuildPositions and the Ready order fill gaps from partial or stale
// settings payloads, while newly cached guilds receive a deterministic ID
// fallback so the list never jumps between refreshes.
func orderGuilds(settings *gateway.UserSettings, readyIDs []discord.GuildID, guilds []discord.Guild) []discord.Guild {
	byID := make(map[discord.GuildID]discord.Guild, len(guilds))
	for _, guild := range guilds {
		if guild.ID.IsValid() {
			byID[guild.ID] = guild
		}
	}

	orderedIDs := make([]discord.GuildID, 0, len(byID))
	seen := make(map[discord.GuildID]struct{}, len(byID))
	appendID := func(id discord.GuildID) {
		if !id.IsValid() {
			return
		}
		if _, exists := seen[id]; exists {
			return
		}
		seen[id] = struct{}{}
		orderedIDs = append(orderedIDs, id)
	}
	if settings != nil {
		for _, folder := range settings.GuildFolders {
			for _, id := range folder.GuildIDs {
				appendID(id)
			}
		}
		for _, id := range settings.GuildPositions {
			appendID(id)
		}
	}
	for _, id := range readyIDs {
		appendID(id)
	}

	remaining := make([]discord.GuildID, 0, len(byID))
	for id := range byID {
		if _, exists := seen[id]; !exists {
			remaining = append(remaining, id)
		}
	}
	sort.Slice(remaining, func(i, j int) bool { return remaining[i] < remaining[j] })
	orderedIDs = append(orderedIDs, remaining...)

	ordered := make([]discord.Guild, 0, len(byID))
	for _, id := range orderedIDs {
		if guild, exists := byID[id]; exists {
			ordered = append(ordered, guild)
		}
	}
	return ordered
}

func statesInChannel(states []discord.VoiceState, channelID discord.ChannelID) []discord.VoiceState {
	filtered := make([]discord.VoiceState, 0, len(states))
	for _, value := range states {
		if value.ChannelID == channelID {
			filtered = append(filtered, value)
		}
	}
	return filtered
}

func displayName(user discord.User, nick string) string {
	if nick != "" {
		return nick
	}
	if user.DisplayName != "" {
		return user.DisplayName
	}
	return user.Username
}

func requestedValue(command string, value, named *bool, current bool) (bool, bool) {
	if command == "toggle_mute" || command == "toggle_deafen" {
		return !current, true
	}
	if named != nil {
		return *named, true
	}
	if value != nil {
		return *value, true
	}
	return current, false
}

func (b *backend) shutdown() {
	b.signalStop()
	// Do not close a session underneath an in-flight command. If a network
	// call ignores its own context, returning from main after this watchdog is
	// the cleanup boundary; the helper process then reaps all internal loops.
	select {
	case <-b.commandDone:
		b.mutationMu.Lock()
		b.leaveAndCloseLocked()
		b.mutationMu.Unlock()
	case <-time.After(cleanupTimeout):
	}
	done := make(chan struct{})
	go func() { b.workers.Wait(); close(done) }()
	select {
	case <-done:
	case <-time.After(cleanupTimeout):
	}
}

func boundedVoiceCall(join func(discord.ChannelID) error, channelID discord.ChannelID) error {
	result := make(chan error, 1)
	go func() { result <- join(channelID) }()
	select {
	case err := <-result:
		return err
	case <-time.After(operationTimeout):
		return errVoiceOperationTimedOut
	}
}

func boundedVoiceLeave(voiceSession *voice.Session) error {
	result := make(chan error, 1)
	go func() { result <- voiceSession.Leave() }()
	select {
	case err := <-result:
		return err
	case <-time.After(cleanupTimeout):
		return errVoiceOperationTimedOut
	}
}

func boundedVoiceToggle(voiceSession *voice.Session, deafen bool) error {
	result := make(chan error, 1)
	go func() { result <- voiceSession.Toggle(deafen) }()
	select {
	case err := <-result:
		return err
	case <-time.After(operationTimeout):
		return errVoiceOperationTimedOut
	}
}

func parseSnowflake(value string) (discord.Snowflake, error) {
	value = strings.TrimSpace(value)
	if !snowflakePattern.MatchString(value) {
		return 0, errors.New("invalid snowflake")
	}
	parsed, err := strconv.ParseUint(value, 10, 64)
	if err != nil || parsed == 0 {
		return 0, errors.New("invalid snowflake")
	}
	return discord.Snowflake(parsed), nil
}

func parseGuildID(value string) (discord.GuildID, error) {
	parsed, err := parseSnowflake(value)
	return discord.GuildID(parsed), err
}

func parseChannelID(value string) (discord.ChannelID, error) {
	parsed, err := parseSnowflake(value)
	return discord.ChannelID(parsed), err
}

func snowflakeString[T ~uint64](value T) string {
	if value == 0 {
		return ""
	}
	return strconv.FormatUint(uint64(value), 10)
}

func isVoiceChannel(channelType discord.ChannelType) bool {
	return channelType == discord.GuildVoice
}

func nonEmpty(value, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return value
}

func safeError(err error) string {
	if err == nil {
		return ""
	}
	message := strings.Join(strings.Fields(err.Error()), " ")
	lower := strings.ToLower(message)
	if strings.Contains(lower, "token") || strings.Contains(lower, "authorization") ||
		strings.Contains(lower, "cookie") || strings.Contains(lower, "x-super-properties") {
		return "Discord request failed."
	}
	if len(message) > maxErrorLength {
		message = message[:maxErrorLength] + "…"
	}
	return nonEmpty(message, "Discord request failed.")
}

func scanRequests(in *os.File, requests chan<- request) {
	defer close(requests)
	scanner := bufio.NewScanner(in)
	scanner.Buffer(make([]byte, 4096), 64*1024)
	for scanner.Scan() {
		var req request
		if json.Unmarshal(scanner.Bytes(), &req) == nil {
			requests <- req
		}
	}
}

func run() int {
	out := newOutput(os.Stdout)
	b := newBackend(out)
	defer b.shutdown()
	b.emit(map[string]any{"type": "ready", "version": 1})

	requests := make(chan request)
	go scanRequests(os.Stdin, requests)
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt)
	defer signal.Stop(signals)
loop:
	for {
		select {
		case req, ok := <-requests:
			if !ok {
				break loop
			}
			b.dispatch(req)
		case <-signals:
			break loop
		case <-b.stop:
			break loop
		}
	}
	if b.fatalError() {
		return 1
	}
	return 0
}

func main() {
	os.Exit(run())
}
