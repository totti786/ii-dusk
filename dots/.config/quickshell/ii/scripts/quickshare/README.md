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

## Protocol

JSON lines, one object per line. Commands: `snapshot`, `visibility` (`visible` | `invisible` |
`temporarily`), `discover` (`on`), `send` (`addr`, `name`, `files`), `accept` / `reject` / `cancel`
(`id`), `quit`. Events: `snapshot`, `transfer`, `endpoint`, `visibility`, `discovering`, `error`.
