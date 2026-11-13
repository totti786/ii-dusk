#!/usr/bin/env python3
"""Build the Telegram Desktop theme from the shell's palette (replaces the walogram tool).

Reads ~/.cache/wal/colors.json (written by matugen's palette), derives the lighter,
darker and alpha variants the theme refers to, appends telegram/constants.tdesktop-theme (the
mapping of Telegram's colour names onto those variants) and zips it with the wallpaper as the
chat background. Output: ~/.cache/wal/wal.tdesktop-theme (walogram used ~/.cache/walogram/). Skips the work when nothing changed.

The variant scheme and the constants file are walogram's (MIT, see telegram/LICENSE-walogram).
Standard library only; Pillow is used for the background when present.
"""
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
PALETTE = CACHE / "wal" / "colors.json"
OUT_DIR = CACHE / "wal"
OUT = OUT_DIR / "wal.tdesktop-theme"
STAMP = OUT_DIR / "telegram-theme.sha"
CONSTANTS = HERE / "telegram" / "constants.tdesktop-theme"

DIVISIONS = range(10, 100, 10)
ALPHAS = [f"{n:02x}" for n in range(0, 0xef, 0x11)]  # 00 11 22 ... ee
VARIANT = re.compile(r"\bcolor(Lighter|Darker|Alpha)?(\d+)(?:_([0-9a-f]+))?\b")
VARIANT_COLORS = (0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15)  # walogram never varies colour6


def rgb(hex_color):
    h = hex_color.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def shade(base, division, lighter):
    """Same integer arithmetic as walogram's shell version."""
    step = division // 10
    out = []
    for c in rgb(base):
        delta = c * step // 10
        out.append(min(255, c + delta) if lighter else c - delta)
    return "#%02x%02x%02x" % tuple(out)


def load_palette():
    data = json.loads(PALETTE.read_text())
    colors = {i: data["colors"][f"color{i}"] for i in range(16)}
    for i in range(8):  # an unset bright colour falls back to its normal one
        colors.setdefault(i + 8, colors[i])
    return colors, str(data.get("wallpaper") or "")


def variables(colors, constants):
    """Only the colour names the constants actually use, so the file stays small."""
    wanted = set()
    for match in VARIANT.finditer(re.sub(r"//.*", "", constants)):
        wanted.add(match.group(0))
    lines = []
    for i in VARIANT_COLORS:
        base = colors[i]
        lines.append(f"color{i}: {base};")
        for d in DIVISIONS:
            for kind, light in (("Lighter", True), ("Darker", False)):
                name = f"color{kind}{i}_{d}"
                if name in wanted:
                    lines.append(f"{name}: {shade(base, d, light)};")
        for a in ALPHAS:
            name = f"colorAlpha{i}_{a}"
            if name in wanted:
                lines.append(f"{name}: {base}{a};")
    # walogram never defines colour6 although two keys (peer 6's name and userpic) point at it
    lines.append(f"color6: {colors[6]};")
    return "\n".join(lines) + "\n\n"


def background(path):
    """The wallpaper scaled to fit 1920x1080 as JPEG, or None (video, missing file).

    Pillow first; formats it cannot read (JPEG XL, AVIF, HEIC) go through ImageMagick."""
    try:
        from PIL import Image
        with Image.open(path) as im:
            im = im.convert("RGB")
            im.thumbnail((1920, 1080))
            buf = io.BytesIO()
            im.save(buf, "JPEG", quality=92)
            return buf.getvalue()
    except Exception:
        pass
    tool = shutil.which("magick") or shutil.which("convert")
    if not tool or not os.path.isfile(path):
        return None
    try:
        out = subprocess.run([tool, path + "[0]", "-auto-orient", "-resize", "1920x1080>", "-colorspace", "sRGB",
                              "-background", "black", "-alpha", "remove", "-quality", "92", "jpg:-"],
                             capture_output=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout if out.returncode == 0 and out.stdout[:2] == b"\xff\xd8" else None


def main():
    if not PALETTE.is_file() or not CONSTANTS.is_file():
        print("telegram_theme: palette or constants file missing", file=sys.stderr)
        return 1
    colors, wallpaper = load_palette()
    constants = CONSTANTS.read_text()
    theme = variables(colors, constants) + constants

    signature = hashlib.sha256(
        (theme + wallpaper + str(os.path.getmtime(wallpaper) if os.path.isfile(wallpaper) else 0)).encode()
    ).hexdigest()
    if "--force" not in sys.argv and OUT.is_file() and STAMP.is_file() and STAMP.read_text() == signature:
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tmp = OUT.with_suffix(".tmp")
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("colors.tdesktop-theme", theme)
        image = background(wallpaper) if wallpaper else None
        if image:
            z.writestr("background.jpg", image)
    os.replace(tmp, OUT)
    STAMP.write_text(signature)
    print(f"telegram theme written: {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
