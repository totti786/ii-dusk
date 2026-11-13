//! Stremio addon streams played as native episodes (port of `mediator/stremio.py`).
//! Show ids look like `stremio:series:tt0903747`; episode ids are the addon video ids
//! (`tt0903747:1:3`, or the bare imdb id for a movie).
use crate::config::Streaming;
use crate::errors::{describe_http, StreamError};
use crate::http::{HttpError, Request};
use crate::{fileio, native_progress, vaplayer};
use serde_json::{json, Map, Value};
use std::net::{SocketAddr, TcpStream};
use std::path::PathBuf;
use std::time::{Duration, Instant};

pub const PREFIX: &str = "stremio:";
pub const EPISODE_TTL: f64 = 12.0 * 3600.0;
pub const SERVER_BUNDLES: [(&str, &str); 2] = [
    ("/usr/share/stremio-service/stremio-runtime", "/usr/share/stremio-service/server.js"),
    ("/opt/stremio/node", "/opt/stremio/server.js"),
];

fn err(s: impl Into<String>) -> StreamError {
    StreamError(s.into())
}

#[derive(Clone)]
pub struct Endpoints {
    pub cinemeta: String,
    pub server: String,
    pub addons: Option<Vec<String>>, // None: read ~/.config/ii/stremio.json, else Torrentio
    pub vaplayer: vaplayer::Endpoints,
}

impl Default for Endpoints {
    fn default() -> Self {
        Endpoints { cinemeta: "https://v3-cinemeta.strem.io".into(), server: "http://127.0.0.1:11470".into(), addons: None, vaplayer: Default::default() }
    }
}

pub fn server_bundle() -> Option<(&'static str, &'static str)> {
    SERVER_BUNDLES.iter().copied().find(|(n, j)| std::path::Path::new(n).exists() && std::path::Path::new(j).exists())
}

pub fn is_show(show_id: &str) -> bool {
    show_id.starts_with(PREFIX)
}

/// ("movie" | "series", "tt…")
pub fn split_show(show_id: &str) -> Result<(String, String), StreamError> {
    let parts: Vec<&str> = show_id.splitn(3, ':').collect();
    let ok = parts.len() == 3 && (parts[1] == "movie" || parts[1] == "series")
        && parts[2].starts_with("tt") && parts[2].len() > 2 && parts[2][2..].bytes().all(|b| b.is_ascii_digit());
    if !ok {
        return Err(err(format!("bad Stremio show id: {show_id}")));
    }
    Ok((parts[1].into(), parts[2].into()))
}

pub fn episode_number(video: &Value) -> String {
    let n = |k: &str| video.get(k).and_then(|v| v.as_i64().or_else(|| v.as_f64().map(|f| f as i64))).filter(|&x| x != 0);
    format!("S{:02}E{:02}", n("season").unwrap_or(0), n("episode").or_else(|| n("number")).unwrap_or(0))
}

pub fn episode_cache_path(imdb: &str) -> PathBuf {
    crate::config::cache_dir().join("cinemeta").join(format!("{imdb}.json"))
}

fn cached_episodes(imdb: &str, max_age: Option<f64>) -> Option<Vec<Value>> {
    let path = episode_cache_path(imdb);
    if let Some(max) = max_age {
        let age = std::fs::metadata(&path).ok()?.modified().ok()?.elapsed().ok()?.as_secs_f64();
        if age > max {
            return None;
        }
    }
    let v: Value = serde_json::from_str(&std::fs::read_to_string(path).ok()?).ok()?;
    v.as_array().filter(|a| !a.is_empty()).cloned()
}

pub fn store_episodes(imdb: &str, eps: &[Value]) {
    let _ = fileio::atomic_write_text(&episode_cache_path(imdb), &serde_json::to_string(eps).unwrap(), 0o644);
}

pub fn episodes(ep: &Endpoints, show_id: &str) -> Result<Vec<Value>, StreamError> {
    let (kind, imdb) = split_show(show_id)?;
    if kind == "movie" {
        return Ok(vec![json!({"id": imdb, "number": "", "title": ""})]);
    }
    if let Some(fresh) = cached_episodes(&imdb, Some(EPISODE_TTL)) {
        return Ok(fresh);
    }
    let meta = match crate::http::get_json_retry(&format!("{}/meta/series/{imdb}.json", ep.cinemeta), 15.0, 3) {
        Ok(v) => v["meta"].clone(),
        Err(e) => {
            if let Some(stale) = cached_episodes(&imdb, None) {
                return Ok(stale);
            }
            let saved = native_progress::load();
            if saved["show_id"] == show_id {
                if let Some(a) = saved["episodes"].as_array().filter(|a| !a.is_empty()) {
                    return Ok(a.clone());
                }
            }
            return Err(err(format!("could not load the episode list from Cinemeta: {}", e.describe())));
        }
    };
    let mut videos: Vec<&Value> = meta["videos"].as_array().map(|a| a.iter().collect()).unwrap_or_default();
    let key = |v: &Value, k: &str| v[k].as_i64().unwrap_or(0);
    videos.sort_by_key(|v| (key(v, "season"), key(v, "episode")));
    let out: Vec<Value> = videos.into_iter()
        .filter(|v| key(v, "season") != 0 && v["id"].as_str().map(|s| !s.is_empty()).unwrap_or(false))
        .map(|v| {
            let title = ["title", "name"].iter().filter_map(|k| v[*k].as_str()).find(|s| !s.is_empty()).unwrap_or("");
            json!({"id": v["id"], "number": episode_number(v), "title": title})
        }).collect();
    if out.is_empty() {
        return Err(err("no episodes found"));
    }
    store_episodes(&imdb, &out);
    Ok(out)
}

// ---- remembered stream choice ----

pub fn store_path() -> PathBuf {
    native_progress::state_dir().join("stremio-streams.json")
}

fn load_store() -> Map<String, Value> {
    match fileio::read_json(&store_path()) {
        Value::Object(m) => m,
        _ => Map::new(),
    }
}

pub fn remember(show_id: &str, episode_id: &str, stream: &Value) -> std::io::Result<()> {
    let mut keep = Map::new();
    for k in ["infoHash", "fileIdx", "url", "quality", "bingeGroup", "filename", "chosen"] {
        keep.insert(k.into(), stream.get(k).cloned().unwrap_or(Value::Null));
    }
    keep.insert("at".into(), json!(crate::state::now() as i64));
    let keep = Value::Object(keep);
    fileio::update_json(&store_path(), |d| {
        d.insert(format!("{show_id}|{episode_id}"), keep.clone());
        d.insert(format!("{show_id}|last"), keep.clone());
    })?;
    Ok(())
}

pub fn recall(show_id: &str, episode_id: &str) -> Option<Value> {
    load_store().remove(&format!("{show_id}|{episode_id}"))
}

// ---- streams ----

/// Stream addon base URLs: `streamAddons` in ~/.config/ii/stremio.json, else Torrentio.
pub fn addons(ep: &Endpoints) -> Vec<String> {
    if let Some(a) = &ep.addons {
        return a.clone();
    }
    let path = crate::config::expand_user("~/.config/ii/stremio.json");
    if let Ok(t) = std::fs::read_to_string(path) {
        if let Ok(v) = serde_json::from_str::<Value>(&t) {
            if let Some(a) = v["streamAddons"].as_array().filter(|a| !a.is_empty()) {
                return a.iter().map(|x| x.as_str().map(String::from).unwrap_or_else(|| x.to_string()).trim_end_matches('/').to_string()).collect();
            }
        }
    }
    vec!["https://torrentio.strem.fun".into()]
}

fn host_of(url: &str) -> String {
    url.split("://").nth(1).unwrap_or(url).split('/').next().unwrap_or(url).to_string()
}

fn quote(s: &str) -> String {
    s.bytes().map(|b| if b.is_ascii_alphanumeric() || b"_.-~/".contains(&b) { (b as char).to_string() } else { format!("%{b:02X}") }).collect()
}

pub fn list_streams(ep: &Endpoints, show_id: &str, episode_id: &str) -> Result<Vec<Value>, StreamError> {
    let (kind, _) = split_show(show_id)?;
    let mut out: Vec<Value> = vec![];
    let mut failed = vec![];
    let all = addons(ep);
    let seeds_re = crate::parse::rx(r"👤\s*(\d+)");
    let quality_re = crate::parse::rx(r"(?i)\b(2160p|4k|1080p|720p|480p)\b");
    for base in &all {
        let url = format!("{base}/stream/{kind}/{}.json", quote(episode_id));
        let data = match crate::http::get_json_retry(&url, 25.0, 3) {
            Ok(d) => d,
            Err(e) => {
                failed.push(format!("{} {}", host_of(base), e.describe()));
                continue;
            }
        };
        for s in data["streams"].as_array().cloned().unwrap_or_default() {
            let hash = s["infoHash"].as_str().unwrap_or("");
            let surl = s["url"].as_str().unwrap_or("");
            if hash.is_empty() && surl.is_empty() {
                continue;
            }
            let title = s["title"].as_str().unwrap_or("");
            let text = format!("{} {}", s["name"].as_str().unwrap_or(""), title);
            let seeds: i64 = seeds_re.captures(title).ok().flatten().and_then(|c| c[1].parse().ok()).unwrap_or(0);
            let quality = quality_re.captures(text.as_str()).ok().flatten().map(|c| c[1].to_lowercase()).unwrap_or_default();
            let hints = &s["behaviorHints"];
            out.push(json!({
                "infoHash": hash, "fileIdx": s["fileIdx"].as_i64().unwrap_or(-1), "url": surl,
                "quality": quality, "seeds": seeds,
                "bingeGroup": hints["bingeGroup"].as_str().unwrap_or(""), "filename": hints["filename"].as_str().unwrap_or(""),
            }));
        }
    }
    out.sort_by_key(|s| std::cmp::Reverse(s["seeds"].as_i64().unwrap_or(0)));
    if out.is_empty() && !failed.is_empty() && failed.len() == all.len() {
        return Err(err(failed.join("; ")));
    }
    Ok(out)
}

fn quality_rank(q: &str) -> i32 {
    match q { "2160p" | "4k" => 0, "1080p" => 1, "720p" => 2, "480p" => 3, _ => 4 }
}

/// Pick a stream for an episode nobody chose: the same release group as last time.
pub fn auto_pick(ep: &Endpoints, show_id: &str, episode_id: &str, best_quality: bool) -> Result<Value, StreamError> {
    let streams = list_streams(ep, show_id, episode_id)?;
    if streams.is_empty() {
        return Err(err("the stream addons answered but listed nothing for this episode"));
    }
    pick_from(streams, &load_store().remove(&format!("{show_id}|last")).unwrap_or(Value::Null), best_quality)
}

pub fn pick_from(streams: Vec<Value>, last: &Value, best_quality: bool) -> Result<Value, StreamError> {
    let s = |v: &Value, k: &str| v[k].as_str().unwrap_or("").to_string();
    if let Some(bg) = last["bingeGroup"].as_str().filter(|b| !b.is_empty()) {
        if let Some(x) = streams.iter().find(|x| s(x, "bingeGroup") == bg) {
            return Ok(x.clone());
        }
    }
    if best_quality {
        let healthy: Vec<&Value> = streams.iter().filter(|x| !s(x, "infoHash").is_empty() && x["seeds"].as_i64().unwrap_or(0) >= 3).collect();
        let pool: Vec<&Value> = if healthy.is_empty() { streams.iter().collect() } else { healthy };
        return Ok((*pool.iter().min_by_key(|x| (quality_rank(&s(x, "quality")), -x["seeds"].as_i64().unwrap_or(0))).unwrap()).clone());
    }
    if let Some(q) = last["quality"].as_str().filter(|q| !q.is_empty()) {
        if let Some(x) = streams.iter().find(|x| s(x, "quality") == q) {
            return Ok(x.clone());
        }
    }
    Ok(streams[0].clone())
}

// ---- server + URL ----

pub fn server_up() -> bool {
    TcpStream::connect_timeout(&SocketAddr::from(([127, 0, 0, 1], 11470)), Duration::from_millis(500)).is_ok()
}

fn pid_path() -> PathBuf {
    native_progress::state_dir().join("stremio-server.pid")
}

fn cmdline(pid: i64) -> Option<String> {
    let raw = std::fs::read(format!("/proc/{pid}/cmdline")).ok()?;
    Some(raw.split(|&b| b == 0).filter(|p| !p.is_empty()).map(|p| String::from_utf8_lossy(p).into_owned()).collect::<Vec<_>>().join(" "))
}

fn pid_alive(pid: i64) -> bool {
    std::fs::read(format!("/proc/{pid}/stat")).ok()
        .and_then(|b| { let t = String::from_utf8_lossy(&b).into_owned(); t.rsplit(')').next().map(|r| r.split_whitespace().next().unwrap_or("").to_string()) })
        .map(|state| state != "Z" && !state.is_empty()).unwrap_or(false)
}

fn is_server_pid(pid: i64) -> bool {
    cmdline(pid).map(|t| t.contains("server.js") && (t.contains("stremio-runtime") || t.contains("/opt/stremio"))).unwrap_or(false)
}

fn server_pids() -> Vec<i64> {
    let Ok(rd) = std::fs::read_dir("/proc") else { return vec![] };
    rd.flatten().filter_map(|e| e.file_name().to_str()?.parse::<i64>().ok()).filter(|&p| is_server_pid(p)).collect()
}

pub fn server_status() -> Value {
    let mut pids: Vec<i64> = vec![];
    let pid = std::fs::read_to_string(pid_path()).ok().and_then(|t| t.trim().parse::<i64>().ok()).unwrap_or(0);
    if pid != 0 {
        if is_server_pid(pid) {
            pids.push(pid);
        } else {
            let _ = std::fs::remove_file(pid_path());
        }
    }
    if pids.is_empty() {
        pids = server_pids();
    }
    pids.sort();
    pids.dedup();
    json!({"running": !pids.is_empty(), "pids": pids, "port": server_up()})
}

fn signal_pid(pid: i64, sig: i32) -> std::io::Result<()> {
    unsafe {
        let r = if libc::getpgid(pid as i32) == pid as i32 { libc::killpg(pid as i32, sig) } else { libc::kill(pid as i32, sig) };
        if r != 0 {
            let e = std::io::Error::last_os_error();
            if e.raw_os_error() != Some(libc::ESRCH) {
                return Err(e);
            }
        }
    }
    Ok(())
}

/// Stop the streaming server. Safe to call when it is not running.
pub fn stop_server() -> Value {
    let status = server_status();
    let pids: Vec<i64> = status["pids"].as_array().unwrap().iter().filter_map(|p| p.as_i64()).collect();
    if pids.is_empty() {
        return json!({"ok": true, "stopped": false, "pids": [], "port_open": status["port"], "message": "not running"});
    }
    for &pid in &pids {
        if signal_pid(pid, libc::SIGTERM).is_err() {
            return json!({"ok": false, "stopped": false, "pids": pids, "port_open": status["port"], "error": format!("not allowed to stop pid {pid}")});
        }
    }
    let deadline = Instant::now() + Duration::from_secs(5);
    while Instant::now() < deadline && pids.iter().any(|&p| pid_alive(p)) {
        std::thread::sleep(Duration::from_millis(100));
    }
    for &pid in &pids {
        if pid_alive(pid) {
            let _ = signal_pid(pid, libc::SIGKILL);
        }
    }
    let _ = std::fs::remove_file(pid_path());
    json!({"ok": true, "stopped": true, "pids": pids, "port_open": server_up()})
}

fn sessions_dir() -> PathBuf {
    native_progress::state_dir().join("stremio-sessions")
}

/// Mark this stream-play process as active so an idle stopper leaves the server up.
pub fn register_session() -> Option<PathBuf> {
    let path = sessions_dir().join(std::process::id().to_string());
    std::fs::create_dir_all(sessions_dir()).ok()?;
    std::fs::write(&path, crate::state::now().to_string()).ok()?;
    Some(path)
}

pub fn unregister_session(path: Option<&PathBuf>) {
    if let Some(p) = path {
        let _ = std::fs::remove_file(p);
    }
}

fn is_play_pid(pid: i64) -> bool {
    cmdline(pid).map(|t| (t.contains("stream-play") || t.contains("stream-resume")) && t.contains("mediator")).unwrap_or(false)
}

/// Pids of live stream-play processes; stale session files are removed.
pub fn active_sessions() -> Vec<i64> {
    let Ok(rd) = std::fs::read_dir(sessions_dir()) else { return vec![] };
    let mut live = vec![];
    for e in rd.flatten() {
        match e.file_name().to_str().and_then(|n| n.parse::<i64>().ok()) {
            Some(pid) if is_play_pid(pid) => live.push(pid),
            _ => {
                let _ = std::fs::remove_file(e.path());
            }
        }
    }
    live
}

/// Start a detached stopper that stops the server unless a play starts meanwhile.
pub fn schedule_stop(delay: f64) {
    let Ok(exe) = std::env::current_exe() else { return };
    use std::os::unix::process::CommandExt;
    let mut c = std::process::Command::new(exe);
    c.args(["stremio", "stop", "--if-idle", "--delay", &delay.to_string()])
        .stdin(std::process::Stdio::null()).stdout(std::process::Stdio::null()).stderr(std::process::Stdio::null());
    unsafe {
        c.pre_exec(|| {
            libc::setsid();
            Ok(())
        });
    }
    let _ = c.spawn();
}

pub fn ensure_server() -> Result<(), StreamError> {
    if server_up() {
        return Ok(());
    }
    let (node, js) = server_bundle().ok_or_else(|| err("the Stremio streaming server is not installed (install stremio-service-bin or stremio)"))?;
    use std::os::unix::process::CommandExt;
    let mut c = std::process::Command::new(node);
    c.arg(js).stdin(std::process::Stdio::null()).stdout(std::process::Stdio::null()).stderr(std::process::Stdio::null());
    unsafe {
        c.pre_exec(|| {
            libc::setsid();
            Ok(())
        });
    }
    let child = c.spawn().map_err(|e| err(format!("could not start the Stremio streaming server: {e}")))?;
    let _ = std::fs::create_dir_all(native_progress::state_dir());
    let _ = std::fs::write(pid_path(), child.id().to_string());
    for _ in 0..40 {
        if server_up() {
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(250));
    }
    Err(err("the Stremio streaming server was started but is not answering on 127.0.0.1:11470 (check `stremio-service` for errors)"))
}

pub fn stream_url(ep: &Endpoints, stream: &Value) -> Result<String, StreamError> {
    if let Some(u) = stream["url"].as_str().filter(|u| !u.is_empty()) {
        return Ok(u.into());
    }
    let h = stream["infoHash"].as_str().filter(|h| !h.is_empty()).ok_or_else(|| err("stream has neither url nor infoHash"))?;
    ensure_server()?;
    // warm the engine so peers are found while mpv opens
    let body = json!({"torrent": {"infoHash": h}}).to_string();
    let _ = Request::get(&format!("{}/{h}/create", ep.server)).header("Content-Type", "application/json").timeout(10.0).post(body.as_bytes()).send();
    let idx = stream["fileIdx"].as_i64().unwrap_or(-1);
    Ok(format!("{}/{h}/{}", ep.server, if idx >= 0 { idx } else { 0 }))
}

/// A direct HLS stream for the episode (vaplayer).
pub fn hls_stream(ep: &Endpoints, show_id: &str, episode_id: &str, check: bool) -> Result<Value, StreamError> {
    let (kind, imdb) = split_show(show_id)?;
    let found = if kind == "movie" {
        vaplayer::streams(&ep.vaplayer, "movie", &imdb, 0, 0, check)?
    } else {
        let c = crate::parse::rx(r"\A(tt\d+):(\d+):(\d+)\z").captures(episode_id).ok().flatten().ok_or_else(|| err(format!("bad episode id: {episode_id}")))?;
        vaplayer::streams(&ep.vaplayer, "tv", &imdb, c[2].parse().unwrap(), c[3].parse().unwrap(), check)?
    };
    Ok(found[0].clone())
}

pub struct Resolved {
    pub episodes: Vec<Value>,
    pub episode: Value,
    pub stream: Value,
}

/// (episode list, the chosen episode, its stream). A stream picked by hand wins; otherwise the
/// enabled sources are tried in order: direct HLS then torrents, or reversed with `prefer_stremio`.
pub fn resolve(ep: &Endpoints, show_id: &str, episode_id: &str, streaming: Option<&Streaming>) -> Result<Resolved, StreamError> {
    let use_hls = streaming.map(|s| s.hls).unwrap_or(true);
    let use_torrent = streaming.map(|s| s.stremio).unwrap_or(true);
    let prefer_torrent = streaming.map(|s| s.prefer_stremio).unwrap_or(false);
    if !(use_hls || use_torrent) {
        return Err(err("all streaming sources are turned off in the settings"));
    }
    // the episode list and the stream lookup are independent: run both at once
    std::thread::scope(|sc| {
        let eps = sc.spawn(|| episodes(ep, show_id));
        let stream = resolve_sources(ep, show_id, episode_id, use_hls, use_torrent, prefer_torrent);
        let eps = eps.join().map_err(|_| err("episode lookup crashed"))?;
        finish(show_id, episode_id, eps, stream?)
    })
}

fn finish(show_id: &str, episode_id: &str, eps: Result<Vec<Value>, StreamError>, stream: Value) -> Result<Resolved, StreamError> {
    let eps = eps?;
    let episode = eps.iter().find(|e| e["id"] == episode_id).cloned().ok_or_else(|| err("episode not found"))?;
    let _ = remember(show_id, episode_id, &stream);
    Ok(Resolved { episodes: eps, episode, stream })
}

fn resolve_sources(ep: &Endpoints, show_id: &str, episode_id: &str, use_hls: bool, use_torrent: bool, prefer_torrent: bool) -> Result<Value, StreamError> {
    let saved = recall(show_id, episode_id);
    if let Some(s) = saved.as_ref().filter(|s| use_torrent && s["chosen"].as_bool().unwrap_or(false)) {
        return Ok(s.clone());
    }
    let mut order = vec!["torrent", "hls"];
    if !prefer_torrent {
        order.reverse();
    }
    let mut problems = vec![];
    for name in order {
        if !(if name == "torrent" { use_torrent } else { use_hls }) {
            continue;
        }
        let got = if name == "torrent" {
            match saved.as_ref().filter(|s| s["infoHash"].as_str().map(|h| !h.is_empty()).unwrap_or(false)) {
                Some(s) => Ok(s.clone()),
                None => auto_pick(ep, show_id, episode_id, prefer_torrent),
            }
        } else {
            hls_stream(ep, show_id, episode_id, false)
        };
        match got {
            Ok(s) => return Ok(s),
            Err(e) => problems.push(format!("{}: {}", if name == "hls" { "Direct stream (vaplayer)" } else { "Torrents (Stremio addons)" }, e.0)),
        }
    }
    Err(err(if problems.is_empty() { "no stream found".to_string() } else { problems.join(" | ") }))
}

#[allow(dead_code)]
fn unused(_: HttpError) -> String {
    describe_http(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn show_ids() {
        assert_eq!(split_show("stremio:series:tt0903747").unwrap(), ("series".into(), "tt0903747".into()));
        assert!(split_show("stremio:anime:tt1").is_err());
        assert!(split_show("stremio:movie:ttx").is_err());
        assert!(is_show("stremio:movie:tt1") && !is_show("hianime:1"));
    }

    #[test]
    fn episode_numbers() {
        assert_eq!(episode_number(&json!({"season": 1, "episode": 3})), "S01E03");
        assert_eq!(episode_number(&json!({"season": 2, "number": 11})), "S02E11");
    }

    #[test]
    fn picks_like_python() {
        let st = |h: &str, q: &str, seeds: i64, bg: &str| json!({"infoHash": h, "quality": q, "seeds": seeds, "bingeGroup": bg});
        let list = vec![st("a", "720p", 90, "x"), st("b", "1080p", 5, "y"), st("c", "2160p", 1, "z")];
        assert_eq!(pick_from(list.clone(), &Value::Null, false).unwrap()["infoHash"], "a");
        assert_eq!(pick_from(list.clone(), &json!({"bingeGroup": "y"}), false).unwrap()["infoHash"], "b");
        assert_eq!(pick_from(list.clone(), &json!({"quality": "2160p"}), false).unwrap()["infoHash"], "c");
        assert_eq!(pick_from(list, &Value::Null, true).unwrap()["infoHash"], "b"); // 4k has < 3 seeds
    }

    #[test]
    fn quoting() {
        assert_eq!(quote("tt1:1:2"), "tt1%3A1%3A2");
    }
}
