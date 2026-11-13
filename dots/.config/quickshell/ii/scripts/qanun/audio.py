#!/usr/bin/env python3
"""
Small synthesiser for Qanun's reference tones, scale playback, flashcards and
composer preview.

It writes a short 48 kHz mono WAV and hands it to the active PipeWire/Pulse
player. Long sounds stay in a child process, so killing the QML Process stops
the note without touching the shell.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import subprocess
import sys
import tempfile
import wave

RATE = 48000


def midi_to_freq(midi: float) -> float:
    return 440.0 * (2.0 ** ((float(midi) - 69.0) / 12.0))


def _player() -> list[str] | None:
    for name in ("pw-play", "paplay", "aplay"):
        if subprocess.call(["sh", "-c", f"command -v {name} >/dev/null 2>&1"]) == 0:
            if name == "aplay":
                return ["aplay", "-q"]
            return [name]
    return None


def _write_wav(samples: list[float], path: str) -> None:
    peak = max((abs(v) for v in samples), default=1.0)
    if peak > 0.98:
        samples = [v * (0.98 / peak) for v in samples]
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        frames = bytearray()
        for value in samples:
            v = int(max(-1.0, min(1.0, value)) * 32767)
            frames += int(v).to_bytes(2, "little", signed=True)
        out.writeframes(bytes(frames))


def pluck(freq: float, seconds: float, volume: float = 0.7, warmth: float = 1.0) -> list[float]:
    """A short plucked-string envelope with a few harmonics, qanun-ish."""
    count = max(1, int(seconds * RATE))
    samples: list[float] = []
    # Slight detune between the harmonics avoids an organ-like tone.
    harmonics = ((1.0, 1.0), (2.0, 0.34), (3.0, 0.17), (4.0, 0.09), (5.0, 0.045))
    attack = max(1, int(0.004 * RATE))
    for i in range(count):
        t = i / RATE
        env = math.exp(-3.2 * t) * (1.0 - math.exp(-t * 900.0))
        if i < attack:
            env *= i / attack
        # Gentle palm mute at the end instead of a click.
        tail = min(1.0, (count - i) / (0.02 * RATE))
        value = 0.0
        for mul, amp in harmonics:
            detune = 1.0 + (0.0007 * (mul - 1.0) * warmth)
            value += amp * math.sin(2.0 * math.pi * freq * mul * detune * t)
        samples.append(value * env * tail * volume * 0.5)
    return samples


def rest(seconds: float) -> list[float]:
    return [0.0] * max(1, int(seconds * RATE))


def play(samples: list[float]) -> int:
    player = _player()
    if player is None:
        sys.stderr.write("qanun audio: no pw-play, paplay or aplay found\n")
        return 1
    fd, path = tempfile.mkstemp(prefix="qanun-", suffix=".wav")
    os.close(fd)
    try:
        _write_wav(samples, path)
        proc = subprocess.Popen(player + [path], stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL)
        proc.wait()
        return proc.returncode or 0
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    tone = sub.add_parser("tone")
    tone.add_argument("freq", type=float)
    tone.add_argument("seconds", type=float, nargs="?", default=1.4)
    tone.add_argument("volume", type=float, nargs="?", default=0.7)
    tone.add_argument("--warmth", type=float, default=1.0)

    melody = sub.add_parser("melody")
    # JSON: {"bpm": 90, "notes": [{"midi": 60, "beats": 1, "rest": false}, ...]}
    melody.add_argument("json", help="path to a melody JSON file")
    melody.add_argument("--volume", type=float, default=0.72)

    chord = sub.add_parser("chord")
    chord.add_argument("freqs", help="comma-separated frequencies")
    chord.add_argument("seconds", type=float, nargs="?", default=1.8)
    chord.add_argument("volume", type=float, nargs="?", default=0.62)

    args = parser.parse_args()
    if args.command == "tone":
        return play(pluck(args.freq, max(0.05, args.seconds), max(0.0, min(1.0, args.volume)),
                          args.warmth))

    if args.command == "chord":
        freqs = []
        for part in str(args.freqs).split(","):
            try:
                value = float(part.strip())
            except ValueError:
                continue
            if value > 0:
                freqs.append(value)
        if not freqs:
            return 1
        seconds = max(0.1, args.seconds)
        count = int(seconds * RATE)
        mixed = [0.0] * count
        gain = max(0.0, min(1.0, args.volume)) / max(1, len(freqs)) * 1.6
        for index, freq in enumerate(freqs):
            tone = pluck(freq, seconds, gain, 1.15)
            for i in range(min(count, len(tone))):
                mixed[i] += tone[i]
        return play(mixed)

    with open(args.json, "r", encoding="utf-8") as handle:
        payload = json.load(handle)
    bpm = max(20.0, min(320.0, float(payload.get("bpm", 90))))
    beat_seconds = 60.0 / bpm
    samples: list[float] = []
    for note in payload.get("notes", []):
        beats = max(0.05, float(note.get("beats", 1)))
        seconds = beats * beat_seconds
        if note.get("rest"):
            samples.extend(rest(seconds))
            continue
        midi = float(note.get("midi", 60))
        samples.extend(pluck(midi_to_freq(midi), seconds, float(args.volume), 1.2))
    if not samples:
        samples = rest(0.2)
    return play(samples)


if __name__ == "__main__":
    raise SystemExit(main())
