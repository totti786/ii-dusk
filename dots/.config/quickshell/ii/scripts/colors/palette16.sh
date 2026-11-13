# shellcheck shell=bash disable=SC2154,SC2034 # palette variables are set by load_palette
#
# palette16.sh: the 16-colour palette backend, sourced by switchwall.sh.
#
# matugen's pywal-style template (matugen/templates/pywal.json) maps Material roles onto the 16
# terminal colours and writes ~/.cache/wal/colors.json. Everything here turns that file into the
# palettes of the apps that only understand 16 colours: Hyprland, hyprlock, Alacritty, rofi,
# Geany, Discord, spicetify, the Telegram theme,
# Qt/Kvantum, plus colors.sh and colors.Xresources for the scripts that source them.
#
# When those apps move to Material roles directly, delete this file and the two places
# switchwall.sh uses it (`apply_palette` and `refine_wal_palette`).

PALETTE_JSON="$HOME/.cache/wal/colors.json"
HYPR_COLORS="$USER_CONFIG/hypr/colors.conf"
HYPRLOCK_CONF="$USER_CONFIG/hypr/hyprlock.conf"
ALACRITTY_DIR="$USER_CONFIG/alacritty"
ALACRITTY_COLORS="$ALACRITTY_DIR/colors.toml"
ALACRITTY_CONF="$ALACRITTY_DIR/alacritty.toml"
ROFI_COLORS="$USER_CONFIG/rofi/themes/colors.rasi"
GEANY_COLORS="$USER_CONFIG/geany/colorschemes/Pywal.conf"
DISCORD_THEME="$USER_CONFIG/Equicord/themes/caelestia.theme.css"
SPICETIFY_COLORS="$USER_CONFIG/spicetify/Themes/pywal/color.ini"
WAL_XRESOURCES="$HOME/.cache/wal/colors.Xresources"

# Set by write_if_changed: whether any file was actually written during this run.
CHANGED=0

# Writes CONTENT to FILE only when it differs, so the apps that watch these files do not
# reload for nothing. Sets CHANGED when it writes.
write_if_changed() {
    local file=$1 content=$2
    if [[ -f "$file" && "$(cat -- "$file")" == "$content" ]]; then
        return 0
    fi
    mkdir -p -- "$(dirname -- "$file")"
    printf '%s\n' "$content" > "$file"
    CHANGED=1
}

# matugen's pywal output as shell variables: background, foreground, cursor, color0..color15,
# plus the names the writers below use (black, bright_red, ...) and two derived shades.
load_palette() {
    [[ -f "$PALETTE_JSON" ]] || die "no palette at $PALETTE_JSON; set a wallpaper first"
    local key value
    while IFS=$'\t' read -r key value; do
        printf -v "$key" '%s' "$value"
    done < <(jq -r '(.special + .colors) | to_entries[] | [.key, .value] | @tsv' "$PALETTE_JSON")

    black=$color0 red=$color1 green=$color2 yellow=$color3
    blue=$color4 magenta=$color5 cyan=$color6 white=$color7
    bright_black=$color8 bright_red=$color9 bright_green=$color10 bright_yellow=$color11
    bright_blue=$color12 bright_magenta=$color13 bright_cyan=$color14 bright_white=$color15

    if have pastel; then
        # Surfaces mix matugen's own black and bright black ("surfaces" in the palette file),
        # not the retoned terminal colours, which no longer sit near the background.
        local surf_black=$black surf_bright=$bright_black
        surf_black=$(jq -r '.surfaces.black // empty' "$PALETTE_JSON" 2>/dev/null) || true
        surf_bright=$(jq -r '.surfaces.bright_black // empty' "$PALETTE_JSON" 2>/dev/null) || true
        surf_black=${surf_black:-$black}
        surf_bright=${surf_bright:-$bright_black}
        bg_mix=$(pastel mix -f 0.4 "$surf_bright" "$surf_black" | pastel format hex)
        bg_light=$(pastel mix -f 0.2 "$surf_bright" "$surf_black" | pastel format hex)
        bg_lighter=$(pastel lighten 0.08 "$surf_black" | pastel format hex)
    else
        bg_mix=$black bg_light=$black bg_lighter=$black
    fi

    alpha_rofi=ff
}

# Hyprland's colors.conf and hyprlock's palette: "$name = rgba(RRGGBBff)" lines.
write_hypr_palette() {
    local -a expr=()
    local name hex alpha
    for name in black red green yellow blue magenta cyan white; do
        hex=${!name}
        alpha=ff
        [[ "$name" == "black" ]] && alpha=aa
        expr+=(-e "s|\\\$${name}[[:space:]]*=.*|\$${name} = rgba(${hex:1}${alpha})|")
    done
    local file
    for file in "$HYPR_COLORS" "$HYPRLOCK_CONF"; do
        [[ -f "$file" ]] || continue
        write_if_changed "$file" "$(sed "${expr[@]}" "$file")"
    done
}

write_alacritty_palette() {
    local text
    text=$(cat <<EOF
[colors.primary]
background = "$background"
foreground = "$foreground"

[colors.cursor]
text = "$black"
cursor = "$white"

[colors.normal]
black = "$black"
red = "$red"
green = "$green"
yellow = "$yellow"
blue = "$blue"
magenta = "$magenta"
cyan = "$cyan"
white = "$white"

[colors.bright]
black = "$bright_black"
red = "$bright_red"
green = "$bright_green"
yellow = "$bright_yellow"
blue = "$bright_blue"
magenta = "$bright_magenta"
cyan = "$bright_cyan"
white = "$bright_white"
EOF
)
    # Alacritty reloads open windows when the main file changes, not when an imported file does,
    # so touch the main file when the colours changed. Windows already open then take them too.
    local was=$CHANGED
    CHANGED=0
    write_if_changed "$ALACRITTY_COLORS" "$text"
    # Touch the main config so Alacritty (which only watches alacritty.toml,
    # not the imported colors.toml) picks up the new palette live.
    [[ -f "$ALACRITTY_DIR/alacritty.toml" ]] && touch "$ALACRITTY_DIR/alacritty.toml"
    if (( CHANGED )) && [[ -f "$ALACRITTY_CONF" ]]; then
        touch -- "$ALACRITTY_CONF"
    fi
    CHANGED=$(( was || CHANGED ))
}

write_rofi_palette() {
    local text
    text=$(cat <<EOF
/* colors */
* {
    background:       ${bg_mix}${alpha_rofi};
    background-alt:   ${bg_light};
    background-blur:  ${background}60;
    foreground:       ${foreground};
    selected:         ${red};
    highlight:        ${yellow};
    urgent:           ${blue};
    on:               ${magenta};
    off:              ${black};
    red:              ${bright_red};
    green:            ${bright_green};
    yellow:           ${bright_yellow};
    blue:             ${bright_blue};
    magenta:          ${bright_magenta};
    cyan:             ${bright_cyan};
    white:            ${bright_white};
}
EOF
)
    write_if_changed "$ROFI_COLORS" "$text"
}

write_geany_palette() {
    [[ -f "$GEANY_COLORS" ]] || return 0
    local text
    text=$(sed \
        -e "s/^bg=.*/bg=${background}/" \
        -e "s/^fg=.*/fg=${foreground}/" \
        -e "s/^tag_yellow=.*/tag_yellow=${cyan}/" \
        -e "s/^fold_bg_grey=.*/fold_bg_grey=${bg_lighter}/" \
        -e "s/^keyword_orange=.*/keyword_orange=${red}/" \
        -e "s/^string_green=.*/string_green=${green}/" \
        -e "s/^margin_bg_grey=.*/margin_bg_grey=${black}/" \
        -e "s/^margin_fg_grey=.*/margin_fg_grey=${black}/" \
        -e "s/^error_red=.*/error_red=${magenta}/" \
        -e "s/^current_line_grey=.*/current_line_grey=${bg_lighter}/" \
        -e "s/^selection_blue=.*/selection_blue=${white}/" \
        "$GEANY_COLORS")
    write_if_changed "$GEANY_COLORS" "$text"
}

write_discord_palette() {
    [[ -f "$DISCORD_THEME" ]] || return 0
    local -A vars=(
        [text-2]=$bright_white [text-3]=$foreground [text-4]=$foreground [text-5]=$foreground
        [accent-1]=$red [accent-2]=$green [accent-3]=$blue [accent-4]=$yellow [accent-5]=$magenta
        [bg-1]=$bg_light [bg-2]=$background [bg-3]=$bg_light [bg-4]=$bg_mix
    )
    local -a expr=()
    local name
    # Anchored to the start of the line: an unanchored match also rewrites the same text
    # inside the theme's comments.
    for name in "${!vars[@]}"; do
        expr+=(-e "s|^\([[:space:]]*\)--${name}:.*|\1--${name}: ${vars[$name]};|")
    done
    local text
    text=$(sed "${expr[@]}" "$DISCORD_THEME")
    write_if_changed "$DISCORD_THEME" "$text"
}

# Spicetify's pywal colour set. Spotify only picks the change up after a refresh, so run it
# when the colours changed. The values are written without the leading #.
write_spicetify_palette() {
    [[ -f "$SPICETIFY_COLORS" ]] || return 0
    local text
    text=$(cat <<EOF
[pywal]
text               = ${bright_white#\#}
subtext            = ${bright_white#\#}
main               = ${bg_light#\#}
main-elevated      = ${bg_mix#\#}
highlight          = ${magenta#\#}
highlight-elevated = ${bright_magenta#\#}
sidebar            = ${bg_mix#\#}
player             = ${blue#\#}
card               = ${green#\#}
shadow             = ${bright_black#\#}
selected-row       = ${green#\#}
button             = ${red#\#}
button-active      = ${bright_red#\#}
button-disabled    = ${blue#\#}
tab-active         = ${yellow#\#}
notification       = ${cyan#\#}
notification-error = ${bright_red#\#}
equalizer          = ${white#\#}
misc               = ${red#\#}
EOF
)
    local was=$CHANGED
    CHANGED=0
    write_if_changed "$SPICETIFY_COLORS" "$text"
    if (( CHANGED )) && have spicetify; then
        ( spicetify -q refresh >/dev/null 2>&1 9>&- & )
    fi
    CHANGED=$(( was || CHANGED ))
}

# X resources for the scripts that still ask xrdb for a colour (brightness, shot). Without a
# display there is nothing to merge.
merge_xresources() {
    [[ -n "$DISPLAY" && -f "$WAL_XRESOURCES" ]] || return 0
    have xrdb && xrdb -merge "$WAL_XRESOURCES" >/dev/null 2>&1
    return 0
}

# Tools that take the palette from their own files. None blocks the apply: the Telegram theme runs
# detached (the apply lock is not handed to them).
apply_side_tools() {
    # These tools only read the palette. Skip them when neither the palette nor the shell's
    # colours changed, so an apply that changes nothing does not flip the icon theme again.
    local sig_file="$PALETTE_CACHE/side-tools.sig" sig
    sig=$(cat -- "$PALETTE_JSON" "$STATE_DIR/user/generated/colors.json" 2>/dev/null | sha256sum | cut -d' ' -f1)
    [[ "$(cat -- "$sig_file" 2>/dev/null)" == "$sig" ]] && return 0
    # Qt apps (qt5ct/qt6ct with Kvantum) and the Kvantum theme follow the same palette.
    python3 "$SCRIPT_DIR/qt_colors.py" >/dev/null 2>&1 || echo "[switchwall] Qt colours not updated" >&2
    merge_xresources
    ( python3 "$SCRIPT_DIR/telegram_theme.py" >"$PALETTE_CACHE/telegram-theme.log" 2>&1 9>&- & )
    printf '%s\n' "$sig" > "$sig_file"
    return 0
}

# The wallpaper matugen built the palette from.
palette_wallpaper() {
    jq -r '.wallpaper // ""' "$PALETTE_JSON" 2>/dev/null
}


# Pushes the palette's colours into the running Hyprland. This used to be `hyprctl reload
# config-only`, but a reload throws away everything the shell set at run time (the blur and
# ignore_alpha layer rules, rounding, gaps, borders) and puts it back a few hundred milliseconds
# to three seconds later, which showed as the widgets and bar flickering at every theme change.
# These are the keys hyprland/general.lua fills from colors.conf; the shell pushes the active
# border and group colours itself.
apply_hypr_live() {
    have hyprctl || return 0
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 0
    local c_black c_blue c_cyan c_magenta c_red c_white c_yellow
    c_black="rgba(${black#\#}aa)"
    c_blue="rgba(${blue#\#}ff)" c_cyan="rgba(${cyan#\#}ff)" c_magenta="rgba(${magenta#\#}ff)"
    c_red="rgba(${red#\#}ff)" c_white="rgba(${white#\#}ff)" c_yellow="rgba(${yellow#\#}ff)"
    hyprctl eval "hl.config({ general = { col = { inactive_border = { colors = { '$c_magenta', '$c_yellow' }, angle = 60 } } }, \
group = { col = { border_inactive = { colors = { '$c_blue', '$c_cyan' }, angle = 90 }, \
border_locked_active = { colors = { '$c_blue', '$c_cyan' }, angle = 45 }, border_locked_inactive = { colors = { '$c_blue', '$c_cyan' }, angle = 45 } }, \
groupbar = { text_color = '$c_white', col = { inactive = '$c_red' } } }, decoration = { shadow = { color = '$c_black' } } })" >/dev/null 2>&1 || true
}

# matugen's pywal template maps Material roles onto the 16 colours, which leaves blue, magenta and
# cyan as dark containers and bright black equal to the background. wal_palette.py replaces the
# accents with the wallpaper's own dominant colours at readable tones (the way pywal chose them)
# and retones the greys. It rewrites ~/.cache/wal/colors.json in place and leaves it as matugen
# wrote it if anything fails, so this never blocks the hook.
refine_wal_palette() {
    local py
    py="$(eval echo "$ILLOGICAL_IMPULSE_VIRTUAL_ENV")/bin/python"
    [[ -x "$py" && -f "$PALETTE_JSON" ]] || return 0
    "$py" "$SCRIPT_DIR/wal_palette.py" "$PALETTE_JSON" || true
}

# Writes every palette file from the current palette. Hyprland reloads only when one of its
# files changed, and a second run in a row does nothing.
apply_palette() {
    mkdir -p "$PALETTE_CACHE"
    exec 9>"$PALETTE_CACHE/apply.lock"
    flock -x 9
    load_theme
    load_palette
    # Before the side tools below: merge_xresources reads colors.Xresources.
    write_wal_files
    CHANGED=0
    write_hypr_palette
    write_alacritty_palette
    write_rofi_palette
    write_geany_palette
    write_discord_palette
    write_spicetify_palette
    apply_side_tools
    apply_hypr_live
    return 0
}

# The two files in ~/.cache/wal that something here still reads, written from matugen's palette
# (~/.cache/wal/colors.json): colors.sh, sourced by material and backup, and
# colors.Xresources, merged into xrdb for brightness and shot. They used to come from
# `wpg -s`, which pulled in pywal to write twenty more files that nothing opens. The text is the
# same as pywal's templates, so a consumer cannot tell the difference.
write_wal_files() {
    [[ -f "$PALETTE_JSON" ]] || return 0
    local dir out
    dir=$(dirname -- "$PALETTE_JSON")
    out=$(jq -r '
        def c($n): .colors["color\($n)"];
        . as $r | ($r.special.background) as $bg | ($r.special.foreground) as $fg | ($r.special.cursor // $fg) as $cur |
        "# Shell variables\n# Generated by '"'"'switchwall'"'"'\nwallpaper='"'"'\($r.wallpaper // "")'"'"'\n\n# Special\nbackground='"'"'\($bg)'"'"'\nforeground='"'"'\($fg)'"'"'\ncursor='"'"'\($cur)'"'"'\n\n# Colors\n"
        + ([range(0;16) as $n | "color\($n)='"'"'\($r | c($n))'"'"'"] | join("\n"))
        + "\n\n# FZF colors\nexport FZF_DEFAULT_OPTS=\"\n    $FZF_DEFAULT_OPTS\n    --color fg:7,bg:0,hl:1,fg+:232,bg+:1,hl+:255\n    --color info:7,prompt:2,spinner:1,pointer:232,marker:1\n\"\n\n# Fix LS_COLORS being unreadable.\nexport LS_COLORS=\"${LS_COLORS}:su=30;41:ow=30;42:st=30;44:\"\n"
    ' "$PALETTE_JSON" 2>/dev/null) || return 0
    [[ -n "$out" ]] && printf '%s\n' "$out" > "$dir/colors.sh.tmp" && mv -f "$dir/colors.sh.tmp" "$dir/colors.sh"
    out=$(jq -r '
        . as $r | ($r.special.background) as $bg | ($r.special.foreground) as $fg | ($r.special.cursor // $fg) as $cur | ($r.alpha // "100") as $a |
        def rgba($h): ($h | ltrimstr("#")) as $x | "rgba:\($x[0:2])/\($x[2:4])/\($x[4:6])/ff";
        "! X colors.\n! Generated by '"'"'switchwall'"'"'\n"
        + "*foreground:        \($fg)\n*background:        \($bg)\n*.foreground:       \($fg)\n*.background:       \($bg)\n"
        + "emacs*foreground:   \($fg)\nemacs*background:   \($bg)\n"
        + "URxvt*foreground:   \($fg)\nXTerm*foreground:   \($fg)\nUXTerm*foreground:  \($fg)\n"
        + "URxvt*background:   [\($a)]\($bg)\nXTerm*background:   \($bg)\nUXTerm*background:  \($bg)\n"
        + "URxvt*cursorColor:  \($cur)\nXTerm*cursorColor:  \($cur)\nUXTerm*cursorColor: \($cur)\n"
        + "URxvt*borderColor:  [\($a)]\($bg)\n\n! Colors 0-15.\n"
        + ([range(0;16) as $n | ($r.colors["color\($n)"]) as $v | "*.color\($n): \($v)\n*color\($n):  \($v)"] | join("\n"))
        + "\n\n! Black color that will not be affected by bold highlighting.\n*.color66: \($bg)\n*color66:  \($bg)\n"
        + "\n! Xclock colors.\nXClock*foreground: \($fg)\nXClock*background: \($bg)\nXClock*majorColor:  \(rgba($fg))\nXClock*minorColor:  \(rgba($fg))\nXClock*hourColor:   \(rgba($fg))\nXClock*minuteColor: \(rgba($fg))\nXClock*secondColor: \(rgba($fg))\n"
        + "\n! Set depth to make transparency work.\nURxvt*depth: 32"
    ' "$PALETTE_JSON" 2>/dev/null) || return 0
    [[ -n "$out" ]] && printf '%s\n' "$out" > "$dir/colors.Xresources.tmp" && mv -f "$dir/colors.Xresources.tmp" "$dir/colors.Xresources"
    return 0
}
