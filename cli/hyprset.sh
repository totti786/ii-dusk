#!/usr/bin/env bash
#
# hyprset — write a single key or animation into the persistent Hyprland config.
#
#   hyprset.sh key  <section:field|field> <value>
#   hyprset.sh anim <name>                <params>
#
# Reached as `setup-ii-dusk.sh hyprset ...`, as `ii-dusk hyprset ...`,
# or run directly by HyprlandSettings.qml. Always executed, never sourced.

set -euo pipefail

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

# HYPRSET_CONFIG wins; otherwise the current data dir, falling back to the
# pre-rename location so a half-migrated install still writes somewhere sane.
CONFIG_PATH="${HYPRSET_CONFIG:-$XDG_DATA_HOME/ii-dusk/hyprland.conf}"
if [[ ! -f "$CONFIG_PATH" && -f "$XDG_DATA_HOME/ii-vynx/hyprland.conf" ]]; then
    CONFIG_PATH="$XDG_DATA_HOME/ii-vynx/hyprland.conf"
fi

die() {
    echo "[hyprset] ERROR: $*" >&2
    exit 1
}
warn() { echo "[hyprset] WARN:  $*" >&2; }

# Values are interpolated into sed expressions delimited by '|', so those
# characters plus the shell metacharacters are refused outright.
check_safe() {
    local val="$1"
    if [[ "$val" == *$'\n'* || "$val" == *$'\r'* ]]; then
        die "Newline in argument: '$val'"
    fi
    if [[ "$val" =~ [\'\"\\\`\$\|\&\;\<\>] ]]; then
        die "Unsafe characters in argument: '$val'"
    fi
}

require_file() {
    [[ -f "$CONFIG_PATH" ]] || die "Config not found: $CONFIG_PATH"
}

# Write via a temp file alongside the target so the replacement is atomic and
# never collides with a concurrent run (the old fixed /tmp path did neither).
write_back() {
    local content="$1" tmp
    tmp="$(mktemp "${CONFIG_PATH}.XXXXXX")"
    printf '%s\n' "$content" >"$tmp"
    chmod --reference="$CONFIG_PATH" "$tmp" 2>/dev/null || true
    mv "$tmp" "$CONFIG_PATH"
}

# ── Key mode ─────────────────────────────────────────────────────────────────

mode_key() {
    local key="$1" value="$2"
    check_safe "$key"
    check_safe "$value"
    require_file

    if [[ "$key" == *:* ]]; then
        local section="${key%%:*}"
        local field="${key#*:}"
        section="${section// /}"
        field="${field// /}"

        if ! grep -qE "^[[:space:]]*${section}[[:space:]]*\{" "$CONFIG_PATH"; then
            warn "Section '${section}' missing, creating new block..."
            printf '\n%s {\n    %s = %s\n}\n' "$section" "$field" "$value" >>"$CONFIG_PATH"
        else
            local replaced original
            original="$(cat "$CONFIG_PATH")"
            replaced="$(sed -E "/^[[:space:]]*${section}[[:space:]]*\{/,/^\}/ s|^([[:space:]]*${field}[[:space:]]*=[[:space:]]*).*|\1${value}|" "$CONFIG_PATH")"

            if [[ "$replaced" == "$original" ]]; then
                warn "Key '${field}' not found in '${section}', appending..."
                replaced="$(sed -E "/^[[:space:]]*${section}[[:space:]]*\{/,/^\}/ {
                    /^\}/ i\\    ${field} = ${value}
                }" "$CONFIG_PATH")"
            fi
            write_back "$replaced"
        fi
    else
        if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$CONFIG_PATH"; then
            local replaced
            replaced="$(sed -E "s|^([[:space:]]*${key}[[:space:]]*=[[:space:]]*).*|\1${value}|" "$CONFIG_PATH")"
            write_back "$replaced"
        else
            printf '%s = %s\n' "$key" "$value" >>"$CONFIG_PATH"
        fi
    fi

    echo "[hyprset] key: ${key} = ${value}"
}

# ── Anim mode ────────────────────────────────────────────────────────────────

mode_anim() {
    local anim_name="$1" params="$2"
    check_safe "$anim_name"
    check_safe "$params"
    require_file

    local head="^([[:space:]]*animation[[:space:]]*=[[:space:]]*${anim_name}[[:space:]]*,[[:space:]]*[^,]+[[:space:]]*,[[:space:]]*[^,]+[[:space:]]*,[[:space:]]*[^,]+)"

    if ! grep -qE "^[[:space:]]*animation[[:space:]]*=[[:space:]]*${anim_name}[[:space:]]*," "$CONFIG_PATH"; then
        warn "Animation '${anim_name}' missing, appending..."
        printf '\nanimation = %s, %s\n' "$anim_name" "$params" >>"$CONFIG_PATH"
        echo "[hyprset] anim: ${anim_name} appended"
        return 0
    fi

    # Callers pass the trailing style field. Hyprland makes that field optional,
    # so replace it when present and append it when it is not -- the old pattern
    # only handled the present case and silently no-opped on the common one.
    local replaced
    replaced="$(sed -E "s|${head},.*|\\1, ${params}|; t; s|${head}[[:space:]]*\$|\\1, ${params}|" "$CONFIG_PATH")"
    write_back "$replaced"

    echo "[hyprset] anim: ${anim_name} = ${params}"
}

# ── Entrypoint ───────────────────────────────────────────────────────────────

[[ $# -lt 3 ]] && die "Usage: $(basename "$0") <key|anim> <name> <value>"

case "$1" in
    key) mode_key "$2" "$3" ;;
    anim) mode_anim "$2" "$3" ;;
    *) die "Unknown mode '$1'" ;;
esac
