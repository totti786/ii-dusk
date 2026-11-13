#!/usr/bin/env bash
# Super+Q: close the active window, unless a full-screen shell overlay is up. Those hold the
# keyboard but the compositor still sees the bind, so it would close the app behind them.
# A windowed overlay (mediator, quran, diwan as a window) is a real window and closes normally.
set -u
OVERLAYS='^quickshell:(mediator|quran|diwan|overview|overlay|mediaMode|monitorOverlay|session|shellSwitcher|tabletAppDrawer|tabletRecents|editMode|presetLightbox|screenTime|bedtime)$'
if hyprctl layers -j | jq -e --arg re "$OVERLAYS" '[.[] | .levels[][] | .namespace | select(test($re))] | length > 0' >/dev/null; then
    exit 0
fi
# Media mode (Super+Z) has no layer to look for; the shell knows. The call has no timeout of its
# own and waits for an instance that is restarting or wedged, then answers whenever it comes
# back: the press would close whatever is focused by then. A shell that does not answer at
# once is taken as "not blocking", and the window closes now.
[ "$(timeout 0.4 qs -c "${qsConfig:-ii}" ipc call windowGuard blocked 2>/dev/null)" = "true" ] && exit 0
hyprctl dispatch 'hl.dsp.window.close()'
