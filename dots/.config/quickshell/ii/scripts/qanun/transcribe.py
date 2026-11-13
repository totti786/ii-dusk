#!/usr/bin/env python3
"""
Qanun's audio-to-sheet-music converter.

The local pipeline is deliberately self-contained: ffmpeg decodes, yt-dlp can
fetch a link, and a small numpy pitch tracker writes a monophonic score plus a
MusicXML engraving. If Demucs is installed it is used for vocal/melody stems;
otherwise the converter falls back to a band-limited melody focus and says so
in the stage stream.

Progress is one JSON object per line so the QML side can show each stage.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unicodedata
from xml.sax.saxutils import escape

import numpy as np

RATE = 22050
FRAME = 2048
HOP = 441
MIN_HZ = 65.0
MAX_HZ = 1400.0
MAX_SECONDS = 240


def emit(stage: str, status: str, message: str = "", **extra) -> None:
    payload = {"stage": stage, "status": status, "message": message}
    payload.update(extra)
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), flush=True)


def fail(message: str, **extra) -> int:
    payload = {"ok": False, "error": message}
    payload.update(extra)
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), flush=True)
    return 1


def safe_slug(text: str) -> str:
    text = unicodedata.normalize("NFKD", text)
    text = text.encode("ascii", "ignore").decode("ascii")
    text = re.sub(r"[^a-zA-Z0-9]+", "-", text).strip("-").lower()
    return text[:60] or "converted-score"


def decode_audio(path: str, temp_dir: str) -> np.ndarray:
    out = os.path.join(temp_dir, "decoded.raw")
    command = [
        "ffmpeg", "-v", "error", "-y", "-i", path,
        "-t", str(MAX_SECONDS), "-ac", "1", "-ar", str(RATE),
        "-af", "highpass=f=70,lowpass=f=5000,afftdn=nf=-28",
        "-f", "s16le", out,
    ]
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                   timeout=240)
    raw = open(out, "rb").read()
    try:
        os.unlink(out)
    except OSError:
        pass
    if not raw:
        return np.zeros(0, dtype=np.float32)
    return np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0


def is_stereo(path: str) -> bool:
    ffprobe = shutil.which("ffprobe")
    if not ffprobe:
        return False
    try:
        out = subprocess.check_output([
            ffprobe, "-v", "error", "-select_streams", "a:0",
            "-show_entries", "stream=channels", "-of", "default=noprint_wrappers=1:nokey=1", path,
        ], stderr=subprocess.DEVNULL, text=True, timeout=20).strip()
        return int(out or 0) >= 2
    except Exception:
        return False


def isolate_stem(input_path: str, temp_dir: str) -> tuple[str, str]:
    """Return (path_to_use, status_message)."""
    demucs = shutil.which("demucs")
    if demucs:
        emit("separate", "running", "Isolating the vocal/melody stem with Demucs…")
        try:
            subprocess.run([
                demucs, "--two-stems=vocals", "-n", "htdemucs",
                "-o", temp_dir, input_path,
            ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)
            for root, _dirs, files in os.walk(temp_dir):
                for name in files:
                    if name == "vocals.wav":
                        path = os.path.join(root, name)
                        emit("separate", "done", "Vocal/melody stem isolated.")
                        return path, "Vocal/melody stem isolated with Demucs."
            return input_path, "Demucs finished but no vocal stem was found; using the mix."
        except Exception as exc:
            return input_path, f"Demucs failed ({exc}); using the mix."
    emit("separate", "skipped",
         "Demucs is not installed. Using a band-limited mono melody focus instead.")
    return input_path, "Melody focus (Demucs not installed)."


def pitch_track(samples: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    if samples.size < FRAME:
        return np.zeros(0), np.zeros(0), np.zeros(0)
    count = 1 + (samples.size - FRAME) // HOP
    midis = np.full(count, -1.0, dtype=np.float32)
    clarity = np.zeros(count, dtype=np.float32)
    levels = np.zeros(count, dtype=np.float32)
    min_lag = max(2, int(RATE / MAX_HZ))
    max_lag = min(FRAME - 2, int(RATE / MIN_HZ))

    for index in range(count):
        frame = samples[index * HOP: index * HOP + FRAME].astype(np.float64)
        frame = frame - float(np.mean(frame))
        rms = float(np.sqrt(np.mean(frame * frame)))
        levels[index] = rms
        if rms < 1e-5:
            continue

        # YIN through the autocorrelation identity:
        #   d(tau) = sum (x[j] - x[j+tau])^2
        # The cumulative mean normalized difference picks the first period,
        # not a later subharmonic.
        n = frame.size
        spectrum = np.fft.rfft(frame, 2 * n)
        correlation = np.fft.irfft(spectrum * np.conj(spectrum), 2 * n)[:n]
        prefix = np.concatenate(([0.0], np.cumsum(frame * frame)))
        total = prefix[n]
        difference = np.empty(max_lag + 2, dtype=np.float64)
        difference[0] = 0.0
        for tau in range(1, max_lag + 2):
            e0 = prefix[n - tau] - prefix[0]
            e1 = total - prefix[tau]
            difference[tau] = max(0.0, e0 + e1 - 2.0 * correlation[tau])
        cmnd = np.ones_like(difference)
        running = 0.0
        for tau in range(1, difference.size):
            running += difference[tau]
            cmnd[tau] = difference[tau] * tau / running if running > 0 else 1.0
        candidates = np.flatnonzero(cmnd[min_lag:max_lag] < 0.18)
        if candidates.size > 0:
            tau = min_lag + int(candidates[0])
            while tau + 1 < max_lag and cmnd[tau + 1] < cmnd[tau]:
                tau += 1
        else:
            tau = min_lag + int(np.argmin(cmnd[min_lag:max_lag]))
        if tau <= 0 or tau + 1 >= cmnd.size:
            continue
        y0, y1, y2 = float(cmnd[tau - 1]), float(cmnd[tau]), float(cmnd[tau + 1])
        denom = y0 - 2.0 * y1 + y2
        shift = 0.5 * (y0 - y2) / denom if abs(denom) > 1e-9 else 0.0
        lag = tau + max(-0.5, min(0.5, shift))
        freq = RATE / lag
        if freq < MIN_HZ or freq > MAX_HZ:
            continue
        clarity[index] = min(1.0, max(0.0, 1.0 - y1))
        midis[index] = 69.0 + 12.0 * math.log(max(freq, 1e-6) / 440.0, 2.0)
    return midis, clarity, levels


def smooth_midi(midis: np.ndarray, clarity: np.ndarray) -> np.ndarray:
    result = midis.copy()
    for i in range(1, len(midis) - 1):
        if midis[i] <= 0:
            continue
        neighbours = [midis[j] for j in (i - 1, i, i + 1) if midis[j] > 0]
        if neighbours:
            result[i] = sorted(neighbours)[len(neighbours) // 2]
    return result


def note_events(midis: np.ndarray, clarity: np.ndarray, levels: np.ndarray,
                bpm: float) -> list[dict]:
    if midis.size == 0:
        return []
    gate = max(0.004, float(np.percentile(levels, 28)) * 0.9)
    active = (midis > 0) & (clarity > 0.34) & (levels > gate)
    smoothed = smooth_midi(midis, clarity)
    events: list[dict] = []
    current_midi = -1
    current_start = 0
    candidate = -1
    candidate_count = 0

    def close(frame_index: int) -> None:
        nonlocal current_midi, current_start
        if current_midi < 0:
            return
        seconds = (frame_index * HOP) / RATE - current_start
        if seconds >= 0.08:
            events.append({"midi": current_midi, "start": current_start,
                           "end": current_start + seconds})
        current_midi = -1
        current_start = frame_index * HOP / RATE

    for i in range(len(smoothed)):
        if not active[i]:
            candidate = -1
            candidate_count = 0
            if current_midi >= 0:
                # A short dropout inside a note should not split it.
                if i > 0 and active[max(0, i - 2):i].any():
                    continue
                close(i)
            continue
        note = int(round(float(smoothed[i])))
        if current_midi < 0:
            current_midi = note
            current_start = i * HOP / RATE
            candidate = note
            candidate_count = 1
            continue
        if note == current_midi:
            candidate = note
            candidate_count = 0
            continue
        if note == candidate:
            candidate_count += 1
        else:
            candidate = note
            candidate_count = 1
        if candidate_count >= 3:
            close(i)
            current_midi = note
            current_start = i * HOP / RATE
            candidate_count = 0
    if current_midi >= 0:
        close(len(smoothed))

    # Merge the same pitch across very small gaps and drop very short blips.
    merged: list[dict] = []
    for event in events:
        if merged:
            previous = merged[-1]
            if event["midi"] == previous["midi"] and event["start"] - previous["end"] < 0.08:
                previous["end"] = event["end"]
                continue
        merged.append(dict(event))

    beat_seconds = 60.0 / max(20.0, min(320.0, bpm))
    notes: list[dict] = []
    previous_end = 0.0
    for event in merged[:512]:
        if event["start"] - previous_end > max(0.12, beat_seconds * 0.75):
            gap = event["start"] - previous_end
            rest_beats = max(0.25, round(gap / beat_seconds * 4) / 4)
            notes.append({"rest": True, "beats": rest_beats})
        duration = event["end"] - event["start"]
        beats = max(0.25, round(duration / beat_seconds * 4) / 4)
        midi = int(event["midi"])
        pc = midi % 12
        letters = ["C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B"]
        alter = [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0][pc]
        octave = midi // 12 - 1
        notes.append({
            "rest": False,
            "letter": letters[pc],
            "alter": alter,
            "octave": octave,
            "midi": midi,
            "beats": beats,
            "duration": beats,
            "dotted": False,
            "tie": False,
        })
        previous_end = event["end"]
    return notes


def split_duration(beats: float) -> list[float]:
    values = [4.0, 3.0, 2.0, 1.5, 1.0, 0.75, 0.5, 0.25]
    result: list[float] = []
    remaining = max(0.25, beats)
    while remaining > 0.001 and len(result) < 16:
        for value in values:
            if value <= remaining + 0.001:
                result.append(value)
                remaining = round(remaining - value, 4)
                break
        else:
            break
    return result or [0.25]


def musicxml_type(beats: float) -> tuple[str, int]:
    value = round(beats * 4) / 4
    dotted = 0
    if abs(value - 3.0) < 0.01:
        value, dotted = 2.0, 1
    elif abs(value - 1.5) < 0.01:
        value, dotted = 1.0, 1
    elif abs(value - 0.75) < 0.01:
        value, dotted = 0.5, 1
    elif abs(value - 6.0) < 0.01:
        value, dotted = 4.0, 1
    names = {4.0: "whole", 2.0: "half", 1.0: "quarter", 0.5: "eighth", 0.25: "16th"}
    return names.get(value, "quarter"), dotted


def write_musicxml(path: str, title: str, notes: list[dict], clef: str) -> None:
    divisions = 4
    parts = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">',
             '<score-partwise version="4.0">',
             f"<work><work-title>{escape(title)}</work-title></work>",
             '<identification><creator type="composer">Qanun audio conversion</creator></identification>',
             '<part-list><score-part id="P1"><part-name>Melody</part-name></score-part></part-list>',
             '<part id="P1">']
    measure: list[str] = []
    position = 0.0
    measure_number = 1

    def open_measure() -> None:
        nonlocal measure, position
        measure = []
        position = 0.0

    def close_measure() -> None:
        nonlocal measure, position, measure_number
        if not measure and position == 0:
            return
        if position < 3.999:
            missing = 4.0 - position
            for chunk in split_duration(missing):
                kind, dotted = musicxml_type(chunk)
                measure.append(f"<note><rest/><duration>{round(chunk * divisions)}</duration><voice>1</voice><type>{kind}</type>" +
                               ("<dot/>" if dotted else "") + "</note>")
        attrs = ""
        if measure_number == 1:
            sign, line = ("F", 4) if clef == "bass" else ("G", 2)
            attrs = ("<attributes><divisions>4</divisions><key><fifths>0</fifths></key>"
                     "<time><beats>4</beats><beat-type>4</beat-type></time>"
                     f"<clef><sign>{sign}</sign><line>{line}</line></clef></attributes>")
        parts.append(f'<measure number="{measure_number}">{attrs}' + "".join(measure) + "</measure>")
        measure_number += 1
        open_measure()

    open_measure()
    for note in notes:
        beats = float(note.get("beats", note.get("duration", 1)) or 1)
        if note.get("rest"):
            for chunk in split_duration(beats):
                while chunk > 0:
                    space = 4.0 - position
                    use = min(chunk, space)
                    kind, dotted = musicxml_type(use)
                    measure.append(f"<note><rest/><duration>{round(use * divisions)}</duration><voice>1</voice><type>{kind}</type>" +
                                   ("<dot/>" if dotted else "") + "</note>")
                    position += use
                    chunk -= use
                    if position >= 3.999:
                        close_measure()
            continue
        remaining = beats
        first_piece = True
        for chunk in split_duration(beats):
            if chunk <= 0:
                continue
            while chunk > 0:
                space = 4.0 - position
                use = min(chunk, space)
                kind, dotted = musicxml_type(use)
                tie_start = chunk > use + 0.001
                tie_prev = not first_piece
                pitch = (f"<pitch><step>{escape(note.get('letter', 'C'))}</step>"
                         f"<alter>{int(note.get('alter', 0))}</alter>"
                         f"<octave>{int(note.get('octave', 4))}</octave></pitch>")
                ties = ""
                if tie_start:
                    ties += '<tie type="start"/>'
                if tie_prev:
                    ties += '<tie type="stop"/>'
                notations = ""
                if tie_start or tie_prev:
                    notations = "<notations>" + ("<tied type=\"start\"/>" if tie_start else "") + ("<tied type=\"stop\"/>" if tie_prev else "") + "</notations>"
                measure.append(f"<note>{pitch}<duration>{round(use * divisions)}</duration>{ties}<voice>1</voice><type>{kind}</type>" +
                               ("<dot/>" if dotted else "") + notations + "</note>")
                position += use
                chunk -= use
                first_piece = False
                if position >= 3.999:
                    close_measure()
        remaining = 0
    close_measure()
    parts.append("</part></score-partwise>")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(parts))


def write_midi(path: str, notes: list[dict], bpm: float) -> None:
    """A compact SMF format-0 melody, useful for DAWs and notation apps."""
    import struct
    ticks_per_beat = 480
    events: list[tuple[int, bytes]] = []
    cursor = 0
    microseconds = max(20000, min(3000000, int(60_000_000 / max(20.0, bpm))))
    events.append((0, b"\xff\x51\x03" + microseconds.to_bytes(3, "big")))
    events.append((0, b"\xc0\x00"))  # acoustic grand
    for note in notes:
        beats = max(0.05, float(note.get("beats", note.get("duration", 1)) or 1))
        ticks = max(1, int(round(beats * ticks_per_beat)))
        if note.get("rest"):
            cursor += ticks
            continue
        midi = max(0, min(127, int(note.get("midi", 60))))
        events.append((cursor, bytes([0x90, midi, 92])))
        events.append((cursor + ticks, bytes([0x80, midi, 0])))
        cursor += ticks
    events.sort(key=lambda item: item[0])
    track = bytearray()
    previous = 0
    for tick, payload in events:
        delta = max(0, tick - previous)
        previous = tick
        value = delta
        buffer = [value & 0x7f]
        value >>= 7
        while value:
            buffer.append((value & 0x7f) | 0x80)
            value >>= 7
        track.extend(reversed(buffer))
        track.extend(payload)
    track.extend(b"\x00\xff\x2f\x00")
    header = b"MThd" + struct.pack(">IHHH", 6, 0, 1, ticks_per_beat)
    with open(path, "wb") as handle:
        handle.write(header)
        handle.write(b"MTrk" + struct.pack(">I", len(track)) + track)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", help="audio file")
    parser.add_argument("--url", help="audio/video URL (downloaded with yt-dlp)")
    parser.add_argument("--title", default="")
    parser.add_argument("--bpm", type=float, default=100.0)
    parser.add_argument("--out-dir", default="")
    args = parser.parse_args()
    if not args.input and not args.url:
        return fail("Choose an audio file or paste a link.")

    out_dir = args.out_dir or os.path.expanduser("~/Documents/Qanun Scores/Conversions")
    os.makedirs(out_dir, exist_ok=True)
    temp_dir = tempfile.mkdtemp(prefix="qanun-convert-")
    input_path = args.input or ""
    title = args.title.strip()
    try:
        if args.url and not input_path:
            emit("input", "running", "Downloading the audio track…")
            ytdlp = shutil.which("yt-dlp")
            if not ytdlp:
                return fail("yt-dlp is not installed, so this link cannot be downloaded.")
            template = os.path.join(temp_dir, "source.%(ext)s")
            subprocess.run([ytdlp, "-x", "--audio-format", "wav", "--no-playlist",
                            "-o", template, args.url],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                           timeout=300)
            for name in os.listdir(temp_dir):
                if name.startswith("source.") and name.endswith(".wav"):
                    input_path = os.path.join(temp_dir, name)
                    break
            if not input_path:
                return fail("The link downloaded, but no WAV audio was found.")
            if not title:
                title = "Converted audio"
        else:
            emit("input", "running", "Reading the audio file…")
            input_path = os.path.abspath(input_path)
            if not os.path.isfile(input_path):
                return fail("The selected audio file does not exist.")
            if not title:
                title = os.path.splitext(os.path.basename(input_path))[0]
        emit("input", "done", os.path.basename(input_path))

        input_path, stem_message = isolate_stem(input_path, temp_dir)
        emit("separate", "done", stem_message)

        emit("transcribe", "running", "Tracking pitch and segmenting notes…")
        samples = decode_audio(input_path, temp_dir)
        if samples.size < FRAME * 2:
            return fail("The audio is too short to transcribe.")
        midis, clarity, levels = pitch_track(samples)
        notes = note_events(midis, clarity, levels, max(20.0, min(320.0, args.bpm)))
        if not notes:
            return fail("No stable melody notes were found. Try a clearer or more melodic recording.")
        emit("transcribe", "done", f"{len(notes)} notes detected.")

        emit("engrave", "running", "Writing the score and MusicXML…")
        pitches = [n["midi"] for n in notes if not n.get("rest")]
        clef = "bass" if pitches and sorted(pitches)[len(pitches) // 2] < 60 else "treble"
        score = {
            "title": title or "Converted audio",
            "composer": "Qanun audio conversion",
            "category": "Converted",
            "region": "",
            "era": "",
            "difficulty": "Transcribed",
            "license": "User-provided audio",
            "source": args.url or input_path,
            "description": "A best-effort monophonic melody transcription. Stem isolation and transcription are approximate; review the result in the composer.",
            "clef": clef,
            "key": 0,
            "time": [4, 4],
            "tempo": int(round(max(20.0, min(320.0, args.bpm)))),
            "notes": notes,
            "kind": "converted"
        }
        slug = safe_slug(title)
        json_path = os.path.join(out_dir, slug + ".json")
        xml_path = os.path.join(out_dir, slug + ".musicxml")
        midi_path = os.path.join(out_dir, slug + ".mid")
        with open(json_path, "w", encoding="utf-8") as handle:
            json.dump(score, handle, ensure_ascii=False, indent=2)
        write_musicxml(xml_path, score["title"], notes, clef)
        write_midi(midi_path, notes, score["tempo"])
        emit("engrave", "done", os.path.basename(xml_path))
        result = {
            "ok": True,
            "title": score["title"],
            "score": score,
            "notes": notes,
            "json": json_path,
            "musicxml": xml_path,
            "midi": midi_path,
            "clef": clef,
            "tempo": score["tempo"],
            "stem": stem_message
        }
        print(json.dumps(result, ensure_ascii=False, separators=(",", ":")), flush=True)
        return 0
    except subprocess.TimeoutExpired:
        return fail("The audio command timed out. Try a shorter recording.")
    except Exception as exc:
        return fail(str(exc))
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
