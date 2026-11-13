#!/usr/bin/env python3
"""Generate the small metronome click set used by the Qanun app."""

from __future__ import annotations

import math
import os
import random
import wave

RATE = 48000
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))), "modules", "ii", "qanun", "assets", "audio")


def write(name: str, samples: list[float]) -> None:
    os.makedirs(OUT, exist_ok=True)
    peak = max((abs(v) for v in samples), default=1.0) or 1.0
    scale = 0.92 / peak if peak > 0.92 else 1.0
    with wave.open(os.path.join(OUT, name), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        frames = bytearray()
        for value in samples:
            v = int(max(-1.0, min(1.0, value * scale)) * 32767)
            frames += int(v).to_bytes(2, "little", signed=True)
        out.writeframes(bytes(frames))


def ping(freq: float, seconds: float, decay: float, gain: float = 0.8,
         noise: float = 0.0) -> list[float]:
    count = int(seconds * RATE)
    result = []
    rng = random.Random(int(freq))
    for i in range(count):
        t = i / RATE
        env = math.exp(-decay * t) * min(1.0, t / 0.0015)
        value = math.sin(2 * math.pi * freq * t) * 0.75
        value += math.sin(2 * math.pi * freq * 2.01 * t) * 0.2
        if noise:
            value += rng.uniform(-1, 1) * noise * math.exp(-decay * 5 * t)
        result.append(value * env * gain)
    return result


def wood(freq: float, seconds: float, gain: float = 0.8) -> list[float]:
    count = int(seconds * RATE)
    result = []
    rng = random.Random(42)
    for i in range(count):
        t = i / RATE
        env = math.exp(-45 * t) * min(1.0, t / 0.0008)
        value = math.sin(2 * math.pi * freq * t) * 0.6
        value += math.sin(2 * math.pi * (freq * 2.73) * t) * 0.3
        value += rng.uniform(-1, 1) * 0.35 * math.exp(-120 * t)
        result.append(value * env * gain)
    return result


for pack, accent_f, beat_f, sub_f in (
    ("click", 1760, 1320, 990),
    ("wood", 680, 520, 430),
    ("beep", 1320, 880, 660),
):
    if pack == "wood":
        write(f"{pack}-accent.wav", wood(accent_f, 0.055, 0.85))
        write(f"{pack}-beat.wav", wood(beat_f, 0.048, 0.8))
        write(f"{pack}-sub.wav", wood(sub_f, 0.038, 0.55))
    else:
        write(f"{pack}-accent.wav", ping(accent_f, 0.075, 55, 0.9, 0.08))
        write(f"{pack}-beat.wav", ping(beat_f, 0.06, 65, 0.8, 0.05))
        write(f"{pack}-sub.wav", ping(sub_f, 0.045, 85, 0.42, 0.02))

print("Wrote click packs to", OUT)
