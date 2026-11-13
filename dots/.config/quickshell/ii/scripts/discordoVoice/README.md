# Discordo Voice helper

build.sh builds the Quickshell NDJSON helper from a pinned Discordo checkout.
The adapter is copied into cmd/ii-voice in that checkout so it can use
Discordo's internal gateway, HTTP identity, and voice packages without changing
the installed /usr/bin/discordo binary.

The default source checkout is the inspected fork at commit
5089044cd699c01110090db4cf3ed6b65cb44565. This is the source pin used to
compile the adapter; live applet voice calls still need the user-level
Connect/Join check. Set
DISCORDO_VOICE_SOURCE_SEED or DISCORDO_VOICE_COMMIT when building from a
different checkout. The source checkout remains under
~/.local/share/quickshell-ii/discordo-voice-src; the resulting helper is
~/.local/share/quickshell-ii/bin/discordo-voice.

The build applies `backend/voice_session_blocking.patch` only in this private
helper checkout. It makes the internal voice session wait for Discordo's
gateway follow handler instead of treating a failed `TryLock` as a successful
join, leave, or mute operation. The installed Discordo application is not
modified.

The upstream Discordo source and its voice dependencies remain under their
original GPL licensing and attribution. This adapter does not modify or replace
the installed Discordo application. The helper reads the existing Discordo
keyring item (discordo / token) only inside Go and never prints or passes it
through QML, arguments, or environment variables.

Run `protocol_smoke.sh` after a build for the offline ready/error/shutdown
protocol check. It does not authenticate or open a Discord gateway.

## Sign-in

The helper owns the saved sign-in (keyring item discordo / token, shared with
the Discordo client). Tokens are checked against Discord before they are saved
and never appear in an event, an error, a log line, an argument or QML.

Commands: `auth_status`, `auth_paste`, `auth_remove`, `auth_qr`,
`auth_qr_cancel`. Replies:

- `{"type":"auth","state":S,"checked_at":ms,"user":{id,name,avatar}}` where S is
  `signed_in`, `missing`, `invalid`, `offline` or `rate_limited`. Only a 401 or
  403 from Discord counts as `invalid`; a network failure never does. `saved`,
  `removed` and `applies_after_call` mark the result of a change; a change made
  during a call applies once the call ends.
- `{"type":"auth_error","action":A,"code":C,"message":M}` for a failed paste,
  QR sign-in or removal. Messages are fixed texts, never Discord or clipboard
  content.
- `{"type":"auth_qr","state":S}` for the QR flow: `connecting`, `waiting`
  (carries `matrix`, rows of 0/1), `scanned` (carries `user`), `saving`, `done`,
  `declined`, `expired`, `cancelled`, `error`.

`auth_paste` reads the clipboard with wl-paste inside Go, rejects text that is
not shaped like a user token, rejects bot tokens, and clears the clipboard (and
the matching cliphist entry) after saving. QR sign-in is Discord's Remote Auth
handshake. `go test ./cmd/ii-voice` runs the sign-in tests with fake keyring,
network and clipboard; never run save or remove against the real keyring item.
