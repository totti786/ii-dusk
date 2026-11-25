#!/bin/sh
# Pywalfox from the shell's own Python environment, so Firefox theming does not depend on a
# system or AUR package. Used as the native-messaging host (`start`, launched by Firefox) and
# by the Firefox app theme's post-hook (`update`).
venv="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv}"
exec "$venv/bin/python" -m pywalfox "${@:-start}"
