#!/usr/bin/env bash
# update-fork.sh — thin wrapper around `setup-ii-dusk.sh update`.
#
# Kept for backwards compatibility with older buttons and shell history. New
# code should call `ii-dusk update` or `setup-ii-dusk.sh update`.
set -euo pipefail
SCRIPT_DIR="$(cd -P "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

# Prefer the installed copy, then this directory, then the legacy locations so
# a wrapper left behind by an older install still finds something to run.
SETUP=""
for candidate in \
    "$XDG_DATA_HOME/ii-dusk/setup-ii-dusk.sh" \
    "$SCRIPT_DIR/setup-ii-dusk.sh" \
    "$XDG_DATA_HOME/ii-vynx/setup-ii-vynx.sh" \
    "$SCRIPT_DIR/setup-ii-vynx.sh"; do
    if [ -f "$candidate" ]; then
        SETUP="$candidate"
        break
    fi
done

if [ -z "$SETUP" ]; then
    echo "✗ Could not locate setup-ii-dusk.sh" >&2
    exit 1
fi

case "$SETUP" in
    *setup-ii-vynx.sh) exec bash "$SETUP" --update --no-confirm --preserve-config "$@" ;;
    *) exec bash "$SETUP" update --yes --keep-config "$@" ;;
esac
