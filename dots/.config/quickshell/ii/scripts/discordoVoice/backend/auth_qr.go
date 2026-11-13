package main

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"strings"
	"sync"
	"time"

	"github.com/ayn2op/arikawa/v3/utils/httputil"
	clientgateway "github.com/ayn2op/discordo/internal/gateway"
	clienthttp "github.com/ayn2op/discordo/internal/http"
	"github.com/skip2/go-qrcode"
)

// QR sign-in: the same Remote Auth handshake Discordo's own login tab runs, without its terminal UI.
// The helper shows a code, the Discord mobile app scans and approves it, and the token that comes back
// is decrypted, checked and saved here. As with every other path, the token never leaves this process.
//
// Events: {"type":"auth_qr","state":S} with S one of connecting, waiting (carries "matrix", the code as
// rows of 0/1), scanned (carries "user"), saving, done, declined, expired, cancelled, error.

const remoteAuthGatewayURL = "wss://remote-auth-gateway.discord.gg/?v=2"

func (m *authManager) qrEvent(state string, extra map[string]any) {
	event := map[string]any{"type": "auth_qr", "state": state}
	for k, v := range extra {
		event[k] = v
	}
	m.b.emit(event)
}

func (m *authManager) startQR() {
	m.mu.Lock()
	if m.qrCancel != nil {
		m.mu.Unlock()
		return
	}
	ctx, cancel := context.WithCancel(m.b.rootCtx)
	m.qrCancel = cancel
	m.mu.Unlock()
	defer func() {
		cancel()
		m.mu.Lock()
		m.qrCancel = nil
		m.mu.Unlock()
	}()
	m.runQR(ctx)
}

func (m *authManager) cancelQR() {
	m.mu.Lock()
	cancel := m.qrCancel
	m.mu.Unlock()
	if cancel != nil {
		cancel()
	}
}

type remoteAuthPayload struct {
	Op                   string `json:"op"`
	HeartbeatInterval    int    `json:"heartbeat_interval"`
	TimeoutMS            int    `json:"timeout_ms"`
	EncryptedNonce       string `json:"encrypted_nonce"`
	Fingerprint          string `json:"fingerprint"`
	EncryptedUserPayload string `json:"encrypted_user_payload"`
	Ticket               string `json:"ticket"`
}

// remoteAuthExchange trades a login ticket for the token, encrypted to our key.
type remoteAuthExchange func(fingerprint, ticket string) (string, error)

func realExchange(fingerprint, ticket string) (string, error) {
	headers := clienthttp.Headers()
	headers.Set("Referer", "https://discord.com/login")
	if fingerprint != "" {
		headers.Set("X-Fingerprint", fingerprint)
	}
	client := clienthttp.NewClient("")
	client.OnRequest = append(client.OnRequest, httputil.WithHeaders(headers))
	return client.ExchangeRemoteAuthTicket(ticket)
}

func decryptOAEP(key *rsa.PrivateKey, encoded string) ([]byte, error) {
	raw, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return nil, err
	}
	return rsa.DecryptOAEP(sha256.New(), nil, key, raw, nil)
}

// qrMatrix returns the code for a fingerprint as rows of 0/1, without a quiet zone.
func qrMatrix(fingerprint string) ([]string, error) {
	code, err := qrcode.New("https://discord.com/ra/"+fingerprint, qrcode.Low)
	if err != nil {
		return nil, err
	}
	code.DisableBorder = true
	bitmap := code.Bitmap()
	rows := make([]string, len(bitmap))
	for y, row := range bitmap {
		var sb strings.Builder
		for _, on := range row {
			if on {
				sb.WriteByte('1')
			} else {
				sb.WriteByte('0')
			}
		}
		rows[y] = sb.String()
	}
	return rows, nil
}

func (m *authManager) runQR(ctx context.Context) {
	m.qrEvent("connecting", nil)

	headers := clienthttp.Headers()
	headers.Set("User-Agent", clienthttp.BrowserUserAgent())
	dialCtx, cancelDial := context.WithTimeout(ctx, authCheckTimeout)
	dialer := clientgateway.NewDialer()
	conn, _, err := dialer.DialContext(dialCtx, remoteAuthGatewayURL, headers)
	cancelDial()
	if err != nil {
		if ctx.Err() != nil {
			m.qrEvent("cancelled", nil)
			return
		}
		m.qrEvent("error", map[string]any{"message": msgOffline})
		return
	}
	// Closing the socket is what unblocks the read below, whether we are done or were cancelled.
	var writeMu sync.Mutex
	write := func(v any) error {
		writeMu.Lock()
		defer writeMu.Unlock()
		return conn.WriteJSON(v)
	}
	go func() {
		<-ctx.Done()
		_ = conn.Close()
	}()
	defer func() { _ = conn.Close() }()

	var key *rsa.PrivateKey
	var fingerprint string
	var deadline <-chan time.Time
	expired := make(chan struct{})

	for {
		_, data, err := conn.ReadMessage()
		if err != nil {
			switch {
			case ctx.Err() != nil:
				select {
				case <-expired:
					m.qrEvent("expired", nil)
				default:
					m.qrEvent("cancelled", nil)
				}
			default:
				m.qrEvent("error", map[string]any{"message": msgOffline})
			}
			return
		}
		var p remoteAuthPayload
		if json.Unmarshal(data, &p) != nil {
			continue
		}
		switch p.Op {
		case "hello":
			interval := time.Duration(p.HeartbeatInterval) * time.Millisecond
			if interval <= 0 {
				interval = 30 * time.Second
			}
			go func() {
				ticker := time.NewTicker(interval)
				defer ticker.Stop()
				for {
					select {
					case <-ticker.C:
						if write(map[string]string{"op": "heartbeat"}) != nil {
							return
						}
					case <-ctx.Done():
						return
					}
				}
			}()
			if p.TimeoutMS > 0 {
				timer := time.NewTimer(time.Duration(p.TimeoutMS) * time.Millisecond)
				deadline = timer.C
				go func() {
					select {
					case <-deadline:
						close(expired)
						m.cancelQR()
					case <-ctx.Done():
						timer.Stop()
					}
				}()
			}
			key, err = rsa.GenerateKey(rand.Reader, 2048)
			if err != nil {
				m.qrEvent("error", map[string]any{"message": "Could not start the sign-in."})
				return
			}
			spki, err := x509.MarshalPKIXPublicKey(key.Public())
			if err != nil {
				m.qrEvent("error", map[string]any{"message": "Could not start the sign-in."})
				return
			}
			if write(map[string]string{"op": "init", "encoded_public_key": base64.StdEncoding.EncodeToString(spki)}) != nil {
				m.qrEvent("error", map[string]any{"message": msgOffline})
				return
			}
		case "nonce_proof":
			nonce, err := decryptOAEP(key, p.EncryptedNonce)
			if err != nil {
				m.qrEvent("error", map[string]any{"message": "Discord's sign-in handshake failed."})
				return
			}
			if write(map[string]string{"op": "nonce_proof", "nonce": base64.RawURLEncoding.EncodeToString(nonce)}) != nil {
				m.qrEvent("error", map[string]any{"message": msgOffline})
				return
			}
		case "pending_remote_init":
			fingerprint = p.Fingerprint
			rows, err := qrMatrix(fingerprint)
			if err != nil {
				m.qrEvent("error", map[string]any{"message": "Could not draw the sign-in code."})
				return
			}
			m.qrEvent("waiting", map[string]any{"matrix": rows})
		case "pending_ticket":
			payload, err := decryptOAEP(key, p.EncryptedUserPayload)
			parts := strings.Split(string(payload), ":")
			if err != nil || len(parts) != 4 {
				m.qrEvent("error", map[string]any{"message": "Discord's sign-in handshake failed."})
				return
			}
			user := map[string]any{"name": nonEmpty(parts[3], "Discord user")}
			if parts[2] != "" && snowflakePattern.MatchString(parts[0]) {
				user["avatar"] = "https://cdn.discordapp.com/avatars/" + parts[0] + "/" + parts[2] + ".png?size=64"
			}
			m.qrEvent("scanned", map[string]any{"user": user})
		case "pending_login":
			m.qrEvent("saving", nil)
			m.finishQR(fingerprint, key, p.Ticket, realExchange)
			return
		case "cancel":
			m.qrEvent("declined", nil)
			return
		}
	}
}

// finishQR exchanges the ticket for the token and saves it like any other.
func (m *authManager) finishQR(fingerprint string, key *rsa.PrivateKey, ticket string, exchange remoteAuthExchange) {
	encrypted, err := exchange(fingerprint, ticket)
	if err != nil {
		m.qrEvent("error", map[string]any{"message": msgOffline})
		return
	}
	raw, err := decryptOAEP(key, encrypted)
	if err != nil || !tokenShape.MatchString(cleanToken(string(raw))) {
		m.qrEvent("error", map[string]any{"message": "Discord's sign-in handshake failed."})
		return
	}
	if m.adopt("qr", cleanToken(string(raw))) {
		m.qrEvent("done", nil)
		return
	}
	// adopt has already said why through an auth_error event
	m.qrEvent("error", map[string]any{"message": "The sign-in could not be completed."})
}
