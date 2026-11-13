#!/usr/bin/env python3
"""Merges the colours matugen rendered into ~/.config/kdeglobals.

matugen/templates/kde/kdeglobals holds every colour set KDE apps read (View, Window, Button,
Selection, Tooltip, Complementary, Header, WM) plus the accent. KDE and Kirigami apps take their
colours from those groups, not from the Qt platform theme. kdeglobals also holds settings that are
not colours (the icon theme, fonts), so only the groups the template defines are replaced; the
rest of the file is kept as it is.

Used as the post-hook of that template: kde_colors.py [RENDERED [KDEGLOBALS]]
"""
import fcntl
import os
import re
import sys
from pathlib import Path

STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
RENDERED = Path(sys.argv[1]).expanduser() if len(sys.argv) > 1 else STATE / "quickshell/user/generated/kdeglobals"
TARGET = Path(sys.argv[2]).expanduser() if len(sys.argv) > 2 else CONFIG / "kdeglobals"

HEADER = re.compile(r"^\[(.+)\]\s*$")


def parse(text: str):
    """[(group, [lines])]: the lines before the first header belong to group None."""
    groups = [(None, [])]
    for line in text.splitlines():
        match = HEADER.match(line)
        if match:
            groups.append((match.group(1), []))
        else:
            groups[-1][1].append(line)
    return groups


def key_of(line: str):
    return line.split("=", 1)[0].strip() if "=" in line else None


def merge(current: str, rendered: str) -> str:
    new = {name: lines for name, lines in parse(rendered) if name}
    out, seen = [], set()
    for name, lines in parse(current):
        if name is None:
            out.extend(lines)
            continue
        if name in new and name != "General":
            out.append(f"[{name}]")
            out.extend(l for l in new[name] if l.strip())
            out.append("")
            seen.add(name)
        elif name == "General" and name in new:
            fresh = {key_of(l): l for l in new[name] if key_of(l)}
            kept = [l for l in lines if key_of(l) not in fresh]
            out.append("[General]")
            out.extend(l for l in kept if l.strip())
            out.extend(fresh.values())
            out.append("")
            seen.add(name)
        else:
            out.append(f"[{name}]")
            out.extend(lines)
    for name, lines in new.items():
        if name not in seen:
            if out and out[-1].strip():
                out.append("")
            out.append(f"[{name}]")
            out.extend(l for l in lines if l.strip())
            out.append("")
    text = "\n".join(out)
    return re.sub(r"\n{3,}", "\n\n", text).strip("\n") + "\n"


def main() -> int:
    if not RENDERED.is_file():
        print(f"kde_colors: nothing rendered at {RENDERED}", file=sys.stderr)
        return 1
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    with open(TARGET.parent / ".kdeglobals.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        current = TARGET.read_text() if TARGET.exists() else ""
        merged = merge(current, RENDERED.read_text())
        if merged != current:
            tmp = TARGET.with_name(TARGET.name + ".tmp")
            tmp.write_text(merged)
            os.replace(tmp, TARGET)
    return 0


if __name__ == "__main__":
    sys.exit(main())
