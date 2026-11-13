#!/usr/bin/env python3
"""Ambient sound mixer: the playback daemon and the catalogue of the Soundscapes app.

    soundscapes.py [--lib DIR] catalog            the library as JSON (sounds, groups, clips, credits)
    soundscapes.py [--lib DIR] download [--refresh]  fetch the manifest and the recordings that are missing
    soundscapes.py [--lib DIR] daemon             run the daemon (the first `ctl` spawns it)
    soundscapes.py [--lib DIR] ctl CMD [k=v ...]  one command; prints the daemon's answer

The library is a Noice extract (`metadata/library-manifest.json`, `metadata/sounds.json`,
`metadata/catalog.json`, `audio/current-128k/*.mp3`, `icons/*.svg`), by default ~/.local/share/soundscapes.

Playback is one detached daemon so a mix goes on when the window closes or the shell reloads.
Every sound that is on gets its own mpv, steered over mpv's IPC socket:

  * a continuous sound (rain, a fan, noise) loops one clip for ever;
  * a sound with `maxSilence` in the manifest (thunder, wolves, seagulls...) plays one random
    clip, then stays quiet for a random while, over and over. "Spacing" scales that quiet.

Volumes ramp, so toggling a sound, pausing and the sleep timer fade instead of cutting.
The clients speak JSON lines on $XDG_RUNTIME_DIR/soundscapes.sock; `subscribe` pushes a
`state` event on every change. Commands:

    state | subscribe [passive=1]        (a passive subscriber, like the shell's island, gets the
                                         pushes but does not keep an idle daemon from exiting)
    toggle id=X | set id=X [on=0|1] [vol=0..1] [spacing=0..1] | master vol=0..1
    play | pause | toggle_play | stop | random
    timer minutes=N [fade=SECONDS]       (0 cancels) | timer_fade fade=SECONDS
    preset_load id=X | preset_save name=X | preset_delete id=X
    quit
"""

import argparse
import asyncio
import ctypes
import json
import os
import random
import re
import shutil
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
SOCK = RUNTIME / "soundscapes.sock"
MPV_DIR = RUNTIME / "soundscapes-mpv"
STATE_FILE = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state") / "soundscapes" / "state.json"
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME") or HOME / ".cache") / "soundscapes"
DEFAULT_LIB = HOME / ".local" / "share" / "soundscapes"

MAX_VOICES = 12
FADE_SECONDS = 1.2        # a sound fading in or out
PAUSE_SECONDS = 0.8       # pause / resume
TICK = 0.05
CURVE = 1.6               # slider position -> loudness: the low end of a slider is usable
IDLE_EXIT_SECONDS = 15 * 60
DEFAULT_SPACING = 0.1

spawn = asyncio.create_subprocess_exec

# Mixes shipped with the app: id -> (name, icon, {sound: volume})
BUILTIN_PRESETS = {
    "rainy-cafe": ("Rainy café", "coffee", {"rain": .55, "coffee_shop": .6, "quiet_conversations": .22, "thunder": .25}),
    "cabin-fire": ("Cabin fire", "fireplace", {"campfire": .7, "rain": .3, "soft_wind": .22}),
    "midnight-forest": ("Midnight forest", "forest", {"night": .55, "crickets": .45, "wolves": .3, "soft_wind": .25}),
    "seaside": ("Seaside morning", "beach_access", {"seashore": .65, "seagulls": .35, "wind_through_palm_trees": .3}),
    "deep-focus": ("Deep focus", "psychology", {"brownian_noise": .45, "fan": .3, "wall_clock": .12}),
    "night-train": ("Night train", "train", {"train": .6, "rain": .3, "quiet_conversations": .12}),
    "quiet-library": ("Quiet library", "local_library", {"public_library": .6, "soft_wind": .12, "rain": .18}),
    "thunderstorm": ("Thunderstorm", "thunderstorm", {"rain": .6, "thunder": .7, "soft_wind": .3}),
    "winter-walk": ("Winter walk", "ac_unit", {"walking_in_snow": .6, "soft_wind": .4, "wind_chimes": .2}),
}


def fail(msg):
    sys.stderr.write(f"soundscapes: {msg}\n")
    sys.exit(1)


# ── the catalogue ─────────────────────────────────────────────────────────────────────────

def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


CDN = "https://cdn.trynoice.com/library"
AUDIO_SUBDIR = "audio/current-128k"


def clip_path(lib, sound_id, segment):
    return Path(lib) / AUDIO_SUBDIR / f"{sound_id}__{segment}.mp3"


def white_icon(svg, dst):
    """The library's icons are black shapes with no fill; the app tints them, so a copy
    filled white (set on the root, the paths inherit it) is what it loads."""
    try:
        if not svg:
            return ""
        svg = re.sub(r"<svg\b", '<svg fill="#ffffff"', svg, count=1)
        if dst.exists() and dst.read_text(encoding="utf-8") == svg:
            return str(dst)
        dst.parent.mkdir(parents=True, exist_ok=True)
        tmp = dst.with_suffix(".tmp")
        tmp.write_text(svg, encoding="utf-8")
        os.replace(tmp, dst)
        return str(dst)
    except OSError:
        return ""


def icon_svg(lib, sound):
    """The icon's SVG text: the library's own file, else the data URL in the manifest."""
    try:
        return (Path(lib) / "icons" / f"{sound['id']}.svg").read_text(encoding="utf-8")
    except OSError:
        pass
    url = sound.get("icon", "")
    if url.startswith("data:image/svg+xml,"):
        from urllib.parse import unquote
        return unquote(url.split(",", 1)[1])
    return ""


def manifest_path(lib):
    return Path(lib) / "metadata" / "library-manifest.json"


def build_catalog(lib):
    """Everything comes from the manifest, so a library with nothing in it but that file
    still lists every sound; `present` says which recordings are on disk."""
    lib = Path(lib)
    manifest = load_json(manifest_path(lib))
    durations = {}
    try:
        for r in load_json(lib / "metadata" / "catalog.json"):
            if r.get("collection") == "current-free-128k":
                durations[r["file"].rsplit("/", 1)[-1]] = float(r.get("duration_s") or 0)
    except (OSError, ValueError, KeyError, TypeError):
        pass
    tag_names = {t["id"]: t["name"] for t in manifest.get("tags", [])}
    groups = [{"id": g["id"], "name": g["name"]} for g in manifest.get("groups", [])]
    group_names = {g["id"]: g["name"] for g in groups}
    out, total, missing = [], 0, 0
    for s in manifest["sounds"]:
        sid = s["id"]
        clips = []
        for seg in s.get("segments", []):
            if not seg.get("isFree"):
                continue
            path = clip_path(lib, sid, seg["name"])
            present = path.exists()
            clips.append({"file": str(path), "segment": seg["name"], "present": present,
                          "duration": durations.get(path.name, 0.0)})
            total += 1
            missing += 0 if present else 1
        if not clips:
            continue
        credits = []
        for src in s.get("sources", []):
            title = src.get("name", "")
            if re.search(r"\bicon\b", title, re.I):
                continue
            credits.append({"title": title, "author": (src.get("author") or {}).get("name", ""),
                            "license": src.get("license", ""), "url": src.get("url", "")})
        out.append({
            "id": sid,
            "name": s["name"],
            "groupId": s["groupId"],
            "group": group_names.get(s["groupId"], s["groupId"]),
            "tags": [tag_names.get(t, t) for t in s.get("tags", [])],
            "silence": int(s.get("maxSilence") or 0),
            "icon": white_icon(icon_svg(lib, s), CACHE_DIR / "icons" / f"{sid}.svg"),
            "clips": clips,
            "available": any(c["present"] for c in clips),
            "credits": credits,
        })
    out.sort(key=lambda s: (s["group"], s["name"]))
    used = {s["groupId"] for s in out}
    return {"lib": str(lib), "groups": [g for g in groups if g["id"] in used], "sounds": out,
            "totalClips": total, "missingClips": missing,
            "presets": [{"id": pid, "name": p[0], "icon": p[1], "builtin": True, "mix": p[2]}
                        for pid, p in BUILTIN_PRESETS.items()]}


def cmd_catalog(args):
    lib = Path(args.lib)
    empty = {"lib": str(lib), "groups": [], "sounds": [], "presets": [], "totalClips": 0, "missingClips": 0}
    if not manifest_path(lib).exists():
        print(json.dumps(dict(empty, error=f"There is no sound library in {lib}", needsDownload=True)))
        return
    try:
        print(json.dumps(build_catalog(lib)))
    except (OSError, ValueError, KeyError) as e:
        print(json.dumps(dict(empty, error=f"The library in {lib} could not be read: {e!r}", needsDownload=True)))


# ── downloading what is missing ───────────────────────────────────────────────────────────

def fetch(url, dest, timeout=30):
    """Download to a .part file and move it into place, so a stopped download leaves nothing half-written."""
    import urllib.request
    dest = Path(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_name(dest.name + ".part")
    req = urllib.request.Request(url, headers={"User-Agent": "ii-soundscapes"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r, open(part, "wb") as f:
            while True:
                chunk = r.read(1 << 16)
                if not chunk:
                    break
                f.write(chunk)
        if part.stat().st_size == 0:
            raise OSError("empty response")
        os.replace(part, dest)
    finally:
        part.unlink(missing_ok=True)


def cmd_download(args):
    """Fetch the manifest (when the library has none) and every free recording that is not
    on disk. Prints JSON lines: progress {done, total, sound}, then one `done`."""
    lib = Path(args.lib)

    def emit(**kw):
        print(json.dumps(kw), flush=True)

    try:
        if args.refresh or not manifest_path(lib).exists():
            emit(event="status", text="manifest")
            fetch(f"{CDN}/library-manifest.json", manifest_path(lib))
        manifest = load_json(manifest_path(lib))
    except (OSError, ValueError) as e:
        emit(event="done", ok=False, failed=0, error=f"Could not reach the sound library: {e}")
        return
    jobs = []
    for s in manifest["sounds"]:
        for seg in s.get("segments", []):
            dest = clip_path(lib, s["id"], seg["name"])
            if seg.get("isFree") and not dest.exists():
                jobs.append((s, seg, dest))
    emit(event="start", total=len(jobs))
    failed = 0
    for i, (s, seg, dest) in enumerate(jobs, 1):
        url = f"{CDN}/segments/{s['id']}/{seg['name']}/128k.mp3"
        for attempt in range(3):
            try:
                fetch(url, dest)
                break
            except OSError:
                if attempt == 2:
                    failed += 1
                else:
                    time.sleep(1.5 * (attempt + 1))
        emit(event="progress", done=i, total=len(jobs), sound=s["name"], failed=failed)
    emit(event="done", ok=failed == 0, failed=failed, total=len(jobs))


# ── one playing sound ─────────────────────────────────────────────────────────────────────

def _die_with_parent():
    """In the child, before exec: end whenever the daemon ends, however that happens."""
    try:
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG
    except (OSError, AttributeError):
        pass


class Voice:
    """One sound that is on: an mpv, its socket, and the level it is fading to."""

    def __init__(self, daemon, sound):
        self.d = daemon
        self.sound = sound
        self.id = sound["id"]
        self.proc = None
        self.writer = None
        self.reader_task = None
        self.loop_task = None
        self.level = 0.0          # 0..1, ramps toward `target`
        self.target = 1.0
        self.sent = -1.0
        self.ended = asyncio.Event()
        self.wake = asyncio.Event()
        self.dead = False
        self.last_clip = None

    @property
    def clips(self):
        return [c["file"] for c in self.sound["clips"] if c["present"]]

    @property
    def gapped(self):
        return self.sound["silence"] > 0

    async def start(self):
        sock = MPV_DIR / f"{self.id}.sock"
        sock.unlink(missing_ok=True)
        cmd = ["mpv", "--no-config", "--no-video", "--audio-display=no", "--really-quiet", "--force-window=no",
               "--terminal=no", "--load-scripts=no", "--osc=no", "--input-default-bindings=no", "--idle=yes",
               "--volume=0", "--audio-client-name=Soundscapes", f"--force-media-title={self.sound['name']}",
               f"--pause={'no' if self.d.mpv_playing else 'yes'}", f"--input-ipc-server={sock}"]
        if os.environ.get("SOUNDSCAPES_AO"):  # for tests: --ao=null plays nothing
            cmd.append(f"--ao={os.environ['SOUNDSCAPES_AO']}")
        if not self.gapped:
            cmd += ["--loop-file=inf", self.clips[0]]
        self.proc = await spawn(
            *cmd, stdin=asyncio.subprocess.DEVNULL, stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL, preexec_fn=_die_with_parent)
        for _ in range(60):
            if sock.exists() or self.proc.returncode is not None:
                break
            await asyncio.sleep(0.05)
        try:
            reader, self.writer = await asyncio.open_unix_connection(str(sock))
        except OSError:
            self.dead = True
            return
        self.reader_task = asyncio.create_task(self._read(reader))
        if self.gapped:
            self.loop_task = asyncio.create_task(self._gaps())

    async def _read(self, reader):
        try:
            while True:
                line = await reader.readline()
                if not line:
                    break
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                if msg.get("event") == "end-file":
                    self.ended.set()
        except (OSError, asyncio.CancelledError):
            pass
        finally:
            self.dead = True
            self.ended.set()
            self.d.voice_died(self)

    def send(self, *command):
        if self.writer is None or self.dead:
            return
        try:
            self.writer.write((json.dumps({"command": list(command)}) + "\n").encode())
        except OSError:
            self.dead = True

    async def _gaps(self):
        """Play a random clip, stay quiet for a random while, and again."""
        clips = self.clips
        while not self.dead:
            choices = [c for c in clips if c != self.last_clip] or clips
            self.last_clip = random.choice(choices)
            self.ended.clear()
            self.send("loadfile", self.last_clip, "replace")
            try:
                await asyncio.wait_for(self.ended.wait(), timeout=3600)
            except asyncio.TimeoutError:
                continue
            if self.dead:
                return
            gap = self._draw_gap()
            while not self.dead:
                self.wake.clear()
                try:
                    await asyncio.wait_for(self.wake.wait(), timeout=gap)
                except asyncio.TimeoutError:
                    break  # the gap is over
                gap = self._draw_gap()  # woken: the spacing changed, draw a new gap

    def _draw_gap(self):
        spacing = self.d.sounds[self.id]["spacing"]
        return random.uniform(2.0, 2.0 + self.sound["silence"] * max(0.0, spacing))

    def apply(self):
        """Send the volume this voice should have now, if it moved."""
        st = self.d.sounds[self.id]
        loud = ((st["vol"] * self.d.master) ** CURVE) * self.d.gain * self.level * 100.0
        loud = max(0.0, min(100.0, loud))
        if abs(loud - self.sent) >= 0.05 or (loud == 0 and self.sent != 0):
            self.sent = loud
            self.send("set_property", "volume", round(loud, 1))

    def stop(self):
        self.dead = True
        for task in (self.loop_task, self.reader_task):
            if task:
                task.cancel()
        if self.writer:
            try:
                self.writer.write(b'{"command":["quit"]}\n')
                self.writer.close()
            except OSError:
                pass
        if self.proc and self.proc.returncode is None:
            try:
                self.proc.terminate()
            except ProcessLookupError:
                pass
        (MPV_DIR / f"{self.id}.sock").unlink(missing_ok=True)


# ── the daemon ────────────────────────────────────────────────────────────────────────────

class Daemon:
    def __init__(self, lib):
        self.lib = lib
        self.catalog = build_catalog(lib)
        self.by_id = {s["id"]: s for s in self.catalog["sounds"]}
        self.sounds = {sid: {"on": False, "vol": 0.6, "spacing": DEFAULT_SPACING} for sid in self.by_id}
        self.order = []                 # ids that are on, oldest first
        self.voices = {}
        self.master = 0.8
        self.playing = True             # the user's intent: false = paused
        self.mpv_playing = True         # what the mpv processes are set to
        self.gain = 1.0                 # global fade (pause, sleep timer)
        self.gain_target = 1.0
        self.gain_rate = 1.0 / PAUSE_SECONDS
        self.timer_end = 0.0
        self.timer_total = 0.0
        self.timer_fade = 30
        self.save_handle = None
        self.timer_task = None
        self.presets = []               # the user's own
        self.current_preset = ""
        self.subscribers = set()
        self.watchers = set()           # passive subscribers: they hear everything, hold nothing up
        self.ramp_task = None
        self.push_pending = False
        self.last_active = time.time()
        self.respawns = {}
        self.stopping = False
        self.load_state()

    # persistence
    def load_state(self):
        try:
            saved = load_json(STATE_FILE)
        except (OSError, ValueError):
            return
        self.master = float(saved.get("master", self.master))
        self.timer_fade = int(saved.get("timerFade", self.timer_fade))
        for sid, st in (saved.get("sounds") or {}).items():
            if sid in self.sounds:
                self.sounds[sid]["vol"] = float(st.get("vol", 0.6))
                self.sounds[sid]["spacing"] = float(st.get("spacing", DEFAULT_SPACING))
        self.presets = [p for p in saved.get("presets", []) if isinstance(p, dict) and p.get("id") and p.get("name")]

    def save_state(self):
        """Debounced: a slider drag is a stream of writes."""
        if self.save_handle is None:
            self.save_handle = asyncio.get_running_loop().call_later(1.0, self._write_state)

    def _write_state(self):
        self.save_handle = None
        data = {"master": self.master, "timerFade": self.timer_fade,
                "sounds": {sid: {"vol": st["vol"], "spacing": st["spacing"]} for sid, st in self.sounds.items()},
                "presets": self.presets}
        try:
            STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
            tmp = STATE_FILE.with_suffix(".tmp")
            tmp.write_text(json.dumps(data), encoding="utf-8")
            os.replace(tmp, STATE_FILE)
        except OSError:
            pass

    # state out
    def snapshot(self):
        now = time.time()
        return {
            "event": "state",
            "playing": self.playing and bool(self.order),
            "paused": not self.playing,
            "master": self.master,
            "active": list(self.order),
            "sounds": {sid: {"on": st["on"], "vol": st["vol"], "spacing": st["spacing"]} for sid, st in self.sounds.items()},
            "timerEnd": self.timer_end if self.timer_end > now else 0,
            "timerTotal": self.timer_total if self.timer_end > now else 0,
            "timerFade": self.timer_fade,
            "now": now,
            "preset": self.current_preset,
            "userPresets": [{"id": p["id"], "name": p["name"], "icon": p.get("icon", "bookmark"), "builtin": False,
                             "mix": p["mix"]} for p in self.presets],
        }

    def push(self):
        if self.push_pending:
            return
        self.push_pending = True
        asyncio.get_running_loop().call_soon(self._flush)

    def _flush(self):
        self.push_pending = False
        line = (json.dumps(self.snapshot()) + "\n").encode()
        for group in (self.subscribers, self.watchers):
            for w in list(group):
                try:
                    w.write(line)
                except OSError:
                    group.discard(w)

    # voices
    def ensure_ramp(self):
        if self.ramp_task is None or self.ramp_task.done():
            self.ramp_task = asyncio.create_task(self._ramp())

    async def _ramp(self):
        while True:
            busy = False
            if self.gain != self.gain_target:
                step = self.gain_rate * TICK
                self.gain = min(self.gain_target, self.gain + step) if self.gain < self.gain_target \
                    else max(self.gain_target, self.gain - step)
                busy = True
            for sid, v in list(self.voices.items()):
                if v.level != v.target:
                    step = TICK / FADE_SECONDS
                    v.level = min(v.target, v.level + step) if v.level < v.target else max(v.target, v.level - step)
                    busy = True
                v.apply()
                if v.target == 0 and v.level == 0:
                    v.stop()
                    del self.voices[sid]
            if not self.playing and self.gain == 0 and self.mpv_playing:
                self.mpv_playing = False
                for v in self.voices.values():
                    v.send("set_property", "pause", True)
            if not busy:
                return
            await asyncio.sleep(TICK)

    def voice_died(self, voice):
        if self.stopping or self.voices.get(voice.id) is not voice or voice.target == 0:
            return
        del self.voices[voice.id]
        n = self.respawns.get(voice.id, 0)
        if self.sounds[voice.id]["on"] and n < 3:
            self.respawns[voice.id] = n + 1
            asyncio.get_running_loop().call_later(1.0, lambda: asyncio.create_task(self._revive(voice.id)))
        else:
            self.sounds[voice.id]["on"] = False
            if voice.id in self.order:
                self.order.remove(voice.id)
            self.push()

    async def _revive(self, sid):
        if self.sounds[sid]["on"] and sid not in self.voices:
            await self._start_voice(sid)

    async def _start_voice(self, sid):
        v = Voice(self, self.by_id[sid])
        self.voices[sid] = v
        await v.start()
        if v.dead and self.voices.get(sid) is v:
            del self.voices[sid]
            self.sounds[sid]["on"] = False
            if sid in self.order:
                self.order.remove(sid)
            self.push()
            return
        v.apply()
        self.ensure_ramp()

    async def switch(self, sid, on):
        st = self.sounds.get(sid)
        if st is None or (on and not self.by_id[sid]["available"]):
            return
        if on:
            if len(self.order) >= MAX_VOICES and not st["on"]:
                return
            v = self.voices.get(sid)
            if st["on"] and v is not None and v.target == 1:
                return
            st["on"] = True
            if sid not in self.order:
                self.order.append(sid)
            self.respawns.pop(sid, None)
            if not self.playing:
                self.resume()
            if v is not None:
                v.target = 1.0
                self.ensure_ramp()
            else:
                await self._start_voice(sid)
        else:
            st["on"] = False
            if sid in self.order:
                self.order.remove(sid)
            v = self.voices.get(sid)
            if v is not None:
                v.target = 0.0
                self.ensure_ramp()
        self.last_active = time.time()

    def pause(self):
        self.playing = False
        self.gain_target = 0.0
        self.gain_rate = 1.0 / PAUSE_SECONDS
        self.ensure_ramp()

    def resume(self):
        self.playing = True
        if not self.mpv_playing:
            self.mpv_playing = True
            for v in self.voices.values():
                v.send("set_property", "pause", False)
        self.gain_target = 1.0
        self.gain_rate = 1.0 / PAUSE_SECONDS
        self.ensure_ramp()

    # sleep timer
    def cancel_timer(self):
        if self.timer_task:
            self.timer_task.cancel()
            self.timer_task = None
        self.timer_end = 0.0

    def set_timer(self, minutes):
        self.cancel_timer()
        if self.playing and self.gain_target < 1:
            self.gain_target = 1.0       # a fade the old timer had begun is undone
            self.gain_rate = 1.0 / PAUSE_SECONDS
            self.ensure_ramp()
        if minutes and minutes > 0:
            self.timer_end = time.time() + minutes * 60
            self.timer_total = minutes * 60
            self.timer_task = asyncio.create_task(self._timer(self.timer_end))

    async def _timer(self, end):
        fade = min(self.timer_fade, max(1, (end - time.time()) / 2))
        await asyncio.sleep(max(0.0, end - fade - time.time()))
        self.gain_target = 0.0
        self.gain_rate = 1.0 / fade
        self.ensure_ramp()
        await asyncio.sleep(max(0.0, end - time.time()))
        self.timer_task = None
        self.timer_end = 0.0
        self.playing = False
        self.gain = 0.0
        self.ensure_ramp()
        self.push()

    # mixes
    async def apply_mix(self, mix, preset_id=""):
        wanted = [sid for sid in mix if sid in self.by_id]
        for sid in list(self.order):
            if sid not in wanted:
                await self.switch(sid, False)
        for sid in wanted:
            self.sounds[sid]["vol"] = max(0.0, min(1.0, float(mix[sid])))
            await self.switch(sid, True)
            if sid in self.voices:
                self.voices[sid].apply()
        self.current_preset = preset_id

    # commands
    async def handle(self, msg, writer):
        cmd = msg.get("cmd", "")
        if cmd in ("state", "subscribe"):
            if cmd == "subscribe":
                # A connection is in one set or the other, and may move between them (the
                # shell's window opening or closing while the island keeps watching).
                if msg.get("passive") in (True, 1, "1", "true"):
                    self.subscribers.discard(writer)
                    self.watchers.add(writer)
                else:
                    self.watchers.discard(writer)
                    self.subscribers.add(writer)
            return self.snapshot()
        if cmd == "toggle":
            sid = str(msg.get("id", ""))
            if sid in self.sounds:
                await self.switch(sid, not self.sounds[sid]["on"])
                self.current_preset = ""
        elif cmd == "set":
            sid = str(msg.get("id", ""))
            st = self.sounds.get(sid)
            if st is not None:
                if "vol" in msg:
                    st["vol"] = max(0.0, min(1.0, float(msg["vol"])))
                if "spacing" in msg:
                    st["spacing"] = max(0.0, min(1.0, float(msg["spacing"])))
                    if sid in self.voices:
                        self.voices[sid].wake.set()
                if "on" in msg:
                    await self.switch(sid, bool(int(msg["on"])))
                if sid in self.voices:
                    self.voices[sid].apply()
                self.current_preset = ""
                self.save_state()
        elif cmd == "master":
            self.master = max(0.0, min(1.0, float(msg.get("vol", self.master))))
            for v in self.voices.values():
                v.apply()
            self.save_state()
        elif cmd == "play":
            self.resume()
        elif cmd == "pause":
            self.pause()
        elif cmd == "toggle_play":
            if self.order:
                self.pause() if self.playing else self.resume()
        elif cmd == "stop":
            self.cancel_timer()
            for sid in list(self.order):
                await self.switch(sid, False)
            self.current_preset = ""
            self.resume()
        elif cmd == "random":
            ids = [sid for sid in self.by_id if sid not in ("brownian_noise", "pink_noise", "white_noise")]
            pick = random.sample(ids, random.choice((2, 3, 3, 4)))
            await self.apply_mix({sid: random.uniform(0.35, 0.8) for sid in pick})
            self.resume()
            self.save_state()
        elif cmd == "timer":
            if "fade" in msg:
                self.timer_fade = max(1, min(300, int(float(msg["fade"]))))
            self.set_timer(float(msg.get("minutes", 0)))
            self.save_state()
        elif cmd == "reload_catalog":
            self.catalog = build_catalog(self.lib)
            self.by_id = {x["id"]: x for x in self.catalog["sounds"]}
            for sid in self.by_id:
                self.sounds.setdefault(sid, {"on": False, "vol": 0.6, "spacing": DEFAULT_SPACING})
            for sid, v in self.voices.items():
                if sid in self.by_id:
                    v.sound = self.by_id[sid]
        elif cmd == "timer_fade":
            self.timer_fade = max(1, min(300, int(float(msg.get("fade", self.timer_fade)))))
            if self.timer_end > time.time():  # the running timer keeps its end, with the new fade
                total = self.timer_total
                self.set_timer((self.timer_end - time.time()) / 60)
                self.timer_total = total
            self.save_state()
        elif cmd == "preset_load":
            pid = str(msg.get("id", ""))
            preset = next((p for p in self.catalog["presets"] if p["id"] == pid), None) \
                or next((p for p in self.presets if p["id"] == pid), None)
            if preset is None:
                return {"ok": False, "error": "no such mix"}
            await self.apply_mix(preset["mix"], pid)
            self.resume()
        elif cmd == "preset_save":
            name = str(msg.get("name", "")).strip()[:40]
            if not self.order or not name:
                return {"ok": False, "error": "a mix needs a name" if self.order else "nothing to save"}
            pid = "user:" + re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") + f"-{int(time.time()) % 100000}"
            self.presets.append({"id": pid, "name": name, "icon": "bookmark",
                                 "mix": {sid: self.sounds[sid]["vol"] for sid in self.order}})
            self.current_preset = pid
            self.save_state()
        elif cmd == "preset_delete":
            pid = str(msg.get("id", ""))
            self.presets = [p for p in self.presets if p["id"] != pid]
            if self.current_preset == pid:
                self.current_preset = ""
            self.save_state()
        elif cmd == "quit":
            asyncio.get_running_loop().call_later(0.1, lambda: asyncio.create_task(self.shutdown()))
            return {"ok": True}
        else:
            return {"ok": False, "error": f"unknown command {cmd!r}"}
        self.last_active = time.time()
        self.push()
        return {"ok": True}

    async def client(self, reader, writer):
        try:
            while True:
                line = await reader.readline()
                if not line:
                    break
                try:
                    reply = await self.handle(json.loads(line), writer)
                except (ValueError, TypeError) as e:
                    reply = {"ok": False, "error": repr(e)}
                writer.write((json.dumps(reply) + "\n").encode())
                await writer.drain()
        except (OSError, asyncio.CancelledError):
            pass
        finally:
            self.subscribers.discard(writer)
            self.watchers.discard(writer)
            try:
                writer.close()
            except OSError:
                pass

    async def watchdog(self):
        """Exit after a long quiet spell so nothing idles for ever."""
        while True:
            await asyncio.sleep(60)
            if self.order or self.subscribers:
                self.last_active = time.time()
            elif time.time() - self.last_active > IDLE_EXIT_SECONDS:
                await self.shutdown()

    async def shutdown(self):
        self.stopping = True
        if self.save_handle is not None:
            self.save_handle.cancel()
            self._write_state()
        for v in list(self.voices.values()):
            v.stop()
        SOCK.unlink(missing_ok=True)
        for sock in MPV_DIR.glob("*.sock"):
            sock.unlink(missing_ok=True)
        os._exit(0)

    async def run(self):
        MPV_DIR.mkdir(parents=True, exist_ok=True)
        SOCK.unlink(missing_ok=True)
        server = await asyncio.start_unix_server(self.client, str(SOCK))
        os.chmod(SOCK, 0o600)
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            loop.add_signal_handler(sig, lambda: asyncio.create_task(self.shutdown()))
        asyncio.create_task(self.watchdog())
        async with server:
            await server.serve_forever()


def cmd_daemon(args):
    if SOCK.exists():
        try:
            s = socket.socket(socket.AF_UNIX)
            s.settimeout(1)
            s.connect(str(SOCK))
            s.close()
            return  # already running
        except OSError:
            SOCK.unlink(missing_ok=True)
    if shutil.which("mpv") is None:
        fail("mpv is not installed")
    try:
        daemon = Daemon(Path(args.lib))
    except (OSError, ValueError, KeyError) as e:
        fail(f"cannot read the library in {args.lib}: {e!r}")
    asyncio.run(daemon.run())


# ── the client ────────────────────────────────────────────────────────────────────────────

def connect_daemon(lib, start=True):
    def attempt():
        s = socket.socket(socket.AF_UNIX)
        s.settimeout(30)
        try:
            s.connect(str(SOCK))
            return s
        except OSError:
            s.close()
            return None

    s = attempt()
    if s or not start:
        return s
    SOCK.unlink(missing_ok=True)
    subprocess.Popen([sys.executable, "-I", os.path.abspath(__file__), "--lib", str(lib), "daemon"],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    for _ in range(100):
        time.sleep(0.1)
        s = attempt()
        if s:
            return s
    return None


def cast(value):
    for kind in (int, float):
        try:
            return kind(value)
        except ValueError:
            pass
    return value


def cmd_ctl(args):
    msg = {"cmd": args.what}
    for pair in args.pairs:
        if "=" not in pair:
            fail(f"expected key=value, got {pair!r}")
        k, v = pair.split("=", 1)
        msg[k] = cast(v)
    s = connect_daemon(args.lib, start=args.what != "quit")
    if s is None:
        print(json.dumps({"ok": False, "error": "the daemon is not running" if args.what == "quit" else "the daemon did not start"}))
        sys.exit(0 if args.what == "quit" else 1)
    s.sendall((json.dumps(msg) + "\n").encode())
    buf = b""
    while not buf.endswith(b"\n"):
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
    s.close()
    print(buf.decode().strip() or json.dumps({"ok": True}))


def main():
    ap = argparse.ArgumentParser(prog="soundscapes")
    ap.add_argument("--lib", default=os.environ.get("SOUNDSCAPES_LIB") or str(DEFAULT_LIB))
    sub = ap.add_subparsers(dest="command", required=True)
    sub.add_parser("catalog").set_defaults(fn=cmd_catalog)
    d = sub.add_parser("download")
    d.add_argument("--refresh", action="store_true", help="fetch the manifest again")
    d.set_defaults(fn=cmd_download)
    sub.add_parser("daemon").set_defaults(fn=cmd_daemon)
    p = sub.add_parser("ctl")
    p.add_argument("what")
    p.add_argument("pairs", nargs="*")
    p.set_defaults(fn=cmd_ctl)
    args = ap.parse_args()
    args.lib = os.path.expanduser(args.lib)
    args.fn(args)


if __name__ == "__main__":
    main()
