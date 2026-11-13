#!/usr/bin/env bash
#
# switchwall.sh: the one entry point for wallpapers, palettes and the colours of this desktop.
#
# With a wallpaper (or none, which opens a picker) it deals with the wallpaper itself: video
# (mpvpaper or the shell's player), Wallpaper Engine, the upscale prompt, the AI category for the
# clock widget and the config entries those need. Then it runs the colour pipeline with the image
# the colours should come from, which is the wallpaper, a video's frame or a Wallpaper Engine
# screenshot. The pipeline runs matugen with the shell's scheme, mode and overrides; matugen's
# post-hook then runs `switchwall.sh --matugen`, which writes the palette files (palette16.sh).
#
#   switchwall.sh [--mode dark|light] [--type SCHEME] [--image FILE|ID] [--noswitch] [--colors-only]
#                 [--lockscreen] [--lightmode] [--color HEX|clear] [--refresh-frame] [--request-seq N]
#
# Commands that do not touch the wallpaper:
#   --matugen        write the palette files from matugen's output (matugen post-hook)
#   --apply          write the palette files, without refreshing the other tools
#   --reload         write the palette, then flip the GTK theme so running apps reload it
#   --restart        same as --reload
#   --restore        GTK and cursor settings at login; the shell restores the wallpaper itself
#   --set FILE       set a wallpaper through the shell's IPC, so its own config updates too
#   --random         set a random wallpaper from ~/Pictures/Wallpapers
#   --pick           open the shell's wallpaper selector, or waypaper / nsxiv without the shell
#   --reset          run the pipeline again for the current wallpaper
#   --phone          send the current wallpaper to the phone over KDE Connect
#   --colors         print the palette (debugging)
#   --folders        rebuild the recoloured icon theme

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
CONFIG_LOCK_FILE="$STATE_DIR/config-write.lock"
export ILLOGICAL_IMPULSE_VIRTUAL_ENV="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$XDG_STATE_HOME/quickshell/.venv}"

USER_CONFIG="$XDG_CONFIG_HOME"
PALETTE_CACHE="$XDG_CACHE_HOME/switchwall"
THEME_FILE="$HOME/.theme"
WALLPAPERS_DIR="$HOME/Pictures/Wallpapers"

MATUGEN_DIR="$XDG_CONFIG_HOME/matugen"
terminalscheme="$SCRIPT_DIR/terminal/scheme-base.json"
SHELL_MATUGEN_CONFIG="$SCRIPT_DIR/matugen-shell.toml"

# Picks the newest installed Matugen; see the header of matugen.sh.
source "$SCRIPT_DIR/matugen.sh"
# The 16-colour palette backend.
source "$SCRIPT_DIR/palette16.sh"

die() { echo "switchwall: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
notify() { have notify-send && notify-send -u low "$@"; }

# True while the shell runs. Matches the whole command line, so a command that only
# mentions "qs -c ii" does not count as the shell.
shell_running() { pgrep -xf "qs -c ii" >/dev/null; }
require_shell() { shell_running || die "the shell is not running; start it first (qs -c ii)"; }

check_and_prompt_upscale() {
    local img="$1"
    # Settings → Apps & Overlays → Wallpaper upscaling. Not `// true`: jq treats false as empty.
    [[ "$(jq -r '.background.upscaylPrompt' "$SHELL_CONFIG_FILE" 2>/dev/null)" == "false" ]] && return
    # Our own output (services/Upscayl.qml) never asks again, even at a smaller scale.
    [[ "$(basename "$img")" == *-upscaled-[234]x.* ]] && return
    min_width_desired="$(hyprctl monitors -j | jq '([.[].width] | max)' | xargs)" # max monitor width
    min_height_desired="$(hyprctl monitors -j | jq '([.[].height] | max)' | xargs)" # max monitor height

    if command -v identify &>/dev/null && [ -f "$img" ]; then
        local img_width img_height
        if is_video "$img"; then # Not check resolution for videos, just let em pass
            img_width=$min_width_desired
            img_height=$min_height_desired
        else
            # One call, header only: -ping skips decoding, which took about half a second per
            # call on a 6843x4473 wallpaper.
            read -r img_width img_height < <(identify -ping -format "%w %h\n" "$img" 2>/dev/null)
        fi
        if [[ "$img_width" -lt "$min_width_desired" || "$img_height" -lt "$min_height_desired" ]]; then
            # In the background: notify-send waits for an answer to its action button, and the
            # colours, icons and terminal palette must not wait for that.
            (
            action=$(notify-send "Upscale?" \
                "Image resolution (${img_width}x${img_height}) is lower than screen resolution (${min_width_desired}x${min_height_desired})" \
                -A "upscale=Upscale" \
                -A "open_upscayl=Open Upscayl" \
                -a "Wallpaper switcher")
            if [[ "$action" == "upscale" ]]; then
                local target="desktop"
                [[ -n "$lockscreen_flag" ]] && target="lockscreen"
                [[ -n "$lightmode_flag" ]] && target="lightmode"
                # The shell's corner popup does it headless (services/Upscayl.qml);
                # without a running shell, fall back to the app.
                if ! qs -c "$QUICKSHELL_CONFIG_NAME" ipc call upscayl prompt "$(realpath "$img")" "$target" \
                        "$img_width" "$img_height" "$min_width_desired" "$min_height_desired" &>/dev/null; then
                    action="open_upscayl"
                fi
            fi
            if [[ "$action" == "open_upscayl" ]]; then
                if command -v upscayl &>/dev/null; then
                    nohup upscayl > /dev/null 2>&1 &
                else
                    action2=$(notify-send \
                        -a "Wallpaper switcher" \
                        -c "im.error" \
                        -A "install_upscayl=Install Upscayl (Arch)" \
                        "Install Upscayl?" \
                        "yay -S upscayl-bin")
                    if [[ "$action2" == "install_upscayl" ]]; then
                        kitty -1 yay -S upscayl-bin
                        if command -v upscayl &>/dev/null; then
                            nohup upscayl > /dev/null 2>&1 &
                        fi
                    fi
                fi
            fi
            ) 200>&- >/dev/null 2>&1 &
        fi
    fi
}

CUSTOM_DIR="$XDG_CONFIG_HOME/hypr/custom"
RESTORE_SCRIPT_DIR="$CUSTOM_DIR/scripts"
RESTORE_SCRIPT="$RESTORE_SCRIPT_DIR/__restore_video_wallpaper.sh"
THUMBNAIL_DIR="$RESTORE_SCRIPT_DIR/mpvpaper_thumbnails"
VIDEO_OPTS="no-audio loop hwdec=auto scale=bilinear interpolation=no video-sync=display-resample panscan=1.0 video-zoom=0.08 load-scripts=no"

# JPEG XL: matugen reads it, but the Pillow and OpenCV scripts behind the terminal palette and
# the light/dark detection do not. Their colours come from a small PNG copy (cached by path and
# mtime); the wallpaper itself stays the .jxl, which Qt draws through kimageformats.
is_jxl() {
    local f="$1" magic
    [[ -f "$f" ]] || return 1
    [[ "${f,,}" == *.jxl ]] && return 0
    magic="$(head -c 12 -- "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    [[ "$magic" == ff0a* || "$magic" == 0000000c4a584c20* ]]
}

decoded_copy() {
    local src="$1" key out
    key="$(printf '%s %s' "$src" "$(stat -c %Y -- "$src" 2>/dev/null)" | md5sum | cut -c1-16)"
    out="$PALETTE_CACHE/decoded/$key.png"
    if [[ ! -s "$out" ]]; then
        mkdir -p "$PALETTE_CACHE/decoded"
        local tmp="$out.$$.tmp.png"
        if { command -v magick &>/dev/null && magick "$src[0]" -resize '2560x2560>' "$tmp" 2>/dev/null; } \
            || { command -v djxl &>/dev/null && djxl "$src" "$tmp" --quiet 2>/dev/null; }; then
            mv -f -- "$tmp" "$out"
        else
            rm -f -- "$tmp"
            return 1
        fi
    fi
    printf '%s' "$out"
}

is_video() {
    local extension="${1##*.}"
    [[ "$extension" == "mp4" || "$extension" == "webm" || "$extension" == "mkv" || "$extension" == "avi" || "$extension" == "mov" ]] && return 0 || return 1
}

# mpvpaper paints the *desktop* background layer. The lockscreen and the
# light-mode variant are only ever stored paths — they never own that layer. So
# picking a video for one of them must not take the live desktop over, and
# picking a static image for one of them must not kill a video the desktop is
# already playing. Both used to happen.
is_desktop_target() {
    [[ -z "$lockscreen_flag" && -z "$lightmode_flag" ]]
}

# "shell" means Quickshell plays the video inside its own wallpaper plane
# (modules/ii/background/wallpaper/VideoWallpaper.qml); mpvpaper is then neither
# required nor started, and no restore script relaunches it at login.
video_backend_is_shell() {
    [[ "$(jq -r '.background.videoBackend // "mpvpaper"' "$SHELL_CONFIG_FILE" 2>/dev/null)" == "shell" ]]
}

PROXY_SCRIPT="$SCRIPT_DIR/../videos/video-proxy.sh"

# Play a screen-sized copy of videos bigger than the screen (videos/video-proxy.sh).
video_downscale_enabled() {
    # Not `// true`: jq's alternative operator treats an explicit false as missing.
    [[ "$(jq -r '.background.videoDownscale' "$SHELL_CONFIG_FILE" 2>/dev/null)" != "false" ]]
}

# The file mpvpaper and the shell player should open for `video`: its copy when
# one is ready. When a copy is worth making and missing, it is made in the
# background and the wallpaper re-applied once it exists (if still current).
resolve_video_playback() {
    local video="$1" proxy
    if ! video_downscale_enabled; then
        echo "$video"
        return
    fi
    proxy="$("$PROXY_SCRIPT" path "$video")"
    if [[ -n "$proxy" ]]; then
        echo "$proxy"
        return
    fi
    if [[ "$colors_only_flag" != "1" && "$noswitch_flag" != "1" ]] && is_desktop_target && "$PROXY_SCRIPT" needed "$video"; then
        nohup setsid bash -c '"$1" ensure "$2" >/dev/null || exit 0
            [[ "$(jq -r ".background.wallpaperPath" "$3")" == "$2" ]] || exit 0
            exec bash "$4" --image "$2"' \
            _ "$PROXY_SCRIPT" "$video" "$SHELL_CONFIG_FILE" "$SCRIPT_DIR/switchwall.sh" >/dev/null 2>&1 &
    fi
    echo "$video"
}

# Seconds into `video` that colors and the poster frame are taken from
# (.background.videoFrameTimes, set in Settings > Background), 0 = first frame.
video_frame_time() {
    jq -r --arg p "$1" '[.background.videoFrameTimes // [] | .[] | select(.path == $p) | .seconds][0] // 0' \
        "$SHELL_CONFIG_FILE" 2>/dev/null || echo 0
}

# Poster/color frame of `video` at its configured time, into $THUMBNAIL_DIR.
# The time is part of the file name, so a new choice is a new path and every
# Image showing the old poster reloads instead of serving its cache.
extract_video_frame() {
    local video="$1" seconds name out
    seconds="$(video_frame_time "$video")"
    [[ "$seconds" =~ ^[0-9]+(\.[0-9]+)?$ ]] || seconds=0
    name="$(basename "$video")"
    if [[ "$seconds" == "0" ]]; then
        out="$THUMBNAIL_DIR/$name.jpg"
    else
        out="$THUMBNAIL_DIR/$name@${seconds}s.jpg"
    fi
    rm -f "$out"
    ffmpeg -y -ss "$seconds" -i "$video" -frames:v 1 "$out" 2>/dev/null
    # Past the end of the video ffmpeg writes nothing: use the first frame.
    if [[ ! -s "$out" && "$seconds" != "0" ]]; then
        out="$THUMBNAIL_DIR/$name.jpg"
        ffmpeg -y -i "$video" -frames:v 1 "$out" 2>/dev/null
    fi
    echo "$out"
}

kill_existing_mpvpaper() {
    pkill -f -9 mpvpaper || true
}

kill_existing_wpe() {
    pkill -f linux-wallpaperengine || true
}

disable_wpe_config() {
    update_config_value_if_changed '.background.useWallpaperEngine' bool false false
}

enable_wpe_config() {
    update_config_value_if_changed '.background.useWallpaperEngine' bool true false
}

create_restore_script_wpe() {
    local wpe_id=$1
    local wpe_args_str=$2
    cat > "$RESTORE_SCRIPT.tmp" << EOF
#!/bin/bash
# Generated by switchwall.sh - Don't modify it by yourself.
# Time: \$(date)

pkill -f linux-wallpaperengine
pkill -f -9 mpvpaper

$wpe_args_str
EOF
    mv "$RESTORE_SCRIPT.tmp" "$RESTORE_SCRIPT"
    chmod +x "$RESTORE_SCRIPT"
}

create_restore_script() {
    local video_path=$1
    cat > "$RESTORE_SCRIPT.tmp" << EOF
#!/bin/bash
# Generated by switchwall.sh - Don't modify it by yourself.
# Time: $(date)

pkill -f -9 mpvpaper

for monitor in \$(hyprctl monitors -j | jq -r '.[] | .name'); do
    mpvpaper -o "$VIDEO_OPTS input-ipc-server=/tmp/mpvpaper-\$monitor.sock" "\$monitor" "$video_path" &
    sleep 0.1
done
EOF
    mv "$RESTORE_SCRIPT.tmp" "$RESTORE_SCRIPT"
    chmod +x "$RESTORE_SCRIPT"
}

remove_restore() {
    cat > "$RESTORE_SCRIPT.tmp" << EOF
#!/bin/bash
# The content of this script will be generated by switchwall.sh - Don't modify it by yourself.
EOF
    mv "$RESTORE_SCRIPT.tmp" "$RESTORE_SCRIPT"
}

update_config_value_if_changed() {
    local jq_filter="$1"
    local value_type="$2"
    local value="$3"
    local default_value="${4:-null}"
    local current_value temp_file

    [[ -f "$SHELL_CONFIG_FILE" ]] || return 0
    mkdir -p "$(dirname "$CONFIG_LOCK_FILE")" 2>/dev/null || return 1

    # Multiple switchwall processes can overlap after rapid selections. Keep the
    # read/compare/write transaction serialized and use a unique temp file, so a
    # stale process cannot overwrite a newer config or trigger a needless reload.
    exec 200>"$CONFIG_LOCK_FILE"
    flock -x 200
    current_value=$(jq -r "${jq_filter} // ${default_value}" "$SHELL_CONFIG_FILE" 2>/dev/null) || {
        flock -u 200
        exec 200>&-
        return 1
    }
    if [[ "$current_value" == "$value" ]]; then
        flock -u 200
        exec 200>&-
        return 0
    fi

    temp_file=$(mktemp "${SHELL_CONFIG_FILE}.tmp.XXXXXX") || {
        flock -u 200
        exec 200>&-
        return 1
    }
    if [[ "$value_type" == "bool" ]]; then
        jq --indent 4 --argjson value "$value" "${jq_filter} = \$value" "$SHELL_CONFIG_FILE" > "$temp_file"
    else
        jq --indent 4 --arg value "$value" "${jq_filter} = \$value" "$SHELL_CONFIG_FILE" > "$temp_file"
    fi
    if [[ $? -eq 0 ]]; then
        mv -f -- "$temp_file" "$SHELL_CONFIG_FILE"
    else
        rm -f -- "$temp_file"
        flock -u 200
        exec 200>&-
        return 1
    fi
    flock -u 200
    exec 200>&-
}

set_wallpaper_path() {
    local path="$1"
    local target="$2"
    if [[ "$target" == "lightmode" ]]; then
        update_config_value_if_changed '.background.lightModeWallpaperPath' string "$path" '""'
    elif [[ "$target" == "lockscreen" ]]; then
        update_config_value_if_changed '.background.lockscreenWallpaperPath' string "$path" '""'
    else
        update_config_value_if_changed '.background.wallpaperPath' string "$path" '""'
    fi
}

set_thumbnail_path() {
    local path="$1"
    update_config_value_if_changed '.background.thumbnailPath' string "$path" '""'
}


# Everything the wallpaper itself needs. Sets color_source to the image the colours are taken from.
prepare_wallpaper() {
        if [[ -z "$imgpath" ]]; then
            echo 'Aborted'
            exit 0
        fi

        if [[ -z "$colors_only_flag" && -z "$noswitch_flag" ]]; then
            check_and_prompt_upscale "$imgpath" &
        fi
        
        if [[ "$noswitch_flag" != "1" && "$colors_only_flag" != "1" ]]; then
            kill_existing_mpvpaper
            kill_existing_wpe
        fi

        # Load Wallpaper Engine settings from config.json
        use_wpe=$(jq -r '.background.useWallpaperEngine' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "false")
        wpe_assets=$(jq -r '.background.wallpaperEngineAssetsPath' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "")

        is_wpe=0
        if [[ "$use_wpe" == "true" ]]; then
            is_wpe=1
        fi

        if [[ $is_wpe -eq 1 ]]; then
            # Auto-detect wpe_assets if empty or invalid
            if [[ -z "$wpe_assets" || ! -d "$wpe_assets" ]]; then
                for candidate_assets in \
                    "/mnt/01DA34356F1F3C40/SteamLibrary/steamapps/common/wallpaper_engine/assets" \
                    "$HOME/.local/share/Steam/steamapps/common/wallpaper_engine/assets" \
                    "$HOME/.steam/steam/steamapps/common/wallpaper_engine/assets" \
                    "$HOME/.steam/root/steamapps/common/wallpaper_engine/assets"; do
                    if [[ -d "$candidate_assets" ]]; then
                        wpe_assets="$candidate_assets"
                        break
                    fi
                done
            fi

            # Try to resolve workshop directory from assets directory or candidate paths if it's a numeric ID
            if [[ "$imgpath" =~ ^[0-9]+$ ]]; then
                local wpe_candidates=()
                if [[ -n "$wpe_assets" ]]; then
                    wpe_candidates+=("${wpe_assets/common\/wallpaper_engine\/assets/workshop\/content\/431960}")
                    wpe_candidates+=("${wpe_assets/common\/wallpaper_engine/workshop\/content\/431960}")
                fi
                wpe_candidates+=(
                    "/mnt/01DA34356F1F3C40/SteamLibrary/steamapps/workshop/content/431960"
                    "$HOME/.local/share/Steam/steamapps/workshop/content/431960"
                    "$HOME/.steam/steam/steamapps/workshop/content/431960"
                    "$HOME/.steam/root/steamapps/workshop/content/431960"
                )
                for cand in "${wpe_candidates[@]}"; do
                    if [[ -d "$cand/$imgpath" ]]; then
                        imgpath="$cand/$imgpath"
                        break
                    fi
                done
            fi
            if [[ "$colors_only_flag" != "1" && "$noswitch_flag" != "1" ]]; then
                enable_wpe_config
            fi

            local wpe_screenshot="/tmp/wpe_screenshot.png"

            if [[ "$noswitch_flag" == "1" || "$colors_only_flag" == "1" ]]; then
                if [ -f "$wpe_screenshot" ]; then
                    color_source="$wpe_screenshot"
                else
                    # Fallback to preview or static
                    local fallback_img=""
                    if [[ -d "$imgpath" ]]; then
                        if [[ -f "$imgpath/preview.jpg" ]]; then
                            fallback_img="$imgpath/preview.jpg"
                        elif [[ -f "$imgpath/preview.gif" ]]; then
                            ffmpeg -y -i "$imgpath/preview.gif" -vframes 1 /tmp/wpe_fallback.png 2>/dev/null
                            fallback_img="/tmp/wpe_fallback.png"
                        fi
                    fi
                    if [[ -n "$fallback_img" && -f "$fallback_img" ]]; then
                        color_source="$fallback_img"
                    else
                        local default_wall="$HOME/.config/quickshell/ii/assets/images/default_wallpaper.png"
                        color_source="$default_wall"
                    fi
                fi
            else
                # Verify dependencies
                if ! command -v linux-wallpaperengine &> /dev/null; then
                    notify-send -a "Wallpaper switcher" -c "im.error" "Wallpaper Engine Error" "linux-wallpaperengine command not found. Please install/check dependencies."
                    exit 1
                fi

                # Load additional settings
                wpe_silent=$(jq -r '.background.wpeSilent' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "true")
                wpe_volume=$(jq -r '.background.wpeVolume' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "50")
                wpe_noautomute=$(jq -r '.background.wpeNoAutoMute' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "false")
                wpe_noaudioprocess=$(jq -r '.background.wpeNoAudioProcessing' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "false")
                wpe_fps=$(jq -r '.background.wpeFps' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "30")
                wpe_screenspan=$(jq -r '.background.wpeScreenSpan' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "")
                wpe_scaling=$(jq -r '.background.wpeScaling' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "default")
                wpe_disablemouse=$(jq -r '.background.wpeDisableMouse' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "false")
                wpe_disableparallax=$(jq -r '.background.wpeDisableParallax' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "false")
                wpe_nofullscreenpause=$(jq -r '.background.wpeNoFullscreenPause' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "false")

                # Determine assets directory and build restore options array
                local wpe_restore_opts=(--layer background)
                if [[ -n "$wpe_assets" && -d "$wpe_assets" ]]; then
                    wpe_restore_opts+=(--assets-dir "$wpe_assets")
                fi

                if [[ "$wpe_silent" == "true" ]]; then
                    wpe_restore_opts+=(--silent)
                else
                    wpe_restore_opts+=(--volume "$wpe_volume")
                fi

                if [[ "$wpe_noautomute" == "true" ]]; then
                    wpe_restore_opts+=(--noautomute)
                fi

                if [[ "$wpe_noaudioprocess" == "true" ]]; then
                    wpe_restore_opts+=(--no-audio-processing)
                fi

                if [[ -n "$wpe_fps" && "$wpe_fps" -gt 0 ]]; then
                    wpe_restore_opts+=(--fps "$wpe_fps")
                fi

                if [[ "$wpe_scaling" != "default" && -n "$wpe_scaling" ]]; then
                    wpe_restore_opts+=(--scaling "$wpe_scaling")
                fi

                if [[ "$wpe_disablemouse" == "true" ]]; then
                    wpe_restore_opts+=(--disable-mouse)
                fi

                if [[ "$wpe_disableparallax" == "true" ]]; then
                    wpe_restore_opts+=(--disable-parallax)
                fi

                if [[ "$wpe_nofullscreenpause" == "true" ]]; then
                    wpe_restore_opts+=(--no-fullscreen-pause)
                fi

                # Build options for current execution (including screenshot)
                local wpe_opts=("${wpe_restore_opts[@]}")
                rm -f "$wpe_screenshot"
                wpe_opts+=(--screenshot "$wpe_screenshot")

                # Launch linux-wallpaperengine
                local wpe_args_str=""
                if [[ -n "$wpe_screenspan" ]]; then
                    nohup setsid linux-wallpaperengine "${wpe_opts[@]}" --screen-span "$wpe_screenspan" "$imgpath" >/tmp/wpe_run.log 2>&1 &
                    wpe_args_str="setsid linux-wallpaperengine ${wpe_restore_opts[*]} --screen-span \"$wpe_screenspan\" \"$imgpath\" &"
                else
                    monitors=$(hyprctl monitors -j | jq -r '.[] | .name')
                    for monitor in $monitors; do
                        nohup setsid linux-wallpaperengine "${wpe_opts[@]}" --screen-root "$monitor" "$imgpath" >/tmp/wpe_run.log 2>&1 &
                        sleep 0.1
                    done
                    wpe_args_str="for monitor in \$(hyprctl monitors -j | jq -r '.[] | .name'); do
    setsid linux-wallpaperengine ${wpe_restore_opts[*]} --screen-root \"\$monitor\" \"$imgpath\" &
    sleep 0.1
done"
                fi

                # Create restore script
                create_restore_script_wpe "$imgpath" "$wpe_args_str"

                # Wait up to 2 seconds for screenshot to be written
                for i in {1..20}; do
                    if [ -f "$wpe_screenshot" ]; then
                        break
                    fi
                    sleep 0.1
                done

                if [ -f "$wpe_screenshot" ]; then
                    color_source="$wpe_screenshot"
                else
                    echo "Cannot create image to colorgen from Wallpaper Engine screenshot, trying fallbacks" >&2
                    local fallback_img=""
                    if [[ -d "$imgpath" ]]; then
                        if [[ -f "$imgpath/preview.jpg" ]]; then
                            fallback_img="$imgpath/preview.jpg"
                        elif [[ -f "$imgpath/preview.gif" ]]; then
                            ffmpeg -y -i "$imgpath/preview.gif" -vframes 1 /tmp/wpe_fallback.png 2>/dev/null
                            fallback_img="/tmp/wpe_fallback.png"
                        fi
                    elif [[ "$imgpath" =~ ^[0-9]+$ && -f "/mnt/01DA34356F1F3C40/SteamLibrary/steamapps/workshop/content/431960/$imgpath/preview.gif" ]]; then
                        ffmpeg -y -i "/mnt/01DA34356F1F3C40/SteamLibrary/steamapps/workshop/content/431960/$imgpath/preview.gif" -vframes 1 /tmp/wpe_fallback.png 2>/dev/null
                        fallback_img="/tmp/wpe_fallback.png"
                    fi

                    if [[ -n "$fallback_img" && -f "$fallback_img" ]]; then
                        color_source="$fallback_img"
                    else
                        exit 1
                    fi
                fi
            fi
        else
            # If not using Wallpaper Engine, make sure it is disabled in config.
            # A colors-only pass must not rewrite the config or cause another
            # FileView reload merely because it inspected the current wallpaper.
            if [[ "$colors_only_flag" != "1" && "$noswitch_flag" != "1" ]]; then
                disable_wpe_config
            fi

            # Resolve directories or numeric IDs to valid image files
            if [[ -d "$imgpath" ]]; then
                if [[ -f "$imgpath/preview.jpg" ]]; then
                    imgpath="$imgpath/preview.jpg"
                elif [[ -f "$imgpath/preview.gif" ]]; then
                    ffmpeg -y -i "$imgpath/preview.gif" -vframes 1 /tmp/wpe_fallback.png 2>/dev/null
                    imgpath="/tmp/wpe_fallback.png"
                else
                    imgpath="$HOME/.config/quickshell/ii/assets/images/default_wallpaper.png"
                fi
            elif [[ "$imgpath" =~ ^[0-9]+$ ]]; then
                local resolved_dir=""
                if [[ -n "$wpe_assets" ]]; then
                    wpe_workshop="${wpe_assets/common\/wallpaper_engine\/assets/workshop\/content\/431960}"
                    if [[ ! -d "$wpe_workshop" ]]; then
                        wpe_workshop="${wpe_assets/common\/wallpaper_engine/workshop\/content\/431960}"
                    fi
                    if [[ -d "$wpe_workshop/$imgpath" ]]; then
                        resolved_dir="$wpe_workshop/$imgpath"
                    fi
                fi
                if [[ -n "$resolved_dir" ]]; then
                    if [[ -f "$resolved_dir/preview.jpg" ]]; then
                        imgpath="$resolved_dir/preview.jpg"
                    elif [[ -f "$resolved_dir/preview.gif" ]]; then
                        ffmpeg -y -i "$resolved_dir/preview.gif" -vframes 1 /tmp/wpe_fallback.png 2>/dev/null
                        imgpath="/tmp/wpe_fallback.png"
                    else
                        imgpath="$HOME/.config/quickshell/ii/assets/images/default_wallpaper.png"
                    fi
                else
                    imgpath="$HOME/.config/quickshell/ii/assets/images/default_wallpaper.png"
                fi
            fi

            if is_video "$imgpath"; then
            mkdir -p "$THUMBNAIL_DIR"

            missing_deps=()
            if [[ "$colors_only_flag" != "1" && "$noswitch_flag" != "1" ]] && ! video_backend_is_shell && ! command -v mpvpaper &> /dev/null; then
                missing_deps+=("mpvpaper")
            fi
            if ! command -v ffmpeg &> /dev/null; then
                missing_deps+=("ffmpeg")
            fi
            if [ ${#missing_deps[@]} -gt 0 ]; then
                echo "Missing deps: ${missing_deps[*]}"
                echo "Arch: sudo pacman -S ${missing_deps[*]}"
                action=$(notify-send \
                    -a "Wallpaper switcher" \
                    -c "im.error" \
                    -A "install_arch=Install (Arch)" \
                    "Can't switch to video wallpaper" \
                    "Missing dependencies: ${missing_deps[*]}")
                if [[ "$action" == "install_arch" ]]; then
                    kitty -1 sudo pacman -S "${missing_deps[*]}"
                    if command -v mpvpaper &>/dev/null && command -v ffmpeg &>/dev/null; then
                        notify-send 'Wallpaper switcher' 'Alright, try again!' -a "Wallpaper switcher"
                    fi
                fi
                exit 0
            fi

            # Set wallpaper path
            if [[ -z "$colors_only_flag" && -z "$noswitch_flag" ]]; then
                if [[ -n "$lightmode_flag" ]]; then
                    set_wallpaper_path "$imgpath" "lightmode"
                elif [[ -n "$lockscreen_flag" ]]; then
                    set_wallpaper_path "$imgpath" "lockscreen"
                else
                    set_wallpaper_path "$imgpath" "desktop"
                fi
            fi

            # Set video wallpaper
            local video_path
            video_path="$(resolve_video_playback "$imgpath")"
            # The shell player reads which file to open from here (VideoWallpaper.qml).
            if is_desktop_target && [[ "$colors_only_flag" != "1" && "$noswitch_flag" != "1" ]]; then
                update_config_value_if_changed '.background.videoPlaybackSource' string "$imgpath" '""'
                update_config_value_if_changed '.background.videoPlaybackPath' string "$video_path" '""'
            fi
            if is_desktop_target && [[ "$colors_only_flag" != "1" && "$noswitch_flag" != "1" ]] && ! video_backend_is_shell; then
                monitors=$(hyprctl monitors -j | jq -r '.[] | .name')
                for monitor in $monitors; do
                    nohup setsid mpvpaper -o "$VIDEO_OPTS input-ipc-server=/tmp/mpvpaper-$monitor.sock" "$monitor" "$video_path" >/dev/null 2>&1 &
                    sleep 0.1
                done
            fi

            # The frame colors are generated from (first frame unless the user
            # picked a moment in Settings > Background).
            thumbnail="$(extract_video_frame "$imgpath")"

            # Set thumbnail path. Global, so it belongs to the desktop wallpaper —
            # a lockscreen or light-mode pick must not repaint the desktop preview.
            # --refresh-frame is a --noswitch run that only re-picks the frame.
            if is_desktop_target && [[ ( "$colors_only_flag" != "1" && "$noswitch_flag" != "1" ) || "$refresh_frame_flag" == "1" ]]; then
                set_thumbnail_path "$thumbnail"
            fi

            if [ -f "$thumbnail" ]; then
                color_source="$thumbnail"
                if is_desktop_target && [[ "$colors_only_flag" != "1" && "$noswitch_flag" != "1" ]]; then
                    if video_backend_is_shell; then
                        remove_restore
                    else
                        create_restore_script "$video_path"
                    fi
                fi
            else
                echo "Cannot create image to colorgen"
                if [[ "$colors_only_flag" != "1" && "$noswitch_flag" != "1" ]]; then
                    remove_restore
                fi
                exit 1
            fi
        else
            if is_desktop_target && [[ "$colors_only_flag" != "1" && "$noswitch_flag" != "1" ]]; then
                kill_existing_mpvpaper
            fi
            color_source="$imgpath"
            # Update wallpaper path in config
            if [[ -z "$colors_only_flag" && -z "$noswitch_flag" ]]; then
                # A light-mode pick only stores its own path; the dark wallpaper stays in wallpaperPath
                if [[ -n "$lightmode_flag" ]]; then
                    set_wallpaper_path "$imgpath" "lightmode"
                else
                    set_wallpaper_path "$imgpath" "${lockscreen_flag:+lockscreen}"
                fi
            fi
            if is_desktop_target && [[ "$colors_only_flag" != "1" && "$noswitch_flag" != "1" ]]; then
                remove_restore
            fi
        fi
    fi
}


# ── Colour pipeline ──────────────────────────────────────────────────────────

# Matugen aborts the whole run - colors.json included - as soon as any template
# in its config points at an input file that does not exist, and it walks the
# templates in random order, so the breakage looks intermittent: some runs write
# the palette, most do not. Name the offending entries instead of leaving the
# shell silently stuck on the previous colors.
report_matugen_failure() {
    local script_name="$1"
    local exit_code="${2:-1}"
    local flag_file="$STATE_DIR/matugen_error_notified"
    local extra_flags=()

    mkdir -p "$STATE_DIR" 2>/dev/null || true

    if [[ -f "$flag_file" ]]; then
        extra_flags+=(-t 0 -h boolean:suppress-sound:true)
    else
        touch "$flag_file" 2>/dev/null || true
    fi

    local cfg="$MATUGEN_DIR/config.toml"
    local missing=()
    local p
    if [[ -f "$cfg" ]]; then
        while read -r p; do
            [[ -z "$p" ]] && continue
            p="${p/#\~/$HOME}"
            [[ -f "$p" ]] || missing+=("$p")
        done < <(grep -oP "input_path\s*=\s*'\K[^']+" "$cfg" 2>/dev/null)
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "[$script_name] matugen aborted (exit code $exit_code); missing template inputs: ${missing[*]}" >&2
        notify-send -a "Wallpaper switcher" -c "im.error" "${extra_flags[@]}" \
            "Color generation failed (code $exit_code)" \
            "matugen aborted with error code $exit_code because these templates are missing: ${missing[*]} - fix or remove them in $cfg" 2>/dev/null || true
    else
        echo "[$script_name] matugen failed (exit code $exit_code); keeping the previous palette." >&2
        notify-send -a "Wallpaper switcher" -c "im.error" "${extra_flags[@]}" \
            "Color generation failed (code $exit_code)" \
            "matugen exited with error code $exit_code, so the shell kept its previous palette." 2>/dev/null || true
    fi
}

# Rebuild the recolored icon theme without holding up the rest of the theming. The recolor
# runs at idle priority, debounces and drops superseded runs itself, so a burst of wallpaper
# changes ends in one rebuild that never takes CPU from the desktop. It is detached from this
# script's process group so the caller finishing (or being killed) does not stop it.
# Folder icons follow the palette. matugen's post-hook (`switchwall.sh --matugen`) starts this as soon as
# colors.json is written, so the icons rebuild alongside the rest of the apply rather than after it.
# It goes before refine_wal_palette: the recolor reads only colors.json and runs detached, so there is no
# reason for it to wait for the palette refinement.
recolor_icons_if_themed() {
    [[ "$(jq -r '.appearance.icons.enableThemed' "${SHELL_CONFIG_FILE:-$HOME/.config/illogical-impulse/config.json}" 2>/dev/null)" == "true" ]] || return 0
    recolor_icons_in_background
}

recolor_icons_in_background() {
    local script="$HOME/.config/quickshell/ii/scripts/colors/recolor_icons.py"
    # Kept in a log (trimmed to the last 200 lines) so a missed recolor can be traced afterwards.
    local log="$HOME/.cache/switchwall/recolor.log"
    mkdir -p "$(dirname "$log")"
    [[ -f "$log" && $(wc -l <"$log") -gt 200 ]] && tail -n 100 "$log" >"$log.tmp" && mv "$log.tmp" "$log"
    echo "== $(date +%T) recolor requested by ${FUNCNAME[1]:-?}" >>"$log"
    if command -v setsid >/dev/null 2>&1; then
        setsid -f python3 "$script" >>"$log" 2>&1 </dev/null
    else
        nohup python3 "$script" >>"$log" 2>&1 </dev/null &
    fi
}

pre_process() {
    local mode_flag="$1"
    # Set GNOME color-scheme if mode_flag is dark or light. The GTK theme is FlatColor in both.
    if [[ "$mode_flag" == "dark" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
        gsettings set org.gnome.desktop.interface gtk-theme 'FlatColor'
    elif [[ "$mode_flag" == "light" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
        gsettings set org.gnome.desktop.interface gtk-theme 'FlatColor'
    fi

    if [ ! -d "$CACHE_DIR"/user/generated ]; then
        mkdir -p "$CACHE_DIR"/user/generated
    fi
}

switch() {
    imgpath="$1"
    mode_flag="$2"
    type_flag="$3"
    color_flag="$4"
    color="$5"
    theme_file="$6"

    # Guard against rapid wallpaper switches racing each other: the all-previews
    # generation below takes over a second, so a second switch launched before it
    # finishes must not have its result overwritten by the older, slower run.
    # request_seq_flag (--request-seq) comes from the QML caller and is strictly
    # increasing in click order, since QML dispatch is single-threaded. Direct
    # callers without a sequence receive the next token under the same lock, so
    # they cannot be rejected just because an older QML token uses timestamps.
    request_token_file="$STATE_DIR/user/generated/.preview_request_token"
    mkdir -p "$(dirname "$request_token_file")"
    if [[ -n "$request_seq_flag" ]]; then
        my_request_token="$request_seq_flag"
        (
            flock -x 201
            current_seq=$(cat "$request_token_file" 2>/dev/null)
            if [[ -z "$current_seq" ]] || ! [[ "$current_seq" =~ ^[0-9]+$ ]] || (( my_request_token > current_seq )); then
                printf '%s' "$my_request_token" > "$request_token_file"
            fi
        ) 201>"$request_token_file.lock"
    else
        my_request_token=$(
            (
                flock -x 201
                current_seq=$(cat "$request_token_file" 2>/dev/null)
                if [[ "$current_seq" =~ ^[0-9]+$ ]]; then
                    next_seq=$((current_seq + 1))
                else
                    next_seq=$(date +%s%3N)
                fi
                printf '%s' "$next_seq" > "$request_token_file"
                printf '%s' "$next_seq"
            ) 201>"$request_token_file.lock"
        )
    fi

    matugen_args=(--source-color-index 0)

    if [[ "$color_flag" == "1" ]]; then
        matugen_args+=(color hex "$color")
        generate_colors_material_args=(--color "$color")
    else
        if [[ -z "$imgpath" ]]; then
            echo 'Aborted'
            exit 0
        fi

        # A folder or a numeric id (Wallpaper Engine) has no image of its own, unless
        # switchwall.sh passed one as --source.
        if [[ -z "$source_img" && ( -d "$imgpath" || "$imgpath" =~ ^[0-9]+$ ) ]]; then
            imgpath="$CONFIG_DIR/assets/images/default_wallpaper.png"
        fi

        matugen_args+=(image "${source_img:-$imgpath}")
        generate_colors_material_args=(--path "${source_img:-$imgpath}")
        if [[ -z "$colors_only_flag" && -z "$noswitch_flag" ]]; then
            # A light-mode pick only stores its own path; the dark wallpaper stays in wallpaperPath
            if [[ -n "$lightmode_flag" ]]; then
                set_wallpaper_path "$imgpath" "lightmode"
            else
                set_wallpaper_path "$imgpath" "${lockscreen_flag:+lockscreen}"
            fi
        fi
    fi

    # Determine mode if not set
    if [[ -z "$mode_flag" ]]; then
        current_mode=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
        if [[ "$current_mode" == "prefer-dark" ]]; then
            mode_flag="dark"
        else
            mode_flag="light"
        fi
    fi

    # enforce dark mode for terminal
    if [[ -n "$mode_flag" ]]; then
        matugen_args+=(--mode "$mode_flag")
        if [[ $(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode' "$SHELL_CONFIG_FILE") == "true" ]]; then
            generate_colors_material_args+=(--mode "dark")
        else
            generate_colors_material_args+=(--mode "$mode_flag")
        fi
    fi
    if [[ "$type_flag" == "scheme-intense" ]]; then
        matugen_args+=(--type "scheme-fidelity")
    elif [[ -n "$type_flag" ]]; then
        matugen_args+=(--type "$type_flag")
    fi
    generate_colors_material_args+=(--scheme "$type_flag")
    generate_colors_material_args+=(--termscheme "$terminalscheme" --blend_bg_fg)
    generate_colors_material_args+=(--cache "$STATE_DIR/user/generated/color.txt")

    # Preset application already has the mode/config state in place. Avoid the
    # synchronous GNOME settings calls and cache-directory setup on the first
    # color frame; those are secondary integration work.
    if [[ -z "$colors_only_flag" ]]; then
        pre_process "$mode_flag"
    fi

    # Check if app and shell theming is enabled in config
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        enable_apps_shell=$(jq -r '.appearance.wallpaperTheming.enableAppsAndShell' "$SHELL_CONFIG_FILE")
        if [ "$enable_apps_shell" == "false" ]; then
            echo "App and shell theming disabled, skipping matugen and color generation"
            return
        fi
    fi

    # Set harmony and related properties
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        harmony=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.harmony' "$SHELL_CONFIG_FILE")
        harmonize_threshold=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold' "$SHELL_CONFIG_FILE")
        term_fg_boost=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost' "$SHELL_CONFIG_FILE")
        [[ "$harmony" != "null" && -n "$harmony" ]] && generate_colors_material_args+=(--harmony "$harmony")
        [[ "$harmonize_threshold" != "null" && -n "$harmonize_threshold" ]] && generate_colors_material_args+=(--harmonize_threshold "$harmonize_threshold")
        [[ "$term_fg_boost" != "null" && -n "$term_fg_boost" ]] && generate_colors_material_args+=(--term_fg_boost "$term_fg_boost")
    fi

    if [[ -n "$theme_file" ]]; then
        mkdir -p "$(dirname "$STATE_DIR/user/generated/colors.json")"
        cp "$theme_file" "$STATE_DIR/user/generated/colors.json"
        rm -f "$STATE_DIR/matugen_error_notified"
        apply_color_overrides_flat "$mode_flag"
        echo "[switchwall] Applied theme: $type_flag"
        if [[ -z "$colors_only_flag" && "$(jq -r '.appearance.icons.enableThemed' "$SHELL_CONFIG_FILE" 2>/dev/null)" == "true" ]]; then recolor_icons_in_background; fi
        "$SCRIPT_DIR"/applycolor.sh
    else
        matugen_exit_code=0
        matugen_config_args=()
        if [[ -n "$colors_only_flag" && -f "$SHELL_MATUGEN_CONFIG" ]]; then
            # The normal config fans out to GTK, Hyprland, terminals, yazi,
            # browsers and other integrations. The first preset frame only
            # needs the m3colors template that Quickshell watches.
            matugen_config_args+=(--config "$SHELL_MATUGEN_CONFIG")
        fi
        # The terminal palette and preview swatches only need the image, not matugen's output, and
        # on a large wallpaper decoding it takes as long as matugen does: run both at once.
        preview_args=()
        if [[ -z "$colors_only_flag" ]]; then
            preview_args+=(
                --all-previews "$STATE_DIR/user/generated/wallpaper_preview_colors.json"
                --request-token "$request_token_file"
                --request-value "$my_request_token"
            )
        fi
        material_scss="$STATE_DIR/user/generated/material_colors.scss"
        (
            source "$(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate"
            python3 "$SCRIPT_DIR/generate_colors_material.py" "${generate_colors_material_args[@]}" "${preview_args[@]}" \
                > "$material_scss.tmp"
        ) 200>&- &
        generate_colors_pid=$!
        color_overrides="$(get_color_overrides "$mode_flag")"
        if [[ -n "$color_overrides" ]]; then
            # Matugen cannot pin a role, but it renders templates from a dump:
            # generate the dump, patch the picked colors in, render from it.
            matugen_dump="$(mktemp --suffix=.json)"
            if matugen "${matugen_config_args[@]}" "${matugen_args[@]}" --dry-run -q -j hex --include-image-in-json true > "$matugen_dump" \
                && run_color_overrides patch-dump "$matugen_dump" --mode "$mode_flag" --overrides "$color_overrides" \
                && matugen "${matugen_config_args[@]}" json "$matugen_dump"; then
                rm -f "$STATE_DIR/matugen_error_notified"
            else
                matugen_exit_code=$?
                report_matugen_failure "switchwall" "$matugen_exit_code"
            fi
            rm -f "$matugen_dump"
        elif matugen "${matugen_config_args[@]}" "${matugen_args[@]}"; then
            rm -f "$STATE_DIR/matugen_error_notified"
        else
            matugen_exit_code=$?
            report_matugen_failure "switchwall" "$matugen_exit_code"
        fi
        if [[ "$type_flag" == "scheme-intense" ]]; then
            echo "[switchwall] Applying intense surface boost to colors.json (mode: $mode_flag)" >&2
            python3 "$SCRIPT_DIR/boost_surface_chroma.py" "$STATE_DIR/user/generated/colors.json" --mode "$mode_flag"
            # The boost rewrites the surfaces; a picked surface still wins.
            apply_color_overrides_flat "$mode_flag"
        fi
        # Folder icons: started by matugen's post-hook as soon as colors.json is written.
        if wait "$generate_colors_pid"; then
            mv "$material_scss.tmp" "$material_scss"
        else
            rm -f "$material_scss.tmp"
            echo "[switchwall] Color generation skipped; preserving the previous terminal palette." >&2
        fi
        "$SCRIPT_DIR"/applycolor.sh
    fi
}

# The scheme types matugen takes, plus the two names that ask for detection.
allowed_types=(scheme-content scheme-expressive scheme-fidelity scheme-fruit-salad scheme-monochrome scheme-neutral scheme-rainbow scheme-tonal-spot scheme-vibrant scheme-intense auto scheme-auto)

get_type_from_config() {
    jq -r '.appearance.palette.type' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "auto"
}

get_accent_color_from_config() {
    jq -r '.appearance.palette.accentColor' "$SHELL_CONFIG_FILE" 2>/dev/null || echo ""
}

set_accent_color() {
    update_config_value_if_changed '.appearance.palette.accentColor' string "$1" '""'
}

# The user's hand-picked key colors for a mode, as compact JSON; empty
# when none of them is set (see color_overrides.py).
get_color_overrides() {
    local mode="${1:-dark}"
    jq -c --arg mode "$mode" '(.appearance.palette.overrides[$mode] // {})
        | with_entries(select((.value | type) == "string" and (.value | test("^#?[0-9A-Fa-f]{6}$"))))
        | select(length > 0)' "$SHELL_CONFIG_FILE" 2>/dev/null
}

run_color_overrides() {
    bash "$SCRIPT_DIR/color_overrides.sh" "$@"
}

apply_color_overrides_flat() {
    local overrides
    overrides="$(get_color_overrides "${1:-dark}")"
    [[ -z "$overrides" ]] && return 0
    run_color_overrides patch-flat "$STATE_DIR/user/generated/colors.json" --mode "${1:-dark}" --overrides "$overrides"
}

# The scheme for an image never changes while the file does not, and a dark/light toggle or a
# re-apply asks again for the same wallpaper: the answer is kept per path, size and mtime.
detect_scheme_type_from_image() {
    local img="$1" key cache_file result
    key=$(printf '%s|%s' "$img" "$(stat -c '%s:%Y' -- "$img" 2>/dev/null)" | sha256sum | cut -c1-24)
    cache_file="$PALETTE_CACHE/scheme-for-image/$key"
    if [[ -s "$cache_file" ]]; then
        cat -- "$cache_file"
        return 0
    fi
    local _venv="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$XDG_STATE_HOME/quickshell/.venv}"
    source "$(eval echo $_venv)/bin/activate"
    result=$("$SCRIPT_DIR"/scheme_for_image.py "$img" 2>/dev/null | tr -d '\n')
    deactivate
    if [[ -n "$result" ]]; then
        mkdir -p "${cache_file%/*}" && printf '%s' "$result" > "$cache_file"
    fi
    printf '%s' "$result"
}


# ── Palette and desktop ──────────────────────────────────────────────────────
# Settings from ~/.theme, which the bar and the GTK setup read too. Defaults cover a missing file.
load_theme() {
    gtk_theme=FlatColor icon_theme=Papirus-Dark
    cursor_theme=Fluent-dark-cursors font_name="Noto Sans 9"
    # shellcheck source=/dev/null
    [[ -f "$THEME_FILE" ]] && source "$THEME_FILE"
    return 0
}

# The wallpaper the shell shows: its own setting, else the image the palette came from.
current_wallpaper() {
    local path
    path=$(jq -r '.background.wallpaperPath // ""' "$SHELL_CONFIG_FILE" 2>/dev/null)
    [[ -f "$path" ]] || path=$(palette_wallpaper)
    printf '%s\n' "$path"
}

# Tools that read the palette on their own. pywalfox reads matugen's colors.json.
refresh_tools() {
    have pywalfox && ( pywalfox update >/dev/null 2>&1 & )
    return 0
}

# Flips the GTK theme so running GTK apps reload their colours. Wayland only.
reload_gtk() {
    have gsettings || return 0
    gsettings set org.gnome.desktop.interface gtk-theme "Dummy"
    gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme"
}

reload_all() {
    apply_palette
    reload_gtk
}

# At login. The shell restores its own wallpaper, so only the GTK and cursor settings are set.
restore() {
    load_theme
    if have gsettings; then
        # Themed icons (recolor_icons.py) live in DynamicTheme. Set the pack back to
        # Papirus here and the shell's colours are lost at every login.
        local icon=$icon_theme
        if [[ "$(jq -r '.appearance.icons.enableThemed // false' "$SHELL_CONFIG_FILE" 2>/dev/null)" == "true" \
              && -d "$HOME/.local/share/icons/DynamicTheme" ]]; then
            icon=DynamicTheme
        fi
        gsettings set org.gnome.desktop.interface icon-theme "$icon"
        gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme"
        gsettings set org.gnome.desktop.interface font-name "$font_name"
        gsettings set org.gnome.desktop.interface cursor-theme "$cursor_theme"
    fi
    if [[ "${XDG_CURRENT_DESKTOP:-}" == "Hyprland" ]] && have hyprctl; then
        hyprctl setcursor "$cursor_theme" 24 >/dev/null 2>&1
    fi
    return 0
}

# Sets a wallpaper through the shell. The shell runs its own pipeline for it (the wallpaper,
# video included, and the palette). The palette then reaches the desktop through the
# matugen post-hook, which runs `switchwall.sh --matugen`.
set_wallpaper() {
    local file=$1
    [[ -n "$file" ]] || die "no image was selected"
    [[ -f "$file" ]] || die "no such file: $file"
    require_shell
    qs -c ii ipc call wallpapers apply "$(realpath -- "$file")"
}

random_wallpaper() {
    have fd || die "fd is not installed"
    local image
    image=$(fd --type f -e jpg -e jpeg -e png -e webp -e jxl . "$WALLPAPERS_DIR" -0 2>/dev/null | shuf -zn1 | tr -d '\0')
    if [[ -n "$image" ]]; then
        set_wallpaper "$image"
    else
        notify -u low "No wallpapers found" "$WALLPAPERS_DIR"
    fi
}

pick_wallpaper() {
    if shell_running; then
        qs -c ii ipc call wallpaperSelector toggle
    elif have waypaper; then
        pgrep -x waypaper >/dev/null || waypaper
    elif have nsxiv; then
        local chosen
        chosen=$(nsxiv -torb "$WALLPAPERS_DIR" | head -n1)
        [[ -n "$chosen" ]] && set_wallpaper "$chosen"
    else
        die "no picker: the shell is not running, and neither waypaper nor nsxiv is installed"
    fi
}

send_to_phone() {
    have kdeconnect-cli || die "KDE Connect is not installed"
    local wallpaper device copy
    wallpaper=$(current_wallpaper)
    [[ -f "$wallpaper" ]] || die "no wallpaper to send"
    device=$(kdeconnect-cli -a --id-only | head -n1)
    [[ -n "$device" ]] || die "no KDE Connect device found"
    # KDE Connect reads the file while it sends, so it is copied to a stable name in the cache.
    mkdir -p "$PALETTE_CACHE"
    copy="$PALETTE_CACHE/phone-wallpaper.${wallpaper##*.}"
    cp -f -- "$wallpaper" "$copy"
    kdeconnect-cli -d "$device" --share "$copy" &&
        kdeconnect-cli -d "$device" --ping
}

show_colors() {
    load_theme
    load_palette
    local name
    for name in background foreground cursor black red green yellow blue magenta cyan white \
        bright_black bright_red bright_green bright_yellow bright_blue bright_magenta bright_cyan bright_white; do
        printf '%-15s %s\n' "$name" "${!name}"
    done
}

usage() {
    awk 'NR > 1 && /^# shellcheck/ { next } NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
    imgpath="" mode_flag="" type_flag="" color_flag="" color="" request_seq_flag=""
    lockscreen_flag="" lightmode_flag="" colors_only_flag="" noswitch_flag="" refresh_frame_flag=""
    color_source="" source_img=""
    local accent="" theme_file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)          mode_flag="$2"; shift 2 ;;
            --type)          type_flag="$2"; shift 2 ;;
            --request-seq)   request_seq_flag="$2"; shift 2 ;;
            --lockscreen)    lockscreen_flag="1"; shift ;;
            --lightmode)     lightmode_flag="1"; shift ;;
            --colors-only)   colors_only_flag="1"; shift ;;
            --refresh-frame) refresh_frame_flag="1"; shift ;;
            --noswitch)      noswitch_flag="1"; shift ;;
            --image)         imgpath="$2"; shift 2 ;;
            --color)
                if [[ "$2" =~ ^#?[A-Fa-f0-9]{6}$ ]]; then
                    accent="$2"; set_accent_color "$2"; shift 2
                elif [[ "$2" == "clear" ]]; then
                    accent="clear"; set_accent_color ""; shift 2
                else
                    accent="picked"; set_accent_color "$(hyprpicker --no-fancy)"; shift
                fi
                ;;
            *) [[ -z "$imgpath" ]] && imgpath="$1"; shift ;;
        esac
    done

    # A colour from the config is used instead of the wallpaper's own.
    local config_color
    config_color="$(get_accent_color_from_config)"
    if [[ "$config_color" =~ ^#?[A-Fa-f0-9]{6}$ ]]; then
        color_flag="1"
        color="$config_color"
        [[ -z "$accent" ]] && accent="$config_color"
    fi

    # These only read the wallpaper that is already set.
    if [[ -n "$noswitch_flag" || -n "$colors_only_flag" ]]; then
        [[ -z "$imgpath" ]] && imgpath=$(jq -r '.background.wallpaperPath' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "")
    fi

    # Nothing chosen yet: ask, unless a colour stands in for the wallpaper.
    if [[ -z "$imgpath" && -z "$accent" && -z "$colors_only_flag" && -z "$noswitch_flag" ]]; then
        cd "$(xdg-user-dir PICTURES)/Wallpapers/showcase" 2>/dev/null || cd "$(xdg-user-dir PICTURES)/Wallpapers" 2>/dev/null || cd "$(xdg-user-dir PICTURES)" || exit 1
        if command -v zenity >/dev/null; then
            imgpath="$(zenity --file-selection --title="Choose wallpaper" 2>/dev/null)"
        else
            imgpath="$(kdialog --getopenfilename . --title 'Choose wallpaper')"
        fi
        if [[ -z "$imgpath" ]]; then
            echo "Wallpaper selection cancelled."
            exit 0
        fi
    fi

    if [[ -z "$imgpath" || "$imgpath" == "null" ]]; then
        imgpath="$CONFIG_DIR/assets/images/default_wallpaper.png"
    fi

    # The AI category for the clock widget is unrelated to the colours, so it runs on its own.
    if [[ -z "$colors_only_flag" && -z "$noswitch_flag" ]]; then
        local ai_enabled ai_model
        ai_enabled=$(jq -r '.background.widgets.clock.cookie.aiStyling' "$SHELL_CONFIG_FILE" 2>/dev/null)
        ai_model=$(jq -r '.background.widgets.clock.cookie.aiStylingModel' "$SHELL_CONFIG_FILE" 2>/dev/null)
        if [[ "$ai_enabled" == "true" ]]; then
            mkdir -p "$STATE_DIR/user/generated/wallpaper"
            case "$ai_model" in
                gemini)     "$SCRIPT_DIR/../ai/gemini-categorize-wallpaper.sh" "$imgpath" > "$STATE_DIR/user/generated/wallpaper/category.txt" & ;;
                openrouter) "$SCRIPT_DIR/../ai/openrouter-categorize-wallpaper.sh" "$imgpath" > "$STATE_DIR/user/generated/wallpaper/category.txt" & ;;
            esac
        fi
    fi

    # The wallpaper itself. With a colour in charge, or a light-mode path that is only being
    # stored, there is none to deal with.
    if [[ -z "$accent" && ! ( -n "$lightmode_flag" && -n "$noswitch_flag" ) ]]; then
        prepare_wallpaper
    fi
    # A video's frame or a Wallpaper Engine screenshot, when that is what the colours come from.
    source_img="$color_source"
    if [[ -z "$source_img" && -z "$color_flag" ]] && is_jxl "$imgpath"; then
        source_img="$(decoded_copy "$imgpath")" || echo "[switchwall] Could not decode $imgpath for its colours" >&2
    fi

    # A light-mode path that is only being stored changes no colours.
    if [[ -n "$lightmode_flag" && -n "$noswitch_flag" ]]; then
        set_wallpaper_path "$imgpath" "lightmode"
        echo "[switchwall] Saved light mode wallpaper path."
        exit 0
    fi

    # A video has no colours of its own; prepare_wallpaper hands over its frame.
    if [[ -z "$color_flag" && -z "$source_img" ]] && is_video "$imgpath"; then
        echo "[switchwall] $imgpath is a video with no frame to take colours from" >&2
        exit 0
    fi

    # The scheme: the one asked for, else the config's. A name that is not a scheme may be a theme.
    [[ -z "$type_flag" ]] && type_flag="$(get_type_from_config)"
    local valid_type=0 t
    for t in "${allowed_types[@]}"; do
        [[ "$type_flag" == "$t" ]] && { valid_type=1; break; }
    done
    if [[ $valid_type -eq 0 ]]; then
        if [[ -f "$XDG_CONFIG_HOME/illogical-impulse/themes/$type_flag.json" ]]; then
            theme_file="$XDG_CONFIG_HOME/illogical-impulse/themes/$type_flag.json"
            valid_type=1
        elif [[ -f "$CONFIG_DIR/defaults/themes/$type_flag.json" ]]; then
            theme_file="$CONFIG_DIR/defaults/themes/$type_flag.json"
            valid_type=1
        fi
    fi
    if [[ $valid_type -eq 0 ]]; then
        echo "[switchwall] Warning: Invalid type '$type_flag', defaulting to 'auto'" >&2
        type_flag="auto"
    fi
    [[ "$type_flag" == "scheme-auto" ]] && type_flag="auto"

    # The mode is otherwise only read later, in switch(), after the dark theme file was picked.
    if [[ -n "$theme_file" && -z "$mode_flag" ]]; then
        if [[ "$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")" == "prefer-dark" ]]; then
            mode_flag="dark"
        else
            mode_flag="light"
        fi
    fi
    if [[ -n "$theme_file" && "$mode_flag" == "light" ]]; then
        local light_theme_file="${theme_file%.json}_light.json"
        if [[ -f "$light_theme_file" ]]; then
            theme_file="$light_theme_file"
            echo "[switchwall] Using light theme variant: $type_flag"
        else
            echo "[switchwall] No light variant for '$type_flag', falling back to matugen generation"
            theme_file=""
            type_flag="scheme-tonal-spot"
        fi
    fi

    # Record the wallpaper unless this run only reads it.
    if [[ -z "$colors_only_flag" && -z "$noswitch_flag" ]]; then
        if [[ -n "$lightmode_flag" ]]; then
            set_wallpaper_path "$imgpath" "lightmode"
        elif [[ -n "$lockscreen_flag" ]]; then
            set_wallpaper_path "$imgpath" "lockscreen"
        else
            set_wallpaper_path "$imgpath" "desktop"
        fi
    fi

    # A new wallpaper ends the accent colour picked for the old one.
    local current_wallpaper
    current_wallpaper=$(jq -r '.background.wallpaperPath' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "")
    if [[ -n "$imgpath" && -z "$noswitch_flag" && "$imgpath" != "$current_wallpaper" ]]; then
        set_accent_color ""
        color_flag=""
        color=""
    fi

    # 'auto' picks the scheme from the image.
    if [[ "$type_flag" == "auto" ]]; then
        if [[ -f "${source_img:-$imgpath}" ]]; then
            local detected_type
            detected_type="$(detect_scheme_type_from_image "${source_img:-$imgpath}")"
            type_flag="scheme-tonal-spot"
            for t in "${allowed_types[@]}"; do
                if [[ "$detected_type" == "$t" && "$detected_type" != "auto" ]]; then
                    type_flag="$detected_type"
                    break
                fi
            done
            [[ "$type_flag" == "$detected_type" ]] || echo "[switchwall] Warning: Could not auto-detect a valid scheme, defaulting to 'scheme-tonal-spot'" >&2
        else
            echo "[switchwall] Warning: No image to auto-detect scheme from, defaulting to 'scheme-tonal-spot'" >&2
            type_flag="scheme-tonal-spot"
        fi
    fi

    switch "$imgpath" "$mode_flag" "$type_flag" "$color_flag" "$color" "$theme_file"
}

case "${1:-}" in
    --matugen)          recolor_icons_if_themed; refine_wal_palette; apply_palette; reload_gtk; refresh_tools ;;
    --apply)            apply_palette ;;
    --reload|--restart) reload_all ;;
    --restore)          restore ;;
    --set)              set_wallpaper "${2:-}" ;;
    --random)           random_wallpaper ;;
    --pick)             pick_wallpaper ;;
    --reset)            set_wallpaper "$(current_wallpaper)" ;;
    --phone)            send_to_phone ;;
    --colors)           show_colors ;;
    --folders)          python3 "$SCRIPT_DIR/recolor_icons.py" --force ;;
    -h|--help)          usage ;;
    *)                  main "$@" ;;
esac
