#!/usr/bin/env python3
"""Pending package updates for the desktop widget, from a cache.

`pkgs.py updates` asks the mirrors (checkupdates) and the AUR (yay -Qua), which takes anything
from seconds to minutes, so the widget never calls it on a timer: this answers from
~/.cache/ii-packages/updates.json while that is younger than MAX_AGE, and only then asks again.

    updates_cached.py [--force]
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

CACHE = Path.home() / ".cache/ii-packages/updates.json"
MAX_AGE = 2 * 3600
PKGS = Path(__file__).resolve().parent.parent / "packages/pkgs.py"


def main():
    force = "--force" in sys.argv
    try:
        cached = json.loads(CACHE.read_text())
    except (OSError, ValueError):
        cached = None
    if cached and not force and time.time() - cached.get("checked", 0) < MAX_AGE:
        print(json.dumps(cached))
        return
    try:
        done = subprocess.run(["python3", "-I", str(PKGS), "updates"], capture_output=True, text=True, timeout=420)
        result = json.loads(done.stdout)
    except (OSError, ValueError, subprocess.TimeoutExpired) as err:
        # Keep the last good answer, flagged, rather than showing "no updates" after a failed check
        if cached:
            cached["errors"] = [str(err)]
            print(json.dumps(cached))
        else:
            print(json.dumps({"repo": [], "aur": [], "errors": [str(err)], "checked": 0}))
        return
    result["checked"] = int(time.time())
    # A check that failed outright must not overwrite a good cache with an empty list
    if result.get("errors") and not (result.get("repo") or result.get("aur")) and cached:
        cached["errors"] = result["errors"]
        print(json.dumps(cached))
        return
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    tmp = CACHE.with_suffix(".tmp")
    tmp.write_text(json.dumps(result))
    os.replace(tmp, CACHE)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
