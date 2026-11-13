//! HiAnime provider client: search, episode list and source resolution by the provider's own
//! stable ids. Owns the HTTP and HTML boundary; callers can inject `fetch` for tests.
use crate::html::{self, attr, classes, Attrs, Handler};
use crate::parse::rx;
use base64::Engine;
use percent_encoding::{percent_decode_str, utf8_percent_encode, AsciiSet, NON_ALPHANUMERIC};
use serde_json::{json, Value};
use std::path::PathBuf;
use std::time::SystemTime;

pub const BASE_URL: &str = "https://hianime.at";
pub const USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
const EMBED_KEY: &[u8] = b"otaku-embed-v1";
pub const EPISODE_TTL: f64 = 1800.0;

/// A user-facing provider or source resolution error.
#[derive(Debug, Clone, PartialEq)]
pub struct ProviderError(pub String);
impl std::fmt::Display for ProviderError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for ProviderError {}
impl From<crate::errors::StreamError> for ProviderError {
    fn from(e: crate::errors::StreamError) -> Self {
        ProviderError(e.0)
    }
}
fn perr(s: impl Into<String>) -> ProviderError {
    ProviderError(s.into())
}

pub type Headers = Vec<(String, String)>;
pub type Fetch = Box<dyn Fn(&str, &Headers) -> Result<String, ProviderError> + Send + Sync>;

fn default_fetch(url: &str, headers: &Headers) -> Result<String, ProviderError> {
    let mut r = crate::http::Request::get(url).timeout(15.0);
    for (k, v) in headers {
        if k != "User-Agent" {
            r = r.header(k, v);
        }
    }
    r.agent(headers.iter().find(|(k, _)| k == "User-Agent").map(|(_, v)| v.as_str()).unwrap_or(USER_AGENT))
        .text()
        .map_err(|e| {
            let host = url.split("://").nth(1).and_then(|r| r.split('/').next()).filter(|h| !h.is_empty()).unwrap_or("the anime provider");
            perr(format!("{host}: {}", e.describe()))
        })
}

#[derive(Debug, Clone, PartialEq)]
pub struct Source {
    pub url: String,
    pub referer: String,
    pub subtitles: String,
    pub quality: String,
}

impl Source {
    pub fn new(url: impl Into<String>) -> Source {
        Source { url: url.into(), referer: String::new(), subtitles: String::new(), quality: "best".into() }
    }
}

const VOID: [&str; 14] = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"];

type Item = std::collections::BTreeMap<String, String>;

/// The main result cards, ignoring repeated sidebar cards.
#[derive(Default)]
struct SearchParser {
    depth: usize,
    item_depth: Option<usize>,
    item: Option<Item>,
    results: Vec<Item>,
    capture: Option<&'static str>,
    parts: String,
    sidebar: bool,
}

impl SearchParser {
    fn provider_id(href: &str, fallback: Option<&str>) -> String {
        let dec = |s: &str| percent_decode_str(s).decode_utf8_lossy().into_owned();
        if let Some(c) = rx(r"/watch/([^/?#]+)").captures(href).ok().flatten() {
            return dec(&c[1]);
        }
        if let Some(c) = rx(r"/([^/?#]+)-([0-9]+)(?:[/?#]|$)").captures(href).ok().flatten() {
            return dec(&format!("{}-{}", &c[1], &c[2]));
        }
        fallback.unwrap_or("").trim().to_string()
    }

    fn finish_item(&mut self) {
        if let Some(item) = self.item.take() {
            let r: Item = item.into_iter().filter(|(_, v)| !v.is_empty()).map(|(k, v)| (k, html_escape::decode_html_entities(&v).trim().to_string())).collect();
            if r.get("id").map(|v| !v.is_empty()).unwrap_or(false) && r.get("title").map(|v| !v.is_empty()).unwrap_or(false) {
                self.results.push(r);
            }
        }
        self.item_depth = None;
    }
}

impl Handler for SearchParser {
    fn start(&mut self, tag: &str, attrs: &Attrs) {
        if self.sidebar {
            return;
        }
        if attr(attrs, "id") == Some("main-sidebar") {
            self.finish_item();
            self.sidebar = true;
            return;
        }
        if !VOID.contains(&tag) {
            self.depth += 1;
        }
        let cl = classes(attrs);
        let has = |c: &str| cl.iter().any(|x| x == c);
        if tag == "div" && has("flw-item") {
            self.finish_item();
            self.item_depth = Some(self.depth);
            self.item = Some(Item::new());
        }
        let depth_item = self.item.is_some();
        if !depth_item {
            return;
        }
        let item = self.item.as_mut().unwrap();
        let a = |k: &str| attr(attrs, k).unwrap_or("");
        if tag == "img" && has("film-poster-img") {
            let src = if !a("src").is_empty() { a("src") } else { a("data-src") };
            item.insert("poster".into(), src.into());
            if !a("alt").is_empty() {
                item.entry("title".into()).or_insert_with(|| a("alt").into());
            }
        } else if tag == "a" && has("film-poster-ahref") {
            item.insert("id".into(), Self::provider_id(a("href"), attr(attrs, "data-id")));
            let t = if !a("title").is_empty() { a("title").to_string() } else { item.get("title").cloned().unwrap_or_default() };
            item.insert("title".into(), t);
        } else if (tag == "a" || tag == "h3") && has("film-name") {
            self.capture = Some("title");
            self.parts.clear();
        } else if tag == "div" && has("description") {
            self.capture = Some("description");
            self.parts.clear();
        } else if tag == "span" && has("fdi-item") {
            self.capture = Some("meta");
            self.parts.clear();
        }
    }

    fn data(&mut self, d: &str) {
        if self.capture.is_some() {
            self.parts.push_str(d);
        }
    }

    fn end(&mut self, tag: &str) {
        if self.sidebar {
            return;
        }
        if let Some(cap) = self.capture {
            if matches!(tag, "a" | "h3" | "div" | "span") {
                let text = self.parts.split_whitespace().collect::<Vec<_>>().join(" ");
                if let (Some(item), false) = (self.item.as_mut(), text.is_empty()) {
                    match cap {
                        "title" => {
                            item.insert("title".into(), text);
                        }
                        "description" => {
                            item.insert("description".into(), text);
                        }
                        _ => {
                            item.entry("meta".into()).or_insert(text);
                        }
                    }
                }
                self.capture = None;
                self.parts.clear();
            }
        }
        if self.item_depth == Some(self.depth) && tag == "div" {
            self.finish_item();
        }
        if !VOID.contains(&tag) {
            self.depth = self.depth.saturating_sub(1);
        }
    }
}

/// Read the episode list and ignore cards that belong to another show.
struct EpisodeParser {
    title_id: String,
    episodes: Vec<Value>,
    current: Option<(String, String, String)>, // id, number, title
    capture: bool,
    parts: String,
}

impl Handler for EpisodeParser {
    fn start(&mut self, tag: &str, attrs: &Attrs) {
        let cl = classes(attrs);
        let has = |c: &str| cl.iter().any(|x| x == c);
        if tag == "a" && has("ep-item") {
            let href = attr(attrs, "href").unwrap_or("");
            let path = url::Url::parse("http://x").unwrap().join(href).map(|u| u.path().to_string()).unwrap_or_default();
            if path != format!("/watch/{}", self.title_id) {
                self.current = None;
                return;
            }
            let id = attr(attrs, "data-id").unwrap_or("").trim().to_string();
            let number = attr(attrs, "data-number").unwrap_or("").trim().to_string();
            if number.is_empty() || id.is_empty() || !id.chars().all(|c| c.is_ascii_digit()) {
                self.current = None;
                return;
            }
            self.current = Some((id, number, html_escape::decode_html_entities(attr(attrs, "title").unwrap_or("")).into_owned()));
            self.parts.clear();
        } else if self.current.is_some() && tag == "div" && has("ep-name") {
            self.capture = true;
            self.parts.clear();
        }
    }
    fn data(&mut self, d: &str) {
        if self.capture {
            self.parts.push_str(d);
        }
    }
    fn end(&mut self, tag: &str) {
        if tag == "div" && self.capture {
            let title = self.parts.split_whitespace().collect::<Vec<_>>().join(" ");
            if let (false, Some(c)) = (title.is_empty(), self.current.as_mut()) {
                c.2 = title;
            }
            self.capture = false;
            self.parts.clear();
        }
        if tag == "a" {
            if let Some((id, number, title)) = self.current.take() {
                if !self.episodes.iter().any(|e| e["id"] == id.as_str()) {
                    self.episodes.push(json!({"id": id, "number": number, "title": title}));
                }
            }
            self.capture = false;
        }
    }
}

/// Find the ZokoAnime server hash for one language.
struct ServerParser {
    mode: String,
    hash: String,
}

impl Handler for ServerParser {
    fn start(&mut self, tag: &str, attrs: &Attrs) {
        if tag != "div" || !classes(attrs).iter().any(|c| c == "server-item") {
            return;
        }
        if attr(attrs, "data-type").unwrap_or("").to_lowercase() != self.mode {
            return;
        }
        let value = attr(attrs, "data-hash").unwrap_or("").trim();
        if value.is_empty() {
            return;
        }
        let name = attr(attrs, "data-server-name").unwrap_or("").to_lowercase();
        if self.hash.is_empty() || name.contains("zoko") {
            self.hash = value.into();
        }
    }
    fn end(&mut self, _: &str) {}
    fn data(&mut self, _: &str) {}
}

pub struct Provider {
    pub base_url: String,
    fetch: Fetch,
    cached: bool, // injected transports (tests) never touch the disk
}

fn cache_base() -> PathBuf {
    crate::config::cache_dir()
}

fn fresh(path: &std::path::Path, ttl: f64) -> bool {
    std::fs::metadata(path).and_then(|m| m.modified()).ok().and_then(|t| SystemTime::now().duration_since(t).ok()).map(|a| a.as_secs_f64() < ttl).unwrap_or(false)
}

fn read_list(path: &std::path::Path) -> Option<Vec<Value>> {
    serde_json::from_str::<Value>(&std::fs::read_to_string(path).ok()?).ok()?.as_array().filter(|a| !a.is_empty()).cloned()
}

fn write_cache(path: &std::path::Path, v: &[Value]) {
    let _ = crate::fileio::atomic_write_text(path, &serde_json::to_string(v).unwrap(), 0o644);
}

const QS: &AsciiSet = &NON_ALPHANUMERIC.remove(b'_').remove(b'.').remove(b'-').remove(b'~');

fn quote_plus(s: &str) -> String {
    utf8_percent_encode(s, QS).to_string().replace("%20", "+")
}
fn quote_all(s: &str) -> String {
    utf8_percent_encode(s, QS).to_string()
}

fn extract_html(raw: &str) -> String {
    match serde_json::from_str::<Value>(raw) {
        Ok(Value::Object(o)) => o.get("html").and_then(|h| h.as_str()).unwrap_or("").to_string(),
        Ok(_) => String::new(),
        Err(_) => raw.to_string(),
    }
}

impl Provider {
    pub fn new() -> Provider {
        let base = std::env::var("MEDIATOR_ANIME_PROVIDER_URL").ok().filter(|v| !v.is_empty()).unwrap_or_else(|| BASE_URL.into());
        Provider { base_url: base.trim_end_matches('/').into(), fetch: Box::new(default_fetch), cached: true }
    }

    pub fn with_fetch(base_url: &str, fetch: Fetch) -> Provider {
        Provider { base_url: base_url.trim_end_matches('/').into(), fetch, cached: false }
    }

    fn get(&self, path: &str, referer: Option<&str>) -> Result<String, ProviderError> {
        let mut h: Headers = vec![("User-Agent".into(), USER_AGENT.into()), ("Accept".into(), "text/html,application/json".into())];
        if let Some(r) = referer {
            h.push(("Referer".into(), r.into()));
        }
        (self.fetch)(&format!("{}{path}", self.base_url), &h)
    }

    fn check_response(page: &str) -> Result<(), ProviderError> {
        let lower = page.to_lowercase();
        if rx(r#"<title>\s*just a moment|cf-chl-|challenge-platform|id=["']cf-chl-|class=["'][^"']*cf-chl-"#).is_match(&lower).unwrap_or(false) {
            return Err(perr("the anime provider is behind a Cloudflare challenge, so requests are blocked from here"));
        }
        Ok(())
    }

    pub fn search(&self, query: &str) -> Result<Vec<Value>, ProviderError> {
        let text = query.trim();
        if text.is_empty() {
            return Err(perr("enter an anime title to search"));
        }
        let slug: String = rx(r"[^a-z0-9]+").replace_all(&text.to_lowercase(), "_").chars().take(80).collect();
        let path = cache_base().join("anime-search").join(format!("{slug}.json"));
        if self.cached && fresh(&path, 600.0) {
            if let Some(hit) = read_list(&path) {
                return Ok(hit);
            }
        }
        let results = self.search_online(text)?;
        if self.cached && !results.is_empty() {
            write_cache(&path, &results);
        }
        Ok(results)
    }

    fn search_online(&self, text: &str) -> Result<Vec<Value>, ProviderError> {
        let page = self.get(&format!("/search?keyword={}", quote_plus(text)), None)?;
        Self::check_response(&page)?;
        let mut p = SearchParser::default();
        html::feed(&page, &mut p);
        p.finish_item();
        let mut seen = std::collections::HashSet::new();
        let mut out = vec![];
        for r in p.results {
            if !seen.insert(r["id"].clone()) {
                continue;
            }
            let g = |k: &str| r.get(k).cloned().unwrap_or_default();
            out.push(json!({"id": r["id"], "title": if g("title").is_empty() { r["id"].clone() } else { g("title") }, "poster": g("poster"), "description": g("description")}));
        }
        Ok(out)
    }

    pub fn episodes(&self, title_id: &str) -> Result<Vec<Value>, ProviderError> {
        let title_id = title_id.trim();
        if !rx(r"\A[A-Za-z0-9][A-Za-z0-9._-]*\z").is_match(title_id).unwrap_or(false) {
            return Err(perr("invalid provider title id"));
        }
        let safe = rx(r"[^A-Za-z0-9._-]").replace_all(title_id, "_").into_owned();
        let path = cache_base().join("anime-episodes").join(format!("{safe}.json"));
        if self.cached && fresh(&path, EPISODE_TTL) {
            if let Some(d) = read_list(&path) {
                return Ok(d);
            }
        }
        let eps = self.fetch_episodes(title_id)?;
        if self.cached {
            write_cache(&path, &eps);
        }
        Ok(eps)
    }

    fn fetch_episodes(&self, title_id: &str) -> Result<Vec<Value>, ProviderError> {
        let endpoint = if rx(r"-\d+$").is_match(title_id).unwrap_or(false) { title_id.rsplit('-').next().unwrap() } else { title_id };
        let raw = self.get(&format!("/api/theme/episode/list/{}", quote_all(endpoint)), None)?;
        let page = extract_html(&raw).replace("\\/", "/");
        let mut p = EpisodeParser { title_id: title_id.into(), episodes: vec![], current: None, capture: false, parts: String::new() };
        html::feed(&page, &mut p);
        if p.episodes.is_empty() {
            return Err(perr("provider returned no episodes"));
        }
        Ok(p.episodes)
    }

    pub fn resolve(&self, title_id: &str, episode_id: &str, dub: bool, quality: &str, episodes: Option<&[Value]>) -> Result<(Source, Value), ProviderError> {
        let (title_id, episode_id) = (title_id.trim(), episode_id.trim());
        let owned;
        let episodes = match episodes {
            Some(e) => e,
            None => {
                owned = self.episodes(title_id)?;
                &owned
            }
        };
        let episode = episodes.iter().find(|e| e["id"] == episode_id).cloned().ok_or_else(|| perr("that episode does not belong to the selected anime"))?;
        let mode = if dub { "dub" } else { "sub" };
        let raw = self.get(&format!("/api/theme/episode/servers?episodeId={}", quote_all(episode_id)), None)?;
        let page = extract_html(&raw).replace("\\/", "/");
        let mut p = ServerParser { mode: mode.into(), hash: String::new() };
        html::feed(&page, &mut p);
        if p.hash.is_empty() {
            return Err(perr(format!("{mode} source is unavailable for this episode")));
        }
        let embed = base64::engine::general_purpose::STANDARD.decode(&p.hash).ok().and_then(|b| String::from_utf8(b).ok()).ok_or_else(|| perr("provider returned an invalid source"))?;
        self.resolve_embed(&embed, episode, quality)
    }

    fn resolve_embed(&self, embed: &str, episode: Value, quality: &str) -> Result<(Source, Value), ProviderError> {
        let referer = match url::Url::parse(embed) {
            Ok(u) if u.host_str().is_some() => format!("{}://{}/", u.scheme(), u.host_str().unwrap().to_string() + &u.port().map(|p| format!(":{p}")).unwrap_or_default()),
            _ => embed.to_string(),
        };
        let page = (self.fetch)(embed, &vec![("User-Agent".into(), USER_AGENT.into()), ("Referer".into(), referer.clone())])?;
        let m = rx(r#"window\.__P\s*=\s*"([^"]+)""#).captures(page.as_str()).ok().flatten().ok_or_else(|| perr("provider embed did not contain a source"))?;
        let payload: Value = (|| {
            let blob = base64::engine::general_purpose::STANDARD.decode(html_escape::decode_html_entities(&m[1]).as_bytes()).ok()?;
            let dec: Vec<u8> = blob.iter().enumerate().map(|(i, v)| v ^ EMBED_KEY[i % EMBED_KEY.len()]).collect();
            serde_json::from_slice(&dec).ok()
        })().ok_or_else(|| perr("provider returned an invalid source payload"))?;
        let master = payload["src"].as_str().unwrap_or("").to_string();
        if master.is_empty() {
            return Err(perr("the anime provider returned no playable source (the site may have changed)"));
        }
        let q = quality.trim().to_lowercase();
        let chosen = if matches!(q.as_str(), "" | "best" | "auto") {
            Variant { url: master.clone(), height: 0, label: "best".into() }
        } else {
            let playlist = (self.fetch)(&master, &vec![("User-Agent".into(), USER_AGENT.into()), ("Referer".into(), referer.clone())])?;
            choose_quality(variants(&master, &playlist), quality)?
        };
        let mut subtitles = String::new();
        for sub in payload["subtitles"].as_array().cloned().unwrap_or_default() {
            if sub.is_object() && truthy(&sub["default"]) && sub["src"].as_str().map(|s| !s.is_empty()).unwrap_or(false) {
                subtitles = urljoin(embed, sub["src"].as_str().unwrap());
                break;
            }
        }
        Ok((Source { url: chosen.url, referer, subtitles, quality: chosen.label }, episode))
    }
}

impl Default for Provider {
    fn default() -> Self {
        Self::new()
    }
}

fn truthy(v: &Value) -> bool {
    match v {
        Value::Bool(b) => *b,
        Value::Null => false,
        Value::Number(n) => n.as_f64() != Some(0.0),
        Value::String(s) => !s.is_empty(),
        Value::Array(a) => !a.is_empty(),
        Value::Object(o) => !o.is_empty(),
    }
}

pub fn urljoin(base: &str, rel: &str) -> String {
    url::Url::parse(base).and_then(|b| b.join(rel)).map(|u| u.to_string()).unwrap_or_else(|_| rel.to_string())
}

#[derive(Debug, Clone, PartialEq)]
pub struct Variant {
    pub url: String,
    pub height: i64,
    pub label: String,
}

pub fn variants(master: &str, playlist: &str) -> Vec<Variant> {
    if !playlist.contains("#EXTM3U") {
        return vec![];
    }
    let lines: Vec<&str> = playlist.lines().map(|l| l.trim()).filter(|l| !l.is_empty()).collect();
    let mut out = vec![];
    for (i, line) in lines.iter().enumerate() {
        if !line.starts_with("#EXT-X-STREAM-INF") || i + 1 >= lines.len() {
            continue;
        }
        let uri = lines[i + 1];
        if uri.starts_with('#') {
            continue;
        }
        let height = rx(r"RESOLUTION=\d+x(\d+)").captures(*line).ok().flatten().and_then(|c| c[1].parse().ok()).unwrap_or(0);
        out.push(Variant { url: urljoin(master, uri), height, label: if height != 0 { format!("{height}p") } else { "best".into() } });
    }
    if out.is_empty() && !master.is_empty() {
        return vec![Variant { url: master.into(), height: 0, label: "best".into() }];
    }
    out
}

pub fn choose_quality(vs: Vec<Variant>, quality: &str) -> Result<Variant, ProviderError> {
    if vs.is_empty() {
        return Err(perr("provider returned no playable quality"));
    }
    let wanted = { let q = quality.trim().to_lowercase(); if q.is_empty() { "best".to_string() } else { q } };
    let mut ordered = vs;
    ordered.sort_by(|a, b| b.height.cmp(&a.height)); // stable, like Python's sorted(reverse=True)
    if matches!(wanted.as_str(), "best" | "auto") {
        return Ok(ordered.remove(0));
    }
    if wanted == "worst" {
        return Ok(ordered.pop().unwrap());
    }
    let wh: String = wanted.chars().filter(|c| c.is_ascii_digit()).collect();
    if let Some(v) = ordered.iter().find(|v| wanted == v.label.to_lowercase() || (!wh.is_empty() && wh == v.height.to_string())) {
        return Ok(v.clone());
    }
    Ok(ordered.remove(0))
}
