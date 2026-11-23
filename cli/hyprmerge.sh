#!/usr/bin/env bash
#
# hyprmerge — fold a repository Hyprland config into the user's persistent one,
# key by key, never overwriting anything already set.
#
#   hyprmerge.sh <repo-config> [local-config] [-v]

set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

IS_VERBOSE=false
TEMP_ARGS=()

for arg in "$@"; do
    case "$arg" in
        -v | --verbose) IS_VERBOSE=true ;;
        *) TEMP_ARGS+=("$arg") ;;
    esac
done

set -- "${TEMP_ARGS[@]}"

REPO_CONFIG="${1:-}"
LOCAL_CONFIG="${2:-$XDG_DATA_HOME/ii-dusk/hyprland.conf}"
VERBOSE="$IS_VERBOSE"

if [[ -z "$REPO_CONFIG" || ! -f "$REPO_CONFIG" ]]; then
    echo -e "\e[1;31m[ERROR]\e[0m Source config invalid: $REPO_CONFIG"
    exit 1
fi

if [[ ! -f "$LOCAL_CONFIG" ]]; then
    mkdir -p "$(dirname "$LOCAL_CONFIG")"
    touch "$LOCAL_CONFIG"
fi

# Route every write through hyprset (sibling, CLI, or mirrored), with the same target file.
hyprset() {
    local cmd=""
    if [[ -f "$SCRIPT_DIR/hyprset.sh" ]]; then
        cmd="$SCRIPT_DIR/hyprset.sh"
    elif command -v ii-dusk >/dev/null 2>&1; then
        HYPRSET_CONFIG="$LOCAL_CONFIG" ii-dusk hyprset "$@"
        return $?
    elif [[ -f "$XDG_DATA_HOME/ii-dusk/cli/hyprset.sh" ]]; then
        cmd="$XDG_DATA_HOME/ii-dusk/cli/hyprset.sh"
    else
        echo -e "\e[1;31m[ERROR]\e[0m hyprset script not found" >&2
        return 1
    fi
    HYPRSET_CONFIG="$LOCAL_CONFIG" bash "$cmd" "$@"
}

log() {
    [[ "$VERBOSE" == "true" ]] && echo -e "\e[1;34m[VERBOSE] [hyprmerge]\e[0m $*"
    return 0
}
skip() {
    [[ "$VERBOSE" == "true" ]] && echo -e "\e[1;33m[VERBOSE] [SKIP]\e[0m: $*"
    return 0
}
apply() { echo -e "\e[1;32m[APPLYING]\e[0m: $*"; }

key_exists_in_section() {
    local section="$1" field="$2"
    # Extracts section block and checks for existing key-value pair
    sed -n "/^[[:space:]]*${section}[[:space:]]*{/,/^[[:space:]]*}/ p" "$LOCAL_CONFIG" | grep -qE "^[[:space:]]*${field}[[:space:]]*="
}

current_section=""
log "Merging $REPO_CONFIG into $LOCAL_CONFIG"

while IFS= read -r line || [[ -n "$line" ]]; do
    # Clean whitespace and carriage returns
    trimmed=$(echo "$line" | tr -d '\r' | xargs)

    # Ignore empty lines and comments
    [[ -z "$trimmed" || "$trimmed" =~ ^# ]] && continue

    # Detect section entrance (e.g., general { )
    if echo "$trimmed" | grep -q "{"; then
        section_name=$(echo "$trimmed" | cut -d'{' -f1 | xargs)
        if [[ -n "$section_name" ]]; then
            current_section="$section_name"
            continue
        fi
    fi

    # Detect section exit
    if [[ "$trimmed" == "}" ]]; then
        current_section=""
        continue
    fi

    # Parse Key = Value pairs
    if echo "$trimmed" | grep -q "="; then
        field=$(echo "$trimmed" | cut -d'=' -f1 | xargs)
        value=$(echo "$trimmed" | cut -d'=' -f2- | xargs)

        # Handle specific animation rules
        if [[ "$field" == "animation" ]]; then
            anim_name=$(echo "$value" | cut -d',' -f1 | xargs)
            if grep -q "animation = $anim_name" "$LOCAL_CONFIG"; then
                skip "animation $anim_name"
            else
                apply "animation $anim_name"
                full_params=$(echo "$value" | cut -d',' -f2- | xargs)
                hyprset anim "$anim_name" "$full_params" >/dev/null 2>&1 || true
            fi
            continue
        fi

        # Process Sectioned or Global keys
        if [[ -n "$current_section" ]]; then
            if key_exists_in_section "$current_section" "$field"; then
                skip "${current_section}:${field}"
            else
                apply "${current_section}:${field}"
                hyprset key "${current_section}:${field}" "$value" >/dev/null 2>&1 || true
                sleep 0.05
            fi
        else
            # Rules that are appended directly to file (binds, execs, etc.)
            if [[ "$field" =~ ^(layerrule|windowrule|windowrulev2|bind|exec|env|monitor)$ ]]; then
                if grep -qF "$trimmed" "$LOCAL_CONFIG"; then
                    skip "rule: $field"
                else
                    apply "rule: $field"
                    echo "$trimmed" >>"$LOCAL_CONFIG"
                fi
            else
                # Handle standard global settings
                if grep -qE "^[[:space:]]*${field}[[:space:]]*=" "$LOCAL_CONFIG"; then
                    skip "$field"
                else
                    apply "$field"
                    hyprset key "$field" "$value" >/dev/null 2>&1 || true
                fi
            fi
        fi
        continue
    fi
done <"$REPO_CONFIG"

log "Merge complete."
