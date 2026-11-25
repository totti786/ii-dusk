"""Save the on-disk config only if it still matches what the shell loaded."""

import json
import os
import sys
import tempfile
from pathlib import Path


def main() -> int:
    source = Path(sys.argv[1])
    backup = source.with_name(source.name + ".bak")
    expected = json.loads(sys.stdin.readline())
    try:
        original = source.read_bytes()
    except FileNotFoundError:
        return 2
    if original.decode("utf-8-sig", errors="replace") != expected:
        return 2

    fd, temporary = tempfile.mkstemp(prefix=f".{backup.name}.", dir=backup.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(original)
            stream.flush()
            os.fsync(stream.fileno())
        try:
            if source.read_bytes() != original:
                return 2
        except FileNotFoundError:
            return 2
        os.replace(temporary, backup)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except OSError:
        sys.exit(1)
