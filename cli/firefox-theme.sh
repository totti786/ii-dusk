#!/usr/bin/env bash
#
# firefox-theme — install ii-dusk's Firefox theme into a profile.
#
# The theme is chrome/userChrome.css (ag.proton, see licenses/README.md) and the one
# pref that makes Firefox read it. Nothing else in the profile is touched: an existing
# userChrome.css of yours is kept as userChrome.css.ii-dusk-backup, and `remove` puts
# it back.
#
# Usage: firefox-theme [install|remove|status] [--profile DIR]
#   install   copy the theme into the profile (the default)
#   remove    take it out again and restore the backup, if there is one
#   status    say which profile would be used and what is installed
#   --profile DIR  use this profile directory instead of Firefox's default one
#
# Restart Firefox afterwards; it reads userChrome.css at start-up only.

set -euo pipefail

here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
src="$here/firefox"
theme="userChrome.css"
backup_name="userChrome.css.ii-dusk-backup"
stamp_name=".ii-dusk-theme"
begin_mark="// >>> ii-dusk firefox theme"
end_mark="// <<< ii-dusk firefox theme"

die() {
    printf 'firefox-theme: %s\n' "$*" >&2
    exit 1
}
say() { printf '  %s\n' "$*"; }

# Firefox's default profile, from profiles.ini: the [Install...] default first (what the
# running install uses), then the profile marked Default=1, then the first one listed.
default_profile() {
    local data="${XDG_CONFIG_HOME:-$HOME/.config}" root
    for root in "$HOME/.mozilla/firefox" "$data/mozilla/firefox" \
        "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox" "$HOME/snap/firefox/common/.mozilla/firefox"; do
        [[ -f "$root/profiles.ini" ]] || continue
        python3 -I - "$root" <<'PY' && return 0
import configparser, os, sys
root = sys.argv[1]
ini = configparser.RawConfigParser()
ini.optionxform = str
ini.read(os.path.join(root, "profiles.ini"))

def resolve(section):
    path = ini.get(section, "Path", fallback="")
    if not path:
        return None
    rel = ini.get(section, "IsRelative", fallback="1") == "1"
    full = os.path.join(root, path) if rel else path
    return full if os.path.isdir(full) else None

for section in ini.sections():
    if section.startswith("Install"):
        value = ini.get(section, "Default", fallback="")
        full = os.path.join(root, value) if value and not os.path.isabs(value) else value
        if full and os.path.isdir(full):
            print(full)
            sys.exit(0)
profiles = [s for s in ini.sections() if s.startswith("Profile")]
for section in profiles:
    if ini.get(section, "Default", fallback="0") == "1" and resolve(section):
        print(resolve(section))
        sys.exit(0)
for section in profiles:
    if resolve(section):
        print(resolve(section))
        sys.exit(0)
sys.exit(1)
PY
    done
    return 1
}

firefox_running() { pgrep -x firefox >/dev/null 2>&1 || pgrep -x firefox-bin >/dev/null 2>&1; }

strip_block() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    sed -i "\|^$begin_mark|,\|^$end_mark|d" "$file"
}

cmd_install() {
    local profile="$1" chrome="$1/chrome" css="$1/chrome/$theme"
    [[ -f "$src/$theme" ]] || die "$src/$theme is missing"
    mkdir -p "$chrome"
    if [[ -f "$css" ]] && ! cmp -s "$css" "$src/$theme" && [[ ! -f "$chrome/$stamp_name" ]]; then
        local dest="$chrome/$backup_name"
        [[ -e "$dest" ]] && dest="$dest.$(date +%Y%m%d-%H%M%S)"
        cp -p "$css" "$dest"
        say "kept your own $theme as ${dest##*/}"
    fi
    cp "$src/$theme" "$css"
    date +%F >"$chrome/$stamp_name"

    local userjs="$profile/user.js"
    if [[ -f "$userjs" ]] && grep -q "^$begin_mark" "$userjs"; then
        :
    elif [[ -f "$userjs" ]] && grep -qE '^[[:space:]]*user_pref\("toolkit\.legacyUserProfileCustomizations\.stylesheets",[[:space:]]*true\)' "$userjs"; then
        :
    else
        { [[ -s "$userjs" ]] && printf '\n'; printf '%s\n' "$begin_mark"; grep -v '^//' "$src/user.js"; printf '%s\n' "$end_mark"; } >>"$userjs"
    fi
    say "installed in $profile"
    firefox_running && say "Firefox is running: restart it to see the theme"
    return 0
}

cmd_remove() {
    local profile="$1" chrome="$1/chrome" css="$1/chrome/$theme"
    if [[ -f "$css" ]] && { [[ -f "$chrome/$stamp_name" ]] || cmp -s "$css" "$src/$theme"; }; then
        rm -f "$css" "$chrome/$stamp_name"
        local saved
        saved="$(ls -1t "$chrome/$backup_name"* 2>/dev/null | head -1 || true)"
        if [[ -n "$saved" ]]; then
            mv "$saved" "$css"
            say "restored your $theme from ${saved##*/}"
        fi
        say "removed from $profile"
    else
        say "the ii-dusk theme is not installed in $profile"
    fi
    strip_block "$profile/user.js"
    [[ -f "$profile/user.js" && ! -s "$profile/user.js" ]] && rm -f "$profile/user.js"
    say "Firefox keeps the stylesheet pref in prefs.js; it does nothing without a userChrome.css"
    return 0
}

cmd_status() {
    local profile="$1" css="$1/chrome/$theme"
    say "profile   $profile"
    if [[ -f "$css" ]] && cmp -s "$css" "$src/$theme"; then
        say "theme     installed"
    elif [[ -f "$css" ]]; then
        say "theme     a different userChrome.css is there"
    else
        say "theme     not installed"
    fi
    [[ -n "$(ls -1 "$1/chrome/$backup_name"* 2>/dev/null | head -1)" ]] && say "backup    your previous userChrome.css is kept"
    firefox_running && say "firefox   running"
    return 0
}

action="install"
profile=""
while (($# > 0)); do
    case "$1" in
        install | remove | status) action="$1" ;;
        -p | --profile)
            shift
            profile="${1:-}"
            [[ -n "$profile" ]] || die "--profile needs a directory"
            ;;
        -h | --help)
            sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done

if [[ -z "$profile" ]]; then
    profile="$(default_profile)" || die "no Firefox profile found (open Firefox once, or pass --profile DIR)"
fi
[[ -d "$profile" ]] || die "not a directory: $profile"

"cmd_$action" "$profile"
