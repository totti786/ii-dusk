#!/usr/bin/env python3
"""Runs books-rs (the Rust books-cli) and returns its one-line JSON answer.

Every source adapter (Z-Library, Library Genesis) goes through here, so the Books app has a
single dependency, and ii-dusk does not ship it: vendor/books-rs, built from your own books-cli
checkout by scripts/build-books-rs.sh. BOOKS_RS_BIN overrides the path.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

_VENDOR = Path(__file__).resolve().parents[2] / "vendor"
RS = Path(os.environ.get("BOOKS_RS_BIN") or (_VENDOR / "books-rs"))


class SourceError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def run(source: str, args: list[str], timeout: int, stdin_text: str | None = None) -> tuple[int, dict]:
    """Run `books-rs <source> <args>`; secrets travel on stdin, never argv."""
    if not (RS.is_file() and os.access(RS, os.X_OK)):
        raise SourceError("missing", f"The Books app needs books-cli, which ii-dusk does not ship. Build it from your own checkout with scripts/build-books-rs.sh <checkout>. Looked for {RS}")
    command = [str(RS), source, *args]
    try:
        proc = subprocess.run(command, input=stdin_text, capture_output=True, text=True, timeout=timeout)
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
