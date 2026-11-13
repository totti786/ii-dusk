#!/bin/sh
# Starts the Rust file-manager backend when it is installed, the Python one otherwise.
bin="$HOME/.local/share/quickshell-ii/bin/fm-helper"
[ -x "$bin" ] && exec "$bin"
exec /usr/bin/python3 "$(dirname "$0")/fm_helper.py"
