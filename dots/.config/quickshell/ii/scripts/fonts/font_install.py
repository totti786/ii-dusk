#!/usr/bin/env python3
"""font_install.py: install, list and remove fonts for the current user.

  font_install.py google "Family Name"     fetch a family from the Google Fonts repository
  font_install.py file <path-or-url>       a .ttf/.otf/.ttc file, a .zip, or a folder of fonts
  font_install.py list                     what was installed through this tool
  font_install.py remove <folder>          take one of those back out

Fonts go to ~/.local/share/fonts/ii-installed/<Name>/ (your own folder, no root), each with a
marker file, and `fc-cache` is run. Only folders carrying the marker can be removed here, so this
cannot delete fonts you installed any other way. Progress lines start with "STEP"; the last line
is "RESULT <json>".

Fonts are checked by their magic bytes before they are kept, URLs must be http(s), archive paths
are flattened (no path traversal), and downloads are capped. Standard library only.
Environment: II_FONT_DIR replaces ~/.local/share/fonts (tests).
"""
from __future__ import annotations

import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile

ROOT = os.path.join(os.path.expanduser(os.environ.get("II_FONT_DIR") or "~/.local/share/fonts"), "ii-installed")
MARKER = ".ii-font.json"
FONT_EXT = (".ttf", ".otf", ".ttc", ".otc")
MAX_DOWNLOAD = 100 * 1024 * 1024
MAX_FILES = 500
LICENSE_NAMES = ("OFL.txt", "LICENSE.txt", "LICENSE", "UFL.txt", "LICENCE.txt")
GOOGLE_LICENSES = ("ofl", "apache", "ufl")
UA = {"User-Agent": "ii-shell-font-installer"}


class Fail(Exception):
    pass


def step(text: str) -> None:
    print(f"STEP {text}", flush=True)


def result(**data) -> int:
    print("RESULT " + json.dumps(data), flush=True)
    return 0 if data.get("ok") else 1


def is_font(head: bytes) -> bool:
    # TrueType, OpenType/CFF, collections, and the old Mac 'true' tag.
    return head[:4] in (b"\x00\x01\x00\x00", b"OTTO", b"ttcf", b"true")


def safe_name(text: str) -> str:
    name = re.sub(r"[^A-Za-z0-9._ -]+", "", text).strip(" .-_")
    return name[:60] or "Font"


def github_token() -> str:
    try:
        done = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, timeout=10)
        return done.stdout.strip() if done.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


def fetch(url: str, limit: int = MAX_DOWNLOAD) -> bytes:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise Fail("Only http and https links are supported.")
    headers = dict(UA)
    if parsed.hostname == "api.github.com":
        # Anonymous calls get 60 an hour per address, which a shared connection can use up. A
        # signed-in `gh` raises that to 5000. The token goes to api.github.com and nowhere else.
        token = github_token()
        if token:
            headers["Authorization"] = f"Bearer {token}"
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=40) as response:
            data = response.read(limit + 1)
    except urllib.error.HTTPError as error:
        if error.code == 403:
            if parsed.hostname == "api.github.com":
                raise Fail("GitHub's hourly limit for this connection is used up. Sign in with `gh auth login` to raise it, or try again later.")
            raise Fail("The server refused the request. Try again in a while.")
        if error.code == 404:
            raise Fail("Not found.")
        raise Fail(f"The server answered {error.code}.")
    except (urllib.error.URLError, OSError) as error:
        raise Fail(f"Could not reach the server: {getattr(error, 'reason', error)}")
    if len(data) > limit:
        raise Fail("That download is larger than the 100 MB limit.")
    return data


def fc_cache(folder: str) -> None:
    subprocess.run(["fc-cache", "-f", folder], capture_output=True, timeout=120)


def families_of(folder: str) -> list:
    files = [os.path.join(folder, f) for f in sorted(os.listdir(folder)) if f.lower().endswith(FONT_EXT)]
    if not files:
        return []
    try:
        out = subprocess.run(["fc-scan", "--format", "%{family[0]}\n", *files], capture_output=True, text=True, timeout=60).stdout
    except (OSError, subprocess.TimeoutExpired):
        return []
    seen = []
    for line in out.splitlines():
        line = line.strip()
        if line and line not in seen:
            seen.append(line)
    return seen


def new_folder(name: str) -> str:
    os.makedirs(ROOT, exist_ok=True)
    base = os.path.join(ROOT, safe_name(name))
    path = base
    n = 2
    while os.path.exists(path):
        # Reinstalling replaces our own folder; a name clash with anything else gets a suffix.
        if os.path.exists(os.path.join(path, MARKER)):
            shutil.rmtree(path)
            break
        path = f"{base} {n}"
        n += 1
    os.makedirs(path)
    return path


def keep_font(folder: str, name: str, data: bytes) -> bool:
    fname = re.sub(r"[^A-Za-z0-9._\[\], -]+", "_", os.path.basename(name)).lstrip(".")
    if not fname.lower().endswith(FONT_EXT) or not is_font(data[:4]):
        return False
    with open(os.path.join(folder, fname), "wb") as handle:
        handle.write(data)
    return True


def finish(folder: str, source: str, kept: int) -> int:
    if kept == 0:
        shutil.rmtree(folder, ignore_errors=True)
        raise Fail("No usable font files were found (.ttf, .otf, .ttc).")
    with open(os.path.join(folder, MARKER), "w", encoding="utf-8") as handle:
        json.dump({"source": source}, handle)
    step("Updating the font cache")
    fc_cache(folder)
    fams = families_of(folder)
    return result(ok=True, folder=os.path.basename(folder), families=fams, files=kept)


def install_google(family: str) -> int:
    family = family.strip()
    if not re.fullmatch(r"[A-Za-z0-9 +'-]{2,60}", family):
        raise Fail("Enter a Google Fonts family name, such as Inter or Roboto Slab.")
    slug = re.sub(r"[^a-z0-9]", "", family.lower())
    listing, licence = None, ""
    for licence in GOOGLE_LICENSES:
        step(f"Looking for {family} on Google Fonts")
        try:
            listing = json.loads(fetch(f"https://api.github.com/repos/google/fonts/contents/{licence}/{slug}", 5_000_000))
            break
        except Fail as error:
            if str(error) != "Not found.":
                raise
    if not isinstance(listing, list):
        raise Fail(f'"{family}" is not on Google Fonts. Check the spelling.')
    files = [item for item in listing if item.get("type") == "file" and item["name"].lower().endswith(FONT_EXT)]
    if not files:
        statics = [item for item in listing if item.get("type") == "dir" and item["name"].lower() == "static"]
        if statics:
            listing = json.loads(fetch(statics[0]["url"], 5_000_000))
            files = [item for item in listing if item.get("type") == "file" and item["name"].lower().endswith(FONT_EXT)]
    if not files:
        raise Fail("That family has no font files in the repository.")
    folder = new_folder(family)
    kept, total = 0, 0
    try:
        for item in files[:MAX_FILES]:
            step(f"Downloading {item['name']}")
            url = item.get("download_url") or ""
            if urllib.parse.urlparse(url).hostname != "raw.githubusercontent.com":
                continue
            data = fetch(url)
            total += len(data)
            if total > MAX_DOWNLOAD:
                raise Fail("That family is larger than the 100 MB limit.")
            kept += 1 if keep_font(folder, item["name"], data) else 0
        for item in listing:
            if item.get("type") == "file" and item["name"] in LICENSE_NAMES and item.get("download_url"):
                with open(os.path.join(folder, item["name"]), "wb") as handle:
                    handle.write(fetch(item["download_url"], 1_000_000))
    except Fail:
        shutil.rmtree(folder, ignore_errors=True)
        raise
    return finish(folder, f"google:{licence}/{slug}", kept)


def collect_zip(data: bytes, folder: str) -> int:
    kept = 0
    try:
        archive = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile:
        raise Fail("That is not a valid zip file.")
    total = 0
    for info in archive.infolist()[:5000]:
        base = os.path.basename(info.filename)  # flattened: no folders, no ".." tricks
        if info.is_dir() or not base.lower().endswith(FONT_EXT):
            continue
        total += info.file_size
        if total > MAX_DOWNLOAD or kept >= MAX_FILES:
            raise Fail("That archive holds too much data.")
        with archive.open(info) as handle:
            kept += 1 if keep_font(folder, base, handle.read()) else 0
    return kept


def install_file(source: str) -> int:
    source = source.strip()
    if not source:
        raise Fail("Give a file, a folder or a link.")
    if source.startswith("file://"):
        source = urllib.parse.unquote(urllib.parse.urlparse(source).path)
    if re.match(r"https?://", source, re.I):
        step("Downloading")
        data = fetch(source)
        name = urllib.parse.unquote(os.path.basename(urllib.parse.urlparse(source).path)) or "Font"
        stem = os.path.splitext(name)[0]
        folder = new_folder(stem)
        try:
            kept = collect_zip(data, folder) if data[:4] == b"PK\x03\x04" else (1 if keep_font(folder, name if name.lower().endswith(FONT_EXT) else name + ".ttf", data) else 0)
        except Fail:
            shutil.rmtree(folder, ignore_errors=True)
            raise
        return finish(folder, source, kept)
    path = os.path.expanduser(source)
    if not os.path.exists(path):
        raise Fail("That path does not exist.")
    stem = os.path.splitext(os.path.basename(path.rstrip("/")))[0]
    folder = new_folder(stem)
    kept = 0
    try:
        if os.path.isdir(path):
            step("Copying fonts from the folder")
            for dirpath, _dirs, names in os.walk(path):
                for name in sorted(names):
                    if name.lower().endswith(FONT_EXT) and kept < MAX_FILES:
                        with open(os.path.join(dirpath, name), "rb") as handle:
                            kept += 1 if keep_font(folder, name, handle.read(MAX_DOWNLOAD)) else 0
        else:
            with open(path, "rb") as handle:
                data = handle.read(MAX_DOWNLOAD + 1)
            if len(data) > MAX_DOWNLOAD:
                raise Fail("That file is larger than the 100 MB limit.")
            if data[:4] == b"PK\x03\x04":
                step("Unpacking")
                kept = collect_zip(data, folder)
            else:
                kept = 1 if keep_font(folder, os.path.basename(path), data) else 0
    except Fail:
        shutil.rmtree(folder, ignore_errors=True)
        raise
    return finish(folder, path, kept)


def listing() -> int:
    items = []
    if os.path.isdir(ROOT):
        for name in sorted(os.listdir(ROOT), key=str.lower):
            folder = os.path.join(ROOT, name)
            if not os.path.exists(os.path.join(folder, MARKER)):
                continue
            files = [f for f in os.listdir(folder) if f.lower().endswith(FONT_EXT)]
            size = sum(os.path.getsize(os.path.join(folder, f)) for f in files)
            items.append({"folder": name, "families": families_of(folder), "files": len(files), "bytes": size})
    return result(ok=True, items=items)


def remove(folder_name: str) -> int:
    if not folder_name or folder_name in (".", "..") or "/" in folder_name or "\\" in folder_name:
        raise Fail("Not a folder this tool installed.")
    folder = os.path.join(ROOT, folder_name)
    if not os.path.isdir(folder) or not os.path.exists(os.path.join(folder, MARKER)):
        raise Fail("Not a folder this tool installed.")
    shutil.rmtree(folder)
    fc_cache(os.path.dirname(folder))
    return result(ok=True, removed=folder_name)


def main(argv: list) -> int:
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        cmd, rest = argv[0], argv[1:]
        if cmd == "google" and rest:
            return install_google(" ".join(rest))
        if cmd == "file" and rest:
            return install_file(" ".join(rest))
        if cmd == "list":
            return listing()
        if cmd == "remove" and rest:
            return remove(" ".join(rest))
    except Fail as error:
        return result(ok=False, error=str(error))
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
