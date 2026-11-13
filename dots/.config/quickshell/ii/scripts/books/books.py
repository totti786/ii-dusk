#!/usr/bin/env python3
"""Library helper for the Quickshell Books app.

Commands, all printing JSON:

  scan [--dir DIR]     one JSON object with every book under DIR (and any book the viewers
                       remember from elsewhere), with last page and last-read time taken from
                       zathura's history. Fast: it never renders anything.
  covers [--dir DIR]   JSON lines, one per finished job: {"id", "cover"} for a new cover
                       image and {"id", "pages"} for a page count. Recently read books first.
                       Covers are cached, so a second run has nothing left to do.

  forget --path FILE   delete the book's saved page from zathura's history and stop listing it
                       as a "remembered" book outside the library (never touches the file)
  restore              list every forgotten book again

Scanning never writes to the viewers' databases; only `forget` removes a history row.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime
import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import zipfile
from pathlib import Path

FORMATS = {".pdf", ".epub", ".djvu", ".cbz"}
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}

HOME = Path.home()
CACHE = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")) / "ii-books"
DATA = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share"))
ZATHURA_DB = DATA / "zathura" / "bookmarks.sqlite"
SIOYEK_DB = DATA / "sioyek" / "local.db"
COVER_DIR = CACHE / "covers"
META_FILE = CACHE / "meta.json"
HIDDEN_FILE = CACHE / "hidden.json"
COVER_SIZE = 400


def book_id(path: Path, stat: os.stat_result) -> str:
    """Changes with the file, so an edited or replaced book gets a new cover."""
    raw = f"{path}|{stat.st_size}|{int(stat.st_mtime)}".encode("utf-8", "surrogateescape")
    return hashlib.sha1(raw).hexdigest()[:20]


def load_meta() -> dict:
    try:
        return json.loads(META_FILE.read_text())
    except (OSError, ValueError):
        return {}


def save_meta(meta: dict) -> None:
    try:
        CACHE.mkdir(parents=True, exist_ok=True)
        tmp = META_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(meta))
        tmp.replace(META_FILE)
    except OSError:
        pass


def load_hidden() -> set[str]:
    try:
        return set(json.loads(HIDDEN_FILE.read_text()))
    except (OSError, ValueError, TypeError):
        return set()


def save_hidden(hidden: set[str]) -> None:
    try:
        CACHE.mkdir(parents=True, exist_ok=True)
        tmp = HIDDEN_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(sorted(hidden)))
        tmp.replace(HIDDEN_FILE)
    except OSError:
        pass


def open_readonly(path: Path) -> sqlite3.Connection | None:
    if not path.exists():
        return None
    try:
        return sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=1.0)
    except sqlite3.Error:
        return None


def parse_time(value) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S"):
        try:
            return datetime.datetime.strptime(str(value), fmt).timestamp()
        except ValueError:
            continue
    return None


def zathura_history() -> dict[str, dict]:
    """file -> {page (0-based), time}"""
    out: dict[str, dict] = {}
    db = open_readonly(ZATHURA_DB)
    if db is None:
        return out
    try:
        for file, page, time in db.execute("SELECT file, page, time FROM fileinfo"):
            if file and str(file).startswith("/"):
                out[str(file)] = {"page": page, "time": parse_time(time)}
    except sqlite3.Error:
        pass
    finally:
        db.close()
    return out


def sioyek_paths() -> set[str]:
    out: set[str] = set()
    db = open_readonly(SIOYEK_DB)
    if db is None:
        return out
    try:
        for (path,) in db.execute("SELECT path FROM document_hash"):
            if path and str(path).startswith("/"):
                out.add(str(path))
    except sqlite3.Error:
        pass
    finally:
        db.close()
    return out


def clean_title(stem: str) -> str:
    title = re.sub(r"[_]+", " ", stem)
    return re.sub(r"\s{2,}", " ", title).strip()


def walk_books(root: Path):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for name in sorted(filenames):
            path = Path(dirpath) / name
            if path.suffix.lower() in FORMATS and not name.startswith("."):
                yield path


def collect(root: Path) -> list[dict]:
    history = zathura_history()
    extra = sioyek_paths()
    meta = load_meta()
    hidden = load_hidden()

    paths: dict[str, Path] = {}
    if root.is_dir():
        for path in walk_books(root):
            paths[str(path)] = path
    for remembered in list(history) + list(extra):
        path = Path(remembered)
        if remembered in hidden and remembered not in history:
            continue
        if remembered not in paths and path.suffix.lower() in FORMATS and path.is_file():
            paths[remembered] = path

    books = []
    for key, path in paths.items():
        try:
            stat = path.stat()
        except OSError:
            continue
        bid = book_id(path, stat)
        info = meta.get(bid, {})
        cover = COVER_DIR / f"{bid}.png"
        if not cover.exists():
            cover = next((p for p in COVER_DIR.glob(f"{bid}.*") if p.suffix.lower() in IMAGE_EXTS), None) if COVER_DIR.exists() else None
        hist = history.get(key)
        try:
            folder = str(path.parent.relative_to(root)) if root in path.parents else str(path.parent)
        except ValueError:
            folder = str(path.parent)
        books.append({
            "id": bid,
            "path": str(path),
            "title": clean_title(path.stem),
            "format": path.suffix.lower().lstrip("."),
            "folder": "" if folder == "." else folder,
            "size": stat.st_size,
            "added": int(stat.st_mtime),
            "page": hist["page"] if hist else None,
            "lastRead": hist["time"] if hist else None,
            "known": hist is not None or key in extra,
            "pages": info.get("pages"),
            "cover": str(cover) if cover else "",
        })
    return books


def cmd_scan(args) -> int:
    root = Path(args.dir).expanduser()
    books = collect(root)
    json.dump({"dir": str(root), "exists": root.is_dir(), "books": books}, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


def cmd_forget(args) -> int:
    """Drop a book from the history: zathura's saved page, and the "remembered" list.

    The file itself is never touched. A book inside the library folder stays in the
    library, just unread; one from elsewhere disappears until it is restored.
    """
    path = str(Path(args.path).expanduser())
    removed = 0
    if ZATHURA_DB.exists():
        try:
            db = sqlite3.connect(str(ZATHURA_DB), timeout=3.0)
            with db:
                removed = db.execute("DELETE FROM fileinfo WHERE file = ?", (path,)).rowcount
            db.close()
        except sqlite3.Error as err:
            emit({"ok": False, "error": str(err)})
            return 1
    hidden = load_hidden()
    hidden.add(path)
    save_hidden(hidden)
    emit({"ok": True, "removed": removed})
    return 0


def cmd_restore(args) -> int:
    """Forget what was forgotten: show every hidden "remembered" book again."""
    save_hidden(set())
    emit({"ok": True})
    return 0


def make_cover(path: Path, bid: str) -> Path | None:
    COVER_DIR.mkdir(parents=True, exist_ok=True)
    out = COVER_DIR / f"{bid}.png"
    suffix = path.suffix.lower()
    try:
        if suffix == ".pdf":
            if shutil.which("papers-thumbnailer"):
                subprocess.run(["papers-thumbnailer", "-s", str(COVER_SIZE), str(path), str(out)],
                               capture_output=True, timeout=30)
            if not out.exists() and shutil.which("pdftoppm"):
                prefix = COVER_DIR / f"{bid}.tmp"
                subprocess.run(["pdftoppm", "-f", "1", "-l", "1", "-png", "-singlefile",
                                "-scale-to", str(COVER_SIZE), str(path), str(prefix)],
                               capture_output=True, timeout=30)
                tmp = Path(f"{prefix}.png")
                if tmp.exists():
                    tmp.replace(out)
        elif suffix == ".epub":
            if shutil.which("gnome-epub-thumbnailer"):
                subprocess.run(["gnome-epub-thumbnailer", "-s", str(COVER_SIZE), str(path), str(out)],
                               capture_output=True, timeout=30)
        elif suffix == ".cbz":
            with zipfile.ZipFile(path) as archive:
                names = sorted(n for n in archive.namelist() if Path(n).suffix.lower() in IMAGE_EXTS)
                if names:
                    target = COVER_DIR / f"{bid}{Path(names[0]).suffix.lower()}"
                    target.write_bytes(archive.read(names[0]))
                    return target
    except (OSError, subprocess.SubprocessError, zipfile.BadZipFile):
        return None
    return out if out.exists() and out.stat().st_size > 0 else None


def page_count(path: Path) -> int | None:
    if path.suffix.lower() != ".pdf" or not shutil.which("pdfinfo"):
        return None
    try:
        result = subprocess.run(["pdfinfo", str(path)], capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return None
    match = re.search(r"^Pages:\s+(\d+)", result.stdout, re.M)
    return int(match.group(1)) if match else None


def emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def cmd_covers(args) -> int:
    try:
        os.nice(10)
    except OSError:
        pass
    books = collect(Path(args.dir).expanduser())
    meta = load_meta()

    # What was read most recently first: that is what the app is showing at the top.
    books.sort(key=lambda b: (b["lastRead"] is None, -(b["lastRead"] or 0), -b["added"]))

    jobs = []
    for book in books:
        info = meta.setdefault(book["id"], {})
        wants_cover = not book["cover"] and not info.get("noCover")
        wants_pages = book["format"] == "pdf" and book["pages"] is None and book["known"] and not info.get("noPages")
        if wants_cover or wants_pages:
            jobs.append((book, wants_cover, wants_pages))

    def work(job):
        book, wants_cover, wants_pages = job
        path = Path(book["path"])
        result = {"id": book["id"]}
        if wants_cover:
            cover = make_cover(path, book["id"])
            result["cover"] = str(cover) if cover else None
        if wants_pages:
            result["pages"] = page_count(path)
        return result

    done = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        for result in pool.map(work, jobs):
            info = meta.setdefault(result["id"], {})
            if "cover" in result:
                if result["cover"]:
                    emit({"id": result["id"], "cover": result["cover"]})
                else:
                    info["noCover"] = True
            if "pages" in result:
                if result["pages"]:
                    info["pages"] = result["pages"]
                    emit({"id": result["id"], "pages": result["pages"]})
                else:
                    info["noPages"] = True
            done += 1
            if done % 25 == 0:
                save_meta(meta)
    save_meta(meta)
    emit({"done": True, "jobs": len(jobs)})
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    for name, handler in (("scan", cmd_scan), ("covers", cmd_covers)):
        p = sub.add_parser(name)
        p.add_argument("--dir", default=str(HOME / "Documents" / "Books"))
        p.set_defaults(handler=handler)
    forget = sub.add_parser("forget")
    forget.add_argument("--path", required=True)
    forget.set_defaults(handler=cmd_forget)
    restore = sub.add_parser("restore")
    restore.set_defaults(handler=cmd_restore)
    args = parser.parse_args()
    return args.handler(args)


if __name__ == "__main__":
    sys.exit(main())
