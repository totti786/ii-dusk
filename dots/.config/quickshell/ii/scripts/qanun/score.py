#!/usr/bin/env python3
"""
Qanun's score helper.

- preview <file> [measures]  print a compact JSON excerpt of the first staff
- download <id> <path>       fetch an OpenScore String Quartets score + preview

Both MuseScore (.mscx) and compressed MusicXML (.mxl) are understood. The
preview intentionally takes only the first staff and a handful of measures:
it is a browsing thumbnail, not a notation engine.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import re
import shutil
import sys
import urllib.parse
import urllib.request
import zipfile
import xml.etree.ElementTree as ET

REPO = "OpenScore/StringQuartets"
RAW = "https://raw.githubusercontent.com/OpenScore/StringQuartets/main/scores/"
UA = {"User-Agent": "ii-qanun/1.0 (+quickshell)"}

LETTERS = ["C", "D", "E", "F", "G", "A", "B"]
SEMITONES = [0, 2, 4, 5, 7, 9, 11]
NATURAL = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
TPC = {
    0: ("C", 0), 1: ("G", 0), 2: ("D", 0), 3: ("A", 0), 4: ("E", 0), 5: ("B", 0),
    6: ("F", 1), 7: ("C", 1), 8: ("G", 1), 9: ("D", 1), 10: ("A", 1), 11: ("E", 1),
    12: ("B", 1), 13: ("F", 2),
    -1: ("F", 0), -2: ("B", -1), -3: ("E", -1), -4: ("A", -1), -5: ("D", -1),
    -6: ("G", -1), -7: ("C", -1), -8: ("F", -1), -9: ("B", -2),
}
DURATION_BEATS = {
    "long": 16.0, "breve": 8.0, "whole": 4.0, "half": 2.0, "quarter": 1.0,
    "eighth": 0.5, "16th": 0.25, "32nd": 0.125, "64th": 0.0625,
}


def _text(node, tag: str, default: str = "") -> str:
    child = node.find(tag) if node is not None else None
    return (child.text or default) if child is not None else default


def _int_text(node, tag: str, default: int = 0) -> int:
    try:
        return int(float(_text(node, tag, str(default)) or default))
    except (TypeError, ValueError):
        return default


def _key_spelling(fifths: int) -> dict[int, tuple[str, int]]:
    """Map pitch classes to letter/alter spellings in a major key."""
    # Tonic pitch class by circle of fifths.
    tonic = (fifths * 7) % 12
    semitones = [0, 2, 4, 5, 7, 9, 11]
    letters = ["C", "D", "E", "F", "G", "A", "B"]
    tonic_index = next((i for i, value in enumerate(semitones) if value == tonic), 0)
    spelling: dict[int, tuple[str, int]] = {}
    for degree in range(7):
        letter = letters[(tonic_index + degree) % 7]
        pc = (tonic + semitones[degree]) % 12
        # Pick the accidental that makes this letter land on the scale pitch.
        alter = (pc - NATURAL[letter] + 6) % 12 - 6
        if alter > 2:
            alter -= 12
        if alter < -2:
            alter += 12
        spelling[pc] = (letter, alter)
    return spelling


def _spell_midi(midi: int, fifths: int = 0) -> tuple[str, int, int]:
    pc = midi % 12
    spelling = _key_spelling(fifths)
    if pc in spelling:
        letter, alter = spelling[pc]
    else:
        letters = ["C", "D", "E", "F", "G", "A", "B"]
        options = []
        for letter in letters:
            for alter in (-1, 1, -2, 2):
                if (NATURAL[letter] + alter) % 12 == pc:
                    options.append((letter, alter))
        # Flat keys prefer flats, sharp keys sharps, C prefers sharps.
        options.sort(key=lambda pair: abs(pair[1]) * 10 + (pair[1] > 0 if fifths < 0 else pair[1] < 0))
        letter, alter = options[0] if options else ("C", 0)
    natural_midi = midi - alter
    octave = (natural_midi - NATURAL[letter]) // 12 - 1
    return letter, alter, octave


def _note_from_musescore(note, measure: int, fifths: int = 0) -> dict | None:
    pitch = _int_text(note, "pitch", -1)
    if pitch < 0:
        return None
    letter, alter, octave = _spell_midi(pitch, fifths)
    tie = note.find("Spanner[@type='Tie']")
    tied = tie is not None and tie.find("next") is not None
    return {
        "midi": pitch,
        "letter": letter,
        "alter": alter,
        "octave": octave,
        "measure": measure,
        "tie": bool(tied),
    }


def _musescore_preview(path: str, max_measures: int) -> dict:
    root = ET.parse(path).getroot()
    score = root.find("Score") if root.tag != "Score" else root
    if score is None:
        raise ValueError("not a MuseScore score")
    staff = score.find("Staff")
    if staff is None:
        raise ValueError("score has no staff")
    title = ""
    for tag in ("workTitle", "movementTitle"):
        for meta in score.findall("metaTag"):
            if meta.attrib.get("name") == tag and meta.text:
                title = meta.text.strip()
    if not title:
        for part in score.findall("Part"):
            name = _text(part, "trackName")
            if name:
                title = name
                break
    measures = staff.findall("Measure")
    key = 0
    time = [4, 4]
    clef = "treble"
    notes: list[dict] = []
    used_measures = 0
    for measure_index, measure in enumerate(measures):
        if used_measures >= max_measures:
            break
        voice = measure.find("voice")
        if voice is None:
            continue
        keysig = voice.find("KeySig/accidental")
        if keysig is not None and keysig.text and re.fullmatch(r"-?\d+", keysig.text.strip()):
            key = int(keysig.text.strip())
        sig_n = voice.find("TimeSig/sigN")
        sig_d = voice.find("TimeSig/sigD")
        if sig_n is not None and sig_d is not None:
            try:
                time = [int(sig_n.text or 4), int(sig_d.text or 4)]
            except ValueError:
                pass
        clef_node = voice.find("Clef/concertClefType")
        if clef_node is not None and clef_node.text:
            clef = "bass" if clef_node.text.strip().upper().startswith("F") else "treble"
        had_note = False
        for element in list(voice):
            if element.tag == "Chord":
                note = element.find("Note")
                if note is None:
                    continue
                parsed = _note_from_musescore(note, measure_index, key)
                if parsed is None:
                    continue
                duration_type = _text(element, "durationType", "quarter")
                duration = DURATION_BEATS.get(duration_type, 1.0)
                dots = len(element.findall("dots"))
                if dots == 0:
                    dots = len(element.findall("durationType/dots"))
                if dots:
                    duration *= 1 + (1 - 0.5 ** dots)
                parsed["duration"] = duration
                parsed["dotted"] = dots > 0
                parsed["rest"] = False
                notes.append(parsed)
                had_note = True
            elif element.tag == "Rest":
                had_note = True
                duration_type = _text(element, "durationType", "quarter")
                duration = DURATION_BEATS.get(duration_type, 1.0)
                notes.append({
                    "midi": -1, "letter": "B", "alter": 0, "octave": 4,
                    "duration": duration, "dotted": False, "rest": True,
                    "measure": measure_index, "tie": False,
                })
        if had_note:
            used_measures += 1
    return {
        "ok": True,
        "format": "musescore",
        "title": title,
        "clef": clef,
        "key": key,
        "time": time,
        "measures": used_measures,
        "notes": notes[:512],
    }


def _musicxml_preview(path: str, max_measures: int) -> dict:
    tree = ET.parse(path)
    root = tree.getroot()
    part = root.find("part")
    if part is None:
        raise ValueError("MusicXML has no part")
    title = ""
    work = root.find("work/work-title")
    if work is not None and work.text:
        title = work.text.strip()
    if not title:
        title = _text(root, "movement-title", "Untitled")
    measures = part.findall("measure")
    notes: list[dict] = []
    used_measures = 0
    divisions = 1
    key = 0
    time = [4, 4]
    clef = "treble"
    for measure_index, measure in enumerate(measures):
        if used_measures >= max_measures:
            break
        attributes = measure.find("attributes")
        if attributes is not None:
            divisions = _int_text(attributes, "divisions", divisions) or divisions
            fifths = attributes.find("key/fifths")
            if fifths is not None:
                try:
                    key = int(fifths.text or 0)
                except ValueError:
                    pass
            beats = _text(attributes, "time/beats", "")
            beat_type = _text(attributes, "time/beat-type", "")
            if beats.isdigit() and beat_type.isdigit():
                time = [int(beats), int(beat_type)]
            sign = _text(attributes, "clef/sign", "")
            if sign:
                clef = "bass" if sign.upper() == "F" else "treble"
        had_note = False
        for element in list(measure):
            if element.tag != "note":
                continue
            had_note = True
            rest = element.find("rest") is not None
            duration = _int_text(element, "duration", divisions)
            beats = max(0.0625, duration / max(1, divisions))
            if rest:
                notes.append({
                    "midi": -1, "letter": "B", "alter": 0, "octave": 4,
                    "duration": beats, "dotted": element.find("dot") is not None,
                    "rest": True, "measure": measure_index, "tie": False,
                })
                continue
            step = _text(element, "pitch/step", "C").upper()
            alter = _int_text(element, "pitch/alter", 0)
            octave = _int_text(element, "pitch/octave", 4)
            if step not in LETTERS:
                step = "C"
            midi = (octave + 1) * 12 + SEMITONES[LETTERS.index(step)] + alter
            tie = element.find("tie[@type='start']") is not None
            notes.append({
                "midi": midi, "letter": step, "alter": alter, "octave": octave,
                "duration": beats, "dotted": element.find("dot") is not None,
                "rest": False, "measure": measure_index, "tie": tie,
            })
        if had_note:
            used_measures += 1
    return {
        "ok": True,
        "format": "musicxml",
        "title": title,
        "clef": clef,
        "key": key,
        "time": time,
        "measures": used_measures,
        "notes": notes[:512],
    }


def preview(path: str, max_measures: int = 8) -> dict:
    if path.lower().endswith(".mxl"):
        with zipfile.ZipFile(path) as archive:
            xml_name = None
            try:
                container = ET.fromstring(archive.read("META-INF/container.xml"))
                for rootfile in container.iter():
                    if rootfile.tag.endswith("rootfile"):
                        xml_name = rootfile.attrib.get("full-path")
                        break
            except Exception:
                pass
            if not xml_name:
                xml_name = next((name for name in archive.namelist()
                                 if name.lower().endswith(".xml")), None)
            if not xml_name:
                raise ValueError("compressed MusicXML has no score XML")
            data = archive.read(xml_name)
        with io.BytesIO(data) as source:
            # ElementTree.parse accepts a file-like object.
            tree = ET.parse(source)
            root = tree.getroot()
            part = root.find("part")
            if part is None:
                raise ValueError("MusicXML has no part")
            # Reuse the path parser through a tiny temporary file avoided by
            # parsing here; keep the implementation above as the single source
            # of truth for MusicXML by writing the bytes to a temp path.
            import tempfile
            fd, temp_path = tempfile.mkstemp(suffix=".musicxml")
            os.close(fd)
            try:
                with open(temp_path, "wb") as handle:
                    handle.write(data)
                return _musicxml_preview(temp_path, max_measures)
            finally:
                try:
                    os.unlink(temp_path)
                except OSError:
                    pass
    return _musescore_preview(path, max_measures)


def download(score_id: str, path: str) -> dict:
    cache_dir = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
    score_dir = os.environ.get("QANUN_SCORE_DIR", os.path.expanduser("~/Documents/Qanun Scores"))
    safe_path = "/".join(urllib.parse.quote(part) for part in path.split("/"))
    url = RAW + safe_path + "/sq" + str(score_id) + ".mscx"
    composer = path.split("/")[0].replace("_", " ").strip() or "OpenScore"
    title = path.split("/")[-1].replace("_", " ").strip() or ("Score " + str(score_id))
    target_dir = os.path.join(score_dir, composer)
    os.makedirs(target_dir, exist_ok=True)
    target = os.path.join(target_dir, f"sq{score_id}.mscx")
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as response, open(target, "wb") as output:
        shutil.copyfileobj(response, output)
    data = preview(target, 8)
    data["file"] = target
    data["url"] = url
    data["id"] = str(score_id)
    data["composer"] = composer
    data["source"] = "OpenScore String Quartets (CC0)"
    preview_dir = os.path.join(cache_dir, "quickshell", "qanun", "previews")
    os.makedirs(preview_dir, exist_ok=True)
    with open(os.path.join(preview_dir, f"{score_id}.json"), "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False)
    return data


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("preview")
    p.add_argument("file")
    p.add_argument("measures", type=int, nargs="?", default=8)
    d = sub.add_parser("download")
    d.add_argument("id")
    d.add_argument("path")
    args = parser.parse_args()
    try:
        if args.command == "preview":
            result = preview(args.file, max(1, min(32, args.measures)))
        else:
            result = download(args.id, args.path)
    except Exception as exc:  # Keep errors machine-readable for QML.
        print(json.dumps({"ok": False, "error": str(exc)}))
        return 1
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
