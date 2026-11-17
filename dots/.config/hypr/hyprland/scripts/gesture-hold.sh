#!/usr/bin/env bash
# 4-finger touchpad holds, replacing fusuma's hold.
#   quick tap (under 0.5s, not cancelled): play/pause
#   hold (0.5s or longer, not cancelled):  mute toggle
# Reads libinput debug-events, so the user needs membership in the "input" group.
# Event lines look like: "event10  GESTURE_HOLD_BEGIN  +0.732s  4" (finger count last).
stdbuf -oL libinput debug-events 2>/dev/null | awk '
  $2 == "GESTURE_HOLD_BEGIN" && $NF == 4 { start = substr($3, 2) + 0 }
  $2 == "GESTURE_HOLD_END" && $NF == 4 && $0 !~ /cancelled/ {
    dur = (substr($3, 2) + 0) - start
    if (dur > 0 && dur < 0.5) system("playerctl play-pause")
    else if (dur >= 0.5) system("wpctl set-mute @DEFAULT_SINK@ toggle")
  }'
