//! Downloading a movie or episode instead of streaming it. Replaces the shell's
//! `scripts/stremio/download.py`.
//!
//! Two ways to get a file into the library:
//!  * the direct (HLS) stream, queued in the shell's Downloads app (`MEDIATOR_YTDL` names its
//!    command, e.g. `python3 .../ytdl.py`); the signed link is only resolved once the job has a slot;
//!  * a torrent, added to qBittorrent through its web API (bound to localhost without a login).
//!
//! Every command prints one JSON value; a failure is `{"error": "..."}`.
use crate::browse;
use crate::config::{self, Config};
use crate::fileio;
use crate::http::{HttpError, Request};
use serde_json::{json, Map, Value};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::Duration;

const HLS_PREFIX: &str = "stremio-hls:";
type Res = Result<Value, String>;

fn state_path() -> PathBuf {
    config::state_dir().join("stremio-downloads.json")
}

fn text(v: &Value) -> String {
    match v {
        Value::Null => String::new(),
        Value::String(s) => s.clone(),
        other => other.to_string(),
    }
}

trait IfEmpty {
    fn if_empty(self, d: &str) -> String;
}
impl IfEmpty for String {
    fn if_empty(self, d: &str) -> String {
        if self.is_empty() { d.to_string() } else { self }
    }
}

fn clean(name: &str) -> String {
    let c = crate::parse::rx(r#"[<>:"/\\|?*]+"#).replace_all(name, " ").into_owned();
    let c = c.trim().trim_matches(|ch| ch == ' ' || ch == '.').to_string();
    c.if_empty("Untitled")
}

fn is_year(s: &str) -> bool {
    s.len() == 4 && s.bytes().all(|b| b.is_ascii_digit())
}

fn library_root(cfg: &Config, movie: bool) -> PathBuf {
    let key = if movie { "movies" } else { "shows" };
    match cfg.libraries.get(key).filter(|v| !v.is_empty()) {
        Some(p) => config::expand_user(p),
        None => config::home().join("Videos").join(if movie { "Movies" } else { "Shows" }),
    }
}

fn save_dir(cfg: &Config, a: &Value) -> PathBuf {
    if a["type"] == "movie" {
        return library_root(cfg, true);
    }
    let title = clean(&text(&a["title"]).if_empty("Series"));
    let year: String = text(&a["year"]).chars().take(4).collect();
    let show = if is_year(&year) { format!("{title} ({year})") } else { title };
    let season = a["season"].as_i64().unwrap_or(0);
    let root = library_root(cfg, false).join(show);
    if season != 0 { root.join(format!("Season {season}")) } else { root }
}

// ---- qBittorrent's web API ----

enum Qb {
    Down,
    Denied,
}

fn qb_base() -> String {
    if let Ok(v) = std::env::var("QB_URL") {
        if !v.is_empty() {
            return v.trim_end_matches('/').to_string();
        }
    }
    let conf = std::env::var("XDG_CONFIG_HOME").ok().filter(|v| !v.is_empty()).map(PathBuf::from).unwrap_or_else(|| config::home().join(".config"))
        .join("qBittorrent").join("qBittorrent.conf");
    let mut port = 8080;
    if let Ok(t) = std::fs::read_to_string(conf) {
        // Newer versions keep it as "Port=" under [WebUI], older ones as "WebUI\Port=" in [Preferences]
        let section = crate::parse::rx(r"(?ms)^\[WebUI\]\s*$(.*?)(?:^\[|\z)").captures(t.as_str()).ok().flatten().map(|c| c[1].to_string());
        let found = section.and_then(|s| crate::parse::rx(r"(?m)^Port=(\d+)").captures(s.as_str()).ok().flatten().map(|c| c[1].to_string()))
            .or_else(|| crate::parse::rx(r"(?m)^WebUI\\Port=(\d+)").captures(t.as_str()).ok().flatten().map(|c| c[1].to_string()));
        if let Some(p) = found.and_then(|p| p.parse().ok()) {
            port = p;
        }
    }
    format!("http://127.0.0.1:{port}")
}

fn qb_call(path: &str, form: Option<&[(&str, String)]>, raw: Option<(&[u8], &str)>) -> Result<String, Qb> {
    let base = qb_base();
    let url = format!("{base}/api/v2/{path}");
    let referer = format!("{base}/");
    let encoded;
    let mut req = Request::get(&url).header("Referer", &referer).header("Origin", &base).timeout(6.0);
    if let Some((body, ctype)) = raw {
        req = req.header("Content-Type", ctype).post(body);
    } else if let Some(f) = form {
        encoded = crate::posters::q(&f.iter().map(|(k, v)| (*k, v.clone())).collect::<Vec<_>>());
        req = req.header("Content-Type", "application/x-www-form-urlencoded").post(encoded.as_bytes());
    }
    match req.send() {
        Ok(b) => Ok(String::from_utf8_lossy(&b).into_owned()),
        Err(HttpError::Status(401)) | Err(HttpError::Status(403)) => Err(Qb::Denied),
        Err(_) => Err(Qb::Down),
    }
}

fn qb_json(path: &str) -> Result<Value, Qb> {
    Ok(serde_json::from_str(&qb_call(path, None, None)?).unwrap_or(Value::Null))
}

fn multipart(fields: &[(&str, String)]) -> (Vec<u8>, String) {
    let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
    let boundary = format!("{:032x}", nanos ^ std::process::id() as u128);
    let mut body = vec![];
    for (k, v) in fields {
        body.extend(format!("--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n").as_bytes());
    }
    body.extend(format!("--{boundary}--\r\n").as_bytes());
    (body, format!("multipart/form-data; boundary={boundary}"))
}

const DENIED: &str = "qBittorrent refused the connection: check its Web UI login settings";

fn ensure_running() -> Result<(), String> {
    match qb_call("app/version", None, None) {
        Ok(_) => return Ok(()),
        Err(Qb::Denied) => return Err(DENIED.into()),
        Err(Qb::Down) => {}
    }
    let exe = crate::notify::which("qbittorrent-nox").ok_or("qbittorrent-nox is not installed")?;
    spawn_detached(Command::new(exe)).map_err(|e| e.to_string())?;
    for _ in 0..40 {
        std::thread::sleep(Duration::from_millis(500));
        match qb_call("app/version", None, None) {
            Ok(_) => return Ok(()),
            Err(Qb::Denied) => return Err(DENIED.into()),
            Err(Qb::Down) => {}
        }
    }
    Err("qBittorrent did not start".into())
}

fn spawn_detached(mut c: Command) -> std::io::Result<()> {
    use std::os::unix::process::CommandExt;
    c.stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
    unsafe {
        c.pre_exec(|| {
            libc::setsid();
            Ok(())
        });
    }
    c.spawn().map(|_| ())
}

fn magnet(hash: &str, name: &str, sources: &Value) -> String {
    // urllib.parse.quote: letters, digits and "_.-~" stay; the name also keeps "/", the tracker does not
    const KEEP: &percent_encoding::AsciiSet = &percent_encoding::NON_ALPHANUMERIC.remove(b'_').remove(b'.').remove(b'-').remove(b'~');
    let enc = |s: &str| percent_encoding::utf8_percent_encode(s, KEEP).to_string();
    const KEEP_SLASH: &percent_encoding::AsciiSet = &KEEP.remove(b'/');
    let enc_name = |s: &str| percent_encoding::utf8_percent_encode(s, KEEP_SLASH).to_string();
    let mut url = format!("magnet:?xt=urn:btih:{hash}&dn={}", enc_name(if name.is_empty() { hash } else { name }));
    for s in sources.as_array().cloned().unwrap_or_default() {
        if let Some(t) = s.as_str().and_then(|s| s.strip_prefix("tracker:")) {
            url += &format!("&tr={}", enc(t));
        }
    }
    url
}

pub fn add(cfg: &Config, a: &Value) -> Res {
    ensure_running()?;
    let hash = text(&a["infoHash"]).to_lowercase();
    if hash.is_empty() {
        return Err("no torrent hash".into());
    }
    let dest = save_dir(cfg, a);
    let pick = a["fileIdx"].as_i64().unwrap_or(-1);
    let mut fields = vec![("urls", magnet(&hash, &text(&a["name"]), &a["sources"])), ("savepath", dest.to_string_lossy().into_owned())];
    if pick >= 0 {
        // Stop once the metadata is in, to learn whether it is a pack and keep only the wanted
        // file. A torrent added stopped never fetches the metadata, so it would sit there forever.
        fields.push(("stopCondition", "MetadataReceived".into()));
    }
    let (body, ctype) = multipart(&fields);
    qb_call("torrents/add", None, Some((&body, &ctype))).map_err(|e| match e {
        Qb::Denied => DENIED.to_string(),
        Qb::Down => "qBittorrent is not reachable".to_string(),
    })?;
    let key = format!("{}|{}", text(&a["showId"]), text(&a["episodeId"]));
    let entry = json!({"hash": hash, "path": dest.to_string_lossy(), "title": text(&a["title"]), "fileIdx": pick, "added": crate::state::now()});
    fileio::update_json(&state_path(), |d| {
        d.insert(key.clone(), entry.clone());
    }).map_err(|e| e.to_string())?;
    if pick >= 0 {
        if let Ok(exe) = std::env::current_exe() {
            let mut c = Command::new(exe);
            c.args(["download", "finalize", &hash, &pick.to_string()]);
            let _ = spawn_detached(c);
        }
    }
    Ok(json!({"ok": true, "hash": hash, "path": dest.to_string_lossy()}))
}

/// Once the metadata is in: a pack keeps only the wanted file, then the torrent starts.
pub fn finalize(hash: &str, pick: i64) {
    let mut files = Value::Null;
    for _ in 0..120 {
        // magnets can take a while to fetch metadata
        if let Ok(v) = qb_json(&format!("torrents/files?hash={hash}")) {
            if v.as_array().map(|a| !a.is_empty()).unwrap_or(false) {
                files = v;
                break;
            }
        }
        std::thread::sleep(Duration::from_secs(2));
    }
    let list = files.as_array().cloned().unwrap_or_default();
    if list.len() > 1 {
        let others: Vec<String> = list.iter().enumerate().filter(|(i, _)| *i as i64 != pick)
            .map(|(i, f)| f["index"].as_i64().map(|n| n.to_string()).unwrap_or_else(|| i.to_string())).collect();
        if !others.is_empty() {
            let _ = qb_call("torrents/filePrio", Some(&[("hash", hash.to_string()), ("id", others.join("|")), ("priority", "0".into())]), None);
        }
    }
    for action in ["start", "resume"] {
        // qBittorrent 5 renamed resume to start
        if qb_call(&format!("torrents/{action}"), Some(&[("hashes", hash.to_string())]), None).is_ok() {
            break;
        }
    }
}

// ---- direct streams, through the Downloads app ----

fn ytdl(args: &[String]) -> Value {
    let raw = std::env::var("MEDIATOR_YTDL").unwrap_or_default();
    let base = shlex::split(&raw).unwrap_or_default();
    if base.is_empty() {
        return json!({"ok": false, "error": "the Downloads app is not configured (MEDIATOR_YTDL)"});
    }
    let out = Command::new(&base[0]).args(&base[1..]).args(args).stdin(Stdio::null()).stderr(Stdio::null()).output();
    out.ok().and_then(|o| String::from_utf8_lossy(&o.stdout).lines().last().and_then(|l| serde_json::from_str(l).ok())).unwrap_or(json!({"ok": false}))
}

fn hls_jobs() -> Vec<Value> {
    ytdl(&["list".into()])["jobs"].as_array().cloned().unwrap_or_default().into_iter()
        .filter(|j| text(&j["tag"]).starts_with(HLS_PREFIX)).collect()
}

fn hls_stem(a: &Value) -> String {
    if a["type"] == "movie" {
        let year: String = text(&a["year"]).chars().take(4).collect();
        let title = clean(&text(&a["title"]).if_empty("Movie"));
        return if is_year(&year) { format!("{title} ({year})") } else { title };
    }
    let ep = text(&a["episodeId"]);
    let parts: Vec<&str> = ep.split(':').collect();
    let (season, episode) = if parts.len() == 3 {
        (parts[1].parse::<i64>().unwrap_or(0), parts[2].parse::<i64>().unwrap_or(0))
    } else {
        (a["season"].as_i64().unwrap_or(0), 0)
    };
    format!("{} S{season:02}E{episode:02}", clean(&text(&a["title"]).if_empty("Series")))
}

pub fn hls(cfg: &Config, a: &Value) -> Res {
    if !cfg.streaming.hls {
        return Err("direct streams are turned off in the Mediator settings".into());
    }
    let tag = format!("{HLS_PREFIX}{}|{}", text(&a["showId"]), text(&a["episodeId"]));
    let dest = save_dir(cfg, a);
    if hls_jobs().iter().any(|j| j["tag"] == tag.as_str() && ["queued", "running", "processing"].contains(&text(&j["status"]).as_str())) {
        return Ok(json!({"ok": true, "path": dest.to_string_lossy(), "result": "active"}));
    }
    let stem = hls_stem(a);
    if [".mkv", ".mp4"].iter().any(|ext| dest.join(format!("{stem}{ext}")).is_file()) {
        return Ok(json!({"ok": true, "path": dest.to_string_lossy(), "result": "have"}));
    }
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let resolve = json!([exe.to_string_lossy(), "stream-resolve", text(&a["showId"]), text(&a["episodeId"])]);
    let label = if a["type"] == "movie" { "Movie".to_string() } else { stem.rsplit(' ').next().unwrap_or("").to_string() };
    let res = ytdl(&["start".into(), tag.clone(), "--preset".into(), "best".into(), "--dir".into(), dest.to_string_lossy().into_owned(),
        "--name".into(), stem, "--tag".into(), tag, "--title".into(), format!("{} · {label}", text(&a["title"])), "--resolve".into(), resolve.to_string()]);
    if res["ok"] != true {
        return Err(res["error"].as_str().unwrap_or("the Downloads app refused the job").to_string());
    }
    Ok(json!({"ok": true, "path": dest.to_string_lossy(), "result": "started", "direct": true}))
}

fn hls_status() -> Map<String, Value> {
    let mut out = Map::new();
    let mut jobs = hls_jobs();
    jobs.sort_by(|a, b| a["created"].as_f64().unwrap_or(0.0).partial_cmp(&b["created"].as_f64().unwrap_or(0.0)).unwrap_or(std::cmp::Ordering::Equal));
    for j in jobs {
        let key = text(&j["tag"])[HLS_PREFIX.len()..].to_string();
        let state = match text(&j["status"]).as_str() {
            "queued" => "queuedDL",
            "running" | "processing" => "downloading",
            "done" => "done",
            _ => {
                out.remove(&key); // cancelled or failed: shown as not downloaded, so it can be retried
                continue;
            }
        };
        let done = state == "done";
        out.insert(key, json!({"progress": if done { 1.0 } else { j["percent"].as_f64().unwrap_or(0.0) / 100.0 }, "state": state, "speed": 0, "path": text(&j["dir"])}));
    }
    out
}

fn torrent_status() -> Map<String, Value> {
    let state = match fileio::read_json(&state_path()) {
        Value::Object(m) => m,
        _ => Map::new(),
    };
    let mut out = Map::new();
    if state.is_empty() {
        return out;
    }
    let mut hashes: Vec<String> = state.values().map(|v| text(&v["hash"])).collect();
    hashes.sort();
    hashes.dedup();
    let Ok(info) = qb_json(&format!("torrents/info?hashes={}", hashes.join("|"))) else { return out };
    let by_hash: std::collections::HashMap<String, Value> = info.as_array().cloned().unwrap_or_default().into_iter().map(|t| (text(&t["hash"]).to_lowercase(), t)).collect();
    for (key, v) in &state {
        if let Some(t) = by_hash.get(&text(&v["hash"])) {
            out.insert(key.clone(), json!({"progress": t["progress"].as_f64().unwrap_or(0.0), "state": text(&t["state"]), "speed": t["dlspeed"].as_i64().unwrap_or(0), "path": v["path"]}));
        }
    }
    out
}

pub fn status() -> Res {
    let mut out = hls_status();
    out.extend(torrent_status());
    Ok(Value::Object(out))
}

// ---- choosing what to download ----

fn direct_available(a: &Value) -> bool {
    let Ok(exe) = std::env::current_exe() else { return false };
    let probe = Command::new(exe).args(["stream-resolve", &text(&a["showId"]), &text(&a["episodeId"])]).stdin(Stdio::null()).stderr(Stdio::null()).output();
    probe.ok().and_then(|o| String::from_utf8_lossy(&o.stdout).lines().last().and_then(|l| serde_json::from_str::<Value>(l).ok())).map(|v| v["ok"] == true).unwrap_or(false)
}

pub fn auto(cfg: &Config, a: &Value) -> Res {
    let (use_hls, use_torrent, prefer_torrent) = (cfg.streaming.hls, cfg.streaming.stremio, cfg.streaming.prefer_stremio);
    let mut a = a.clone();
    for k in ["showId", "episodeId"] {
        if a[k].is_null() {
            a[k] = json!("");
        }
    }
    if use_hls && !(prefer_torrent && use_torrent) {
        if direct_available(&a) {
            return hls(cfg, &a);
        }
        if !use_torrent {
            return Err("no direct stream found for this one, and Stremio torrents are turned off".into());
        }
    }
    if !use_torrent {
        return Err("Stremio torrents are turned off in the Mediator settings".into());
    }
    let streams = browse::streams(&text(&a["type"]), &text(&a["videoId"]))?;
    let streams = streams.as_array().cloned().unwrap_or_default();
    if streams.is_empty() {
        if use_hls && prefer_torrent && direct_available(&a) {
            return hls(cfg, &a);
        }
        return Err("no streams found".into());
    }
    // Prefer a healthy 1080p, then anything else by seeders
    let with_hash: Vec<&Value> = streams.iter().filter(|s| !text(&s["infoHash"]).is_empty()).collect();
    let mut healthy: Vec<&Value> = with_hash.iter().copied().filter(|s| s["seeds"].as_i64().unwrap_or(0) >= 3).collect();
    if healthy.is_empty() {
        healthy = with_hash;
    }
    if healthy.is_empty() {
        if use_hls && prefer_torrent && direct_available(&a) {
            return hls(cfg, &a);
        }
        return Err("only direct streams were found, which cannot be downloaded here".into());
    }
    let rank = |q: &str| -> i32 {
        if prefer_torrent {
            match q { "2160p" | "4k" => 0, "1080p" => 1, "720p" => 2, _ => 3 }
        } else {
            match q { "1080p" => 0, "720p" => 1, "2160p" | "4k" => 2, _ => 3 }
        }
    };
    healthy.sort_by_key(|s| (rank(&text(&s["quality"])), -s["seeds"].as_i64().unwrap_or(0)));
    let best = healthy[0];
    let name = text(&best["filename"]).if_empty(&text(&a["title"]));
    a["infoHash"] = best["infoHash"].clone();
    a["fileIdx"] = best["fileIdx"].clone();
    a["sources"] = best["sources"].clone();
    a["name"] = json!(name);
    let mut res = add(cfg, &a)?;
    res["picked"] = json!({"quality": best["quality"], "seeds": best["seeds"], "name": name});
    Ok(res)
}

/// "1-13" | "1,3,5" | "1-3,8" -> sorted unique episode numbers.
fn parse_episode_spec(spec: &str) -> Result<Vec<i64>, String> {
    let mut out = std::collections::BTreeSet::new();
    for part in spec.split(',') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }
        let (lo, hi) = match part.split_once('-') {
            Some((l, h)) => (l, Some(h)),
            None => (part, None),
        };
        let bad = || format!("bad episode range {part:?}");
        let lo_n: i64 = lo.parse().map_err(|_| bad())?;
        let hi_n: i64 = match hi {
            Some(h) => h.parse().map_err(|_| bad())?,
            None => lo_n,
        };
        if lo_n > hi_n {
            return Err(bad());
        }
        out.extend(lo_n..=hi_n);
    }
    if out.is_empty() {
        return Err("no episodes given".into());
    }
    Ok(out.into_iter().collect())
}

/// Queue a whole season (or a range) as lazy jobs. Signed links expire within hours, so each job
/// resolves its own link when it gets a download slot; nothing is resolved up front here.
pub fn batch(cfg: &Config, a: &Value) -> Res {
    let show = text(&a["showId"]);
    let mut ids: Vec<String> = a["episodeIds"].as_array().map(|l| l.iter().map(text).collect()).unwrap_or_default();
    if ids.is_empty() && !text(&a["spec"]).is_empty() {
        let imdb = show.rsplit(':').next().unwrap_or("");
        let season = a["season"].as_i64().unwrap_or(0);
        ids = parse_episode_spec(&text(&a["spec"]))?.into_iter().map(|n| format!("{imdb}:{season}:{n}")).collect();
    }
    if ids.is_empty() {
        return Err("no episodes to download".into());
    }
    let (mut started, mut have, mut active, mut failed) = (0, 0, 0, 0);
    let mut failures = vec![];
    for eid in &ids {
        // serial: torrent adds share one state file
        let parts: Vec<&str> = eid.split(':').collect();
        let res = if parts.len() != 3 {
            Err("bad episode id".to_string())
        } else {
            let mut one = a.clone();
            one["episodeId"] = json!(eid);
            one["videoId"] = json!(eid);
            one["season"] = json!(parts[1].parse::<i64>().unwrap_or(0));
            auto(cfg, &one)
        };
        match res {
            Ok(v) if v["ok"] == true => match v["result"].as_str() {
                Some("have") => have += 1,
                Some("active") => active += 1,
                _ => started += 1,
            },
            Ok(_) => {
                failed += 1;
                failures.push(json!({"episodeId": eid, "error": "not queued"}));
            }
            Err(e) => {
                failed += 1;
                failures.push(json!({"episodeId": eid, "error": e}));
            }
        }
    }
    Ok(json!({"ok": failed < ids.len(), "total": ids.len(), "started": started, "have": have, "active": active, "failed": failed, "failures": failures}))
}

// ---- anime episodes and seasons, through the Downloads app ----

const ACTIVE: [&str; 3] = ["queued", "running", "processing"];
const AHEAD: usize = 2; // episodes the feeder keeps started: the downloader runs max_parallel, one more waits
const VIDEO_EXTS: [&str; 3] = [".mkv", ".mp4", ".webm"];

fn anime_root(cfg: &Config) -> PathBuf {
    if let Ok(v) = std::env::var("ANIME_DOWNLOAD_ROOT") {
        if !v.is_empty() {
            return PathBuf::from(v);
        }
    }
    match cfg.libraries.get("anime").filter(|v| !v.is_empty()) {
        Some(p) => config::expand_user(p),
        None => config::home().join("Videos").join("Anime"),
    }
}

fn clean_anime(name: &str) -> String {
    let c = crate::parse::rx(r#"[<>:"/\\|?*\x00-\x1f]+"#).replace_all(name, " ").into_owned();
    c.trim().trim_matches(|ch| ch == ' ' || ch == '.').to_string().if_empty("Untitled")
}

fn anime_stem(title: &str, number: &str, pad: usize) -> String {
    let number = number.trim();
    let (digits, frac) = match number.split_once('.') {
        Some((d, f)) => (d, Some(f)),
        None => (number, None),
    };
    let label = format!("{digits:0>pad$}{}", frac.map(|f| format!(".{f}")).unwrap_or_default());
    format!("{} - {label}", clean_anime(title))
}

fn have_file(folder: &std::path::Path, stem: &str) -> bool {
    VIDEO_EXTS.iter().any(|ext| folder.join(format!("{stem}{ext}")).is_file())
}

fn anime_tag(show: &str, episode: &str) -> String {
    format!("anime:{show}|{episode}")
}

fn anime_jobs(show: Option<&str>) -> Vec<Value> {
    let prefix = match show { Some(s) => format!("anime:{s}|"), None => "anime:".to_string() };
    ytdl(&["list".into()])["jobs"].as_array().cloned().unwrap_or_default().into_iter().filter(|j| text(&j["tag"]).starts_with(&prefix)).collect()
}

fn batches_dir() -> PathBuf {
    config::state_dir().join("anime-batches")
}

fn batch_file(show: &str) -> PathBuf {
    let safe = crate::parse::rx(r"[^A-Za-z0-9._-]+").replace_all(show, "_").into_owned();
    batches_dir().join(format!("{safe}.json"))
}

fn start_one(cfg: &Config, req: &Value, ep: &Value) -> &'static str {
    let (show, title) = (text(&req["show"]), text(&req["title"]));
    let folder = anime_root(cfg).join(clean_anime(&title));
    let pad = req["pad"].as_u64().filter(|p| *p > 0).unwrap_or(2) as usize;
    let stem = anime_stem(&title, &text(&ep["number"]), pad);
    if have_file(&folder, &stem) {
        return "have";
    }
    let tag = anime_tag(&show, &text(&ep["id"]));
    if anime_jobs(Some(&show)).iter().any(|j| j["tag"] == tag.as_str() && ACTIVE.contains(&text(&j["status"]).as_str())) {
        return "active"; // already on its way; a second job would write the same file
    }
    let Ok(exe) = std::env::current_exe() else { return "error" };
    let quality = text(&req["quality"]).if_empty("best");
    let mut resolve = vec![exe.to_string_lossy().into_owned(), "stream-resolve".into(), show.clone(), text(&ep["id"]), "-q".into(), quality];
    if req["dub"] == true {
        resolve.push("--dub".into());
    }
    let mut args: Vec<String> = vec!["start".into(), tag.clone(), "--preset".into(), "best".into(), "--dir".into(), folder.to_string_lossy().into_owned(),
        "--name".into(), stem, "--tag".into(), tag, "--title".into(), format!("{title} · Episode {}", text(&ep["number"])), "--resolve".into(), json!(resolve).to_string()];
    let height = req["height"].as_i64().unwrap_or(0);
    if [360, 480, 720].contains(&height) {
        args.extend(["--scale".into(), height.to_string()]);
    }
    if ytdl(&args)["ok"] == true { "started" } else { "error" }
}

fn anime_load(raw: &str) -> Result<Value, String> {
    let req: Value = serde_json::from_str(raw).map_err(|e| format!("bad JSON: {e}"))?;
    if text(&req["show"]).is_empty() || text(&req["title"]).is_empty() || req["episodes"].as_array().map(|a| a.is_empty()).unwrap_or(true) {
        return Err("show, title and episodes are required".into());
    }
    Ok(req)
}

pub fn anime_episode(cfg: &Config, raw: &str) -> Res {
    let req = anime_load(raw)?;
    Ok(json!({"ok": true, "result": start_one(cfg, &req, &req["episodes"][0])}))
}

pub fn anime_season(raw: &str) -> Res {
    let req = anime_load(raw)?;
    let path = batch_file(&text(&req["show"]));
    fileio::atomic_write_text(&path, &req.to_string(), 0o644).map_err(|e| e.to_string())?;
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let mut c = Command::new(exe);
    c.args(["download", "anime-feed", &path.to_string_lossy()]);
    spawn_detached(c).map_err(|e| e.to_string())?;
    Ok(json!({"ok": true, "queued": req["episodes"].as_array().map(|a| a.len()).unwrap_or(0)}))
}

/// Detached: start the batch's episodes in order, never more than AHEAD unfinished at once.
pub fn anime_feed(cfg: &Config, path: &str) {
    let path = PathBuf::from(path);
    loop {
        let Some(mut req) = std::fs::read_to_string(&path).ok().and_then(|t| serde_json::from_str::<Value>(&t).ok()) else { return }; // cancelled: the batch file is gone
        let mut pending = req["episodes"].as_array().cloned().unwrap_or_default();
        if pending.is_empty() {
            let _ = std::fs::remove_file(&path);
            return;
        }
        if anime_jobs(Some(&text(&req["show"]))).iter().filter(|j| ACTIVE.contains(&text(&j["status"]).as_str())).count() >= AHEAD {
            std::thread::sleep(Duration::from_secs(3));
            continue;
        }
        let ep = pending.remove(0);
        start_one(cfg, &req, &ep);
        req["episodes"] = Value::Array(pending);
        if fileio::atomic_write_text(&path, &req.to_string(), 0o644).is_err() {
            return;
        }
    }
}

pub fn anime_status(cfg: &Config, arg: &str) -> Res {
    // Plain provider id, or the batch JSON so episodes already on disk can be marked done
    let req: Value = if arg.starts_with('{') { serde_json::from_str(arg).map_err(|e| format!("bad JSON: {e}"))? } else { json!({"show": arg}) };
    let show = text(&req["show"]);
    let mut states: Map<String, Value> = Map::new();
    let mut created: std::collections::HashMap<String, f64> = Default::default();
    for j in anime_jobs(Some(&show)) {
        let episode = text(&j["tag"]).split_once('|').map(|(_, e)| e.to_string()).unwrap_or_default();
        let state = match text(&j["status"]).as_str() {
            "queued" => "queued", "running" => "downloading", "processing" => "processing", "done" => "done", "error" => "error",
            _ => continue, // cancelled jobs are not shown
        };
        let made = j["created"].as_f64().unwrap_or(0.0);
        if created.get(&episode).map(|prev| *prev > made).unwrap_or(false) {
            continue;
        }
        created.insert(episode.clone(), made);
        states.insert(episode, json!({"state": state, "percent": j["percent"].as_f64().unwrap_or(0.0), "error": text(&j["error"]), "phase": text(&j["phase"]), "id": j["id"]}));
    }
    let mut pending: Vec<String> = vec![];
    if let Ok(rd) = std::fs::read_dir(batches_dir()) {
        for e in rd.flatten() {
            if let Some(b) = std::fs::read_to_string(e.path()).ok().and_then(|t| serde_json::from_str::<Value>(&t).ok()) {
                if text(&b["show"]) == show {
                    pending = b["episodes"].as_array().map(|a| a.iter().map(|e| text(&e["id"])).collect()).unwrap_or_default();
                }
            }
        }
    }
    let batch = !pending.is_empty();
    for episode in pending {
        states.entry(episode).or_insert_with(|| json!({"state": "queued", "percent": 0, "error": "", "id": ""}));
    }
    if !text(&req["title"]).is_empty() {
        let title = text(&req["title"]);
        let folder = anime_root(cfg).join(clean_anime(&title));
        let pad = req["pad"].as_u64().filter(|p| *p > 0).unwrap_or(2) as usize;
        for ep in req["episodes"].as_array().cloned().unwrap_or_default() {
            let id = text(&ep["id"]);
            let known_ok = states.get(&id).map(|k| k["state"] != "error").unwrap_or(false);
            if !known_ok && have_file(&folder, &anime_stem(&title, &text(&ep["number"]), pad)) {
                states.insert(id, json!({"state": "done", "percent": 100, "error": "", "id": ""}));
            }
        }
    }
    Ok(json!({"ok": true, "episodes": states, "batch": batch}))
}

pub fn anime_cancel(show: &str) -> Res {
    if let Ok(rd) = std::fs::read_dir(batches_dir()) {
        for e in rd.flatten() {
            if std::fs::read_to_string(e.path()).ok().and_then(|t| serde_json::from_str::<Value>(&t).ok()).map(|b| text(&b["show"]) == show).unwrap_or(false) {
                let _ = std::fs::remove_file(e.path());
            }
        }
    }
    let stopped: Vec<Value> = anime_jobs(Some(show)).into_iter().filter(|j| ACTIVE.contains(&text(&j["status"]).as_str())).collect();
    for j in &stopped {
        ytdl(&["cancel".into(), text(&j["id"])]);
    }
    std::thread::sleep(Duration::from_millis(1500)); // let yt-dlp exit before its partial files are removed
    for j in &stopped {
        let (folder, name) = (PathBuf::from(text(&j["dir"])), text(&j["name"]));
        if name.is_empty() || !folder.is_dir() {
            continue;
        }
        if let Ok(rd) = std::fs::read_dir(&folder) {
            for f in rd.flatten() {
                let fname = f.file_name().to_string_lossy().into_owned();
                if fname.starts_with(&format!("{name}.")) && (fname.ends_with(".part") || fname.ends_with(".ytdl") || fname.contains(".part-")) {
                    let _ = std::fs::remove_file(f.path());
                }
            }
        }
        let _ = std::fs::remove_dir(&folder); // only succeeds when the folder is empty
    }
    Ok(json!({"ok": true}))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn episode_specs() {
        assert_eq!(parse_episode_spec("1-3,8").unwrap(), vec![1, 2, 3, 8]);
        assert_eq!(parse_episode_spec("5").unwrap(), vec![5]);
        assert!(parse_episode_spec("3-1").is_err());
        assert!(parse_episode_spec("x").is_err());
        assert!(parse_episode_spec(" , ").is_err());
    }

    #[test]
    fn names_and_magnets() {
        assert_eq!(clean("A: B/C?"), "A  B C");
        assert_eq!(clean("..."), "Untitled");
        assert_eq!(hls_stem(&json!({"type": "series", "title": "Dark", "episodeId": "tt1:2:5"})), "Dark S02E05");
        assert_eq!(hls_stem(&json!({"type": "movie", "title": "Dune", "year": "2021–"})), "Dune (2021)");
        let m = magnet("abc", "My Show", &json!(["tracker:udp://x.org:80", "dht:abc"]));
        assert!(m.starts_with("magnet:?xt=urn:btih:abc&dn=My%20Show") && m.contains("&tr=udp%3A%2F%2Fx.org%3A80"), "{m}");
    }

    #[test]
    fn anime_file_names() {
        assert_eq!(anime_stem("Steins;Gate", "1", 2), "Steins;Gate - 01");
        assert_eq!(anime_stem("A: B", "12.5", 3), "A  B - 012.5");
        assert_eq!(anime_stem("One Piece", "1100", 2), "One Piece - 1100");
    }

    #[test]
    fn save_dir_layout() {
        let mut cfg = Config::default();
        cfg.libraries.insert("shows".into(), "/lib/shows".into());
        cfg.libraries.insert("movies".into(), "/lib/movies".into());
        assert_eq!(save_dir(&cfg, &json!({"type": "movie"})), PathBuf::from("/lib/movies"));
        assert_eq!(save_dir(&cfg, &json!({"type": "series", "title": "Dark", "year": "2017-2020", "season": 2})), PathBuf::from("/lib/shows/Dark (2017)/Season 2"));
    }
}
