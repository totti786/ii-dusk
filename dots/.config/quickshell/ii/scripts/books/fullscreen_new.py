#!/usr/bin/env python3
"""Launch a reader and make its window fullscreen once it maps.

Hyprland's window rule alone is dropped when the window opens while the Books overlay holds
the keyboard, so the state is set explicitly on the new window instead.

usage: fullscreen_new.py VIEWER FILE
"""
import json
import subprocess
import sys
import time

CLASSES = {"zathura": "org.pwmt.zathura", "sioyek": "sioyek"}


def clients() -> list[dict]:
    try:
        out = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=3).stdout
        return json.loads(out)
    except Exception:
        return []


def main() -> None:
    viewer, path = sys.argv[1], sys.argv[2]
    cls = CLASSES.get(viewer, viewer)
    before = {c["address"] for c in clients()}
    subprocess.Popen(["setsid", "-f", viewer, path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        for c in clients():
            if c["class"] == cls and c["address"] not in before:
                if c["fullscreen"] == 0:
                    subprocess.run(["hyprctl", "dispatch",
                                    f"hl.dsp.window.fullscreen({{ mode = 0, action = 'set', window = 'address:{c['address']}' }})"],
                                   capture_output=True, timeout=3)
                return
        time.sleep(0.05)


main()
