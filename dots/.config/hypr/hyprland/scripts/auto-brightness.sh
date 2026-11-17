#!/usr/bin/env bash
# Set the screen brightness from the webcam's view of the room (one shot, no daemon).
#
#   auto-brightness.sh              measure and set the brightness
#   auto-brightness.sh --measure    only print the reading (log10 scene light), change nothing
#   auto-brightness.sh calibrate dark|bright
#                                   store the current room as the 0% (dark) or 100% (bright) end
#
# Why it locks the exposure: with the camera's auto-exposure on, the picture always looks
# about equally bright, so it says nothing about the room. We switch to manual exposure,
# pick a shutter time that gives a usable picture, and divide the picture level by that
# shutter time. The camera's own settings are put back afterwards. If another program is
# using the camera we do nothing, because changing its exposure would wreck the call.
#
# Needs: ffmpeg, v4l2-ctl, brightnessctl, awk. Settings in ~/.config/auto-brightness.conf.
set -u

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/auto-brightness.conf"
# Defaults, overridden by the config file. LO/HI are log10 of the scene light that maps to
# MIN% and MAX% (use `calibrate` instead of editing them by hand).
DEVICE=""            # empty = first camera that can capture video
LO=-4.7
HI=-1.7
MIN=5
MAX=100
SKIP=8               # frames dropped while the exposure settles
KEEP=4               # frames averaged afterwards
STEPS=20             # steps in the fade
DEADBAND=2           # leave the screen alone when already within this many percent
# shellcheck disable=SC1090
[[ -f "$CONF" ]] && source "$CONF"

die() { echo "auto-brightness: $*" >&2; exit 1; }
for tool in ffmpeg v4l2-ctl brightnessctl awk; do
    command -v "$tool" >/dev/null || die "$tool is not installed"
done

# --- pick the camera --------------------------------------------------------------------
find_device() {
    local d
    for d in /dev/video*; do
        [[ -e "$d" ]] || continue
        v4l2-ctl -d "$d" --list-formats 2>/dev/null | grep -qE "^\s*\[[0-9]+\]" && { echo "$d"; return; }
    done
}
[[ -n "$DEVICE" ]] || DEVICE=$(find_device)
[[ -n "$DEVICE" ]] || die "no camera found"

# Never touch a camera somebody else is streaming from.
if command -v fuser >/dev/null && fuser "$DEVICE" >/dev/null 2>&1; then
    die "the camera is in use, skipping"
fi

# One run at a time (the key repeats).
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/auto-brightness.lock"
flock -n 9 || exit 0

# --- camera settings: save, then restore on exit ----------------------------------------
ctrl() { v4l2-ctl -d "$DEVICE" --get-ctrl "$1" 2>/dev/null | awk -F': ' '{print $2}'; }
saved_ae=$(ctrl auto_exposure)
saved_exp=$(ctrl exposure_time_absolute)
saved_blc=$(ctrl backlight_compensation)
restore() {
    [[ -n "$saved_blc" ]] && v4l2-ctl -d "$DEVICE" -c backlight_compensation="$saved_blc" >/dev/null 2>&1
    [[ -n "$saved_exp" ]] && v4l2-ctl -d "$DEVICE" -c exposure_time_absolute="$saved_exp" >/dev/null 2>&1
    [[ -n "$saved_ae" ]] && v4l2-ctl -d "$DEVICE" -c auto_exposure="$saved_ae" >/dev/null 2>&1
}
trap restore EXIT

# Average luma (0-255) of the last frames at the given exposure (units of 100 us).
sample() {
    v4l2-ctl -d "$DEVICE" -c auto_exposure=1,backlight_compensation=0,exposure_time_absolute="$1" >/dev/null 2>&1
    ffmpeg -loglevel error -f v4l2 -video_size 320x240 -i "$DEVICE" -frames:v $((SKIP + KEEP)) \
        -vf "signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" -f null - 2>/dev/null \
        | awk -F= -v skip="$SKIP" '/YAVG=/ { n++; if (n > skip) { s += $2; c++ } } END { if (c) printf "%.2f", s / c }'
}

# Scene light as log10, from luma and the exposure used. Luma is gamma encoded, so undo
# that first; 0.003 is the sensor's black level, measured on this camera.
measure() {
    local exp=60 pass y
    for pass in 1 2 3; do
        y=$(sample "$exp")
        [[ -n "$y" ]] || return 1
        if awk -v y="$y" 'BEGIN { exit !(y < 35) }' && (( exp < 2047 )); then
            exp=$(( exp * 6 > 2047 ? 2047 : exp * 6 )); continue
        fi
        if awk -v y="$y" 'BEGIN { exit !(y > 215) }' && (( exp > 3 )); then
            exp=$(( exp / 6 < 3 ? 3 : exp / 6 )); continue
        fi
        break
    done
    awk -v y="$y" -v e="$exp" 'BEGIN {
        lin = (y / 255) ^ 2.2 - 0.003; if (lin < 1e-6) lin = 1e-6
        printf "%.3f", log(lin / e) / log(10)
    }'
}

level=$(measure) || die "could not read the camera"

case "${1:-}" in
    --measure) echo "scene light: $level (log10); dark end $LO, bright end $HI"; exit 0 ;;
    calibrate)
        key=${2:-}
        [[ "$key" == dark || "$key" == bright ]] || die "usage: calibrate dark|bright"
        var=LO; [[ "$key" == bright ]] && var=HI
        mkdir -p "$(dirname "$CONF")"; touch "$CONF"
        grep -v "^$var=" "$CONF" > "$CONF.tmp"; echo "$var=$level" >> "$CONF.tmp"; mv "$CONF.tmp" "$CONF"
        echo "saved $var=$level to $CONF"; exit 0 ;;
    "") ;;
    *) die "unknown option: $1" ;;
esac

# --- map to a percentage and fade there --------------------------------------------------
target=$(awk -v l="$level" -v lo="$LO" -v hi="$HI" -v mn="$MIN" -v mx="$MAX" 'BEGIN {
    if (hi <= lo) { print mx; exit }
    t = (l - lo) / (hi - lo); if (t < 0) t = 0; if (t > 1) t = 1
    printf "%d", mn + t * (mx - mn) + 0.5
}')
max_raw=$(brightnessctl max)
cur_raw=$(brightnessctl get)
cur_pct=$(( cur_raw * 100 / max_raw ))
echo "scene $level -> $target% (screen was $cur_pct%)"

diff=$(( target - cur_pct )); (( diff < 0 )) && diff=$(( -diff ))
(( diff <= DEADBAND )) && exit 0

target_raw=$(( target * max_raw / 100 ))
for (( i = 1; i <= STEPS; i++ )); do
    brightnessctl -q set $(( cur_raw + (target_raw - cur_raw) * i / STEPS )) >/dev/null 2>&1
    sleep 0.02
done
