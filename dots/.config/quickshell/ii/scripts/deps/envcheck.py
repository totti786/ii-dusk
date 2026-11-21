#!/usr/bin/env python3
"""envcheck.py: what the shell needs, and what this machine has.

The one place that knows the dependency list. Settings > About > Dependencies reads `status`;
`check.sh` prints `check`. Standard library only, so it runs on any interpreter, including when
the shell's own environment is the thing that is broken.

  envcheck.py status           JSON: the environment, every program/package/font, a summary
  envcheck.py check [--quiet]  the same as a report; exit 1 when a REQUIRED item is missing
  envcheck.py fonts           JSON: the fonts the shell uses, whether each is installed, and where to get it
  envcheck.py outdated         JSON: environment packages with a newer release (needs the network)
  envcheck.py packages         JSON: every package in the environment with its version and pin
  envcheck.py sync             bring the environment to requirements.lock (STEP/DONE lines)
  envcheck.py rebuild          delete the environment and build it again from the lock

REQUIRED: the shell is degraded or broken without it. OPTIONAL: one feature needs it, and that
feature says so itself when it is absent. Install commands are suggestions: nothing here runs
pacman or an AUR helper.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
HOME = os.path.expanduser("~")
VENV = os.path.expanduser(os.environ.get("ILLOGICAL_IMPULSE_VIRTUAL_ENV") or "~/.local/state/quickshell/.venv")
VENV_PY = os.path.join(VENV, "bin", "python")
LOCK = os.path.join(HERE, "requirements.lock")
REQ_IN = os.path.join(HERE, "requirements.in")
NODEPS = os.path.join(HERE, "requirements-nodeps.txt")
WANT_PYTHON = "3.12"

# Environments the single one replaced. Safe to delete once nothing refers to them.
STALE_VENVS = [
    "~/.local/share/quickshell-ii/voice-venv", "~/.local/share/quickshell-ii/edge-tts-venv",
    "~/.local/state/ii-quran/venv", "~/.local/share/ii-anki-engine/venv",
    "~/.local/state/quickshell/.venv.system-3.14",
]

# (id, kind, name, package, required, feature). kind: cmd (a program on PATH), pkg (a pacman
# package), font (a family fontconfig knows). `package` is what to install, "" when unknown.
GROUPS = [
    ("qt", "Qt and Quickshell", [
        ("quickshell", "pkg", "quickshell-dusk-git", "quickshell-dusk-git", True, "The shell itself (patched Quickshell)"),
        ("qt6-declarative", "pkg", "qt6-declarative", "qt6-declarative", True, "QML runtime"),
        ("qt6-base", "pkg", "qt6-base", "qt6-base", True, "Qt"),
        ("qt6-svg", "pkg", "qt6-svg", "qt6-svg", True, "SVG icons"),
        ("qt6-5compat", "pkg", "qt6-5compat", "qt6-5compat", True, "Graphical effects (248 imports)"),
        ("qt6-multimedia", "pkg", "qt6-multimedia", "qt6-multimedia", True, "Sounds, video"),
        ("qt6-multimedia-ffmpeg", "pkg", "qt6-multimedia-ffmpeg", "qt6-multimedia-ffmpeg", True, "Media decoding"),
        ("qt6-wayland", "pkg", "qt6-wayland", "qt6-wayland", True, "Wayland platform"),
        ("qt6-imageformats", "pkg", "qt6-imageformats", "qt6-imageformats", True, "Image formats"),
        ("qt6-positioning", "pkg", "qt6-positioning", "qt6-positioning", True, "Location-aware widgets"),
        ("kirigami", "pkg", "kirigami", "kirigami", False, "Text editor, some settings pages"),
        ("syntax-highlighting", "pkg", "syntax-highlighting", "syntax-highlighting", False, "Text editor highlighting"),
    ]),
    ("core", "Desktop essentials", [
        ("hyprctl", "cmd", "hyprctl", "hyprland", True, "Compositor control"),
        ("jq", "cmd", "jq", "jq", True, "Reading settings in scripts"),
        ("pactl", "cmd", "pactl", "libpulse", True, "Audio"),
        ("wpctl", "cmd", "wpctl", "wireplumber", True, "Audio"),
        ("playerctl", "cmd", "playerctl", "playerctl", True, "Media keys"),
        ("nmcli", "cmd", "nmcli", "networkmanager", True, "Network"),
        ("bluetoothctl", "cmd", "bluetoothctl", "bluez-utils", True, "Bluetooth"),
        ("brightnessctl", "cmd", "brightnessctl", "brightnessctl", True, "Brightness"),
        ("wl-copy", "cmd", "wl-copy", "wl-clipboard", True, "Clipboard"),
        ("grim", "cmd", "grim", "grim", True, "Screenshots"),
        ("slurp", "cmd", "slurp", "slurp", True, "Region selection"),
        ("notify-send", "cmd", "notify-send", "libnotify", True, "Notifications from scripts"),
        ("xdg-open", "cmd", "xdg-open", "xdg-utils", True, "Opening files and links"),
        ("matugen", "cmd", "matugen", "matugen", True, "Colour themes"),
        ("hyprpicker", "cmd", "hyprpicker", "hyprpicker", False, "Colour picker"),
        ("ddcutil", "cmd", "ddcutil", "ddcutil", False, "External monitor brightness"),
        ("ydotool", "cmd", "ydotool", "ydotool", False, "Typing for the voice orb and dictation"),
        ("wtype", "cmd", "wtype", "wtype", False, "Typing text"),
        ("fprintd", "cmd", "fprintd-verify", "fprintd", False, "Fingerprint unlock"),
        ("udisksctl", "cmd", "udisksctl", "udisks2", False, "Removable drives"),
        ("easyeffects", "cmd", "easyeffects", "easyeffects", False, "Audio effects"),
    ]),
    ("media", "Media and files", [
        ("mpv", "cmd", "mpv", "mpv", True, "Playback everywhere"),
        ("ffmpeg", "cmd", "ffmpeg", "ffmpeg", True, "Thumbnails, conversion"),
        ("ffprobe", "cmd", "ffprobe", "ffmpeg", True, "Media info"),
        ("yt-dlp", "cmd", "yt-dlp", "yt-dlp", True, "Downloads, streaming"),
        ("magick", "cmd", "magick", "imagemagick", True, "Image conversion"),
        ("rsvg-convert", "cmd", "rsvg-convert", "librsvg", True, "SVG rendering"),
        ("pdftoppm", "cmd", "pdftoppm", "poppler", True, "PDF thumbnails"),
        ("tesseract", "cmd", "tesseract", "tesseract", False, "Text from screenshots"),
        ("cava", "cmd", "cava", "cava", False, "Audio visualiser"),
        ("songrec", "cmd", "songrec", "songrec", False, "Song recognition"),
        ("aria2c", "cmd", "aria2c", "aria2", False, "Downloads"),
        ("qbittorrent-nox", "cmd", "qbittorrent-nox", "qbittorrent-nox", False, "Torrents"),
        ("zathura", "cmd", "zathura", "zathura", False, "Reading books"),
        ("sioyek", "cmd", "sioyek", "sioyek", False, "Reading books"),
        ("syncplay", "cmd", "syncplay", "syncplay", False, "Watching together"),
        ("stremio-service", "cmd", "stremio-service", "stremio-service", False, "Mediator streaming"),
        ("obs", "cmd", "obs", "obs-studio", False, "Recording through OBS"),
        ("mpvpaper", "cmd", "mpvpaper", "mpvpaper", False, "Video wallpaper"),
        ("qalc", "cmd", "qalc", "libqalculate", False, "Calculator in search"),
        ("bsdtar", "cmd", "bsdtar", "libarchive", False, "Archives"),
    ]),
    ("devices", "Phone, network and accounts", [
        ("adb", "cmd", "adb", "android-tools", False, "Phone link"),
        ("scrcpy", "cmd", "scrcpy", "scrcpy", False, "Phone screen"),
        ("kdeconnect-cli", "cmd", "kdeconnect-cli", "kdeconnect-minimal", False, "Phone notifications and files"),
        ("kdeconnect-app", "cmd", "kdeconnect-app", "kdeconnect", False, "KDE Connect shortcut"),
        ("socat", "cmd", "socat", "socat", False, "Sockets in scripts"),
        ("sshfs", "cmd", "sshfs", "sshfs", False, "Mounting remote folders"),
        ("fusermount3", "cmd", "fusermount3", "fuse3", False, "Mounting"),
        ("tailscale", "cmd", "tailscale", "tailscale", False, "Tailscale toggle"),
        ("warp-cli", "cmd", "warp-cli", "cloudflare-warp-bin", False, "Cloudflare WARP toggle"),
        ("nordvpn", "cmd", "nordvpn", "nordvpn-bin", False, "NordVPN toggle"),
        ("secret-tool", "cmd", "secret-tool", "libsecret", False, "Saved passwords"),
        ("gjs", "cmd", "gjs", "gjs", False, "BudsLink earbuds service"),
        ("blueman-manager", "cmd", "blueman-manager", "blueman", False, "Bluetooth settings shortcut"),
        ("khal", "cmd", "khal", "khal", False, "Calendar command"),
    ]),
    ("build", "Build tools", [
        ("uv", "cmd", "uv", "uv", True, "Builds the Python environment"),
        ("cargo", "cmd", "cargo", "rust", True, "Builds the Rust helpers on this machine"),
        ("gcc", "cmd", "gcc", "gcc", False, "Compiled Python packages"),
        ("pkg-config", "cmd", "pkg-config", "pkgconf", False, "Compiled Python packages"),
        ("go", "cmd", "go", "go", False, "Discord voice helper"),
        ("node", "cmd", "node", "nodejs", False, "Anki LaTeX, search index"),
    ]),
    ("fonts", "Fonts", [
        ("font-material", "font", "Material Symbols", "", True, "Every icon in the shell"),
        ("font-jetbrains", "font", "JetBrainsMono Nerd Font", "ttf-jetbrains-mono-nerd", True, "Monospace text"),
        ("font-google-sans-flex", "font", "Google Sans Flex", "", True, "The main UI font (falls back to a default without it)"),
        ("font-readex", "font", "Readex Pro", "", False, "Alternate style"),
        ("font-space-grotesk", "font", "Space Grotesk", "", False, "Alternate style"),
        ("font-amiri", "font", "Amiri", "ttf-amiri", False, "Quran and Arabic poetry"),
        ("font-noto-sans-arabic", "font", "Noto Sans Arabic", "noto-fonts", False, "Arabic interface text (the default Arabic font)"),
        ("font-noto-kufi", "font", "Noto Kufi Arabic", "noto-fonts", False, "Arabic headings"),
    ]),
]

# Where each font can be fetched from: ("google", family) uses the Google Fonts repository,
# ("url", link) downloads a zip. Fonts with neither (the Nerd Font is 134 MB) use their package. Settings > Interface & Fonts > Install fonts reads this.
FONT_SOURCES = {
    "Material Symbols": ("google", "Material Symbols Rounded"),
    "Google Sans Flex": ("google", "Google Sans Flex"),
    "Readex Pro": ("google", "Readex Pro"),
    "Space Grotesk": ("google", "Space Grotesk"),
    "Amiri": ("google", "Amiri"),
    "Noto Sans Arabic": ("google", "Noto Sans Arabic"),
    "Noto Kufi Arabic": ("google", "Noto Kufi Arabic"),
}

# Modules the shell imports, checked inside the environment. (module, what needs it)
PY_MODULES = [
    ("PIL", "Images everywhere"), ("numpy", "Images, voice"), ("cv2", "Depth, image analysis"),
    ("materialyoucolor", "All colour themes"), ("gi", "Bluetooth agent, portals"), ("dbus", "D-Bus helpers"),
    ("mutagen", "Music tags"), ("psutil", "Resource alerts"), ("requests", "Web calls"),
    ("cryptography", "LocalSend"), ("onnxruntime", "Voice orb"), ("kokoro_onnx", "Voice orb speech"),
    ("openwakeword", "Wake word"), ("pywhispercpp", "Voice transcription"), ("scipy", "Voice, OpenRGB"),
    ("soundfile", "Voice orb"), ("edge_tts", "Voice orb fallback speech"), ("anki", "Anki app"),
    ("fontTools", "Quran glyph repair"), ("pathops", "Quran glyph repair"), ("brotli", "Quran fonts"),
    ("ytmusicapi", "Music, lyrics"), ("twisted", "Syncplay"), ("evdev", "Tablet scrolling"),
    ("xkbcommon", "Key display"), ("pyte", "LocalSend terminal"), ("icalendar", "Calendar"),
    ("khal", "Calendar"), ("dateutil", "Calendar"), ("configobj", "Calendar"),
    ("pyaxmlparser", "Phone app icons"), ("tinytuya", "Smart devices"), ("obsws_python", "OBS control"),
    ("openrgb", "OpenRGB"),
]


def run(cmd, timeout=30):
    try:
        done = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return done.returncode, done.stdout
    except (OSError, subprocess.TimeoutExpired):
        return 127, ""


def norm(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower()


def read_pins(path: str) -> dict:
    out = {}
    try:
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            m = re.match(r"([A-Za-z0-9_.\-]+)\s*==\s*([^\s;#]+)", line)
            if m:
                out[norm(m.group(1))] = m.group(2)
    except OSError:
        pass
    return out


def installed_packages() -> dict:
    code, out = run(["uv", "pip", "freeze", "--python", VENV_PY], 30)
    if code != 0:
        code, out = run([VENV_PY, "-m", "pip", "freeze"], 30)
    pins = {}
    for line in out.splitlines():
        m = re.match(r"([A-Za-z0-9_.\-]+)==(\S+)", line.strip())
        if m:
            pins[norm(m.group(1))] = m.group(2)
    return pins


def environment() -> dict:
    env = {"path": VENV, "exists": os.path.isfile(VENV_PY), "wantPython": WANT_PYTHON,
           "uv": shutil.which("uv") is not None, "wrapperOnPath": f"{os.sep}scripts{os.sep}deps{os.sep}bin" in os.environ.get("PATH", ""),
           "staleVenvs": [p for p in STALE_VENVS if os.path.isdir(os.path.expanduser(p))]}
    if not env["exists"]:
        env.update({"python": "", "isolated": False, "locked": 0, "installed": 0, "missing": [], "extra": [], "changed": [], "modules": []})
        return env
    code, out = run([VENV_PY, "-V"])
    env["python"] = out.strip().replace("Python ", "")
    try:
        env["isolated"] = "include-system-site-packages = false" in open(os.path.join(VENV, "pyvenv.cfg")).read()
    except OSError:
        env["isolated"] = False
    lock = read_pins(LOCK)
    lock.update(read_pins(NODEPS))
    have = installed_packages()
    env["locked"], env["installed"] = len(lock), len(have)
    env["missing"] = sorted(({"name": n, "lock": v} for n, v in lock.items() if n not in have), key=lambda x: x["name"])
    env["extra"] = sorted(n for n in have if n not in lock)
    env["changed"] = sorted(({"name": n, "installed": have[n], "lock": lock[n]} for n in lock if n in have and have[n] != lock[n]), key=lambda x: x["name"])
    # find_spec does not import anything, so this is fast and cannot be broken by a half-working package.
    probe = ("import importlib.util,json,sys\nprint(json.dumps({m: importlib.util.find_spec(m) is not None "
             "for m in json.loads(sys.argv[1])}))")
    code, out = run([VENV_PY, "-I", "-c", probe, json.dumps([m for m, _ in PY_MODULES])], 30)
    try:
        found = json.loads(out)
    except ValueError:
        found = {}
    env["modules"] = [{"name": m, "feature": f, "ok": bool(found.get(m))} for m, f in PY_MODULES]
    return env


def snapshot_system() -> dict:
    code, out = run(["pacman", "-Qq"], 20)
    pacman = set(out.split()) if code == 0 else None
    code, out = run(["fc-list", ":", "family"], 20)
    fonts = out.lower()
    return {"pacman": pacman, "fonts": fonts}


# Things with no working package: a command that fetches them into the user's own folders.
MANUAL_HINTS = {
    "Google Sans Flex": (
        "mkdir -p ~/.local/share/fonts/GoogleSansFlex && curl -fL -o ~/.local/share/fonts/GoogleSansFlex/GoogleSansFlex.ttf "
        "'https://raw.githubusercontent.com/google/fonts/main/ofl/googlesansflex/GoogleSansFlex%5BROND%2Copsz%2Cslnt%2Cwdth%2Cwght%5D.ttf'"
        " && fc-cache -f ~/.local/share/fonts/GoogleSansFlex"
    ),
}


def install_hint(package: str, name: str = "") -> str:
    if name in MANUAL_HINTS:
        return MANUAL_HINTS[name]
    if not package:
        return ""
    if run(["pacman", "-Si", package], 15)[0] == 0:
        return f"sudo pacman -S {package}"
    helper = next((h for h in ("paru", "yay") if shutil.which(h)), "")
    return f"{helper} -S {package}" if helper else f"{package} is in the AUR"


def status() -> dict:
    snap = snapshot_system()
    groups, req_missing, opt_missing = [], 0, 0
    for gid, title, items in GROUPS:
        out = []
        for iid, kind, name, package, required, feature in items:
            if kind == "cmd":
                ok = shutil.which(name) is not None
            elif kind == "pkg":
                ok = (name in snap["pacman"]) if snap["pacman"] is not None else shutil.which(name) is not None
            else:
                ok = name.lower() in snap["fonts"]
            hint = "" if ok else install_hint(package, name)
            if not ok:
                req_missing += 1 if required else 0
                opt_missing += 0 if required else 1
            out.append({"id": iid, "kind": kind, "name": name, "package": package, "required": required,
                        "feature": feature, "ok": ok, "install": hint,
                        "fontSource": list(FONT_SOURCES.get(name, ())) if kind == "font" else []})
        groups.append({"id": gid, "title": title, "items": out})
    env = environment()
    if not env["exists"] or not env.get("isolated", True):
        req_missing += 1
    env_issues = len(env["missing"]) + len(env["changed"]) + sum(1 for m in env["modules"] if not m["ok"])
    return {"env": env, "groups": groups,
            "summary": {"requiredMissing": req_missing, "optionalMissing": opt_missing, "environmentIssues": env_issues}}


def cmd_check(quiet: bool) -> int:
    data = status()
    env = data["env"]
    say = print
    say(f"Python environment {env['path']}")
    if not env["exists"]:
        say("  MISSING  the environment: run scripts/deps/bootstrap.sh")
    else:
        say(f"  {'ok     ' if env['python'].startswith(WANT_PYTHON) else 'WRONG  '} Python {env['python']} (want {WANT_PYTHON}.x)")
        say(f"  {'ok     ' if env['isolated'] else 'WRONG  '} {'no system site-packages' if env['isolated'] else 'can see system packages'}")
        say(f"  {'ok     ' if env['wrapperOnPath'] else 'absent '} deps/bin on PATH")
        for item in env["missing"]:
            say(f"  MISSING  package {item['name']}=={item['lock']}")
        for item in env["changed"]:
            say(f"  CHANGED  {item['name']} {item['installed']} (lock {item['lock']})")
        for item in env["extra"]:
            say(f"  extra    {item}")
        for item in env["modules"]:
            if not item["ok"]:
                say(f"  MISSING  module {item['name']} ({item['feature']})")
        say(f"  {env['installed']} installed, {env['locked']} locked")
    for path in env["staleVenvs"]:
        say(f"  stale    {path} (no longer used, safe to delete)")
    for group in data["groups"]:
        say(group["title"])
        for it in group["items"]:
            if it["ok"]:
                if not quiet:
                    say(f"  ok       {it['name']}")
            else:
                tag = "MISSING " if it["required"] else "absent  "
                tail = f"  [{it['install']}]" if it["install"] else ""
                say(f"  {tag} {it['name']} ({it['feature']}){tail}")
    helpers = os.path.join(HERE, "..", "rust-helpers.sh")
    if os.access(helpers, os.X_OK):
        say("Rust helpers")
        for line in run([helpers, "status"], 60)[1].splitlines():
            name, _, state = line.partition(" ")
            if state != "ok" or not quiet:
                say(f"  {state:<8} {name}")
    s = data["summary"]
    say(f"required missing: {s['requiredMissing']}, optional absent: {s['optionalMissing']}, environment issues: {s['environmentIssues']}")
    return 1 if s["requiredMissing"] else 0


def cmd_fonts() -> int:
    """Only the fonts, fast: just fontconfig, no pacman or environment checks."""
    code, out = run(["fc-list", ":", "family"], 20)
    have = out.lower()
    rows = []
    for gid, _title, items in GROUPS:
        if gid != "fonts":
            continue
        for iid, _kind, name, package, required, feature in items:
            source = FONT_SOURCES.get(name)
            rows.append({"id": iid, "name": name, "required": required, "feature": feature,
                         "ok": name.lower() in have, "source": list(source) if source else [],
                         "package": package})
    print(json.dumps(rows))
    return 0


def cmd_packages() -> int:
    pins = read_pins(REQ_IN)
    have = installed_packages()
    print(json.dumps([{"name": n, "version": v, "pinned": n in pins} for n, v in sorted(have.items())]))
    return 0


def cmd_outdated() -> int:
    code, out = run(["uv", "pip", "list", "--outdated", "--format", "json", "--python", VENV_PY], 120)
    try:
        rows = json.loads(out) if code == 0 else []
    except ValueError:
        rows = []
    pins = read_pins(REQ_IN)
    print(json.dumps({"ok": code == 0, "packages": [
        {"name": r.get("name", ""), "version": r.get("version", ""), "latest": r.get("latest_version", ""),
         "pinned": norm(r.get("name", "")) in pins} for r in rows]}))
    return 0


def main(argv: list) -> int:
    cmd = argv[0] if argv else "check"
    if cmd == "status":
        print(json.dumps(status()))
        return 0
    if cmd == "check":
        return cmd_check("--quiet" in argv)
    if cmd == "packages":
        return cmd_packages()
    if cmd == "fonts":
        return cmd_fonts()
    if cmd == "outdated":
        return cmd_outdated()
    if cmd in ("sync", "rebuild"):
        boot = os.path.join(HERE, "bootstrap.sh")
        os.execv("/bin/bash", ["bash", boot] + (["--fresh"] if cmd == "rebuild" else []))
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
