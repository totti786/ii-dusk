#!/usr/bin/env python3
"""Book sources for the Quickshell Books app: browse, search and download over OPDS.

OPDS is the catalogue protocol that Calibre-Web, Calibre's content server, Kavita, Komga and
COPS speak, and that public-domain libraries such as Project Gutenberg publish. A source is
just a catalogue URL, so a self-hosted server and a public library are handled the same way.

Commands, all printing JSON (download prints JSON lines):

  sources                                  every source, built-in ones first
  source-add --name N --url U [--user X]   add one; with --user the password is read from stdin
                                           and kept in the system keyring (secret-tool)
  source-remove --id ID                    forget a source and its stored password
  browse --id ID [--url U] [--query Q]     one page of a catalogue, or search results
  download --id ID --url U --dest DIR --title T [--author A] [--ext E]
                                           stream a file into DIR; prints {"progress", "total"}
                                           lines and a final {"done": true, "path": ...}

Nothing here is written outside the sources file, the keyring and the download folder.
"""

from __future__ import annotations

import argparse
import base64
import html
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

# `python3 -I` does not put the script directory on sys.path (verified), so a
# sibling module must be added explicitly before importing it.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import libgen_source  # noqa: E402 — sibling adapter
import manga_source  # noqa: E402 — sibling adapter
import zlib_source  # noqa: E402 — sibling adapter
from zlib_source import SourceError  # noqa: E402 — shared error type

USER_AGENT = "ii-books/1.0 (quickshell)"
TIMEOUT = 25
MAX_FEED_BYTES = 10 * 1024 * 1024
MAX_DOWNLOAD_BYTES = 1024 * 1024 * 1024
SECRET_SERVICE = "ii-books"

ATOM = "{http://www.w3.org/2005/Atom}"
OPENSEARCH = "{http://a9.com/-/spec/opensearch/1.1/}"

# Formats the viewers open. Everything else a catalogue offers (Kindle, plain text, HTML) is
# left out rather than downloaded into a library that cannot show it.
EXT_BY_TYPE = {
    "application/epub+zip": "epub",
    "application/pdf": "pdf",
    "image/vnd.djvu": "djvu",
    "image/x-djvu": "djvu",
    "application/x-cbz": "cbz",
    "application/vnd.comicbook+zip": "cbz",
    "application/zip+cbz": "cbz",
}
SUPPORTED_EXTS = {"epub", "pdf", "djvu", "cbz"}

BUILTIN_SOURCES = [
    {
        "id": "gutenberg",
        "name": "Project Gutenberg",
        "url": "https://www.gutenberg.org/ebooks.opds/",
        "user": "",
        "builtin": True,
    },
    {
        "id": "zlib",
        "name": "Z-Library",
        "url": "zlib:",
        "user": "",
        "builtin": True,
        "kind": "zlib",
    },
    {
        "id": "libgen",
        "name": "Library Genesis",
        "url": "libgen:",
        "user": "",
        "builtin": True,
        "kind": "libgen",
    },
    {
        "id": "manga",
        "name": "Manga (MangaDex)",
        "url": "manga:",
        "user": "",
        "builtin": True,
        "kind": "manga",
    },
]

CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
SOURCES_FILE = CONFIG_HOME / "ii-books" / "sources.json"


# SourceError comes from zlib_source (imported above) so both modules raise one type.


# ------------------------------------------------------------------ sources


def load_user_sources() -> list[dict]:
    try:
        data = json.loads(SOURCES_FILE.read_text())
    except (OSError, ValueError):
        return []
    sources = []
    for item in data if isinstance(data, list) else []:
        if isinstance(item, dict) and item.get("id") and item.get("url"):
            sources.append({
                "id": str(item["id"]),
                "name": str(item.get("name") or item["id"]),
                "url": str(item["url"]),
                "user": str(item.get("user") or ""),
                "builtin": False,
            })
    return sources


def save_user_sources(sources: list[dict]) -> None:
    SOURCES_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = SOURCES_FILE.with_suffix(".tmp")
    keep = [{k: s[k] for k in ("id", "name", "url", "user")} for s in sources]
    tmp.write_text(json.dumps(keep, indent=2))
    tmp.replace(SOURCES_FILE)


def all_sources() -> list[dict]:
    return BUILTIN_SOURCES + load_user_sources()


def find_source(source_id: str) -> dict:
    for source in all_sources():
        if source["id"] == source_id:
            return source
    raise SourceError("unknown_source", f"No source called {source_id!r}.")


def slug(name: str) -> str:
    base = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return base or "source"


def check_url(url: str) -> str:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise SourceError("bad_url", "A source needs an http:// or https:// address.")
    return url


def origin(url: str) -> tuple[str, str]:
    parsed = urllib.parse.urlparse(url)
    return parsed.scheme, parsed.netloc.lower()


def password_for(source: dict) -> str:
    override = os.environ.get("II_BOOKS_PASSWORD")
    if override is not None:
        return override
    if not source.get("user") or not shutil.which("secret-tool"):
        return ""
    try:
        result = subprocess.run(
            ["secret-tool", "lookup", "service", SECRET_SERVICE, "source", source["id"]],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return result.stdout.rstrip("\n") if result.returncode == 0 else ""


def store_password(source_id: str, name: str, password: str) -> None:
    if not shutil.which("secret-tool"):
        raise SourceError("no_keyring", "secret-tool (libsecret) is needed to store a password.")
    try:
        result = subprocess.run(
            ["secret-tool", "store", f"--label=ii Books: {name}",
             "service", SECRET_SERVICE, "source", source_id],
            input=password, capture_output=True, text=True, timeout=15,
        )
    except (OSError, subprocess.SubprocessError) as err:
        raise SourceError("no_keyring", f"Could not reach the keyring: {err}") from err
    if result.returncode != 0:
        raise SourceError("no_keyring", "The keyring refused the password. Is it unlocked?")


def clear_password(source_id: str) -> None:
    if not shutil.which("secret-tool"):
        return
    try:
        subprocess.run(["secret-tool", "clear", "service", SECRET_SERVICE, "source", source_id],
                       capture_output=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        pass


# ------------------------------------------------------------------ network


class _SameOriginAuth(urllib.request.HTTPRedirectHandler):
    """Follow redirects, but never carry the password to another site."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new is not None and origin(newurl) != origin(req.full_url):
            new.headers.pop("Authorization", None)
            new.unredirected_hdrs.pop("Authorization", None)
        return new


def open_url(source: dict, url: str, accept: str = "*/*"):
    check_url(url)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": accept})
    if source.get("user") and origin(url) == origin(source["url"]):
        token = base64.b64encode(f"{source['user']}:{password_for(source)}".encode()).decode()
        request.add_header("Authorization", f"Basic {token}")
    opener = urllib.request.build_opener(_SameOriginAuth)
    try:
        return opener.open(request, timeout=TIMEOUT)
    except urllib.error.HTTPError as err:
        if err.code in (401, 403):
            raise SourceError("auth", "The server wants a login. Check the username and password.") from err
        if err.code == 404:
            raise SourceError("not_found", "That page does not exist on the server.") from err
        raise SourceError("http", f"The server answered {err.code}.") from err
    except urllib.error.URLError as err:
        raise SourceError("network", f"Could not reach the server: {err.reason}") from err
    except (TimeoutError, OSError) as err:
        raise SourceError("network", f"Could not reach the server: {err}") from err


def fetch_xml(source: dict, url: str) -> tuple[ET.Element, str]:
    with open_url(source, url, "application/atom+xml, application/xml;q=0.9, */*;q=0.5") as response:
        final_url = response.geturl()
        body = response.read(MAX_FEED_BYTES + 1)
    if len(body) > MAX_FEED_BYTES:
        raise SourceError("too_big", "The catalogue page is too large.")
    try:
        return ET.fromstring(body), final_url
    except ET.ParseError as err:
        raise SourceError("not_opds", "That address did not return an OPDS catalogue.") from err


# ------------------------------------------------------------------ parsing


def text_of(element: ET.Element | None) -> str:
    if element is None:
        return ""
    raw = "".join(element.itertext())
    return re.sub(r"\s+", " ", html.unescape(raw)).strip()


def http_url(base: str, href: str | None) -> str:
    if not href:
        return ""
    absolute = urllib.parse.urljoin(base, html.unescape(href))
    return absolute if urllib.parse.urlparse(absolute).scheme in ("http", "https") else ""


def ext_for(link_type: str, href: str) -> str:
    kind = link_type.split(";")[0].strip().lower()
    if kind in EXT_BY_TYPE:
        return EXT_BY_TYPE[kind]
    suffix = Path(urllib.parse.urlparse(href).path).suffix.lower().lstrip(".")
    return suffix if suffix in SUPPORTED_EXTS else ""


def parse_entry(entry: ET.Element, base: str) -> dict | None:
    title = text_of(entry.find(f"{ATOM}title"))
    if not title:
        return None
    authors = [text_of(a.find(f"{ATOM}name")) for a in entry.findall(f"{ATOM}author")]
    summary_node = entry.find(f"{ATOM}summary")
    if summary_node is None:
        summary_node = entry.find(f"{ATOM}content")
    summary = text_of(summary_node)
    # Project Gutenberg wraps the blurb in credits and metadata; keep just the blurb.
    blurb = re.search(r"Summary:\s*(.*?)(?:\s+Reading Level:|\s+Author:|$)", summary)
    if blurb:
        summary = blurb.group(1).strip()

    cover = thumb = nav = ""
    formats: list[dict] = []
    related: list[dict] = []
    for link in entry.findall(f"{ATOM}link"):
        rel = link.get("rel") or ""
        kind = link.get("type") or ""
        href = http_url(base, link.get("href"))
        if not href:
            continue
        if rel.startswith("http://opds-spec.org/acquisition"):
            ext = ext_for(kind, href)
            if ext:
                formats.append({"href": href, "ext": ext, "label": link.get("title") or ext.upper(),
                                "size": int(link.get("length") or 0) if (link.get("length") or "").isdigit() else 0})
        elif rel == "http://opds-spec.org/image":
            cover = href
        elif rel == "http://opds-spec.org/image/thumbnail":
            thumb = href
        elif "opds-catalog" in kind or "atom+xml" in kind:
            if rel in ("subsection", "http://opds-spec.org/sort/new", "http://opds-spec.org/sort/popular",
                       "http://opds-spec.org/featured", "http://opds-spec.org/recommended", "") and not nav:
                nav = href
            elif rel == "related":
                related.append({"title": (link.get("title") or "").rstrip("…").strip(), "href": href})

    has_acquisition = any(l.get("rel", "").startswith("http://opds-spec.org/acquisition")
                          for l in entry.findall(f"{ATOM}link"))
    if formats or has_acquisition:
        return {
            "kind": "book",
            "title": title,
            "author": ", ".join(a for a in authors if a),
            "summary": summary[:2400],
            "cover": cover or thumb,
            "thumb": thumb or cover,
            "formats": formats,
            "related": related[:10],
            "href": nav,
        }
    if nav:
        return {"kind": "nav", "title": title, "subtitle": summary[:200], "href": nav,
                "thumb": thumb if thumb else ""}
    return None


def link_href(root: ET.Element, base: str, rel: str) -> str:
    for link in root.findall(f"{ATOM}link"):
        if link.get("rel") == rel:
            return http_url(base, link.get("href"))
    return ""


def norm_title(title: str) -> str:
    return re.sub(r"\W+", " ", title.lower()).strip()


def parse_feed(root: ET.Element, base: str) -> dict:
    entries = [e for e in (parse_entry(node, base) for node in root.findall(f"{ATOM}entry")) if e]
    books = [e for e in entries if e["kind"] == "book"]
    navs = [e for e in entries if e["kind"] == "nav"]

    detail = None
    # A book's own page lists its editions as entries with the same title: merge them.
    if books and not navs and len({norm_title(b["title"]) for b in books}) == 1:
        detail = dict(books[0])
        seen = set()
        merged = []
        for book in books:
            for fmt in book["formats"]:
                if fmt["href"] not in seen:
                    seen.add(fmt["href"])
                    merged.append(fmt)
            detail["cover"] = detail["cover"] or book["cover"]
            detail["summary"] = detail["summary"] or book["summary"]
            detail["related"] = detail["related"] or book["related"]
        order = {"epub": 0, "pdf": 1, "djvu": 2, "cbz": 3}
        detail["formats"] = sorted(merged, key=lambda f: (order.get(f["ext"], 9), -f["size"]))
        detail["kind"] = "detail"

    return {
        "title": text_of(root.find(f"{ATOM}title")),
        "entries": entries,
        "detail": detail,
        "next": link_href(root, base, "next"),
        "search": any(l.get("rel") == "search" for l in root.findall(f"{ATOM}link")),
    }


def search_template(source: dict, root: ET.Element, base: str) -> str:
    """The URL pattern to search with, from an OPDS search link or its OpenSearch description."""
    for link in root.findall(f"{ATOM}link"):
        if link.get("rel") != "search":
            continue
        href = http_url(base, link.get("href"))
        kind = link.get("type") or ""
        if "{searchTerms}" in (link.get("href") or ""):
            return urllib.parse.urljoin(base, link.get("href"))
        if not href:
            continue
        description, description_url = fetch_xml(source, href)
        for node in description.iter():
            if node.tag.endswith("Url") and "atom" in (node.get("type") or "") and node.get("template"):
                return urllib.parse.urljoin(description_url, node.get("template"))
        if "atom" in kind:
            return href
    raise SourceError("no_search", "This catalogue has no search.")


# ------------------------------------------------------------------ commands


def emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def cmd_sources(args) -> int:
    emit({"sources": [dict(s, hasPassword=bool(s["user"])) for s in all_sources()]})
    return 0


def cmd_source_add(args) -> int:
    url = check_url(args.url.strip())
    name = args.name.strip() or urllib.parse.urlparse(url).netloc
    user = (args.user or "").strip()
    sources = load_user_sources()
    taken = {s["id"] for s in all_sources()}
    base_id, n = slug(name), 1
    source_id = base_id
    while source_id in taken:
        n += 1
        source_id = f"{base_id}-{n}"
    if user:
        password = sys.stdin.readline().rstrip("\n")
        store_password(source_id, name, password)
    sources.append({"id": source_id, "name": name, "url": url, "user": user})
    save_user_sources(sources)
    emit({"ok": True, "id": source_id})
    return 0


def cmd_source_remove(args) -> int:
    sources = load_user_sources()
    if not any(s["id"] == args.id for s in sources):
        raise SourceError("unknown_source", "That source cannot be removed.")
    clear_password(args.id)
    save_user_sources([s for s in sources if s["id"] != args.id])
    emit({"ok": True})
    return 0


def cmd_login(args) -> int:
    source = find_source(args.id)
    if source.get("kind") != "zlib":
        raise SourceError("unsupported", "This source does not need a login.")
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        raise SourceError("input", "Credentials must be a JSON object.")
    if not isinstance(payload, dict):
        raise SourceError("input", "Credentials must be a JSON object.")
    emit(zlib_source.login(payload))
    return 0


def cmd_settings(args) -> int:
    source = find_source(args.id)
    if source.get("kind") != "zlib":
        raise SourceError("unsupported", "This source has no settings.")
    emit(zlib_source.settings(args.domain))
    return 0


def cmd_browse(args) -> int:
    source = find_source(args.id)
    if source.get("kind") == "zlib":
        emit(zlib_source.browse(query=args.query, url=args.url))
        return 0
    if source.get("kind") == "libgen":
        emit({**libgen_source.browse(query=args.query, url=args.url)})
        return 0
    if source.get("kind") == "manga":
        try:
            page = manga_source.browse(args.url, args.query)
        except manga_source.MangaError as error:
            emit({"ok": False, "message": str(error)})
            return 1
        page["ok"] = True
        emit(page)
        return 0
    url = args.url or source["url"]
    if args.query:
        root, base = fetch_xml(source, source["url"])
        template = search_template(source, root, base)
        url = template.replace("{searchTerms}", urllib.parse.quote_plus(args.query))
        url = re.sub(r"\{[^}]*\?\}", "", url)  # optional OpenSearch parameters
    root, base = fetch_xml(source, url)
    page = parse_feed(root, base)
    page["url"] = base
    page["ok"] = True
    emit(page)
    return 0


def safe_name(text: str) -> str:
    cleaned = re.sub(r'[\\/:*?"<>|\x00-\x1f]+', " ", text)
    return re.sub(r"\s+", " ", cleaned).strip(" .")[:120] or "book"


def cmd_download(args) -> int:
    source = find_source(args.id)
    if source.get("kind") == "zlib":
        emit(zlib_source.download(args.url, args.dest, args.title, args.author, args.ext))
        return 0
    if source.get("kind") == "libgen":
        emit(libgen_source.download(args.url, args.dest, args.title, args.author, args.ext))
        return 0
    if source.get("kind") == "manga":
        try:
            emit(manga_source.download(args.url, args.dest, emit))
        except manga_source.MangaError as error:
            emit({"ok": False, "message": str(error)})
            return 1
        return 0
    dest = Path(args.dest).expanduser()
    dest.mkdir(parents=True, exist_ok=True)
    ext = (args.ext or "").lower().lstrip(".")

    with open_url(source, args.url) as response:
        if not ext:
            ext = ext_for(response.headers.get("Content-Type", ""), response.geturl())
        if ext not in SUPPORTED_EXTS:
            raise SourceError("unsupported", "That file type is not one the viewers can open.")
        total = int(response.headers.get("Content-Length") or 0)
        if total > MAX_DOWNLOAD_BYTES:
            raise SourceError("too_big", "The file is larger than 1 GB.")

        stem = safe_name(f"{args.author} - {args.title}" if args.author else args.title)
        target = dest / f"{stem}.{ext}"
        counter = 2
        while target.exists():
            target = dest / f"{stem} ({counter}).{ext}"
            counter += 1
        partial = target.with_name(target.name + ".part")

        def cleanup(*_):
            partial.unlink(missing_ok=True)
            raise SystemExit(1)

        signal.signal(signal.SIGTERM, cleanup)
        received = 0
        last_report = 0.0
        try:
            with open(partial, "wb") as out:
                while True:
                    chunk = response.read(256 * 1024)
                    if not chunk:
                        break
                    received += len(chunk)
                    if received > MAX_DOWNLOAD_BYTES:
                        raise SourceError("too_big", "The file is larger than 1 GB.")
                    out.write(chunk)
                    if received - last_report >= 128 * 1024:
                        last_report = received
                        emit({"progress": received, "total": total})
            if received == 0:
                raise SourceError("empty", "The server sent an empty file.")
            partial.replace(target)
        except BaseException:
            partial.unlink(missing_ok=True)
            raise
    emit({"done": True, "path": str(target), "size": received})
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("sources").set_defaults(handler=cmd_sources)

    add = sub.add_parser("source-add")
    add.add_argument("--name", default="")
    add.add_argument("--url", required=True)
    add.add_argument("--user", default="")
    add.set_defaults(handler=cmd_source_add)

    remove = sub.add_parser("source-remove")
    remove.add_argument("--id", required=True)
    remove.set_defaults(handler=cmd_source_remove)

    login = sub.add_parser("login")
    login.add_argument("--id", required=True)
    login.set_defaults(handler=cmd_login)

    settings = sub.add_parser("settings")
    settings.add_argument("--id", required=True)
    settings.add_argument("--domain", default=None)
    settings.set_defaults(handler=cmd_settings)

    browse = sub.add_parser("browse")
    browse.add_argument("--id", required=True)
    browse.add_argument("--url", default="")
    browse.add_argument("--query", default="")
    browse.set_defaults(handler=cmd_browse)

    download = sub.add_parser("download")
    download.add_argument("--id", required=True)
    download.add_argument("--url", required=True)
    download.add_argument("--dest", required=True)
    download.add_argument("--title", required=True)
    download.add_argument("--author", default="")
    download.add_argument("--ext", default="")
    download.set_defaults(handler=cmd_download)

    args = parser.parse_args()
    try:
        return args.handler(args)
    except SourceError as err:
        emit({"ok": False, "error": err.code, "message": err.message})
        return 1


if __name__ == "__main__":
    sys.exit(main())
