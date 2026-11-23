# What the shell needs

Written 2026-11-21 from the code and this machine (Arch, Hyprland, Quickshell 0.3.2 dusk build). The package
names are Arch's. `check.sh` tests this whole list against the machine: `scripts/deps/check.sh`.

Method: every QML, JS, shell and Python file was scanned for imports, launched commands and font names, and each
result was resolved to its owning package with `pacman -Qo`. The command scan is heuristic (it finds names that
match installed executables), so a command only ever built into a string at run time could be missed.

## 1. Runtime

| Package | Why |
|---|---|
| quickshell-dusk-git (qs) | the shell. Needs qt6-declarative, qt6-base, qt6-svg, jemalloc, libpipewire, libxcb, wayland, libdrm, mesa, cpptrace, polkit |
| qt6-5compat | `Qt5Compat.GraphicalEffects`, 248 imports |
| qt6-multimedia + qt6-multimedia-ffmpeg | `QtMultimedia` (soundscapes, sounds, video) |
| qt6-wayland, qt6-imageformats, qt6-positioning | Wayland platform, image formats, `QtPositioning` |
| kirigami, syntax-highlighting | text editor and a few settings pages (optional) |
| hyprland | compositor; the shell talks to it through `hyprctl` and `Quickshell.Hyprland` |

QML modules imported and where they come from: `Quickshell.*` (quickshell), `Qt5Compat.GraphicalEffects`
(qt6-5compat), `QtQuick.*`, `QtTest`, `QtQml.*`, `Qt.labs.*` (qt6-declarative), `QtMultimedia` (qt6-multimedia),
`QtPositioning` (qt6-positioning), `org.kde.kirigami`, `org.kde.syntaxhighlighting` (KDE frameworks),
`MpvWallpaper` (our optional plugin, built into `~/.local/lib/qt6/qml`, absent on this machine).

## 2. Programs the shell launches

Required for the core shell: `hyprctl jq pactl wpctl playerctl nmcli bluetoothctl brightnessctl wl-copy wl-paste
grim slurp notify-send xdg-open matugen mpv ffmpeg ffprobe yt-dlp magick rsvg-convert pdftoppm cargo`.

Packages by area (all installed here unless marked absent):

- **Audio and media:** pipewire, pipewire-audio, wireplumber, libpulse, mpv, ffmpeg, flac, cava, easyeffects, songrec, gstreamer, playerctl, yt-dlp, aria2, qbittorrent-nox, syncplay, stremio-service, obs-studio, gpu-screen-recorder
- **Images and documents:** imagemagick, librsvg, resvg, libjxl, poppler, tesseract, loupe, nsxiv, zathura, gnome-epub-thumbnailer, highlight
- **Desktop:** wl-clipboard, grim, slurp, hyprpicker, wtype, ydotool, libnotify, xdg-utils, xdg-user-dirs, kconfig, xsettingsd, xorg-xrdb, fontconfig, gtk3 (gtk-launch), gtk-update-icon-cache, brightnessctl, ddcutil, v4l-utils
- **Network and devices:** networkmanager-iwd (nmcli), iw, bluez-utils, avahi, tailscale, openssh, sshfs, smbclient, android-tools (adb), scrcpy, droidcam, kdeconnect-minimal, udisks2, fuse3, fprintd, fwupd, cups
- **Secrets:** libsecret (secret-tool), gnome-keyring, bitwarden-cli, rbw
- **Theming:** matugen, pastel, kconfig, imagemagick
- **Build tools for helpers:** rust (cargo), gcc, clang, cmake, meson, ninja, make, pkgconf, go, nodejs-lts-jod, npm, pnpm
- **Tools the scripts call:** jq, ripgrep, fd, fzf, bat, inotify-tools, socat, moreutils, libarchive, acl, libcap, squashfs-tools, translate-shell, github-cli, docker, bc, perf, pacman-contrib, wget, curl, rsync, psmisc, procps-ng, util-linux
- **Not packaged by pacman, found in `~/.local/bin` or `/usr/local`:** `mediator` (built from `scripts/mediatorRs`), `ii-fand`, `localsend-cli`, `browse`, `voxtype`

**Absent on this machine (all optional, each feature reports it):** gjs (BudsLink earbuds), qalc (calculator
search), mpvpaper (video wallpaper), warp-cli, nordvpn, blueman-manager, nautilus, kdeconnect-app, hyprmon, gaze.

## 3. Rust helpers (built here by `rust-helpers.sh`)

osk_autoshow, touch_gestures, app_stats, workspace_arranger, workspace_profile_manager, sni_watcher, health_watch,
ii-quickshare, mediator-rs, ii_link. All ten are up to date. They need `cargo`, or a prebuilt release for the
source hash. `books-rs` is a separate optional binary at `vendor/books-rs`, built from the books-cli checkout.

## 4. Fonts

| Font | State | Used for |
|---|---|---|
| **Google Sans Flex** | **not installed, not bundled** | the main UI and number font (`appearance.typography`, 37 uses). The shell silently falls back to the default font |
| Material Symbols Rounded / Outlined | installed | every icon |
| JetBrainsMono Nerd Font | installed | mono text |
| Readex Pro, Space Grotesk, Amiri, Noto Kufi Arabic | installed | alternate styles, Arabic |
| Almarai, Gabarito, Rubik | not installed | Arabic body text (Nextrum, not the shell) and older styles |
| SF Pro Display, Nagasaki, Ndot57 | bundled in `assets/fonts` | island and widget faces |

## 5. Python: one environment

Everything the shell runs in Python lives in **one virtual environment**: `~/.local/state/quickshell/.venv`
(`$ILLOGICAL_IMPULSE_VIRTUAL_ENV`), Python 3.12.16 from uv, 95 packages, no access to system site-packages.
Nothing the shell ships reads a Python package from the system. It replaced six environments on 2026-11-21
(shell, voice, TTS, Quran, Anki, and an abandoned system-site experiment); they are kept in
`~/.dots-backup/venvs-20261121` until you delete them.

| File | What it is |
|---|---|
| `requirements.in` | the top-level packages, with the few deliberate pins |
| `requirements.lock` | every version, frozen from the tested environment |
| `requirements-nodeps.txt` | `openwakeword` 0.6.0, installed without dependencies (it hard-requires `tflite-runtime`, which has no 3.12 wheel and is unused with the onnx backend) |
| `bootstrap.sh` | builds the environment from the lock: `bootstrap.sh` or `bootstrap.sh --fresh` |
| `envcheck.py` | the dependency list as code: `status` (JSON), `check`, `packages`, `outdated`, `sync`, `rebuild`. Settings > About > Dependencies and `check.sh` both read it |
| `check.sh` | prints `envcheck.py check`: the whole machine against this document |
| `bin/python3`, `bin/python` | the wrapper that routes the shell's scripts into the environment (below) |

### 5.1 How a script gets the environment

`deps/bin` is first on `PATH` for the shell (`qs-guard.sh` adds it) and for Hyprland's own launches (`env.lua`).
The `python3` wrapper there decides by what is being run:

- a script inside `~/.config/quickshell`, `~/.config/hypr`, `~/.local/share/quickshell-ii`, `~/.local/state/quickshell`, inline code (`-c`) or code on stdin -> **the environment**
- any other script, or `python3 -m ...` -> **`/usr/bin/python3`**, exactly as before

So the shell's 385 `python3` call sites and its `#!/usr/bin/env python3` scripts needed no edits, and the 39 installed tools that find Python
through `env` (khal, glib-mkenums, gdbus-codegen, ...) are unaffected. Scripts that re-exec themselves into a venv (orb, wake word,
Anki, Quran, colours) read `$ILLOGICAL_IMPULSE_VIRTUAL_ENV` and nothing else.

### 5.2 Pins that are deliberate

- `materialyoucolor==2.0.10`: system 3.x flickers and disagrees with matugen.
- `anki==26.9.4`: a newer engine can upgrade a collection in place and Anki desktop then cannot open it. Raise it on purpose
  (`II_ANKI_VERSION=... scripts/anki/install_engine.sh`, and `requirements.in`).
- `opencv-contrib-python<5`, `kde-material-you-colors==1.10.1`, `material-color-utilities==0.2.1`, `pygobject==3.52.3`,
  `pycairo==1.28.0`, `dbus-python==1.4.0`: the versions the colour and Bluetooth scripts were written against.
- `numpy` and `pillow` float: opencv 4.14 supports numpy 2.5, and Pillow 13 is what the code was moved to
  (`Image.getdata` became `get_flattened_data`).

### 5.3 What is installed for what

anki, fonttools, brotli, skia-pathops (Anki, Quran glyph repair) / onnxruntime, kokoro-onnx, openwakeword, pywhispercpp, scipy,
scikit-learn, soundfile, edge-tts (voice orb) / materialyoucolor, material-color-utilities, kde-material-you-colors, libsass, opencv,
pillow, numpy (colours, images, depth) / pygobject, pycairo, dbus-python (Bluetooth agent, portals) / twisted (Syncplay) /
evdev, xkbcommon (tablet, key display) / icalendar, khal, python-dateutil, configobj (calendar) / pyte, cryptography (LocalSend) /
pyaxmlparser (phone icons) / ytmusicapi (Music) / mutagen, psutil, requests, tqdm (media, resources) /
tinytuya, obsws-python, openrgb-python (smart devices, OBS control, OpenRGB, formerly absent).

### 5.4 Still on the system Python, on purpose

Nothing of the shell's own. Only scripts that are not part of the shell (the `-m` form, other programs) use the system interpreter. `khal` the command is a pacman package with its own dependencies; the shell's calendar code imports `khal` as a
library from the environment.

### 5.5 Costs of the single environment

- 865 MB across the six old environments, 793 MB now: the saving is small, because the big packages (numpy, onnxruntime, scipy, opencv) were never duplicated much. Every script that activates it for colours sees the same package set, including
  the speech and Anki packages. Imports are lazy, so start-up is unchanged.
- One environment means one `numpy`: a package that pins an old numpy would now have to be solved against all of them. `bootstrap.sh`
  rebuilding from the lock is the way back if an update goes wrong.
- The wrapper adds one small shell start (a few milliseconds) to each `python3` call.

## 6. Still to do

1. **Google Sans Flex** is not installed and not bundled; bundle it in `assets/fonts`.
2. Delete `~/.dots-backup/venvs-20261121` once you are happy.
3. Run `scripts/deps/check.sh` after every upstream merge.

## 4. Where the lists live

Since the old `sdata/` installer tree was removed (2026-11-23), `defaults/dependencies.json` is the only package list the
fork owns. `required` features (shell tools, desktop tools, media tools, wallpaper colours, audio, session, Qt modules)
are offered by `install` and `update`; `optional` ones (fonts, visualizer, OCR, phone, ...) only through `deps`.
`install` still takes the base system from end-4's own `./setup install`, which brings its own broader package set.
The audit that decided what to keep is `SDATA-DEPS-AUDIT.md` in the repository root.
