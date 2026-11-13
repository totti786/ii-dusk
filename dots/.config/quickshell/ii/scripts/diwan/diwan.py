#!/usr/bin/env python3
"""diwan.py: a small bridge between the shell and the Qafiyah poetry catalogue (api.qafiyah.com).

  diwan.py poem SLUG             one poem with its verses, poet, era, meter, neighbours
  diwan.py random                a random poem
  diwan.py search QUERY [--page N] [--section poems|poets]
  diwan.py list [--poet S] [--era S] [--meter S] [--theme S] [--collection S] [--page N]
  diwan.py poets [QUERY] [--page N]
  diwan.py terms KIND            eras | meters | themes | collections
  diwan.py home                  themes, eras, meters and collections in one go
  diwan.py daily                 the poem of the day (the same all day, at most three requests)
  diwan.py verses SLUG:N...      saved verses, from the cache only
  diwan.py library SLUG...       title/poet of poems already cached (never touches the network)

Every command prints one JSON object: {"ok": true, ...} or {"ok": false, "error": "..."}.
The API allows 60 requests an hour without a key, so everything is cached under
~/.cache/diwan: poems for good, lists for a day, vocabularies for a month. A key (500 an hour)
is read from QAFIYAH_API_KEY or from ~/.config/diwan/key.
"""
import argparse
import base64
import datetime
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://api.qafiyah.com/v1"
USER_AGENT = "diwan-quickshell/1.0 (+https://qafiyah.com)"
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "diwan")
DAY = 86400
SLUG = re.compile(r"^[A-Za-z0-9_-]{1,40}$")


class ApiError(Exception):
    pass


def api_key():
    key = os.environ.get("QAFIYAH_API_KEY", "").strip()
    if key:
        return key
    try:
        with open(os.path.expanduser("~/.config/diwan/key")) as f:
            return f.read().strip()
    except OSError:
        return ""


def api_get(path, params=None, raw=False):
    query = []
    for name, value in (params or {}).items():
        if value is None or value == "":
            continue
        for item in value if isinstance(value, (list, tuple)) else [value]:
            query.append((name, str(item)))
    url = BASE + path + ("?" + urllib.parse.urlencode(query) if query else "")
    headers = {"User-Agent": USER_AGENT, "Accept": "text/plain" if raw else "application/json"}
    key = api_key()
    if key:
        headers["x-api-key"] = key
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=25) as r:
            body = r.read().decode("utf-8")
            return body if raw else json.loads(body)
    except urllib.error.HTTPError as err:
        if err.code in (429, 503):
            retry = err.headers.get("Retry-After")
            wait = ""
            if retry and retry.isdigit():
                wait = f" حاول بعد {max(1, int(retry) // 60)} دقيقة."
            raise ApiError("طُلب من خدمة الشعر أكثر من المسموح به الآن." + wait) from None
        if err.code == 404:
            raise ApiError("لم يُعثر عليه.") from None
        raise ApiError(f"ردّت خدمة الشعر برمز {err.code}.") from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise ApiError("تعذّر الاتصال بخدمة الشعر. تحقّق من الاتصال بالإنترنت.") from None
    except ValueError:
        raise ApiError("أرسلت خدمة الشعر ما لا يمكن قراءته.") from None


# ------------------------------------------------------------------ cache


def cache_path(kind, name):
    # Arabic queries would all collapse to underscores, so anything but plain slugs is hashed
    safe = name if re.fullmatch(r"[A-Za-z0-9_.-]{1,80}", name) else hashlib.sha1(name.encode()).hexdigest()
    return os.path.join(CACHE, kind, safe + ".json")


def cache_read(kind, name, ttl=None):
    path = cache_path(kind, name)
    try:
        if ttl is not None and time.time() - os.path.getmtime(path) > ttl:
            return None
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def cache_write(kind, name, value):
    path = cache_path(kind, name)
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(value, f, ensure_ascii=False)
        os.replace(tmp, path)
    except OSError:
        pass


def cached(kind, name, ttl, fetch):
    hit = cache_read(kind, name, ttl)
    if hit is not None:
        return hit
    try:
        value = fetch()
    except ApiError:
        stale = cache_read(kind, name)  # better an old answer than none
        if stale is not None:
            return stale
        raise
    cache_write(kind, name, value)
    return value


# ----------------------------------------------------------------- shaping


def clean(text):
    """Search results wrap hits in <mark>; the reader shows plain text."""
    return re.sub(r"</?mark>", "", text or "")


def name_of(value):
    return (value or {}).get("name", "") if isinstance(value, dict) else ""


def slim_poem(p):
    verses = []
    for v in p.get("verses") or []:
        halves = [clean(h).strip() for h in v if h and clean(h).strip()]
        if halves:
            verses.append(halves)
    return {
        "slug": p.get("slug", ""),
        "title": clean(p.get("title")) or "",
        "verses": verses,
        "poet": name_of(p.get("poet")),
        "poetSlug": (p.get("poet") or {}).get("slug", ""),
        "era": name_of(p.get("era")),
        "eraSlug": (p.get("era") or {}).get("slug", ""),
        "meter": name_of(p.get("meter")),
        "meterSlug": (p.get("meter") or {}).get("slug", ""),
        "rhyme": name_of(p.get("rhyme")),
        "theme": name_of(p.get("theme")),
        "form": name_of(p.get("poemType")),
        "formSlug": (p.get("poemType") or {}).get("slug", ""),
        "prev": p.get("prev") or None,
        "next": p.get("next") or None,
        "related": [
            {"slug": r.get("slug", ""), "title": clean(r.get("title")),
             "poet": name_of(r.get("poet")), "era": name_of(r.get("era")),
             "meter": name_of(r.get("meter"))}
            for r in (p.get("relatedPoems") or [])[:6]
        ],
        "recensions": [
            {"slug": r.get("slug", ""), "title": clean(r.get("title"))}
            for r in (p.get("recensions") or [])[:6]
        ],
    }


def slim_row(r):
    return {
        "slug": r.get("slug", ""),
        "title": clean(r.get("title")) or "",
        "poet": name_of(r.get("poet")),
        "poetSlug": (r.get("poet") or {}).get("slug", ""),
        "era": name_of(r.get("era")),
        "meter": name_of(r.get("meter")),
        "snippet": clean(r.get("snippet") or r.get("sample") or "").replace(" * ", "   ").replace("*", "   ").strip(),
    }


def fetch_poem(slug):
    if not SLUG.match(slug):
        raise ApiError("هذا ليس عنوان قصيدة.")
    return cached("poems", slug, None, lambda: slim_poem(api_get(f"/poems/{slug}")["data"]))


def page_of(data, page=1, size=30):
    """The API pages by opaque cursor now; the UI still shows "page N of M", worked out from the total."""
    total = int(data.get("total") or 0)
    return {"page": page, "pages": max(1, -(-total // size)), "total": total}


def encode_cursor(obj):
    return base64.urlsafe_b64encode(json.dumps(obj, separators=(",", ":")).encode()).decode().rstrip("=")


def chained(kind, key, page, request, build):
    """Page N of a cursor-paged listing. Each page's answer is cached with the cursor of the next, so
    stepping forward costs one request; jumping ahead walks the pages in between (each cached after)."""
    cursor = None
    for n in range(1, page + 1):
        name = f"{key}-p{n}"
        hit = cache_read(kind, name, DAY)
        if hit is None:
            data = request(cursor)
            hit = {**build(data, n), "_next": data.get("next") or ""}
            cache_write(kind, name, hit)
        cursor = hit["_next"]
        if not cursor and n < page:
            raise ApiError("لا صفحات بعد هذه.")
    return {k: v for k, v in hit.items() if k != "_next"}


# ---------------------------------------------------------------- commands


def cmd_poem(a):
    return {"poem": fetch_poem(a.slug)}


def cmd_random(a):
    slug = api_get("/poems/random", {"option": "slug"}, raw=True).strip().strip('"')
    return {"poem": fetch_poem(slug)}


def cmd_search(a):
    key = f"{a.section}-{a.page}-{a.query}"
    page = max(1, int(a.page))
    params = {"q": a.query, "types": a.section}
    if page > 1:  # offset cursors are plain, so any page is one request
        params["poemsCursor" if a.section == "poems" else "poetsCursor"] = encode_cursor({"offset": (page - 1) * 20})

    def fetch():
        data = api_get("/search", params)
        poems, poets = data.get("poems") or {}, data.get("poets") or {}
        if a.section == "poets":
            return {"poets": [{"slug": r.get("slug", ""), "name": clean(r.get("name")), "era": name_of(r.get("era")),
                               "count": r.get("poemsCount", 0)} for r in poets.get("data") or []],
                    **page_of(poets, page, 20)}
        return {"poems": [slim_row(r) for r in poems.get("data") or []], **page_of(poems, page, 20)}
    return cached("search", key, DAY, fetch)


def cmd_list(a):
    params = {"poet": a.poet, "era": a.era, "theme": a.theme, "meter": a.meter, "collection": a.collection}
    key = "-".join(f"{k}={v}" for k, v in sorted(params.items()) if v) or "all"
    return chained("list", key, max(1, int(a.page)),
                   lambda c: api_get("/poems", {**params, "cursor": c}),
                   lambda d, n: {"poems": [slim_row(r) for r in d.get("data") or []], **page_of(d, n)})


def cmd_poets(a):
    return chained("poets", a.query or "all", max(1, int(a.page)),
                   lambda c: api_get("/poets", {"q": a.query, "cursor": c}),
                   lambda d, n: {"poets": [{"slug": r.get("slug", ""), "name": clean(r.get("name")),
                                            "era": name_of(r.get("era")), "count": r.get("poemsCount", 0)}
                                           for r in d.get("data") or []], **page_of(d, n)})


def terms_of(kind):
    def fetch():
        return {"terms": [{"slug": r.get("slug", ""), "name": r.get("name", ""),
                           "count": r.get("poemsCount", 0)} for r in api_get(f"/{kind}")["data"]]}
    return cached("terms", kind, 30 * DAY, fetch)["terms"]


def cmd_terms(a):
    return {"terms": terms_of(a.kind)}


def cmd_home(a):
    return {kind: terms_of(kind) for kind in ("themes", "eras", "meters", "collections")}


DAILY_THEMES = ("alhikma", "alnasib", "almadih", "alzuhd", "alritha", "alhamasa", "alwasf", "alitab")


def cmd_daily(a):
    """One poem per calendar day, picked by arithmetic on the date so it never changes within
    the day: a theme by the weekday cycle, a page and a row of that theme's listing."""
    today = datetime.date.today()
    day = today.toordinal()

    def listing(page):
        return cmd_list(argparse.Namespace(page=str(page), poet=None, era=None, meter=None,
                                           theme=DAILY_THEMES[day % len(DAILY_THEMES)], collection=None))

    def fetch():
        first = listing(1)
        pages = max(1, min(first["pages"], 6))  # deeper pages cost a request per step
        page = (day * 7919) % pages + 1
        rows = (first if page == 1 else listing(page))["poems"]
        best = None
        for k in range(len(rows)):
            row = rows[(day * 31 + k) % len(rows)]
            poem = fetch_poem(row["slug"])
            if poem["verses"] and (best is None or len(poem["verses"]) > len(best["verses"])):
                best = poem
            if len(poem["verses"]) >= 4:
                break
            if k >= 7 and best is not None:
                break
        if best is not None:
            poem = best
            return {"slug": poem["slug"], "title": poem["title"], "poet": poem["poet"], "era": poem["era"],
                    "meter": poem["meter"], "verse": poem["verses"][0], "count": len(poem["verses"])}
        raise ApiError("لا قصيدة اليوم.")
    return {"daily": cached("daily", today.isoformat(), None, fetch)}


def cmd_verses(a):
    out = []
    for key in a.keys[:300]:
        slug, _, idx = key.partition(":")
        if not SLUG.match(slug) or not idx.isdigit():
            continue
        p = cache_read("poems", slug)
        if p and int(idx) < len(p["verses"]):
            out.append({"slug": slug, "index": int(idx), "title": p["title"], "poet": p["poet"], "era": p["era"],
                        "meter": "", "snippet": "   ".join(p["verses"][int(idx)])})
    return {"poems": out}


def cmd_library(a):
    out = []
    for slug in a.slugs[:200]:
        if not SLUG.match(slug):
            continue
        p = cache_read("poems", slug)
        if p:
            out.append({"slug": slug, "title": p["title"], "poet": p["poet"], "era": p["era"],
                        "meter": p["meter"], "snippet": "   ".join(p["verses"][0]) if p["verses"] else ""})
    return {"poems": out}


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("poem")
    p.add_argument("slug")
    p.set_defaults(func=cmd_poem)

    sub.add_parser("random").set_defaults(func=cmd_random)

    p = sub.add_parser("search")
    p.add_argument("query")
    p.add_argument("--page", default="1")
    p.add_argument("--section", choices=("poems", "poets"), default="poems")
    p.set_defaults(func=cmd_search)

    p = sub.add_parser("list")
    p.add_argument("--page", default="1")
    for flag in ("poet", "era", "meter", "theme", "collection"):
        p.add_argument("--" + flag)
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("poets")
    p.add_argument("query", nargs="?")
    p.add_argument("--page", default="1")
    p.set_defaults(func=cmd_poets)

    p = sub.add_parser("terms")
    p.add_argument("kind", choices=("eras", "meters", "themes", "collections"))
    p.set_defaults(func=cmd_terms)

    sub.add_parser("home").set_defaults(func=cmd_home)

    sub.add_parser("daily").set_defaults(func=cmd_daily)

    p = sub.add_parser("verses")
    p.add_argument("keys", nargs="*")
    p.set_defaults(func=cmd_verses)

    p = sub.add_parser("library")
    p.add_argument("slugs", nargs="*")
    p.set_defaults(func=cmd_library)
    return parser


def main():
    args = build_parser().parse_args()
    try:
        out = {"ok": True, **args.func(args)}
    except ApiError as err:
        out = {"ok": False, "error": str(err)}
    print(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
