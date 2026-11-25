"""Store bounded orb timing statistics without retaining turn contents."""
import collections
import fcntl
import json
import os
import re
import sys
import tempfile
from pathlib import Path

LIMIT = 256
NUMBERS = ("captureMs", "transcriptionMs", "generationMs", "firstTokenMs",
           "speechStartMs", "captureToAudioMs")


def clean_record(value):
    if not isinstance(value, dict):
        return None
    at = value.get("at", "")
    if not isinstance(at, str) or not re.fullmatch(r"[0-9T:.Z+\-]{10,35}", at):
        return None
    record = {"at": at}
    for key in ("route", "model", "outcome", "input"):
        item = value.get(key, "")
        if isinstance(item, str) and re.fullmatch(r"[a-zA-Z0-9_.:/-]{1,128}", item):
            record[key] = item
    for key in NUMBERS:
        item = value.get(key)
        if type(item) in (int, float) and 0 <= item < 600000:
            record[key] = round(item)
    return record


def update(path, operation, value=None):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock_path = path.with_suffix(".lock")
    archive = path.with_suffix(".legacy-private.jsonl")
    fd = os.open(lock_path, os.O_CREAT | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if operation == "clear":
            path.unlink(missing_ok=True)
            archive.unlink(missing_ok=True)
            return
        rows = collections.deque(maxlen=LIMIT)
        legacy = False
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        except FileNotFoundError:
            pass
        else:
            with os.fdopen(fd, encoding="utf-8", errors="replace") as old:
                os.fchmod(old.fileno(), 0o600)
                for line in old:
                    try:
                        raw = json.loads(line)
                        legacy = legacy or (isinstance(raw, dict) and "text" in raw)
                        record = clean_record(raw)
                    except (ValueError, RecursionError):
                        continue
                    if record:
                        rows.append(record)
        if legacy:
            # Preserve the old diagnostic file privately until the user clears history.
            try:
                os.link(path, archive, follow_symlinks=False)
            except FileExistsError:
                pass
        if operation == "record" and (record := clean_record(value)):
            rows.append(record)
        if not rows and not path.exists():
            return
        fd, temporary = tempfile.mkstemp(prefix=".voice-timings-", dir=path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as output:
                for row in rows:
                    output.write(json.dumps(row, separators=(",", ":")) + "\n")
            os.replace(temporary, path)
        finally:
            Path(temporary).unlink(missing_ok=True)


if __name__ == "__main__":
    operation = sys.argv[1]
    if operation not in {"scrub", "record", "clear"}:
        sys.exit(2)
    update(Path(sys.argv[2]), operation, json.loads(sys.argv[3]) if operation == "record" else None)
