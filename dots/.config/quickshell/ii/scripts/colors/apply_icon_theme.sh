#!/usr/bin/env bash
# Point every copy of the icon theme setting at one theme, and tell running apps to re-read it.
#
# There are five copies of this setting and they have to move together: gsettings for GNOME and
# GTK, kdeglobals for Qt and KDE apps - this shell included - the GTK 3 and GTK 4 inis, and
# XSETTINGS for X11 apps. Leaving one behind is not a partial success: the next time anything
# asks the icon loader to reload, it reads kdeglobals, and the whole desktop silently reverts to
# whatever that one still says. That is why this is one script with one caller-supplied name,
# rather than a write in each place that happens to need one.
#
# Usage: apply_icon_theme.sh <theme-name>

set -u

pack="${1:-}"
[ -n "$pack" ] || { echo "apply_icon_theme.sh: no theme name given" >&2; exit 1; }

# `changed` stays 0 when every copy already names this theme (a rebuild of the same DynamicTheme):
# then nothing is written, and the loader needs one refresh instead of two.
changed=0
if [ "$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")" != "$pack" ]; then
    gsettings set org.gnome.desktop.interface icon-theme "$pack" 2>/dev/null || true
    changed=1
fi

if command -v kwriteconfig6 >/dev/null 2>&1; then
    if [ "$(kreadconfig6 --file kdeglobals --group Icons --key Theme 2>/dev/null)" != "$pack" ]; then
        kwriteconfig6 --file kdeglobals --group Icons --key Theme "$pack"
        changed=1
    fi
fi

set_ini() {
    file="$1"
    grep -qx "gtk-icon-theme-name=$pack" "$file" 2>/dev/null && return 0
    changed=1
    mkdir -p "${file%/*}"
    [ -f "$file" ] || printf '[Settings]\n' > "$file"
    grep -v '^gtk-icon-theme-name=' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    printf 'gtk-icon-theme-name=%s\n' "$pack" >> "$file"
}

conf="${XDG_CONFIG_HOME:-$HOME/.config}"
set_ini "$conf/gtk-3.0/settings.ini"
set_ini "$conf/gtk-4.0/settings.ini"

# qt5ct and qt6ct: with QT_QPA_PLATFORMTHEME=qt6ct, Qt apps (file managers, KDE tools) read the
# icon theme from here, not from kdeglobals.
for qtct in "$conf/qt5ct/qt5ct.conf" "$conf/qt6ct/qt6ct.conf"; do
    [ -f "$qtct" ] && grep -q '^icon_theme=' "$qtct" || continue
    grep -qx "icon_theme=$pack" "$qtct" && continue
    sed -i "s|^icon_theme=.*|icon_theme=$pack|" "$qtct"
    changed=1
done

if command -v xsettingsd >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    xconf="$conf/xsettingsd/xsettingsd.conf"
    if ! grep -qx "Net/IconThemeName \"$pack\"" "$xconf" 2>/dev/null; then
        changed=1
        mkdir -p "${xconf%/*}"
        touch "$xconf"
        grep -v '^Net/IconThemeName ' "$xconf" > "$xconf.tmp" && mv "$xconf.tmp" "$xconf"
        printf 'Net/IconThemeName "%s"\n' "$pack" >> "$xconf"
        if pgrep -x xsettingsd >/dev/null 2>&1; then
            pkill -HUP -x xsettingsd || true
        else
            setsid -f xsettingsd >/dev/null 2>&1 || true
        fi
    fi
fi

# Twice, with a gap, when the name changed. KIconLoader answers this signal by reading the theme name and then
# rebuilding the theme it names, in that order, so the first refresh hands Qt the name from
# before this change and every icon comes out one theme behind. The second refresh, once the
# rebuild has happened, is the one that lands the new theme. The group argument is ignored -
# each signal rebuilds all of them - so this is two refreshes, not the fourteen it once sent.
# When no copy of the setting changed, Qt already holds this theme's name and one refresh is
# enough to make it re-read the rebuilt directory.
if [ "$changed" = 1 ]; then passes="1 2"; else passes="1"; fi
for _ in $passes; do
    dbus-send --session --type=signal /KIconLoader \
        org.kde.KIconLoader.iconChanged int32:0 2>/dev/null || true
    # The loader rebuilds its theme on its own thread after each signal; the shell redraws only
    # once this script is done, and a redraw that beats the rebuild shows the old colours (tried 0.1 s:
    # folders stopped changing at all)
    sleep 0.4
done
