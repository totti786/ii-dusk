//! Jellyfin as a second source of titles (port of `mediator/jellyfin.py`).
//! The server's libraries become Titles (source = "jellyfin") built from the same Entry model as
//! local files. Watch state stays in the local SQLite database too: merged in from the server when
//! a library loads (the newer side wins) and reported back as you watch. The token is never put in
//! a URL (see `write_mpv_auth`).
use crate::catalog::{cmp_order, unique_id, Entry, Title};
use crate::config::Jellyfin as JellyfinConfig;
use crate::parse::{norm_key, rx};
use crate::state::State;
use serde_json::{json, Map, Value};
use std::cell::{Cell, RefCell};
use std::collections::{BTreeMap, HashMap};

pub const TICKS: f64 = 10_000_000.0; // Jellyfin counts time in 100ns ticks
pub const USER_AGENT: &str = "mediator/0.1"; // some reverse proxies refuse the default agent with a 403
pub const PAGE: i64 = 500;

#[derive(Debug, Clone, PartialEq)]
pub struct JellyfinError(pub String);
impl std::fmt::Display for JellyfinError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for JellyfinError {}
type R<T> = Result<T, JellyfinError>;
fn err<T>(m: impl Into<String>) -> R<T> {
    Err(JellyfinError(m.into()))
}

pub fn cache_dir() -> std::path::PathBuf {
    crate::config::cache_dir().join("jellyfin")
}

// ---- HTTP ----

pub trait JfHttp {
    fn get(&self, path: &str, params: &[(&str, String)]) -> R<Value>;
    fn post(&self, path: &str, body: Option<&Value>, params: &[(&str, String)], headers: &[(&str, String)]) -> R<Option<Value>>;
    fn bytes(&self, path: &str, params: &[(&str, String)]) -> R<Vec<u8>>;
}

pub struct Http {
    pub base: String,
    pub token: String,
    pub timeout: f64,
}
impl Http {
    pub fn new(base: &str, token: &str) -> Http {
        Http { base: base.trim_end_matches('/').into(), token: token.into(), timeout: 20.0 }
    }
    pub fn with_timeout(mut self, t: f64) -> Http {
        self.timeout = t;
        self
    }
    fn request(&self, method: &str, path: &str, params: &[(&str, String)], body: Option<&Value>, headers: &[(&str, String)], accept: &str) -> R<Vec<u8>> {
        let mut url = format!("{}{}", self.base, path);
        if !params.is_empty() {
            let q: Vec<String> = params.iter().map(|(k, v)| format!("{}={}", enc(k), enc(v))).collect();
            url.push(if url.contains('?') { '&' } else { '?' });
            url.push_str(&q.join("&"));
        }
        let payload = body.map(|b| b.to_string());
        let mut req = crate::http::Request::get(&url).agent(USER_AGENT).timeout(self.timeout).header("Accept", accept);
        for (k, v) in headers {
            req = req.header(k, v);
        }
        if !self.token.is_empty() {
            req = req.header("X-Emby-Token", &self.token);
        }
        if method == "POST" {
            req = req.header("Content-Type", "application/json");
            req = req.post(payload.as_deref().unwrap_or("{}").as_bytes());
        }
        req.send().map_err(|e| match e {
            crate::http::HttpError::Status(c) => JellyfinError(format!("HTTP {c} for {method} {path}")),
            other => JellyfinError(format!("cannot reach {}: {}", self.base, other.describe())),
        })
    }
}
fn enc(s: &str) -> String {
    percent_encoding::utf8_percent_encode(s, percent_encoding::NON_ALPHANUMERIC).to_string().replace("%20", "+")
}
impl JfHttp for Http {
    fn get(&self, path: &str, params: &[(&str, String)]) -> R<Value> {
        let raw = self.request("GET", path, params, None, &[], "application/json")?;
        serde_json::from_slice(&raw).or_else(|_| err(format!("{path}: server did not return JSON (is the URL right?)")))
    }
    fn post(&self, path: &str, body: Option<&Value>, params: &[(&str, String)], headers: &[(&str, String)]) -> R<Option<Value>> {
        let raw = self.request("POST", path, params, Some(body.unwrap_or(&json!({}))), headers, "application/json")?;
        Ok(if raw.is_empty() { None } else { serde_json::from_slice(&raw).ok() })
    }
    fn bytes(&self, path: &str, params: &[(&str, String)]) -> R<Vec<u8>> {
        self.request("GET", path, params, None, &[], "*/*")
    }
}

// ---- turning server items into Titles (pure) ----

#[derive(Debug, Clone, Default)]
pub struct RemoteLibrary {
    pub kind: String,
    pub titles: Vec<Title>,
    pub userdata: BTreeMap<String, Value>, // entry path -> trimmed UserData
    pub stale: bool,                       // served from an old cache because the server was unreachable
}

pub fn stream_url(base: &str, item_id: &str) -> String {
    format!("{}/Videos/{}/stream?Static=true", base.trim_end_matches('/'), item_id)
}

const ABOUT: &str = "CommunityRating,Genres,Overview,OfficialRating";

fn present(v: &Value) -> bool {
    match v {
        Value::Null => false,
        Value::String(s) => !s.is_empty(),
        Value::Array(a) => !a.is_empty(),
        _ => true,
    }
}

fn about(item: &Value) -> Value {
    let mut m = Map::new();
    for k in ["CommunityRating", "Genres", "Overview", "OfficialRating", "ProductionYear"] {
        if present(&item[k]) {
            m.insert(k.into(), item[k].clone());
        }
    }
    Value::Object(m)
}

pub fn trim(item: &Value) -> Value {
    let ud = &item["UserData"];
    let src = item["MediaSources"].get(0).cloned().unwrap_or(json!({}));
    let mut u = Map::new();
    for k in ["PlaybackPositionTicks", "Played", "LastPlayedDate"] {
        if let Some(v) = ud.get(k) {
            u.insert(k.into(), v.clone());
        }
    }
    let num = |v: &Value| if v.as_f64().map(|f| f != 0.0).unwrap_or(false) { v.clone() } else { json!(0) };
    json!({
        "Id": item["Id"], "Name": item["Name"], "SeriesId": item["SeriesId"], "SeriesName": item["SeriesName"],
        "ParentIndexNumber": item["ParentIndexNumber"], "IndexNumber": item["IndexNumber"], "IndexNumberEnd": item["IndexNumberEnd"],
        "ProductionYear": item["ProductionYear"], "Size": num(&src["Size"]), "RunTimeTicks": num(&item["RunTimeTicks"]),
        "CommunityRating": item["CommunityRating"], "Genres": item["Genres"], "Overview": item["Overview"],
        "OfficialRating": item["OfficialRating"], "UserData": Value::Object(u),
    })
}

/// Jellyfin timestamps carry 7 fractional digits. Seconds since the epoch, 0 when unreadable.
pub fn parse_when(s: Option<&str>) -> f64 {
    let Some(s) = s.filter(|s| !s.is_empty()) else { return 0.0 };
    let Ok(Some(c)) = rx(r"^(\d{4})-(\d\d)-(\d\d)(?:[T ](\d\d):(\d\d)(?::(\d\d)(?:[.,](\d+))?)?)?(Z|[+-]\d\d(?::?\d\d)?)?$").captures(s.trim()) else { return 0.0 };
    let n = |i: usize| c.get(i).and_then(|m| m.as_str().parse::<i64>().ok()).unwrap_or(0);
    let days = days_from_civil(n(1), n(2), n(3));
    let frac = c.get(7).map(|m| format!("0.{}", m.as_str()).parse::<f64>().unwrap_or(0.0)).unwrap_or(0.0);
    let mut t = (days * 86400 + n(4) * 3600 + n(5) * 60 + n(6)) as f64 + frac;
    if let Some(z) = c.get(8).map(|m| m.as_str()).filter(|z| *z != "Z") {
        let sign = if z.starts_with('-') { -1.0 } else { 1.0 };
        let d: String = z[1..].chars().filter(|c| c.is_ascii_digit()).collect();
        let (h, m) = (d[..2].parse::<f64>().unwrap_or(0.0), d.get(2..4).and_then(|x| x.parse::<f64>().ok()).unwrap_or(0.0));
        t -= sign * (h * 3600.0 + m * 60.0);
    }
    t
}

fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

/// `%Y-%m-%dT%H:%M:%S.%fZ` for "now".
pub fn utc_stamp() -> String {
    let t = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default();
    let secs = t.as_secs() as i64;
    let date = crate::info::civil_date(secs);
    let r = secs.rem_euclid(86400);
    format!("{date}T{:02}:{:02}:{:02}.{:06}Z", r / 3600, r % 3600 / 60, r % 60, t.subsec_micros())
}

fn generic_name(name: Option<&str>) -> String {
    let n = name.unwrap_or("").trim();
    if rx(r"(?i)^(episode|ep)\s*\d+(\.\d+)?$").is_match(n).unwrap_or(false) { String::new() } else { n.to_string() }
}

fn s<'a>(v: &'a Value, k: &str) -> &'a str {
    v[k].as_str().unwrap_or("")
}
fn int(v: &Value) -> i64 {
    v.as_i64().or_else(|| v.as_f64().map(|f| f as i64)).unwrap_or(0)
}
fn userdata_with_runtime(it: &Value) -> Value {
    let mut m = it["UserData"].as_object().cloned().unwrap_or_default();
    m.insert("RunTimeTicks".into(), json!(if int(&it["RunTimeTicks"]) != 0 { it["RunTimeTicks"].clone() } else { json!(0) }));
    Value::Object(m)
}

pub fn build_titles(kind: &str, base: &str, series: &[Value], items: &[Value]) -> RemoteLibrary {
    let mut lib = RemoteLibrary { kind: kind.into(), ..Default::default() };
    let mut used: HashMap<String, usize> = HashMap::new();
    let name_of = |v: &Value| { let n = s(v, "Name"); if n.is_empty() { "?".to_string() } else { n.to_string() } };
    let year_of = |v: &Value| v["ProductionYear"].as_i64().map(|y| y as i32);
    if kind == "movies" {
        let mut sorted: Vec<&Value> = items.iter().collect();
        sorted.sort_by_key(|i| norm_key(s(i, "Name")));
        for it in sorted {
            let (name, year) = (name_of(it), year_of(it));
            let mut t = Title::new(format!("jellyfin/{}", unique_id("movies", &norm_key(&name), year, &mut used)), "movies", name.clone(), year);
            t.source = "jellyfin".into();
            t.remote_id = s(it, "Id").into();
            t.remote = about(it);
            let e = Entry { path: stream_url(base, s(it, "Id")), rel: name.clone(), size: int(&it["Size"]), kind: "movie".into(), season: None, episode: None,
                episode_end: None, version: 1, name: String::new(), rule: "jellyfin".into(), confidence: "high".into(), stem: name, remote_id: s(it, "Id").into() };
            lib.userdata.insert(e.path.clone(), userdata_with_runtime(it));
            t.entries.push(e);
            lib.titles.push(t);
        }
        return lib;
    }
    let mut order: Vec<String> = vec![];
    let mut by_series: HashMap<String, Title> = HashMap::new();
    let mut sorted: Vec<&Value> = series.iter().collect();
    sorted.sort_by_key(|i| norm_key(s(i, "Name")));
    for sv in sorted {
        let (name, year) = (name_of(sv), year_of(sv));
        let mut t = Title::new(format!("jellyfin/{}", unique_id(kind, &norm_key(&name), year, &mut used)), kind, name, year);
        t.source = "jellyfin".into();
        t.remote_id = s(sv, "Id").into();
        t.remote = about(sv);
        order.push(s(sv, "Id").into());
        by_series.insert(s(sv, "Id").into(), t);
    }
    for it in items {
        let Some(t) = by_series.get_mut(s(it, "SeriesId")) else { continue };
        let (season, ep) = (it["ParentIndexNumber"].as_i64(), it["IndexNumber"].as_f64());
        let ekind = if ep.is_none() { "extra" } else if season == Some(0) { "special" } else { "episode" };
        let name = generic_name(it["Name"].as_str());
        let id = s(it, "Id");
        let sn = season.unwrap_or(1);
        let e = Entry { path: stream_url(base, id), rel: format!("{}/S{:02}/{}", t.name, sn, if name.is_empty() { id } else { &name }),
            size: int(&it["Size"]), kind: ekind.into(), season: Some(sn as i32), episode: ep, episode_end: it["IndexNumberEnd"].as_i64().map(|x| x as i32),
            version: 1, name: name.clone(), rule: "jellyfin".into(), confidence: "high".into(), stem: if name.is_empty() { t.name.clone() } else { name.clone() }, remote_id: id.into() };
        lib.userdata.insert(e.path.clone(), userdata_with_runtime(it));
        t.entries.push(e);
    }
    for id in order {
        let mut t = by_series.remove(&id).unwrap();
        if !t.entries.is_empty() {
            t.entries.sort_by(cmp_order);
            lib.titles.push(t);
        }
    }
    lib
}

/// Pull the server's watch state into the local database; whichever side is newer wins.
pub fn merge_into_state(state: &State, lib: &RemoteLibrary) -> usize {
    let by_path: HashMap<&str, (&Title, &Entry)> = lib.titles.iter().flat_map(|t| t.entries.iter().map(move |e| (e.path.as_str(), (t, e)))).collect();
    let mut changed = 0;
    for (path, ud) in &lib.userdata {
        let pos = ud["PlaybackPositionTicks"].as_f64().unwrap_or(0.0) / TICKS;
        let played = ud["Played"].as_bool().unwrap_or(false);
        let when = parse_when(ud["LastPlayedDate"].as_str());
        let Some((t, e)) = by_path.get(path.as_str()) else { continue };
        if !(played || pos > 0.0) {
            continue;
        }
        if let Ok(Some(local)) = state.get(path, 0) {
            if local.updated >= when {
                continue;
            }
        }
        let dur = ud["RunTimeTicks"].as_f64().unwrap_or(0.0) / TICKS;
        let w = if when != 0.0 { when } else { 1.0 }; // no date on the server: treat as old
        if state.put(path, &t.id, if played { 0.0 } else { pos }, dur, played, e.size, &e.label(), Some(w)).is_ok() {
            changed += 1;
        }
    }
    changed
}

// ---- the client ----

pub struct Jellyfin {
    pub cfg: JellyfinConfig,
    pub http: Box<dyn JfHttp>,
    pub cache_dir: std::path::PathBuf,
    now: Box<dyn Fn() -> f64>,
    user_id: RefCell<String>,
}

fn cache_ok(c: &Value, url: &str, user: &str) -> bool {
    c["v"] == 2 && c["url"] == url && c["user"] == user
}

impl Jellyfin {
    pub fn new(cfg: &JellyfinConfig) -> Jellyfin {
        Jellyfin::with_http(cfg, Box::new(Http::new(&cfg.url, &cfg.token)), cache_dir(), Box::new(crate::state::now))
    }
    pub fn with_http(cfg: &JellyfinConfig, http: Box<dyn JfHttp>, cache_dir: std::path::PathBuf, now: Box<dyn Fn() -> f64>) -> Jellyfin {
        Jellyfin { cfg: cfg.clone(), http, cache_dir, now, user_id: RefCell::new(cfg.user_id.clone()) }
    }

    pub fn user_id(&self) -> R<String> {
        if self.user_id.borrow().is_empty() {
            let users = self.http.get("/Users", &[])?;
            let want = self.cfg.username.to_lowercase();
            let hit = users.as_array().and_then(|a| a.iter().find(|u| s(u, "Name").to_lowercase() == want).cloned());
            let Some(hit) = hit else { return err(format!("no Jellyfin user named {}", crate::selection::py_str(&self.cfg.username))) };
            *self.user_id.borrow_mut() = s(&hit, "Id").into();
        }
        Ok(self.user_id.borrow().clone())
    }

    fn views(&self) -> R<Vec<Value>> {
        Ok(self.http.get(&format!("/Users/{}/Views", self.user_id()?), &[])?["Items"].as_array().cloned().unwrap_or_default())
    }

    pub fn status(&self) -> R<Value> {
        let info = self.http.get("/System/Info/Public", &[])?;
        let libs: Vec<Value> = self.views()?.iter().map(|v| json!({"name": v["Name"], "type": v["CollectionType"], "id": v["Id"]})).collect();
        Ok(json!({"server": info["ServerName"], "version": info["Version"], "libraries": libs}))
    }

    pub fn kinds(&self) -> Vec<&'static str> {
        ["anime", "shows", "movies"].into_iter().filter(|k| self.cfg.libraries.get(*k).map(|v| !v.is_empty()).unwrap_or(false)).collect()
    }

    fn items(&self, params: &[(&str, String)]) -> R<Vec<Value>> {
        let uid = self.user_id()?;
        let (mut out, mut start) = (vec![], 0i64);
        loop {
            let mut p: Vec<(&str, String)> = params.to_vec();
            p.extend([("Recursive", "true".into()), ("StartIndex", start.to_string()), ("Limit", PAGE.to_string())]);
            let page = self.http.get(&format!("/Users/{uid}/Items"), &p)?;
            let got = page["Items"].as_array().cloned().unwrap_or_default();
            start += got.len() as i64;
            let done = got.is_empty() || start >= int(&page["TotalRecordCount"]);
            out.extend(got);
            if done {
                return Ok(out);
            }
        }
    }

    fn cache_file(&self, kind: &str) -> std::path::PathBuf {
        self.cache_dir.join(format!("{kind}.json"))
    }
    fn read_cache(&self, kind: &str) -> Option<Value> {
        serde_json::from_str(&std::fs::read_to_string(self.cache_file(kind)).ok()?).ok()
    }
    fn write_cache(&self, kind: &str, data: &Value) {
        let _ = std::fs::create_dir_all(&self.cache_dir);
        let _ = crate::fileio::atomic_write_text(&self.cache_file(kind), &data.to_string(), 0o644);
    }

    /// `any_age`: take the cached listing however old it is (no network when there is one).
    pub fn library(&self, kind: &str, refresh: bool, any_age: bool) -> R<RemoteLibrary> {
        let cached = self.read_cache(kind);
        let hint = self.user_id.borrow().clone();
        let usable = cached.as_ref().filter(|c| cache_ok(c, &self.cfg.url, &hint));
        let build = |c: &Value| build_titles(kind, &self.cfg.url, c["series"].as_array().map(|v| v.as_slice()).unwrap_or(&[]), c["items"].as_array().map(|v| v.as_slice()).unwrap_or(&[]));
        if let Some(c) = usable {
            if !refresh && (any_age || (self.now)() - c["fetched"].as_f64().unwrap_or(0.0) < self.cfg.cache_ttl as f64) {
                return Ok(build(c));
            }
        }
        let fetch = || -> R<Value> {
            let name = self.cfg.libraries.get(kind).cloned().unwrap_or_default();
            let views = self.views()?;
            let Some(view) = views.iter().find(|v| s(v, "Name").to_lowercase() == name.to_lowercase()) else {
                let have: Vec<&str> = views.iter().map(|v| s(v, "Name")).collect();
                return err(format!("no Jellyfin library named {} (have: {})", crate::selection::py_str(&name), if have.is_empty() { "none".to_string() } else { have.join(", ") }));
            };
            let pid = s(view, "Id").to_string();
            let (series, items) = if kind == "movies" {
                (vec![], self.items(&[("ParentId", pid), ("IncludeItemTypes", "Movie".into()), ("Fields", format!("MediaSources,{ABOUT}"))])?)
            } else {
                (self.items(&[("ParentId", pid.clone()), ("IncludeItemTypes", "Series".into()), ("Fields", ABOUT.into())])?,
                 self.items(&[("ParentId", pid), ("IncludeItemTypes", "Episode".into()), ("Fields", "MediaSources".into())])?)
            };
            Ok(json!({"v": 2, "fetched": (self.now)(), "url": self.cfg.url, "user": self.user_id()?,
                "series": series.iter().map(trim).collect::<Vec<_>>(), "items": items.iter().map(trim).collect::<Vec<_>>()}))
        };
        match fetch() {
            Ok(data) => {
                self.write_cache(kind, &data);
                Ok(build(&data))
            }
            Err(e) => match usable {
                Some(c) => {
                    // offline: an old listing beats nothing
                    let mut lib = build(c);
                    lib.stale = true;
                    Ok(lib)
                }
                None => Err(e),
            },
        }
    }

    /// The cached listing as titles, never touching the network (None without a usable cache).
    pub fn cached_library(&self, kind: &str) -> Option<RemoteLibrary> {
        let cached = self.read_cache(kind)?;
        let hint = self.user_id.borrow().clone();
        if !cache_ok(&cached, &self.cfg.url, &hint) {
            return None;
        }
        Some(build_titles(kind, &self.cfg.url, cached["series"].as_array().map(|v| v.as_slice()).unwrap_or(&[]), cached["items"].as_array().map(|v| v.as_slice()).unwrap_or(&[])))
    }

    /// Set the server's resume point / played flag for one item.
    pub fn report(&self, item_id: &str, position: f64, _duration: f64, watched: bool) -> R<()> {
        let mut body = json!({"PlaybackPositionTicks": if watched { 0 } else { (position * TICKS) as i64 }, "Played": watched});
        if watched || position > 0.0 {
            body["LastPlayedDate"] = json!(utc_stamp());
        }
        self.user_data(item_id, &body)
    }

    /// Write back an item's UserData verbatim (used to restore state).
    pub fn set_user_data(&self, item_id: &str, ud: &Value) -> R<()> {
        let mut keep = Map::new();
        for k in ["PlaybackPositionTicks", "Played", "PlayCount", "IsFavorite", "LastPlayedDate", "Likes", "Rating"] {
            if let Some(v) = ud.get(k) {
                keep.insert(k.into(), v.clone());
            }
        }
        self.user_data(item_id, &Value::Object(keep))
    }

    fn user_data(&self, item_id: &str, body: &Value) -> R<()> {
        let uid = self.user_id()?;
        // 10.9 and later
        match self.http.post(&format!("/UserItems/{item_id}/UserData"), Some(body), &[("userId", uid.clone())], &[]) {
            Ok(_) => Ok(()),
            Err(e) if e.0.contains("HTTP 404") || e.0.contains("HTTP 405") => self.http.post(&format!("/Users/{uid}/Items/{item_id}/UserData"), Some(body), &[], &[]).map(|_| ()),
            Err(e) => Err(e),
        }
    }

    pub fn item_user_data(&self, item_id: &str) -> R<Value> {
        let v = self.item(item_id)?["UserData"].clone();
        Ok(if v.is_null() { json!({}) } else { v })
    }
    pub fn item(&self, item_id: &str) -> R<Value> {
        self.http.get(&format!("/Users/{}/Items/{item_id}", self.user_id()?), &[])
    }
    pub fn poster(&self, item_id: &str) -> R<Vec<u8>> {
        self.http.bytes(&format!("/Items/{item_id}/Images/Primary"), &[("maxWidth", "600".into())])
    }

    /// Returns (access_token, user_id).
    pub fn authenticate(http: &dyn JfHttp, username: &str, password: &str) -> R<(String, String)> {
        let host = std::fs::read_to_string("/proc/sys/kernel/hostname").unwrap_or_default().trim().to_string();
        let auth = format!("MediaBrowser Client=\"mediator\", Device=\"mediator\", DeviceId=\"mediator-{host}\", Version=\"0.1\"");
        let res = http.post("/Users/AuthenticateByName", Some(&json!({"Username": username, "Pw": password})), &[], &[("X-Emby-Authorization", auth)])?;
        match res {
            Some(r) if r.get("AccessToken").is_some() => Ok((s(&r, "AccessToken").into(), s(&r["User"], "Id").into())),
            _ => err("login failed"),
        }
    }
}

// ---- playing ----

/// A private mpv config file carrying the auth header, so the token never appears in argv, in the
/// stream URL, or in anything we store. Pass it as `--include=PATH`; delete after.
pub fn write_mpv_auth(token: &str) -> std::io::Result<std::path::PathBuf> {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    let base = std::env::var("XDG_RUNTIME_DIR").ok().filter(|v| !v.is_empty()).map(std::path::PathBuf::from).unwrap_or_else(std::env::temp_dir);
    let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().subsec_nanos();
    for n in 0..100u32 {
        let path = base.join(format!("mediator-jf-{}-{}-{}.conf", std::process::id(), nanos, n));
        match std::fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&path) {
            Ok(mut f) => {
                writeln!(f, "http-header-fields=\"X-Emby-Token: {token}\"")?;
                return Ok(path);
            }
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
    Err(std::io::Error::new(std::io::ErrorKind::AlreadyExists, "no free temp name"))
}

/// Mirror a manual watched/unwatched mark onto the server. Returns an error message, or None.
pub fn push_marks(cfg: &JellyfinConfig, entries: &[Entry], watched: bool, client: Option<&Jellyfin>) -> Option<String> {
    let items: Vec<&Entry> = entries.iter().filter(|e| !e.remote_id.is_empty()).collect();
    if items.is_empty() {
        return None;
    }
    let owned;
    let client = match client {
        Some(c) => c,
        None => {
            owned = Jellyfin::with_http(cfg, Box::new(Http::new(&cfg.url, &cfg.token).with_timeout(6.0)), cache_dir(), Box::new(crate::state::now));
            &owned
        }
    };
    for e in items {
        if let Err(x) = client.report(&e.remote_id, 0.0, 0.0, watched) {
            return Some(format!("saved locally, but could not update Jellyfin: {x}"));
        }
    }
    None
}

/// Reports watch state to the server without ever stalling or breaking playback.
pub struct Reporter<'a> {
    client: &'a Jellyfin,
    by_path: HashMap<String, String>, // path -> remote id
    failures: Cell<u32>,
    last: RefCell<HashMap<String, (i64, bool)>>,
}
impl<'a> Reporter<'a> {
    pub fn new(client: &'a Jellyfin, entries: &[Entry]) -> Reporter<'a> {
        Reporter { client, by_path: entries.iter().map(|e| (e.path.clone(), e.remote_id.clone())).collect(), failures: Cell::new(0), last: RefCell::new(HashMap::new()) }
    }
    pub fn report(&self, path: &str, position: f64, duration: f64, watched: bool) {
        let Some(id) = self.by_path.get(path).filter(|i| !i.is_empty()) else { return };
        let state = (position.round() as i64, watched);
        if self.last.borrow().get(path) == Some(&state) {
            return;
        }
        if self.failures.get() >= 2 && !watched {
            return; // server looks unreachable; only try again when a file finishes
        }
        match self.client.report(id, position, duration, watched) {
            Ok(()) => {
                self.failures.set(0);
                self.last.borrow_mut().insert(path.into(), state);
            }
            Err(_) => self.failures.set(self.failures.get() + 1),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timestamps_with_seven_digits_parse() {
        let t = parse_when(Some("2024-03-05T10:20:30.1234567Z"));
        assert!((t - 1709634030.123456).abs() < 1e-3, "{t}");
        assert_eq!(parse_when(Some("1970-01-02T00:00:00+01:00")), 82800.0);
        assert_eq!(parse_when(Some("nope")), 0.0);
        assert_eq!(parse_when(None), 0.0);
    }

    #[test]
    fn movies_and_series_become_titles() {
        let series = vec![json!({"Id": "s1", "Name": "Show", "ProductionYear": 2020})];
        let items = vec![
            json!({"Id": "e2", "SeriesId": "s1", "ParentIndexNumber": 1, "IndexNumber": 2, "Name": "Episode 2", "RunTimeTicks": 6000000000i64}),
            json!({"Id": "e1", "SeriesId": "s1", "ParentIndexNumber": 1, "IndexNumber": 1, "Name": "Pilot"}),
            json!({"Id": "x", "SeriesId": "s1", "ParentIndexNumber": 0, "IndexNumber": 1, "Name": "Special"}),
            json!({"Id": "orphan", "SeriesId": "nope"}),
        ];
        let lib = build_titles("shows", "http://jf/", &series, &items);
        assert_eq!(lib.titles.len(), 1);
        let t = &lib.titles[0];
        assert_eq!(t.id, "jellyfin/shows/show-2020");
        let paths: Vec<_> = t.entries.iter().map(|e| e.remote_id.as_str()).collect();
        assert_eq!(paths, ["x", "e1", "e2"]);
        assert_eq!(t.entries[0].kind, "special");
        assert_eq!(t.entries[2].name, ""); // "Episode 2" is a generic name
        assert_eq!(t.entries[1].path, "http://jf/Videos/e1/stream?Static=true");
        let m = build_titles("movies", "http://jf", &[], &[json!({"Id": "m", "Name": "Film", "ProductionYear": 1999})]);
        assert_eq!(m.titles[0].id, "jellyfin/movies/film-1999");
    }

    struct Fake;
    impl JfHttp for Fake {
        fn get(&self, path: &str, _: &[(&str, String)]) -> R<Value> {
            err(format!("cannot reach {path}"))
        }
        fn post(&self, p: &str, _: Option<&Value>, _: &[(&str, String)], _: &[(&str, String)]) -> R<Option<Value>> {
            err(format!("HTTP 500 for POST {p}"))
        }
        fn bytes(&self, p: &str, _: &[(&str, String)]) -> R<Vec<u8>> {
            err(p)
        }
    }

    #[test]
    fn offline_listing_falls_back_to_the_cache() {
        let d = tempfile::tempdir().unwrap();
        let mut cfg = crate::config::Config::default().jellyfin;
        cfg.url = "http://jf".into();
        cfg.user_id = "u".into();
        cfg.libraries.insert("movies".into(), "Films".into());
        let c = Jellyfin::with_http(&cfg, Box::new(Fake), d.path().to_path_buf(), Box::new(|| 10_000.0));
        assert!(c.library("movies", false, false).is_err());
        let data = json!({"v": 2, "fetched": 0, "url": "http://jf", "user": "u", "series": [], "items": [trim(&json!({"Id": "m", "Name": "Film"}))]});
        std::fs::write(d.path().join("movies.json"), data.to_string()).unwrap();
        let lib = c.library("movies", false, false).unwrap();
        assert!(lib.stale);
        assert_eq!(lib.titles.len(), 1);
    }

    #[test]
    fn auth_file_is_private() {
        use std::os::unix::fs::PermissionsExt;
        let p = write_mpv_auth("tok").unwrap();
        assert_eq!(std::fs::metadata(&p).unwrap().permissions().mode() & 0o777, 0o600);
        assert_eq!(std::fs::read_to_string(&p).unwrap(), "http-header-fields=\"X-Emby-Token: tok\"\n");
        std::fs::remove_file(p).unwrap();
    }
}
