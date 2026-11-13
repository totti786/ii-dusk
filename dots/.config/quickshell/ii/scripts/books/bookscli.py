#!/usr/bin/env python3
"""Runs the bundled books-cli (vendor/books.pyz) and returns its one-line JSON answer.

Every source adapter (Z-Library, Library Genesis) goes through here, so the Books app has a
single dependency: the .pyz built by scripts/build-books-zipapp.sh. BOOKS_CLI_PYZ overrides it.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

PYZ = Path(os.environ.get("BOOKS_CLI_PYZ") or (Path(__file__).resolve().parents[2] / "vendor" / "books.pyz"))


class SourceError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def run(source: str, args: list[str], timeout: int, stdin_text: str | None = None) -> tuple[int, dict]:
    """Run `books.pyz <source> <args>`; secrets travel on stdin, never argv."""
    if not PYZ.is_file():
        raise SourceError("missing", f"books-cli bundle not found at {PYZ}; run scripts/build-books-zipapp.sh")
    try:
        proc = subprocess.run([sys.executable, "-I", str(PYZ), source, *args], input=stdin_text,
                              capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise SourceError("timeout", "books-cli timed out")
    except OSError as err:
        raise SourceError("missing", f"could not run books-cli: {err}")
    lines = [line for line in proc.stdout.splitlines() if line.strip()]
    try:
        data = json.loads(lines[-1]) if lines else {}
    except ValueError:
        raise SourceError(source, proc.stderr.strip() or "books-cli returned no JSON")
    if not isinstance(data, dict):
        raise SourceError(source, "books-cli returned an unexpected answer")
    return proc.returncode, data
