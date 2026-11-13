#!/usr/bin/env bash
# Lid switch handler for the `switch:on/off:Lid Switch` binds in custom/keybinds.lua.
#
#   lid closed, on AC               -> blank the internal panel, keep running
#   lid closed, on battery          -> suspend (hypridle locks via before_sleep_cmd)
#   keep-awake toggled in the shell -> blank the internal panel, never suspend
#
# Keep-awake is Quickshell's IdleInhibitor toggle and only inhibits idle, not
# sleep, so the lid handler has to consult the shell's persisted state itself.
#
# LID_DRY_RUN=1 prints the decision instead of acting on it.

set -u

INTERNAL="eDP-1"
STATES="$HOME/.local/state/quickshell/states.json"

dpms() {
    if [[ ${LID_DRY_RUN:-0} == 1 ]]; then
        echo "dpms $1 $INTERNAL"
        return 0
    fi
    hyprctl dispatch "hl.dsp.dpms({ action = \"$1\", monitor = \"$INTERNAL\" })" >/dev/null
}

suspend() {
    if [[ ${LID_DRY_RUN:-0} == 1 ]]; then
        echo "suspend"
        return 0
    fi
    # Both block until resume; only reached on failure if the box comes back up.
    systemctl suspend || loginctl suspend || dpms off
}

if [[ ${1:-close} == open ]]; then
    dpms on
    exit 0
fi

# A timed keep-awake session that already elapsed does not count, even if the
# shell has not rewritten states.json yet.
keep_awake=false
if pidof qs quickshell >/dev/null 2>&1 && [[ -r $STATES ]] && command -v jq >/dev/null; then
    keep_awake=$(jq -r '(.idle.inhibit // false) and (((.idle.expiresAt // 0) == 0) or (.idle.expiresAt > (now * 1000)))' "$STATES" 2>/dev/null)
    keep_awake=${keep_awake:-false}
fi

on_ac=false
if [[ -r /sys/class/power_supply/ACAD/online ]] && [[ $(</sys/class/power_supply/ACAD/online) == 1 ]]; then
    on_ac=true
fi

if [[ $keep_awake == true || $on_ac == true ]]; then
    dpms off
else
    suspend
fi
