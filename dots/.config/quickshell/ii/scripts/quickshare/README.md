# Quick Share daemon (`ii-quickshare`)

Quick Share (Android's Nearby Share) for the shell. One detached Rust process speaks the protocol
(mDNS, a BLE nudge, the UKEY2 handshake, the AES/HMAC channel) and talks JSON lines to
`services/QuickShareService.qml` over `$XDG_RUNTIME_DIR/ii-quickshare.sock`. It is detached on
purpose: reloading the shell never drops a transfer.

## Origin and licence

The protocol core is adapted from [rquickshare](https://github.com/Martichou/rquickshare)'s
`rqs_lib` (GPL-3.0). `src/main.rs` is the shell-specific part: the socket server, a single-instance
guard, and clean shutdown on SIGTERM. The crate is GPL-3.0-only (`ii-quickshare_src/LICENSE`).
`mdns-sd` is the rquickshare author's fork, pinned by commit in `Cargo.toml` so a build is
reproducible.

## It is compiled here, not shipped

Nothing compiled is committed: the binary, its stamp and `target/` are gitignored.

```bash
yay -S --needed rust
~/.config/quickshell/ii/scripts/rust-helpers.sh build ii-quickshare   # about 2 minutes cold
```

You do not have to run that yourself. **Turning Quick Share on builds it** if the binary is
missing: Settings > Devices & phone > Quick Share shows the progress, and a failure shows cargo's
last lines with a Retry button. A failed build is not retried on its own.

`rust-helpers.sh` installs through a rename (the old daemon may be running) and stamps the binary
with a hash of the sources it came from. After an update replaces `ii-quickshare_src/`, the helper
reads as *stale* until it is rebuilt. It keeps running meanwhile: stale means missing the newest
fixes, not broken. **Settings > About & Updates > Compiled components** lists every helper built
this way, with its state and a rebuild button.

## Operating notes

- The daemon starts when Quick Share is enabled and exits when it is disabled. Its log is
  `~/.local/state/quickshell/ii-quickshare.log` (the previous run is `.log.1`).
- Only one runs per user. A second launch sees the live socket and exits, so it cannot take the
  socket from the first. A dead daemon's leftover socket is detected and replaced by the shell.
- Do not run the binary by hand to "try it" while the shell's copy is up.
- Changing the download folder in Settings restarts the daemon (it reads the folder once, at
  startup), never during a transfer.

## Robustness (2026-11-18)

- Each outgoing send is its own task, so a long transfer no longer blocks incoming connections.
- An `accept()` error backs off and retries instead of ending the listener for good.
- While invisible, or for a peer outside the local network, inbound connections are closed at
  accept. At most 16 are served at once, and a peer that never starts the handshake is cut after 30 s.
- mDNS register/unregister failures are logged, not fatal; a dead mdns-sd thread is restarted.
- "Temporarily" really lasts 10 minutes (it was 60 s), and the daemon reports its own expiry to
  the shell, which used to keep showing "temporarily" after the PC had gone hidden.
- `quit` goes through the normal shutdown, so the mDNS record is withdrawn.

## Port, watchdog, picker (2026-11-18)

- `--port N` (shell passes `quickShare.port`, default 47321) pins the listener so a firewall rule can match; a taken port falls back to a random one. The snapshot reports the real `port`.
- `{"cmd":"ping"}` answers `{"ev":"pong"}`. The shell pings every 10 s and restarts a daemon that misses 3 in a row.
- Devices sent to are remembered (`quickShare.recent`). `QuickShareService.sendTo(name, files)` sends now if the phone is in range, otherwise as soon as it appears (20 s), else the files stay staged. `warm()` starts discovery early. The Files app's Share submenu uses them.

## Protocol

JSON lines, one object per line. Commands: `snapshot`, `visibility` (`visible` | `invisible` |
`temporarily`), `discover` (`on`), `send` (`addr`, `name`, `files`), `accept` / `reject` / `cancel`
(`id`), `quit`. Events: `snapshot`, `transfer`, `endpoint`, `visibility`, `discovering`, `error`.
