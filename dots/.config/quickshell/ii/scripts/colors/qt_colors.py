#!/usr/bin/env python3
"""Qt and Kvantum colours from the shell's matugen palette.

The shell's generated colors.json is the source. The Material tokens it holds are written
in the form the Kvantum scripts read, the two scripts run to recolour the MaterialAdw theme,
and the qt5ct and qt6ct colour schemes are written from the same tokens. Stdlib only.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
CACHE = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache"))
STATE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state"))

SHELL_COLORS = Path(sys.argv[1]) if len(sys.argv) > 1 else STATE / "quickshell/user/generated/colors.json"
TOKENS = CACHE / "wal" / "material_colors.sh"
KVANTUM = CONFIG / "Kvantum" / "Colloid"
QT_SCHEMES = [CONFIG / "qt5ct" / "style-colors.conf", CONFIG / "qt6ct" / "colors" / "style-colors.conf"]

# Qt's palette roles in index order (QPalette::ColorRole 0..20), each with the token it takes.
ROLES = [
    ("WindowText", "on_background"),
    ("Button", "surface_container"),
    ("Light", "surface_container_low"),
    ("Midlight", "surface_container"),
    ("Dark", "surface"),
    ("Mid", "surface_container_high"),
    ("Text", "on_background"),
    ("BrightText", "on_background"),
    ("ButtonText", "on_background"),
    ("Base", "background"),
    ("Window", "background"),
    ("Shadow", "shadow"),
    ("Highlight", "primary"),
    ("HighlightedText", "on_surface"),
    ("Link", "tertiary"),
    ("LinkVisited", "tertiary_fixed"),
    ("AlternateBase", "surface_container_low"),
    ("NoRole", "background"),
    ("ToolTipBase", "surface_container_high"),
    ("ToolTipText", "on_background"),
    ("PlaceholderText", "outline"),
]
# Disabled and inactive groups change only what the state changes.
DISABLED = {
    "WindowText": "outline", "Text": "outline", "ButtonText": "outline",
    "BrightText": "outline", "Highlight": "surface_container_highest",
}
INACTIVE = {"Highlight": "secondary_container", "HighlightedText": "on_secondary_container"}


def camel(name: str) -> str:
    head, *rest = name.split("_")
    return head + "".join(part.capitalize() for part in rest)


def load_colors() -> dict:
    raw = json.loads(SHELL_COLORS.read_text())
    return {key: value.lower() for key, value in raw.items()
            if isinstance(value, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", value)}


def load_terminal_colors() -> dict:
    # The 16 ANSI colours from the same matugen run, for the terminal keys the SVG script reads.
    raw = json.loads((CACHE / "wal" / "colors.json").read_text())["colors"]
    return {f"color{i}": raw[f"color{i}"].lower() for i in range(16)}


def write_tokens(colors: dict) -> None:
    # Kvantum's scripts read camelCase names, and one lowercase spelling it uses too.
    tokens = {}
    for key, value in colors.items():
        name = camel(key)
        tokens[name] = value
        tokens[name.lower()] = value
    ansi = load_terminal_colors()
    for index in range(16):
        tokens[f"term{index}"] = ansi[f"color{index}"]
    # The name is kept with its underscore: the SVG script reads it that way.
    tokens["neutral_paletteKeyColor"] = ansi["color4"]
    TOKENS.parent.mkdir(parents=True, exist_ok=True)
    TOKENS.write_text("".join(f'{name}="{value}"\n' for name, value in sorted(tokens.items())))


def qt_group(colors: dict, overrides: dict) -> str:
    values = []
    for role, token in ROLES:
        token = overrides.get(role, token)
        values.append("#ff" + colors[token].lstrip("#"))
    return ", ".join(values)


def write_qt_schemes(colors: dict) -> None:
    text = (
        "[ColorScheme]\n"
        f"active_colors={qt_group(colors, {})}\n"
        f"disabled_colors={qt_group(colors, DISABLED)}\n"
        f"inactive_colors={qt_group(colors, INACTIVE)}\n"
    )
    for path in QT_SCHEMES:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)


def run_kvantum() -> None:
    for script in ("changeAdwColors.py", "adwsvgDark.py"):
        subprocess.run([sys.executable, str(KVANTUM / script)], check=True)


def main() -> int:
    colors = load_colors()
    if "background" not in colors or "primary" not in colors:
        print(f"qt_colors: no palette in {SHELL_COLORS}", file=sys.stderr)
        return 1
    write_tokens(colors)
    run_kvantum()
    write_qt_schemes(colors)
    return 0


if __name__ == "__main__":
    sys.exit(main())
