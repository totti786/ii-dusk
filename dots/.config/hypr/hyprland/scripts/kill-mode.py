#!/usr/bin/env python3
"""Arm Hyprland's kill mode (click a window to kill it) once Escape and Super are up.

Hyprland cancels kill mode on ANY Escape event, press or release, so arming it while the
Super+Escape chord is still held gets it reset by that very key's release. This waits for
both keys to be released (read from the keyboards' evdev state), then runs `hyprctl kill`.
"""
import glob
import subprocess
import time

try:
    import evdev
    from evdev import ecodes
except ImportError:  # no evdev: fall back to a fixed wait
    evdev = None

WATCHED = {1, 125, 126}  # KEY_ESC, KEY_LEFTMETA, KEY_RIGHTMETA


def keyboards():
    found = []
    for path in glob.glob("/dev/input/event*"):
        try:
            dev = evdev.InputDevice(path)
            if 1 in dev.capabilities().get(ecodes.EV_KEY, []):
                found.append(dev)
            else:
                dev.close()
        except OSError:
            continue
    return found


def held(devs):
    for dev in devs:
        try:
            if WATCHED & set(dev.active_keys()):
                return True
        except OSError:
            continue
    return False


def main():
    if evdev is None:
        time.sleep(0.8)
    else:
        devs = keyboards()
        deadline = time.monotonic() + 3
        while held(devs) and time.monotonic() < deadline:
            time.sleep(0.01)
        time.sleep(0.06)  # let the compositor process the last release before arming
    subprocess.run(["hyprctl", "kill"], check=False)


if __name__ == "__main__":
    main()
