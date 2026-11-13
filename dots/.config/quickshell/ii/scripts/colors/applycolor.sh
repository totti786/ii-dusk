#!/usr/bin/env bash
# Runs after the palette is generated. Terminals follow the palette through palette16.sh's files
# (alacritty reloads colors.toml live), so the only thing left here is OpenRGB.

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"

CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
if [ -f "$CONFIG_FILE" ]; then
  enable_openrgb=$(jq -r '.appearance.openrgb.enable' "$CONFIG_FILE")
  if [ "$enable_openrgb" = "true" ]; then
    openrgb_duration=$(jq -r '.appearance.openrgb.fadeDuration' "$CONFIG_FILE")
    # OpenRGB drives peripherals over a socket and can stall; it already only
    # runs when explicitly enabled, and is backgrounded so it never holds up the
    # rest of the theming (or, via presets.sh, the shell recolour).
    python3 "$CONFIG_DIR/scripts/colors/openRGB/apply_openrgb.py" -d $openrgb_duration & disown
  fi
fi
