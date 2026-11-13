#!/usr/bin/env python3
"""Reads 16 kHz mono s16le audio on stdin and prints one {"rms","peak"} JSON line per 50 ms.

Hex has no level feed of its own, so while it records the shell listens to the default
microphone through `parec` and feeds these frames to the same meter Voxtype's audio bridge
drives. The output matches the bridge's frames (0..1 values)."""
import array
import json
import math
import sys

CHUNK = 1600  # 50 ms of 16 kHz s16le: 800 samples
stdin = sys.stdin.buffer
while True:
    data = stdin.read(CHUNK)
    if not data:
        break
    samples = array.array("h")
    samples.frombytes(data[: len(data) - (len(data) % 2)])
    if not samples:
        continue
    peak = max(abs(s) for s in samples) / 32768
    rms = math.sqrt(sum(s * s for s in samples) / len(samples)) / 32768
    print(json.dumps({"rms": round(rms, 4), "peak": round(peak, 4)}), flush=True)
