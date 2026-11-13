//! Poster images for titles (port of `mediator/posters.py`) and the metadata HTTP client.
//! `find()` never touches the network: a poster already on disk is looked up in order: mediator's
//! own cache, artwork next to the media, then the old bash mediator's cache. `fetch()` fills the
//! cache from Jikan (anime), AniList, TVmaze (shows) and Cinemeta (movies and shows).
use crate::catalog::{splitext, Title};
use crate::parse::{norm_key, rx, VIDEO_EXTS};
use md5::{Digest as _, Md5};
use serde_json::{json, Map, Value};
use sha2::Sha256;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

pub const IMAGE_EXTS: [&str; 4] = [".jpg", ".jpeg", ".png", ".webp"];
pub const ART_NAMES: [&str; 6] = ["poster", "folder", "cover", "thumb", "thumbnail", "show"];
pub const MISS_RETRY_DAYS: f64 = 14.0;
pub const USER_AGENT: &str = "mediator/0.1 (local media browser)";
pub const HOST_DOWN_SECONDS: f64 = 300.0;

pub fn cache_root() -> PathBuf {
    crate::config::cache_dir()
}
pub fn cache_dir() -> PathBuf {
    cache_root().join("posters")
}
pub fn image_cache_dir() -> PathBuf {
    cache_root().join("images")
}
pub fn legacy_dir() -> PathBuf {
    crate::config::expand_user("~/.local/share/mediator")
}

pub fn slug(title_id: &str) -> String {
    rx(r"[^A-Za-z0-9._-]+").replace_all(&title_id.replace('/', "__"), "_").into_owned()
}

/// Network trouble. Distinct from "the service has no such title".
#[derive(Debug, Clone, PartialEq)]
pub struct HttpFail(pub String);
impl std::fmt::Display for HttpFail {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for HttpFail {}

/// Injectable transport so every lookup branch is testable. `None` means "no such thing" (404).
pub trait Http {
    fn json(&self, url: &str) -> Result<Option<Value>, HttpFail>;
    fn post_json(&self, url: &str, payload: &Value) -> Result<Option<Value>, HttpFail>;
    fn bytes(&self, url: &str) -> Result<Vec<u8>, HttpFail>;
    /// `json` for several URLs, in the order given (the real transport asks for them together).
    fn json_many(&self, urls: &[String]) -> Vec<Result<Option<Value>, HttpFail>> {
        urls.iter().map(|u| self.json(u)).collect()
    }
}

// ---- remembering hosts that are down ----

fn hosts_file() -> PathBuf {
    cache_root().join("hosts-down.json")
}
fn host_of(url: &str) -> String {
    if url.contains("://") { url.split('/').nth(2).unwrap_or(url).to_string() } else { url.to_string() }
}
fn load_down() -> Map<String, Value> {
    let now = crate::state::now();
    match crate::fileio::read_json(&hosts_file()) {
        Value::Object(m) => m.into_iter().filter(|(_, v)| v.as_f64().map(|t| t > now).unwrap_or(false)).collect(),
        _ => Map::new(),
    }
}
fn host_is_down(url: &str) -> bool {
    load_down().contains_key(&host_of(url))
}
fn mark_host(url: &str, ok: bool) {
    let host = host_of(url);
    let mut down = load_down();
    if ok && !down.contains_key(&host) {
        return;
    }
    if ok {
        down.remove(&host);
    } else {
        down.insert(host, json!(crate::state::now() + HOST_DOWN_SECONDS));
    }
    let _ = crate::fileio::atomic_write_text(&hosts_file(), &Value::Object(down).to_string(), 0o644);
}

/// A host that timed out or refused is not asked again for a while (see `HOST_DOWN_SECONDS`).
pub struct RealHttp {
    pub timeout: f64,
}

impl RealHttp {
    pub fn new(timeout: f64) -> Self {
        RealHttp { timeout }
    }
    fn timeout_for(&self, url: &str) -> f64 {
        if host_of(url) == "api.jikan.moe" { self.timeout.min(5.0) } else { self.timeout }
    }
    fn call(&self, url: &str, payload: Option<&Value>) -> Result<Option<Vec<u8>>, HttpFail> {
        if host_is_down(url) {
            return Err(HttpFail(format!("{} is not answering (skipped for now)", host_of(url))));
        }
        let body = payload.map(|p| p.to_string());
        let mut req = crate::http::Request::get(url).agent(USER_AGENT).timeout(self.timeout_for(url));
        if let Some(b) = &body {
            req = req.header("Content-Type", "application/json").header("Accept", "application/json").post(b.as_bytes());
        }
        match req.send() {
            Ok(b) => {
                mark_host(url, true);
                Ok(Some(b))
            }
            Err(crate::http::HttpError::Status(c)) => {
                mark_host(url, true); // the host answered
                if c == 404 { Ok(None) } else { Err(HttpFail(format!("HTTP {c} for {url}"))) }
            }
            Err(e) => {
                mark_host(url, false);
                Err(HttpFail(format!("{} for {url}", e.describe())))
            }
        }
    }
}

impl Http for RealHttp {
    fn json(&self, url: &str) -> Result<Option<Value>, HttpFail> {
        match self.call(url, None)? {
            None => Ok(None),
            Some(b) => serde_json::from_slice(&b).map(Some).map_err(|_| HttpFail(format!("bad JSON from {url}"))),
        }
    }
    fn post_json(&self, url: &str, payload: &Value) -> Result<Option<Value>, HttpFail> {
        match self.call(url, Some(payload))? {
            None => Ok(None),
            Some(b) => serde_json::from_slice(&b).map(Some).map_err(|_| HttpFail(format!("bad JSON from {url}"))),
        }
    }
    fn bytes(&self, url: &str) -> Result<Vec<u8>, HttpFail> {
        self.call(url, None)?.ok_or_else(|| HttpFail(format!("404 for {url}")))
    }
    fn json_many(&self, urls: &[String]) -> Vec<Result<Option<Value>, HttpFail>> {
        let mut out = Vec::with_capacity(urls.len());
        for chunk in urls.chunks(4) {
            std::thread::scope(|scope| {
                let handles: Vec<_> = chunk.iter().map(|u| scope.spawn(move || self.json(u))).collect();
                for h in handles {
                    out.push(h.join().unwrap_or_else(|_| Err(HttpFail("lookup failed".into()))));
                }
            });
        }
        out
    }
}

/// `urllib.parse.urlencode` over the non-empty params.
pub fn q(params: &[(&str, String)]) -> String {
    use percent_encoding::{utf8_percent_encode, AsciiSet, NON_ALPHANUMERIC};
    const S: &AsciiSet = &NON_ALPHANUMERIC.remove(b'_').remove(b'.').remove(b'-').remove(b'~');
    let enc = |s: &str| utf8_percent_encode(s, S).to_string().replace("%20", "+");
    params.iter().filter(|(_, v)| !v.is_empty()).map(|(k, v)| format!("{}={}", enc(k), enc(v))).collect::<Vec<_>>().join("&")
}

// ---- finding what is already on disk ----

fn cached(title: &Title, dir: &Path) -> Option<PathBuf> {
    let base = dir.join(slug(&title.id));
    IMAGE_EXTS.iter().map(|e| PathBuf::from(format!("{}{e}", base.display()))).find(|p| p.is_file())
}

fn first_art(folder: &Path, extra: &[String]) -> Option<PathBuf> {
    let names: Vec<String> = std::fs::read_dir(folder).ok()?.flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect();
    let by_lower: HashMap<String, &String> = names.iter().map(|n| (n.to_lowercase(), n)).collect();
    let stems: Vec<String> = ART_NAMES.iter().map(|s| s.to_string()).chain(extra.iter().cloned()).map(|s| s.to_lowercase()).collect();
    for stem in &stems {
        for ext in IMAGE_EXTS {
            if let Some(hit) = by_lower.get(&format!("{stem}{ext}")) {
                return Some(folder.join(hit));
            }
        }
    }
    names.iter().find(|n| { let l = n.to_lowercase(); IMAGE_EXTS.iter().any(|e| l.ends_with(&format!("-poster{e}"))) }).map(|n| folder.join(n))
}

fn local_art(title: &Title) -> Option<PathBuf> {
    if title.source != "local" {
        return None;
    }
    let mut folders: Vec<PathBuf> = vec![];
    for e in &title.entries {
        let root = &e.path[..e.path.len().saturating_sub(e.rel.len())];
        let parts: Vec<&str> = e.rel.split('/').collect();
        if parts.len() < 2 {
            let stem = splitext(parts[parts.len() - 1]).0;
            for ext in IMAGE_EXTS {
                for cand in [format!("{stem}{ext}"), format!("{stem}-poster{ext}")] {
                    let p = Path::new(root).join(cand);
                    if p.is_file() {
                        return Some(p);
                    }
                }
            }
            continue;
        }
        let folder = if title.lib == "movies" { Path::new(&e.path).parent().unwrap().to_path_buf() } else { Path::new(root).join(parts[0]) };
        if !folders.contains(&folder) {
            folders.push(folder);
        }
    }
    for folder in folders {
        if title.lib == "movies" {
            let Ok(rd) = std::fs::read_dir(&folder) else { continue };
            let vids = rd.flatten().filter(|e| VIDEO_EXTS.contains(&splitext(&e.file_name().to_string_lossy()).1.to_lowercase().as_str())).count();
            if vids > 1 {
                continue;
            }
        }
        let base = folder.file_name().map(|n| n.to_string_lossy().to_lowercase()).unwrap_or_default();
        if let Some(hit) = first_art(&folder, &[base]) {
            return Some(hit);
        }
    }
    None
}

fn legacy(title: &Title, dir: &Path) -> Option<PathBuf> {
    if title.source != "local" {
        return None;
    }
    let fallback = std::fs::read(dir.join("cover.jpg")).ok().map(|b| crate::fileio::hex(&Md5::digest(&b)));
    let lib_dir = dir.join(&title.lib);
    let want = norm_key(&title.name);
    for e in std::fs::read_dir(lib_dir).ok()?.flatten() {
        let name = e.file_name().to_string_lossy().into_owned();
        let (stem, ext) = splitext(&name);
        if !IMAGE_EXTS.contains(&ext.to_lowercase().as_str()) || norm_key(stem) != want {
            continue;
        }
        let data = std::fs::read(e.path()).ok()?;
        if fallback.as_deref() == Some(crate::fileio::hex(&Md5::digest(&data)).as_str()) || !looks_like_image(&data) {
            continue; // the generic placeholder the old script wrote, or not an image
        }
        return Some(e.path());
    }
    None
}

pub fn find(title: &Title) -> Option<PathBuf> {
    find_in(title, &cache_dir(), &legacy_dir())
}
pub fn find_in(title: &Title, cache: &Path, legacy_dir: &Path) -> Option<PathBuf> {
    cached(title, cache).or_else(|| local_art(title)).or_else(|| legacy(title, legacy_dir))
}
pub fn source_of(title: &Title, cache: &Path, legacy_dir: &Path) -> &'static str {
    if cached(title, cache).is_some() {
        "cache"
    } else if local_art(title).is_some() {
        "local"
    } else if legacy(title, legacy_dir).is_some() {
        "legacy"
    } else {
        "none"
    }
}

// ---- images ----

pub fn looks_like_image(d: &[u8]) -> bool {
    d.len() >= 2048 && (d.starts_with(&[0xff, 0xd8, 0xff]) || d.starts_with(b"\x89PNG\r\n\x1a\n") || (d.starts_with(b"RIFF") && &d[8..12] == b"WEBP"))
}
pub fn ext_for(d: &[u8]) -> &'static str {
    if d.starts_with(b"\x89PNG\r\n\x1a\n") { ".png" } else if d.starts_with(b"RIFF") { ".webp" } else { ".jpg" }
}

/// Write `data` as the cached poster for `title` (atomic). Returns the path.
pub fn store(title: &Title, data: &[u8], cache: &Path) -> Result<PathBuf, HttpFail> {
    if !looks_like_image(data) {
        return Err(HttpFail("not a usable image (too small or not JPEG/PNG/WebP)".into()));
    }
    let base = cache.join(slug(&title.id));
    for ext in IMAGE_EXTS {
        let _ = std::fs::remove_file(format!("{}{ext}", base.display()));
    }
    let path = PathBuf::from(format!("{}{}", base.display(), ext_for(data)));
    write_bytes(&path, data).map_err(|e| HttpFail(e.to_string()))?;
    Ok(path)
}

fn write_bytes(path: &Path, data: &[u8]) -> std::io::Result<()> {
    use std::io::Write;
    if let Some(d) = path.parent() {
        std::fs::create_dir_all(d)?;
    }
    let tmp = PathBuf::from(format!("{}.tmp{}", path.display(), std::process::id()));
    std::fs::File::create(&tmp)?.write_all(data)?;
    std::fs::rename(tmp, path)
}

pub fn image_key(url: &str) -> String {
    crate::fileio::hex(&Sha256::digest(url.as_bytes()))
}
fn image_path(url: &str, dir: &Path) -> Option<PathBuf> {
    let base = dir.join(image_key(url));
    IMAGE_EXTS.iter().map(|e| PathBuf::from(format!("{}{e}", base.display()))).find(|p| p.is_file())
}
pub fn load_image_index(dir: &Path) -> std::collections::BTreeMap<String, String> {
    match crate::fileio::read_json(&dir.join("index.json")) {
        Value::Object(m) => m.into_iter().map(|(k, v)| (k, v.as_str().map(String::from).unwrap_or_else(|| v.to_string()))).collect(),
        _ => Default::default(),
    }
}
pub fn save_image_index(index: &std::collections::BTreeMap<String, String>, dir: &Path) {
    let _ = crate::fileio::atomic_write_text(&dir.join("index.json"), &serde_json::to_string(index).unwrap(), 0o644);
}

/// Download a remote cover once and return its stable local path (reused without a request).
pub fn cache_image(url: &str, http: &dyn Http, dir: &Path, update_index: bool) -> Result<PathBuf, HttpFail> {
    let text = url.trim();
    let low = text.to_lowercase();
    if !(low.starts_with("http://") || low.starts_with("https://")) {
        return Err(HttpFail("only http(s) image URLs can be cached".into()));
    }
    if let Some(existing) = image_path(text, dir) {
        if update_index {
            let mut index = load_image_index(dir);
            let e = existing.to_string_lossy().into_owned();
            if index.get(text) != Some(&e) {
                index.insert(text.into(), e);
                save_image_index(&index, dir);
            }
        }
        return Ok(existing);
    }
    let data = http.bytes(text)?;
    if !looks_like_image(&data) {
        return Err(HttpFail("not a usable image (too small or not JPEG/PNG/WebP)".into()));
    }
    let path = dir.join(format!("{}{}", image_key(text), ext_for(&data)));
    write_bytes(&path, &data).map_err(|e| HttpFail(e.to_string()))?;
    if update_index {
        let mut index = load_image_index(dir);
        index.insert(text.into(), path.to_string_lossy().into_owned());
        save_image_index(&index, dir);
    }
    Ok(path)
}

/// Cache a batch of covers and write the URL → path index once.
pub fn cache_images(urls: &[String], http: &dyn Http, dir: &Path) -> (std::collections::BTreeMap<String, String>, std::collections::BTreeMap<String, String>) {
    let mut index = load_image_index(dir);
    let mut errors = std::collections::BTreeMap::new();
    let images: std::collections::BTreeMap<String, String>;
    let mut images_map: std::collections::BTreeMap<String, String> = std::collections::BTreeMap::new();
    for raw in urls {
        let url = raw.trim();
        if url.is_empty() {
            continue;
        }
        match cache_image(url, http, dir, false) {
            Ok(p) => {
                let p = p.to_string_lossy().into_owned();
                images_map.insert(url.into(), p.clone());
                index.insert(url.into(), p);
            }
            Err(e) => {
                errors.insert(url.to_string(), e.0);
            }
        }
    }
    images = images_map;
    save_image_index(&index, dir);
    (images, errors)
}

// ---- fetching ----

/// candidates: (names, year, image_url). Prefer exact name + year, then exact name, then year.
pub fn best<T: Clone>(cands: &[(Vec<Option<String>>, Option<i64>, T, bool)], title: &Title) -> Option<T> {
    let want = norm_key(&title.name);
    let mut top: Option<((bool, bool, bool, i64), T)> = None;
    for (i, (names, year, val, usable)) in cands.iter().enumerate() {
        if !usable {
            continue;
        }
        let nk: Vec<String> = names.iter().flatten().filter(|n| !n.is_empty()).map(|n| norm_key(n)).collect();
        let key = (nk.iter().any(|n| *n == want), title.year.map(|y| Some(y as i64) == *year).unwrap_or(false), nk.iter().any(|n| n.starts_with(&want)), -(i as i64));
        if top.as_ref().map(|(k, _)| key > *k).unwrap_or(true) {
            top = Some((key, val.clone()));
        }
    }
    top.map(|(_, v)| v)
}

fn s(v: &Value) -> Option<String> {
    v.as_str().map(String::from)
}
fn jikan_year(a: &Value) -> Option<i64> {
    a["year"].as_i64().filter(|&y| y != 0).or_else(|| a["aired"]["prop"]["from"]["year"].as_i64())
}
static JIKAN_NEXT: std::sync::Mutex<Option<std::time::Instant>> = std::sync::Mutex::new(None);

/// Wait for this caller's turn at Jikan, which allows about 3 requests a second *in total*:
/// every thread shares one clock, so enriching several titles at once stays inside the limit.
pub fn jikan_pace(secs: f64) {
    let step = std::time::Duration::from_secs_f64(secs);
    let wait = {
        let mut next = JIKAN_NEXT.lock().unwrap();
        let now = std::time::Instant::now();
        let slot = next.map_or(now, |n| n.max(now));
        *next = Some(slot + step);
        slot - now
    };
    std::thread::sleep(wait);
}
fn sleep_for(secs: f64) {
    jikan_pace(secs);
}

pub fn from_jikan(title: &Title, http: &dyn Http, sleep: &dyn Fn(f64)) -> Result<Option<String>, HttpFail> {
    sleep(0.45);
    let data = http.json(&format!("https://api.jikan.moe/v4/anime?{}", q(&[("q", title.name.clone()), ("limit", "10".into()), ("sfw", "true".into())])))?;
    let mut cands = vec![];
    for a in data.as_ref().and_then(|d| d["data"].as_array()).cloned().unwrap_or_default() {
        let mut names = vec![s(&a["title"]), s(&a["title_english"]), s(&a["title_japanese"])];
        names.extend(a["titles"].as_array().cloned().unwrap_or_default().iter().map(|t| s(&t["title"])));
        let url = s(&a["images"]["jpg"]["large_image_url"]);
        cands.push((names, jikan_year(&a), url.clone().unwrap_or_default(), url.map(|u| !u.is_empty()).unwrap_or(false)));
    }
    Ok(best(&cands, title))
}

const ANILIST_POSTER_Q: &str = "query($q: String) { Page(perPage: 10) { media(search: $q, type: ANIME) {\n  title { romaji english native } synonyms seasonYear coverImage { extraLarge large } } } }";

/// Second source for anime, for when Jikan is down or has no match.
pub fn from_anilist(title: &Title, http: &dyn Http) -> Result<Option<String>, HttpFail> {
    let data = http.post_json("https://graphql.anilist.co", &json!({"query": ANILIST_POSTER_Q, "variables": {"q": title.name}}))?;
    let mut cands = vec![];
    for m in data.as_ref().and_then(|d| d["data"]["Page"]["media"].as_array()).cloned().unwrap_or_default() {
        let t = &m["title"];
        let mut names = vec![s(&t["romaji"]), s(&t["english"]), s(&t["native"])];
        names.extend(m["synonyms"].as_array().cloned().unwrap_or_default().iter().map(s));
        let url = s(&m["coverImage"]["extraLarge"]).filter(|u| !u.is_empty()).or_else(|| s(&m["coverImage"]["large"]));
        cands.push((names, m["seasonYear"].as_i64(), url.clone().unwrap_or_default(), url.map(|u| !u.is_empty()).unwrap_or(false)));
    }
    Ok(best(&cands, title))
}

pub fn premiered_year(s: &Value) -> Option<i64> {
    s["premiered"].as_str().filter(|p| !p.is_empty()).and_then(|p| p.get(..4)).and_then(|y| y.parse().ok())
}

pub fn from_tvmaze(title: &Title, http: &dyn Http) -> Result<Option<String>, HttpFail> {
    let data = http.json(&format!("https://api.tvmaze.com/search/shows?{}", q(&[("q", title.name.clone())])))?;
    let mut cands = vec![];
    for hit in data.as_ref().and_then(|d| d.as_array()).cloned().unwrap_or_default() {
        let sh = &hit["show"];
        let url = s(&sh["image"]["original"]).filter(|u| !u.is_empty()).or_else(|| s(&sh["image"]["medium"]));
        cands.push((vec![s(&sh["name"])], premiered_year(sh), url.clone().unwrap_or_default(), url.map(|u| !u.is_empty()).unwrap_or(false)));
    }
    Ok(best(&cands, title))
}

pub fn year_value(v: &Value) -> Option<i64> {
    v.as_i64().filter(|&y| y != 0)
}

pub fn year_of(m: &Value) -> Option<i64> {
    let t = match (&m["year"], &m["releaseInfo"]) {
        (Value::Null, r) => r.to_string(),
        (y, _) => y.to_string(),
    };
    let t = if m["year"].is_null() && m["releaseInfo"].is_null() { String::new() } else { t.trim_matches('"').to_string() };
    rx(r"\A\d{4}").find(&t).ok().flatten().and_then(|x| x.as_str().parse().ok())
}

pub fn from_cinemeta(title: &Title, http: &dyn Http) -> Result<Option<String>, HttpFail> {
    let kind = if title.lib == "movies" { "movie" } else { "series" };
    let enc = percent_encoding::utf8_percent_encode(&title.name, percent_encoding::NON_ALPHANUMERIC).to_string().replace("%2E", ".").replace("%2D", "-").replace("%5F", "_").replace("%7E", "~");
    let data = http.json(&format!("https://v3-cinemeta.strem.io/catalog/{kind}/top/search={enc}.json"))?;
    let mut cands = vec![];
    for m in data.as_ref().and_then(|d| d["metas"].as_array()).cloned().unwrap_or_default() {
        let url = s(&m["poster"]).unwrap_or_default().replace("/poster/small/", "/poster/large/");
        cands.push((vec![s(&m["name"])], year_of(&m), url.clone(), !url.is_empty()));
    }
    Ok(best(&cands, title))
}

#[derive(Debug, Clone, PartialEq)]
pub struct FetchResult {
    pub status: &'static str, // fetched | have | miss | skipped | error
    pub detail: String,
    pub path: Option<PathBuf>,
}
fn fr(status: &'static str, detail: impl Into<String>, path: Option<PathBuf>) -> FetchResult {
    FetchResult { status, detail: detail.into(), path }
}

fn load_misses(cache: &Path) -> Map<String, Value> {
    match crate::fileio::read_json(&cache.join("misses.json")) {
        Value::Object(m) => m,
        _ => Map::new(),
    }
}
fn save_misses(cache: &Path, m: &Map<String, Value>) {
    let _ = crate::fileio::atomic_write_text(&cache.join("misses.json"), &Value::Object(m.clone()).to_string(), 0o644);
}

pub struct FetchOpts<'a> {
    pub refresh: bool,
    pub cache: PathBuf,
    pub legacy: PathBuf,
    pub now: f64,
    pub sleep: &'a dyn Fn(f64),
}
impl Default for FetchOpts<'_> {
    fn default() -> Self {
        FetchOpts { refresh: false, cache: cache_dir(), legacy: legacy_dir(), now: crate::state::now(), sleep: &sleep_for }
    }
}

/// `jellyfin_poster`: the server's own artwork bytes for the item, when a client is configured.
pub fn fetch(title: &Title, http: &dyn Http, jellyfin_poster: Option<&dyn Fn(&str) -> Result<Vec<u8>, String>>, o: &FetchOpts) -> FetchResult {
    let cache = &o.cache;
    if !o.refresh {
        if let Some(have) = find_in(title, cache, &o.legacy) {
            return fr("have", source_of(title, cache, &o.legacy), Some(have));
        }
        if let Some(t) = load_misses(cache).get(&title.id).and_then(|v| v.as_f64()).filter(|t| *t != 0.0) {
            if o.now - t < MISS_RETRY_DAYS * 86400.0 {
                return fr("skipped", "not found earlier; --refresh to retry", None);
            }
        }
    }
    if title.source == "jellyfin" {
        let (Some(j), false) = (jellyfin_poster, title.remote_id.is_empty()) else { return fr("skipped", "Jellyfin is not configured", None) };
        return match j(&title.remote_id) {
            Ok(b) => match store(title, &b, cache) {
                Ok(p) => fr("fetched", "jellyfin", Some(p)),
                Err(e) => fr("error", e.0, None),
            },
            Err(e) => fr(if e.contains("404") { "miss" } else { "error" }, e, None),
        };
    }
    let mut tried: Vec<&str> = vec![];
    let mut url: Option<String> = None;
    let res: Result<Option<()>, HttpFail> = (|| {
        if title.lib == "anime" {
            tried.push("jikan");
            url = from_jikan(title, http, o.sleep).unwrap_or(None); // Jikan is down; AniList has the same covers
            if url.is_none() {
                tried.push("anilist");
                url = from_anilist(title, http)?;
            }
        } else if title.lib == "shows" {
            tried.push("tvmaze");
            url = from_tvmaze(title, http)?;
        }
        if url.is_none() && (title.lib == "movies" || title.lib == "shows") {
            tried.push("cinemeta");
            url = from_cinemeta(title, http)?;
        }
        Ok(None)
    })();
    if let Err(e) = res {
        return fr("error", e.0, None);
    }
    let miss = |why: String| {
        let mut m = load_misses(cache);
        m.insert(title.id.clone(), json!(o.now));
        save_misses(cache, &m);
        fr("miss", why, None)
    };
    let Some(url) = url else {
        if tried.is_empty() {
            return fr("skipped", "no source for this library", None);
        }
        return miss(format!("no poster at {}", tried.join("/")));
    };
    let data = match http.bytes(&url) {
        Ok(d) => d,
        Err(e) if e.0.starts_with("404") => return miss(format!("{} listed a poster that no longer exists", tried.last().unwrap())),
        Err(e) => return fr("error", e.0, None),
    };
    let path = match store(title, &data, cache) {
        Ok(p) => p,
        Err(e) => return fr("error", e.0, None),
    };
    let mut m = load_misses(cache);
    if m.remove(&title.id).is_some() {
        save_misses(cache, &m);
    }
    fr("fetched", tried.last().copied().unwrap_or(""), Some(path))
}
