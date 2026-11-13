#!/usr/bin/env python3
"""Return normalized waveform peaks for one audio file as JSON."""

from __future__ import annotations

import json
import math
import shutil
import subprocess
import sys


def duration(path: str) -> float:
    ffprobe = shutil.which("ffprobe")
    if not ffprobe:
        return 0.0
    try:
        out = subprocess.check_output([
            ffprobe, "-v", "error", "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1", path,
        ], stderr=subprocess.DEVNULL, text=True).strip()
        return max(0.0, float(out or 0.0))
    except Exception:
        return 0.0


def main() -> int:
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "error": "missing path"}))
        return 1
    path = sys.argv[1]
    buckets = max(16, min(512, int(sys.argv[2]) if len(sys.argv) > 2 else 96))
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        print(json.dumps({"ok": False, "error": "ffmpeg is not installed"}))
        return 2
    try:
        raw = subprocess.check_output([
            ffmpeg, "-v", "error", "-i", path, "-ac", "1", "-ar", "4000",
            "-f", "s16le", "-",
        ], stderr=subprocess.DEVNULL)
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        return 3

    sample_count = len(raw) // 2
    if sample_count <= 0:
        print(json.dumps({"ok": False, "error": "empty audio"}))
        return 4

    import array
    samples = array.array("h")
    samples.frombytes(raw[: sample_count * 2])
    if sys.byteorder != "little":
        samples.byteswap()

    peaks: list[float] = []
    for bucket in range(buckets):
        start = int(bucket * sample_count / buckets)
        end = int((bucket + 1) * sample_count / buckets)
        peak = 0
        for value in samples[start:end]:
            peak = max(peak, abs(int(value)))
        peaks.append(peak / 32768.0)
    strongest = max(peaks, default=0.0)
    if strongest > 0:
        peaks = [min(1.0, p / strongest) for p in peaks]
    else:
        peaks = [0.0] * buckets
    # A little perceptual lift so quiet recordings still show their shape.
    peaks = [round(math.sqrt(max(0.0, min(1.0, p))), 4) for p in peaks]
    print(json.dumps({
        "ok": True,
        "peaks": peaks,
        "duration": round(duration(path), 2),
        "buckets": buckets,
    }, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
