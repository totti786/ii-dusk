#!/usr/bin/env python3
"""Rewrites every #rrggbb in a file as three 0-1 floats, which is how sioyek takes a colour.

Used as the post-hook of matugen's sioyek template: hex_to_floats.py FILE
"""
import re
import sys
from pathlib import Path


def floats(match: re.Match) -> str:
    value = match.group(1)
    return " ".join(f"{int(value[i:i + 2], 16) / 255:.3f}" for i in (0, 2, 4))


path = Path(sys.argv[1]).expanduser()
text = path.read_text()
path.write_text(re.sub(r"#([0-9a-fA-F]{6})\b", floats, text))
