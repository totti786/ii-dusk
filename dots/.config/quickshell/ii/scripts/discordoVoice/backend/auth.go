package main

import (
	"context"
	"errors"
	"net"
	"os/exec"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/ayn2op/arikawa/v3/discord"
	"github.com/ayn2op/arikawa/v3/utils/httputil"
	"github.com/ayn2op/discordo/internal/consts"
	clienthttp "github.com/ayn2op/discordo/internal/http"
	"github.com/zalando/go-keyring"
)

// Sign-in for the voice applet: check the saved Discordo token, add or replace it, remove it.
//
// The token lives in the system keyring (discordo / token), shared with the Discordo client. It is
// read, checked and written only inside this process: it is never part of an event, an error, a log
// line or a command argument, and the shell never sees it. A token is checked against Discord before
// it is saved, so the keyring only ever holds one that was accepted.

const authCheckTimeout = 10 * time.Second

type authState string

const (
	authSignedIn    authState = "signed_in"
	authMissing     authState = "missing"
	authInvalid     authState = "invalid"
	authOffline     authState = "offline"
	authRateLimited authState = "rate_limited"
)

// Fixed texts for the shell: nothing from a Discord response or from the clipboard is ever repeated.
const (
	msgClipboardEmpty = "The clipboard is empty. Copy your Discord token first."
	msgNotAToken      = "The clipboard does not look like a Discord token."
	msgRejected       = "Discord rejected that token."
	msgOffline        = "Could not reach Discord. Check your connection and try again."
	msgRateLimited    = "Discord asked to slow down. Try again in a minute."
	msgBotToken       = "That is a bot token. Voice needs a user sign-in."
	msgKeyringFailed  = "Could not save to the system keyring."
	msgRemoveFailed   = "Could not remove the token from the system keyring."
)

// A user token is three dot-separated base64url parts (a few older ones start with "mfa."). This only
// keeps arbitrary clipboard text, a password for instance, from being sent to Discord to be "checked".
var tokenShape = regexp.MustCompile(`^(mfa\.)?[A-Za-z0-9_-]{18,}(\.[A-Za-z0-9_-]{4,}){0,2}$`)

type identity struct {
	ID     string
	Name   string
	Avatar string
	Bot    bool
}

// authDeps is everything that touches the outside world, so tests can run without a keyring, a
// network or a clipboard.
type authDeps struct {
	load   func() (string, error)
	save   func(token string) error
	remove func() error
	me     func(ctx context.Context, token string) (identity, error)
	paste  func(ctx context.Context) (string, error)
	// scrub removes the copied token from the clipboard and from clipboard history
	scrub func(token string)
}

func systemAuthDeps() authDeps {
	return authDeps{
		load:   func() (string, error) { return keyring.Get(consts.Name, keyringUser) },
		save:   func(token string) error { return keyring.Set(consts.Name, keyringUser, token) },
		remove: func() error { return keyring.Delete(consts.Name, keyringUser) },
		me:     discordMe,
		paste:  clipboardText,
		scrub:  scrubClipboard,
	}
}

func discordMe(ctx context.Context, token string) (identity, error) {
	user, err := clienthttp.NewClient(token).WithContext(ctx).Me()
	if err != nil {
		return identity{}, err
	}
	avatar := ""
	if user.Avatar != "" {
		avatar = user.AvatarURLWithType(discord.PNGImage) + "?size=64"
	}
	return identity{ID: snowflakeString(user.ID), Name: nonEmpty(user.DisplayOrUsername(), "Discord user"), Avatar: avatar, Bot: user.Bot}, nil
}

// classify turns a failed identity request into a state. Only an answer from Discord that rejects the
// token counts as invalid: a network error, a timeout or a 5xx says nothing about the token.
func classify(err error) authState {
	var httpErr *httputil.HTTPError
	if errors.As(err, &httpErr) {
		switch {
		case httpErr.Status == 401 || httpErr.Status == 403:
			return authInvalid
		case httpErr.Status == 429:
			return authRateLimited
		}
		return authOffline
	}
	var netErr net.Error
	if errors.As(err, &netErr) || errors.Is(err, context.DeadlineExceeded) {
		return authOffline
	}
	return authOffline
}

// cleanToken trims what people copy along with a token: whitespace, quotes, an "Authorization:" or
// "Bearer " prefix.
func cleanToken(raw string) string {
	token := strings.TrimSpace(raw)
	token = strings.TrimPrefix(token, "Authorization:")
	token = strings.TrimSpace(token)
	token = strings.TrimPrefix(token, "Bearer ")
	return strings.Trim(strings.TrimSpace(token), "\"'`")
}

type authManager struct {
	b    *backend
	deps authDeps

	mu       sync.Mutex
	checking bool
	qrCancel context.CancelFunc
}

func newAuthManager(b *backend, deps authDeps) *authManager {
	return &authManager{b: b, deps: deps}
}

// handle runs on its own goroutine: a sign-in check is a network request and must never hold up a
// mute or a leave in the middle of a call.
func (m *authManager) handle(req request) {
	switch strings.ToLower(strings.TrimSpace(req.Command)) {
	case "auth_status":
		go m.status()
	case "auth_paste":
		go m.paste()
	case "auth_remove":
		go m.removeToken()
	case "auth_qr":
		go m.startQR()
	case "auth_qr_cancel":
		m.cancelQR()
	}
}

// begin lets one status, paste or remove run at a time; a second request while one is running is dropped.
func (m *authManager) begin() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.checking {
		return false
	}
	m.checking = true
	return true
}

func (m *authManager) end() {
	m.mu.Lock()
	m.checking = false
	m.mu.Unlock()
}

func (m *authManager) emitState(state authState, who *identity, extra map[string]any) {
	event := map[string]any{"type": "auth", "state": string(state), "checked_at": time.Now().UnixMilli()}
	if who != nil {
		user := map[string]any{"id": who.ID, "name": who.Name}
		if who.Avatar != "" {
			user["avatar"] = who.Avatar
		}
		event["user"] = user
	}
	for k, v := range extra {
		event[k] = v
	}
	m.b.emit(event)
}

// emitProblem reports a failed add or remove without changing the signed-in state the shell shows.
func (m *authManager) emitProblem(action, code, message string) {
	m.b.emit(map[string]any{"type": "auth_error", "action": action, "code": code, "message": message})
}

func (m *authManager) status() {
	if !m.begin() {
		return
	}
	defer m.end()
	state, who := m.checkWith()
	m.emitState(state, who, nil)
}

// checkWith reads the saved token and asks Discord who it belongs to.
func (m *authManager) checkWith() (authState, *identity) {
	token, err := m.deps.load()
	if err != nil || strings.TrimSpace(token) == "" {
		return authMissing, nil
	}
	ctx, cancel := context.WithTimeout(m.b.rootCtx, authCheckTimeout)
	defer cancel()
	who, err := m.deps.me(ctx, token)
	if err != nil {
		return classify(err), nil
	}
	return authSignedIn, &who
}

func (m *authManager) paste() {
	if !m.begin() {
		return
	}
	defer m.end()
	ctx, cancel := context.WithTimeout(m.b.rootCtx, authCheckTimeout)
	defer cancel()
	raw, err := m.deps.paste(ctx)
	token := cleanToken(raw)
	if err != nil || token == "" {
		m.emitProblem("paste", "empty_clipboard", msgClipboardEmpty)
		return
	}
	if !tokenShape.MatchString(token) {
		m.emitProblem("paste", "not_a_token", msgNotAToken)
		return
	}
	m.adopt("paste", token)
}

// adopt checks a token and, only if Discord accepts it, saves it.
func (m *authManager) adopt(action, token string) bool {
	ctx, cancel := context.WithTimeout(m.b.rootCtx, authCheckTimeout)
	defer cancel()
	who, err := m.deps.me(ctx, token)
	if err != nil {
		switch classify(err) {
		case authInvalid:
			m.emitProblem(action, "rejected", msgRejected)
		case authRateLimited:
			m.emitProblem(action, "rate_limited", msgRateLimited)
		default:
			m.emitProblem(action, "offline", msgOffline)
		}
		return false
	}
	if who.Bot {
		m.emitProblem(action, "bot", msgBotToken)
		return false
	}
	if err := m.deps.save(token); err != nil {
		m.emitProblem(action, "keyring", msgKeyringFailed)
		return false
	}
	if m.deps.scrub != nil {
		m.deps.scrub(token)
	}
	deferred := m.b.credentialChanged()
	m.emitState(authSignedIn, &who, map[string]any{"saved": true, "applies_after_call": deferred})
	return true
}

func (m *authManager) removeToken() {
	if !m.begin() {
		return
	}
	defer m.end()
	if err := m.deps.remove(); err != nil && !errors.Is(err, keyring.ErrNotFound) {
		m.emitProblem("remove", "keyring", msgRemoveFailed)
		return
	}
	deferred := m.b.credentialChanged()
	m.emitState(authMissing, nil, map[string]any{"removed": true, "applies_after_call": deferred})
}

// credentialChanged makes a running connection stop using a token that was just replaced or removed.
// A call in progress is left alone: it ends with the call, and the shell is told so.
func (b *backend) credentialChanged() (deferred bool) {
	b.stateMu.RLock()
	connected := b.state != nil
	inCall := b.voice != nil
	b.stateMu.RUnlock()
	if !connected {
		return false
	}
	if inCall {
		return true
	}
	go func() {
		b.mutationMu.Lock()
		b.leaveAndCloseLocked()
		b.mutationMu.Unlock()
		b.connection("disconnected", "")
		b.signalStop()
	}()
	return false
}

// clipboardText reads the clipboard inside this process, so a token never passes through the shell.
func clipboardText(ctx context.Context) (string, error) {
	out, err := exec.CommandContext(ctx, "wl-paste", "--no-newline", "--type", "text").Output()
	if err != nil {
		return "", err
	}
	if len(out) > 4096 {
		return "", errors.New("clipboard too large")
	}
	return string(out), nil
}

// scrubClipboard clears the clipboard and drops the matching cliphist entry, if cliphist is in use.
func scrubClipboard(token string) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = exec.CommandContext(ctx, "wl-copy", "--clear").Run()
	if _, err := exec.LookPath("cliphist"); err != nil {
		return
	}
	list, err := exec.CommandContext(ctx, "cliphist", "list").Output()
	if err != nil {
		return
	}
	for i, line := range strings.Split(string(list), "\n") {
		if i >= 20 || strings.TrimSpace(line) == "" {
			break
		}
		decoded, err := exec.CommandContext(ctx, "cliphist", "decode", strings.SplitN(line, "\t", 2)[0]).Output()
		if err == nil && cleanToken(string(decoded)) == token {
			del := exec.CommandContext(ctx, "cliphist", "delete")
			del.Stdin = strings.NewReader(line + "\n")
			_ = del.Run()
		}
	}
}
