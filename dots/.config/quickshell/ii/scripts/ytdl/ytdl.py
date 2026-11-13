#!/usr/bin/env python3
"""ytdl: a small JSON front for yt-dlp, used by the shell's Downloads app.

    ytdl info URL                 what a link is (title, thumbnail, playlist entries)
    ytdl start URL [--preset P] [--title T] [--thumb U] [--playlist] [--subs] [--dir D]
                                  queue a download; a detached worker runs it
    ytdl list                     every job, newest first
    ytdl cancel ID | remove ID | clear
    ytdl config show | set        settings (patch in $YTDL_CONFIG_PATCH as JSON)

Every command prints JSON. Jobs are files under ~/.local/state/ytdl/jobs, written by the
worker as it goes, so downloads carry on when the window is closed and the window just
reads the folder. Standard library only; yt-dlp and ffmpeg are the only dependencies.
"""
import argparse
import fcntl
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

HOME = Path.home()
CONFIG = HOME / ".config" / "ytdl" / "config.json"
STATE = HOME / ".local" / "state" / "ytdl"
JOBS = STATE / "jobs"

DEFAULTS = {
    "dir": str(HOME / "Videos" / "Downloads"),
    "preset": "best",
    "cookies_browser": "",
    "rate_limit": "",
    "max_parallel": 2,
    "notify": True,
    "subs": False,
}
PRESETS = {
    "best": {"label": "Best quality", "audio": False,
             "args": ["-f", "bv*+ba/b", "--merge-output-format", "mkv"]},
    "1080": {"label": "1080p", "audio": False,
             "args": ["-f", "bv*[height<=1080]+ba/b[height<=1080]", "--merge-output-format", "mp4"]},
    "720": {"label": "720p", "audio": False,
            "args": ["-f", "bv*[height<=720]+ba/b[height<=720]", "--merge-output-format", "mp4"]},
    "480": {"label": "480p", "audio": False,
            "args": ["-f", "bv*[height<=480]+ba/b[height<=480]", "--merge-output-format", "mp4"]},
    "mp3": {"label": "Audio (MP3)", "audio": True,
            "args": ["-x", "--audio-format", "mp3", "--audio-quality", "0",
                     "--embed-thumbnail", "--embed-metadata"]},
    "opus": {"label": "Audio (Opus)", "audio": True,
             "args": ["-x", "--audio-format", "opus", "--embed-metadata"]},
}
SETTABLE = {"dir": str, "preset": str, "cookies_browser": str, "rate_limit": str,
            "max_parallel": int, "notify": bool, "subs": bool}
# Plain files (an ISO, an archive, a PDF) are not yt-dlp's business: aria2c takes them, with
# several connections to the server and resume. It also speaks FTP and SFTP, which axel does not.
FILE_CONNECTIONS = 8
FILE_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
BROWSERS = {"", "firefox", "chrome", "chromium", "brave", "edge", "opera", "vivaldi", "zen"}


def out(obj, code=0):
    print(json.dumps(obj, ensure_ascii=False))
    sys.exit(code)


def fail(msg):
    out({"ok": False, "error": msg}, 1)


# ── config ──────────────────────────────────────────────────────────────────────────────

def load_config():
    cfg = dict(DEFAULTS)
    try:
        cfg.update({k: v for k, v in json.loads(CONFIG.read_text()).items() if k in DEFAULTS})
    except (OSError, ValueError):
        pass
    cfg["dir"] = os.path.expanduser(cfg["dir"])
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
        elif want is int:
            try:
                val = int(val)
            except (TypeError, ValueError):
                raise ValueError(f"{key} must be a number")
            if not 1 <= val <= 8:
                raise ValueError("max_parallel must be between 1 and 8")
        else:
            val = str(val).strip()
        if key == "preset" and val not in PRESETS:
            raise ValueError(f"unknown preset: {val}")
        if key == "cookies_browser" and val not in BROWSERS:
            raise ValueError(f"unsupported browser: {val}")
        if key == "rate_limit" and val and not re.fullmatch(r"\d+(\.\d+)?[KkMm]?", val):
            raise ValueError("speed limit looks like 500K or 2M")
        if key == "dir" and not val:
            raise ValueError("the download folder cannot be empty")
        cfg[key] = val
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    CONFIG.write_text(json.dumps(cfg, indent=2) + "\n")
    return load_config()


def settings_view():
    cfg = load_config()
    cfg["presets"] = [{"id": k, "label": v["label"], "audio": v["audio"]} for k, v in PRESETS.items()]
    cfg["path"] = str(CONFIG)
    cfg["yt_dlp"] = shutil.which("yt-dlp") is not None
    cfg["ffmpeg"] = shutil.which("ffmpeg") is not None
    cfg["aria2c"] = shutil.which("aria2c") is not None
    return cfg


# ── info ────────────────────────────────────────────────────────────────────────────────

def base_cmd(cfg):
    cmd = ["yt-dlp", "--no-colors", "--ignore-config"]
    if cfg["cookies_browser"]:
        cmd += ["--cookies-from-browser", cfg["cookies_browser"]]
    if cfg["rate_limit"]:
        cmd += ["--limit-rate", cfg["rate_limit"]]
    return cmd


def best_thumb(d):
    if d.get("thumbnail"):
        return d["thumbnail"]
    thumbs = [t for t in d.get("thumbnails") or [] if t.get("url")]
    return thumbs[-1]["url"] if thumbs else ""


def summarize(d):
    return {
        "title": d.get("title") or d.get("id") or "",
        "uploader": d.get("uploader") or d.get("channel") or d.get("uploader_id") or "",
        "duration": d.get("duration") or 0,
        "thumbnail": best_thumb(d),
        "url": d.get("webpage_url") or d.get("url") or "",
        "site": d.get("extractor_key") or d.get("ie_key") or "",
    }


def human_size(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024


def probe_file(url, timeout=15):
    """What a link is when it is a plain file: {name, size, mime}. None for a web page or anything unreachable."""
    parts = urllib.parse.urlparse(url)
    if parts.scheme not in ("http", "https", "ftp", "sftp"):
        return None
    name = urllib.parse.unquote(os.path.basename(parts.path))
    size, mime, disposition = 0, "", ""
    if parts.scheme in ("http", "https"):
        headers = None
        for method, extra in (("HEAD", {}), ("GET", {"Range": "bytes=0-0"})):
            try:
                req = urllib.request.Request(url, method=method, headers={"User-Agent": FILE_AGENT, **extra})
                with urllib.request.urlopen(req, timeout=timeout) as r:
                    headers = r.headers
                    break
            except (urllib.error.URLError, OSError, ValueError):
                continue
        if headers is None:
            return None
        mime = (headers.get("Content-Type") or "").split(";")[0].strip().lower()
        if mime in ("text/html", "application/xhtml+xml"):
            return None
        disposition = headers.get("Content-Disposition") or ""
        total = re.search(r"/(\d+)$", headers.get("Content-Range") or "")
        size = int(total.group(1)) if total else int(headers.get("Content-Length") or 0)
        found = re.search(r"filename\*=(?:UTF-8'')?([^;]+)", disposition, re.I) \
            or re.search(r'filename="?([^";]+)"?', disposition, re.I)
        if found:
            name = urllib.parse.unquote(found.group(1).strip().strip('"'))
    name = name.replace("/", "_").strip() or "download"
    return {"name": name, "size": size, "mime": mime, "host": parts.hostname or ""}


def file_info(url, probe):
    sizeText = f" · {human_size(probe['size'])}" if probe["size"] else ""
    return {"title": probe["name"], "uploader": probe["host"] + sizeText, "duration": 0, "thumbnail": "",
            "url": url, "site": "Direct file", "playlist": False, "kind": "file", "size": probe["size"]}


def cmd_info(args):
    cfg = load_config()
    if shutil.which("yt-dlp") is None:
        probe = probe_file(args.url)
        if probe:
            out({"ok": True, "info": file_info(args.url, probe)})
        fail("yt-dlp is not installed")
    try:
        p = subprocess.run(base_cmd(cfg) + ["-J", "--flat-playlist", "--no-warnings", args.url],
                           capture_output=True, text=True, timeout=args.timeout)
    except subprocess.TimeoutExpired:
        fail("the site took too long to answer")
    if p.returncode != 0:
        probe = probe_file(args.url)
        if probe and shutil.which("aria2c"):
            out({"ok": True, "info": file_info(args.url, probe)})
        lines = [l for l in p.stderr.strip().splitlines() if l.strip()]
        msg = re.sub(r"^ERROR:\s*(\[[^\]]+\]\s*)?", "", lines[-1]) if lines else "yt-dlp failed"
        if probe:
            msg = "this is a plain file and aria2c is not installed to download it"
        fail(msg)
    try:
        d = json.loads(p.stdout)
    except ValueError:
        fail("yt-dlp returned something unreadable")
    info = summarize(d)
    info["url"] = info["url"] or args.url
    # yt-dlp's catch-all extractor will "download" any direct link; a plain file is better
    # served by aria2c (several connections, resume, the exact bytes). Streams stay yt-dlp's.
    if info["site"] == "Generic" and d.get("entries") is None and shutil.which("aria2c"):
        probe = probe_file(args.url)
        if probe and not re.search(r"mpegurl|dash\+xml|f4m", probe["mime"]) \
                and not re.search(r"\.(m3u8|mpd|f4m)(\?|$)", args.url, re.I):
            out({"ok": True, "info": file_info(args.url, probe)})
    entries = d.get("entries")
    info["playlist"] = entries is not None
    if entries is not None:
        items = [e for e in entries if e]
        info["count"] = len(items)
        info["entries"] = [{"title": e.get("title") or e.get("id") or "",
                            "duration": e.get("duration") or 0} for e in items[:200]]
        if not info["thumbnail"] and items:
            info["thumbnail"] = best_thumb(items[0])
    out({"ok": True, "info": info})


# ── jobs ────────────────────────────────────────────────────────────────────────────────

def job_path(job_id):
    return JOBS / f"{job_id}.json"


def read_job(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def write_job(job):
    JOBS.mkdir(parents=True, exist_ok=True)
    tmp = job_path(job["id"]).with_suffix(".tmp")
    tmp.write_text(json.dumps(job, ensure_ascii=False))
    os.replace(tmp, job_path(job["id"]))


def alive(pid):
    if not pid:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    try:  # a zombie still answers kill(0)
        return Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[0] != "Z"
    except OSError:
        return False


def all_jobs():
    jobs = []
    for path in JOBS.glob("*.json") if JOBS.exists() else []:
        job = read_job(path)
        if job is None:
            continue
        # A worker that died without saying so (reboot, kill -9) must not look busy forever
        if job["status"] in ("queued", "running", "processing") and not alive(job.get("worker")):
            job["status"] = "error"
            job["error"] = job.get("error") or "Interrupted"
            write_job(job)
        jobs.append(job)
    jobs.sort(key=lambda j: j.get("created", 0), reverse=True)
    return jobs


def cmd_start(args):
    if args.kind == "file":
        if shutil.which("aria2c") is None:
            fail("aria2c is not installed")
    elif shutil.which("yt-dlp") is None:
        fail("yt-dlp is not installed")
    cfg = load_config()
    preset = args.preset or cfg["preset"]
    if preset not in PRESETS:
        fail(f"unknown preset: {preset}")
    dest = os.path.expanduser(args.dir or cfg["dir"])
    job = {
        "id": uuid.uuid4().hex[:10], "url": args.url, "title": args.title or args.url,
        "thumbnail": args.thumb or "", "preset": preset, "playlist": bool(args.playlist),
        "subs": bool(args.subs or cfg["subs"]), "dir": dest, "status": "queued",
        "percent": 0, "speed": 0, "eta": 0, "downloaded": 0, "total": 0,
        "index": 0, "count": 0, "current": "", "file": "", "error": "",
        "created": time.time(), "finished": 0, "worker": 0, "pid": 0,
        # Jobs from other apps: `resolve` is a command that prints {url, referer, subtitles} once the
        # job gets a slot (stream links expire, so they are fetched late), `name` the file stem,
        # `tag` a key the owning app finds its jobs by.
        "tag": args.tag or "", "name": args.name or "", "referer": args.referer or "",
        "resolve": json.loads(args.resolve) if args.resolve else [], "subtitle_url": "",
        "scale": int(args.scale or 0), "phase": "", "kind": "file" if args.kind == "file" else "",
    }
    write_job(job)
    worker = subprocess.Popen([sys.executable, os.path.abspath(__file__), "work", job["id"]],
                              stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, start_new_session=True)
    job["worker"] = worker.pid
    write_job(job)
    out({"ok": True, "job": job})


def cmd_list(_args):
    out({"ok": True, "jobs": all_jobs()})


def cmd_watch(args):
    """`list` as a stream for an open window: one line now, then one whenever a job file
    changes. Between changes it only stats the job files, so it costs next to nothing; the
    list is still re-read every few seconds so a worker that died without a word shows."""
    last_sig, last_line, last_full = None, None, 0.0
    parent = os.getppid()
    while True:
        # Orphaned (reader gone, reparented): nobody will ever read another line.
        if os.getppid() != parent:
            return
        try:
            sig = sorted((e.name, e.stat().st_mtime_ns) for e in os.scandir(JOBS) if e.name.endswith(".json"))
        except OSError:
            sig = []
        now = time.monotonic()
        if sig != last_sig or now - last_full > 5:
            last_sig, last_full = sig, now
            line = json.dumps({"ok": True, "jobs": all_jobs()}, ensure_ascii=False)
            if line != last_line:
                last_line = line
                try:
                    print(line, flush=True)
                except BrokenPipeError:
                    return
        time.sleep(args.interval)


def cmd_cancel(args):
    job = read_job(job_path(args.id))
    if job is None:
        fail("no such download")
    if job["status"] in ("queued", "running", "processing"):
        job["status"] = "cancelled"
        job["finished"] = time.time()
        write_job(job)
        for pid in (job.get("pid"), job.get("worker")):
            if pid and alive(pid):
                try:
                    os.killpg(os.getpgid(pid), signal.SIGTERM)
                except (ProcessLookupError, PermissionError):
                    pass
    out({"ok": True})


def cmd_remove(args):
    job = read_job(job_path(args.id))
    if job and job["status"] in ("queued", "running", "processing"):
        fail("cancel it first")
    job_path(args.id).unlink(missing_ok=True)
    out({"ok": True})


def cmd_clear(_args):
    n = 0
    for job in all_jobs():
        if job["status"] in ("done", "error", "cancelled"):
            job_path(job["id"]).unlink(missing_ok=True)
            n += 1
    out({"ok": True, "removed": n})


# ── the worker ──────────────────────────────────────────────────────────────────────────

PROGRESS = "download:ytdl|%(progress.status)s|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|" \
           "%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s|" \
           "%(info.playlist_index)s|%(info.playlist_count)s"


def num(text):
    try:
        return float(text)
    except ValueError:
        return 0.0


def notify(cfg, title, body):
    if cfg["notify"] and shutil.which("notify-send"):
        subprocess.Popen(["notify-send", "-a", "Downloads", "-i", "folder-download", title, body],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def wait_for_slot(job, cfg):
    """Hold the job in "queued" until fewer than max_parallel others are running."""
    JOBS.mkdir(parents=True, exist_ok=True)
    with open(STATE / "slots.lock", "a+") as lock:
        while True:
            fcntl.flock(lock, fcntl.LOCK_EX)
            try:
                fresh = read_job(job_path(job["id"]))
                if fresh is None or fresh["status"] == "cancelled":
                    return False
                busy = [j for j in all_jobs() if j["id"] != job["id"] and j["status"] in ("running", "processing")]
                if len(busy) < max(1, int(cfg["max_parallel"])):
                    job["status"] = "running"
                    write_job(job)
                    return True
            finally:
                fcntl.flock(lock, fcntl.LOCK_UN)
            time.sleep(1)


def fail_job(job, cfg, message):
    fresh = read_job(job_path(job["id"]))
    if fresh is not None and fresh["status"] == "cancelled":
        return
    job["status"], job["error"], job["finished"] = "error", message, time.time()
    write_job(job)
    notify(cfg, "Download failed", message)


def resolve_job(job, cfg):
    """Ask the owning app for the real URL now that the job has a slot. False = job failed."""
    try:
        proc = subprocess.run(job["resolve"], capture_output=True, text=True, timeout=120)
        lines = [line for line in proc.stdout.splitlines() if line.strip()]
        data = json.loads(lines[-1]) if lines else {}
    except (subprocess.TimeoutExpired, OSError, ValueError):
        data = {}
    if not data.get("ok") or not data.get("url"):
        fail_job(job, cfg, str(data.get("error") or "could not find a source for this episode"))
        return False
    job["url"], job["referer"] = data["url"], data.get("referer") or ""
    job["subtitle_url"] = data.get("subtitles") or ""
    write_job(job)
    return True


def scale_video(job):
    """Re-encode the finished file down to `scale` pixels high (the source offers one quality).
    Runs at low priority so it does not starve a video you are watching. Keeps the original on failure."""
    video = Path(job["file"])
    if shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None:
        return
    probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                            "stream=height:format=duration", "-of", "json", str(video)],
                           capture_output=True, text=True)
    try:
        info = json.loads(probe.stdout)
        height = int(info["streams"][0]["height"])
        duration = float(info["format"]["duration"])
    except (ValueError, KeyError, IndexError):
        return
    if height <= job["scale"] + 8:
        return
    job["phase"], job["percent"] = "Converting", 0
    write_job(job)
    target = video.with_name(video.stem + ".scaling.mkv")
    proc = subprocess.Popen(
        ["nice", "-n", "10", "ffmpeg", "-v", "error", "-y", "-i", str(video), "-map", "0",
         "-vf", f"scale=-2:{job['scale']}", "-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
         "-c:a", "copy", "-c:s", "copy", "-progress", "pipe:1", "-nostats", str(target)],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    job["pid"] = proc.pid
    last = 0.0
    for line in proc.stdout:
        if line.startswith("out_time_us=") and duration > 0:
            try:
                job["percent"] = round(min(99.0, int(line.split("=", 1)[1]) / 1e6 / duration * 100), 1)
            except ValueError:
                continue
            now = time.time()
            if now - last > 1.0:
                fresh = read_job(job_path(job["id"]))
                if fresh is not None and fresh["status"] == "cancelled":
                    proc.terminate()
                    break
                write_job(job)
                last = now
    done = proc.wait()
    job["phase"] = ""
    if done == 0 and target.is_file() and target.stat().st_size > 0:
        final = video.with_suffix(".mkv")
        video.unlink(missing_ok=True)
        target.replace(final)
        job["file"] = str(final)
    else:
        target.unlink(missing_ok=True)


def add_subtitles(job):
    """Mux the provider's separate .vtt into an .mkv beside the video; keep a sidecar on failure."""
    video = Path(job["file"])
    sidecar = video.with_suffix(".en.vtt")
    try:
        import urllib.request
        req = urllib.request.Request(job["subtitle_url"], headers={
            "User-Agent": "Mozilla/5.0", "Referer": job.get("referer") or ""})
        with urllib.request.urlopen(req, timeout=30) as r:
            sidecar.write_bytes(r.read())
    except (OSError, ValueError):
        return
    if shutil.which("ffmpeg") is None:
        return
    merged = video.with_name(video.stem + ".muxing.mkv")
    done = subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", str(video), "-i", str(sidecar), "-map", "0", "-map", "1",
         "-c", "copy", "-c:s", "srt", "-metadata:s:s:0", "language=eng", str(merged)],
        stdin=subprocess.DEVNULL, capture_output=True)
    if done.returncode == 0 and merged.stat().st_size > 0:
        final = video.with_suffix(".mkv")
        video.unlink(missing_ok=True)
        merged.replace(final)
        sidecar.unlink(missing_ok=True)
        job["file"] = str(final)
    else:
        merged.unlink(missing_ok=True)


ARIA_READOUT = re.compile(r"\[#\w+\s+(\d+)B?/(\d+)B?\((\d+)%\)\s+CN:\d+(?:\s+SD:\d+)?\s+DL:(\d+)B?(?:\s+ETA:(\w+))?\]")


def eta_seconds(text):
    total = 0
    for amount, unit in re.findall(r"(\d+)([dhms])", text or ""):
        total += int(amount) * {"d": 86400, "h": 3600, "m": 60, "s": 1}[unit]
    return total


def run_file_job(job, cfg):
    """A plain file through aria2c: several connections, resume, and the same job file as any other download."""
    name = (job.get("name") or "").strip()
    if not name:
        name = job["title"] if job["title"] != job["url"] else (os.path.basename(urllib.parse.urlparse(job["url"]).path) or "download")
    name = urllib.parse.unquote(name).replace("/", "_")
    job["current"] = name
    if job["title"] == job["url"]:
        job["title"] = name
    Path(job["dir"]).mkdir(parents=True, exist_ok=True)
    cmd = ["aria2c", "--human-readable=false", "--summary-interval=0", "--console-log-level=warn",
           "--download-result=hide", "--show-console-readout=true", "--enable-color=false",
           "-x", str(FILE_CONNECTIONS), "-s", str(FILE_CONNECTIONS), "-k", "1M", "-c",
           "--file-allocation=none", "--auto-file-renaming=true", "--user-agent=" + FILE_AGENT,
           "-d", job["dir"], "-o", name]
    if cfg["rate_limit"]:
        cmd += ["--max-overall-download-limit=" + cfg["rate_limit"]]
    if job.get("referer"):
        cmd += ["--referer=" + job["referer"]]
    cmd.append(job["url"])
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
    job["pid"] = proc.pid
    write_job(job)
    last_write, last_error, pending = 0.0, "", b""
    fd = proc.stdout.fileno()
    while True:
        chunk = os.read(fd, 4096)
        if not chunk:
            break
        pending += chunk
        *lines, pending = re.split(rb"[\r\n]", pending)
        dirty = False
        for raw in lines:
            line = raw.decode("utf-8", "replace").strip()
            m = ARIA_READOUT.search(line)
            if m:
                done, total, percent, speed = int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))
                job["downloaded"], job["total"], job["percent"] = done, total, float(percent)
                job["speed"], job["eta"] = speed, eta_seconds(m.group(5))
                job["index"], job["count"] = 1, 1
                dirty = True
            elif line and ("errorCode" in line or "ERR" in line or "exception" in line.lower()):
                last_error = re.sub(r"^\d\d/\d\d \d\d:\d\d:\d\d \[(ERROR|NOTICE)\]\s*", "", line)
        now = time.time()
        if dirty and now - last_write > 0.4:
            fresh = read_job(job_path(job["id"]))
            if fresh is not None and fresh["status"] == "cancelled":
                proc.terminate()
                break
            write_job(job)
            last_write = now
    code = proc.wait()
    fresh = read_job(job_path(job["id"]))
    if fresh is not None and fresh["status"] == "cancelled":
        return
    job["finished"] = time.time()
    job["speed"] = job["eta"] = 0
    target = Path(job["dir"]) / name
    if code == 0:
        job["file"] = str(target)
        job["status"], job["percent"] = "done", 100
        notify(cfg, "Download finished", name)
    else:
        job["status"] = "error"
        job["error"] = last_error or f"aria2c exited with {code}"
        notify(cfg, "Download failed", job["error"])
    write_job(job)


def cmd_work(args):
    job = read_job(job_path(args.id))
    if job is None:
        return
    cfg = load_config()
    job["worker"] = os.getpid()
    if not wait_for_slot(job, cfg):
        return
    if job.get("resolve") and not resolve_job(job, cfg):
        return
    if job.get("kind") == "file":
        run_file_job(job, cfg)
        return
    preset = PRESETS[job["preset"]]
    Path(job["dir"]).mkdir(parents=True, exist_ok=True)
    template = "%(playlist_title)s/%(playlist_index)02d - %(title)s.%(ext)s" if job["playlist"] \
        else "%(title)s.%(ext)s"
    if job.get("name"):
        template = job["name"].replace("%", "%%") + ".%(ext)s"
    cmd = base_cmd(cfg) + preset["args"] + [
        "--newline", "--progress", "--no-warnings", "-N", "4", "-P", job["dir"], "-o", template,
        "--progress-template", PROGRESS,
        "--print", "before_dl:ytdlTitle|%(title)s", "--print", "after_move:ytdlFile|%(filepath)s",
        "--yes-playlist" if job["playlist"] else "--no-playlist",
    ]
    if job["subs"] and not preset["audio"]:
        cmd += ["--write-subs", "--write-auto-subs", "--sub-langs", "en.*,en", "--embed-subs"]
    if not preset["audio"] and not job.get("resolve"):
        cmd += ["--embed-thumbnail", "--embed-metadata"]
    if job.get("referer"):
        cmd += ["--referer", job["referer"]]
    cmd.append(job["url"])

    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    job["pid"] = proc.pid
    write_job(job)
    last_write = 0.0
    last_error = ""
    for line in proc.stdout:
        line = line.rstrip("\n")
        dirty = False
        if line.startswith("ytdl|"):
            f = line.split("|")
            if len(f) >= 9:
                done, total, est = num(f[2]), num(f[3]), num(f[4])
                size = total or est
                job["downloaded"], job["total"] = int(done), int(size)
                job["percent"] = round(min(100.0, done / size * 100), 1) if size else job["percent"]
                job["speed"], job["eta"] = int(num(f[5])), int(num(f[6]))
                job["index"], job["count"] = int(num(f[7])), int(num(f[8]))
                dirty = True
        elif line.startswith("ytdlTitle|"):
            job["current"] = line.split("|", 1)[1]
            if not job["playlist"] and job["title"] == job["url"]:
                job["title"] = job["current"]
            dirty = True
        elif line.startswith("ytdlFile|"):
            job["file"] = line.split("|", 1)[1]
            dirty = True
        elif re.match(r"\[(Merger|ExtractAudio|EmbedThumbnail|Metadata|EmbedSubtitle|VideoConvertor|MoveFiles)\]", line):
            job["status"], job["speed"], job["eta"] = "processing", 0, 0
            dirty = True
        elif line.startswith("ERROR"):
            last_error = re.sub(r"^ERROR:\s*(\[[^\]]+\]\s*)?", "", line)
        now = time.time()
        if dirty and now - last_write > 0.4:
            fresh = read_job(job_path(job["id"]))
            if fresh is not None and fresh["status"] == "cancelled":
                proc.terminate()
                break
            write_job(job)
            last_write = now
    code = proc.wait()
    fresh = read_job(job_path(job["id"]))
    if fresh is not None and fresh["status"] == "cancelled":
        return
    job["finished"] = time.time()
    job["speed"] = job["eta"] = 0
    if code == 0 and job.get("scale") and job.get("file"):
        job["status"], job["speed"], job["eta"] = "processing", 0, 0
        write_job(job)
        scale_video(job)
        fresh = read_job(job_path(job["id"]))
        if fresh is not None and fresh["status"] == "cancelled":
            return
    if code == 0 and job.get("subtitle_url") and job.get("file"):
        job["status"], job["speed"], job["eta"] = "processing", 0, 0
        write_job(job)
        add_subtitles(job)
    if code == 0:
        job["status"], job["percent"] = "done", 100
        notify(cfg, "Download finished", job["current"] or job["title"])
    else:
        job["status"] = "error"
        job["error"] = last_error or f"yt-dlp exited with {code}"
        notify(cfg, "Download failed", job["error"])
    write_job(job)


# ── config command and main ─────────────────────────────────────────────────────────────

def cmd_config(args):
    if args.action == "set":
        try:
            patch = json.loads(os.environ.get("YTDL_CONFIG_PATCH", "{}"))
            apply_patch(patch)
        except (ValueError, OSError) as e:
            fail(str(e))
    out({"ok": True, "settings": settings_view()})


def main():
    ap = argparse.ArgumentParser(prog="ytdl")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("info"); p.add_argument("url"); p.add_argument("--timeout", type=int, default=45)
    p.set_defaults(fn=cmd_info)
    p = sub.add_parser("start"); p.add_argument("url")
    p.add_argument("--preset"); p.add_argument("--title"); p.add_argument("--thumb")
    p.add_argument("--dir"); p.add_argument("--playlist", action="store_true"); p.add_argument("--subs", action="store_true")
    p.add_argument("--tag"); p.add_argument("--name"); p.add_argument("--referer"); p.add_argument("--resolve"); p.add_argument("--scale", type=int); p.add_argument("--kind")
    p.set_defaults(fn=cmd_start)
    sub.add_parser("list").set_defaults(fn=cmd_list)
    p = sub.add_parser("watch"); p.add_argument("--interval", type=float, default=0.5); p.set_defaults(fn=cmd_watch)
    for name, fn in (("cancel", cmd_cancel), ("remove", cmd_remove), ("work", cmd_work)):
        p = sub.add_parser(name); p.add_argument("id"); p.set_defaults(fn=fn)
    sub.add_parser("clear").set_defaults(fn=cmd_clear)
    p = sub.add_parser("config"); p.add_argument("action", choices=["show", "set"]); p.set_defaults(fn=cmd_config)
    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
