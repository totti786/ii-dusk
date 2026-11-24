#!/usr/bin/env python3
"""Resident wake-word listener for the voice orb.

The detector itself is `ii-wake`, a native Rustpotter binary at
~/.local/share/quickshell-ii/bin/ii-wake. It reads 16 kHz mono PCM from PipeWire through
pw-record and prints one JSON line per event on stdout:

  {"event": "ready", "engine": "rustpotter"}
  {"event": "wake", "word": "hey_borb", "score": 0.97}
  {"event": "error", "message": "..."}

No audio is stored or sent anywhere. The shell stops this process while a voice session
owns the microphone and starts it again afterwards.

Env: II_WAKE_WORD (model name in ~/.local/share/quickshell-ii/wake/<name>.rpw, or a path),
II_WAKE_THRESHOLD (default 0.5), II_WAKE_MIN_SCORES (default 10), II_WAKE_EAGER (1 to emit
on the minimum partial scores), II_WAKE_COOLDOWN (seconds between wakes, default 2).
"""
import os
import sys
from pathlib import Path

BINARY = Path.home() / ".local/share/quickshell-ii/bin/ii-wake"

if not BINARY.is_file():
    print('{"event":"error","message":"ii-wake binary is missing; see scripts/ai/wake_word.py"}', flush=True)
    sys.exit(1)

# Replace this interpreter with the native process: no Python stays resident.
os.execv(str(BINARY), [str(BINARY)])
