#!/usr/bin/env python3
"""music: a light YouTube Music backend for the shell's Music app.

One-shot commands print a JSON object and exit:

    music search QUERY [--kind songs|albums|playlists]
    music home | album BROWSE_ID | playlist BROWSE_ID
    music lyrics VIDEO_ID [--title T --artist A --duration S]
    music fav list|toggle     (toggle reads the track from $MUSIC_TRACK)
    music history
    music config show|set     (patch in $MUSIC_CONFIG_PATCH as JSON)
    music cache               sizes of what is cached
    music cache clear audio|art|lyrics|search

Playback is one detached daemon that owns an mpv and the queue, so music keeps playing
when the window closes. The window talks to it over a unix socket:

    music daemon              run it (the first `ctl` or window start spawns it)
    music ctl play ID | toggle | pause | next | prev | stop | quit | state

Everything lives under ~/.cache/music, ~/.config/music and ~/.local/share/music, never
in /tmp or /run. Standard library plus ytmusicapi; yt-dlp and mpv do the heavy lifting.
All subprocesses are started from argument lists, never through a shell.
"""
import argparse
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
from pathlib import Path

# asyncio, urllib.request and concurrent.futures are imported where they are used: the
# shell runs a fresh one-shot command for every search, list and lyrics lookup, and at the
# top they cost each of those a tenth of a second or more before doing anything.

HOME = Path.home()
CONFIG = HOME / ".config" / "music" / "config.json"
CACHE = HOME / ".cache" / "music"
DATA = HOME / ".local" / "share" / "music"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
SOCK = RUNTIME / "music-daemon.sock"
MPV_SOCK = RUNTIME / "music-mpv.sock"
MPRIS_SO = "/etc/mpv/scripts/mpris.so"

DEFAULTS = {"audio_cache_mb": 1024, "art_cache_mb": 200, "autoplay_radio": True, "volume": 70,
            "auto_download_likes": False, "show_lyrics": True}
SETTABLE = {"audio_cache_mb": int, "art_cache_mb": int, "autoplay_radio": bool, "volume": int,
            "auto_download_likes": bool, "show_lyrics": bool}
UA = "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"


def out(obj, code=0):
    print(json.dumps(obj, ensure_ascii=False))
    sys.exit(code)


def fail(msg):
    out({"ok": False, "error": str(msg)}, 1)


# ── config and small files ──────────────────────────────────────────────────────────────

def load_config():
    cfg = dict(DEFAULTS)
    try:
        cfg.update({k: v for k, v in json.loads(CONFIG.read_text()).items() if k in DEFAULTS})
    except (OSError, ValueError):
        pass
    return cfg


def apply_patch(patch):
    cfg = load_config()
    for key, val in patch.items():
        want = SETTABLE.get(key)
        if want is None:
            raise ValueError(f"unknown setting: {key}")
        if want is bool:
            if not isinstance(val, bool):
                raise ValueError(f"{key} must be true or false")
        else:
            try:
                val = int(val)
            except (TypeError, ValueError):
                raise ValueError(f"{key} must be a number")
            lo, hi = {"audio_cache_mb": (0, 20000), "art_cache_mb": (20, 2000), "volume": (0, 100)}[key]
            if not lo <= val <= hi:
                raise ValueError(f"{key} must be between {lo} and {hi}")
        cfg[key] = val
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    CONFIG.write_text(json.dumps(cfg, indent=2) + "\n")
    return load_config()


def read_json(path, default):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return default


def write_json(path, obj):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, ensure_ascii=False))
    os.replace(tmp, path)


def dir_size(path):
    total = 0
    for p in Path(path).glob("*"):
        try:
            total += p.stat().st_size
        except OSError:
            pass
    return total


def evict(path, cap_bytes, keep=()):
    """Delete the least recently used files until the folder fits under the cap."""
    files = []
    for p in Path(path).glob("*"):
        if p.suffix in (".part", ".ytdl", ".tmp") or p.name in keep:
            continue
        try:
            st = p.stat()
            files.append((max(st.st_atime, st.st_mtime), st.st_size, p))
        except OSError:
            pass
    total = sum(f[1] for f in files)
    for _, size, p in sorted(files):
        if total <= cap_bytes:
            break
        try:
            p.unlink()
            total -= size
        except OSError:
            pass


# ── the YouTube Music side ──────────────────────────────────────────────────────────────

_yt = None


def ytm():
    global _yt
    if _yt is None:
        try:
            from ytmusicapi import YTMusic
        except ImportError:
            raise RuntimeError("python-ytmusicapi is not installed")
        _yt = YTMusic()
    return _yt


def art_url(url, size):
    """The same cover at another size. Googleusercontent URLs end in =w120-h120-..."""
    if not url:
        return ""
    if re.search(r"=w\d+-h\d+", url):
        return re.sub(r"=w\d+-h\d+", f"=w{size}-h{size}", url, count=1)
    if "=s" in url and "googleusercontent" in url:
        return re.sub(r"=s\d+", f"=s{size}", url, count=1)
    return url


def best_thumb(thumbs, vid=""):
    thumbs = [t for t in thumbs or [] if t.get("url")]
    if thumbs:
        return thumbs[-1]["url"]
    return f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg" if vid else ""


def seconds(text):
    try:
        parts = [int(p) for p in str(text).split(":")]
    except ValueError:
        return 0
    total = 0
    for p in parts:
        total = total * 60 + p
    return total


def artists(item):
    names = [a.get("name", "") for a in item.get("artists") or [] if a.get("name")]
    return ", ".join(names) or item.get("author") or ""


def artist_refs(item):
    """[{name, id}] for every credited artist that has a page to open."""
    return [{"name": a["name"], "id": a["id"]} for a in item.get("artists") or []
            if isinstance(a, dict) and a.get("name") and a.get("id")]


def track_of(item, fallback_art="", fallback_album=""):
    vid = item.get("videoId") or ""
    album = item.get("album")
    thumbs = item.get("thumbnail") or item.get("thumbnails")
    return {
        "artistRefs": artist_refs(item),
        "id": vid,
        "title": item.get("title") or "",
        "artist": artists(item),
        "album": (album.get("name") if isinstance(album, dict) else album) or fallback_album,
        "duration": item.get("duration_seconds") or seconds(item.get("length") or item.get("duration") or 0),
        "art": best_thumb(thumbs, vid) or fallback_art,
    }


def cached(kind, key, ttl, fn):
    """A JSON answer kept on disk for `ttl` seconds; a stale one is still used if the
    network fails, so the app keeps working offline."""
    path = CACHE / kind / (hashlib.sha1(key.encode()).hexdigest()[:20] + ".json")
    entry = read_json(path, None)
    if entry and time.time() - entry["t"] < ttl:
        return entry["v"]
    try:
        value = fn()
    except Exception:
        if entry:
            return entry["v"]
        raise
    write_json(path, {"t": time.time(), "v": value})
    return value


def fetch_bytes(url, timeout=12):
    import urllib.request
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def art_path(url, size):
    return CACHE / "art" / (hashlib.sha1(art_url(url, size).encode()).hexdigest()[:20] + ".jpg")


def art_file(url, size):
    """Path of the cover on disk, fetched once. Empty if it cannot be had."""
    if not url:
        return ""
    path = art_path(url, size)
    if path.exists():
        try:
            os.utime(path)
        except OSError:
            pass
        return str(path)
    try:
        data = fetch_bytes(art_url(url, size))
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_bytes(data)
        os.replace(tmp, path)
        return str(path)
    except Exception:
        return ""


def art_file_if_cached(url, size):
    """Like art_file but never touches the network, so a state push is always instant."""
    if not url:
        return ""
    path = art_path(url, size)
    return str(path) if path.exists() else ""


def art_color(path):
    """A colour from the cover for the player to tint itself with: the most common
    colour that is not near-grey, so a dark cover still gives something to work with."""
    if not path:
        return ""
    sidecar = Path(path).with_suffix(".color")
    try:
        return sidecar.read_text()
    except OSError:
        pass
    try:
        from PIL import Image
        im = Image.open(path).convert("RGB").resize((48, 48))
        best, best_score = None, -1.0
        for count, (r, g, b) in im.getcolors(48 * 48):
            mx, mn = max(r, g, b), min(r, g, b)
            sat = (mx - mn) / mx if mx else 0
            score = count * (0.25 + sat) * (1 if 40 < mx < 245 else 0.3)
            if score > best_score:
                best, best_score = (r, g, b), score
        color = "#%02x%02x%02x" % best
    except Exception:
        return ""
    try:
        sidecar.write_text(color)
    except OSError:
        pass
    return color


def with_thumbs(tracks, size=226):
    """Fetch the small covers in parallel and put their paths on the tracks."""
    from concurrent.futures import ThreadPoolExecutor
    urls = {t["art"] for t in tracks if t.get("art")}
    with ThreadPoolExecutor(8) as pool:
        files = dict(zip(urls, pool.map(lambda u: art_file(u, size), urls)))
    for t in tracks:
        t["thumb"] = files.get(t.get("art"), "")
    evict(CACHE / "art", load_config()["art_cache_mb"] * 1048576)
    return tracks


def with_thumbs_fast(items, size=226):
    """Like with_thumbs but never waits for the network: a cover already on disk is a path,
    any other is its web address, which the window can show at once, and a background
    worker saves the missing ones for next time."""
    missing = []
    for t in items:
        art = t.get("art")
        if not art:
            t["thumb"] = ""
            continue
        path = art_path(art, size)
        if path.exists():
            t["thumb"] = str(path)
        else:
            t["thumb"] = art_url(art, size) if art.startswith("https://") else ""
            missing.append(art)
    if missing:
        try:
            subprocess.Popen([sys.executable, "-I", os.path.abspath(__file__), "art-prefetch", str(size)] + sorted(set(missing)),
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
        except OSError:
            pass
    return items


def cmd_art_prefetch(args):
    from concurrent.futures import ThreadPoolExecutor
    urls = [u for u in args.urls if u.startswith("https://")]
    with ThreadPoolExecutor(8) as pool:
        list(pool.map(lambda u: art_file(u, args.size), urls))
    evict(CACHE / "art", load_config()["art_cache_mb"] * 1048576)


def mark_cached(tracks):
    audio = CACHE / "audio"
    have = {p.stem for p in audio.glob("*") if p.suffix not in (".part", ".ytdl")} if audio.exists() else set()
    favs = {t["id"] for t in read_json(DATA / "favorites.json", [])}
    saved = downloaded_ids()
    for t in tracks:
        t["cached"] = t.get("id") in have or t.get("id") in saved
        t["fav"] = t.get("id") in favs
        t["downloaded"] = t.get("id") in saved
    return tracks


def cmd_search(args):
    kind = args.kind
    try:
        raw = cached("search", f"{kind}:{args.query.lower()}", 3600,
                     lambda: ytm().search(args.query, filter=kind, limit=25))
    except Exception as e:
        fail(e)
    items = []
    for r in raw[:24]:
        if kind == "songs":
            if r.get("videoId"):
                items.append(dict(track_of(r), kind="song"))
        elif kind == "albums":
            items.append({"kind": "album", "id": r.get("browseId"), "title": r.get("title"),
                          "artist": artists(r), "artistRefs": artist_refs(r), "year": r.get("year") or "",
                          "art": best_thumb(r.get("thumbnails")), "type": r.get("type") or "Album"})
        elif kind == "artists":
            if r.get("browseId"):
                items.append({"kind": "artist", "id": r["browseId"], "title": r.get("artist") or "",
                              "artist": "", "year": "", "art": best_thumb(r.get("thumbnails")), "type": "Artist"})
        elif kind == "playlists":
            items.append({"kind": "playlist", "id": r.get("browseId"), "title": r.get("title"),
                          "artist": r.get("author") or "", "year": r.get("itemCount") or "",
                          "art": best_thumb(r.get("thumbnails"))})
    with_thumbs_fast(items)
    mark_cached([i for i in items if i["kind"] == "song"])
    out({"ok": True, "kind": kind, "items": items})


def cmd_collection(args):
    kind = args.cmd
    try:
        if kind == "album":
            d = cached("browse", f"album:{args.id}", 86400, lambda: ytm().get_album(args.id))
            cover = best_thumb(d.get("thumbnails"))
            tracks = [track_of(t, cover, d.get("title", "")) for t in d.get("tracks", []) if t.get("videoId")]
            head = {"title": d.get("title"), "artist": artists(d), "artistRefs": artist_refs(d),
                    "year": d.get("year") or "", "art": cover}
        else:
            d = cached("browse", f"playlist:{args.id}", 3600, lambda: ytm().get_playlist(args.id, limit=100))
            tracks = [track_of(t) for t in d.get("tracks", []) if t.get("videoId")]
            author = d.get("author")
            head = {"title": d.get("title"), "year": "", "art": best_thumb(d.get("thumbnails")),
                    "artist": author.get("name", "") if isinstance(author, dict) else author or ""}
    except Exception as e:
        fail(e)
    for t in tracks:
        t["art"] = t["art"] or head["art"]
    with_thumbs(tracks)
    head["thumb"] = art_file(head["art"], 544)
    mark_cached(tracks)
    out({"ok": True, "head": head, "tracks": tracks})


# ── artists: a page to open, and a list to follow ─────────────────────────────────────
# Following is kept on this machine, like likes. YouTube's own subscribe needs a Google
# login, which the app does not have, so nothing here changes anything on YouTube.

FOLLOWING = DATA / "following.json"


def raw_file(url):
    """A picture exactly as served (banners must not be squared), fetched once."""
    if not url:
        return ""
    path = CACHE / "art" / (hashlib.sha1(url.encode()).hexdigest()[:20] + ".jpg")
    if path.exists():
        return str(path)
    try:
        data = fetch_bytes(url)
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_bytes(data)
        os.replace(tmp, path)
        return str(path)
    except Exception:
        return ""


def album_item(a, kind="album"):
    return {"kind": kind, "id": a.get("browseId") or "", "title": a.get("title") or "",
            "artist": "", "year": a.get("year") or a.get("type") or "", "art": best_thumb(a.get("thumbnails")),
            "type": a.get("type") or ""}


def resolve_artist(name):
    """The first artist YouTube Music finds for a name, for tracks saved without an id."""
    name = (name or "").strip()
    if not name:
        return ""
    raw = cached("search", f"artists:{name.lower()}", 86400,
                 lambda: ytm().search(name, filter="artists", limit=5))
    for r in raw:
        if r.get("browseId"):
            return r["browseId"]
    return ""


def is_following(aid):
    return any(a.get("id") == aid for a in read_json(FOLLOWING, []))


def artist_data(aid):
    d = cached("browse", f"artist2:{aid}", 6 * 3600, lambda: ytm().get_artist(aid))
    songs = []
    sb = (d.get("songs") or {}).get("browseId")
    if sb:
        try:
            pl = cached("browse", f"artistsongs:{aid}", 6 * 3600, lambda: ytm().get_playlist(sb, limit=30))
            songs = [t for t in pl.get("tracks", []) if t.get("videoId")]
        except Exception:
            songs = []
    if not songs:
        songs = [t for t in (d.get("songs") or {}).get("results", []) if t.get("videoId")]
    return d, songs


def cmd_artist(args):
    aid = args.id
    try:
        if not aid.startswith("UC"):
            aid = resolve_artist(args.name or aid)
            if not aid:
                fail("Could not find that artist")
        d, raw_songs = artist_data(aid)
    except SystemExit:
        raise
    except Exception as e:
        fail(e)
    avatar = args.art or ""
    if not avatar:
        # The page only has the wide banner; a square picture comes from a search for the name
        try:
            for r in cached("search", f"artists:{(d.get('name') or '').lower()}", 86400,
                            lambda: ytm().search(d.get("name") or "", filter="artists", limit=5)):
                if r.get("browseId") == aid:
                    avatar = best_thumb(r.get("thumbnails"))
                    break
        except Exception:
            pass
    head_thumb = art_file(avatar, 226) if avatar else ""
    thumbs = d.get("thumbnails") or []
    banner = (thumbs[1] if len(thumbs) > 1 else thumbs[-1])["url"] if thumbs else ""
    songs = [dict(track_of(t), kind="song") for t in raw_songs[:25]]
    related = [{"kind": "artist", "id": r.get("browseId") or "", "title": r.get("title") or "",
                "artist": "", "year": (r.get("subscribers") or "") and f"{r['subscribers']} subscribers",
                "art": best_thumb(r.get("thumbnails"))} for r in (d.get("related") or {}).get("results", [])[:12]
               if r.get("browseId")]
    albums = [album_item(a) for a in (d.get("albums") or {}).get("results", [])[:14] if a.get("browseId")]
    singles = [album_item(a) for a in (d.get("singles") or {}).get("results", [])[:14] if a.get("browseId")]
    with_thumbs(songs)
    mark_cached(songs)
    with_thumbs_fast(albums + singles + related)
    head = {"id": aid, "name": d.get("name") or "", "description": d.get("description") or "",
            "subscribers": d.get("subscribers") or "", "monthly": d.get("monthlyListeners") or "",
            "views": d.get("views") or "", "radioId": d.get("radioId") or "", "shuffleId": d.get("shuffleId") or "",
            "banner": raw_file(banner), "art": avatar, "avatar": head_thumb}
    out({"ok": True, "head": head, "following": is_following(aid), "songs": songs,
         "albums": albums, "singles": singles, "related": related})


def cmd_artist_radio(args):
    """Songs to start an artist's radio or shuffle from."""
    try:
        w = ytm().get_watch_playlist(playlistId=args.id, limit=40)
    except Exception as e:
        fail(e)
    tracks = [dict(track_of(t), kind="song") for t in w.get("tracks", []) if t.get("videoId")]
    with_thumbs(tracks)
    mark_cached(tracks)
    out({"ok": True, "tracks": tracks})


def following_list():
    items = [dict(a, kind="artist", title=a.get("name", "")) for a in read_json(FOLLOWING, [])]
    return with_thumbs_fast(items)


def cmd_follow(args):
    if args.action == "toggle":
        try:
            a = json.loads(os.environ.get("MUSIC_ARTIST", "{}"))
        except ValueError:
            fail("bad artist")
        if not a.get("id") or not a.get("name"):
            fail("no artist")
        cur = read_json(FOLLOWING, [])
        if any(x["id"] == a["id"] for x in cur):
            cur = [x for x in cur if x["id"] != a["id"]]
        else:
            cur.insert(0, {"id": a["id"], "name": a["name"], "art": a.get("art", "")})
        write_json(FOLLOWING, cur)
    out({"ok": True, "artists": following_list()})


# ── taste: what gets played, finished, skipped and liked ───────────────────────────────

PLAYS = DATA / "plays.json"
HALF_LIFE = 45 * 86400  # a listen counts half as much after six weeks


def log_listen(track, listened, duration, finished):
    """One listen of one track. A finish or most of the song is a vote for it, an early
    skip is a vote against; under half a minute of a song that was not skipped says nothing."""
    if not track or not track.get("id"):
        return
    plays = read_json(PLAYS, {})
    e = plays.setdefault(track["id"], {"track": slim(track), "done": 0, "part": 0, "skips": 0, "secs": 0, "last": 0})
    frac = listened / duration if duration else 0
    if finished or frac >= 0.8:
        e["done"] += 1
    elif listened < 30 and frac < 0.4:
        e["skips"] += 1
    elif listened >= 30:
        e["part"] += 1
    e["secs"] += int(listened)
    e["last"] = time.time()
    e["track"] = slim(track)
    if len(plays) > 1500:  # keep the ones that matter
        keep = sorted(plays.items(), key=lambda kv: kv[1]["last"], reverse=True)[:1000]
        plays = dict(keep)
    write_json(PLAYS, plays)


def artists_of(t):
    return [a.strip() for a in (t.get("artist") or "").split(",") if a.strip()]


def taste_profile():
    """Artist scores from the play log and the likes, newer listens weighing more."""
    now = time.time()
    plays = read_json(PLAYS, {})
    favs = read_json(DATA / "favorites.json", [])
    scores, counts, likes = {}, {}, {}
    for e in plays.values():
        decay = 0.5 ** ((now - e["last"]) / HALF_LIFE)
        v = (e["done"] * 1.0 + e["part"] * 0.4 - e["skips"] * 1.2) * decay
        for a in artists_of(e["track"]):
            scores[a] = scores.get(a, 0) + v
            counts[a] = counts.get(a, 0) + e["done"] + e["part"]
    for t in favs:
        for a in artists_of(t):
            scores[a] = scores.get(a, 0) + 4
            likes[a] = likes.get(a, 0) + 1
    return {"scores": scores, "counts": counts, "likes": likes, "plays": plays,
            "favs": {t["id"] for t in favs}}


def track_taste(t, prof):
    """How much this listener should like a track: its artists, its own history, a like."""
    sc = prof["scores"]
    arts = artists_of(t)
    v = sum(sc.get(a, 0) for a in arts) / len(arts) if arts else 0
    own = prof["plays"].get(t.get("id"))
    if own:
        v += own["done"] * 0.5 - own["skips"] * 2
    if t.get("id") in prof["favs"]:
        v += 3
    return v


def seeds(prof, n):
    """Songs to start recommendations from: liked and often-finished, a different few each day."""
    pool = {}
    for tid, e in prof["plays"].items():
        pool[tid] = (e["track"], e["done"] * 1.0 + e["part"] * 0.3 - e["skips"])
    for t in read_json(DATA / "favorites.json", []):
        pool[t["id"]] = (t, pool.get(t["id"], (t, 0))[1] + 3)
    ranked = sorted((v for v in pool.values() if v[1] > 0), key=lambda v: v[1], reverse=True)[:max(n * 3, 8)]
    rng = random.Random(time.strftime("%Y-%m-%d"))
    rng.shuffle(ranked)
    return [t for t, _ in ranked[:n]]


def cmd_taste(args):
    if args.action == "reset":
        PLAYS.unlink(missing_ok=True)
    prof = taste_profile()
    ranked = sorted(prof["scores"].items(), key=lambda kv: kv[1], reverse=True)
    top = [{"name": a, "score": round(v, 1), "plays": prof["counts"].get(a, 0), "likes": prof["likes"].get(a, 0)}
           for a, v in ranked[:12] if v > 0]
    secs = sum(e["secs"] for e in prof["plays"].values())
    out({"ok": True, "artists": top, "tracks": len(prof["plays"]), "hours": round(secs / 3600, 1),
         "skipped": sum(e["skips"] for e in prof["plays"].values())})


def personal_shelves():
    """Shelves built from the listening log; empty until there is some."""
    prof = taste_profile()
    result = []
    recent = [dict(t, kind="song") for t in read_json(DATA / "history.json", [])[:12]]
    if recent:
        result.append({"title": "Jump back in", "tracks": recent})
    picks = seeds(prof, 3)
    if not picks:
        return result
    seen = {t["id"] for t in read_json(DATA / "history.json", [])[:30]} | {t["id"] for t in picks}

    def radio(seed):
        w = ytm().get_watch_playlist(seed["id"], radio=True, limit=25)
        return [dict(track_of(t), kind="song") for t in w.get("tracks", []) if t.get("videoId")]

    key = "|".join(t["id"] for t in picks)
    try:
        pool = cached("browse", "mix-" + hashlib.md5(key.encode()).hexdigest()[:10], 3 * 3600,
                      lambda: [radio(t) for t in picks])
    except Exception:
        pool = []
    if pool:
        mixed, ids = [], set()
        for i in range(max(len(r) for r in pool)):  # round-robin so each seed gets a say
            for r in pool:
                if i < len(r) and r[i]["id"] not in ids and r[i]["id"] not in seen \
                        and track_taste(r[i], prof) > -1.5:
                    ids.add(r[i]["id"])
                    mixed.append(r[i])
        order = {t["id"]: i for i, t in enumerate(mixed)}
        mixed.sort(key=lambda t: track_taste(t, prof) - order[t["id"]] * 0.15, reverse=True)
        if mixed:
            result.append({"title": "Made for you", "tracks": mixed[:14]})
        more = [t for t in pool[0] if t["id"] != picks[0]["id"] and t["id"] not in seen][:12]
        if more:
            result.append({"title": f"More like {picks[0]['title']}", "tracks": more})
    return result


def followed_shelf():
    """A few songs from each followed artist, taken in turn, so a long list does not drown a short one."""
    from concurrent.futures import ThreadPoolExecutor
    following = read_json(FOLLOWING, [])[:10]
    if not following:
        return None

    def top(a):
        try:
            return [dict(track_of(t), kind="song") for t in artist_data(a["id"])[1][:6]]
        except Exception:
            return []

    with ThreadPoolExecutor(5) as pool:
        lists = list(pool.map(top, following))
    mixed, ids = [], set()
    for i in range(6):
        for lst in lists:
            if i < len(lst) and lst[i]["id"] not in ids:
                ids.add(lst[i]["id"])
                mixed.append(lst[i])
    if not mixed:
        return None
    return {"title": "From artists you follow", "tracks": with_thumbs(mark_cached(mixed[:16]))}


def cmd_home(_args):
    try:
        personal = personal_shelves()
    except Exception:
        personal = []
    shelves, error = [], None
    try:
        shelves = cached("browse", "home", 1800, lambda: ytm().get_home(limit=3))
    except Exception as e:
        error = e
    if error and not personal:
        fail(error)
    try:
        followed = followed_shelf()
    except Exception:
        followed = None
    result = []
    for shelf in personal:
        result.append({"title": shelf["title"], "tracks": with_thumbs(mark_cached(shelf["tracks"][:14]))})
        if followed and len(result) == 1:
            result.append(followed)
    if followed and not any(s is followed for s in result):
        result.insert(0, followed)
    for shelf in shelves[:4]:
        tracks = [dict(track_of(c), kind="song") for c in shelf.get("contents", [])
                  if isinstance(c, dict) and c.get("videoId")]
        if tracks:
            result.append({"title": shelf.get("title") or "", "tracks": with_thumbs(mark_cached(tracks[:12]))})
    out({"ok": True, "shelves": result})


# ── lyrics ──────────────────────────────────────────────────────────────────────────────

def parse_lrc(text):
    lines = []
    for raw in (text or "").splitlines():
        stamps = re.findall(r"\[(\d+):(\d+(?:\.\d+)?)\]", raw)
        body = re.sub(r"\[[^\]]*\]", "", raw).strip()
        for m, s in stamps:
            lines.append({"t": int(m) * 60 + float(s), "text": body})
    lines.sort(key=lambda l: l["t"])
    return lines


def lyrics_from_ytm(vid):
    watch = ytm().get_watch_playlist(vid, limit=1)
    browse = watch.get("lyrics")
    if not browse:
        return None
    timed = ytm().get_lyrics(browse, timestamps=True)
    if timed and timed.get("hasTimestamps"):
        lines = [{"t": (l.start_time if hasattr(l, "start_time") else l["start_time"]) / 1000,
                  "text": l.text if hasattr(l, "text") else l["text"]} for l in timed["lyrics"]]
        return {"synced": True, "lines": lines, "source": "YouTube Music"}
    plain = ytm().get_lyrics(browse)
    if plain and plain.get("lyrics"):
        return {"synced": False, "lines": [{"t": 0, "text": l} for l in plain["lyrics"].splitlines()],
                "source": "YouTube Music"}
    return None


def lyrics_from_lrclib(title, artist, duration):
    qs = urllib.parse.urlencode({"track_name": title, "artist_name": artist.split(",")[0].strip(),
                                 "duration": int(duration or 0)})
    try:
        d = json.loads(fetch_bytes(f"https://lrclib.net/api/get?{qs}", 10))
    except Exception:
        return None
    if d.get("syncedLyrics"):
        return {"synced": True, "lines": parse_lrc(d["syncedLyrics"]), "source": "LRCLIB"}
    if d.get("plainLyrics"):
        return {"synced": False, "lines": [{"t": 0, "text": l} for l in d["plainLyrics"].splitlines()],
                "source": "LRCLIB"}
    return None


def get_lyrics(vid, title="", artist="", duration=0):
    path = CACHE / "lyrics" / f"{vid}.json"
    entry = read_json(path, None)
    if entry and (entry.get("lines") or time.time() - entry.get("t", 0) < 7 * 86400):
        return entry
    found, errored = None, False
    try:
        found = lyrics_from_ytm(vid)
    except Exception:
        errored = True
    # Synced beats plain, so LRCLIB gets a say when YouTube only had unsynced text
    if (not found or not found["synced"]) and title:
        other = lyrics_from_lrclib(title, artist, duration)
        if other and (not found or other["synced"]):
            found = other
    if found is None:
        if errored:  # the network failed: say nothing was found, but remember nothing
            return {"lines": [], "synced": False, "source": ""}
        found = {"lines": [], "synced": False, "source": ""}
    found["t"] = time.time()
    write_json(path, found)
    return found


def cmd_lyrics(args):
    d = get_lyrics(args.id, args.title or "", args.artist or "", args.duration or 0)
    out({"ok": True, "id": args.id, **{k: d.get(k) for k in ("synced", "lines", "source")}})


# ── favourites, history, cache sizes ────────────────────────────────────────────────────

def toggle_like(track):
    """Like or unlike; returns the new list of favourites. `liked` is true after a like."""
    path = DATA / "favorites.json"
    favs = read_json(path, [])
    if any(t["id"] == track["id"] for t in favs):
        favs = [t for t in favs if t["id"] != track["id"]]
    else:
        favs.insert(0, slim(track))
        if load_config()["auto_download_likes"]:
            start_download_worker([track])
    write_json(path, favs)
    return favs


def toggle_saved(track):
    """Download for offline, or remove the download; returns True when it is now saved."""
    saved = read_json(DATA / "downloads.json", [])
    if any(t["id"] == track["id"] for t in saved):
        write_json(DATA / "downloads.json", [t for t in saved if t["id"] != track["id"]])
        for p in DOWNLOADS.glob(f"{track['id']}.*"):
            p.unlink(missing_ok=True)
        return False
    start_download_worker([track])
    return True


def notify(title, body=""):
    """One replaceable toast, so a run of key presses does not stack."""
    try:
        subprocess.Popen(["notify-send", "-a", "Music", "-t", "2500", "-h", "string:x-canonical-private-synchronous:music",
                          title, body], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


def cmd_fav(args):
    path = DATA / "favorites.json"
    favs = read_json(path, [])
    if args.action == "toggle":
        try:
            track = json.loads(os.environ.get("MUSIC_TRACK", "{}"))
        except ValueError:
            fail("bad track")
        if not track.get("id"):
            fail("no track")
        favs = toggle_like(track)
    tracks = [dict(t, kind="song") for t in favs]
    with_thumbs(tracks)
    mark_cached(tracks)
    out({"ok": True, "tracks": tracks})


# ── downloads: tracks kept for good, outside the cache that gets trimmed ───────────────

DOWNLOADS = DATA / "downloads"
PARTIAL = (".part", ".ytdl", ".queued")
VID_RE = re.compile(r"^[A-Za-z0-9_-]{6,20}$")


def download_file(vid):
    if DOWNLOADS.exists() and VID_RE.match(vid or ""):
        for p in DOWNLOADS.glob(f"{vid}.*"):
            if p.suffix not in PARTIAL:
                return p
    return None


def downloaded_ids():
    if not DOWNLOADS.exists():
        return set()
    return {p.stem for p in DOWNLOADS.glob("*") if p.suffix not in PARTIAL}


def downloading_ids():
    if not DOWNLOADS.exists():
        return set()
    return {p.name.split(".")[0] for p in DOWNLOADS.glob("*.part")} | \
           {p.stem for p in DOWNLOADS.glob("*.queued")}


def start_download_worker(tracks):
    """Detached, so a download goes on after the window closes and the daemon idles out."""
    tracks = [slim(t) for t in tracks if VID_RE.match(t.get("id") or "") and not download_file(t["id"])]
    if not tracks:
        return
    saved = read_json(DATA / "downloads.json", [])
    have = {t["id"] for t in saved}
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    for t in tracks:
        if t["id"] not in have:
            saved.insert(0, t)
        (DOWNLOADS / f"{t['id']}.queued").touch()
    write_json(DATA / "downloads.json", saved)
    subprocess.Popen([sys.executable, "-I", os.path.abspath(__file__), "dl-worker"] + [t["id"] for t in tracks],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def cmd_dl_worker(args):
    for vid in args.ids:
        if not VID_RE.match(vid) or download_file(vid):
            (DOWNLOADS / f"{vid}.queued").unlink(missing_ok=True)
            continue
        if not any(t["id"] == vid for t in read_json(DATA / "downloads.json", [])):
            (DOWNLOADS / f"{vid}.queued").unlink(missing_ok=True)  # removed while waiting
            continue
        try:
            subprocess.run(["yt-dlp", "-f", "bestaudio", "--no-warnings", "--no-playlist", "--ignore-config",
                            "-o", str(DOWNLOADS / f"{vid}.%(ext)s"), f"https://music.youtube.com/watch?v={vid}"],
                           stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           timeout=900)
        except (subprocess.TimeoutExpired, OSError):
            pass
        (DOWNLOADS / f"{vid}.queued").unlink(missing_ok=True)
        if not download_file(vid):  # failed: forget it so the button can be tried again
            for p in DOWNLOADS.glob(f"{vid}.*"):
                p.unlink(missing_ok=True)
            write_json(DATA / "downloads.json", [t for t in read_json(DATA / "downloads.json", []) if t["id"] != vid])


def cmd_dl(args):
    saved = read_json(DATA / "downloads.json", [])
    if args.action in ("toggle", "add"):
        try:
            track = json.loads(os.environ.get("MUSIC_TRACK", "{}"))
        except ValueError:
            fail("bad track")
        if not track.get("id") or not VID_RE.match(track["id"]):
            fail("no track")
        if args.action == "toggle":
            toggle_saved(track)
        else:
            start_download_worker([track])
    elif args.action == "likes":
        start_download_worker(read_json(DATA / "favorites.json", []))
    out(dl_state())


def dl_state():
    done, busy = downloaded_ids(), downloading_ids()
    saved = read_json(DATA / "downloads.json", [])
    tracks = [dict(t, kind="song", downloaded=t["id"] in done) for t in saved]
    with_thumbs(tracks)
    return {"ok": True, "tracks": tracks, "done": sorted(done), "busy": sorted(busy - done),
            "bytes": dir_size(DOWNLOADS) if DOWNLOADS.exists() else 0}


def cmd_history(_args):
    tracks = [dict(t, kind="song") for t in read_json(DATA / "history.json", [])]
    with_thumbs(tracks)
    mark_cached(tracks)
    out({"ok": True, "tracks": tracks})


def cmd_cache(args):
    if args.action == "clear":
        if args.what not in ("audio", "art", "lyrics", "search", "browse"):
            fail("clear audio, art, lyrics, search or browse")
        shutil.rmtree(CACHE / args.what, ignore_errors=True)
    sizes = {k: dir_size(CACHE / k) for k in ("audio", "art", "lyrics", "search", "browse")}
    sizes["downloads"] = dir_size(DOWNLOADS) if DOWNLOADS.exists() else 0
    out({"ok": True, "sizes": sizes})


def cmd_config(args):
    if args.action == "set":
        try:
            apply_patch(json.loads(os.environ.get("MUSIC_CONFIG_PATCH", "{}")))
        except (ValueError, OSError) as e:
            fail(e)
    cfg = load_config()
    cfg["path"] = str(CONFIG)
    cfg["ytmusicapi"] = __import__("importlib.util").util.find_spec("ytmusicapi") is not None
    cfg["mpv"] = shutil.which("mpv") is not None
    cfg["yt_dlp"] = shutil.which("yt-dlp") is not None
    out({"ok": True, "settings": cfg})


def slim(t):
    out_ = {k: t.get(k, "") for k in ("id", "title", "artist", "album", "duration", "art")}
    refs = t.get("artistRefs")
    if isinstance(refs, list) and refs:
        out_["artistRefs"] = [{"name": str(r.get("name", "")), "id": str(r.get("id", ""))} for r in refs
                              if isinstance(r, dict) and r.get("id")][:6]
    return out_



# ── MPRIS: how the rest of the shell sees this player ──────────────────────────────────

def make_mpris(daemon, loop):
    """Expose the daemon on the session bus as org.mpris.MediaPlayer2.music, so the bar, the
    media controls and the media view get the real title, artist, album, cover and length
    (mpv alone only knows a stream URL). Runs a GLib loop in a thread; every command it
    receives is handed to the asyncio loop. Returns None when dbus-python is unavailable."""
    try:
        import dbus
        import dbus.mainloop.glib
        import dbus.service
        from gi.repository import GLib
    except Exception:
        return None
    import threading

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    try:
        name = dbus.service.BusName("org.mpris.MediaPlayer2.music", bus, do_not_queue=True)
    except Exception:
        return None
    ROOT, PLAYER, PROPS = "org.mpris.MediaPlayer2", "org.mpris.MediaPlayer2.Player", "org.freedesktop.DBus.Properties"

    def run(cmd, **kw):
        asyncio.run_coroutine_threadsafe(daemon.handle(dict(cmd=cmd, **kw)), loop)

    class Player(dbus.service.Object):
        def __init__(self):
            super().__init__(bus, "/org/mpris/MediaPlayer2", name)
            self.last = {}

        def root_props(self):
            return {"CanQuit": dbus.Boolean(False), "CanRaise": dbus.Boolean(False),
                    "HasTrackList": dbus.Boolean(False), "Identity": "Music", "DesktopEntry": "",
                    "SupportedUriSchemes": dbus.Array([], signature="s"),
                    "SupportedMimeTypes": dbus.Array([], signature="s")}

        def metadata(self):
            cur = daemon.current()
            if not cur or not daemon.loaded_id:
                return dbus.Dictionary({"mpris:trackid": dbus.ObjectPath("/org/mpris/MediaPlayer2/TrackList/NoTrack")},
                                       signature="sv")
            vid = cur["id"]
            md = {
                "mpris:trackid": dbus.ObjectPath("/org/mpris/MediaPlayer2/Track/" + re.sub(r"\W", "_", vid)),
                "mpris:length": dbus.Int64(int((daemon.dur or cur.get("duration") or 0) * 1e6)),
                "xesam:title": cur.get("title", ""),
                "xesam:artist": dbus.Array([a.strip() for a in cur.get("artist", "").split(",") if a.strip()], signature="s"),
                "xesam:album": cur.get("album", ""),
                "xesam:url": f"https://music.youtube.com/watch?v={vid}",
            }
            cover = art_file_if_cached(cur.get("art"), 800)
            if cover:
                md["mpris:artUrl"] = "file://" + cover
            return dbus.Dictionary(md, signature="sv")

        def player_props(self):
            cur = daemon.current()
            status = "Stopped" if not cur or not daemon.loaded_id else ("Paused" if daemon.paused else "Playing")
            return {
                "PlaybackStatus": status,
                "LoopStatus": {"off": "None", "one": "Track", "all": "Playlist"}[daemon.repeat],
                "Rate": dbus.Double(1.0), "MinimumRate": dbus.Double(1.0), "MaximumRate": dbus.Double(1.0),
                "Shuffle": dbus.Boolean(daemon.shuffle),
                "Metadata": self.metadata(),
                "Volume": dbus.Double(daemon.volume / 100),
                "Position": dbus.Int64(int(daemon.position_now() * 1e6)),
                "CanGoNext": dbus.Boolean(bool(cur)), "CanGoPrevious": dbus.Boolean(bool(cur)),
                "CanPlay": dbus.Boolean(bool(cur)), "CanPause": dbus.Boolean(bool(cur)),
                "CanSeek": dbus.Boolean(bool(cur and daemon.loaded_id)), "CanControl": dbus.Boolean(True),
            }

        def all_props(self, iface):
            if iface == ROOT:
                return self.root_props()
            if iface == PLAYER:
                return self.player_props()
            raise dbus.exceptions.DBusException("unknown interface " + iface)

        @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
        def Get(self, iface, prop):
            return self.all_props(iface)[prop]

        @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
        def GetAll(self, iface):
            return dbus.Dictionary(self.all_props(iface), signature="sv")

        @dbus.service.method(PROPS, in_signature="ssv")
        def Set(self, iface, prop, value):
            if iface != PLAYER:
                return
            if prop == "Volume":
                run("volume", volume=int(round(float(value) * 100)))
            elif prop == "Shuffle":
                if bool(value) != daemon.shuffle:
                    run("shuffle")
            elif prop == "LoopStatus":
                want = {"None": "off", "Track": "one", "Playlist": "all"}.get(str(value), "off")
                steps = ["off", "all", "one"]
                for _ in range((steps.index(want) - steps.index(daemon.repeat)) % 3):
                    run("repeat")

        @dbus.service.signal(PROPS, signature="sa{sv}as")
        def PropertiesChanged(self, iface, changed, invalidated):
            pass

        @dbus.service.signal(PLAYER, signature="x")
        def Seeked(self, position):
            pass

        @dbus.service.method(ROOT)
        def Raise(self):
            pass

        @dbus.service.method(ROOT)
        def Quit(self):
            pass

        @dbus.service.method(PLAYER)
        def Next(self): run("next")

        @dbus.service.method(PLAYER)
        def Previous(self): run("prev")

        @dbus.service.method(PLAYER)
        def Pause(self): run("pause")

        @dbus.service.method(PLAYER)
        def PlayPause(self): run("toggle")

        @dbus.service.method(PLAYER)
        def Stop(self): run("stop")

        @dbus.service.method(PLAYER)
        def Play(self):
            run("toggle" if daemon.paused else "resume")

        @dbus.service.method(PLAYER, in_signature="x")
        def Seek(self, offset):
            run("seek", pos=max(0.0, daemon.position_now() + offset / 1e6))

        @dbus.service.method(PLAYER, in_signature="ox")
        def SetPosition(self, track_id, position):
            run("seek", pos=max(0.0, position / 1e6))

        @dbus.service.method(PLAYER, in_signature="s")
        def OpenUri(self, uri):
            pass

        def sync(self):
            """Tell listeners what changed since the last time. Runs in the GLib thread."""
            now = self.player_props()
            now.pop("Position", None)
            changed = {k: v for k, v in now.items() if self.last.get(k) != v}
            if changed:
                self.last = now
                self.PropertiesChanged(PLAYER, dbus.Dictionary(changed, signature="sv"), dbus.Array([], signature="s"))
            return False

    player = Player()
    threading.Thread(target=GLib.MainLoop().run, daemon=True).start()

    class Handle:
        def sync(self):
            GLib.idle_add(player.sync)

        def seeked(self, pos):
            GLib.idle_add(lambda: (player.Seeked(dbus.Int64(int(pos * 1e6))), False)[1])

    return Handle()


# ── the playback daemon ─────────────────────────────────────────────────────────────────

class Daemon:
    def __init__(self):
        self.cfg = load_config()
        saved = read_json(DATA / "state.json", {})
        self.queue = saved.get("queue", [])
        idx = saved.get("index", -1)
        self.index = idx if 0 <= idx < len(self.queue) else -1
        self.repeat = saved.get("repeat", "off")
        self.shuffle = bool(saved.get("shuffle", False))
        self.volume = saved.get("volume", self.cfg["volume"])
        self.paused = True
        self.pos = 0.0
        self.dur = 0.0
        self.loading = False
        self.error = ""
        self.loaded_id = ""        # what mpv actually has open
        self.token = 0             # bumped on every play so a slow resolve can be dropped
        self.errors_in_a_row = 0
        self.urls = {}             # id -> (url, when); streams expire, so never kept long
        self.subs = set()
        self.mpv_w = None
        from concurrent.futures import ThreadPoolExecutor
        self.pool = ThreadPoolExecutor(4)
        self.download_lock = asyncio.Lock()
        self.radio_lock = asyncio.Lock()
        self.last_active = time.time()
        self.dirty = False
        self.mpris = None
        self.own_mpris = False
        self.pos_stamp = time.time()
        self.listening = None      # the track mpv is playing, until its listen is logged
        self.radio_rounds = 0

    def close_listen(self, finished=False):
        t, self.listening = self.listening, None
        if t:
            log_listen(t, self.pos, self.dur or float(t.get("duration") or 0), finished)

    def position_now(self):
        """Where the song is now: mpv reports a few times a second, so add what has passed."""
        if self.paused or self.loading or not self.loaded_id:
            return self.pos
        return min(self.pos + (time.time() - self.pos_stamp), self.dur or 1e9)

    # ── state out ──
    def current(self):
        return self.queue[self.index] if 0 <= self.index < len(self.queue) else None

    def snapshot(self, with_queue=True):
        cur = self.current()
        # An idle mpv reports pause=false with nothing loaded: playing needs the track loaded
        playing = bool(cur) and self.loaded_id == cur.get("id") and not self.paused and not self.loading
        s = {"event": "state", "playing": playing,
             "paused": self.paused, "loading": self.loading, "pos": round(self.pos, 2),
             "dur": self.dur or (cur or {}).get("duration", 0), "index": self.index,
             "repeat": self.repeat, "shuffle": self.shuffle, "volume": self.volume,
             "error": self.error, "track": None}
        if cur:
            big = art_file_if_cached(cur.get("art"), 800)
            s["track"] = dict(cur, cover=big, color=art_color(big) if big else "",
                              thumb=art_file_if_cached(cur.get("art"), 226))
        if with_queue:
            s["queue"] = [dict(t, thumb=art_file_if_cached(t.get("art"), 226)) for t in self.queue]
        return s

    async def broadcast(self, with_queue=True):
        if self.mpris:
            self.mpris.sync()
        if not self.subs:
            return
        data = (json.dumps(self.snapshot(with_queue), ensure_ascii=False) + "\n").encode()
        for w in list(self.subs):
            try:
                w.write(data)
                await w.drain()
            except Exception:
                self.subs.discard(w)

    def save(self):
        write_json(DATA / "state.json", {"queue": self.queue, "index": self.index, "repeat": self.repeat,
                                         "shuffle": self.shuffle, "volume": self.volume})

    # ── mpv ──
    async def start_mpv(self):
        MPV_SOCK.unlink(missing_ok=True)
        cmd = ["mpv", "--no-config", "--idle=yes", "--no-video", "--audio-display=no", "--ytdl=no",
               "--force-window=no", "--really-quiet", f"--input-ipc-server={MPV_SOCK}",
               f"--volume={self.volume}", "--cache=yes", "--demuxer-max-bytes=48MiB",
               "--user-agent=" + UA, "--title=music", "--audio-client-name=Music"]
        if not self.own_mpris and os.path.exists(MPRIS_SO):
            cmd.append(f"--script={MPRIS_SO}")  # fallback: title only, no artist or cover
        if os.environ.get("MUSIC_AO"):
            cmd.append(f"--ao={os.environ['MUSIC_AO']}")
        await asyncio.create_subprocess_exec(*cmd, stdin=asyncio.subprocess.DEVNULL,
                                             stdout=asyncio.subprocess.DEVNULL,
                                             stderr=asyncio.subprocess.DEVNULL,
                                             preexec_fn=die_with_parent)
        for _ in range(100):
            if MPV_SOCK.exists():
                break
            await asyncio.sleep(0.05)
        reader, self.mpv_w = await asyncio.open_unix_connection(str(MPV_SOCK))
        for i, prop in enumerate(("pause", "time-pos", "duration", "volume")):
            self.send(["observe_property", i + 1, prop])
        asyncio.ensure_future(self.read_mpv(reader))

    def send(self, command):
        if self.mpv_w:
            self.mpv_w.write((json.dumps({"command": command}) + "\n").encode())

    async def read_mpv(self, reader):
        last_push = 0.0
        while True:
            line = await reader.readline()
            if not line:
                self.save()
                os._exit(0)  # mpv is gone (killed, crashed): nothing left to run
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            ev = msg.get("event")
            if ev == "property-change":
                name, val = msg.get("name"), msg.get("data")
                if name == "pause" and val is not None:
                    self.paused = bool(val)
                    self.last_active = time.time()
                    await self.broadcast(False)
                elif name == "time-pos" and val is not None and not self.loading:
                    # The old song keeps reporting until the new one is up; its position is not ours
                    self.pos = float(val)
                    self.pos_stamp = time.time()
                    if time.time() - last_push >= 1 and self.subs:
                        last_push = time.time()
                        await self.broadcast(False)
                elif name == "duration" and val:
                    self.dur = float(val)
                elif name == "volume" and val is not None:
                    self.volume = int(val)
                    self.dirty = True
            elif ev == "file-loaded":
                self.errors_in_a_row = 0
            elif ev == "playback-restart":
                # Audio is actually flowing now (file-loaded comes earlier, while a stream
                # is still buffering), so this is what ends "loading"
                if self.loading and self.loaded_id:
                    self.loading = False
                    self.pos_stamp = time.time()
                    await self.broadcast(False)
            elif ev == "end-file":
                reason = msg.get("reason")
                if reason == "eof":
                    self.close_listen(finished=True)
                    await self.advance(auto=True)
                elif reason == "error":
                    self.errors_in_a_row += 1
                    self.error = "Could not play this track"
                    self.loading = False
                    await self.broadcast(False)
                    if self.errors_in_a_row < 3:
                        await asyncio.sleep(1)
                        await self.advance(auto=True)

    # ── resolving and caching audio ──
    def cached_audio(self, vid):
        saved = download_file(vid)
        if saved:
            return str(saved)
        audio = CACHE / "audio"
        for p in audio.glob(f"{vid}.*"):
            if p.suffix not in (".part", ".ytdl"):
                try:
                    os.utime(p)
                except OSError:
                    pass
                return str(p)
        return ""

    async def resolve(self, vid):
        hit = self.cached_audio(vid)
        if hit:
            return hit
        got = self.urls.get(vid)
        if got and time.time() - got[1] < 2700:
            return got[0]
        proc = await asyncio.create_subprocess_exec(
            "yt-dlp", "-g", "-f", "bestaudio", "--no-warnings", "--no-playlist", "--ignore-config",
            f"https://music.youtube.com/watch?v={vid}",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        try:
            so, se = await asyncio.wait_for(proc.communicate(), 45)
        except asyncio.TimeoutError:
            proc.kill()
            raise RuntimeError("YouTube took too long to answer")
        url = so.decode().strip().splitlines()[0] if so.strip() else ""
        if proc.returncode != 0 or not url:
            err = [l for l in se.decode().splitlines() if l.strip()]
            raise RuntimeError(re.sub(r"^ERROR:\s*(\[[^\]]+\]\s*)?", "", err[-1]) if err else "Could not resolve the track")
        self.urls[vid] = (url, time.time())
        return url

    async def download(self, vid):
        """Keep a copy of the track so it plays instantly, and offline, next time."""
        cap = self.cfg["audio_cache_mb"]
        if cap <= 0 or self.cached_audio(vid) or vid in downloading_ids():
            return
        async with self.download_lock:
            if self.cached_audio(vid):
                return
            (CACHE / "audio").mkdir(parents=True, exist_ok=True)
            proc = await asyncio.create_subprocess_exec(
                "yt-dlp", "-f", "bestaudio", "--no-warnings", "--no-playlist", "--ignore-config",
                "-o", str(CACHE / "audio" / f"{vid}.%(ext)s"), f"https://music.youtube.com/watch?v={vid}",
                stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
            try:
                await asyncio.wait_for(proc.wait(), 600)
            except asyncio.TimeoutError:
                proc.kill()
            keep = {p.name for t in (self.current(), self.peek_next()) if t
                    for p in (CACHE / "audio").glob(f"{t['id']}.*")}
            evict(CACHE / "audio", cap * 1048576, keep)
            await self.broadcast(True)

    def peek_next(self):
        i = self.index + 1
        return self.queue[i] if self.queue and i < len(self.queue) else None

    async def prefetch_art(self, track):
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(self.pool, art_file, track.get("art"), 800)
        await loop.run_in_executor(self.pool, art_file, track.get("art"), 226)
        await self.broadcast(True)

    # ── playback ──
    async def play_index(self, i):
        if not 0 <= i < len(self.queue):
            return
        self.index = i
        self.token += 1
        token = self.token
        track = self.queue[i]
        self.close_listen()
        self.loading, self.error, self.pos, self.dur = True, "", 0.0, float(track.get("duration") or 0)
        self.send(["set_property", "pause", True])  # the old song stops now, not when the new one is resolved
        self.save()
        await self.broadcast(True)
        asyncio.ensure_future(self.prefetch_art(track))
        try:
            source = await self.resolve(track["id"])
        except Exception as e:
            if token == self.token:
                self.loading, self.error = False, str(e)
                await self.broadcast(False)
            return
        if token != self.token:
            return
        title = f"{track['artist']} - {track['title']}" if track.get("artist") else track["title"]
        self.send(["set_property", "force-media-title", title])
        self.send(["loadfile", source, "replace"])
        self.send(["set_property", "pause", False])
        self.loaded_id = track["id"]
        self.listening = track
        self.last_active = time.time()
        self.record_history(track)
        asyncio.ensure_future(self.download(track["id"]))
        nxt = self.peek_next()
        if nxt:
            asyncio.ensure_future(self.warm(nxt))
        if self.index >= len(self.queue) - 3 and self.cfg["autoplay_radio"]:
            asyncio.ensure_future(self.extend_radio(track["id"]))

    async def warm(self, track):
        """Look the next track up while this one plays, so skipping is instant."""
        try:
            await self.resolve(track["id"])
            asyncio.ensure_future(self.prefetch_art(track))
            asyncio.ensure_future(self.download(track["id"]))
        except Exception:
            pass

    def record_history(self, track):
        hist = [t for t in read_json(DATA / "history.json", []) if t["id"] != track["id"]]
        hist.insert(0, slim(track))
        write_json(DATA / "history.json", hist[:200])

    async def extend_radio(self, vid):
        async with self.radio_lock:  # two callers at once would both add the same tracks
            loop = asyncio.get_running_loop()
            prof = await loop.run_in_executor(self.pool, taste_profile)
            self.radio_rounds += 1
            if self.radio_rounds % 2 == 0:  # every other round, drift toward what they love
                liked = await loop.run_in_executor(self.pool, lambda: seeds(prof, 1))
                if liked:
                    vid = liked[0]["id"]
            try:
                watch = await loop.run_in_executor(self.pool, lambda: ytm().get_watch_playlist(vid, radio=True, limit=30))
            except Exception:
                return
            have = {t["id"] for t in self.queue}
            added = [track_of(t) for t in watch.get("tracks", []) if t.get("videoId") and t["videoId"] not in have]
            # Skip what they keep skipping, and put what suits them first (stable: radio order breaks ties)
            added = [t for t in added if track_taste(t, prof) > -1.5]
            added.sort(key=lambda t: track_taste(t, prof), reverse=True)
            if added:
                self.queue.extend(added)
                self.save()
                await self.broadcast(True)
                for t in added[:12]:
                    asyncio.ensure_future(self.prefetch_art(t))

    async def advance(self, auto=False, step=1):
        if not self.queue:
            return
        if auto and self.repeat == "one" and self.current():
            return await self.play_index(self.index)
        if self.shuffle and step > 0 and len(self.queue) > 1:
            choices = [i for i in range(len(self.queue)) if i != self.index]
            return await self.play_index(random.choice(choices))
        i = self.index + step
        if 0 <= i < len(self.queue):
            return await self.play_index(i)
        if step < 0:
            return await self.play_index(0)
        if self.repeat == "all":
            return await self.play_index(0)
        if auto and self.cfg["autoplay_radio"] and self.current():
            before = len(self.queue)
            await self.extend_radio(self.current()["id"])
            if len(self.queue) > before:
                return await self.play_index(before)
        self.send(["stop"])
        self.paused, self.loading, self.pos, self.loaded_id = True, False, 0.0, ""
        await self.broadcast(False)

    # ── commands from clients ──
    async def handle(self, msg):
        cmd = msg.get("cmd")
        self.last_active = time.time()
        if cmd == "state":
            return self.snapshot()
        if cmd == "play":
            tracks = msg.get("tracks") or ([msg["track"]] if msg.get("track") else [])
            if not tracks:
                return {"ok": False, "error": "nothing to play"}
            self.queue = [slim(t) for t in tracks]
            start = min(max(int(msg.get("index", 0)), 0), len(self.queue) - 1)
            await self.play_index(start)
            return {"ok": True}
        if cmd == "jump":
            await self.play_index(int(msg.get("index", 0)))
        elif cmd == "toggle":
            cur = self.current()
            if cur and self.loaded_id != cur["id"]:
                await self.play_index(self.index)
            elif cur:
                self.send(["cycle", "pause"])
        elif cmd == "pause":
            self.send(["set_property", "pause", True])
        elif cmd == "resume":
            self.send(["set_property", "pause", False])
        elif cmd == "next":
            await self.advance(step=1)
        elif cmd == "prev":
            if self.pos > 4 and self.current():
                self.send(["seek", 0, "absolute"])
            else:
                await self.advance(step=-1)
        elif cmd == "seek":
            self.send(["seek", float(msg.get("pos", 0)), "absolute"])
            self.pos = float(msg.get("pos", 0))
            self.pos_stamp = time.time()
            if self.mpris:
                self.mpris.seeked(self.pos)
        elif cmd == "volume":
            self.volume = max(0, min(100, int(msg.get("volume", self.volume))))
            self.send(["set_property", "volume", self.volume])
            self.dirty = True
        elif cmd == "repeat":
            self.repeat = {"off": "all", "all": "one", "one": "off"}.get(self.repeat, "off")
            self.save()
        elif cmd == "shuffle":
            self.shuffle = not self.shuffle
            self.save()
        elif cmd in ("like", "save"):  # for the global keys: act on whatever is playing
            cur = self.current()
            if not cur:
                notify("Nothing is playing")
                return {"ok": False, "error": "nothing is playing"}
            label = f"{cur['title']} · {cur['artist']}" if cur.get("artist") else cur["title"]
            if cmd == "like":
                liked = not any(t["id"] == cur["id"] for t in read_json(DATA / "favorites.json", []))
                toggle_like(cur)
                notify("Added to favourites" if liked else "Removed from favourites", label)
            else:
                notify("Downloading for offline" if toggle_saved(cur) else "Download removed", label)
        elif cmd == "mix":  # a random mix of what they love, started from anywhere
            pool = read_json(DATA / "favorites.json", [])
            source = "favourites"
            if len(pool) < 2:
                pool, source = read_json(DATA / "history.json", []), "history"
            if len(pool) < 2:
                notify("Nothing to shuffle yet", "Like or play a few songs first")
                return {"ok": False, "error": "nothing to shuffle"}
            pool = [slim(t) for t in pool]
            random.shuffle(pool)
            self.queue = pool
            notify("Shuffling your " + source, f"{len(pool)} songs")
            await self.play_index(0)
            return {"ok": True}
        elif cmd == "enqueue":
            tracks = [slim(t) for t in (msg.get("tracks") or [msg.get("track")]) if t]
            if msg.get("next"):
                at = self.index + 1
                self.queue[at:at] = tracks
            else:
                self.queue.extend(tracks)
            if self.index < 0 and self.queue:
                await self.play_index(0)
            else:
                self.save()
            for t in tracks[:12]:
                asyncio.ensure_future(self.prefetch_art(t))
        elif cmd == "remove":
            i = int(msg.get("index", -1))
            if 0 <= i < len(self.queue):
                if i == self.index:
                    return {"ok": False, "error": "That one is playing"}
                del self.queue[i]
                if i < self.index:
                    self.index -= 1
                self.save()
        elif cmd == "clear":
            cur = self.current()
            self.queue = [cur] if cur else []
            self.index = 0 if cur else -1
            self.save()
        elif cmd == "stop":
            self.send(["stop"])
            self.paused, self.loaded_id, self.pos = True, "", 0.0
        elif cmd == "quit":
            self.save()
            os._exit(0)
        await self.broadcast(True)
        return {"ok": True}

    async def client(self, reader, writer):
        try:
            while True:
                line = await reader.readline()
                if not line:
                    break
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                if msg.get("cmd") == "subscribe":
                    self.subs.add(writer)
                    writer.write((json.dumps(self.snapshot(True), ensure_ascii=False) + "\n").encode())
                    await writer.drain()
                    continue
                reply = await self.handle(msg)
                if reply is not None:
                    writer.write((json.dumps(reply, ensure_ascii=False) + "\n").encode())
                    await writer.drain()
        except (ConnectionError, asyncio.IncompleteReadError):
            pass
        finally:
            self.subs.discard(writer)
            writer.close()

    async def janitor(self):
        """Save the volume, and exit after a long quiet spell so nothing idles forever."""
        while True:
            await asyncio.sleep(30)
            if self.dirty:
                self.dirty = False
                self.save()
            if self.paused and not self.subs and time.time() - self.last_active > 600:
                self.save()
                os._exit(0)

    async def run(self):
        DATA.mkdir(parents=True, exist_ok=True)
        self.mpris = make_mpris(self, asyncio.get_running_loop())
        self.own_mpris = self.mpris is not None
        await self.start_mpv()
        SOCK.unlink(missing_ok=True)
        server = await asyncio.start_unix_server(self.client, str(SOCK))
        os.chmod(SOCK, 0o600)
        asyncio.ensure_future(self.janitor())
        async with server:
            await server.serve_forever()


def die_with_parent():
    """Run in mpv's child process: have the kernel end it whenever the daemon ends, however
    that happens, so no player is left playing with nothing in control of it."""
    import ctypes
    ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, 15)  # PR_SET_PDEATHSIG, SIGTERM


def cmd_daemon(_args):
    # The daemon is the only asyncio user (Daemon, make_mpris); its methods read the global
    global asyncio
    import asyncio
    if SOCK.exists():
        try:
            import socket
            s = socket.socket(socket.AF_UNIX)
            s.settimeout(1)
            s.connect(str(SOCK))
            s.close()
            return  # already running
        except OSError:
            SOCK.unlink(missing_ok=True)
    if shutil.which("mpv") is None:
        fail("mpv is not installed")
    asyncio.run(Daemon().run())


def connect_daemon(spawn=True):
    """A connected socket to the daemon, starting it first when nothing answers. A socket
    file left behind by a daemon that died is told apart by the refused connection."""
    import socket

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
    if s or not spawn:
        return s
    SOCK.unlink(missing_ok=True)
    subprocess.Popen([sys.executable, os.path.abspath(__file__), "daemon"], stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    for _ in range(100):
        time.sleep(0.1)
        s = attempt()
        if s:
            return s
    return None


def cmd_ctl(args):
    msg = {"cmd": args.what}
    if args.what == "play" and args.arg:
        msg["track"] = {"id": args.arg, "title": args.arg, "artist": "", "album": "", "duration": 0, "art": ""}
    s = connect_daemon(spawn=args.what not in ("quit", "like", "save"))
    if s is None:
        fail("the player is not running" if args.what in ("quit", "like", "save") else "the player did not start")
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
    ap = argparse.ArgumentParser(prog="music")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("search"); p.add_argument("query")
    p.add_argument("--kind", default="songs", choices=["songs", "albums", "playlists", "artists"]); p.set_defaults(fn=cmd_search)
    sub.add_parser("home").set_defaults(fn=cmd_home)
    for name in ("album", "playlist"):
        p = sub.add_parser(name); p.add_argument("id"); p.set_defaults(fn=cmd_collection)
    p = sub.add_parser("artist"); p.add_argument("id"); p.add_argument("--name", default=""); p.add_argument("--art", default=""); p.set_defaults(fn=cmd_artist)
    p = sub.add_parser("artist-radio"); p.add_argument("id"); p.set_defaults(fn=cmd_artist_radio)
    p = sub.add_parser("follow"); p.add_argument("action", choices=["list", "toggle"]); p.set_defaults(fn=cmd_follow)
    p = sub.add_parser("lyrics"); p.add_argument("id"); p.add_argument("--title"); p.add_argument("--artist")
    p.add_argument("--duration", type=float); p.set_defaults(fn=cmd_lyrics)
    p = sub.add_parser("fav"); p.add_argument("action", choices=["list", "toggle"]); p.set_defaults(fn=cmd_fav)
    sub.add_parser("history").set_defaults(fn=cmd_history)
    p = sub.add_parser("dl"); p.add_argument("action", choices=["list", "toggle", "add", "likes"]); p.set_defaults(fn=cmd_dl)
    p = sub.add_parser("art-prefetch"); p.add_argument("size", type=int); p.add_argument("urls", nargs="+")
    p.set_defaults(fn=cmd_art_prefetch)
    p = sub.add_parser("dl-worker"); p.add_argument("ids", nargs="+"); p.set_defaults(fn=cmd_dl_worker)
    p = sub.add_parser("taste"); p.add_argument("action", nargs="?", default="show", choices=["show", "reset"])
    p.set_defaults(fn=cmd_taste)
    p = sub.add_parser("config"); p.add_argument("action", choices=["show", "set"]); p.set_defaults(fn=cmd_config)
    p = sub.add_parser("cache"); p.add_argument("action", nargs="?", default="show", choices=["show", "clear"])
    p.add_argument("what", nargs="?"); p.set_defaults(fn=cmd_cache)
    sub.add_parser("daemon").set_defaults(fn=cmd_daemon)
    p = sub.add_parser("ctl"); p.add_argument("what"); p.add_argument("arg", nargs="?"); p.set_defaults(fn=cmd_ctl)
    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
