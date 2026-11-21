#!/usr/bin/env bash
# Keeps the orb's two helper daemons running, without systemd units. The shell calls this at start
# and once a minute; each daemon is started only when it is not already running, so it also revives
# one that crashed, and the daemons survive shell reloads (the warm voice model is slow to load).
#   - local_voice.py: warm Kokoro voice behind $XDG_RUNTIME_DIR/ii-companion-voice.sock
#   - ydotoold: private pointer/keyboard input behind $XDG_RUNTIME_DIR/ii-companion-input.sock
run="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
here="$(cd "$(dirname "$0")" && pwd)"
python="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv}/bin/python"

start() {
    local pattern="$1"; shift
    pgrep -u "$(id -u)" -f -- "$pattern" >/dev/null && return 0
    setsid nohup "$@" >/dev/null 2>&1 < /dev/null &
}

[ -x "$python" ] && start "[l]ocal_voice.py" env OMP_NUM_THREADS=2 nice -n 5 "$python" "$here/local_voice.py"
command -v ydotoold >/dev/null && start "[y]dotoold --socket-path=$run/ii-companion-input.sock" \
    ydotoold --socket-path="$run/ii-companion-input.sock" --socket-perm=0600
exit 0
