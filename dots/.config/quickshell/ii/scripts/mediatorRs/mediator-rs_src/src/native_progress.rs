//! Persistent state for the native provider player (port of `mediator/native_progress.py`).
//! One atomic JSON document for the current episode plus one file per episode. The state stores
//! only provider identities and playback metadata, never a resolved (signed) URL.
use crate::fileio::atomic_write_text;
use crate::state::{finished, now};
use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::PathBuf;

pub const SETTLE_MIN: f64 = 10.0;

pub fn state_dir() -> PathBuf {
    crate::config::state_dir()
}
pub fn state_path() -> PathBuf {
    state_dir().join("native-stream.json")
}

// ---- Python-flavoured coercions, so odd values in old files behave the same ----

fn pystr(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        Value::Null => "None".into(),
        Value::Bool(b) => if *b { "True" } else { "False" }.into(),
        Value::Number(n) => n.to_string(),
        other => other.to_string(),
    }
}
fn text(m: &Value, k: &str, default: &str) -> String {
    match m.get(k) {
        Some(v) => pystr(v).trim().to_string(),
        None => default.to_string(),
    }
}
fn num(v: Option<&Value>) -> Option<f64> {
    match v? {
        Value::Number(n) => n.as_f64(),
        Value::Bool(b) => Some(*b as i64 as f64),
        Value::String(s) => s.trim().parse().ok(),
        _ => None,
    }
}
pub fn finite(v: Option<&Value>, default: f64) -> f64 {
    match num(v) {
        Some(x) if x.is_finite() && x >= 0.0 => x,
        _ => default,
    }
}
fn int(v: Option<&Value>) -> Option<i64> {
    match v? {
        Value::Number(n) => n.as_i64().or_else(|| n.as_f64().map(|f| f as i64)),
        Value::Bool(b) => Some(*b as i64),
        Value::String(s) => s.trim().parse().ok(),
        _ => None,
    }
}
fn positive_int(v: Option<&Value>) -> i64 {
    int(v).filter(|&n| n > 0).unwrap_or(0)
}
fn nonneg_int(v: Option<&Value>) -> i64 {
    int(v).filter(|&n| n >= 0).unwrap_or(0)
}
pub fn truthy_pub(v: Option<&Value>) -> bool {
    truthy(v, false)
}
fn truthy(v: Option<&Value>, default: bool) -> bool {
    match v {
        None => default,
        Some(Value::Bool(b)) => *b,
        Some(Value::Null) => false,
        Some(Value::Number(n)) => n.as_f64() != Some(0.0),
        Some(Value::String(s)) => !s.is_empty(),
        Some(Value::Array(a)) => !a.is_empty(),
        Some(Value::Object(o)) => !o.is_empty(),
    }
}
pub fn is_empty(v: &Value) -> bool {
    v.as_object().map(|o| o.is_empty()).unwrap_or(true)
}
fn empty() -> Value {
    Value::Object(Map::new())
}

fn episode(v: &Value) -> Option<Value> {
    let o = v.as_object()?;
    let id = text(v, "id", "");
    if id.is_empty() || o.is_empty() {
        return None;
    }
    Some(json!({"id": id, "number": text(v, "number", ""), "title": text(v, "title", "")}))
}

fn session(v: Option<&Value>) -> Value {
    let Some(v) = v.filter(|v| v.is_object()) else { return empty() };
    let mut socket = text(v, "socket", "");
    let mut socket_id = text(v, "socket_id", "");
    if !socket.is_empty() && socket_id.is_empty() {
        socket_id = basename(&socket);
    }
    if !socket_id.is_empty() && !is_socket_id(&socket_id) {
        socket_id.clear();
    }
    if !socket.is_empty() && (socket_id.is_empty() || basename(&socket) != socket_id) {
        socket.clear();
    }
    let worker = positive_int(v.get("worker_pid"));
    let mpv = positive_int(v.get("mpv_pid"));
    let title = text(v, "media_title", "");
    if socket.is_empty() && socket_id.is_empty() && title.is_empty() && worker == 0 {
        return empty();
    }
    json!({
        "socket": socket, "socket_id": socket_id, "worker_pid": worker, "mpv_pid": mpv, "media_title": title,
        "active": truthy(v.get("active"), true), "attached": truthy(v.get("attached"), false),
        "paused": truthy(v.get("paused"), false), "position": finite(v.get("position"), 0.0),
        "duration": finite(v.get("duration"), 0.0), "updated_at": finite(v.get("updated_at"), now()),
    })
}

fn basename(p: &str) -> String {
    p.rsplit('/').next().unwrap_or(p).to_string()
}
fn is_socket_id(s: &str) -> bool {
    s.strip_prefix("mediator-").and_then(|r| r.strip_suffix(".sock")).map(|d| !d.is_empty() && d.bytes().all(|b| b.is_ascii_digit())).unwrap_or(false)
}

fn clean(raw: &Value) -> Value {
    if !raw.is_object() {
        return empty();
    }
    let (show_id, episode_id) = (text(raw, "show_id", ""), text(raw, "episode_id", ""));
    if show_id.is_empty() || episode_id.is_empty() {
        return empty();
    }
    let mut eps: Vec<Value> = vec![];
    if let Some(items) = raw.get("episodes").and_then(|e| e.as_array()) {
        for item in items {
            if let Some(c) = episode(item) {
                if !eps.iter().any(|o| o["id"] == c["id"]) {
                    eps.push(c);
                }
            }
        }
    }
    let title = text(raw, "title", "");
    let quality = text(raw, "quality", "best");
    json!({
        "show_id": show_id,
        "title": if title.is_empty() { show_id.clone() } else { title },
        "poster": text(raw, "poster", ""),
        "episodes": eps,
        "episode_id": episode_id,
        "episode_number": text(raw, "episode_number", ""),
        "episode_title": text(raw, "episode_title", ""),
        "quality": if quality.is_empty() { "best".to_string() } else { quality },
        "dub": truthy(raw.get("dub"), false),
        "position": finite(raw.get("position"), 0.0),
        "duration": finite(raw.get("duration"), 0.0),
        "resume_from": finite(raw.get("resume_from"), 0.0),
        "settled": truthy(raw.get("settled"), true),
        "watched": truthy(raw.get("watched"), false),
        "updated_at": finite(raw.get("updated_at"), now()),
        "session": session(raw.get("session")),
        "anilist_id": positive_int(raw.get("anilist_id")),
        "season": nonneg_int(raw.get("season")),
        "total": positive_int(raw.get("total")),
    })
}

fn read(path: &std::path::Path) -> Option<Value> {
    serde_json::from_str(&fs::read_to_string(path).ok()?).ok()
}

/// The last valid state, or an empty object for missing/bad state.
pub fn load() -> Value {
    read(&state_path()).map(|v| clean(&v)).unwrap_or_else(empty)
}

fn episode_path(show_id: &str, episode_id: &str) -> PathBuf {
    let key = serde_json::to_string(&json!([show_id, episode_id])).unwrap();
    let digest = Sha256::digest(key.as_bytes());
    state_dir().join("native-episodes").join(format!("{}.json", hex(&digest)))
}
fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

pub fn load_episode(show_id: &str, episode_id: &str) -> Value {
    if let Some(v) = read(&episode_path(show_id, episode_id)) {
        return clean(&v);
    }
    let cur = load();
    if cur["show_id"] == show_id && cur["episode_id"] == episode_id { cur } else { empty() }
}

fn episode_files() -> Vec<PathBuf> {
    let Ok(rd) = fs::read_dir(state_dir().join("native-episodes")) else { return vec![] };
    rd.flatten().map(|e| e.path()).filter(|p| p.extension().map(|x| x == "json").unwrap_or(false)).collect()
}

/// The most recently played native episodes, newest first.
pub fn recent(limit: usize) -> Vec<Value> {
    let mut states: Vec<Value> = episode_files().iter().filter_map(|p| read(p)).map(|v| clean(&v)).filter(|s| !is_empty(s)).collect();
    states.sort_by(|a, b| b["updated_at"].as_f64().partial_cmp(&a["updated_at"].as_f64()).unwrap_or(std::cmp::Ordering::Equal));
    states.truncate(limit);
    states
}

/// The newest episode of each show, capped after grouping so one series cannot crowd out others.
pub fn recent_shows(limit: usize) -> Vec<Value> {
    let mut seen = std::collections::HashSet::new();
    let mut states: Vec<Value> = episode_files().iter().filter_map(|p| read(p)).map(|v| clean(&v)).filter(|s| !is_empty(s)).collect();
    states.sort_by(|a, b| b["updated_at"].as_f64().partial_cmp(&a["updated_at"].as_f64()).unwrap_or(std::cmp::Ordering::Equal));
    states.into_iter().filter(|state| {
        let show = state["show_id"].as_str().unwrap_or("");
        !show.is_empty() && seen.insert(show.to_owned())
    }).take(limit).collect()
}

/// Drop every remembered episode of one show. Returns how many records were removed.
pub fn forget(show_id: &str) -> usize {
    if show_id.is_empty() {
        return 0;
    }
    let mut removed = 0;
    for p in episode_files() {
        if let Some(v) = read(&p) {
            if v.is_object() && pystr(v.get("show_id").unwrap_or(&Value::Null)) == show_id && fs::remove_file(&p).is_ok() {
                removed += 1;
            }
        }
    }
    if load()["show_id"] == show_id {
        let _ = fs::remove_file(state_path());
    }
    removed
}

/// The current native state whose live player owns this socket name, if any.
pub fn load_for_socket(socket_id: &str) -> Value {
    let wanted = basename(socket_id.trim());
    if wanted.is_empty() {
        return empty();
    }
    let state = load();
    let s = &state["session"];
    if s["socket_id"] == wanted.as_str() || s["socket"].as_str().map(|p| !p.is_empty() && basename(p) == wanted).unwrap_or(false) {
        return state;
    }
    empty()
}

/// The next episode in the remembered list after the current one.
pub fn next_episode(state: Option<&Value>) -> Option<Value> {
    let owned;
    let state = match state {
        Some(s) if s.is_object() => s,
        _ => {
            owned = load();
            &owned
        }
    };
    let eps = state.get("episodes")?.as_array()?;
    let i = eps.iter().position(|e| e.get("id") == state.get("episode_id"))?;
    eps.get(i + 1).cloned()
}

fn write(state: &Value, make_current: bool) -> Value {
    let c = clean(state);
    if is_empty(&c) {
        return empty();
    }
    let body = format!("{}\n", serde_json::to_string(&c).unwrap());
    let mut targets = vec![episode_path(c["show_id"].as_str().unwrap(), c["episode_id"].as_str().unwrap())];
    if make_current {
        targets.push(state_path());
    }
    for t in targets {
        let _ = atomic_write_text(&t, &body, 0o600);
    }
    c
}

fn plausible(current: &mut Value, position: f64) -> bool {
    if truthy(current.get("settled"), true) {
        return true;
    }
    if position >= finite(current.get("resume_from"), 0.0) - SETTLE_MIN {
        current["settled"] = json!(true);
        return true;
    }
    false
}

#[derive(Default)]
pub struct Begin {
    pub title: String,
    pub poster: String,
    pub episodes: Option<Vec<Value>>,
    pub episode_number: String,
    pub episode_title: String,
    pub quality: Option<String>,
    pub dub: bool,
    pub position: f64,
    pub duration: f64,
    pub anilist_id: i64,
    pub season: i64,
    pub total: i64,
}

/// Record the selected stable provider identities before mpv starts.
pub fn begin(show_id: &str, episode_id: &str, b: Begin) -> Value {
    let mut current = load();
    if current["show_id"] != show_id {
        current = empty();
    }
    let keep = |new: &str, key: &str, fallback: &str| -> String {
        if !new.is_empty() { new.to_string() } else { current.get(key).and_then(|v| v.as_str()).unwrap_or(fallback).to_string() }
    };
    let pos = finite(Some(&json!(b.position)), 0.0);
    let ikeep = |new: i64, key: &str| -> i64 { if new > 0 { new } else { current.get(key).and_then(|v| v.as_i64()).unwrap_or(0) } };
    let incoming = json!({
        "show_id": show_id,
        "title": keep(&b.title, "title", show_id),
        "poster": keep(&b.poster, "poster", ""),
        "episodes": b.episodes.clone().unwrap_or_else(|| current.get("episodes").and_then(|e| e.as_array()).cloned().unwrap_or_default()),
        "episode_id": episode_id,
        "episode_number": b.episode_number,
        "episode_title": b.episode_title,
        "quality": b.quality.clone().unwrap_or_else(|| "best".into()),
        "dub": b.dub,
        "position": pos,
        "duration": finite(Some(&json!(b.duration)), 0.0),
        "resume_from": pos,
        "settled": pos < SETTLE_MIN,
        "watched": false,
        "updated_at": now(),
        "session": {},
        "anilist_id": ikeep(positive_int(Some(&json!(b.anilist_id))), "anilist_id"),
        "season": if b.season != 0 { nonneg_int(Some(&json!(b.season))) } else { current.get("season").and_then(|v| v.as_i64()).unwrap_or(0) },
        "total": ikeep(positive_int(Some(&json!(b.total))), "total"),
    });
    write(&incoming, true)
}

/// The exact title put in mpv's `force-media-title` option.
pub fn expected_media_title(state: &Value) -> String {
    let explicit = text(&state["session"], "media_title", "");
    if !explicit.is_empty() {
        return explicit;
    }
    let (title, number) = (text(state, "title", ""), text(state, "episode_number", ""));
    if !title.is_empty() && !number.is_empty() { format!("{title} Episode {number}").trim().to_string() } else { String::new() }
}

fn is_this(cur: &Value, show_id: &str, episode_id: &str) -> bool {
    cur["show_id"] == show_id && cur["episode_id"] == episode_id
}

#[derive(Default)]
pub struct Attach {
    pub worker_pid: i64,
    pub media_title: String,
    pub position: Option<f64>,
    pub duration: Option<f64>,
    pub paused: Option<bool>,
}

/// Mark an exact live native socket as attached to the remembered episode.
pub fn attach_session(show_id: &str, episode_id: &str, socket: &str, a: Attach) -> Value {
    let mut cur = load();
    if !is_this(&cur, show_id, episode_id) {
        return cur;
    }
    let prev = if cur["session"].is_object() { cur["session"].clone() } else { empty() };
    let prev_worker = prev.get("worker_pid").and_then(|v| v.as_i64()).unwrap_or(0);
    let title = if !a.media_title.is_empty() { a.media_title.clone() } else {
        let p = text(&prev, "media_title", "");
        if !p.is_empty() { p } else { expected_media_title(&cur) }
    };
    let mut merged = prev.as_object().cloned().unwrap_or_default();
    for (k, v) in [
        ("socket", json!(socket)), ("socket_id", json!(basename(socket))),
        ("worker_pid", json!(if a.worker_pid != 0 { a.worker_pid } else { prev_worker })),
        ("media_title", json!(title)), ("active", json!(true)), ("attached", json!(true)),
        ("paused", json!(a.paused.unwrap_or_else(|| truthy(prev.get("paused"), false)))),
        ("position", json!(a.position.unwrap_or_else(|| cur["position"].as_f64().unwrap_or(0.0)))),
        ("duration", json!(a.duration.unwrap_or_else(|| cur["duration"].as_f64().unwrap_or(0.0)))),
        ("updated_at", json!(now())),
    ] {
        merged.insert(k.into(), v);
    }
    cur["session"] = session(Some(&Value::Object(merged)));
    if let Some(p) = a.position {
        cur["position"] = json!(finite(Some(&json!(p)), 0.0));
    }
    if let Some(d) = a.duration {
        cur["duration"] = json!(finite(Some(&json!(d)), 0.0));
    }
    write(&cur, true)
}

/// Checkpoint an adopted player without changing its stable identity.
pub fn update_session(show_id: &str, episode_id: &str, position: Option<f64>, duration: Option<f64>, paused: Option<bool>) -> Value {
    let mut cur = load();
    if !is_this(&cur, show_id, episode_id) {
        return cur;
    }
    let mut rt = if cur["session"].is_object() { cur["session"].as_object().cloned().unwrap_or_default() } else { Map::new() };
    if rt.is_empty() {
        return cur;
    }
    let position = position.filter(|&p| plausible(&mut cur, finite(Some(&json!(p)), 0.0)));
    rt.insert("active".into(), json!(true));
    rt.insert("attached".into(), json!(true));
    if let Some(p) = position {
        rt.insert("position".into(), json!(p));
    } else if !rt.contains_key("position") {
        rt.insert("position".into(), cur["position"].clone());
    }
    if let Some(d) = duration {
        rt.insert("duration".into(), json!(d));
    } else if !rt.contains_key("duration") {
        rt.insert("duration".into(), cur["duration"].clone());
    }
    if let Some(p) = paused {
        rt.insert("paused".into(), json!(p));
    } else if !rt.contains_key("paused") {
        rt.insert("paused".into(), json!(false));
    }
    rt.insert("updated_at".into(), json!(now()));
    cur["session"] = Value::Object(rt);
    if let Some(p) = position {
        cur["position"] = json!(finite(Some(&json!(p)), 0.0));
    }
    if let Some(d) = duration {
        cur["duration"] = json!(finite(Some(&json!(d)), 0.0));
    }
    write(&cur, true)
}

/// Clear live ownership after the exact native socket really disappears.
pub fn finish_session(show_id: &str, episode_id: &str, socket: &str) -> Value {
    let mut cur = load();
    if !is_this(&cur, show_id, episode_id) {
        return cur;
    }
    if !socket.is_empty() {
        if let Some(s) = cur["session"]["socket"].as_str().filter(|s| !s.is_empty()) {
            if s != socket {
                return cur;
            }
        }
    }
    cur["session"] = empty();
    write(&cur, true)
}

/// Persist a finite mpv checkpoint without changing show/episode identity.
pub fn checkpoint(show_id: &str, episode_id: &str, position: f64, duration: f64, eof: bool, finish_ratio: f64, finish_tail: f64) -> Value {
    let latest = load();
    let is_current = is_this(&latest, show_id, episode_id);
    let mut cur = if is_current { latest.clone() } else { load_episode(show_id, episode_id) };
    if is_empty(&cur) {
        return latest;
    }
    let position = finite(Some(&json!(position)), 0.0);
    let duration = finite(Some(&json!(duration)), 0.0);
    if !eof && !plausible(&mut cur, position) {
        if duration != 0.0 {
            cur["duration"] = json!(duration);
        }
        cur["updated_at"] = json!(now());
        return write(&cur, is_current);
    }
    cur["position"] = json!(position);
    cur["duration"] = json!(duration);
    cur["watched"] = json!(finished(position, duration, eof, finite(Some(&json!(finish_ratio)), 0.9), finite(Some(&json!(finish_tail)), 120.0)));
    cur["updated_at"] = json!(now());
    write(&cur, is_current)
}

pub fn json_state() -> Value {
    json!({"ok": true, "state": load()})
}
