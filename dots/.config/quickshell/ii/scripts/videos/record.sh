#!/usr/bin/env bash

# Clear AppImage library overrides to avoid breaking system commands like flatpak/obs
unset LD_LIBRARY_PATH
unset LD_PRELOAD

# Resolved up front: the recording branches cd into the save directory later.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
JSON_PATH=".screenRecord.savePath"
SERVICE_PATH=".screenRecord.service"

STATE_FILE="$HOME/.local/state/quickshell/states.json"
STATE_JSON_PATH=".screenRecord.active"

CUSTOM_PATH=$(jq -r "$JSON_PATH" "$CONFIG_FILE" 2>/dev/null)
# What the user asked for, before availability is considered. "auto" is the
# shipped default; the explicit values stay explicit when their recorder exists.
REC_SERVICE_CONFIG=$(jq -r "$SERVICE_PATH" "$CONFIG_FILE" 2>/dev/null)
if [[ -z "$REC_SERVICE_CONFIG" || "$REC_SERVICE_CONFIG" == "null" ]]; then
    REC_SERVICE_CONFIG="auto"
fi

REC_USE_GPU=$(jq -r ".screenRecord.useGpu" "$CONFIG_FILE" 2>/dev/null)
if [[ -z "$REC_USE_GPU" || "$REC_USE_GPU" == "null" ]]; then
    REC_USE_GPU="true"
fi

REC_CODEC=$(jq -r ".screenRecord.codec" "$CONFIG_FILE" 2>/dev/null)
if [[ -z "$REC_CODEC" || "$REC_CODEC" == "null" ]]; then
    REC_CODEC="auto"
fi

REC_RESOLUTION=$(jq -r ".screenRecord.resolution" "$CONFIG_FILE" 2>/dev/null)
if [[ -z "$REC_RESOLUTION" || "$REC_RESOLUTION" == "null" ]]; then
    REC_RESOLUTION="native"
fi

REC_QUALITY=$(jq -r ".screenRecord.quality" "$CONFIG_FILE" 2>/dev/null)
if [[ -z "$REC_QUALITY" || "$REC_QUALITY" == "null" ]]; then
    REC_QUALITY="balanced"
fi

REC_FRAMERATE=$(jq -r ".screenRecord.framerate" "$CONFIG_FILE" 2>/dev/null)
if [[ -z "$REC_FRAMERATE" || "$REC_FRAMERATE" == "null" ]]; then
    REC_FRAMERATE="60"
fi

REC_FRAME_SYNC=$(jq -r ".screenRecord.frameSync" "$CONFIG_FILE" 2>/dev/null)
if [[ -z "$REC_FRAME_SYNC" || "$REC_FRAME_SYNC" == "null" ]]; then
    REC_FRAME_SYNC="cfr"
fi

REC_RECORD_AUDIO=$(jq -r ".screenRecord.recordAudio" "$CONFIG_FILE" 2>/dev/null)
if [[ -z "$REC_RECORD_AUDIO" || "$REC_RECORD_AUDIO" == "null" ]]; then
    REC_RECORD_AUDIO="false"
fi

REC_SHOW_NOTIFICATIONS=$(jq -r ".screenRecord.showNotifications" "$CONFIG_FILE" 2>/dev/null)
if [[ -z "$REC_SHOW_NOTIFICATIONS" || "$REC_SHOW_NOTIFICATIONS" == "null" ]]; then
    REC_SHOW_NOTIFICATIONS="true"
fi

REC_USE_TOOLBAR=$(jq -r ".screenRecord.useToolbar" "$CONFIG_FILE" 2>/dev/null)
if [[ -z "$REC_USE_TOOLBAR" || "$REC_USE_TOOLBAR" == "null" ]]; then
    REC_USE_TOOLBAR="true"
fi

REC_FORMAT=$(jq -r ".screenRecord.format" "$CONFIG_FILE" 2>/dev/null)
if [[ -z "$REC_FORMAT" || "$REC_FORMAT" == "null" ]]; then
    REC_FORMAT="mp4"
fi


REC_RECORD_MIC=$(jq -r ".screenRecord.recordMic" "$CONFIG_FILE" 2>/dev/null)
if [[ -z "$REC_RECORD_MIC" || "$REC_RECORD_MIC" == "null" ]]; then
    REC_RECORD_MIC="false"
fi

REC_MIC_DEVICE=$(jq -r ".screenRecord.micDevice" "$CONFIG_FILE" 2>/dev/null)
if [[ -z "$REC_MIC_DEVICE" || "$REC_MIC_DEVICE" == "null" ]]; then
    REC_MIC_DEVICE=""
fi

RECORDING_DIR=""

TIMER_PID=""  
SECONDS_ELAPSED=-1
RECORDING_SESSION=0
RECORDER_PID=""

if [[ -n "$CUSTOM_PATH" ]]; then
    RECORDING_DIR="$CUSTOM_PATH"
else
    RECORDING_DIR="$HOME/Videos"
fi

start_timer() {
    if [[ -n "$TIMER_PID" ]]; then
        kill "$TIMER_PID" 2>/dev/null
    fi

    ( 
        while true; do
            IS_PAUSED=$(jq -r ".screenRecord.paused" "$STATE_FILE" 2>/dev/null)
            if [[ "$IS_PAUSED" != "true" ]]; then
                SECONDS_ELAPSED=$((SECONDS_ELAPSED + 1))
                jq ".screenRecord.seconds = $SECONDS_ELAPSED" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
            fi
            sleep 1
        done
    ) &
    TIMER_PID=$!
}
stop_timer() {
    if [[ -n "$TIMER_PID" ]]; then
        kill "$TIMER_PID" 2>/dev/null
        wait "$TIMER_PID" 2>/dev/null
        TIMER_PID=""
        jq ".screenRecord.seconds = 0" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi
}

cleanup() {
    stop_timer
    # A recording session owns the state until it is done. If this process is
    # terminated while one is running, stop the child cleanly and clear the
    # state so the bar cannot be left showing a recording that ended.
    if [[ "${RECORDING_SESSION:-0}" == "1" ]]; then
        if [[ -n "${RECORDER_PID:-}" ]] && kill -0 "$RECORDER_PID" 2>/dev/null; then
            kill -CONT "$RECORDER_PID" 2>/dev/null
            kill -INT "$RECORDER_PID" 2>/dev/null
        fi
        updatestate false
    fi
}

trap cleanup EXIT

getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}

getaudiooutput() {
    local default_sink default_monitor monitor

    # The first monitor returned by pactl is not necessarily the monitor of
    # the current output (HDMI, USB and Bluetooth monitors can all precede it).
    # Start with PipeWire/PulseAudio's actual default sink so desktop audio is
    # captured from what the user is hearing.
    default_sink=$(pactl get-default-sink 2>/dev/null)
    if [[ -n "$default_sink" && "$default_sink" != "null" ]]; then
        default_monitor="${default_sink}.monitor"
        monitor=$(pactl list short sources 2>/dev/null | awk -v wanted="$default_monitor" '$2 == wanted { print $2; exit }')
        if [[ -n "$monitor" ]]; then
            echo "$monitor"
            return
        fi
    fi

    # Fallback for unusual PulseAudio setups without a matching default sink.
    monitor=$(pactl list short sources 2>/dev/null | awk '$2 ~ /\.monitor$/ { print $2; exit }')
    if [[ -z "$monitor" ]]; then
        return
    else
        echo "$monitor"
    fi
}
getactivemonitor() {
    local active=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name' 2>/dev/null)
    if [[ -z "$active" || "$active" == "null" ]]; then
        # Fallback to the first monitor
        active=$(hyprctl monitors -j | jq -r '.[0].name' 2>/dev/null)
    fi
    if [[ -z "$active" || "$active" == "null" ]]; then
        # Second fallback
        active=$(hyprctl activeworkspace -j | jq -r '.monitor' 2>/dev/null)
    fi
    echo "$active"
}

# gpu-screen-recorder's process name is longer than pgrep's 15-character
# comm limit, so -x can never match it; the full command line is the only
# reliable handle.
gsr_pid() {
    pgrep -f '(^|/)gpu-screen-recorder( |$)' 2>/dev/null | head -n1
}

service_available() {
    case "$1" in
        gsr) command -v gpu-screen-recorder >/dev/null 2>&1 ;;
        wf-recorder) command -v wf-recorder >/dev/null 2>&1 ;;
        obs)
            command -v obs >/dev/null 2>&1 && return 0
            command -v flatpak >/dev/null 2>&1 &&
                flatpak list --app --columns=application 2>/dev/null | grep -qx com.obsproject.Studio
            ;;
        *) return 1 ;;
    esac
}

# Pick the recorder for this run. An explicit choice is honoured while its
# program exists; otherwise (and for "auto") the most capable backend wins:
# GPU Screen Recorder, then wf-recorder, then OBS. OBS is last because it
# needs a configured scene and its WebSocket API, while the other two record
# immediately.
resolve_service() {
    local requested="${1:-auto}" candidate
    [[ "$requested" == "gpu-screen-recorder" ]] && requested="gsr"

    case "$requested" in
        gsr|wf-recorder|obs)
            if service_available "$requested"; then
                printf '%s' "$requested"
                return 0
            fi
            ;;
    esac

    for candidate in gsr wf-recorder obs; do
        if service_available "$candidate"; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

# Actually try to encode one frame with the given hardware codec, rather than
# trusting `ffmpeg -encoders` (which only reflects what ffmpeg was compiled
# with, not whether the hardware/driver behind it is actually present).
test_encoder() {
    local codec="$1"
    case "$codec" in
        h264_vaapi|hevc_vaapi)
            [ -e /dev/dri/renderD128 ] || return 1
            ffmpeg -y -v error -init_hw_device vaapi=va:/dev/dri/renderD128 -filter_hw_device va \
                -f lavfi -i testsrc=size=128x128:rate=1 -frames:v 1 -vf format=nv12,hwupload \
                -c:v "$codec" -f null - &>/dev/null
            ;;
        *)
            ffmpeg -y -v error -f lavfi -i testsrc=size=128x128:rate=1 -frames:v 1 \
                -c:v "$codec" -f null - &>/dev/null
            ;;
    esac
}

get_best_codec() {
    # If the user explicitly chose a CPU codec:
    if [[ "$REC_CODEC" == "libx264" || "$REC_CODEC" == "libx265" ]]; then
        echo "$REC_CODEC"
        return
    fi

    # If the user disabled GPU acceleration:
    if [[ "$REC_USE_GPU" != "true" ]]; then
        if [[ "$REC_CODEC" == "hevc_"* || "$REC_CODEC" == "libx265" ]]; then
            echo "libx265"
        else
            echo "libx264"
        fi
        return
    fi

    # If the user explicitly chose a GPU codec:
    if [[ "$REC_CODEC" != "auto" ]]; then
        if ffmpeg -encoders 2>/dev/null | grep -q "$REC_CODEC" && test_encoder "$REC_CODEC"; then
            echo "$REC_CODEC"
            return
        fi
    fi

    # If "auto" or the chosen GPU codec doesn't actually work, auto-detect by
    # probing each hardware encoder in turn:
    if ffmpeg -encoders 2>/dev/null | grep -q "h264_nvenc" && test_encoder "h264_nvenc"; then
        echo "h264_nvenc"
    elif ffmpeg -encoders 2>/dev/null | grep -q "h264_vaapi" && test_encoder "h264_vaapi"; then
        echo "h264_vaapi"
    elif ffmpeg -encoders 2>/dev/null | grep -q "h264_amf" && test_encoder "h264_amf"; then
        echo "h264_amf"
    else
        echo "libx264"
    fi
}

# GPU Screen Recorder has its own codec vocabulary (h264/hevc/vp9/av1), so the
# ffmpeg encoder names in the settings collapse to the codec family. CPU
# encoding only exists for H.264 there.
gsr_codec() {
    case "$REC_CODEC" in
        hevc*|libx265) echo "hevc" ;;
        h264*|libx264) echo "h264" ;;
        *) echo "auto" ;;
    esac
}

# GSR's three quality presets line up with the settings page's low/balanced/high.
gsr_quality() {
    case "$REC_QUALITY" in
        low) echo "medium" ;;
        high) echo "very_high" ;;
        *) echo "high" ;;
    esac
}

# ── Quality: a resolution and a frame rate instead of a raw bitrate ──────────
# Mbps means nothing on its own — the same number is generous at 720p and starved
# at 4K — so the bitrate is derived from the pixels actually being encoded. The
# bits-per-pixel figures below are mirrored in ScreenRecordingConfig.qml so the
# settings page can show the same estimate before recording starts;
# test_screen_recording_contract.py fails if the two drift apart.
QUALITY_BPP_LOW="0.05"
QUALITY_BPP_BALANCED="0.09"
QUALITY_BPP_HIGH="0.15"
BITRATE_FLOOR_MBPS="1.5"
BITRATE_CEILING_MBPS="80"

# The target box a recording is fitted into, aspect ratio preserved. Empty means
# "native": whatever the screen or the selected region already is.
resolution_box() {
    case "$REC_RESOLUTION" in
        2160p) echo "3840 2160" ;;
        1440p) echo "2560 1440" ;;
        1080p) echo "1920 1080" ;;
        720p) echo "1280 720" ;;
        480p) echo "854 480" ;;
        *) echo "" ;;
    esac
}

quality_bpp() {
    case "$REC_QUALITY" in
        low) echo "$QUALITY_BPP_LOW" ;;
        high) echo "$QUALITY_BPP_HIGH" ;;
        *) echo "$QUALITY_BPP_BALANCED" ;;
    esac
}

# Hyprland reports a monitor's mode in physical pixels but positions it in
# logical ones, so a region's pixel count is its logical size times the scale of
# the monitor it lands on.
monitor_scale_at() {
    local x=$1 y=$2
    local scale
    scale=$(hyprctl monitors -j 2>/dev/null | jq -r --argjson x "$x" --argjson y "$y" \
        '[.[] | select($x >= .x and $y >= .y and $x < (.x + (.width / .scale)) and $y < (.y + (.height / .scale)))][0].scale // 1' 2>/dev/null)
    if [[ -z "$scale" || "$scale" == "null" ]]; then
        scale="1"
    fi
    echo "$scale"
}

# The size a recording is actually encoded at: fitted inside the resolution
# preset, aspect preserved, never scaled up. Scaling a small region up to a big
# preset only wastes bits, so the preset is a ceiling rather than a target.
fit_size() {
    local src_w=$1 src_h=$2 box_w box_h

    read -r box_w box_h <<< "$(resolution_box)"
    if [[ -n "$box_w" ]] && (( src_w > box_w || src_h > box_h )); then
        awk -v sw="$src_w" -v sh="$src_h" -v bw="$box_w" -v bh="$box_h" 'BEGIN {
            ratio = bw / sw
            if (bh / sh < ratio) ratio = bh / sh
            w = int(sw * ratio / 2) * 2
            h = int(sh * ratio / 2) * 2
            if (w < 2) w = 2
            if (h < 2) h = 2
            print w, h
        }'
    else
        echo "$src_w $src_h"
    fi
}

# The bitrate the pixels and frame rate are worth. Shared by the wf-recorder
# path and the size estimate, so the two cannot disagree.
bitrate_for() {
    local out_w=$1 out_h=$2

    awk -v w="$out_w" -v h="$out_h" -v fps="$REC_FRAMERATE" -v bpp="$(quality_bpp)" \
        -v lo="$BITRATE_FLOOR_MBPS" -v hi="$BITRATE_CEILING_MBPS" 'BEGIN {
        mbps = w * h * fps * bpp / 1000000
        if (mbps < lo) mbps = lo
        if (mbps > hi) mbps = hi
        printf "%.1f", mbps
    }'
}

# Appends the scaling filter and the derived bitrate to CODEC_OPTS, now that the
# size of what is about to be captured is known.
apply_quality() {
    local src_w=$1 src_h=$2 codec=$3
    local box_w box_h out_w out_h bitrate

    read -r box_w box_h <<< "$(resolution_box)"
    read -r out_w out_h <<< "$(fit_size "$src_w" "$src_h")"

    if [[ -n "$box_w" ]] && (( src_w > box_w || src_h > box_h )); then
        if [[ "$codec" == *_vaapi ]]; then
            # VAAPI frames live on the GPU by the time the filter runs, so the
            # scaler has to be the VAAPI one; the CPU `scale` would never see them.
            CODEC_OPTS+=("-F" "scale_vaapi=w=${box_w}:h=${box_h}:force_original_aspect_ratio=decrease:force_divisible_by=2:format=nv12")
        else
            CODEC_OPTS+=("-F" "scale=${box_w}:${box_h}:force_original_aspect_ratio=decrease:force_divisible_by=2")
        fi
    fi

    bitrate=$(bitrate_for "$out_w" "$out_h")
    CODEC_OPTS+=("-p" "b=${bitrate}M")
}

notify-send() {
    if [[ "$REC_SHOW_NOTIFICATIONS" == "true" ]]; then
        command notify-send "$@"
    fi
}

updateloading() {
    local state_value=$1
    jq ".screenRecord.loading = $state_value" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

updatestate() {
    local state_value=$1
    if [[ "$state_value" == "true" ]]; then
        jq "$STATE_JSON_PATH = true | .screenRecord.loading = false" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        start_timer
    else
        # Stop the writer before clearing the flag: a timer tick that already
        # read active=true could otherwise land its jq write afterwards and
        # resurrect a recording that has just ended.
        stop_timer
        jq "$STATE_JSON_PATH = false | .screenRecord.loading = false | .screenRecord.paused = false | .screenRecord.seconds = 0" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi
}

toggle_pause() {
    local current_paused=$(jq -r ".screenRecord.paused" "$STATE_FILE" 2>/dev/null)
    local target_paused="true"
    if [[ "$current_paused" == "true" ]]; then
        target_paused="false"
    fi

    # Act on the recorder FIRST, and only mirror the new state if it worked. A failed
    # pause that still flips the state file leaves the UI lying about the recording.
    if [[ "$REC_SERVICE" == "obs" ]] && { pgrep -x "obs" > /dev/null || pgrep -f "com.obsproject.Studio" > /dev/null; }; then
        python3 "$SCRIPT_DIR/obs_pause.py" 2>/dev/null || return
    elif GSR_ACTIVE_PID=$(gsr_pid) && [[ -n "$GSR_ACTIVE_PID" ]]; then
        # GSR toggles its own pause state on SIGUSR2, so the video keeps a
        # correct timeline instead of freezing a frame the way SIGSTOP does.
        kill -USR2 "$GSR_ACTIVE_PID" 2>/dev/null || return
    elif pgrep -x wf-recorder > /dev/null; then
        # wf-recorder has no pause feature and installs no SIGUSR1 handler, so the
        # default action applies: SIGUSR1 terminates it. That is why pausing used to
        # end the recording. Suspending the process instead keeps the encoder and the
        # output file alive; the paused span shows up as a still frame in the video.
        if [[ "$target_paused" == "true" ]]; then
            pkill -STOP -x wf-recorder || return
        else
            pkill -CONT -x wf-recorder || return
        fi
    else
        return
    fi

    if [[ "$target_paused" == "true" ]]; then
        jq ".screenRecord.paused = true" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        notify-send "Recording Paused" -a 'Recorder' &
    else
        jq ".screenRecord.paused = false" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        notify-send "Recording Resumed" -a 'Recorder' &
    fi
}

# Resolve before anything else touches the recorder. A configured backend that
# was uninstalled (or the "auto" default) falls through to the next one instead
# of failing the recording.
if ! REC_SERVICE=$(resolve_service "$REC_SERVICE_CONFIG"); then
    notify-send "No Screen Recorder" "Install GPU Screen Recorder, wf-recorder, or OBS Studio" -a 'Recorder' &
    exit 1
fi

mkdir -p "$RECORDING_DIR"
cd "$RECORDING_DIR" || exit

ARGS=("$@")

if [[ "${ARGS[0]}" == "--pause" ]]; then
    toggle_pause
    exit 0
fi

MANUAL_REGION=""
# The setting turns sound on for every entry point (bar, keybinds, IPC);
# --sound still forces it for a single recording when the setting is off.
SOUND_FLAG=0
if [[ "$REC_RECORD_AUDIO" == "true" ]]; then
    SOUND_FLAG=1
fi
FULLSCREEN_FLAG=0
REGION_FLAG=0
WINDOW_FLAG=0
OBS_FLAG=0
FORCE_RECORD_FLAG=0

for ((i=0;i<${#ARGS[@]};i++)); do
    if [[ "${ARGS[i]}" == "--force-record" ]]; then
        FORCE_RECORD_FLAG=1
    elif [[ "${ARGS[i]}" == "--region" ]]; then
        REGION_FLAG=1
        if (( i+1 < ${#ARGS[@]} )) && [[ ! "${ARGS[i+1]}" =~ ^-- ]]; then
            MANUAL_REGION="${ARGS[i+1]}"
            i=$((i+1))
        fi
    elif [[ "${ARGS[i]}" == "--window" ]]; then
        WINDOW_FLAG=1
    elif [[ "${ARGS[i]}" == "--sound" ]]; then
        SOUND_FLAG=1
    elif [[ "${ARGS[i]}" == "--fullscreen" ]]; then
        FULLSCREEN_FLAG=1
    elif [[ "${ARGS[i]}" == "--obs" ]]; then
        OBS_FLAG=1
    fi
done

AUDIO_ARGS=()
if [[ "$REC_SERVICE" == "wf-recorder" && $SOUND_FLAG -eq 1 ]]; then
    AUDIO_DEVICE=$(getaudiooutput)
    if [[ -n "$AUDIO_DEVICE" ]]; then
        AUDIO_ARGS=("--audio=$AUDIO_DEVICE")
    else
        # Let wf-recorder select its backend's default source when pactl cannot
        # expose a monitor name (for example during an audio-server restart).
        AUDIO_ARGS=("--audio")
    fi
    # ffmpeg's AAC default of 128 kb/s audibly dulls music. wf-recorder 0.6.0
    # drops -P options (avcodec_open2 gets NULL instead of the dictionary), so
    # this only takes effect once a release carries the upstream fix; until
    # then it is ignored harmlessly and audio stays at 128 kb/s.
    AUDIO_ARGS+=("-C" "aac" "-P" "b=320k")
fi

IS_OBS_RECORDING=0
if [[ "$REC_SERVICE" == "obs" ]]; then
    if pgrep -x "obs" > /dev/null || pgrep -f "com.obsproject.Studio" > /dev/null; then
        STATUS=$(python3 "$SCRIPT_DIR/obs_control.py" status 2>/dev/null)
        if [[ "$STATUS" == "active" ]]; then
            IS_OBS_RECORDING=1
        fi
    fi
fi

GSR_ACTIVE_PID=$(gsr_pid)
if [[ -n "$GSR_ACTIVE_PID" ]]; then
    notify-send "Recording Stopped" "Stopped" -a 'Recorder' &
    updatestate false
    # SIGINT is GSR's "stop and save": it flushes the container and exits. Wait
    # for that before returning so a restart does not race the finalizer.
    kill -INT "$GSR_ACTIVE_PID" 2>/dev/null
    for _ in {1..50}; do
        kill -0 "$GSR_ACTIVE_PID" 2>/dev/null || break
        sleep 0.2
    done
    if kill -0 "$GSR_ACTIVE_PID" 2>/dev/null; then
        kill -TERM "$GSR_ACTIVE_PID" 2>/dev/null
    fi
    exit 0
fi

if pgrep wf-recorder > /dev/null; then
    notify-send "Recording Stopped" "Stopped" -a 'Recorder' &
    updatestate false
    # A paused recorder is SIGSTOPped: it cannot run its shutdown handler (and would
    # never flush the file) until it is resumed, so always continue it before killing.
    pkill -CONT -x wf-recorder 2>/dev/null
    pkill wf-recorder &
    exit 0
fi

if [[ $IS_OBS_RECORDING -eq 1 ]]; then
    notify-send "Stopping OBS Recording..." "Saving file..." -a 'Recorder' &
    python3 "$SCRIPT_DIR/obs_control.py" stop
    sleep 1.5
    pkill -x "obs" || pkill -f "com.obsproject.Studio"
    exit 0
fi

# The state file can outlive its recorder: a killed script, a shell restart or a
# recorder crash leaves active=true with nothing running. Without this the bar's
# stop button starts a brand-new recording and asks for a region, which looks
# exactly like a stop that is being ignored.
if [[ "$(jq -r "$STATE_JSON_PATH" "$STATE_FILE" 2>/dev/null)" == "true" ]]; then
    notify-send "Recording Stopped" "The recorder was no longer running" -a 'Recorder' &
    updatestate false
    exit 0
fi

# If toolbar is enabled, open the toolbar instead of recording directly
if [[ "$REC_USE_TOOLBAR" == "true" && $FORCE_RECORD_FLAG -eq 0 ]]; then
    qs -c ii ipc call recordingToolbar open
    exit 0
fi


if [[ $WINDOW_FLAG -eq 1 && -z "$MANUAL_REGION" ]]; then
    ACTIVE_WIN=$(hyprctl activewindow -j 2>/dev/null)
    WIN_ADDR=$(echo "$ACTIVE_WIN" | jq -r '.address // empty' 2>/dev/null)
    if [[ -n "$WIN_ADDR" && "$WIN_ADDR" != "null" && "$WIN_ADDR" != "0x0" ]]; then
        WIN_X=$(echo "$ACTIVE_WIN" | jq -r '.at[0]' 2>/dev/null)
        WIN_Y=$(echo "$ACTIVE_WIN" | jq -r '.at[1]' 2>/dev/null)
        WIN_W=$(echo "$ACTIVE_WIN" | jq -r '.size[0]' 2>/dev/null)
        WIN_H=$(echo "$ACTIVE_WIN" | jq -r '.size[1]' 2>/dev/null)

        MANUAL_REGION="${WIN_X},${WIN_Y} ${WIN_W}x${WIN_H}"
    else
        # Fallback to interactive region selection if no window is active
        REGION_FLAG=1
    fi
fi

if [[ $REGION_FLAG -eq 1 && -z "$MANUAL_REGION" ]]; then
    # Interactive region selection
    MANUAL_REGION=$(slurp)
    if [[ -z "$MANUAL_REGION" ]]; then
        # notify-send "Recording cancelled" "No region selected" -a 'Recorder' & disown
        exit 0
    fi
fi
OBS_CMD=""
if [[ "$REC_SERVICE" == "obs" ]]; then
    if [[ -d "/var/lib/flatpak/app/com.obsproject.Studio" || -d "$HOME/.local/share/flatpak/app/com.obsproject.Studio" ]]; then
        OBS_CMD="flatpak run com.obsproject.Studio"
    elif command -v obs &> /dev/null; then
        OBS_CMD="obs"
    elif flatpak list 2>/dev/null | grep -q "com.obsproject.Studio"; then
        OBS_CMD="flatpak run com.obsproject.Studio"
    fi
fi

# Set loading state immediately to give UI feedback
updateloading true

if [[ -n "$OBS_CMD" ]]; then
    OBS_WAS_RUNNING=0
    if pgrep -x "obs" > /dev/null || pgrep -f "com.obsproject.Studio" > /dev/null; then
        OBS_WAS_RUNNING=1
    fi

    if [[ $OBS_WAS_RUNNING -eq 0 ]]; then
        notify-send "Starting OBS..." "OBS starting, please wait..." -a 'Recorder' &
        # Do NOT pass --startrecording here: OBS would open the xdg-desktop-portal
        # screen-picker dialog. Instead, open OBS minimized with its saved scenes,
        # then trigger recording via WebSocket so it uses the pre-configured sources.
        nohup $OBS_CMD --minimize-to-tray > /dev/null 2>&1 &

        # Wait for OBS process to appear
        for i in {1..30}; do
            if pgrep -x "obs" > /dev/null || pgrep -f "com.obsproject.Studio" > /dev/null; then
                break
            fi
            sleep 1
        done
    fi

    # Wait for WebSocket server to become available (OBS needs a few seconds after
    # process launch before the WebSocket server is ready to accept requests).
    # obs_control.py now returns "error" when the connection itself fails, so we
    # can keep waiting instead of mistaking the failure for an idle recording state.
    WEBSOCKET_READY=0
    for i in {1..30}; do
        STATUS=$(python3 "$SCRIPT_DIR/obs_control.py" status 2>/dev/null)
        if [[ "$STATUS" == "inactive" || "$STATUS" == "active" ]]; then
            WEBSOCKET_READY=1
            break
        fi
        sleep 1
    done

    if [[ $WEBSOCKET_READY -eq 0 ]]; then
        notify-send "OBS Error" "Could not reach OBS WebSocket server. Check OBS -> Tools -> WebSocket Server Settings." -a 'Recorder' &
        pkill -x "obs" 2>/dev/null || pkill -f "com.obsproject.Studio" 2>/dev/null
        updatestate false
        exit 1
    fi

    notify-send "Starting OBS Recording..." "Triggering via WebSocket" -a 'Recorder' &
    python3 "$SCRIPT_DIR/obs_control.py" start

    # Wait for the recording to actually become active before entering the watchdog
    # loop. This is critical: a Wayland pipewire-screen-cast source may pop up the
    # xdg-desktop-portal screen picker when start_record() is issued, and the user
    # needs time to choose a monitor. Until they do, status stays "inactive" and the
    # previous watchdog would have killed OBS immediately (the original bug).
    RECORDING_ACTIVE=0
    for i in {1..60}; do
        if ! pgrep -x "obs" > /dev/null && ! pgrep -f "com.obsproject.Studio" > /dev/null; then
            break
        fi
        STATUS=$(python3 "$SCRIPT_DIR/obs_control.py" status 2>/dev/null)
        if [[ "$STATUS" == "active" ]]; then
            RECORDING_ACTIVE=1
            break
        fi
        if [[ "$STATUS" == "error" ]]; then
            break
        fi
        sleep 1
    done

    if [[ $RECORDING_ACTIVE -eq 0 ]]; then
        notify-send "Recording Failed" "OBS did not start recording. Make sure your scene has a screen capture source and accept the Wayland portal dialog if it appears." -a 'Recorder' &
        sleep 2
        pkill -x "obs" 2>/dev/null || pkill -f "com.obsproject.Studio" 2>/dev/null
        updatestate false
        exit 1
    fi

    updatestate true

    # Now that we have confirmed the recording is "active", watch for it to become
    # "inactive" (which means the user stopped it via a second record.sh call) or
    # for OBS to be killed externally.
    while true; do
        if ! pgrep -x "obs" > /dev/null && ! pgrep -f "com.obsproject.Studio" > /dev/null; then
            break
        fi
        STATUS=$(python3 "$SCRIPT_DIR/obs_control.py" status 2>/dev/null)
        if [[ "$STATUS" != "active" ]]; then
            # Recording stopped. Give OBS a moment to flush the file, then close it.
            sleep 1
            pkill -x "obs" 2>/dev/null || pkill -f "com.obsproject.Studio" 2>/dev/null
            break
        fi
        sleep 1
    done
    
    if [[ -n "$MANUAL_REGION" ]]; then
        notify-send "Processing Region..." "Cropping video, please wait..." -a 'Recorder' &
        LATEST_FILE=$(ls -1t | grep -E '\.(mp4|mkv|flv|mov)$' | head -1)
        if [[ -n "$LATEST_FILE" ]]; then
             # MANUAL_REGION is in format "X,Y WxH" (slurp)
             # ffmpeg crop filter: crop=w:h:x:y
             W=$(echo "$MANUAL_REGION" | cut -d' ' -f2 | cut -d'x' -f1)
             H=$(echo "$MANUAL_REGION" | cut -d' ' -f2 | cut -d'x' -f2)
             X=$(echo "$MANUAL_REGION" | cut -d' ' -f1 | cut -d',' -f1)
             Y=$(echo "$MANUAL_REGION" | cut -d' ' -f1 | cut -d',' -f2)
             
             ffmpeg -i "$LATEST_FILE" -filter:v "crop=$W:$H:$X:$Y" "cropped_$LATEST_FILE" -y && mv "cropped_$LATEST_FILE" "$LATEST_FILE"
             notify-send "Recording Finished" "Saved to: $PWD/$LATEST_FILE" -a 'Recorder' &
        fi
    fi

    LATEST_FILE=$(ls -1t | grep -E '\.(mp4|mkv|flv|mov)$' | head -1)
    if [[ -n "$LATEST_FILE" ]]; then
        notify-send "Recording Finished" "Saved to: $PWD/$LATEST_FILE" -a 'Recorder' &
        qs -c ii ipc call launchVideoEditor handle "$PWD/$LATEST_FILE"
    fi

    updatestate false
    exit 0
elif [[ "$REC_SERVICE" == "gsr" ]]; then
    GSR_FORMAT="$REC_FORMAT"
    case "$GSR_FORMAT" in
        mp4|mkv|webm|flv) ;;
        # GSR has no animated-image muxer. Record the clip as MP4 instead of
        # failing after the format was picked in the toolbar.
        *) GSR_FORMAT="mp4" ;;
    esac
    FILENAME="recording_$(getdate).${GSR_FORMAT}"

    GSR_CODEC="$(gsr_codec)"
    GSR_ENCODER_ARGS=()
    if [[ "$GSR_FORMAT" == "webm" ]]; then
        # WebM carries VP8/VP9/AV1 and Opus, never H.264 or AAC.
        GSR_CODEC="vp9"
    fi
    if [[ "$REC_USE_GPU" != "true" || "$REC_CODEC" == "libx264" ]]; then
        # GSR's CPU encoder is H.264 only; it has no software HEVC.
        GSR_ENCODER_ARGS=("-encoder" "cpu")
        GSR_CODEC="h264"
    fi

    if [[ "$REC_FRAME_SYNC" == "vfr" ]]; then
        GSR_FRAME_SYNC="vfr"
    else
        GSR_FRAME_SYNC="cfr"
    fi

    GSR_ARGS=(-f "$REC_FRAMERATE" -k "$GSR_CODEC" -q "$(gsr_quality)"
        -fm "$GSR_FRAME_SYNC" -c "$GSR_FORMAT" -cursor yes
        -fallback-cpu-encoding yes -o "$FILENAME")
    [[ ${#GSR_ENCODER_ARGS[@]} -gt 0 ]] && GSR_ARGS+=("${GSR_ENCODER_ARGS[@]}")

    if [[ $SOUND_FLAG -eq 1 ]]; then
        # GSR follows PipeWire's default output, unlike the monitor source name
        # wf-recorder wants, so no pactl lookup is needed here.
        GSR_AUDIO="default_output"
        if [[ "$REC_RECORD_MIC" == "true" ]]; then
            GSR_AUDIO+="|${REC_MIC_DEVICE:-default_input}"
        fi
        GSR_ARGS+=(-a "$GSR_AUDIO" -ab 320)
        if [[ "$GSR_FORMAT" == "webm" ]]; then
            GSR_ARGS+=(-ac opus)
        else
            GSR_ARGS+=(-ac aac)
        fi
    fi

    if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
        MONITOR="$(getactivemonitor)"
        [[ -z "$MONITOR" || "$MONITOR" == "null" ]] && MONITOR="screen"
        read -r MON_W MON_H <<< "$(hyprctl monitors -j 2>/dev/null | jq -r --arg m "$MONITOR" \
            '[.[] | select(.name == $m)][0] | "\(.width) \(.height)"' 2>/dev/null)"
        if [[ -z "$MON_W" || "$MON_W" == "null" ]]; then
            MON_W=1920
            MON_H=1080
        fi
        if [[ -n "$(resolution_box)" ]]; then
            read -r GSR_W GSR_H <<< "$(fit_size "$MON_W" "$MON_H")"
            GSR_ARGS+=(-s "${GSR_W}x${GSR_H}")
        fi
        GSR_ARGS+=(-w "$MONITOR")
    else
        if [[ -n "$MANUAL_REGION" ]]; then
            region="$MANUAL_REGION"
        else
            if ! region="$(slurp 2>&1)"; then
                notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
                updatestate false
                exit 1
            fi
        fi

        pos="${region%% *}"      # x,y (logical)
        size="${region##* }"     # WxH (logical)
        x="${pos%,*}"
        y="${pos#*,}"

        # GSR takes slurp's logical coordinates directly; only the encoded size
        # needs the monitor scale to derive a bitrate/preview resolution.
        region_scale="$(monitor_scale_at "$x" "$y")"
        read -r REGION_W REGION_H <<< "$(awk -v s="${size%x*}" -v t="${size#*x}" -v scale="$region_scale" 'BEGIN {
            printf "%d %d", int(s * scale + 0.5), int(t * scale + 0.5)
        }')"
        if [[ -n "$(resolution_box)" ]]; then
            read -r GSR_W GSR_H <<< "$(fit_size "$REGION_W" "$REGION_H")"
            GSR_ARGS+=(-s "${GSR_W}x${GSR_H}")
        fi
        GSR_ARGS+=(-w "${size}+${x}+${y}")
    fi

    notify-send "Starting recording" "$FILENAME" -a 'Recorder' & disown
    RECORDING_SESSION=1
    updatestate true
    gpu-screen-recorder "${GSR_ARGS[@]}" &
    RECORDER_PID=$!
    wait "$RECORDER_PID"
    RECORDING_SESSION=0

    if [[ ! -s "$FILENAME" ]]; then
        notify-send "Recording Failed" "GPU Screen Recorder did not write $FILENAME" -a 'Recorder' &
    fi

    if [[ -s "$FILENAME" ]]; then
        notify-send "Recording Finished" "Saved to: $PWD/$FILENAME" -a 'Recorder' &
        qs -c ii ipc call launchVideoEditor handle "$PWD/$FILENAME"
    fi
    updatestate false
else
    FILENAME="recording_$(getdate).${REC_FORMAT}"
    
    CODEC=$(get_best_codec)
    CODEC_OPTS=("-c" "$CODEC")

    # wf-recorder's -r *is* the constant-frame-rate switch: it holds the given
    # rate by repeating frames when the screen is idle. Leaving it out is what
    # gives the variable rate, where a frame only exists when something changed.
    if [[ "$REC_FRAME_SYNC" != "vfr" ]]; then
        CODEC_OPTS+=("-r" "$REC_FRAMERATE")
    fi

    if [[ "$CODEC" == "h264_vaapi" || "$CODEC" == "hevc_vaapi" ]]; then
        # Do NOT force --pixel-format nv12 here: it makes wf-recorder insert a
        # scale_vaapi conversion step that some VAAPI drivers (e.g. Intel Xe/Arc)
        # refuse with "Failed to configure graph filter: Function not implemented".
        # Letting wf-recorder auto-negotiate the pixel format works everywhere.
        CODEC_OPTS+=("-d" "/dev/dri/renderD128")
    elif [[ "$CODEC" == "h264_amf" || "$CODEC" == "hevc_amf" ]]; then
        CODEC_OPTS+=("--pixel-format" "nv12")
    elif [[ "$CODEC" == "h264_nvenc" || "$CODEC" == "hevc_nvenc" ]]; then
        CODEC_OPTS+=("--pixel-format" "yuv420p")
    else
        CODEC_OPTS+=("--pixel-format" "yuv420p")
    fi

    # wf-recorder converts the screen to limited-range video but flags the file
    # as full range (yuvj), so players skip the range expansion and the picture looks
    # washed out; re-encoding sites like Discord ignore the flag, which is why it
    # looks right there. Label what is actually written: the VAAPI scaler uses
    # BT.709, swscale (every other path) its BT.601 default.
    if [[ "$CODEC" == *_vaapi ]]; then
        COLOR_MATRIX="bt709"
    else
        COLOR_MATRIX="smpte170m"
    fi
    CODEC_OPTS+=("-p" "color_range=tv" "-p" "colorspace=$COLOR_MATRIX"
        "-p" "color_primaries=bt709" "-p" "color_trc=bt709")

    if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
        MONITOR="$(getactivemonitor)"
        read -r MON_W MON_H <<< "$(hyprctl monitors -j 2>/dev/null | jq -r --arg m "$MONITOR" \
            '[.[] | select(.name == $m)][0] | "\(.width) \(.height)"' 2>/dev/null)"
        if [[ -z "$MON_W" || "$MON_W" == "null" ]]; then
            MON_W=1920
            MON_H=1080
        fi
        apply_quality "$MON_W" "$MON_H" "$CODEC"

        notify-send "Starting recording" "$FILENAME" -a 'Recorder' & disown
        RECORDING_SESSION=1
        updatestate true
        wf-recorder -o "$MONITOR" "${CODEC_OPTS[@]}" -f "$FILENAME" "${AUDIO_ARGS[@]}" &
        RECORDER_PID=$!
        wait "$RECORDER_PID"
        RECORDING_SESSION=0
    else
        # If a manual region was provided via --region, use it; otherwise run slurp as before.
        if [[ -n "$MANUAL_REGION" ]]; then
            region="$MANUAL_REGION"
        else
            if ! region="$(slurp 2>&1)"; then
                notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
                updatestate false
                exit 1
            fi
        fi

        pos="${region%% *}"      # x,y
        size="${region##* }"     # WxH
        x="${pos%,*}"
        y="${pos#*,}"
        geometry="${x},${y} ${size}"

        # slurp works in logical coordinates; the recorded file is in physical
        # pixels, so the scale of the monitor the selection landed on is what
        # turns one into the other.
        region_scale="$(monitor_scale_at "$x" "$y")"
        read -r REGION_W REGION_H <<< "$(awk -v s="${size%x*}" -v t="${size#*x}" -v scale="$region_scale" 'BEGIN {
            printf "%d %d", int(s * scale + 0.5), int(t * scale + 0.5)
        }')"
        apply_quality "$REGION_W" "$REGION_H" "$CODEC"

        notify-send "Starting recording" "$FILENAME" -a 'Recorder' & disown
        RECORDING_SESSION=1
        updatestate true
        # With a geometry, wf-recorder detects the containing output from the
        # global xdg-output coordinates. Forcing the focused output here makes
        # selections on another monitor invalid and silently records the full
        # output instead.
        wf-recorder "${CODEC_OPTS[@]}" -f "$FILENAME" --geometry "$geometry" "${AUDIO_ARGS[@]}" &
        RECORDER_PID=$!
        wait "$RECORDER_PID"
        RECORDING_SESSION=0
    fi

    # Post recording action (launch video editor)
    if [[ -f "$FILENAME" ]]; then
        notify-send "Recording Finished" "Saved to: $PWD/$FILENAME" -a 'Recorder' &
        qs -c ii ipc call launchVideoEditor handle "$PWD/$FILENAME"
    fi
    updatestate false
fi
