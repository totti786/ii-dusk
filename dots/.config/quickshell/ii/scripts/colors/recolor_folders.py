#!/usr/bin/env python3
"""
recolor_icons.py — wallpaper-coloured folders for the base icon pack.

Local replacement for upstream's full-pack recolor. It does what the old papirus-folders
script did, without touching /usr/share/icons: it writes a small theme, DynamicTheme, that
holds only the folder and user-folder icons of the base pack in the shell's primary colour,
and inherits everything else from the base pack.

  - The base pack (appearance.iconTheme, or --base) draws its default folders in three fixed
    blues, in files named folder-blue*.svg and user-blue*.svg under <size>/places.
  - Those files are copied into DynamicTheme with the three blues swapped for the primary
    colour and two darker shades.
  - Every other name in that directory that is a symlink chain ending on one of those files
    (folder.svg, folder-documents.svg, desktop.svg, ...) is linked to the recoloured copy, so a
    lookup finds the coloured file inside DynamicTheme and never falls through to the stock blue.

The directory name, index.theme rewrite, staging swap, apply_icon_theme.sh call and the
.colhash written last are unchanged from upstream, because the shell's icon plumbing
(IconThemes.qml, TaskbarApps.qml, apply_icon_theme.sh) relies on them.

Standard library only. A base pack without blue folders (Adwaita, breeze) gives an empty
overlay, which is correct: nothing is recoloured.
"""
import configparser
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

FORCE = "--force" in sys.argv
BASE_OVERRIDE = sys.argv[sys.argv.index("--base") + 1] if "--base" in sys.argv[:-1] else ""

# Bump when the mapping changes so an unchanged colour still regenerates once.
ALGORITHM_VERSION = 4

# The three blues Papirus draws its default folders with, lightest first, and how much each
# loses per channel. Every shade starts FOLDER_DARKEN below the primary colour, so the folders
# sit a little darker than the shell's accent instead of matching it exactly.
FOLDER_DARKEN = 30
BLUES = (("5294e2", FOLDER_DARKEN), ("4877b1", FOLDER_DARKEN + 20), ("1d344f", FOLDER_DARKEN + 56))
BLUE_FILE = re.compile(r"^(folder|user)-blue.*\.svg$")

CONFIG_JSON = os.path.expanduser("~/.config/illogical-impulse/config.json")
COLORS_JSON = os.path.expanduser("~/.local/state/quickshell/user/generated/colors.json")
# RECOLOR_ICONS_TARGET and RECOLOR_ICONS_NO_APPLY exist for tests: build somewhere else, and leave
# the desktop's theme settings alone.
TARGET_THEME_PATH = os.environ.get("RECOLOR_ICONS_TARGET") or os.path.expanduser("~/.local/share/icons/DynamicTheme")
LOCK_PATH = TARGET_THEME_PATH + ".lock"
DEFAULT_BASES = ["Papirus-Dark", "Papirus-Base", "Papirus", "breeze", "Adwaita"]


def _xdg_data_dirs():
    dirs = [os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")]
    dirs += (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    dirs += ["/usr/local/share", "/usr/share"]
    seen, out = set(), []
    for d in dirs:
        d = os.path.realpath(d) if d else ""
        if d and d not in seen:
            seen.add(d)
            out.append(d)
    return out


ICON_SEARCH_DIRS = [os.path.expanduser("~/.icons")] + [os.path.join(d, "icons") for d in _xdg_data_dirs()]


def _read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None


def folder_accent():
    """The shell's primary colour as six lowercase hex digits, or None."""
    data = _read_json(COLORS_JSON)
    if isinstance(data, dict) and isinstance(data.get("colors"), dict):
        data = data["colors"]
        data = data.get("dark") or data.get("light") or data
    primary = data.get("primary") if isinstance(data, dict) else None
    if isinstance(primary, str) and re.fullmatch(r"#?[0-9A-Fa-f]{6}", primary):
        return primary.lstrip("#").lower()
    return None


def darker(hexcolor, amount):
    out = ""
    for i in (0, 2, 4):
        value = max(0, min(255, int(hexcolor[i:i + 2], 16) - amount))
        out += f"{value:02x}"
    return out


def find_base(name):
    for candidate in [name] + DEFAULT_BASES:
        if not candidate:
            continue
        for d in ICON_SEARCH_DIRS:
            path = os.path.join(d, candidate)
            if os.path.isfile(os.path.join(path, "index.theme")):
                return candidate, path
    return None, None


def read_index(path):
    parser = configparser.RawConfigParser(strict=False, interpolation=None)
    parser.optionxform = str
    parser.read(os.path.join(path, "index.theme"), encoding="utf-8")
    return parser


def places_dirs(index):
    """[(directory, section)] for every directory the base theme declares for places."""
    out = []
    if not index.has_option("Icon Theme", "Directories"):
        return out
    for d in index.get("Icon Theme", "Directories").replace(";", ",").split(","):
        d = d.strip()
        if d and index.has_section(d) and index.get(d, "Context", fallback="").lower() == "places":
            out.append((d, index[d]))
    return out


def recolor_svg(src, dst, mapping):
    with open(src, encoding="utf-8") as f:
        text = f.read()
    for old, new in mapping.items():
        text = re.sub(old, new, text, flags=re.IGNORECASE)
    with open(dst, "w", encoding="utf-8") as f:
        f.write(text)


def build_overlay(base_path, base_name, accent, staging):
    """Write the overlay theme into staging. Returns (recoloured files, linked names)."""
    mapping = {old: darker(accent, amount) for old, amount in BLUES}
    index = read_index(base_path)
    declared = places_dirs(index)

    sections = []
    recolored = linked = 0
    for rel, section in declared:
        src_dir = os.path.join(base_path, rel)
        if not os.path.isdir(src_dir):
            continue
        real_dir = os.path.realpath(src_dir)
        out_dir = os.path.join(staging, rel)
        made = {}
        for name in sorted(os.listdir(src_dir)):
            path = os.path.join(src_dir, name)
            if BLUE_FILE.match(name) and os.path.isfile(path):
                os.makedirs(out_dir, exist_ok=True)
                recolor_svg(path, os.path.join(out_dir, name), mapping)
                made[name] = True
                recolored += 1
        if not made:
            continue
        # Names that are symlink chains ending on a recoloured file, in this directory.
        for name in sorted(os.listdir(src_dir)):
            path = os.path.join(src_dir, name)
            if name in made or not name.endswith(".svg") or not os.path.islink(path):
                continue
            real = os.path.realpath(path)
            if os.path.dirname(real) != real_dir or os.path.basename(real) not in made:
                continue
            os.symlink(os.path.basename(real), os.path.join(out_dir, name))
            linked += 1
        sections.append((rel, section))

    with open(os.path.join(staging, "index.theme"), "w", encoding="utf-8") as f:
        f.write("[Icon Theme]\nName=DynamicTheme\n")
        f.write(f"Comment=Folders of {base_name} in the wallpaper colour\n")
        f.write(f"Inherits={base_name},hicolor\n")
        f.write("Directories=" + ",".join(rel for rel, _ in sections) + "\n")
        for rel, section in sections:
            f.write(f"\n[{rel}]\n")
            for key, value in section.items():
                f.write(f"{key}={value}\n")
    return recolored, linked


def fingerprint(path):
    """Cheap change marker for the base pack: its index.theme and the newest places dir mtime."""
    parts = []
    for rel in ("index.theme",):
        try:
            parts.append(str(int(os.stat(os.path.join(path, rel)).st_mtime)))
        except OSError:
            parts.append("0")
    newest = 0
    for sub in os.listdir(path):
        places = os.path.join(path, sub, "places")
        try:
            newest = max(newest, int(os.stat(places).st_mtime))
        except OSError:
            pass
    parts.append(str(newest))
    return ":".join(parts)


def generate():
    config = _read_json(CONFIG_JSON) or {}
    wanted = BASE_OVERRIDE or (config.get("appearance") or {}).get("iconTheme") or ""
    base_name, base_path = find_base(wanted)
    if not base_name:
        print("No suitable base icon theme found.")
        return
    accent = folder_accent()
    if not accent:
        print("No primary colour in colors.json; leaving the icons as they are.")
        return
    print(f"Base pack {base_name}, folder colour #{accent}")

    colors_hash = hashlib.md5(json.dumps([ALGORITHM_VERSION, accent]).encode()).hexdigest()
    base_fp = fingerprint(base_path)
    hash_file = TARGET_THEME_PATH + ".colhash"
    tag_file = TARGET_THEME_PATH + ".basetheme"
    fp_file = TARGET_THEME_PATH + ".basefp"

    def stored(path):
        try:
            with open(path) as f:
                return f.read().strip()
        except OSError:
            return ""

    if (not FORCE and os.path.isdir(TARGET_THEME_PATH) and stored(hash_file) == colors_hash
            and stored(tag_file) == base_name and stored(fp_file) == base_fp):
        print(f"Colour and base pack unchanged (hash={colors_hash[:8]}), skipping.")
        return accent

    # Built next to the live theme and renamed over it, so the shell never reads a half-written
    # directory (a half-written icon cache crashes KIconTheme).
    staging = TARGET_THEME_PATH + ".new"
    if os.path.exists(staging):
        shutil.rmtree(staging)
    os.makedirs(staging)
    recolored, linked = build_overlay(base_path, base_name, accent, staging)
    print(f"Recoloured {recolored} folder icons, linked {linked} names.")

    for tool in ("gtk4-update-icon-cache", "gtk-update-icon-cache"):
        if shutil.which(tool):
            subprocess.run([tool, "-f", "-q", "-t", staging], capture_output=True)

    old = TARGET_THEME_PATH + ".old"
    if os.path.exists(TARGET_THEME_PATH):
        if os.path.exists(old):
            shutil.rmtree(old)
        os.rename(TARGET_THEME_PATH, old)
    os.rename(staging, TARGET_THEME_PATH)
    if os.path.exists(old):
        shutil.rmtree(old)

    # Every copy of the icon theme setting must name DynamicTheme before the hash below
    # changes: the shell redraws its icons when the hash file changes.
    if not os.environ.get("RECOLOR_ICONS_NO_APPLY"):
        subprocess.run(["bash", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                             "apply_icon_theme.sh"), "DynamicTheme"],
                       capture_output=True)
    for path, value in ((hash_file, colors_hash), (tag_file, base_name), (fp_file, base_fp)):
        try:
            with open(path, "w") as f:
                f.write(value)
        except OSError:
            pass
    print("Done.")
    return accent


if __name__ == "__main__":
    os.makedirs(os.path.dirname(LOCK_PATH), exist_ok=True)
    with open(LOCK_PATH, "w") as lock_file:
        fcntl.flock(lock_file, fcntl.LOCK_EX)
        # A wallpaper switch rewrites colors.json while this can be running: if the colour moved
        # during a run, build again with the new one instead of leaving the old folders behind.
        for attempt in range(3):
            used = generate()
            if used is None or folder_accent() == used:
                break
            print(f"The primary colour changed while building (was #{used}); building again.")
