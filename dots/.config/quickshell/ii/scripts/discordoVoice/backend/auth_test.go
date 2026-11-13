package main

import (
	"bufio"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net"
	"os"
	"strings"
	"sync"
	"testing"

	"github.com/ayn2op/arikawa/v3/utils/httputil"
	"github.com/zalando/go-keyring"
)

// Built from parts so secret scanners do not mistake this fake for a real bot token.
var testToken = strings.Join([]string{"MTIzNDU2Nzg5MDEyMzQ1Njc4", "GabcdE", "abcdefghijklmnopqrstuvwxyz0123456789ab"}, ".")

type authFake struct {
	mu        sync.Mutex
	stored    string
	loadErr   error
	saveErr   error
	removeErr error
	meErr     error
	who       identity
	clip      string
	clipErr   error
	saved     []string
	scrubbed  []string
	removed   int
	meCalls   int
}

func (f *authFake) deps() authDeps {
	return authDeps{
		load: func() (string, error) {
			f.mu.Lock()
			defer f.mu.Unlock()
			if f.loadErr != nil {
				return "", f.loadErr
			}
			return f.stored, nil
		},
		save: func(token string) error {
			f.mu.Lock()
			defer f.mu.Unlock()
			if f.saveErr != nil {
				return f.saveErr
			}
			f.stored = token
			f.saved = append(f.saved, token)
			return nil
		},
		remove: func() error {
			f.mu.Lock()
			defer f.mu.Unlock()
			f.removed++
			if f.removeErr == nil {
				f.stored = ""
			}
			return f.removeErr
		},
		me: func(ctx context.Context, token string) (identity, error) {
			f.mu.Lock()
			defer f.mu.Unlock()
			f.meCalls++
			if f.meErr != nil {
				return identity{}, f.meErr
			}
			return f.who, nil
		},
		paste: func(ctx context.Context) (string, error) { return f.clip, f.clipErr },
		scrub: func(token string) {
			f.mu.Lock()
			defer f.mu.Unlock()
			f.scrubbed = append(f.scrubbed, token)
		},
	}
}

// harness builds an auth manager whose events are read back from a file, so a test can also check that
// no event, in any form, carries a token.
func harness(t *testing.T) (*authManager, *authFake, func() []map[string]any) {
	t.Helper()
	file, err := os.CreateTemp(t.TempDir(), "events")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { file.Close() })
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	b := &backend{out: newOutput(file), rootCtx: ctx, cancel: cancel, stop: make(chan struct{})}
	fake := &authFake{who: identity{ID: "42", Name: "Sam", Avatar: "https://cdn.example/a.png"}}
	b.auth = newAuthManager(b, fake.deps())
	read := func() []map[string]any {
		f, err := os.Open(file.Name())
		if err != nil {
			t.Fatal(err)
		}
		defer f.Close()
		var events []map[string]any
		scanner := bufio.NewScanner(f)
		for scanner.Scan() {
			var event map[string]any
			if err := json.Unmarshal(scanner.Bytes(), &event); err != nil {
				t.Fatalf("event is not JSON: %q", scanner.Text())
			}
			events = append(events, event)
		}
		return events
	}
	return b.auth, fake, read
}

func httpStatus(status int) error { return &httputil.HTTPError{Status: status} }

func lastOf(t *testing.T, events []map[string]any, kind string) map[string]any {
	t.Helper()
	for i := len(events) - 1; i >= 0; i-- {
		if events[i]["type"] == kind {
			return events[i]
		}
	}
	t.Fatalf("no %q event in %v", kind, events)
	return nil
}

func noTokenIn(t *testing.T, events []map[string]any, secrets ...string) {
	t.Helper()
	raw, _ := json.Marshal(events)
	for _, secret := range secrets {
		if secret != "" && strings.Contains(string(raw), secret) {
			t.Fatalf("an event carries a token: %s", raw)
		}
	}
}

func TestCleanTokenStripsWhatPeopleCopyAlong(t *testing.T) {
	for _, raw := range []string{
		testToken, "  " + testToken + "\n", "\"" + testToken + "\"", "'" + testToken + "'",
		"Bearer " + testToken, "Authorization: " + testToken, "Authorization: Bearer " + testToken,
	} {
		if got := cleanToken(raw); got != testToken {
			t.Errorf("cleanToken(%q) = %q", raw, got)
		}
	}
}

func TestTokenShape(t *testing.T) {
	for _, ok := range []string{testToken, "mfa."+"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"} {
		if !tokenShape.MatchString(ok) {
			t.Errorf("%q should look like a token", ok)
		}
	}
	for _, bad := range []string{"", "hunter2", "correct horse battery staple", "https://discord.com/channels/1/2",
		"has space.inside.token", strings.Repeat("a", 18) + "\n", "short.tok.en"} {
		if tokenShape.MatchString(bad) {
			t.Errorf("%q must not be sent to Discord as a token", bad)
		}
	}
}

func TestClassifyOnlyCallsADiscordRefusalInvalid(t *testing.T) {
	cases := []struct {
		err  error
		want authState
	}{
		{httpStatus(401), authInvalid},
		{httpStatus(403), authInvalid},
		{httpStatus(429), authRateLimited},
		{httpStatus(500), authOffline},
		{httpStatus(502), authOffline},
		{context.DeadlineExceeded, authOffline},
		{&net.DNSError{Err: "no such host"}, authOffline},
		{errors.New("something else"), authOffline},
	}
	for _, c := range cases {
		if got := classify(c.err); got != c.want {
			t.Errorf("classify(%v) = %q, want %q", c.err, got, c.want)
		}
	}
}

func TestStatusReportsEachState(t *testing.T) {
	cases := []struct {
		name  string
		setup func(*authFake)
		want  authState
	}{
		{"signed in", func(f *authFake) { f.stored = testToken }, authSignedIn},
		{"no token", func(f *authFake) {}, authMissing},
		{"keyring locked", func(f *authFake) { f.loadErr = errors.New("locked") }, authMissing},
		{"rejected", func(f *authFake) { f.stored = testToken; f.meErr = httpStatus(401) }, authInvalid},
		{"offline", func(f *authFake) { f.stored = testToken; f.meErr = context.DeadlineExceeded }, authOffline},
		{"server error", func(f *authFake) { f.stored = testToken; f.meErr = httpStatus(503) }, authOffline},
		{"rate limited", func(f *authFake) { f.stored = testToken; f.meErr = httpStatus(429) }, authRateLimited},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			m, fake, read := harness(t)
			c.setup(fake)
			m.status()
			events := read()
			event := lastOf(t, events, "auth")
			if event["state"] != string(c.want) {
				t.Fatalf("state = %v, want %v", event["state"], c.want)
			}
			if c.want == authSignedIn {
				user, _ := event["user"].(map[string]any)
				if user["name"] != "Sam" || user["id"] != "42" {
					t.Fatalf("identity missing: %v", event)
				}
			} else if _, has := event["user"]; has {
				t.Fatalf("a %s state must not carry an identity: %v", c.want, event)
			}
			noTokenIn(t, events, testToken)
		})
	}
}

func TestStatusWithoutTokenNeverAsksDiscord(t *testing.T) {
	m, fake, _ := harness(t)
	m.status()
	if fake.meCalls != 0 {
		t.Fatal("asked Discord about a token that does not exist")
	}
}

func TestPasteSavesAValidToken(t *testing.T) {
	m, fake, read := harness(t)
	fake.clip = "Bearer " + testToken + "\n"
	m.paste()
	if len(fake.saved) != 1 || fake.saved[0] != testToken {
		t.Fatalf("saved = %v", fake.saved)
	}
	if len(fake.scrubbed) != 1 || fake.scrubbed[0] != testToken {
		t.Fatalf("the copied token was not scrubbed: %v", fake.scrubbed)
	}
	events := read()
	event := lastOf(t, events, "auth")
	if event["state"] != "signed_in" || event["saved"] != true {
		t.Fatalf("unexpected event %v", event)
	}
	noTokenIn(t, events, testToken)
}

func TestPasteRefusesWithoutSavingOrScrubbing(t *testing.T) {
	cases := []struct {
		name  string
		setup func(*authFake)
		code  string
		calls int
	}{
		{"empty clipboard", func(f *authFake) { f.clip = "  \n" }, "empty_clipboard", 0},
		{"clipboard error", func(f *authFake) { f.clipErr = errors.New("no wayland") }, "empty_clipboard", 0},
		{"not a token", func(f *authFake) { f.clip = "my password is hunter2" }, "not_a_token", 0},
		{"rejected", func(f *authFake) { f.clip = testToken; f.meErr = httpStatus(401) }, "rejected", 1},
		{"offline", func(f *authFake) { f.clip = testToken; f.meErr = context.DeadlineExceeded }, "offline", 1},
		{"rate limited", func(f *authFake) { f.clip = testToken; f.meErr = httpStatus(429) }, "rate_limited", 1},
		{"bot", func(f *authFake) { f.clip = testToken; f.who.Bot = true }, "bot", 1},
		{"keyring", func(f *authFake) { f.clip = testToken; f.saveErr = errors.New("locked") }, "keyring", 1},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			m, fake, read := harness(t)
			fake.stored = "previous-token-previous-token"
			c.setup(fake)
			m.paste()
			events := read()
			problem := lastOf(t, events, "auth_error")
			if problem["code"] != c.code || problem["action"] != "paste" {
				t.Fatalf("problem = %v, want code %s", problem, c.code)
			}
			if fake.meCalls != c.calls {
				t.Fatalf("Discord was asked %d times, want %d (an unlikely token must not be sent)", fake.meCalls, c.calls)
			}
			if len(fake.saved) != 0 || len(fake.scrubbed) != 0 {
				t.Fatalf("saved %v, scrubbed %v", fake.saved, fake.scrubbed)
			}
			if fake.stored != "previous-token-previous-token" {
				t.Fatal("a failed paste replaced the saved token")
			}
			noTokenIn(t, events, testToken, fake.clip)
		})
	}
}

func TestRemoveDeletesAndToleratesNothingToDelete(t *testing.T) {
	m, fake, read := harness(t)
	fake.stored = testToken
	m.removeToken()
	if fake.stored != "" || fake.removed != 1 {
		t.Fatalf("token not removed: %q (%d calls)", fake.stored, fake.removed)
	}
	if event := lastOf(t, read(), "auth"); event["state"] != "missing" || event["removed"] != true {
		t.Fatalf("unexpected event %v", event)
	}

	m, fake, read = harness(t)
	fake.removeErr = keyring.ErrNotFound
	m.removeToken()
	if event := lastOf(t, read(), "auth"); event["state"] != "missing" {
		t.Fatalf("removing nothing should still end up signed out: %v", event)
	}

	m, fake, read = harness(t)
	fake.stored = testToken
	fake.removeErr = errors.New("keyring locked")
	m.removeToken()
	events := read()
	if lastOf(t, events, "auth_error")["code"] != "keyring" {
		t.Fatalf("a failed removal must say so: %v", events)
	}
	for _, e := range events {
		if e["type"] == "auth" {
			t.Fatalf("a failed removal must not claim a signed-out state: %v", e)
		}
	}
}

func TestOnlyOneCheckRunsAtATime(t *testing.T) {
	m, _, _ := harness(t)
	if !m.begin() {
		t.Fatal("first check refused")
	}
	if m.begin() {
		t.Fatal("a second check started while one was running")
	}
	m.end()
	if !m.begin() {
		t.Fatal("a check could not start after the previous one ended")
	}
}

func TestCredentialChangeWithoutAConnectionHasNothingToStop(t *testing.T) {
	m, _, _ := harness(t)
	if m.b.credentialChanged() {
		t.Fatal("reported a deferred change with no connection")
	}
}

func TestQRMatrixIsASquareOfZerosAndOnes(t *testing.T) {
	rows, err := qrMatrix("abcdef0123456789")
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) < 21 {
		t.Fatalf("a QR code has at least 21 rows, got %d", len(rows))
	}
	for _, row := range rows {
		if len(row) != len(rows) || strings.Trim(row, "01") != "" {
			t.Fatalf("bad row %q in a %d-row code", row, len(rows))
		}
	}
}

func encryptFor(t *testing.T, key *rsa.PrivateKey, plain string) string {
	t.Helper()
	cipher, err := rsa.EncryptOAEP(sha256.New(), rand.Reader, &key.PublicKey, []byte(plain), nil)
	if err != nil {
		t.Fatal(err)
	}
	return base64.StdEncoding.EncodeToString(cipher)
}

func TestQRTicketBecomesASavedToken(t *testing.T) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	m, fake, read := harness(t)
	m.finishQR("fp", key, "ticket", func(fingerprint, ticket string) (string, error) {
		if fingerprint != "fp" || ticket != "ticket" {
			t.Errorf("exchange got %q %q", fingerprint, ticket)
		}
		return encryptFor(t, key, testToken), nil
	})
	if len(fake.saved) != 1 || fake.saved[0] != testToken {
		t.Fatalf("saved = %v", fake.saved)
	}
	events := read()
	if lastOf(t, events, "auth_qr")["state"] != "done" {
		t.Fatalf("events = %v", events)
	}
	noTokenIn(t, events, testToken)
}

func TestQRFailuresSaveNothing(t *testing.T) {
	key, _ := rsa.GenerateKey(rand.Reader, 2048)
	other, _ := rsa.GenerateKey(rand.Reader, 2048)
	cases := map[string]func(*authFake) remoteAuthExchange{
		"exchange fails": func(*authFake) remoteAuthExchange {
			return func(string, string) (string, error) { return "", httpStatus(500) }
		},
		"encrypted to another key": func(*authFake) remoteAuthExchange {
			return func(string, string) (string, error) { return encryptFor(t, other, testToken), nil }
		},
		"not a token inside": func(*authFake) remoteAuthExchange {
			return func(string, string) (string, error) { return encryptFor(t, key, "hunter2"), nil }
		},
		"discord rejects it": func(f *authFake) remoteAuthExchange {
			f.meErr = httpStatus(401)
			return func(string, string) (string, error) { return encryptFor(t, key, testToken), nil }
		},
	}
	for name, build := range cases {
		t.Run(name, func(t *testing.T) {
			m, fake, read := harness(t)
			m.finishQR("fp", key, "ticket", build(fake))
			if len(fake.saved) != 0 {
				t.Fatalf("saved %v", fake.saved)
			}
			events := read()
			if lastOf(t, events, "auth_qr")["state"] != "error" {
				t.Fatalf("events = %v", events)
			}
			noTokenIn(t, events, testToken)
		})
	}
}

func TestCancelQRWithNothingRunningIsHarmless(t *testing.T) {
	m, _, _ := harness(t)
	m.cancelQR()
}
