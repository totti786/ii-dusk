#!/usr/bin/env python3
"""
Qanun's tuner front end.

Reads mono s16 PCM from PipeWire/Pulse and prints one JSON object per analysis
window on stdout. The QML side owns note naming, transposition and the reference
pitch, so this script reports frequency, level and confidence only.

A pure-Python autocorrelation fallback keeps the tuner usable on machines
without numpy; the numpy FFT path is what normally runs.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import signal
import subprocess
import sys
import time

try:
    import numpy as np
except Exception:  # pragma: no cover - optional acceleration
    np = None


RATE = 48000
WINDOW = 8192
HOP = 2400  # ~50 ms
MIN_HZ = 45.0
MAX_HZ = 2400.0


def _capture_command() -> list[str] | None:
    if subprocess.call(["sh", "-c", "command -v parec >/dev/null 2>&1"]) == 0:
        return ["parec", "--format=s16le", "--rate=48000", "--channels=1",
                "--latency-msec=20", "--raw"]
    if subprocess.call(["sh", "-c", "command -v pw-record >/dev/null 2>&1"]) == 0:
        return ["pw-record", "--rate=48000", "--channels=1", "--format=s16",
                "--latency=20ms", "-"]
    return None


def _start_capture(command: list[str]) -> subprocess.Popen[bytes]:
    return subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            bufsize=0)


def _read_samples(proc: subprocess.Popen[bytes], count: int) -> bytes:
    chunks: list[bytes] = []
    remaining = count * 2
    while remaining > 0:
        data = proc.stdout.read(remaining) if proc.stdout else b""
        if not data:
            break
        chunks.append(data)
        remaining -= len(data)
    return b"".join(chunks)


def _note_from_bytes(data: bytes):
    if np is not None:
        return np.frombuffer(data, dtype="<i2").astype(np.float32) / 32768.0
    # array('h') is endian-dependent; decode explicitly.
    import array
    values = array.array("h")
    values.frombytes(data)
    if sys.byteorder != "little":
        values.byteswap()
    return [v / 32768.0 for v in values]


def _analyze_numpy(samples) -> tuple[float, float, float, float]:
    x = np.asarray(samples, dtype=np.float64)
    if x.size < 1024:
        return 0.0, 0.0, 0.0, 0.0
    x = x - float(np.mean(x))
    rms = float(np.sqrt(np.mean(x * x)))
    if rms < 1e-5:
        return 0.0, rms, 0.0, 0.0

    n = x.size
    window = n // 2
    min_lag = max(2, int(RATE / MAX_HZ))
    max_lag = min(n - window - 2, int(RATE / MIN_HZ))
    if max_lag <= min_lag:
        return 0.0, rms, 0.0, 0.0

    # YIN's difference function. It picks the first period rather than the
    # strongest autocorrelation lobe, so 880 Hz does not report as 440 Hz.
    difference = np.zeros(max_lag + 2, dtype=np.float64)
    for tau in range(1, max_lag + 2):
        diff = x[:window] - x[tau:tau + window]
        difference[tau] = float(np.dot(diff, diff))
    cumulative = np.ones_like(difference)
    running = 0.0
    for tau in range(1, difference.size):
        running += difference[tau]
        cumulative[tau] = difference[tau] * tau / running if running > 0 else 1.0

    threshold = 0.16
    candidates = np.flatnonzero(cumulative[min_lag:max_lag] < threshold)
    if candidates.size > 0:
        tau = min_lag + int(candidates[0])
        while tau + 1 < max_lag and cumulative[tau + 1] < cumulative[tau]:
            tau += 1
    else:
        tau = min_lag + int(np.argmin(cumulative[min_lag:max_lag]))
    if tau <= 0 or tau + 1 >= cumulative.size:
        return 0.0, rms, 0.0, 0.0
    y0, y1, y2 = float(cumulative[tau - 1]), float(cumulative[tau]), float(cumulative[tau + 1])
    # Keep numpy scalars out of the JSON writer; y1 is used for clarity below.
    denom = y0 - 2.0 * y1 + y2
    shift = 0.5 * (y0 - y2) / denom if abs(denom) > 1e-9 else 0.0
    lag = tau + max(-0.5, min(0.5, shift))
    if lag <= 0:
        return 0.0, rms, 0.0, 0.0
    freq = RATE / lag
    clarity = max(0.0, min(1.0, 1.0 - y1))
    return freq, rms, clarity, float(np.max(np.abs(np.asarray(samples))))


def _analyze_python(samples) -> tuple[float, float, float, float]:
    x = [float(v) for v in samples]
    if len(x) < 512:
        return 0.0, 0.0, 0.0, 0.0
    mean = sum(x) / len(x)
    x = [v - mean for v in x]
    rms = math.sqrt(sum(v * v for v in x) / len(x))
    if rms < 1e-5:
        return 0.0, rms, 0.0, 0.0

    # A decimated copy is enough for the fallback: it only runs on machines
    # where numpy is absent.
    step = 4
    y = x[::step]
    rate = RATE / step
    min_lag = max(2, int(rate / MAX_HZ))
    max_lag = min(len(y) - 2, int(rate / MIN_HZ))
    energy = sum(v * v for v in y)
    if energy <= 0:
        return 0.0, rms, 0.0, 0.0
    best_lag, best = 0, 0.0
    for lag in range(min_lag, max_lag):
        total = 0.0
        for i in range(0, len(y) - lag):
            total += y[i] * y[i + lag]
        score = total / energy
        if score > best:
            best, best_lag = score, lag
    if best_lag <= 0:
        return 0.0, rms, 0.0, 0.0
    freq = rate / best_lag
    return freq, rms, max(0.0, min(1.0, best)), max(abs(v) for v in x)


def _emit(freq: float, rms: float, clarity: float, peak: float) -> None:
    payload = {
        "freq": round(float(freq), 2),
        "level": round(float(rms), 5),
        "clarity": round(float(clarity), 3),
        "peak": round(float(peak), 4),
        "t": int(time.time() * 1000),
    }
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def _stream(proc: subprocess.Popen[bytes]) -> None:
    buffer = bytearray()
    while True:
        chunk = _read_samples(proc, HOP)
        if not chunk:
            break
        buffer.extend(chunk)
        if len(buffer) > WINDOW * 2:
            del buffer[: len(buffer) - WINDOW * 2]
        if len(buffer) < WINDOW * 2:
            continue
        data = bytes(buffer[-WINDOW * 2:])
        if np is not None:
            freq, rms, clarity, peak = _analyze_numpy(_note_from_bytes(data))
        else:
            freq, rms, clarity, peak = _analyze_python(_note_from_bytes(data))
        _emit(freq, rms, clarity, peak)


def _analyze_file(path: str) -> int:
    """Analyze a WAV file once, for diagnostics and tests."""
    import wave
    with wave.open(path, "rb") as wav:
        params = wav.getparams()
        raw = wav.readframes(params.nframes)
    samples = _note_from_bytes(raw[: WINDOW * 2])
    if np is not None:
        freq, rms, clarity, peak = _analyze_numpy(samples)
    else:
        freq, rms, clarity, peak = _analyze_python(samples)
    _emit(freq, rms, clarity, peak)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", help="analyze one WAV instead of capturing")
    parser.add_argument("--source", default="", help="Pulse source name (optional)")
    args = parser.parse_args()
    if args.file:
        return _analyze_file(args.file)

    command = _capture_command()
    if command is None:
        sys.stderr.write("qanun tuner: neither parec nor pw-record is installed\n")
        return 1
    if args.source:
        command = list(command)
        if command[0] == "parec":
            command[1:1] = ["--device", args.source]
        elif command[0] == "pw-record":
            command[1:1] = ["--target", args.source]

    proc = _start_capture(command)

    def stop(signum, frame):  # noqa: ARG001
        try:
            proc.terminate()
        except Exception:
            pass
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        _stream(proc)
    except BrokenPipeError:
        pass
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=1)
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
