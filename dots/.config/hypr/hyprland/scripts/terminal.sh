#!/usr/bin/env bash
# The terminal the binds open: Alacritty, or kitty when Alacritty is missing.
# Arguments pass straight through; both take -e, --hold and --class.
for term in alacritty kitty; do
    command -v "$term" >/dev/null 2>&1 && exec "$term" "$@"
done
echo "terminal.sh: neither alacritty nor kitty is installed" >&2
command -v notify-send >/dev/null 2>&1 &&
    notify-send "No terminal found" "Install alacritty, or kitty as a fallback."
exit 127
