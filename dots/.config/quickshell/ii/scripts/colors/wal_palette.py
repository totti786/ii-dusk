#!/usr/bin/env python3
"""
wal_palette.py — rewrites the 16 terminal colours in matugen's pywal-format palette.

matugen's template (matugen/templates/pywal.json) maps Material roles onto color0..color15,
which gives one hue family and dark containers for blue, magenta and cyan (2:1 contrast).
This keeps the roles that suit (background, foreground, cursor and the greys) and takes the
six accent hues from the wallpaper the way pywal does: the image's dominant colours, ranked
by Material's scorer. Each is moved to a readable tone, keeping its hue and chroma, so the
palette looks like pywal's but stays legible and follows the dark or light mode.

The "surfaces" block matugen writes beside the colours (the unretoned black and bright black,
which palette16.sh mixes into the rofi, dunst, KDE and similar backgrounds) is left untouched.

Usage: wal_palette.py [palette.json]   (default ~/.cache/wal/colors.json, rewritten in place)
Needs materialyoucolor and Pillow, so run it with the shell's venv. On any failure the file
is left as matugen wrote it.
"""
import json
import os
import sys
import tempfile

from PIL import Image
from materialyoucolor.hct import Hct
from materialyoucolor.quantize import QuantizeCelebi
from materialyoucolor.score.score import Score, ScoreOptions

PATH = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.cache/wal/colors.json")

# Accent tones: a source colour's own tone, shifted by ACCENT_SHIFT and kept inside
# [ACCENT_MIN, ACCENT_MAX] (mirrored for light mode). Bright variants sit BRIGHT_STEP further out.
ACCENT_MIN, ACCENT_MAX, ACCENT_SHIFT, BRIGHT_STEP = 52, 68, 8, 4
CHROMA_MIN = 14
# Greys (tone for dark mode; light mode uses 100 - tone): black, white, bright black, bright white.
TONE_BLACK, TONE_WHITE, TONE_BRBLACK, TONE_BRWHITE = 6, 74, 28, 80


def to_hct(hexcolor):
    return Hct.from_int(int("ff" + hexcolor.lstrip("#"), 16))


def to_hex(hue, chroma, tone):
    return "#%06x" % (Hct.from_hct(hue, chroma, max(0, min(100, tone))).to_int() & 0xFFFFFF)


def source_colors(image_path, count=6):
    image = Image.open(image_path)
    image.draft("RGB", (256, 256))  # JPEG: decode at a fraction of the size
    image = image.convert("RGB")
    image.thumbnail((128, 128))
    ranked = Score.score(QuantizeCelebi(list(image.getdata()), 128),
                         ScoreOptions(count, 0xFF4285F4, True, False))
    return ["#%06x" % (argb & 0xFFFFFF) for argb in ranked]


def refine(palette):
    colors = palette["colors"]
    dark = to_hct(palette["special"]["background"]).tone < 50
    # The scheme's own accents fill in for an image with fewer than six usable colours.
    fallback = [colors["color1"], colors["color3"], colors["color2"]]
    try:
        sources = source_colors(palette["wallpaper"])
    except Exception:
        sources = []
    while len(sources) < 6:
        sources.append(fallback[len(sources) % 3])

    for index, source in enumerate(sources[:6]):
        hct = to_hct(source)
        chroma = max(CHROMA_MIN, hct.chroma)
        if dark:
            tone = min(ACCENT_MAX, max(ACCENT_MIN, hct.tone + ACCENT_SHIFT))
            bright = min(100, tone + BRIGHT_STEP)
        else:
            tone = min(100 - ACCENT_MIN, max(100 - ACCENT_MAX, hct.tone - ACCENT_SHIFT))
            bright = max(0, tone - BRIGHT_STEP)
        colors[f"color{index + 1}"] = to_hex(hct.hue, chroma, tone)
        colors[f"color{index + 9}"] = to_hex(hct.hue, chroma, bright)

    # Greys take the hue and chroma of the scheme's own on_surface_variant (matugen's color7).
    grey = to_hct(colors["color7"])
    for slot, tone in ((0, TONE_BLACK), (7, TONE_WHITE), (8, TONE_BRBLACK), (15, TONE_BRWHITE)):
        colors[f"color{slot}"] = to_hex(grey.hue, grey.chroma, tone if dark else 100 - tone)
    return palette


def main():
    with open(PATH, encoding="utf-8") as f:
        palette = json.load(f)
    text = json.dumps(refine(palette), indent=4) + "\n"
    handle, tmp = tempfile.mkstemp(dir=os.path.dirname(PATH), prefix=".colors.", suffix=".tmp")
    with os.fdopen(handle, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, PATH)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"wal_palette: left {PATH} as matugen wrote it ({error})", file=sys.stderr)
        sys.exit(1)
