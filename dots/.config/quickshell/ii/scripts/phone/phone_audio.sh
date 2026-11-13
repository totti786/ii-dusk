#!/usr/bin/env bash
# Streams what the phone is playing (not its microphone) to this PC through scrcpy.
# The process is detached, so it outlives a shell reload; a pid file lets the shell
# find it again.
#
#   phone_audio.sh start <scrcpy args…>   spawn scrcpy, print its pid
#   phone_audio.sh stop                   end it
#   phone_audio.sh status                 print the pid when it is alive, else nothing
#   phone_audio.sh volume <0-150>         set the stream's volume
set -u

PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/phone-audio.pid"

alive() {
    local pid
    pid=$(cat "$PIDFILE" 2>/dev/null) || return 1
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    grep -q -- '--audio-source=' "/proc/$pid/cmdline" 2>/dev/null || return 1
    echo "$pid"
}

case "${1:-}" in
start)
    shift
    alive >/dev/null && { alive; exit 0; }
    setsid -f bash -c 'echo $$ > "$1"; shift; exec "$@"' _ "$PIDFILE" "$@" >/dev/null 2>&1 </dev/null
    for _ in $(seq 1 20); do
        alive && exit 0
        sleep 0.1
    done
    exit 1
    ;;
stop)
    pid=$(alive) && kill "$pid" 2>/dev/null
    rm -f "$PIDFILE"
    ;;
status)
    alive || true
    ;;
volume)
    vol="${2:-100}"
    [[ "$vol" =~ ^[0-9]+$ ]] || exit 1
    pid=$(alive) || exit 1
    pactl -f json list sink-inputs 2>/dev/null | jq -r --arg pid "$pid" \
        '.[] | select(.properties["application.process.id"] == $pid) | .index' |
        while read -r idx; do pactl set-sink-input-volume "$idx" "${vol}%"; done
    ;;
*)
    echo "usage: $0 start|stop|status|volume" >&2
    exit 2
    ;;
esac
