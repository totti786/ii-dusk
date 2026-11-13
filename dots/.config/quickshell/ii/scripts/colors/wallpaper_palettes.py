#!/usr/bin/env python3
"""The colour scheme matugen would make from each wallpaper, for the deck
picker's swatch cards (services/WallpaperPalettes.qml).

    wallpaper_palettes.py --cache FILE [--type T] [--mode dark|light] [--workers N]

Reads wallpaper paths from stdin, one line at a time, tab-separated. Every line
moves its paths to the front of the queue, in that order (the picker sends the
cards in view), so what is on screen is read first. When stdin closes the worker
finishes what it is doing and exits.

matugen runs as a dry run (nothing is written or applied). The type and mode are
the ones switchwall.sh would pass, so a card shows the scheme its wallpaper will
give. Prints one JSON line per wallpaper as soon as it is known:

    {"p": path, "w": width, "h": height, "c": {role: "#rrggbb", ...}}
    {"p": path, "e": 1}

when matugen cannot read the file (a video, a broken image). Results are cached
on disk, keyed by path, mtime, size, type and mode.

The idea of reading each card's scheme from a matugen dry run comes from
https://github.com/dhrruvsharma/qs-wallpaperpicker (GPL-3.0).
"""

import argparse
import ctypes
import json
import shutil
import os
import signal
import struct
import subprocess
import sys
import threading
from collections import deque

ROLES = (
    "background", "surface", "surface_container_lowest", "surface_container_low",
    "surface_container", "surface_container_high", "surface_container_highest",
    "on_surface", "on_surface_variant", "outline", "outline_variant",
    "primary", "on_primary", "primary_container", "on_primary_container",
    "secondary", "on_secondary", "secondary_container", "on_secondary_container",
    "tertiary", "on_tertiary", "tertiary_container", "on_tertiary_container",
    "error", "source_color",
)
VIDEO = (".mp4", ".webm", ".mkv", ".mov", ".m4v", ".avi", ".ogv", ".gif")
FLUSH_EVERY = 25


def _jpeg_size(f):
    f.seek(2)
    while True:
        byte = f.read(1)
        if not byte:
            return 0, 0
        if byte != b"\xff":
            continue
        marker = f.read(1)
        while marker == b"\xff":
            marker = f.read(1)
        if not marker:
            return 0, 0
        m = marker[0]
        if m in (0xD9, 0xDA):
            return 0, 0
        if m == 0x01 or 0xD0 <= m <= 0xD7:
            continue
        length = struct.unpack(">H", f.read(2))[0]
        if 0xC0 <= m <= 0xCF and m not in (0xC4, 0xC8, 0xCC):
            f.read(1)
            h, w = struct.unpack(">HH", f.read(4))
            return w, h
        f.seek(length - 2, 1)


def image_size(path):
    """(width, height) from the file's header, or (0, 0)."""
    try:
        with open(path, "rb") as f:
            head = f.read(30)
            if head[:8] == b"\x89PNG\r\n\x1a\n":
                return struct.unpack(">II", head[16:24])
            if head[:6] in (b"GIF87a", b"GIF89a"):
                return struct.unpack("<HH", head[6:10])
            if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
                kind = head[12:16]
                if kind == b"VP8 ":
                    w, h = struct.unpack("<HH", head[26:30])
                    return w & 0x3FFF, h & 0x3FFF
                if kind == b"VP8L":
                    bits = int.from_bytes(head[21:25], "little")
                    return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
                if kind == b"VP8X":
                    return int.from_bytes(head[24:27], "little") + 1, int.from_bytes(head[27:30], "little") + 1
            if head[:2] == b"\xff\xd8":
                return _jpeg_size(f)
            # JPEG XL (bare codestream, or inside its ISO box container): the size is a
            # bit-packed header, so ask ImageMagick, header only.
            if head[:2] == b"\xff\x0a" or head[:12] == b"\x00\x00\x00\x0cJXL \r\n\x87\n":
                return _identify_size(path)
    except (OSError, struct.error):
        pass
    return 0, 0


def _identify_size(path):
    tool = shutil.which("magick")
    if not tool:
        return 0, 0
    try:
        out = subprocess.run([tool, "identify", "-ping", "-format", "%w %h", path + "[0]"],
                             capture_output=True, text=True, timeout=10).stdout.split()
        return int(out[0]), int(out[1])
    except (OSError, subprocess.SubprocessError, ValueError, IndexError):
        return 0, 0


# matugen processes running now. When the picker closes the worker is stopped, and a
# matugen that loses its output pipe panics and aborts (a core dump each), so they are
# stopped first, and a worker killed outright takes them down with it (see _die_with_parent).
_children = set()
_children_lock = threading.Lock()
_stopping = threading.Event()


def _die_with_parent():
    """In the child, before exec: SIGKILL when the worker goes, whatever way it goes."""
    try:
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGKILL)  # PR_SET_PDEATHSIG
    except (OSError, AttributeError):
        pass


def stop_children():
    _stopping.set()
    with _children_lock:
        children = list(_children)
    for proc in children:
        try:
            proc.kill()
        except OSError:
            pass


_worker = None


def _on_term(signum, frame):
    stop_children()
    try:
        _worker.save()  # what it has read so far is not lost
    except Exception:
        pass
    os._exit(0)


def scheme(path, scheme_type, mode):
    cmd = ["matugen", "image", path, "--source-color-index", "0"]
    if scheme_type:
        cmd += ["--type", scheme_type]
    if mode:
        cmd += ["--mode", mode]
    cmd += ["--dry-run", "-q", "-j", "hex"]
    if _stopping.is_set():
        return None
    try:
        # stdin is the picker's pipe: matugen must not read it.
        proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, preexec_fn=_die_with_parent)
    except OSError as e:
        sys.stderr.write("palette failed for %s: %r\n" % (path, e))
        return None
    with _children_lock:
        _children.add(proc)
    try:
        stdout, stderr = proc.communicate(timeout=90)
        if _stopping.is_set():
            return None
        if proc.returncode != 0:
            sys.stderr.write("matugen exit %d on %s: %s\n" % (proc.returncode, path, stderr.strip()[:300]))
            return None
        colors = json.loads(stdout)["colors"]
        return {r: (colors[r].get("default") or colors[r]["dark"])["color"] for r in ROLES if r in colors}
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        return None
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as e:
        sys.stderr.write("palette failed for %s: %r\n" % (path, e))
        return None
    finally:
        with _children_lock:
            _children.discard(proc)


class Worker:
    def __init__(self, args):
        self.args = args
        self.lock = threading.Condition()
        self.queue = deque()
        self.queued = set()
        self.done = set()
        self.closed = False
        self.dirty = 0
        self.cache = {}
        try:
            with open(args.cache) as f:
                self.cache = json.load(f)
        except (OSError, ValueError):
            pass

    def key(self, path):
        try:
            st = os.stat(path)
        except OSError:
            return None
        return "%s|%d|%d|%s|%s" % (path, st.st_mtime_ns, st.st_size, self.args.type, self.args.mode)

    def emit(self, path, colors):
        if colors:
            w, h = image_size(path)
            line = {"p": path, "w": w, "h": h, "c": colors}
        else:
            line = {"p": path, "e": 1}
        sys.stdout.write(json.dumps(line) + "\n")
        sys.stdout.flush()

    def save(self):
        tmp = self.args.cache + ".tmp"
        try:
            os.makedirs(os.path.dirname(self.args.cache), exist_ok=True)
            with open(tmp, "w") as f:
                json.dump(dict(self.cache), f)
            os.replace(tmp, self.args.cache)
        except OSError:
            pass

    def prioritise(self, paths):
        with self.lock:
            for path in reversed(paths):
                if path in self.done:
                    # Asked again (the card scrolled back into view, or the panel
                    # reopened): answered from memory without reading the file.
                    self.done.discard(path)
                if path in self.queued:
                    try:
                        self.queue.remove(path)
                    except ValueError:
                        pass
                self.queue.appendleft(path)
                self.queued.add(path)
            self.lock.notify_all()

    def next_path(self):
        with self.lock:
            while not self.queue:
                if self.closed:
                    return None
                self.lock.wait()
            path = self.queue.popleft()
            self.queued.discard(path)
            return path

    def work(self):
        while True:
            path = self.next_path()
            if path is None:
                return
            key = self.key(path)
            if key is None:
                self.emit(path, None)
                continue
            colors = self.cache.get(key)
            if colors is None:
                if path.lower().endswith(VIDEO):
                    self.emit(path, None)
                    continue
                colors = scheme(path, self.args.type, self.args.mode)
                if _stopping.is_set():
                    return
                if colors:
                    self.cache[key] = colors
                    with self.lock:
                        self.dirty += 1
                        flush = self.dirty >= FLUSH_EVERY
                        if flush:
                            self.dirty = 0
                    if flush:
                        self.save()
            self.emit(path, colors)

    def run(self):
        threads = [threading.Thread(target=self.work, daemon=True) for _ in range(self.args.workers)]
        for t in threads:
            t.start()
        for line in sys.stdin:
            paths = [p for p in line.rstrip("\n").split("\t") if p]
            if paths:
                self.prioritise(paths)
        with self.lock:
            self.closed = True
            self.queue.clear()
            self.lock.notify_all()
        for t in threads:
            t.join()
        self.save()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache", required=True)
    parser.add_argument("--type", default="")
    parser.add_argument("--mode", default="")
    parser.add_argument("--workers", type=int, default=2)
    args = parser.parse_args()
    try:
        os.nice(10)  # a background job: never compete with the desktop
    except OSError:
        pass
    global _worker
    _worker = Worker(args)
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, _on_term)
    _worker.run()


if __name__ == "__main__":
    main()
