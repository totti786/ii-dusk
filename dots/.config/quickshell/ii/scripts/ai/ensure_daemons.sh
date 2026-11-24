#!/usr/bin/env bash
# Keeps the orb's two helper daemons running, without systemd units. The shell calls this while the
# orb is visible and once a minute; each daemon is started only when it is not already running, so it
# also revives one that crashed, and the daemons survive shell reloads (the warm voice model is slow
# to load).
#   - local_voice.py: warm Kokoro voice behind $XDG_RUNTIME_DIR/ii-companion-voice.sock
#   - ydotoold: private pointer/keyboard input behind $XDG_RUNTIME_DIR/ii-companion-input.sock
#
# Usage: ensure_daemons.sh [start|stop-voice]
#   start       (default) start whichever daemon is not running.
#   stop-voice  stop the warm Kokoro voice only. Its ~440 MiB of model (resident and swapped) is only
#               worth holding while the orb can be heard; the input helper keeps running. The next
#               speech request or a visible orb starts it again.
run="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
here="$(cd "$(dirname "$0")" && pwd)"
python="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv}/bin/python"

start() {
    local pattern="$1"; shift
    pgrep -u "$(id -u)" -f -- "$pattern" >/dev/null && return 0
    setsid nohup "$@" >/dev/null 2>&1 < /dev/null &
}

stop() {
    local pattern="$1"
    pkill -u "$(id -u)" -f -- "$pattern" 2>/dev/null
    return 0
}

case "${1:-start}" in
    stop-voice)
        stop "[l]ocal_voice.py"
        # The daemon unlinks this when it starts; dropping it now keeps companion_status honest
        # while the process is still exiting.
        rm -f "$run/ii-companion-voice.sock"
        exit 0
        ;;
    start|"") ;;
    *)
        echo "usage: $0 [start|stop-voice]" >&2
        exit 2
        ;;
esac

[ -x "$python" ] && start "[l]ocal_voice.py" env OMP_NUM_THREADS=2 nice -n 5 "$python" "$here/local_voice.py"
command -v ydotoold >/dev/null && start "[y]dotoold --socket-path=$run/ii-companion-input.sock" \
    ydotoold --socket-path="$run/ii-companion-input.sock" --socket-perm=0600
exit 0
