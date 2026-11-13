#!/usr/bin/env python3
"""qb.py: a small bridge between the shell and qBittorrent's web API.

  qb.py watch                 one JSON line every 2 s: the torrents and the transfer totals
  qb.py action ACT HASH...    stop | start | recheck | reannounce | delete | delete-files
  qb.py add-url URL [opts]    a magnet link or an http(s) link to a .torrent
  qb.py add-file PATH [opts]  opts: --dir D --category C --paused --sequential --skip-check
  qb.py detail HASH           properties, files, trackers and peers of one torrent
  qb.py file-prio HASH PRIO ID...   0 skip, 1 normal, 6 high, 7 maximum, for those file numbers
  qb.py queue MOVE HASH...    top | bottom | up | down
  qb.py op OP HASH... [--value V]   one change to torrents: see OPS
  qb.py category add NAME [--dir D] | remove NAME
  qb.py prefs                 the settings the app edits, as JSON
  qb.py set-prefs JSON        change some of them
  qb.py alt-speed             switch the alternative speed limits on or off
  qb.py limits [--down B --up B]   show, or set, the global speed limits (bytes/s, 0 = none)
  qb.py search QUERY [--plugins a,b] [--cat C]   stream results from the search plugins, one JSON line per batch
  qb.py search-plugins        the installed search plugins, with whether each is on
  qb.py search-plugin NAME on|off   turn one plugin on or off
  qb.py search-update         fetch newer versions of the official plugins
  qb.py start-service         start qbittorrent-nox in the background
  qb.py shutdown              ask qBittorrent to quit

The address is QB_URL, else http://127.0.0.1:<WebUI\\Port from qBittorrent.conf>. The shell
relies on "bypass authentication for clients on localhost", so no password is stored here.
All subprocesses are started from argument lists, never through a shell.
"""
import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

CONF = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "qBittorrent" / "qBittorrent.conf"
HASH_RE = re.compile(r"^[0-9a-fA-F]{40}$|^[0-9a-fA-F]{64}$")
ACTIONS = {"stop", "start", "recheck", "reannounce", "delete", "delete-files"}
PRIOS = {0, 1, 6, 7}
# Changes to torrents, by name: the API path and the form field the value goes in ("" = none)
OPS = {
    "sequential": ("torrents/toggleSequentialDownload", ""),
    "first-last": ("torrents/toggleFirstLastPiecePrio", ""),
    "force-start": ("torrents/setForceStart", "value"),
    "dl-limit": ("torrents/setDownloadLimit", "limit"),
    "up-limit": ("torrents/setUploadLimit", "limit"),
    "category": ("torrents/setCategory", "category"),
    "location": ("torrents/setLocation", "location"),
    "auto-tmm": ("torrents/setAutoManagement", "enable"),
}
# The preferences the app may read and write, with the type each must have
PREFS = {
    "save_path": str, "temp_path_enabled": bool, "temp_path": str,
    "queueing_enabled": bool, "max_active_downloads": int, "max_active_uploads": int, "max_active_torrents": int,
    "dl_limit": int, "up_limit": int, "alt_dl_limit": int, "alt_up_limit": int,
    "dht": bool, "pex": bool, "lsd": bool, "upnp": bool, "listen_port": int,
    "max_connec": int, "max_uploads": int, "encryption": int,
    "max_ratio_enabled": bool, "max_ratio": float, "start_paused_enabled": bool,
}


def base_url():
    env = os.environ.get("QB_URL")
    if env:
        return env.rstrip("/")
    port = 8080
    try:
        text = CONF.read_text()
        # Newer versions keep it as "Port=" under [WebUI], older ones as "WebUI\\Port=" in [Preferences]
        sect = re.search(r"^\[WebUI\]\s*$(.*?)(?=^\[|\Z)", text, re.M | re.S)
        m = (sect and re.search(r"^Port=(\d+)", sect.group(1), re.M)) or re.search(r"^WebUI\\Port=(\d+)", text, re.M)
        if m:
            port = int(m.group(1))
    except OSError:
        pass
    return f"http://127.0.0.1:{port}"


BASE = base_url()


class Down(Exception):
    pass


class Denied(Exception):
    pass


def call(path, data=None, raw=None, ctype=None, timeout=6):
    headers = {"Referer": BASE + "/", "Origin": BASE}
    body = None
    if raw is not None:
        body, headers["Content-Type"] = raw, ctype
    elif data is not None:
        body = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(BASE + "/api/v2/" + path, data=body, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            raise Denied()
        raise Down(f"HTTP {e.code}")
    except (urllib.error.URLError, OSError, TimeoutError):
        raise Down()


def jcall(path, data=None):
    return json.loads(call(path, data) or "null")


def out(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def snapshot():
    try:
        torrents = jcall("torrents/info")
        info = jcall("transfer/info")
        cats = jcall("torrents/categories") or {}
        alt = call("transfer/speedLimitsMode").strip() == "1"
    except Down:
        return {"state": "down", "base": BASE}
    except Denied:
        return {"state": "denied", "base": BASE}
    keep = ("hash", "name", "state", "progress", "size", "total_size", "dlspeed", "upspeed", "eta", "ratio",
            "num_seeds", "num_leechs", "num_complete", "num_incomplete", "added_on", "completion_on",
            "save_path", "category", "downloaded", "uploaded", "availability", "seq_dl", "f_l_piece_prio", "force_start",
            "priority", "dl_limit", "up_limit", "tags", "amount_left", "content_path", "auto_tmm", "magnet_uri")
    return {"state": "up", "base": BASE,
            "torrents": [{k: t.get(k) for k in keep} for t in torrents],
            "transfer": {k: info.get(k, 0) for k in ("dl_info_speed", "up_info_speed", "dl_info_data", "up_info_data",
                                                      "dl_rate_limit", "up_rate_limit")},
            "dht": info.get("dht_nodes", 0), "connection": info.get("connection_status", ""),
            "categories": [{"name": n, "path": (c or {}).get("savePath", "")} for n, c in sorted(cats.items())],
            "alt": alt}


def cmd_watch(_):
    # Only changes are sent: with qBittorrent down or idle, the window would otherwise
    # re-parse and rebuild the same list every two seconds.
    # The shell writes a line to stdin after it changes something; the watcher then looks
    # every 0.3 s for a few seconds (qBittorrent takes a moment to act) instead of waiting out
    # the slow interval.
    import select
    last = None
    fast_until = 0.0
    listening = True
    while True:
        line = json.dumps(snapshot())
        if line != last:
            last = line
            sys.stdout.write(line + "\n")
            sys.stdout.flush()
        wait = 0.3 if time.time() < fast_until else 2
        if not listening:
            time.sleep(wait)
            continue
        try:
            ready, _, _ = select.select([sys.stdin], [], [], wait)
        except (OSError, ValueError):
            listening = False
            continue
        if ready:
            if sys.stdin.readline():
                fast_until = time.time() + 5
            else:
                listening = False             # the shell closed the pipe: plain polling from here


def cmd_action(args):
    hashes = [h for h in args.hashes if HASH_RE.match(h)]
    if not hashes or args.act not in ACTIONS:
        sys.exit("bad arguments")
    joined = "|".join(hashes)
    try:
        if args.act in ("delete", "delete-files"):
            call("torrents/delete", {"hashes": joined, "deleteFiles": "true" if args.act == "delete-files" else "false"})
        elif args.act in ("stop", "start"):
            try:
                call("torrents/" + args.act, {"hashes": joined})
            except Down:
                # qBittorrent before 5 calls them pause and resume
                call("torrents/" + ("pause" if args.act == "stop" else "resume"), {"hashes": joined})
        else:
            call("torrents/" + args.act, {"hashes": joined})
    except (Down, Denied) as e:
        sys.exit(str(e) or "qBittorrent is not reachable")


def multipart(fields, files):
    boundary = uuid.uuid4().hex
    parts = []
    for k, v in fields.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
    for k, (name, content) in files.items():
        parts.append((f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"; filename="{name}"\r\n'
                      "Content-Type: application/x-bittorrent\r\n\r\n").encode() + content + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def add_fields(args):
    fields = {}
    if args.dir:
        fields["savepath"] = args.dir
    if args.category:
        fields["category"] = args.category
    if args.paused:
        fields["paused"] = "true"
        fields["stopped"] = "true"
    if args.sequential:
        fields["sequentialDownload"] = "true"
    if args.skip_check:
        fields["skip_checking"] = "true"
    return fields


def cmd_add_url(args):
    url = args.url.strip()
    if not re.match(r"^(magnet:\?|https?://)", url):
        sys.exit("that is not a magnet or web link")
    fields = add_fields(args)
    fields["urls"] = url
    body, ctype = multipart(fields, {})
    try:
        call("torrents/add", raw=body, ctype=ctype)
    except (Down, Denied) as e:
        sys.exit(str(e) or "qBittorrent is not reachable")


def cmd_add_file(args):
    path = Path(args.path)
    try:
        content = path.read_bytes()
    except OSError:
        sys.exit("cannot read that file")
    if not content.startswith(b"d"):
        sys.exit("that is not a .torrent file")
    body, ctype = multipart(add_fields(args), {"torrents": (path.name, content)})
    try:
        call("torrents/add", raw=body, ctype=ctype)
    except (Down, Denied) as e:
        sys.exit(str(e) or "qBittorrent is not reachable")


def cmd_detail(args):
    if not HASH_RE.match(args.hash):
        sys.exit("bad hash")
    h = urllib.parse.quote(args.hash)
    try:
        files = jcall("torrents/files?hash=" + h) or []
        trackers = jcall("torrents/trackers?hash=" + h) or []
        props = jcall("torrents/properties?hash=" + h) or {}
        try:
            peers = (jcall(f"sync/torrentPeers?hash={h}&rid=0") or {}).get("peers", {})
        except Down:
            peers = {}
    except (Down, Denied) as e:
        out({"ok": False, "error": str(e) or "qBittorrent is not reachable"})
        return
    keep = ("addition_date", "completion_date", "creation_date", "created_by", "comment", "piece_size", "pieces_have",
            "pieces_num", "total_size", "total_downloaded", "total_uploaded", "share_ratio", "time_elapsed",
            "seeding_time", "nb_connections", "is_private", "save_path", "dl_limit", "up_limit", "peers", "seeds")
    out({"ok": True, "hash": args.hash,
         "props": {k: props.get(k) for k in keep},
         "files": [{"index": i, "name": f.get("name"), "size": f.get("size"), "progress": f.get("progress"),
                    "priority": f.get("priority")} for i, f in enumerate(files)],
         "trackers": [{"url": t.get("url"), "status": t.get("status"), "peers": t.get("num_peers"),
                       "msg": t.get("msg")} for t in trackers if str(t.get("url", "")).startswith(("http", "udp", "wss"))],
         "peers": [{"ip": p.get("ip"), "client": p.get("client"), "progress": p.get("progress"),
                    "dl": p.get("dl_speed"), "up": p.get("up_speed"), "country": p.get("country_code")}
                   for p in sorted(peers.values(), key=lambda p: -(p.get("dl_speed", 0) + p.get("up_speed", 0)))[:50]]})


def cmd_file_prio(args):
    if not HASH_RE.match(args.hash) or args.prio not in PRIOS or not all(re.fullmatch(r"\d{1,6}", i) for i in args.ids):
        sys.exit("bad arguments")
    try:
        call("torrents/filePrio", {"hash": args.hash, "id": "|".join(args.ids), "priority": str(args.prio)})
    except (Down, Denied) as e:
        sys.exit(str(e) or "qBittorrent is not reachable")


def cmd_queue(args):
    hashes = [h for h in args.hashes if HASH_RE.match(h)]
    path = {"top": "topPrio", "bottom": "bottomPrio", "up": "increasePrio", "down": "decreasePrio"}.get(args.move)
    if not hashes or not path:
        sys.exit("bad arguments")
    try:
        call("torrents/" + path, {"hashes": "|".join(hashes)})
    except (Down, Denied) as e:
        sys.exit(str(e) or "qBittorrent is not reachable")


def cmd_op(args):
    hashes = [h for h in args.hashes if HASH_RE.match(h)]
    if not hashes or args.op not in OPS and args.op != "rename":
        sys.exit("bad arguments")
    try:
        if args.op == "rename":
            if len(hashes) != 1 or not args.value.strip():
                sys.exit("bad arguments")
            call("torrents/rename", {"hash": hashes[0], "name": args.value.strip()})
            return
        path, field = OPS[args.op]
        data = {"hashes": "|".join(hashes)}
        if field:
            data[field] = args.value
        call(path, data)
    except (Down, Denied) as e:
        sys.exit(str(e) or "qBittorrent is not reachable")


def cmd_category(args):
    name = args.name.strip()
    if not name or len(name) > 100:
        sys.exit("bad name")
    try:
        if args.action == "add":
            call("torrents/createCategory", {"category": name, "savePath": args.dir or ""})
        else:
            call("torrents/removeCategories", {"categories": name})
    except (Down, Denied) as e:
        sys.exit(str(e) or "qBittorrent is not reachable")


def cmd_prefs(_):
    try:
        prefs = jcall("app/preferences") or {}
    except (Down, Denied) as e:
        out({"ok": False, "error": str(e) or "qBittorrent is not reachable"})
        return
    out({"ok": True, "prefs": {k: prefs.get(k) for k in PREFS if k in prefs}})


def cmd_set_prefs(args):
    try:
        wanted = json.loads(args.json)
    except ValueError:
        sys.exit("bad JSON")
    clean = {}
    for k, v in (wanted.items() if isinstance(wanted, dict) else []):
        t = PREFS.get(k)
        if t is None:
            continue
        if t is float and isinstance(v, (int, float)) and not isinstance(v, bool):
            clean[k] = float(v)
        elif t is int and isinstance(v, int) and not isinstance(v, bool):
            clean[k] = v
        elif isinstance(v, t) and not (t is not bool and isinstance(v, bool)):
            clean[k] = v
    if not clean:
        sys.exit("nothing to change")
    try:
        call("app/setPreferences", {"json": json.dumps(clean)})
    except (Down, Denied) as e:
        sys.exit(str(e) or "qBittorrent is not reachable")


def cmd_alt_speed(_):
    try:
        call("transfer/toggleSpeedLimitsMode", {})
    except (Down, Denied) as e:
        sys.exit(str(e) or "qBittorrent is not reachable")


def cmd_limits(args):
    try:
        if args.down is not None:
            call("transfer/setDownloadLimit", {"limit": str(max(0, args.down))})
        if args.up is not None:
            call("transfer/setUploadLimit", {"limit": str(max(0, args.up))})
        out({"ok": True, "down": int(call("transfer/downloadLimit") or 0), "up": int(call("transfer/uploadLimit") or 0)})
    except (Down, Denied) as e:
        out({"ok": False, "error": str(e) or "qBittorrent is not reachable"})


def cmd_search_plugins(_):
    try:
        plugins = jcall("search/plugins") or []
    except (Down, Denied) as e:
        out({"ok": False, "error": str(e) or "qBittorrent is not reachable"})
        return
    out({"ok": True, "plugins": [
        {"name": p.get("name"), "title": p.get("fullName") or p.get("name"), "enabled": bool(p.get("enabled")),
         "version": p.get("version"), "url": p.get("url"),
         "categories": [{"id": c.get("id"), "name": c.get("name")} for c in p.get("supportedCategories", [])]}
        for p in plugins if p.get("name")]})


def cmd_search_plugin(args):
    if not re.fullmatch(r"[\w.-]{1,60}", args.name):
        sys.exit("bad plugin name")
    try:
        call("search/enablePlugin", {"names": args.name, "enable": "true" if args.state == "on" else "false"})
    except (Down, Denied) as e:
        sys.exit(str(e) or "qBittorrent is not reachable")


def cmd_search_update(_):
    try:
        call("search/updatePlugins", {})
    except (Down, Denied) as e:
        sys.exit(str(e) or "qBittorrent is not reachable")


def cmd_search(args):
    query = args.query.strip()
    if not query or len(query) > 200:
        sys.exit("empty search")
    plugins = args.plugins.strip() or "enabled"
    if plugins not in ("enabled", "all") and not re.fullmatch(r"[\w.-]+(\|[\w.-]+)*", plugins.replace(",", "|")):
        sys.exit("bad plugins")
    plugins = plugins.replace(",", "|")
    sid = None

    def cleanup(*_):
        # qBittorrent keeps at most five searches, so leave nothing behind
        if sid is not None:
            try:
                call("search/stop", {"id": str(sid)})
                call("search/delete", {"id": str(sid)})
            except (Down, Denied):
                pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)
    try:
        # Old searches of ours (a reload killed the app mid-way) would fill the five slots
        for st in jcall("search/status") or []:
            try:
                call("search/stop", {"id": str(st.get("id"))})
                call("search/delete", {"id": str(st.get("id"))})
            except Down:
                pass
        sid = (jcall("search/start", {"pattern": query, "plugins": plugins, "category": args.cat}) or {}).get("id")
        if sid is None:
            raise Down("the search did not start")
        offset = 0
        idle = 0
        while True:
            time.sleep(0.8)
            data = jcall(f"search/results?id={sid}&limit=200&offset={offset}") or {}
            rows = data.get("results") or []
            offset += len(rows)
            done = data.get("status") != "Running"
            if rows or done:
                out({"ok": True, "done": done and not rows, "rows": [
                    {"name": r.get("fileName"), "url": r.get("fileUrl"), "size": r.get("fileSize"),
                     "seeds": r.get("nbSeeders"), "peers": r.get("nbLeechers"), "site": r.get("siteUrl"),
                     "page": r.get("descrLink"), "engine": r.get("engineName"), "date": r.get("pubDate")}
                    for r in rows if r.get("fileUrl")]})
            if done and not rows:
                break
            idle = 0 if rows else idle + 1
            if idle > 150:  # two minutes without a result: give up on the slow sites
                out({"ok": True, "done": True, "rows": []})
                break
    except (Down, Denied) as e:
        out({"ok": False, "error": str(e) or "qBittorrent is not reachable"})
    finally:
        cleanup()


def cmd_start_service(_):
    exe = shutil.which("qbittorrent-nox")
    if not exe:
        sys.exit("qbittorrent-nox is not installed")
    subprocess.Popen([exe], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def cmd_shutdown(_):
    try:
        call("app/shutdown", {})
    except (Down, Denied) as e:
        sys.exit(str(e) or "qBittorrent is not reachable")


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("watch").set_defaults(fn=cmd_watch)
    a = sub.add_parser("action"); a.add_argument("act"); a.add_argument("hashes", nargs="+"); a.set_defaults(fn=cmd_action)
    for name, arg, fn in (("add-url", "url", cmd_add_url), ("add-file", "path", cmd_add_file)):
        a = sub.add_parser(name); a.add_argument(arg); a.add_argument("--dir"); a.add_argument("--category")
        a.add_argument("--paused", action="store_true"); a.add_argument("--sequential", action="store_true")
        a.add_argument("--skip-check", action="store_true"); a.set_defaults(fn=fn)
    a = sub.add_parser("file-prio"); a.add_argument("hash"); a.add_argument("prio", type=int); a.add_argument("ids", nargs="+")
    a.set_defaults(fn=cmd_file_prio)
    a = sub.add_parser("queue"); a.add_argument("move"); a.add_argument("hashes", nargs="+"); a.set_defaults(fn=cmd_queue)
    a = sub.add_parser("op"); a.add_argument("op"); a.add_argument("hashes", nargs="+"); a.add_argument("--value", default="")
    a.set_defaults(fn=cmd_op)
    a = sub.add_parser("category"); a.add_argument("action", choices=["add", "remove"]); a.add_argument("name")
    a.add_argument("--dir"); a.set_defaults(fn=cmd_category)
    sub.add_parser("prefs").set_defaults(fn=cmd_prefs)
    a = sub.add_parser("set-prefs"); a.add_argument("json"); a.set_defaults(fn=cmd_set_prefs)
    sub.add_parser("alt-speed").set_defaults(fn=cmd_alt_speed)
    a = sub.add_parser("detail"); a.add_argument("hash"); a.set_defaults(fn=cmd_detail)
    a = sub.add_parser("limits"); a.add_argument("--down", type=int); a.add_argument("--up", type=int); a.set_defaults(fn=cmd_limits)
    a = sub.add_parser("search"); a.add_argument("query"); a.add_argument("--plugins", default="enabled")
    a.add_argument("--cat", default="all"); a.set_defaults(fn=cmd_search)
    sub.add_parser("search-plugins").set_defaults(fn=cmd_search_plugins)
    a = sub.add_parser("search-plugin"); a.add_argument("name"); a.add_argument("state", choices=["on", "off"])
    a.set_defaults(fn=cmd_search_plugin)
    sub.add_parser("search-update").set_defaults(fn=cmd_search_update)
    sub.add_parser("start-service").set_defaults(fn=cmd_start_service)
    sub.add_parser("shutdown").set_defaults(fn=cmd_shutdown)
    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
