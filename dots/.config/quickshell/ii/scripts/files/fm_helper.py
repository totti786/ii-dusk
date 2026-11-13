#!/usr/bin/env python3
"""Backend for the ii file manager.

A long-lived helper that speaks JSON lines on stdin/stdout. Every request is
``{"id": N, "op": "...", ...}``; replies are ``{"id": N, "event": "result"|"error"|"progress"|...}``.
Unsolicited events carry no id (``changed``, ``devices``).  Slow work runs on worker
threads so a big copy never blocks listing a folder.

Nothing here touches a path the caller did not name; destructive operations
(delete, replace) only happen on explicit request.
"""
from __future__ import annotations

import ctypes
import errno
import fnmatch
import json
import os
import re
import shlex
import shutil
import signal
import stat as statmod
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any, Callable

try:
    import gi

    gi.require_version("Gio", "2.0")
    from gi.repository import Gio  # type: ignore
except Exception:  # pragma: no cover - the helper still works, with extension-only types
    Gio = None  # type: ignore

import mimetypes

HOME = Path(os.environ.get("HOME", "/")).resolve()
TRASH = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")) / "Trash"
UCA = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "Thunar" / "uca.xml"
ACCELS = UCA.with_name("accels.scm")
BOOKMARKS = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "gtk-3.0" / "bookmarks"
THUMBS = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")) / "thumbnails"

_out_lock = threading.Lock()


def send(obj: dict) -> None:
    line = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
    with _out_lock:
        try:
            sys.stdout.write(line + "\n")
            sys.stdout.flush()
        except BrokenPipeError:
            os._exit(0)


# ───────────────────────── file types ─────────────────────────

CODE_EXT = {
    "py", "js", "ts", "tsx", "jsx", "c", "h", "cc", "cpp", "hpp", "rs", "go", "java", "kt", "lua", "sh", "bash",
    "zsh", "fish", "qml", "css", "scss", "html", "htm", "xml", "json", "yaml", "yml", "toml", "ini", "conf",
    "sql", "rb", "php", "cs", "swift", "vue", "svelte", "nix", "cmake", "mk", "diff", "patch",
}
ARCHIVE_MIME = {
    "application/zip", "application/x-tar", "application/gzip", "application/x-7z-compressed", "application/x-rar",
    "application/vnd.rar", "application/x-xz", "application/zstd", "application/x-bzip2", "application/x-compressed-tar",
    "application/x-xz-compressed-tar", "application/x-zstd-compressed-tar", "application/x-bzip-compressed-tar",
    "application/x-cpio", "application/x-archive", "application/x-lzma", "application/x-iso9660-image",
    "application/x-cd-image", "application/vnd.debian.binary-package", "application/x-rpm", "application/java-archive",
}
ARCHIVE_EXT = (".tar.gz", ".tar.xz", ".tar.zst", ".tar.bz2", ".tgz", ".txz", ".zip", ".7z", ".rar", ".tar", ".iso")
TEXT_EXTRA = {"application/json", "application/xml", "application/x-shellscript", "application/javascript",
              "application/x-yaml", "application/toml", "application/x-desktop", "application/sql", "image/svg+xml"}


_SNIFF_BYTES = 4096
_SNIFF_CACHE: dict = {}
# Reading a file's head over a phone or network mount would stall a listing: those go by name.
_NO_SNIFF_PREFIXES = ("/run/user/", "/media/", "/mnt/")
GENERIC_MIME = {"application/octet-stream", "text/plain", "application/x-zerosize"}


CODE_MIME = {"text/x-python", "text/x-csrc", "text/x-chdr", "text/x-c++src", "text/x-c++hdr", "text/x-java",
             "text/x-script.python", "text/x-lua", "text/x-qml", "text/x-rust", "text/x-go", "text/html", "text/css",
             "text/javascript", "text/x-sql", "text/x-makefile", "text/x-cmake", "text/x-diff", "text/x-patch",
             "text/x-shellscript", "application/x-php", "application/x-ruby", "application/x-perl", "application/x-sh"}
BOOK_MIME = {"application/x-mobipocket-ebook", "image/vnd.djvu", "application/vnd.comicbook+zip",
             "application/vnd.comicbook-rar", "application/x-cbz", "application/x-cbr"}
EXEC_MIME = {"application/x-executable", "application/x-pie-executable", "application/x-sharedlib",
             "application/x-mach-binary", "application/vnd.microsoft.portable-executable", "application/x-msdownload"}


def guess_mime(name: str, is_dir: bool, path: str | None = None, st: os.stat_result | None = None) -> str:
    """The file's type from its content (the shared-mime-info magic) together with its name, so a
    picture saved as `photo.dat` is an image and a `.jpg` that is really a PNG is a PNG. Falls back to
    the name alone when the file cannot be read."""
    if is_dir:
        return "inode/directory"
    if Gio is not None:
        data = None
        if path and st is not None and statmod.S_ISREG(st.st_mode) and st.st_size > 0 \
                and not path.startswith(_NO_SNIFF_PREFIXES):
            key = (path, st.st_mtime_ns, st.st_size)
            hit = _SNIFF_CACHE.get(key)
            if hit is not None:
                return hit
            try:
                with open(path, "rb") as f:
                    data = f.read(_SNIFF_BYTES)
            except OSError:
                data = None
        mime = None
        try:
            by_name = Gio.content_type_guess(name, None)[0]
            if data is None:
                mime = by_name
            else:
                by_content = Gio.content_type_guess(None, data)[0]
                if by_content in GENERIC_MIME:
                    mime = Gio.content_type_guess(name, data)[0]  # text and the like: the name tells which
                elif by_name in GENERIC_MIME or Gio.content_type_is_a(by_name, by_content):
                    mime = by_name if by_name not in GENERIC_MIME else by_content  # .docx inside a zip
                elif Gio.content_type_is_a(by_content, "text/plain") and Gio.content_type_is_a(by_name, "text/plain"):
                    mime = by_name  # two kinds of text: the magic is a guess (a `//` comment looks like TypeScript), the name is not
                else:
                    mime = by_content  # the content disagrees with the name: the content wins
        except Exception:
            mime = None
        if mime:
            if data is not None:
                if len(_SNIFF_CACHE) > 50000:
                    _SNIFF_CACHE.clear()
                _SNIFF_CACHE[(path, st.st_mtime_ns, st.st_size)] = mime
            return mime
    return mimetypes.guess_type(name)[0] or "application/octet-stream"


def kind_of(name: str, mime: str, is_dir: bool, mode: int = 0) -> str:
    """A coarse category the UI maps to an icon and a colour. The file's type decides; its name
    only breaks the tie when the type is generic (plain text, unknown binary)."""
    if is_dir:
        return "folder"
    low = name.lower()
    ext = low.rsplit(".", 1)[-1] if "." in low else ""
    generic = mime in GENERIC_MIME
    if mime.startswith("image/"):
        return "image"
    if mime.startswith("video/"):
        return "video"
    if mime.startswith("audio/"):
        return "audio"
    if mime == "application/pdf":
        return "pdf"
    if mime in ARCHIVE_MIME or (generic and low.endswith(ARCHIVE_EXT)):
        return "archive"
    if mime in TEXT_EXTRA or (generic and ext in CODE_EXT) or mime in CODE_MIME:
        return "code"
    if "spreadsheet" in mime or "ms-excel" in mime or mime == "text/csv" or (generic and ext in ("xlsx", "xls", "ods", "csv")):
        return "sheet"
    if mime.startswith("text/"):
        return "text"
    if "presentation" in mime or "ms-powerpoint" in mime or (generic and ext in ("pptx", "ppt", "odp")):
        return "slides"
    if "wordprocessing" in mime or "msword" in mime or mime == "application/rtf" or (generic and ext in ("docx", "doc", "odt", "rtf")):
        return "doc"
    if "epub" in mime or mime in BOOK_MIME or (generic and ext in ("epub", "mobi", "azw3", "djvu", "cbz", "cbr")):
        return "book"
    if mime.startswith("font/") or "font" in mime or (generic and ext in ("ttf", "otf", "woff", "woff2")):
        return "font"
    if mime in EXEC_MIME or (mode & 0o111 and generic):
        return "exec"
    return "file"


def type_class(name: str, mime: str, is_dir: bool) -> str:
    """Thunar's custom-action categories: directories, image, audio, video, text, other."""
    if is_dir:
        return "directories"
    if mime.startswith("image/") and mime != "image/svg+xml":
        return "image-files"
    if mime.startswith("audio/"):
        return "audio-files"
    if mime.startswith("video/"):
        return "video-files"
    if mime.startswith("text/") or mime in TEXT_EXTRA or kind_of(name, mime, False) in ("code", "text"):
        return "text-files"
    return "other-files"


# ───────────────────────── listing ─────────────────────────

def entry_for(path: str, name: str | None = None, st: os.stat_result | None = None) -> dict:
    name = name if name is not None else os.path.basename(path)
    try:
        lst = os.lstat(path)
    except OSError:
        return {"name": name, "path": path, "isDir": False, "isLink": False, "size": 0, "mtime": 0, "kind": "file",
                "mime": "application/octet-stream", "hidden": name.startswith("."), "mode": "", "broken": True}
    is_link = statmod.S_ISLNK(lst.st_mode)
    broken = False
    target = ""
    st = lst
    if is_link:
        try:
            target = os.readlink(path)
        except OSError:
            target = ""
        try:
            st = os.stat(path)
        except OSError:
            broken = True
    is_dir = statmod.S_ISDIR(st.st_mode)
    mime = guess_mime(name, is_dir, path, st)
    return {
        "name": name,
        "path": path,
        "isDir": is_dir,
        "isLink": is_link,
        "target": target,
        "broken": broken,
        "size": 0 if is_dir else st.st_size,
        "mtime": st.st_mtime,
        "mode": statmod.filemode(st.st_mode),
        "mime": mime,
        "kind": kind_of(name, mime, is_dir, st.st_mode),
        "hidden": name.startswith("."),
    }


def parse_trashinfo(info_path: Path) -> dict:
    out = {"orig": "", "deleted": ""}
    try:
        for line in info_path.read_text(errors="replace").splitlines():
            if line.startswith("Path="):
                out["orig"] = urllib.parse.unquote(line[5:])
            elif line.startswith("DeletionDate="):
                out["deleted"] = line[13:]
    except OSError:
        pass
    return out


_libc = ctypes.CDLL(None, use_errno=True)


def rename_noreplace(src: str, dst: str) -> None:
    """rename(2) that fails with FileExistsError instead of replacing whatever appeared at dst."""
    try:
        r = _libc.renameat2(-100, os.fsencode(src), -100, os.fsencode(dst), 1)  # AT_FDCWD, RENAME_NOREPLACE
    except AttributeError:
        r, e = -1, errno.ENOSYS
    else:
        e = ctypes.get_errno()
    if r == 0:
        return
    if e == errno.EEXIST:
        raise FileExistsError(e, os.strerror(e), dst)
    if e in (errno.ENOSYS, errno.EINVAL, errno.ENOTSUP):  # a filesystem without the flag: best effort
        if os.path.lexists(dst):
            raise FileExistsError(errno.EEXIST, os.strerror(errno.EEXIST), dst)
        os.rename(src, dst)
        return
    raise OSError(e, os.strerror(e), dst)


def sync_fs(path: str) -> None:
    """Flush what was written to the filesystem holding path, so a drive can be pulled afterwards."""
    try:
        fd = os.open(path, os.O_RDONLY)
    except OSError:
        return
    try:
        if _libc.syncfs(fd) != 0:
            os.sync()
    except Exception:
        pass
    finally:
        os.close(fd)


def fmt_bytes(n: float) -> str:
    for u in ("B", "KiB", "MiB", "GiB", "TiB"):
        if n < 1024 or u == "TiB":
            return f"{n:.0f} {u}" if u == "B" else f"{n:.1f} {u}"
        n /= 1024
    return str(n)


_SKIP_FS = {"proc", "sysfs", "cgroup", "cgroup2", "devpts", "securityfs", "debugfs", "tracefs", "configfs", "fusectl",
            "bpf", "pstore", "mqueue", "hugetlbfs", "autofs", "binfmt_misc", "devtmpfs", "efivarfs", "overlay",
            "nfs", "nfs4", "cifs", "smb3", "sshfs", "fuse.sshfs", "fuse.gvfsd-fuse", "fuse.portal", "fuse.rclone"}


def mount_points() -> list[str]:
    """Mount points of local filesystems (where a per-drive trash can live); network and fuse mounts are left out so a hung one cannot stall a listing."""
    out = []
    try:
        for line in open("/proc/self/mounts"):
            parts = line.split()
            if len(parts) < 3 or parts[2] in _SKIP_FS or parts[2].startswith("fuse"):
                continue
            out.append(parts[1].replace("\\040", " "))
    except OSError:
        pass
    return out


def topdir_of(path: str) -> str:
    p = os.path.abspath(path)
    while not os.path.ismount(p):
        parent = os.path.dirname(p)
        if parent == p:
            break
        p = parent
    return p


def trash_roots() -> list[Path]:
    """The home trash and every per-drive trash (`.Trash-UID`, or `.Trash/UID`) that exists."""
    roots = [TRASH]
    uid = str(os.getuid())
    for mp in mount_points():
        if mp == "/":
            continue
        for cand in (Path(mp) / f".Trash-{uid}", Path(mp) / ".Trash" / uid):
            if (cand / "files").is_dir() and cand not in roots:
                roots.append(cand)
    return roots


def trash_root_of_file(path: str) -> Path | None:
    """The trash that holds `path` (a file inside some trash's `files` folder), if any."""
    p = Path(os.path.abspath(path))
    if p.parent.name != "files":
        return None
    root = p.parent.parent
    return root if root in trash_roots() else None


def trash_topdir(root: Path) -> Path | None:
    if root == TRASH:
        return None
    return root.parent if root.name.startswith(".Trash-") else root.parent.parent


def trash_orig(root: Path, raw: str) -> str:
    if raw and not raw.startswith("/"):
        top = trash_topdir(root)
        if top is not None:
            return str(top / raw)
    return raw


def list_trash() -> list[dict]:
    out = []
    for root in trash_roots():
        files = root / "files"
        info = root / "info"
        if not files.is_dir():
            continue
        for e in os.scandir(files):
            d = entry_for(e.path, e.name)
            meta = parse_trashinfo(info / (e.name + ".trashinfo"))
            d["origPath"] = trash_orig(root, meta["orig"])
            d["deleted"] = meta["deleted"]
            out.append(d)
    return out


def op_list(req: dict, job: Job | None = None) -> dict:
    path = req["path"]
    if path in ("trash:///", "trash://", "trash:"):
        ents = list_trash()
        return {"path": "trash:///", "entries": ents, "trash": True, "icons": {m: icon_names(m) for m in {e["mime"] for e in ents}}}
    if path.startswith("recent:"):
        ents = list_recent()
        return {"path": "recent:///", "entries": ents, "virtual": True, "writable": False, "icons": {m: icon_names(m) for m in {e["mime"] for e in ents}},
                "thumbable": [m for m in {e["mime"] for e in ents} if m in thumbnailers()]}
    if path.startswith("starred:"):
        ents = [entry_for(p) for p in meta_load().get("starred", []) if os.path.lexists(p)]
        return {"path": "starred:///", "entries": ents, "virtual": True, "writable": False, "icons": {m: icon_names(m) for m in {e["mime"] for e in ents}},
                "thumbable": [m for m in {e["mime"] for e in ents} if m in thumbnailers()]}
    p = os.path.abspath(os.path.expanduser(path))
    if not os.path.isdir(p):
        raise OSError(f"Not a folder: {p}")
    entries: list[dict] = []
    mimes: set[str] = set()
    streamed = False
    sent = 0
    with os.scandir(p) as it:
        for e in it:
            if job is not None and job.cancelled.is_set():
                raise Cancelled()
            ent = entry_for(e.path, e.name)
            entries.append(ent)
            mimes.add(ent["mime"])
            # A huge folder shows up while it is still being read instead of all at once
            if job is not None and len(entries) - sent >= 800 and len(entries) >= 1600:
                send({"id": req["id"], "event": "partial", "entries": entries[sent:],
                      "thumbable": [m for m in mimes if m in thumbnailers()], "icons": {m: icon_names(m) for m in mimes}})
                sent = len(entries)
                streamed = True
    try:
        du = shutil.disk_usage(p)
        free, total = du.free, du.total
    except OSError:
        free = total = 0
    return {"path": p, "entries": entries[sent:], "streamed": streamed, "free": free, "total": total,
            "writable": os.access(p, os.W_OK),
            "icons": {m: icon_names(m) for m in mimes},
            "thumbable": [m for m in mimes if m in thumbnailers()]}


# ───────────────────────── jobs, cancel, conflicts ─────────────────────────

class Job:
    def __init__(self, jid: int):
        self.id = jid
        self.cancelled = threading.Event()
        self.resolution: dict | None = None
        self.resolved = threading.Event()
        self.apply_all: str | None = None


jobs: dict[int, Job] = {}


class Cancelled(Exception):
    pass


def unique_name(directory: str, name: str, suffix_style: str = "copy") -> str:
    """`name (copy).ext`, `name (copy 2).ext` ... that does not exist in `directory`."""
    stem, ext = split_ext(name)
    n = 0
    while True:
        n += 1
        tag = " (copy)" if n == 1 else f" (copy {n})"
        cand = f"{stem}{tag}{ext}"
        if not os.path.lexists(os.path.join(directory, cand)):
            return cand


def split_ext(name: str) -> tuple[str, str]:
    low = name.lower()
    for double in (".tar.gz", ".tar.xz", ".tar.zst", ".tar.bz2", ".tar.lz"):
        if low.endswith(double):
            return name[: -len(double)], name[-len(double):]
    if name.startswith(".") and name.count(".") == 1:
        return name, ""
    stem, dot, ext = name.rpartition(".")
    if not dot or not stem:
        return name, ""
    return stem, "." + ext


def tree_size(path: str, job: Job | None = None) -> tuple[int, int, int]:
    """(bytes, files, folders) under path, not following symlinks."""
    size = files = folders = 0
    stack = [path]
    while stack:
        cur = stack.pop()
        if job and job.cancelled.is_set():
            raise Cancelled()
        try:
            st = os.lstat(cur)
        except OSError:
            continue
        if statmod.S_ISDIR(st.st_mode):
            folders += 1
            try:
                with os.scandir(cur) as it:
                    stack.extend(e.path for e in it)
            except OSError:
                pass
        else:
            files += 1
            size += st.st_size
    return size, files, folders


class Transfer:
    """Copies or moves a list of paths into a folder with progress, conflicts and cancel."""

    CHUNK = 4 * 1024 * 1024

    def __init__(self, job: Job, mode: str, srcs: list[str], dest: str, op_id: int, names: dict | None = None):
        self.job, self.mode, self.srcs, self.dest, self.rid = job, mode, srcs, dest, op_id
        self.names = names or {}  # source path -> the name it takes in dest (undo of a renamed move)
        self.replaced: list[dict] = []  # originals put in the trash to make room, {src: where it was, dst: in trash}
        self.skipped = 0  # sockets, devices... that cannot be copied
        self.failed = 0  # items that could not be copied inside a folder
        self.copied = 0  # bytes actually written
        self.total = 0
        self.done = 0
        self.last_emit = 0.0
        self.current = ""
        self.errors: list[str] = []
        self.results: list[dict] = []  # {src, dst} pairs of what was created, for undo
        self.started = time.monotonic()

    def emit(self, force: bool = False) -> None:
        now = time.monotonic()
        if not force and now - self.last_emit < 0.12:
            return
        self.last_emit = now
        elapsed = max(0.001, now - self.started)
        send({"id": self.rid, "event": "progress", "done": self.done, "total": self.total,
              "current": self.current, "speed": self.done / elapsed})

    def ask(self, src: str, dst: str, mismatch: bool = False) -> str:
        """Returns replace, skip or rename (and a new name through self.rename_to).

        `mismatch` means a folder is on one side and something else on the other. Replacing
        would delete a whole folder for a file (or the reverse), so it is never offered, and a
        remembered "replace for all" does not apply to it.
        """
        self.rename_to = None
        if self.job.apply_all and not (mismatch and self.job.apply_all == "replace"):
            return self.job.apply_all
        self.job.resolved.clear()
        self.job.resolution = None
        send({"id": self.rid, "event": "conflict", "src": entry_for(src), "dst": entry_for(dst), "mismatch": mismatch})
        while not self.job.resolved.wait(0.2):
            if self.job.cancelled.is_set():
                raise Cancelled()
        res = self.job.resolution or {"action": "cancel"}
        if res["action"] == "cancel":
            raise Cancelled()
        if mismatch and res["action"] == "replace":
            res = {**res, "action": "rename", "all": False}
        if res.get("all") and res["action"] in ("replace", "skip", "rename"):
            self.job.apply_all = res["action"]
        self.rename_to = res.get("name")
        return res["action"]

    rename_to: str | None = None

    def run(self) -> dict:
        need = 0
        clash = False
        try:
            for s in self.srcs:
                name = self.names.get(s) or os.path.basename(s.rstrip("/"))
                clash = clash or os.path.lexists(os.path.join(self.dest, name))
                if self.mode == "copy" or not self.same_fs(s):
                    size = tree_size(s, self.job)[0]
                    need += size
                    self.total += size
                else:
                    self.total += 1
        except Cancelled:
            return {"ok": False, "cancelled": True, "errors": [], "results": []}
        self.total = max(self.total, 1)
        if need > 0 and not clash:  # a clash may replace bytes already there, so only a clean copy is judged up front
            try:
                free = shutil.disk_usage(self.dest).free
            except OSError:
                free = need
            if need > free:
                raise OSError(f"Not enough space: {fmt_bytes(need)} needed, {fmt_bytes(free)} free")
        try:
            for s in self.srcs:
                self.check()
                name = self.names.get(s) or os.path.basename(s.rstrip("/"))
                self.place(s, os.path.join(self.dest, name), top=True)
        except Cancelled:
            self.emit(True)
            return {"ok": False, "cancelled": True, "errors": self.errors, "results": self.results, "replaced": self.replaced}
        if self.copied > 0:
            self.current = "Writing to disk"
            self.emit(True)
            sync_fs(self.dest)
        self.done = self.total
        self.emit(True)
        return {"ok": not self.errors, "errors": self.errors, "results": self.results, "replaced": self.replaced}

    def same_fs(self, src: str) -> bool:
        try:
            return os.stat(src).st_dev == os.stat(self.dest).st_dev
        except OSError:
            return False

    def check(self) -> None:
        if self.job.cancelled.is_set():
            raise Cancelled()

    def place(self, src: str, dst: str, top: bool = False) -> None:
        """Put src at dst, resolving a clash. `top` marks the items the user picked."""
        self.check()
        self.current = os.path.basename(src)
        same_place = os.path.abspath(src) == os.path.abspath(dst) or self.same_file(src, dst)
        if same_place:
            if self.mode == "move":
                return
            dst = os.path.join(os.path.dirname(dst), unique_name(os.path.dirname(dst), os.path.basename(dst)))
        elif os.path.lexists(dst):
            src_dir = self.is_real_dir(src)
            dst_dir = self.is_real_dir(dst)
            if src_dir and dst_dir:
                self.merge(src, dst)
                return
            act = self.ask(src, dst, mismatch=src_dir != dst_dir)
            if act == "skip":
                self.done += self.size_hint(src)
                return
            if act == "rename":
                new = self.rename_to or unique_name(os.path.dirname(dst), os.path.basename(dst))
                dst = os.path.join(os.path.dirname(dst), new)
                if os.path.lexists(dst):
                    dst = os.path.join(os.path.dirname(dst), unique_name(os.path.dirname(dst), os.path.basename(dst)))
            elif act == "replace":
                # The original goes to the trash so Undo can bring it back. Without a trash
                # a plain file still lands through a temp file and an atomic replace; only a
                # link or a special file is removed first, and never a folder.
                kept = None
                if not self.is_real_dir(dst):
                    try:
                        kept = trash_one(dst)
                    except OSError:
                        kept = None
                if kept:
                    self.replaced.append({"src": dst, "dst": kept["dst"]})
                elif not (os.path.isfile(dst) and not os.path.islink(dst) and os.path.isfile(src) and not os.path.islink(src)):
                    self.remove(dst)
        try:
            if self.mode == "move" and self.same_fs(src):
                os.rename(src, dst)
                self.done += 1
                self.results.append({"src": src, "dst": dst})
                self.emit()
                return
            before = (self.failed, self.skipped)
            self.copy_any(src, dst)
            self.results.append({"src": src, "dst": dst})
            if self.mode == "move":
                if (self.failed, self.skipped) != before:
                    self.errors.append(f"{os.path.basename(src)}: some items could not be copied, so the original stays")
                else:
                    self.remove(src, "src")
        except Cancelled:
            raise
        except OSError as e:
            self.errors.append(f"{os.path.basename(src)}: {e.strerror or e}")

    @staticmethod
    def is_real_dir(path: str) -> bool:
        """A folder itself, not a link to one."""
        return os.path.isdir(path) and not os.path.islink(path)

    @staticmethod
    def same_file(a: str, b: str) -> bool:
        """The same entry reached through two paths (a folder that is a symlink or a bind mount).
        Parents are resolved, the name is not, so a link and its target stay different."""
        try:
            pa = os.path.join(os.path.realpath(os.path.dirname(a)), os.path.basename(a))
            pb = os.path.join(os.path.realpath(os.path.dirname(b)), os.path.basename(b))
            return pa == pb
        except OSError:
            return False

    def size_hint(self, src: str) -> int:
        try:
            return tree_size(src)[0] if self.mode == "copy" or not self.same_fs(src) else 1
        except Cancelled:
            return 0

    def merge(self, src: str, dst: str) -> None:
        try:
            names = os.listdir(src)
        except OSError as e:
            self.errors.append(f"{os.path.basename(src)}: {e.strerror or e}")
            return
        for n in names:
            self.place(os.path.join(src, n), os.path.join(dst, n))
        if self.mode == "move":
            try:
                os.rmdir(src)
            except OSError:
                pass

    def remove(self, path: str, what: str = "dst") -> None:
        if self.is_real_dir(path):
            if what == "dst":
                raise OSError(f"{os.path.basename(path)}: refusing to delete a folder to make room")
            shutil.rmtree(path)
        else:
            os.unlink(path)

    def copy_any(self, src: str, dst: str) -> None:
        self.check()
        if os.path.islink(src):
            os.symlink(os.readlink(src), dst)
            return
        if os.path.isdir(src):
            os.makedirs(dst, exist_ok=True)
            for n in os.listdir(src):
                try:
                    self.copy_any(os.path.join(src, n), os.path.join(dst, n))
                except Cancelled:
                    raise
                except OSError as e:
                    self.failed += 1
                    self.errors.append(f"{n}: {e.strerror or e}")
            try:
                shutil.copystat(src, dst)
            except OSError:
                pass
            return
        mode = os.stat(src).st_mode
        if statmod.S_ISFIFO(mode):
            os.mkfifo(dst, statmod.S_IMODE(mode))
            return
        if not statmod.S_ISREG(mode):
            self.skipped += 1  # sockets and devices are not copied
            return
        tmp = dst + ".part"
        k = 1
        while os.path.lexists(tmp):
            k += 1
            tmp = f"{dst}.{k}.part"
        try:
            with open(src, "rb") as fi, open(tmp, "wb") as fo:
                while True:
                    self.check()
                    buf = fi.read(self.CHUNK)
                    if not buf:
                        break
                    fo.write(buf)
                    self.done += len(buf)
                    self.copied += len(buf)
                    self.emit()
            shutil.copystat(src, tmp)
            os.replace(tmp, dst)
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise


# ───────────────────────── trash ─────────────────────────

def drive_trash(path: str) -> Path | None:
    """The trash folder for a path that is not on the home drive (made on first use), or None."""
    top = topdir_of(path)
    uid = str(os.getuid())
    shared = Path(top) / ".Trash"
    try:
        st = os.lstat(shared)
        if statmod.S_ISDIR(st.st_mode) and st.st_mode & statmod.S_ISVTX and not statmod.S_ISLNK(st.st_mode):
            root = shared / uid
            root.mkdir(mode=0o700, exist_ok=True)
            return root
    except OSError:
        pass
    root = Path(top) / f".Trash-{uid}"
    try:
        root.mkdir(mode=0o700, exist_ok=True)
        return root
    except OSError:
        return None


def trash_one(path: str) -> dict | None:
    """Move to the trash of the drive the path is on (freedesktop spec)."""
    path = os.path.abspath(path)
    TRASH.mkdir(parents=True, exist_ok=True)
    try:
        home_dev = os.stat(TRASH).st_dev
        same = os.lstat(path).st_dev == home_dev
    except OSError as e:
        raise OSError(f"{os.path.basename(path)}: {e.strerror}")
    root = TRASH
    stored = path
    if not same:
        root = drive_trash(path)
        if root is None:
            r = subprocess.run(["gio", "trash", path], capture_output=True, text=True)
            if r.returncode != 0:
                raise OSError(r.stderr.strip() or "could not move to the trash")
            return None
        stored = os.path.relpath(path, trash_topdir(root) if root.name.startswith(".Trash-") else root.parent.parent)
    files = root / "files"
    info = root / "info"
    files.mkdir(parents=True, exist_ok=True)
    info.mkdir(parents=True, exist_ok=True)
    base = os.path.basename(path)
    name, n = base, 1
    while os.path.lexists(files / name) or os.path.lexists(info / (name + ".trashinfo")):
        n += 1
        stem, ext = split_ext(base)
        name = f"{stem}.{n}{ext}"
    quoted = urllib.parse.quote(stored, safe="/")
    (info / (name + ".trashinfo")).write_text(
        f"[Trash Info]\nPath={quoted}\nDeletionDate={time.strftime('%Y-%m-%dT%H:%M:%S')}\n")
    try:
        os.rename(path, files / name)
    except OSError:
        (info / (name + ".trashinfo")).unlink(missing_ok=True)
        raise
    return {"src": path, "dst": str(files / name)}


def op_trash(req: dict, job: Job) -> dict:
    results, errors = [], []
    for p in req["paths"]:
        if job.cancelled.is_set():
            break
        try:
            r = trash_one(p)
            if r:
                results.append(r)
        except OSError as e:
            errors.append(str(e))
    return {"ok": not errors, "errors": errors, "results": results}


def restore_one(path: str) -> dict:
    name = os.path.basename(path)
    root = trash_root_of_file(path) or TRASH
    info = root / "info" / (name + ".trashinfo")
    meta = parse_trashinfo(info)
    orig = trash_orig(root, meta["orig"])
    if not orig:
        raise OSError(f"{name}: original location unknown")
    os.makedirs(os.path.dirname(orig), exist_ok=True)
    dest = orig
    if os.path.lexists(dest):
        dest = os.path.join(os.path.dirname(orig), unique_name(os.path.dirname(orig), os.path.basename(orig)))
    shutil.move(path, dest)
    info.unlink(missing_ok=True)
    return {"src": path, "dst": dest}


def op_restore(req: dict, job: Job) -> dict:
    results, errors = [], []
    for p in req["paths"]:
        try:
            results.append(restore_one(p))
        except OSError as e:
            errors.append(str(e))
    return {"ok": not errors, "errors": errors, "results": results}


def op_empty_trash(req: dict, job: Job) -> dict:
    errors = []
    for root in trash_roots():
        for sub in ("files", "info"):
            d = root / sub
            if not d.is_dir():
                continue
            for e in os.scandir(d):
                if job.cancelled.is_set():
                    raise Cancelled()
                try:
                    if e.is_dir(follow_symlinks=False):
                        shutil.rmtree(e.path)
                    else:
                        os.unlink(e.path)
                except OSError as ex:
                    errors.append(f"{e.name}: {ex.strerror}")
        (root / "directorysizes").unlink(missing_ok=True)
    return {"ok": not errors, "errors": errors}


def op_delete(req: dict, job: Job) -> dict:
    errors = []
    for p in req["paths"]:
        if job.cancelled.is_set():
            break
        try:
            root = trash_root_of_file(p)
            if os.path.isdir(p) and not os.path.islink(p):
                shutil.rmtree(p)
            else:
                os.unlink(p)
            if root is not None:
                (root / "info" / (os.path.basename(p) + ".trashinfo")).unlink(missing_ok=True)
        except OSError as e:
            errors.append(f"{os.path.basename(p)}: {e.strerror or e}")
    return {"ok": not errors, "errors": errors}


# ───────────────────────── small file ops ─────────────────────────

def check_name(name: str) -> str:
    name = name.strip("\n")
    if not name or name in (".", "..") or "/" in name or "\0" in name:
        raise OSError("That name is not allowed")
    return name


def op_rename(req: dict, job: Job) -> dict:
    src = req["path"]
    new = check_name(req["name"])
    dst = os.path.join(os.path.dirname(src), new)
    if dst == src:
        return {"ok": True, "src": src, "dst": dst}
    try:
        rename_noreplace(src, dst)
    except FileExistsError:
        raise OSError(f"“{new}” already exists")
    return {"ok": True, "src": src, "dst": dst}


def op_mkdir(req: dict, job: Job) -> dict:
    dst = os.path.join(req["dir"], check_name(req["name"]))
    if os.path.lexists(dst):
        raise OSError(f"“{os.path.basename(dst)}” already exists")
    os.mkdir(dst)
    return {"ok": True, "dst": dst}


def op_newfile(req: dict, job: Job) -> dict:
    dst = os.path.join(req["dir"], check_name(req["name"]))
    fd = os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    os.close(fd)
    return {"ok": True, "dst": dst}


def op_symlink(req: dict, job: Job) -> dict:
    name = req.get("name") or ("Link to " + os.path.basename(req["target"]))
    dst = os.path.join(req["dir"], check_name(name))
    if os.path.lexists(dst):
        dst = os.path.join(req["dir"], unique_name(req["dir"], os.path.basename(dst)))
    os.symlink(req["target"], dst)
    return {"ok": True, "dst": dst}


def op_bulk_rename(req: dict, job: Job) -> dict:
    """pairs: [[path, newName]]; two-phase so swaps and shifted numbering work."""
    pairs = [(p, check_name(n)) for p, n in req["pairs"] if os.path.basename(p) != n]
    targets = [os.path.join(os.path.dirname(p), n) for p, n in pairs]
    if len(set(targets)) != len(targets):
        raise OSError("Two files would get the same name")
    srcs = {p for p, _ in pairs}
    for t in targets:
        if os.path.lexists(t) and t not in srcs:
            raise OSError(f"“{os.path.basename(t)}” already exists")
    staged = []
    try:
        for i, (p, n) in enumerate(pairs):
            tmp = os.path.join(os.path.dirname(p), f".fm-rename-{os.getpid()}-{i}")
            os.rename(p, tmp)
            staged.append((tmp, p, os.path.join(os.path.dirname(p), n)))
        for tmp, _, dst in staged:
            os.rename(tmp, dst)
    except OSError:
        for tmp, orig, _ in staged:
            if os.path.lexists(tmp):
                os.rename(tmp, orig)
        raise
    return {"ok": True, "results": [{"src": o, "dst": d} for _, o, d in staged]}


# ───────────────────────── properties ─────────────────────────

def op_props(req: dict, job: Job) -> dict:
    import grp
    import pwd

    paths = req["paths"]
    size = files = folders = 0
    last = 0.0
    for p in paths:
        s, f, d = 0, 0, 0
        stack = [p]
        while stack:
            if job.cancelled.is_set():
                raise Cancelled()
            cur = stack.pop()
            try:
                st = os.lstat(cur)
            except OSError:
                continue
            if statmod.S_ISDIR(st.st_mode):
                d += 1
                try:
                    with os.scandir(cur) as it:
                        stack.extend(e.path for e in it)
                except OSError:
                    pass
            else:
                f += 1
                s += st.st_size
            if time.monotonic() - last > 0.25:
                last = time.monotonic()
                send({"id": req["id"], "event": "progress", "size": size + s, "files": files + f, "folders": folders + d})
        size, files, folders = size + s, files + f, folders + d
    out: dict[str, Any] = {"size": size, "files": files, "folders": folders}
    first = paths[0]
    e = entry_for(first)
    try:
        st = os.stat(first)
        modes = set()
        for q in paths:
            try:
                modes.add(statmod.S_IMODE(os.stat(q).st_mode))
            except OSError:
                pass
        out["mixedPerms"] = len(modes) > 1
        out.update({
            "name": e["name"], "path": first, "mime": e["mime"], "kind": e["kind"], "isDir": e["isDir"],
            "isLink": e["isLink"], "target": e.get("target", ""),
            "perms": "" if len(modes) > 1 else oct(statmod.S_IMODE(st.st_mode) & 0o777)[2:].zfill(3), "modeStr": statmod.filemode(st.st_mode),
            "owner": pwd.getpwuid(st.st_uid).pw_name if st.st_uid in {p.pw_uid for p in pwd.getpwall()} else str(st.st_uid),
            "group": grp.getgrgid(st.st_gid).gr_name if st.st_gid in {g.gr_gid for g in grp.getgrall()} else str(st.st_gid),
            "mtime": st.st_mtime, "atime": st.st_atime, "ctime": st.st_ctime,
            "writable": os.access(first, os.W_OK), "executable": bool(st.st_mode & 0o111),
            "device": os.path.dirname(os.path.abspath(first)),
        })
        du = shutil.disk_usage(first if os.path.isdir(first) else os.path.dirname(first))
        out["free"], out["fsTotal"] = du.free, du.total
    except OSError as ex:
        out["error"] = str(ex)
    out["multiple"] = len(paths) > 1
    return out


def op_chmod(req: dict, job: Job) -> dict:
    """Set permissions. `recursive` applies them inside folders too, keeping files non-executable
    unless they already were (like chmod -R with X)."""
    mode = int(str(req["mode"]), 8)
    errors: list[str] = []

    def apply(p: str, top: bool) -> None:
        if job.cancelled.is_set():
            raise Cancelled()
        try:
            st = os.lstat(p)
            if statmod.S_ISLNK(st.st_mode):
                return
            isdir = statmod.S_ISDIR(st.st_mode)
            m = mode & 0o777
            if not top and not isdir and not (st.st_mode & 0o111):
                m &= ~0o111
            os.chmod(p, (st.st_mode & 0o7000) | m)  # setuid, setgid and sticky are not part of the 3 digits shown
            if isdir and req.get("recursive"):
                for n in os.listdir(p):
                    apply(os.path.join(p, n), False)
        except OSError as e:
            errors.append(f"{os.path.basename(p)}: {e.strerror or e}")

    for p in req["paths"]:
        apply(p, True)
    return {"ok": not errors, "errors": errors}


# ───────────────────────── folder sizes, duplicates, terminal ─────────────────────────

def dir_size(path: str, job: Job) -> int:
    """Bytes under a folder, staying on its filesystem and not following links."""
    try:
        rdev = os.lstat(path).st_dev
    except OSError:
        return 0
    size = 0
    stack = [path]
    seen: set[tuple[int, int]] = set()
    while stack:
        if job.cancelled.is_set():
            raise Cancelled()
        cur = stack.pop()
        try:
            with os.scandir(cur) as it:
                for e in it:
                    try:
                        st = e.stat(follow_symlinks=False)
                    except OSError:
                        continue
                    if st.st_dev != rdev:
                        continue
                    if statmod.S_ISDIR(st.st_mode):
                        stack.append(e.path)
                    else:
                        if st.st_nlink > 1:
                            key = (st.st_dev, st.st_ino)
                            if key in seen:
                                continue
                            seen.add(key)
                        size += st.st_size
        except OSError:
            continue
    return size


def op_dirsizes(req: dict, job: Job) -> dict:
    """Sizes of several folders, streamed as each one finishes (the list shows them as they arrive)."""
    batch: dict[str, int] = {}
    last = time.monotonic()
    for p in req["paths"]:
        batch[p] = dir_size(p, job)
        if time.monotonic() - last > 0.25:
            send({"id": req["id"], "event": "partial", "sizes": batch})
            batch, last = {}, time.monotonic()
    return {"sizes": batch}


def op_dupes(req: dict, job: Job) -> dict:
    """Files with identical content under a folder: group by size, then a head hash, then the full hash."""
    import hashlib
    root = os.path.abspath(os.path.expanduser(req["path"]))
    min_size = max(1, int(req.get("minSize") or 1))
    hidden = bool(req.get("hidden"))
    by_size: dict[int, list[str]] = {}
    seen_inodes: set[tuple[int, int]] = set()
    count = 0
    last = 0.0
    stack = [root]
    while stack:
        if job.cancelled.is_set():
            raise Cancelled()
        cur = stack.pop()
        try:
            with os.scandir(cur) as it:
                for e in it:
                    if not hidden and e.name.startswith("."):
                        continue
                    try:
                        st = e.stat(follow_symlinks=False)
                    except OSError:
                        continue
                    if statmod.S_ISDIR(st.st_mode):
                        stack.append(e.path)
                    elif statmod.S_ISREG(st.st_mode) and st.st_size >= min_size:
                        key = (st.st_dev, st.st_ino)
                        if key in seen_inodes:
                            continue  # a hard link of a file already seen is not a second copy
                        seen_inodes.add(key)
                        by_size.setdefault(st.st_size, []).append(e.path)
                        count += 1
        except OSError:
            continue
        if time.monotonic() - last > 0.3:
            last = time.monotonic()
            send({"id": req["id"], "event": "progress", "stage": "scan", "files": count})
    cands = {sz: ps for sz, ps in by_size.items() if len(ps) > 1}
    total = sum(sz * len(ps) for sz, ps in cands.items())
    done = 0

    def digest(path: str, limit: int | None) -> str | None:
        nonlocal done, last
        h = hashlib.sha256()
        read = 0
        try:
            with open(path, "rb") as fh:
                while True:
                    if job.cancelled.is_set():
                        raise Cancelled()
                    n = (1 << 20) if limit is None else min(1 << 16, limit - read)
                    if n <= 0:
                        break
                    buf = fh.read(n)
                    if not buf:
                        break
                    h.update(buf)
                    read += len(buf)
                    done += len(buf)
                    if time.monotonic() - last > 0.3:
                        last = time.monotonic()
                        send({"id": req["id"], "event": "progress", "stage": "hash", "done": done, "total": total})
                    if limit is not None and read >= limit:
                        break
        except OSError:
            return None
        return h.hexdigest()

    groups = []
    for sz, ps in cands.items():
        heads: dict[str, list[str]] = {}
        for p in ps:
            d = digest(p, 1 << 16)
            if d is not None:
                heads.setdefault(d, []).append(p)
        for same_head in heads.values():
            if len(same_head) < 2:
                continue
            if sz <= (1 << 16):
                full = {"": same_head}  # the head was the whole file
            else:
                full = {}
                for p in same_head:
                    d = digest(p, None)
                    if d is not None:
                        full.setdefault(d, []).append(p)
            for same in full.values():
                if len(same) > 1:
                    same.sort(key=lambda q: (os.path.getmtime(q), q))
                    groups.append({"size": sz, "paths": same})
    groups.sort(key=lambda g: -g["size"] * (len(g["paths"]) - 1))
    return {"groups": groups[:2000], "wasted": sum(g["size"] * (len(g["paths"]) - 1) for g in groups), "scanned": count}


def terminal_command() -> list[str]:
    wrapper = HOME / ".local/bin/terminal"
    if os.access(wrapper, os.X_OK):
        return [str(wrapper)]
    env = os.environ.get("TERMINAL")
    if env and shutil.which(shlex.split(env)[0]):
        return shlex.split(env)
    for t in ("alacritty", "kitty", "foot", "wezterm", "konsole", "gnome-terminal", "xterm"):
        if shutil.which(t):
            return [t]
    raise OSError("No terminal found")


def op_terminal(req: dict, job: Job) -> dict:
    """A terminal opened in a folder (a file's folder if a file is given)."""
    d = os.path.abspath(os.path.expanduser(req["dir"]))
    if not os.path.isdir(d):
        d = os.path.dirname(d)
    if not os.path.isdir(d):
        d = str(HOME)
    subprocess.Popen(terminal_command(), cwd=d, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    return {"ok": True}


def op_wallpaper(req: dict, job: Job) -> dict:
    script = Path(__file__).resolve().parent.parent / "colors" / "switchwall.sh"
    subprocess.Popen([str(script), "--set", req["path"]], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    return {"ok": True}


# ───────────────────────── search ─────────────────────────

_KIND_EXTS = {
    "image": "jpg jpeg png gif webp bmp svg avif heic tiff tif ico jxl",
    "video": "mp4 mkv webm avi mov m4v wmv flv ogv mpg mpeg",
    "audio": "mp3 flac ogg opus wav m4a aac wma aiff",
    "document": "pdf doc docx odt rtf txt md epub djvu xls xlsx ods csv ppt pptx odp",
    "archive": "zip 7z rar tar gz xz bz2 zst iso",
    "code": "py js ts jsx tsx qml c cpp h hpp rs go java kt sh lua json yaml yml toml html css",
}


def _kind_matches(kind: str, ent: dict) -> bool:
    if kind == "folder":
        return ent["isDir"]
    exts = _KIND_EXTS.get(kind)
    if not exts:
        return True
    return not ent["isDir"] and ent["name"].rpartition(".")[2].lower() in exts.split()


def op_search(req: dict, job: Job) -> dict:
    """Name search through fd, or file-content search through rg; filters narrow either."""
    root = os.path.abspath(os.path.expanduser(req["path"]))
    query = req.get("query", "")
    kind = req.get("kind") or ""
    days = int(req.get("days") or 0)
    min_mb = float(req.get("minMb") or 0)
    if req.get("content") and query and shutil.which("rg"):
        cmd = ["rg", "--files-with-matches", "--smart-case", "--fixed-strings", "--max-filesize", "5M",
               "--max-count", "1", "--no-messages"]
        # .gitignore and friends decide what a project builds, not what a person wants to find
        cmd += ["--no-ignore"]
        if req.get("hidden"):
            cmd += ["--hidden"]
        cmd += ["--", query, root]
    else:
        cmd = ["fd", "--color", "never", "--absolute-path", "--ignore-case", "--no-ignore", "--max-results", "3000"]
        if req.get("hidden"):
            cmd += ["--hidden"]
        else:
            cmd += ["--exclude", "node_modules", "--exclude", "__pycache__"]
        if kind == "folder":
            cmd += ["--type", "d"]
            min_mb = 0  # folders have no size to filter on
        elif kind in _KIND_EXTS:
            cmd += ["--type", "f"]
            for ext in _KIND_EXTS[kind].split():
                cmd += ["-e", ext]
        if days > 0:
            cmd += ["--changed-within", f"{days}d"]
        if min_mb > 0:
            cmd += ["--type", "f", "--size", f"+{int(min_mb)}m"]
        # *.png, report-??.pdf and [ab]*.txt are globs; anything else is a plain substring
        if any(c in query for c in "*?["):
            cmd += ["--glob", "--", query, root]
        else:
            cmd += ["--fixed-strings", "--", query, root]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, errors="replace")
    batch: list[dict] = []
    total = 0
    last = time.monotonic()
    assert proc.stdout is not None
    for line in proc.stdout:
        if job.cancelled.is_set():
            proc.kill()
            break
        p = line.rstrip("\n")
        if not p:
            continue
        ent = entry_for(p.rstrip("/"))
        if req.get("content") and kind and not _kind_matches(kind, ent):
            continue
        if req.get("content") and days > 0 and time.time() - ent["mtime"] > days * 86400:
            continue
        if req.get("content") and min_mb > 0 and ent["size"] < min_mb * 1e6:
            continue
        batch.append(ent)
        total += 1
        if len(batch) >= 50 or time.monotonic() - last > 0.2:
            send({"id": req["id"], "event": "partial", "entries": batch})
            batch, last = [], time.monotonic()
        if total >= 3000:
            proc.kill()
            break
    proc.wait()
    return {"entries": batch, "count": total, "cancelled": job.cancelled.is_set()}


# ───────────────────────── archives ─────────────────────────

def run_cancellable(cmd: list[str], job: Job, cwd: str | None = None, stdin: str | None = None) -> tuple[int, str]:
    """Run a tool, polling the job's cancel flag; returns (exit code, its last output)."""
    out = tempfile.TemporaryFile()
    proc = subprocess.Popen(cmd, cwd=cwd, stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
                            stdout=out, stderr=subprocess.STDOUT, start_new_session=True)
    if stdin is not None:
        try:
            assert proc.stdin is not None
            proc.stdin.write(stdin.encode())
            proc.stdin.close()
        except OSError:
            pass
    while True:
        try:
            rc = proc.wait(timeout=0.2)
            break
        except subprocess.TimeoutExpired:
            if job.cancelled.is_set():
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except OSError:
                    pass
                proc.wait()
                raise Cancelled()
    out.seek(0)
    return rc, out.read().decode("utf-8", "replace").strip()


def last_line(text: str, fallback: str) -> str:
    lines = [ln for ln in text.splitlines() if ln.strip()]
    return lines[-1] if lines else fallback


def op_compress(req: dict, job: Job) -> dict:
    paths = req["paths"]
    fmt = req.get("format", "zip")
    password = req.get("password") or ""
    parents = [os.path.dirname(p) for p in paths]
    base = os.path.commonpath(parents) if len(set(parents)) > 1 else parents[0]
    names = [os.path.relpath(p, base) for p in paths]
    stem = req.get("name") or (os.path.basename(paths[0]) if len(paths) == 1 else os.path.basename(base) or "archive")
    stem = split_ext(stem)[0] if len(paths) == 1 and not os.path.isdir(paths[0]) else stem
    dest_dir = req.get("dest") or base
    if not os.access(dest_dir, os.W_OK):
        dest_dir = str(HOME)
    out = os.path.join(dest_dir, f"{stem}.{fmt}")
    if os.path.lexists(out):
        out = os.path.join(dest_dir, unique_name(dest_dir, os.path.basename(out)))
    tmp = out + ".part"
    send({"id": req["id"], "event": "progress", "done": 0, "total": 0, "current": os.path.basename(out)})
    tar_flags = {"tar.gz": "z", "tar.xz": "J", "tar.bz2": "j", "tar.zst": "--zstd", "tar": ""}
    stdin = None
    if fmt in tar_flags:
        flag = tar_flags[fmt]
        cmd = ["tar", "-c" + (flag if len(flag) == 1 else ""), "-f", tmp] + ([flag] if len(flag) > 1 else []) + ["--"] + names
    else:
        kind = "-tzip" if fmt == "zip" else "-t7z"
        cmd = ["7z", "a", kind, "-bd", "-y"]
        if password:
            cmd += ["-p", "-mem=AES256"] if fmt == "zip" else ["-p", "-mhe=on"]
            stdin = f"{password}\n{password}\n"
        cmd += [tmp, "--"] + names
    try:
        rc, text = run_cancellable(cmd, job, cwd=base, stdin=stdin)
        if rc != 0:
            raise OSError(last_line(text, "compression failed"))
        os.replace(tmp, out)
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass
    return {"ok": True, "dst": out}


_PASSWORD_HINTS = ("wrong password", "encrypted", "passphrase", "enter password", "can not open encrypted")


def op_extract(req: dict, job: Job) -> dict:
    arc = req["path"]
    base = os.path.dirname(arc)
    stem = split_ext(os.path.basename(arc))[0]
    here = req.get("here", False)
    password = req.get("password") or ""
    parent = req.get("dest") or base
    if not os.access(parent, os.W_OK):
        raise OSError("This folder is read-only")
    send({"id": req["id"], "event": "progress", "done": 0, "total": 0, "current": os.path.basename(arc)})
    tmp = tempfile.mkdtemp(prefix=".fm-extract-", dir=parent)
    try:
        if shutil.which("bsdtar") and not password:
            rc, text = run_cancellable(["bsdtar", "-xf", arc, "-C", tmp], job)
        else:
            # 7z takes the password of an extraction on its command line only (it cannot read it from a pipe)
            rc, text = run_cancellable(["7z", "x", "-y", "-bd"] + ([f"-p{password}"] if password else []) + [f"-o{tmp}", arc], job)
        if rc != 0:
            if any(h in text.lower() for h in _PASSWORD_HINTS):
                return {"ok": False, "password": True, "wrong": bool(password)}
            raise OSError(last_line(text, "extraction failed"))
        children = sorted(os.listdir(tmp))
        if here:
            t = Transfer(job, "move", [os.path.join(tmp, c) for c in children], parent, req["id"])
            res = t.run()
            if res.get("cancelled"):
                return {"ok": False, "cancelled": True}
            first = res["results"][0]["dst"] if res.get("results") else parent
            return {"ok": res["ok"], "errors": res["errors"], "dst": first}
        dest = os.path.join(parent, stem)
        if os.path.lexists(dest):
            dest = os.path.join(parent, unique_name(parent, stem))
        if len(children) == 1 and os.path.isdir(os.path.join(tmp, children[0])) and not os.path.islink(os.path.join(tmp, children[0])):
            # one top-level folder: use it as the result rather than nesting foo/foo
            if children[0] != stem and not os.path.lexists(os.path.join(parent, children[0])):
                dest = os.path.join(parent, children[0])
            os.rename(os.path.join(tmp, children[0]), dest)
        else:
            os.rename(tmp, dest)
            tmp = ""
        return {"ok": True, "dst": dest}
    finally:
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)


# ───────────────────────── open with ─────────────────────────

def op_apps(req: dict, job: Job) -> dict:
    mime = req["mime"]
    out = []
    if Gio is None:
        return {"apps": out}
    default = Gio.AppInfo.get_default_for_type(mime, False)
    seen = set()
    infos = list(Gio.AppInfo.get_all_for_type(mime))
    if default:
        infos.insert(0, default)
    for a in infos:
        aid = a.get_id()
        if aid in seen or not a.should_show():
            continue
        seen.add(aid)
        icon = a.get_icon()
        names = icon.get_names() if icon is not None and hasattr(icon, "get_names") else []
        out.append({"id": aid, "name": a.get_display_name(), "icon": names[0] if names else "",
                    "default": bool(default and default.get_id() == aid)})
    return {"apps": out}


def op_all_apps(req: dict, job: Job) -> dict:
    out = []
    if Gio is not None:
        for a in Gio.AppInfo.get_all():
            if not a.should_show():
                continue
            icon = a.get_icon()
            names = icon.get_names() if icon is not None and hasattr(icon, "get_names") else []
            out.append({"id": a.get_id(), "name": a.get_display_name(), "icon": names[0] if names else ""})
    out.sort(key=lambda a: a["name"].lower())
    return {"apps": out}


def op_open(req: dict, job: Job) -> dict:
    paths = req["paths"]
    app = req.get("app")
    if app and Gio is not None:
        info = Gio.DesktopAppInfo.new(app)
        if info is None:
            raise OSError("That app is not installed")
        info.launch_uris([Gio.File.new_for_path(p).get_uri() for p in paths], None)
        return {"ok": True}
    for p in paths:
        subprocess.Popen(["gio", "open", p], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    return {"ok": True}


def op_set_default_app(req: dict, job: Job) -> dict:
    r = subprocess.run(["xdg-mime", "default", req["app"], req["mime"]], capture_output=True, text=True)
    if r.returncode != 0:
        raise OSError(r.stderr.strip() or "could not set the default")
    return {"ok": True}


# ───────────────────────── places, bookmarks, devices ─────────────────────────

def user_dirs() -> dict[str, str]:
    out: dict[str, str] = {}
    f = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "user-dirs.dirs"
    try:
        for line in f.read_text().splitlines():
            m = re.match(r'XDG_(\w+)_DIR="(.*)"', line.strip())
            if m:
                out[m.group(1)] = m.group(2).replace("$HOME", str(HOME)).rstrip("/") or str(HOME)
    except OSError:
        pass
    # xdg-user-dirs writes "$HOME/" for a folder it considers disabled, which would make Documents,
    # Downloads and the rest all point at Home: fall back to the conventional folder when it exists
    for key, default in (("DESKTOP", "Desktop"), ("DOCUMENTS", "Documents"), ("DOWNLOAD", "Downloads"),
                         ("MUSIC", "Music"), ("PICTURES", "Pictures"), ("VIDEOS", "Videos")):
        if out.get(key, str(HOME)) == str(HOME) and (HOME / default).is_dir():
            out[key] = str(HOME / default)
    return out


def read_bookmarks() -> list[dict]:
    out = []
    try:
        for line in BOOKMARKS.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            uri, _, label = line.partition(" ")
            if not uri.startswith("file://"):
                continue
            path = urllib.parse.unquote(uri[7:])
            out.append({"path": path, "name": label or os.path.basename(path) or path, "exists": os.path.exists(path)})
    except OSError:
        pass
    return out


def write_bookmarks(items: list[dict]) -> None:
    BOOKMARKS.parent.mkdir(parents=True, exist_ok=True)
    lines = []
    for b in items:
        uri = "file://" + urllib.parse.quote(b["path"], safe="/")
        label = b.get("name") or ""
        default = os.path.basename(b["path"])
        lines.append(uri + (f" {label}" if label and label != default else ""))
    tmp = BOOKMARKS.with_suffix(".tmp")
    tmp.write_text("\n".join(lines) + ("\n" if lines else ""))
    os.replace(tmp, BOOKMARKS)


def op_places(req: dict, job: Job) -> dict:
    ud = user_dirs()
    standard = [("Home", str(HOME), "home")]
    for key, label, icon in (("DESKTOP", "Desktop", "desktop_windows"), ("DOCUMENTS", "Documents", "description"),
                             ("DOWNLOAD", "Downloads", "download"), ("MUSIC", "Music", "library_music"),
                             ("PICTURES", "Pictures", "image"), ("VIDEOS", "Videos", "movie")):
        p = ud.get(key)
        if p and os.path.isdir(p) and p != str(HOME):
            standard.append((label, p, icon))
    places = [{"name": n, "path": p, "icon": i} for n, p, i in standard]
    std_paths = {p["path"] for p in places}
    marks = [b for b in read_bookmarks() if b["exists"] and b["path"] not in std_paths]
    trash_count = 0
    for root in trash_roots():
        try:
            trash_count += len(os.listdir(root / "files"))
        except OSError:
            pass
    return {"places": places, "bookmarks": marks, "trashCount": trash_count}


def op_bookmark(req: dict, job: Job) -> dict:
    items = read_bookmarks()
    path = req["path"]
    if req.get("remove"):
        items = [b for b in items if b["path"] != path]
    elif not any(b["path"] == path for b in items):
        items.append({"path": path, "name": req.get("name") or os.path.basename(path)})
    elif req.get("name"):
        for b in items:
            if b["path"] == path:
                b["name"] = req["name"]
    write_bookmarks(items)
    return {"ok": True}


def _size_label(n: int) -> str:
    for unit, div in (("TB", 1e12), ("GB", 1e9), ("MB", 1e6)):
        if n >= div:
            v = n / div
            return f"{v:.0f} {unit}" if v >= 10 or unit == "MB" else f"{v:.1f} {unit}"
    return f"{n} B"


_FS_NAMES = {"ntfs": "NTFS", "vfat": "FAT32", "exfat": "exFAT", "ext4": "ext4", "btrfs": "Btrfs", "xfs": "XFS", "f2fs": "F2FS", "iso9660": "Disc"}


def _device_name(n: dict, parent: dict | None, removable: bool, mp: str) -> tuple[str, str]:
    """A readable title and a one-line detail for a block device."""
    fs = n.get("fstype") or ""
    size = int(n.get("size") or 0)
    fsname = _FS_NAMES.get(fs, fs.upper())
    label = (n.get("label") or "").strip()
    part = (n.get("partlabel") or "").strip()
    model = ((parent or n).get("model") or "").strip().replace("_", " ")
    if mp == "/":
        title = label or "System"
    elif mp == "/home":
        title = label or "Home partition"
    elif label:
        title = label
    elif part and part.lower() not in ("basic data partition", "linux filesystem", "linux data"):
        title = part
    elif fs in ("ntfs", "exfat") and not removable:
        title = "Windows drive"
    elif removable:
        title = model or "Removable drive"
    elif model:
        title = f"{model} ({_size_label(size)})"
    else:
        title = f"{fsname} volume"
    detail = " · ".join(x for x in (_size_label(size), fsname) if x)
    return title, detail


def op_devices(req: dict, job: Job) -> dict:
    r = subprocess.run(["lsblk", "-J", "-b", "-o", "NAME,PATH,LABEL,PARTLABEL,SIZE,FSTYPE,MOUNTPOINTS,RM,TYPE,HOTPLUG,PKNAME,FSUSED,MODEL,VENDOR"],
                       capture_output=True, text=True)
    out = []
    try:
        data = json.loads(r.stdout)
    except ValueError:
        return {"devices": out}

    def walk(nodes, parent=None):
        for n in nodes:
            kids = n.get("children") or []
            mps = [m for m in (n.get("mountpoints") or []) if m]
            fs = n.get("fstype")
            if fs and fs not in ("swap", "crypto_LUKS", "LVM2_member") and n.get("type") in ("part", "disk", "crypt", "lvm"):
                mp = mps[0] if mps else ""
                if mp in ("/boot", "/boot/efi") or mp.startswith("/var/lib") or mp.startswith("/boot"):
                    pass
                else:
                    removable = bool(n.get("rm")) or bool(n.get("hotplug"))
                    title, detail = _device_name(n, parent, removable, mp)
                    out.append({"dev": n["path"], "name": title, "detail": detail, "size": int(n.get("size") or 0),
                                "fs": fs, "mount": mp, "removable": removable, "used": int(n.get("fsused") or 0),
                                "system": mp in ("/", "/home")})
            walk(kids, n)

    walk(data.get("blockdevices", []))
    return {"devices": [d for d in out if d["mount"] or d["removable"] or not d["system"]]}


# ───────────────────────── meta: starred, folder colours, per-folder view ─────────────────────────

META = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")) / "ii-file-manager" / "meta.json"
_meta_cache: dict | None = None
_meta_lock = threading.Lock()


def meta_load() -> dict:
    global _meta_cache
    if _meta_cache is None:
        try:
            _meta_cache = json.loads(META.read_text())
        except (OSError, ValueError):
            _meta_cache = {}
        for k, d in (("starred", []), ("colors", {}), ("views", {})):
            _meta_cache.setdefault(k, d)
    return _meta_cache


def meta_save() -> None:
    META.parent.mkdir(parents=True, exist_ok=True)
    tmp = META.with_suffix(".tmp")
    tmp.write_text(json.dumps(_meta_cache, ensure_ascii=False))
    os.replace(tmp, META)


def op_meta_get(req: dict, job: Job) -> dict:
    with _meta_lock:
        m = meta_load()
        return {"starred": list(m["starred"]), "colors": dict(m["colors"]), "views": dict(m["views"])}


def op_meta_set(req: dict, job: Job) -> dict:
    """star {paths, on}, color {paths, color ('' clears)}, view {path, view|null}."""
    with _meta_lock:
        m = meta_load()
        kind = req["kind"]
        if kind == "star":
            cur = [p for p in m["starred"] if p not in req["paths"]]
            m["starred"] = cur + (list(req["paths"]) if req.get("on") else [])
        elif kind == "color":
            for p in req["paths"]:
                if req.get("color"):
                    m["colors"][p] = req["color"]
                else:
                    m["colors"].pop(p, None)
        elif kind == "view":
            if req.get("view"):
                m["views"][req["path"]] = req["view"]
            else:
                m["views"].pop(req["path"], None)
        meta_save()
    return {"ok": True}


def list_recent(limit: int = 200) -> list[dict]:
    """Files GTK apps opened lately (recently-used.xbel), newest first."""
    xbel = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")) / "recently-used.xbel"
    try:
        root = ET.parse(xbel).getroot()
    except (OSError, ET.ParseError):
        return []
    items = []
    for b in root.iter("bookmark"):
        href = b.get("href", "")
        if not href.startswith("file://"):
            continue
        path = urllib.parse.unquote(href[7:])
        if not os.path.isfile(path):
            continue
        items.append((b.get("modified") or b.get("visited") or "", path))
    items.sort(reverse=True)
    seen, out = set(), []
    for _, path in items:
        if path in seen:
            continue
        seen.add(path)
        out.append(entry_for(path))
        if len(out) >= limit:
            break
    return out


# ───────────────────────── network places, MTP, image tools ─────────────────────────

def gvfs_local_path(uri: str, timeout: int) -> str:
    """The gvfsd-fuse path of a mounted gvfs location. MTP, SMB and SFTP mounts have no
    `target-uri` (that is only for shortcuts); the FUSE path is what `gio info` calls the local path."""
    f = subprocess.run(["gio", "info", "-a", "standard::name", uri], capture_output=True, text=True, timeout=timeout).stdout
    mm = re.search(r"^local path: (.+)$", f, re.M)
    if mm and os.path.exists(mm.group(1).strip()):
        return mm.group(1).strip()
    mm = re.match(r"^([a-z0-9+.-]+)://([^/]*)", uri)
    if mm:
        guess = f"/run/user/{os.getuid()}/gvfs/{mm.group(1)}:host={mm.group(2)}"
        if os.path.exists(guess):
            return guess
    return ""


def op_net_places(req: dict, job: Job) -> dict:
    """gvfs mounts (SMB, SFTP, MTP, ...) that are mounted now, and volumes that can be mounted."""
    if not shutil.which("gio"):
        return {"mounts": [], "available": False}
    r = subprocess.run(["gio", "mount", "-li"], capture_output=True, text=True, timeout=10)
    out = []
    volume = ""
    idle = []
    for line in r.stdout.splitlines():
        vm = re.match(r"^Volume\(\d+\): (.+)$", line)
        if vm:
            volume = vm.group(1)
            continue
        ar = re.match(r"^\s+activation_root=(\S+)$", line)
        if ar and volume:
            # A phone that is plugged in but not opened yet is only a volume, with no mount
            if ar.group(1).split(":", 1)[0] in ("mtp", "gphoto2", "afc"):
                idle.append((volume, ar.group(1)))
            volume = ""
            continue
        m = re.match(r"^Mount\(\d+\): (.+?) -> (\S+)$", line.strip())
        if not m:
            continue
        name, uri = m.group(1), m.group(2)
        scheme = uri.split(":", 1)[0]
        if scheme in ("file", "trash", "recent", "network"):
            continue
        try:
            local = gvfs_local_path(uri, 5)
        except subprocess.TimeoutExpired:
            local = ""
        # The same mount is listed twice for a phone (a shadow mount and the real one)
        dup = next((o for o in out if o["uri"].rstrip("/") == uri.rstrip("/")), None)
        if dup:
            dup["path"] = dup["path"] or local
            continue
        out.append({"name": name, "uri": uri, "scheme": scheme, "path": local, "mounted": True})
    have = {m["uri"].rstrip("/") for m in out}
    for name, uri in idle:
        if uri.rstrip("/") not in have:
            out.append({"name": name, "uri": uri, "scheme": uri.split(":", 1)[0], "path": "", "mounted": False})
    return {"mounts": out, "available": True}


def op_net_mount(req: dict, job: Job) -> dict:
    """Mount a URI (smb://host/share, sftp://user@host/, mtp://...) and return its local path."""
    uri = req["uri"].strip()
    if not re.match(r"^[a-z][a-z0-9+.-]*://", uri):
        uri = "sftp://" + uri if "@" in uri else "smb://" + uri
    r = subprocess.run(["gio", "mount", uri], capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL)
    if r.returncode != 0 and "already mounted" not in (r.stderr or ""):
        raise OSError((r.stderr or r.stdout).strip().splitlines()[-1] if (r.stderr or r.stdout).strip() else "could not connect")
    local = gvfs_local_path(uri, 10)
    if not local:
        raise OSError("Connected, but the share has no local path")
    return {"path": local}


def op_net_unmount(req: dict, job: Job) -> dict:
    r = subprocess.run(["gio", "mount", "-u", req["uri"]], capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        raise OSError(r.stderr.strip() or "could not disconnect")
    return {"ok": True}


def op_image_tool(req: dict, job: Job) -> dict:
    """Batch image resize / convert / rotate with ImageMagick; results land beside the originals."""
    if not shutil.which("magick"):
        raise OSError("ImageMagick is not installed")
    tool = req["tool"]
    made = []
    for src in req["paths"]:
        if not os.path.isfile(src):
            continue
        if job.cancelled.is_set():
            break
        directory, name = os.path.split(src)
        stem, ext = split_ext(name)
        if tool == "resize":
            pct = int(req.get("percent") or 50)
            out_name = f"{stem} ({pct}%){ext}"
            args = ["-resize", f"{pct}%"]
        elif tool == "convert":
            fmt = req["format"].lower().lstrip(".")
            out_name = f"{stem}.{fmt}"
            args = ["-quality", "92"]
        elif tool == "rotate":
            deg = int(req.get("degrees") or 90)
            out_name = f"{stem} (rotated){ext}"
            args = ["-rotate", str(deg)]
        else:
            raise OSError(f"Unknown image tool {tool}")
        dst = os.path.join(directory, out_name)
        if os.path.lexists(dst):
            dst = os.path.join(directory, unique_name(directory, out_name))
        r = subprocess.run(["magick", src, "-auto-orient", *args, dst], capture_output=True, text=True)
        if r.returncode != 0:
            raise OSError(r.stderr.strip().splitlines()[-1] if r.stderr.strip() else "ImageMagick failed")
        made.append(dst)
    return {"made": made}


# ───────────────────────── KDE Connect ─────────────────────────

_KDC_DEV = "/modules/kdeconnect/devices/"


def _busctl(*args: str, timeout: float = 20) -> str:
    r = subprocess.run(["busctl", "--user", *args], capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        raise OSError(r.stderr.strip() or "KDE Connect is not running")
    return r.stdout.strip()


def _kdc_prop(dev: str, sub: str, iface: str, prop: str) -> str:
    try:
        out = _busctl("get-property", "org.kde.kdeconnect", _KDC_DEV + dev + sub, "org.kde.kdeconnect.device" + iface, prop, timeout=3)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return out.split(" ", 1)[1].strip().strip('"') if " " in out else ""


def op_kdc_devices(req: dict, job: Job) -> dict:
    """Paired devices KDE Connect can reach right now."""
    if not shutil.which("kdeconnect-cli"):
        return {"devices": [], "available": False}
    r = subprocess.run(["kdeconnect-cli", "-a", "--id-name-only"], capture_output=True, text=True, timeout=10)
    out = []
    for line in r.stdout.splitlines():
        did, _, name = line.strip().partition(" ")
        if not did or not name:
            continue
        kind = _kdc_prop(did, "", "", "type") or "smartphone"
        charge = _kdc_prop(did, "/battery", ".battery", "charge")
        charging = _kdc_prop(did, "/battery", ".battery", "isCharging") == "true"
        out.append({"id": did, "name": name, "type": kind,
                    "battery": int(charge) if charge.lstrip("-").isdigit() else -1, "charging": charging})
    return {"devices": out, "available": True}


def _kdc_dirs(path: str, iface: str) -> tuple[str, list[dict]]:
    mp = _busctl("call", "org.kde.kdeconnect", path, iface, "mountPoint", timeout=5).partition(" ")[2].strip().strip('"')
    # The root of the phone's SFTP server is not readable; the storages the app exports are listed
    # by getDirectories as path/name pairs ('a{sv} 1 "<path>" s "Internal shared storage"')
    dirs = []
    try:
        raw = _busctl("call", "org.kde.kdeconnect", path, iface, "getDirectories", timeout=5)
        dirs = [{"path": a, "name": b} for a, b in re.findall(r'"([^"]+)" s "([^"]*)"', raw) if a.startswith("/")]
    except OSError:
        pass
    return mp, dirs


def _readable(path: str) -> bool:
    """A mount left from an earlier session (the phone changed address or slept) answers every call
    with an I/O error; listing it is the only reliable test."""
    try:
        os.listdir(path)
        return True
    except OSError:
        return False


def op_kdc_mount(req: dict, job: Job) -> dict:
    """Mount a device's storage through its SFTP plugin and return where it appears."""
    dev = req["device"]
    path = _KDC_DEV + dev + "/sftp"
    iface = "org.kde.kdeconnect.device.sftp"
    if not shutil.which("sshfs"):
        raise OSError("Browsing a phone needs sshfs: install it with  sudo pacman -S sshfs")

    def mount() -> None:
        ok = _busctl("call", "org.kde.kdeconnect", path, iface, "mountAndWait", timeout=40)
        if not ok.endswith("true"):
            err = _busctl("call", "org.kde.kdeconnect", path, iface, "getMountError", timeout=5)
            raise OSError(err.partition(" ")[2].strip().strip('"') or "the phone could not be mounted")

    mount()
    mp, dirs = _kdc_dirs(path, iface)
    target = dirs[0]["path"] if dirs else ""
    if target and not _readable(target):
        # Stale mount: drop it, and mount again so the connection is a live one
        try:
            _busctl("call", "org.kde.kdeconnect", path, iface, "unmount", timeout=10)
        except OSError:
            pass
        subprocess.run(["fusermount3", "-uz", mp], capture_output=True)
        time.sleep(0.5)
        mount()
        mp, dirs = _kdc_dirs(path, iface)
        target = dirs[0]["path"] if dirs else ""
        if target and not _readable(target):
            raise OSError("The phone is reachable but its storage can't be read. Open the KDE Connect app on the phone and allow file access")
    return {"mount": target or mp, "dirs": dirs, "root": mp}


def op_kdc_send(req: dict, job: Job) -> dict:
    paths = [p for p in req["paths"] if isinstance(p, str) and os.path.isfile(p)]
    if not paths:
        raise OSError("Only files can be sent")
    r = subprocess.run(["kdeconnect-cli", "-d", req["device"], "--share", *paths], capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        raise OSError(r.stderr.strip() or "could not send")
    return {"sent": len(paths)}


def op_kdc_ping(req: dict, job: Job) -> dict:
    subprocess.run(["kdeconnect-cli", "-d", req["device"], "--ping"], capture_output=True, timeout=10)
    return {"ok": True}


def op_mount(req: dict, job: Job) -> dict:
    r = subprocess.run(["udisksctl", "mount", "-b", req["dev"]], capture_output=True, text=True)
    if r.returncode != 0:
        raise OSError(r.stderr.strip() or "could not mount")
    m = re.search(r" at (.+?)\.?$", r.stdout.strip())
    return {"ok": True, "mount": m.group(1) if m else ""}


def op_unmount(req: dict, job: Job) -> dict:
    r = subprocess.run(["udisksctl", "unmount", "-b", req["dev"]], capture_output=True, text=True)
    if r.returncode != 0:
        raise OSError(r.stderr.strip() or "could not unmount")
    if req.get("eject"):
        base = re.sub(r"\d+$", "", req["dev"]).rstrip("p") if "nvme" in req["dev"] else re.sub(r"\d+$", "", req["dev"])
        subprocess.run(["udisksctl", "power-off", "-b", base], capture_output=True, text=True)
    return {"ok": True}


# ───────────────────────── clipboard ─────────────────────────

def op_clip_set(req: dict, job: Job) -> dict:
    """Publish files so other apps can paste them (GTK file managers read this type)."""
    paths = req["paths"]
    if not paths:
        return {"ok": True}
    body = ("cut" if req.get("cut") else "copy") + "\n" + "\n".join(
        "file://" + urllib.parse.quote(p, safe="/") for p in paths)
    subprocess.Popen(["wl-copy", "--type", "x-special/gnome-copied-files"], stdin=subprocess.PIPE,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True) \
        .communicate(body.encode())
    return {"ok": True}


def op_clip_get(req: dict, job: Job) -> dict:
    """Files another app (or this one) put on the clipboard: {paths, cut}."""
    try:
        types = subprocess.run(["wl-paste", "--list-types"], capture_output=True, text=True, timeout=2).stdout.split()
    except (OSError, subprocess.TimeoutExpired):
        return {"paths": [], "cut": False}

    def read(t: str) -> str:
        return subprocess.run(["wl-paste", "--no-newline", "--type", t], capture_output=True, text=True, timeout=2).stdout

    paths: list[str] = []
    cut = False
    try:
        if "x-special/gnome-copied-files" in types:
            lines = read("x-special/gnome-copied-files").splitlines()
            cut = bool(lines) and lines[0].strip() == "cut"
            paths = [urllib.parse.unquote(l[7:]) for l in lines[1:] if l.startswith("file://")]
        elif "text/uri-list" in types:
            for l in read("text/uri-list").splitlines():
                if l.startswith("file://"):
                    paths.append(urllib.parse.unquote(l[7:]))
        elif any(t.startswith("text/plain") for t in types):
            for l in read([t for t in types if t.startswith("text/plain")][0]).splitlines():
                l = l.strip()
                if l.startswith("/") and os.path.exists(l):
                    paths.append(l)
    except (OSError, subprocess.TimeoutExpired):
        pass
    return {"paths": [p for p in paths if os.path.lexists(p)], "cut": cut}


# ───────────────────────── thumbnails and icons ─────────────────────────

_icon_cache: dict[str, list[str]] = {}


def icon_names(mime: str) -> list[str]:
    """Theme icon names for a type, most specific first (`audio-flac`, then `audio-x-generic`)."""
    got = _icon_cache.get(mime)
    if got is not None:
        return got
    names: list[str] = []
    if Gio is not None:
        try:
            icon = Gio.content_type_get_icon(mime)
            names = [n for n in (icon.get_names() if hasattr(icon, "get_names") else []) if not n.endswith("-symbolic")]
        except Exception:
            names = []
    _icon_cache[mime] = names[:6]
    return _icon_cache[mime]


def thumb_dirs() -> list[Path]:
    return [Path("/usr/share/thumbnailers"), Path("/usr/local/share/thumbnailers"),
            Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")) / "thumbnailers"]


_thumbnailers: dict[str, str] | None = None


def thumbnailers() -> dict[str, str]:
    """mime type -> command template, from the freedesktop .thumbnailer files."""
    global _thumbnailers
    if _thumbnailers is not None:
        return _thumbnailers
    out: dict[str, str] = {}
    for d in thumb_dirs():
        try:
            files = sorted(d.glob("*.thumbnailer"))
        except OSError:
            continue
        for f in files:
            exec_line, mimes = "", ""
            try:
                for line in f.read_text(errors="replace").splitlines():
                    if line.startswith("Exec="):
                        exec_line = line[5:].strip()
                    elif line.startswith("MimeType="):
                        mimes = line[9:]
            except OSError:
                continue
            for m in mimes.split(";"):
                if m and exec_line:
                    out[m.strip()] = exec_line  # later directories (the user's) win
    _thumbnailers = out
    return out


def thumb_path(path: str, size: str = "large") -> Path:
    import hashlib

    uri = "file://" + urllib.parse.quote(path, safe="/")
    return THUMBS / size / (hashlib.md5(uri.encode()).hexdigest() + ".png")


def thumb_valid(tp: Path, mtime: int) -> bool:
    """A cached thumbnail counts when its Thumb::MTime matches the file (as other apps write it)."""
    try:
        with open(tp, "rb") as f:
            head = f.read(4096)
    except OSError:
        return False
    m = re.search(rb"Thumb::MTime\x00(\d+)", head)
    if m:
        return int(m.group(1)) == mtime
    try:
        return tp.stat().st_mtime >= mtime
    except OSError:
        return False


def add_png_text(path: Path, items: dict[str, str]) -> None:
    import struct
    import zlib

    try:
        data = path.read_bytes()
    except OSError:
        return
    if data[:8] != b"\x89PNG\r\n\x1a\n" or b"Thumb::MTime" in data[:4096]:
        return
    chunks = b""
    for k, v in items.items():
        body = k.encode() + b"\0" + v.encode()
        chunks += struct.pack(">I", len(body)) + b"tEXt" + body + struct.pack(">I", zlib.crc32(b"tEXt" + body) & 0xFFFFFFFF)
    path.write_bytes(data[:33] + chunks + data[33:])


def op_thumb(req: dict, job: Job) -> dict:
    """The freedesktop thumbnail for a file: from the shared cache, else made by an installed thumbnailer."""
    import hashlib

    path = req["path"]
    try:
        st = os.stat(path)
    except OSError:
        return {"thumb": ""}
    mtime = int(st.st_mtime)
    want = int(req.get("size", 256))
    order = ["large", "x-large"] + (["normal"] if want <= 128 else [])
    for d in order:
        tp = thumb_path(path, d)
        if tp.is_file() and thumb_valid(tp, mtime):
            return {"thumb": str(tp)}
    uri = "file://" + urllib.parse.quote(path, safe="/")
    key = hashlib.md5(uri.encode()).hexdigest()
    fail = THUMBS / "fail" / "ii-file-manager" / (key + ".png")
    try:
        if fail.is_file() and fail.stat().st_mtime >= st.st_mtime and time.time() - fail.stat().st_mtime < 3600:  # a failure is retried after an hour
            return {"thumb": ""}
    except OSError:
        pass
    mime = req.get("mime") or guess_mime(os.path.basename(path), False)
    tmpl = thumbnailers().get(mime)
    out = THUMBS / "large" / (key + ".png")
    ok = False
    if tmpl:
        out.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        tmp = out.with_suffix(".tmp.png")
        tokens = {"s": "256", "i": path, "u": uri, "o": str(tmp), "%": "%"}
        try:
            cmd = [re.sub(r"%([siuo%])", lambda m: tokens[m.group(1)], t) for t in shlex.split(tmpl)]
            ok = subprocess.run(cmd, capture_output=True, timeout=40, stdin=subprocess.DEVNULL).returncode == 0
        except (subprocess.SubprocessError, OSError, ValueError):
            ok = False
        if ok and tmp.is_file() and tmp.stat().st_size > 0:
            add_png_text(tmp, {"Thumb::URI": uri, "Thumb::MTime": str(mtime), "Thumb::Size": str(st.st_size)})
            os.chmod(tmp, 0o600)
            os.replace(tmp, out)
            return {"thumb": str(out)}
        tmp.unlink(missing_ok=True)
    try:
        fail.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        fail.write_bytes(b"")
    except OSError:
        pass
    return {"thumb": ""}


# ───────────────────────── Thunar custom actions ─────────────────────────

FLAGS = ("directories", "audio-files", "image-files", "other-files", "text-files", "video-files")
_uca_cache: tuple[float, list[dict]] | None = None


def load_actions() -> list[dict]:
    global _uca_cache
    try:
        m = UCA.stat().st_mtime
    except OSError:
        return []
    if _uca_cache and _uca_cache[0] == m:
        return _uca_cache[1]
    out = []
    try:
        root = ET.parse(UCA).getroot()
    except (ET.ParseError, OSError):
        return []
    accels = load_accels()
    seen: set[str] = set()
    for a in root.findall("action"):
        g = lambda k: (a.findtext(k) or "").strip()
        uid = g("unique-id")
        # Two actions copied from each other can share an id; the second would never run
        while uid in seen:
            uid += "+"
        seen.add(uid)
        out.append({
            "id": uid, "name": g("name"), "submenu": g("submenu"), "icon": g("icon"), "description": g("description"),
            "command": (a.findtext("command") or "").strip(), "patterns": g("patterns") or "*", "range": g("range"),
            "flags": [f for f in FLAGS if a.find(f) is not None], "startupNotify": a.find("startup-notify") is not None,
            "shortcut": accels.get(uid, ""),
        })
    _uca_cache = (m, out)
    return out


def load_accels() -> dict[str, str]:
    out: dict[str, str] = {}
    try:
        for line in ACCELS.read_text().splitlines():
            m = re.match(r'\(gtk_accel_path "<Actions>/ThunarActions/uca-action-(.+?)" "(.*)"\)', line.strip())
            if m and m.group(2):
                key = m.group(2)
                mods = re.findall(r"<(\w+)>", key)
                base = re.sub(r"<\w+>", "", key)
                names = {"Primary": "Ctrl", "Control": "Ctrl", "Alt": "Alt", "Shift": "Shift", "Super": "Meta"}
                out[m.group(1)] = "+".join([names.get(x, x) for x in mods] + [base.upper() if len(base) == 1 else base])
    except OSError:
        pass
    return out


def range_ok(rng: str, n: int) -> bool:
    rng = (rng or "").strip()
    if rng in ("", "*"):
        return True
    if "-" in rng:
        lo, _, hi = rng.partition("-")
        try:
            return int(lo or 0) <= n <= int(hi or 10**9)
        except ValueError:
            return True
    try:
        return n == int(rng)
    except ValueError:
        return True


def action_visible(a: dict, sel: list[dict]) -> bool:
    if not a["command"] or not sel:
        return False
    if not range_ok(a["range"], len(sel)):
        return False
    pats = [p for p in re.split(r"[;]", a["patterns"]) if p] or ["*"]
    flags = a["flags"]
    for e in sel:
        if not any(fnmatch.fnmatchcase(e["name"].lower(), p.lower()) for p in pats):
            return False
        if flags and type_class(e["name"], e["mime"], e["isDir"]) not in flags:
            return False
        if not flags:
            return False
    return True


def op_actions(req: dict, job: Job) -> dict:
    """The custom actions that apply to the selection (or to the folder when nothing is selected)."""
    paths = req.get("paths") or ([req["dir"]] if req.get("dir") else [])
    sel = [entry_for(p.rstrip("/") or "/") for p in paths]
    acts = [a for a in load_actions() if action_visible(a, sel)]
    return {"actions": acts}


def op_actions_all(req: dict, job: Job) -> dict:
    return {"actions": load_actions()}


def q(s: str) -> str:
    return shlex.quote(s)


def substitute(cmd: str, paths: list[str]) -> str:
    first = paths[0]
    codes = {
        "f": q(first),
        "F": " ".join(q(p) for p in paths),
        "d": q(os.path.dirname(first) or "/"),
        "D": " ".join(q(os.path.dirname(p) or "/") for p in paths),
        "n": q(os.path.basename(first)),
        "N": " ".join(q(os.path.basename(p)) for p in paths),
        "u": q("file://" + urllib.parse.quote(first, safe="/")),
        "U": " ".join(q("file://" + urllib.parse.quote(p, safe="/")) for p in paths),
    }

    def rep(m: re.Match) -> str:
        c = m.group(1)
        if c == "%":
            return "%"
        return codes.get(c, m.group(0))

    return re.sub(r"%([a-zA-Z%])", rep, cmd)


def op_run_action(req: dict, job: Job) -> dict:
    act = next((a for a in load_actions() if a["id"] == req["actionId"]), None)
    if act is None:
        raise OSError("That action no longer exists")
    paths = req.get("paths") or ([req["dir"]] if req.get("dir") else [])
    if not paths:
        raise OSError("Nothing to run it on")
    cmd = substitute(act["command"], paths)
    cwd = req.get("dir") or os.path.dirname(paths[0])
    uses_path = re.search(r"%[fFnNuU]", act["command"]) is not None
    if len(paths) == 1 and os.path.isdir(paths[0]) and not uses_path:
        cwd = paths[0]
    if not os.path.isdir(cwd):
        cwd = str(HOME)
    # Quick commands report their result; long ones (a terminal, meld, a big conversion) are left
    # running instead of holding the window up until they end
    out, err = tempfile.TemporaryFile(), tempfile.TemporaryFile()
    proc = subprocess.Popen(["sh", "-c", cmd], cwd=cwd, stdin=subprocess.DEVNULL, stdout=out, stderr=err, start_new_session=True)
    try:
        proc.wait(timeout=6)
    except subprocess.TimeoutExpired:
        threading.Thread(target=proc.wait, daemon=True).start()
        return {"ok": True, "code": 0, "stderr": "", "stdout": "", "name": act["name"], "background": True}

    def tail(f, n):
        f.seek(0)
        return f.read().decode("utf-8", "replace").strip()[-n:]

    return {"ok": proc.returncode == 0, "code": proc.returncode, "stderr": tail(err, 600),
            "stdout": tail(out, 300), "name": act["name"]}


def op_save_actions(req: dict, job: Job) -> dict:
    global _uca_cache
    root = ET.Element("actions")
    for a in req["actions"]:
        el = ET.SubElement(root, "action")
        for tag, key in (("icon", "icon"), ("name", "name"), ("submenu", "submenu"), ("unique-id", "id"),
                         ("command", "command"), ("description", "description"), ("range", "range"),
                         ("patterns", "patterns")):
            ET.SubElement(el, tag).text = a.get(key, "") or ""
        if a.get("startupNotify"):
            ET.SubElement(el, "startup-notify")
        for f in a.get("flags", []):
            if f in FLAGS:
                ET.SubElement(el, f)
    UCA.parent.mkdir(parents=True, exist_ok=True)
    bak = UCA.with_suffix(".xml.ii-backup")
    if UCA.exists() and not bak.exists():
        shutil.copy2(UCA, bak)
    ET.indent(root, space="\t")
    tmp = UCA.with_suffix(".tmp")
    tmp.write_text('<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(root, encoding="unicode") + "\n")
    os.replace(tmp, UCA)
    _uca_cache = None
    return {"ok": True}


# ───────────────────────── watching ─────────────────────────

watchers: dict[str, subprocess.Popen] = {}
watch_lock = threading.Lock()


def op_watch(req: dict, job: Job) -> dict:
    wid = str(req["watchId"])
    unwatch(wid)
    path = req["path"]
    if path.startswith("trash:"):
        path = str(TRASH / "files")
    if not os.path.isdir(path):
        return {"ok": False}
    proc = subprocess.Popen(
        ["inotifywait", "-m", "-q", "-e", "create,delete,move,attrib,close_write,delete_self,move_self", "--format", "%e|%f", path],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    with watch_lock:
        watchers[wid] = proc

    def pump() -> None:
        assert proc.stdout is not None
        pending = [False]
        timer: list[threading.Timer | None] = [None]

        def fire() -> None:
            pending[0] = False
            send({"event": "changed", "watchId": wid})

        for line in proc.stdout:
            ev, _, name = line.rstrip("\n").partition("|")
            if name.endswith(".part") or name.startswith(".fm-extract-"):
                continue  # a copy in flight writes these; the finished file raises its own event
            if not pending[0]:
                pending[0] = True
                t = threading.Timer(0.2, fire)
                timer[0] = t
                t.start()
        with watch_lock:
            alive = watchers.get(wid) is proc
        if alive:
            send({"event": "changed", "watchId": wid})  # the folder itself went away: let the window notice

    threading.Thread(target=pump, daemon=True).start()
    return {"ok": True}


def unwatch(wid: str) -> None:
    with watch_lock:
        p = watchers.pop(wid, None)
    if p:
        try:
            p.terminate()
        except OSError:
            pass


def op_unwatch(req: dict, job: Job) -> dict:
    unwatch(str(req["watchId"]))
    return {"ok": True}


# ───────────────────────── dispatch ─────────────────────────

def op_transfer(req: dict, job: Job) -> dict:
    t = Transfer(job, req["mode"], req["srcs"], req["dest"], req["id"], req.get("names"))
    if not os.path.isdir(req["dest"]):
        raise OSError("The destination is not a folder")
    # Refuse to put a folder inside itself
    for s in req["srcs"]:
        if os.path.isdir(s) and (os.path.abspath(req["dest"]) + "/").startswith(os.path.abspath(s) + "/"):
            if req["mode"] == "move" or os.path.abspath(req["dest"]) != os.path.dirname(os.path.abspath(s)):
                raise OSError("A folder cannot be copied into itself")
    return t.run()


# ───────────────────────── checksums, disk usage, folder compare ─────────────────────────

_HASHES = ("md5", "sha1", "sha256", "sha512")


def op_hash(req: dict, job: Job) -> dict:
    """Several digests of one file in a single read, with progress."""
    import hashlib
    path = req["path"]
    algos = [a for a in (req.get("algos") or ["sha256"]) if a in _HASHES] or ["sha256"]
    if not os.path.isfile(path):
        raise OSError("Checksums are for files")
    total = os.path.getsize(path)
    hs = {a: hashlib.new(a) for a in algos}
    done = 0
    last = 0.0
    with open(path, "rb") as fh:
        while True:
            if job.cancelled.is_set():
                raise Cancelled()
            chunk = fh.read(1 << 20)
            if not chunk:
                break
            for h in hs.values():
                h.update(chunk)
            done += len(chunk)
            if time.monotonic() - last > 0.2:
                last = time.monotonic()
                send({"id": req["id"], "event": "progress", "done": done, "total": total})
    return {"hashes": {a: h.hexdigest() for a, h in hs.items()}, "size": total}


def op_du(req: dict, job: Job) -> dict:
    """Disk use of each child of a folder. Counts blocks actually used, counts a hard link once,
    never follows symlinks and stays on the folder's filesystem. Snapshots stream while it walks."""
    root = os.path.abspath(os.path.expanduser(req["path"]))
    rdev = os.lstat(root).st_dev
    seen: set[tuple[int, int]] = set()
    items: list[dict] = []
    last = [0.0]

    def snapshot(force: bool = False) -> None:
        if force or time.monotonic() - last[0] > 0.3:
            last[0] = time.monotonic()
            send({"id": req["id"], "event": "progress", "items": sorted(items, key=lambda i: -i["size"])[:400]})

    try:
        names = sorted(os.listdir(root))
    except OSError as ex:
        raise OSError(str(ex))
    for name in names:
        if job.cancelled.is_set():
            raise Cancelled()
        p = os.path.join(root, name)
        try:
            st = os.lstat(p)
        except OSError:
            continue
        item = {"name": name, "path": p, "isDir": statmod.S_ISDIR(st.st_mode), "size": 0, "files": 0}
        items.append(item)
        stack = [p]
        while stack:
            if job.cancelled.is_set():
                raise Cancelled()
            cur = stack.pop()
            try:
                cst = os.lstat(cur)
            except OSError:
                continue
            if cst.st_dev != rdev:
                continue
            if cst.st_nlink > 1 and not statmod.S_ISDIR(cst.st_mode):
                key = (cst.st_dev, cst.st_ino)
                if key in seen:
                    continue
                seen.add(key)
            item["size"] += cst.st_blocks * 512
            if statmod.S_ISDIR(cst.st_mode):
                try:
                    with os.scandir(cur) as it:
                        stack.extend(e.path for e in it)
                except OSError:
                    pass
            else:
                item["files"] += 1
            snapshot()
    snapshot(True)
    free = shutil.disk_usage(root)
    return {"items": sorted(items, key=lambda i: -i["size"]), "total": sum(i["size"] for i in items),
            "free": free.free, "fsTotal": free.total}


def _walk_rel(root: str, job: Job) -> dict[str, tuple[bool, int, float]]:
    out: dict[str, tuple[bool, int, float]] = {}
    stack = [""]
    while stack:
        if job.cancelled.is_set():
            raise Cancelled()
        rel = stack.pop()
        try:
            with os.scandir(os.path.join(root, rel) if rel else root) as it:
                for e in it:
                    r = os.path.join(rel, e.name) if rel else e.name
                    try:
                        st = e.stat(follow_symlinks=False)
                    except OSError:
                        continue
                    isdir = statmod.S_ISDIR(st.st_mode)
                    out[r] = (isdir, 0 if isdir else st.st_size, st.st_mtime)
                    if isdir:
                        stack.append(r)
        except OSError:
            pass
    return out


def op_compare(req: dict, job: Job) -> dict:
    """What differs between two folders: only on one side, or on both with another size or content."""
    import filecmp
    a = os.path.abspath(os.path.expanduser(req["a"]))
    b = os.path.abspath(os.path.expanduser(req["b"]))
    for d in (a, b):
        if not os.path.isdir(d):
            raise OSError("Both sides must be folders")
    wa = _walk_rel(a, job)
    wb = _walk_rel(b, job)
    only_a, only_b, differ = [], [], []
    same = 0
    cap = 3000

    def under_missing(rel: str, missing: set[str]) -> bool:
        parts = rel.split(os.sep)
        return any(os.sep.join(parts[:i]) in missing for i in range(1, len(parts)))

    miss_a: set[str] = set()
    miss_b: set[str] = set()
    for rel in sorted(wa):
        if job.cancelled.is_set():
            raise Cancelled()
        if rel not in wb:
            if not under_missing(rel, miss_b):
                if wa[rel][0]:
                    miss_b.add(rel)
                if len(only_a) < cap:
                    only_a.append({"rel": rel, "isDir": wa[rel][0], "size": wa[rel][1], "mtime": wa[rel][2]})
            continue
        da, sa, ma = wa[rel]
        db, sb, mb = wb[rel]
        if da != db:
            differ.append({"rel": rel, "isDir": da, "why": "type", "sizeA": sa, "sizeB": sb, "mtimeA": ma, "mtimeB": mb})
        elif not da:
            changed = sa != sb
            if not changed and abs(ma - mb) > 2:
                changed = sa <= (256 << 20) and not filecmp.cmp(os.path.join(a, rel), os.path.join(b, rel), shallow=False)
            if changed:
                differ.append({"rel": rel, "isDir": False, "why": "size" if sa != sb else "content",
                               "sizeA": sa, "sizeB": sb, "mtimeA": ma, "mtimeB": mb})
            else:
                same += 1
        else:
            same += 1
    for rel in sorted(wb):
        if rel not in wa and not under_missing(rel, miss_a):
            if wb[rel][0]:
                miss_a.add(rel)
            if len(only_b) < cap:
                only_b.append({"rel": rel, "isDir": wb[rel][0], "size": wb[rel][1], "mtime": wb[rel][2]})
    return {"onlyA": only_a, "onlyB": only_b, "differ": differ[:cap], "same": same, "a": a, "b": b}


OPS: dict[str, Callable[[dict, Job], dict]] = {
    "list": lambda r, j: op_list(r, j),
    "transfer": op_transfer,
    "trash": op_trash,
    "restore": op_restore,
    "emptyTrash": op_empty_trash,
    "delete": op_delete,
    "rename": op_rename,
    "mkdir": op_mkdir,
    "newfile": op_newfile,
    "symlink": op_symlink,
    "bulkRename": op_bulk_rename,
    "props": op_props,
    "chmod": op_chmod,
    "search": op_search,
    "hash": op_hash,
    "du": op_du,
    "compare": op_compare,
    "compress": op_compress,
    "dirsizes": op_dirsizes,
    "dupes": op_dupes,
    "terminal": op_terminal,
    "wallpaper": op_wallpaper,
    "extract": op_extract,
    "apps": op_apps,
    "allApps": op_all_apps,
    "open": op_open,
    "setDefaultApp": op_set_default_app,
    "places": op_places,
    "bookmark": op_bookmark,
    "devices": op_devices,
    "meta_get": op_meta_get,
    "meta_set": op_meta_set,
    "net_places": op_net_places,
    "net_mount": op_net_mount,
    "net_unmount": op_net_unmount,
    "image_tool": op_image_tool,
    "kdc_devices": op_kdc_devices,
    "kdc_mount": op_kdc_mount,
    "kdc_send": op_kdc_send,
    "kdc_ping": op_kdc_ping,
    "mount": op_mount,
    "unmount": op_unmount,
    "clipSet": op_clip_set,
    "clipGet": op_clip_get,
    "thumb": op_thumb,
    "actions": op_actions,
    "actionsAll": op_actions_all,
    "runAction": op_run_action,
    "saveActions": op_save_actions,
    "watch": op_watch,
    "unwatch": op_unwatch,
}


def handle(req: dict) -> None:
    rid = req.get("id")
    op = req.get("op")
    job = Job(rid)
    jobs[rid] = job
    try:
        fn = OPS.get(op)
        if fn is None:
            raise OSError(f"Unknown operation {op}")
        result = fn(req, job)
        send({"id": rid, "event": "result", **(result or {})})
    except Cancelled:
        send({"id": rid, "event": "result", "ok": False, "cancelled": True})
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as e:
        send({"id": rid, "event": "error", "message": (e.strerror if isinstance(e, OSError) and e.strerror else str(e))})
    except Exception as e:  # keep the helper alive whatever a handler does
        send({"id": rid, "event": "error", "message": f"{type(e).__name__}: {e}"})
    finally:
        jobs.pop(rid, None)


def main() -> None:
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    pool = ThreadPoolExecutor(max_workers=12)
    send({"event": "ready", "home": str(HOME)})
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except ValueError:
            continue
        op = req.get("op")
        if op == "cancel":
            j = jobs.get(req.get("target"))
            if j:
                j.cancelled.set()
            continue
        if op == "resolve":
            j = jobs.get(req.get("target"))
            if j:
                j.resolution = {"action": req.get("action"), "all": bool(req.get("all")), "name": req.get("name")}
                j.resolved.set()
            continue
        pool.submit(handle, req)
    for w in list(watchers):
        unwatch(w)
    os._exit(0)


if __name__ == "__main__":
    main()
