# sdata dependency audit

Written 2026-11-23, before removing `sdata/`. Not committed.

**Scope.** All 123 package entries (121 unique) named in `sdata/dist-arch/illogical-impulse-*/PKGBUILD` `depends=` (15 groups). The Fedora,
Gentoo and Nix lists under `sdata/` are ports of this same list, so they add nothing new.

**Method.** Every package was checked three ways:
1. Is it installed on this machine (`pacman -Q`)?
2. Does the code under `dots/` call its executables or import its modules? `ripgrep -uuu`, whole-word, with
   docs, tests, translations, JSON and `.qsb` files excluded.
3. Does `setup-ii-dusk.sh` or `defaults/dependencies.json` already cover it?

Counts are files that mention the thing. Unused here means no hit in `dots/` or `setup-ii-dusk.sh`. Packages that
were not installed were searched by their executable or module name instead. Weak spots: short names (`jq`,
`bc`) and things called through a daemon or library are judged by hand and marked.

**Verdicts.**
- **CORE**: the shell or Hyprland config breaks without it.
- **FEATURE**: one feature needs it, and the code copes when it is missing.
- **BUILD**: only needed to compile something (Quickshell, MicroTeX, a helper).
- **DROP**: nothing in this fork uses it.

## 0. What the fork really uses from sdata

`setup-ii-dusk.sh` does not use `sdata/`'s installer. It clones end-4's own `./setup install` for the base (line ~3260),
so none of `setup`, `subcmd-*`, `dist-*/install-deps.sh` or the PKGBUILDs ever run from this repo.

Only these touch the fork:

| File | Used by | Action before deleting `sdata/` |
|---|---|---|
| `sdata/cli/lib/hyprset.sh`, `hyprmerge.sh` | `setup-ii-dusk.sh` lines 3753-3758 (`ii-dusk hyprset`/`hyprmerge`) | move to e.g. `setup/lib/` and fix the lookup path |
| `setup-ii-dusk.sh:2751-2754` | copies `sdata/` into the mirror dir | change to copy the new helper dir (or nothing) |
| `.github/workflows/dist-update-notification.yml` | triggers on `sdata/dist-arch/**` | delete the workflow |
| `.github/CONTRIBUTING.md:56` | points at `sdata/uv/README.md` | repoint to `scripts/deps/DEPENDENCIES.md` |
| `setup` (repo root script) | sources `sdata/lib/*` and dispatches `sdata/subcmd-*` | delete with sdata (nothing calls it) |

Everything else (`dist-arch/dist-fedora/dist-gentoo/dist-nix`, `subcmd-*`, `lib/*`, `deps-info.md`, `uv/shell.nix`,
`subcmd-virtmon/hypr_mon_guard`) has no caller in this fork. `sdata/uv/` is only the `--via-nix` shell for a Python
bootstrap the fork replaced with `scripts/deps/bootstrap.sh`.

## 1. Package verdicts

Legend: `inst` is installed on this machine. `dep.json` means already in `defaults/dependencies.json`.
**Gap** marks a package the shell needs that no fork-owned list covers once end-4's base installer is the only source.

### illogical-impulse-audio
| Package | inst | Evidence | Verdict |
|---|---|---|---|
| cava | yes | 12 files (visualizer) | FEATURE |
| pavucontrol-qt | no | only a fallback after the built-in mixer (`variables.lua`, 1 float rule) | DROP |
| wireplumber | yes | `wpctl` in 10 files | CORE |
| pipewire-pulse | yes | provides the `pactl` server the shell uses (23 files) | CORE |
| libdbusmenu-gtk3 | yes | 0 hits | DROP |
| playerctl | yes | 8 files, plus `playerctld` | CORE |

### illogical-impulse-backlight
| Package | inst | Evidence | Verdict |
|---|---|---|---|
| geoclue | no | `start_geoclue_agent.sh` in execs.lua; Weather.qml says the service stalls the shell | FEATURE (location) |
| brightnessctl | yes | 9 files | CORE |
| ddcutil | yes | 6 files (external monitors) | FEATURE |

### illogical-impulse-basic
| Package | inst | Evidence | Verdict |
|---|---|---|---|
| bc | yes | 25 files | CORE |
| coreutils | yes | base system | CORE (base) |
| cliphist | yes | 22 files | CORE |
| cmake | yes | build only (Quickshell, helpers; `setup-ii-dusk.sh` 11 mentions) | BUILD |
| curl | yes | 59 files | CORE |
| wget | yes | 6 files | FEATURE |
| ripgrep | yes | `rg` in 19 files | CORE |
| jq | yes | 50 files | CORE |
| xdg-user-dirs | yes | `xdg-user-dir` 6 files | CORE |
| rsync | yes | no use in `dots/`; the fork installer only mentions it in comments | DROP (`unknown`, end-4's installer used it) |
| go-yq | no | 0 real hits (only matches inside binary files); used by end-4's installer | DROP |
| yt-dlp | yes | 27 files (Downloads, mediator) | CORE |
| ffmpeg | yes | `ffmpeg`/`ffprobe` 35+14 files | CORE |
| aria2 | yes | `aria2c` 8 files | FEATURE (Downloads) |

### illogical-impulse-fonts-themes
| Package | inst | Evidence | Verdict |
|---|---|---|---|
| adw-gtk-theme-git | no | **Reversed 2026-11-23:** adw-gtk3 is the GTK theme now (matugen writes its `gtk.css`); the repo package `adw-gtk-theme` is in dependencies.json | CORE |
| breeze | no | `kdeglobals` names `Theme=breeze-dark`, only as a fallback icon theme | DROP |
| breeze-plus | no | 0 hits (Papirus is the base icon pack) | DROP |
| darkly-bin | no | 0 hits | DROP |
| eza | yes | 1 file (alias) | DROP |
| fish | no | only the word in comments and file extensions; terminal is alacritty | DROP |
| fontconfig | yes | `fc-list`/`fc-match`/`fc-cache` | CORE |
| kitty | no | 51 mentions are theme writers; `terminal = "alacritty"` in variables.lua | DROP (or FEATURE if the kitty theme writer stays) |
| matugen | yes | 44 files | CORE (dep.json: no, **Gap**) |
| otf-space-grotesk | yes | 21 files | CORE (font) |
| starship | no | 1 comment | DROP |
| ttf-jetbrains-mono-nerd | yes | 19 files | CORE (font) |
| ttf-material-symbols-variable-git | yes | 41 files | CORE (font) |
| ttf-readex-pro | yes | 21 files | CORE (font) |
| ttf-rubik-vf | no | a font fallback list only | DROP |
| ttf-twemoji | yes | 0 hits | DROP |

### illogical-impulse-hyprland
| Package | inst | Evidence | Verdict |
|---|---|---|---|
| hyprland | yes | everywhere | CORE |
| hyprsunset | yes | 2 files (night light) | FEATURE |
| hyprmon-bin | no | 21 mentions; dep.json `monitor-profiles` | FEATURE (already dep.json) |
| wl-clipboard | yes | `wl-copy` 49, `wl-paste` 16 | CORE |

### illogical-impulse-kde
| Package | inst | Evidence | Verdict |
|---|---|---|---|
| bluedevil | no | 0 hits (shell has its own Bluetooth UI) | DROP |
| gnome-keyring | yes | started in execs.lua; secrets (books, AI keys) | CORE |
| networkmanager | yes | `nmcli` 34 files | CORE |
| plasma-nm | no | 0 hits | DROP |
| polkit-kde-agent | no | only an ignore-list string; Quickshell has its own polkit agent | DROP |
| dolphin | no | file manager is `ii-files` | DROP |
| systemsettings | no | only a fallback after the shell's own settings | DROP |

### illogical-impulse-microtex-git
All four are build dependencies for MicroTeX only. `LatexRenderer.qml` expects `/opt/MicroTeX`, which is absent here,
so LaTeX in the AI chat does not render on this machine.

| Package | inst | Verdict |
|---|---|---|
| tinyxml2, gtkmm3, cairomm, gtksourceviewmm | yes/yes/yes/no | BUILD, only if LaTeX rendering is wanted; otherwise DROP the whole group |

### illogical-impulse-phone
| Package | inst | Evidence | Verdict |
|---|---|---|---|
| kdeconnect | yes (we run kdeconnect-minimal) | `kdeconnect-cli` 20 files | FEATURE (dep.json) |
| scrcpy | yes | 71 files | FEATURE (dep.json) |
| android-tools | yes | `adb` 32 files | FEATURE (dep.json) |
| pulseaudio-utils | no | wrong name on Arch: `pactl` comes from libpulse | DROP (name only) |
| v4l-utils | yes | `v4l2-ctl` 21 files | FEATURE (**Gap**: dep.json lists only v4l2loopback) |
| python-dbus | yes | dep.json required | CORE |
| python-gobject | yes | dep.json required | CORE |
| python-pyaxmlparser | no | dep.json `phone` | FEATURE |
| python-pillow | yes | dep.json required | CORE |
| libnotify | yes | `notify-send` 87 files | CORE (**Gap**) |

### illogical-impulse-portal
| Package | inst | Evidence | Verdict |
|---|---|---|---|
| xdg-desktop-portal | yes | file pickers, screen share | CORE |
| xdg-desktop-portal-kde | no | 0 hits | DROP |
| xdg-desktop-portal-gtk | yes | file chooser | CORE |
| xdg-desktop-portal-hyprland | yes | screen share | CORE |

### illogical-impulse-python
These are for end-4's GTK4 Python tools. `bootstrap.sh` makes its own venv with `uv`.

| Package | inst | Evidence | Verdict |
|---|---|---|---|
| uv | yes | `scripts/deps/bootstrap.sh` | CORE (**Gap**: bootstrap prerequisite) |
| clang | yes | eBPF net helper build (`app_stats`) | BUILD (FEATURE) |
| gtk4, libadwaita, libsoup3, libportal-gtk4, gobject-introspection | yes/yes/yes/no/no | no `Gtk 4.0` or Adw imports in the fork's Python | DROP |

### illogical-impulse-quickshell-git
| Package | inst | Evidence | Verdict |
|---|---|---|---|
| cpptrace, jemalloc, mesa, qt6-declarative, qt6-base, qt6-svg, libdrm, libpipewire, libxcb, wayland | yes | Quickshell's own build/runtime deps; `quickshell-dusk-git` carries them | CORE (via quickshell-dusk) |
| qt6-5compat | yes | `Qt5Compat` in 261 files | CORE |
| qt6-multimedia | yes | `QtMultimedia` 18 files | CORE |
| qt6-positioning | yes | 2 files | CORE |
| qt6-imageformats | yes | image formats | CORE |
| qt6-wayland | yes | platform plugin | CORE |
| kirigami | yes | 3 files | CORE (FEATURE: settings pages and dock only) |
| syntax-highlighting | yes | 1 file (AI code blocks) | FEATURE |
| qt6-avif-image-plugin | no | 28 files mention avif | FEATURE |
| qt6-quicktimeline | yes | `QtQuick.Timeline` 0 hits | DROP |
| qt6-sensors | no | 0 hits | DROP |
| qt6-tools | no | provides qmllint/lupdate; only for development | BUILD (dev) |
| qt6-translations | yes | 0 hits | DROP |
| qt6-virtualkeyboard | no | 0 hits (own OSK) | DROP |
| kdialog | no | 32 mentions, each `command -v kdialog` with a fallback | FEATURE |

### illogical-impulse-screencapture
| Package | inst | Evidence | Verdict |
|---|---|---|---|
| hyprshot | yes | 0 hits (grim + slurp used) | DROP |
| python-evdev | no | imported by two scripts, but from the shell's venv (`requirements.lock`) | DROP (system package) |
| python-xkbcommon | no | used by `keypress_monitor.py`, from the venv | DROP (system package) |
| slurp | yes | 4 files | CORE |
| swappy | yes | 5 files | FEATURE |
| tesseract + tesseract-data-eng | yes | OCR, 25 files | FEATURE |
| wf-recorder | yes | 21 files (we build `ii-wf-recorder`); dep.json `phone-screen` | FEATURE |

### illogical-impulse-toolkit
| Package | inst | Evidence | Verdict |
|---|---|---|---|
| upower | yes | `Quickshell.Services.UPower` imported; the daemon must run | CORE (**Gap**) |
| wtype | yes | 12 files | CORE |
| ydotool | yes | 13 files, `Ydotool.qml` | CORE |

### illogical-impulse-widgets
| Package | inst | Evidence | Verdict |
|---|---|---|---|
| fuzzel | yes | 4 files (emoji picker) | FEATURE |
| gjs | no | 7 files (BudsLink earbuds); absent here | FEATURE |
| glib2 | yes | `gio`, `gdbus`, `gapplication` | CORE |
| imagemagick | yes | `magick`, `convert`, `compare`... | CORE |
| hypridle | yes | 12 files; config generated from Settings | CORE |
| hyprlock | yes | 14 files | CORE |
| hyprpicker | yes | 9 files | CORE |
| songrec | yes | 10 files | FEATURE |
| translate-shell | yes | `trans` 11 files | FEATURE |
| wlogout | no | only the Ctrl+Alt+Delete bind falls back to it; the shell has its own session screen | DROP (or FEATURE) |
| libqalculate | no | `qalc` 23 files, absent here, the code copes | FEATURE |

## 2. Totals

| Verdict | Packages |
|---|---|
| CORE | 56 |
| FEATURE | 24 |
| BUILD | 7 |
| DROP | 34 |

121 unique packages: the PKGBUILDs name 123, with `qt6-svg` and `wl-clipboard` listed twice. The count comes from
the tables above by script; the ten Quickshell build/runtime libraries each count as one CORE.

## 3. Gaps, to fix before `sdata/` goes

These are CORE or needed by an existing feature but are in neither `defaults/dependencies.json` nor the fork's own
installer, so today they only arrive through end-4's base install (the one thing this repo is trying to stop
depending on):

- **Core (required tier):** `matugen`, `libnotify` (notify-send), `upower`, `uv`, `jq`, `ripgrep`, `bc`, `curl`,
  `wl-clipboard`, `playerctl`, `brightnessctl`, `cliphist`, `hyprland`, `hypridle`, `hyprlock`, `hyprpicker`,
  `grim`, `slurp`, `wtype`, `ydotool`, `imagemagick`, `xdg-desktop-portal(-gtk/-hyprland)`, `gnome-keyring`,
  `networkmanager`, `wireplumber`, `pipewire-pulse`, `fontconfig`, the four fonts, and `yt-dlp`/`ffmpeg`.
- **Feature (optional tier):** `v4l-utils` (phone camera), `cava`, `ddcutil`, `swappy`, `tesseract`, `songrec`,
  `translate-shell`, `libqalculate`, `fuzzel`, `gjs`, `syntax-highlighting`, `qt6-avif-image-plugin`, `kdialog`,
  `geoclue`, `hyprsunset`, `aria2`.

`DEPENDENCIES.md` (in `scripts/deps/`) already lists most of these by area, and `check.sh` tests them against a
machine. It is documentation, not an install list.

## 4. Decisions (2026-11-23)

1. **MicroTeX / LaTeX rendering: dropped.** It only renders math in the AI chat, and nothing in this fork ever built
   `/opt/MicroTeX` (it was absent here too). The four build packages are gone. `LatexRenderer.qml` stays and shows the
   raw text when the binary is missing.
2. **kitty, fish, starship: dropped as dependencies.** The terminal is alacritty. The remaining code mentions are an
   example app name, a keybind importer for people who use kitty, and an optional theme entry, none of which needs
   kitty installed.
3. **Fedora, Gentoo, Nix: not supported for now.** The lists went with `sdata/`. `deps.py` still understands `arch` and
   `fedora` names; required packages only have to resolve on Arch.
4. **python-evdev and python-xkbcommon: system packages dropped.** They are used (`scripts/videos/keypress_monitor.py`
   and `scripts/tablet/tablet_scroll.py` import evdev, the key monitor also uses xkbcommon; the imports sit inside `try:`
   blocks, which is why the first scan missed them), but the shell's own venv installs both from
   `scripts/deps/requirements.lock` (`evdev==2.0.0`, `xkbcommon==1.5.1`). The Rust helpers use the `evdev` crate.

## 5. What was done

- `cli/hyprset.sh` and `cli/hyprmerge.sh` replace `sdata/cli/lib/`; the installer mirrors `cli/` and removes the old
  mirrored `sdata`.
- `sdata/`, the root `setup` script and the `sdata/dist-arch` workflow are deleted.
- `defaults/dependencies.json` gained seven required features covering section 3's gaps, plus fifteen optional ones
  (fonts, visualizer, OCR, night light, ...), and `v4l-utils` in the phone camera feature.
- README clone commands point at this fork.
