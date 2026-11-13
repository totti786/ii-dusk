//! Synopsis, rating, genres and the like for a title, fetched once and kept on disk (port of
//! `mediator/meta.py`). Every source is reduced to one shape: synopsis, rating (0-10),
//! rating_source, genres, year, runtime (minutes), certification, studio, status, director, cast.
use crate::catalog::Title;
use crate::parse::{norm_key, rx};
use crate::posters::{self, best, q, slug, Http, HttpFail};
use serde_json::{json, Map, Value};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

pub const MISS_RETRY_DAYS: f64 = 14.0;
pub const CINEMETA: &str = "https://v3-cinemeta.strem.io";
/// One Jikan request at a time, so parallel fetches keep to its rate limit.
pub static JIKAN_LOCK: Mutex<()> = Mutex::new(());

pub fn cache_dir() -> PathBuf {
    posters::cache_root().join("meta")
}

fn path(title: &Title, dir: &Path) -> PathBuf {
    dir.join(format!("{}.json", slug(&title.id)))
}
fn read(title: &Title, dir: &Path) -> Option<Value> {
    serde_json::from_str(&std::fs::read_to_string(path(title, dir)).ok()?).ok()
}
fn write(title: &Title, data: &Value, dir: &Path) {
    let _ = crate::fileio::atomic_write_text(&path(title, dir), &data.to_string(), 0o644);
}

pub fn find(title: &Title) -> Option<Value> {
    find_in(title, &cache_dir())
}
pub fn find_in(title: &Title, dir: &Path) -> Option<Value> {
    match read(title, dir) {
        Some(d) if d.get("miss").is_none() => Some(d),
        // a server's own listing already says rating, genres and a blurb: no lookup needed
        _ => title.remote.as_object().filter(|o| !o.is_empty()).map(|_| norm_jellyfin(&title.remote)),
    }
}

// ---- turning each source's answer into the one shape ----

pub fn text(v: &Value) -> String {
    let s = match v {
        Value::Null => return String::new(),
        Value::String(s) if s.is_empty() => return String::new(),
        Value::String(s) => s.clone(),
        o => o.to_string(),
    };
    let s = rx(r"<br\s*/?>").replace_all(&s, "\n").into_owned();
    let s = html_escape::decode_html_entities(&rx(r"<[^>]+>").replace_all(&s, "")).into_owned();
    let s = rx(r"\[Written by [^\]]*\]").replace_all(&s, "").into_owned();
    rx(r"\n{3,}").replace_all(&s, "\n\n").trim().to_string()
}

pub fn num(v: &Value) -> Option<f64> {
    let n = match v {
        Value::Number(n) => n.as_f64()?,
        Value::String(s) => s.trim().parse().ok()?,
        Value::Bool(b) => *b as i64 as f64,
        _ => return None,
    };
    if n > 0.0 { Some((n * 10.0).round() / 10.0) } else { None }
}

fn pystr(v: &Value) -> String {
    match v {
        Value::Null => String::new(),
        Value::String(s) => s.clone(),
        Value::Number(n) if n.as_f64() == Some(0.0) => String::new(),
        o => o.to_string(),
    }
}

pub fn minutes(v: &Value) -> Option<i64> {
    let s = pystr(v);
    if let Some(c) = rx(r"(\d+)\s*(?:hr|h)\D*(\d+)?").captures(s.as_str()).ok().flatten() {
        let before = s.splitn(2, &c[1]).next().unwrap_or("");
        if !before.contains("min") {
            return Some(c[1].parse::<i64>().unwrap() * 60 + c.get(2).and_then(|m| m.as_str().parse::<i64>().ok()).unwrap_or(0));
        }
    }
    rx(r"(\d+)\s*min").captures(s.as_str()).ok().flatten().map(|c| c[1].parse().unwrap())
}

fn empty_meta(v: &Value) -> bool {
    match v {
        Value::Null => true,
        Value::String(s) => s.is_empty() || s == "N/A",
        Value::Array(a) => a.is_empty(),
        _ => false,
    }
}
/// Drop empty values (`None`, `""`, `[]`, `"N/A"`).
pub fn clean(pairs: Vec<(&str, Value)>) -> Value {
    Value::Object(pairs.into_iter().filter(|(_, v)| !empty_meta(v)).map(|(k, v)| (k.to_string(), v)).collect())
}
fn opt<T: Into<Value>>(x: Option<T>) -> Value {
    x.map(Into::into).unwrap_or(Value::Null)
}
fn sv(v: &Value) -> Value {
    if v.is_null() { Value::Null } else { v.clone() }
}
fn names(v: &Value, key: &str) -> Vec<Value> {
    v[key].as_array().cloned().unwrap_or_default().iter().filter_map(|g| g.get("name").cloned()).collect()
}

pub fn norm_jikan(a: &Value) -> Value {
    let year = posters::year_value(&a["year"]).or_else(|| a["aired"]["prop"]["from"]["year"].as_i64());
    let rating = a["rating"].as_str().unwrap_or("");
    clean(vec![
        ("synopsis", json!(text(&a["synopsis"]))), ("rating", opt(num(&a["score"]))), ("rating_source", json!("MyAnimeList")),
        ("genres", json!(names(a, "genres"))), ("year", opt(year)), ("runtime", opt(minutes(&a["duration"]))),
        ("certification", json!(rating.split(" - ").next().unwrap_or(""))),
        ("studio", sv(&a["studios"][0]["name"])), ("status", sv(&a["status"])), ("source", json!("jikan")),
    ])
}

pub fn norm_tvmaze(s: &Value) -> Value {
    let net = if s["network"].as_object().map(|o| !o.is_empty()).unwrap_or(false) { &s["network"] } else { &s["webChannel"] };
    clean(vec![
        ("synopsis", json!(text(&s["summary"]))), ("rating", opt(num(&s["rating"]["average"]))), ("rating_source", json!("TVmaze")),
        ("genres", sv(&s["genres"])), ("year", opt(posters::premiered_year(s))),
        ("runtime", if num_nonzero(&s["averageRuntime"]) { s["averageRuntime"].clone() } else { sv(&s["runtime"]) }),
        ("studio", sv(&net["name"])), ("status", sv(&s["status"])), ("imdb_id", sv(&s["externals"]["imdb"])), ("source", json!("tvmaze")),
    ])
}

fn num_nonzero(v: &Value) -> bool {
    match v { Value::Null => false, Value::Number(n) => n.as_f64() != Some(0.0), Value::String(s) => !s.is_empty(), _ => true }
}

pub fn norm_cinemeta(m: &Value) -> Value {
    let id = if num_nonzero(&m["imdb_id"]) { m["imdb_id"].clone() } else { sv(&m["id"]) };
    clean(vec![
        ("synopsis", json!(text(&m["description"]))), ("rating", opt(num(&m["imdbRating"]))), ("rating_source", json!("IMDb")),
        ("genres", sv(&m["genres"])), ("year", opt(posters::year_of(m))), ("runtime", opt(minutes(&m["runtime"]))),
        ("director", json!(m["director"].as_array().map(|a| a.iter().filter_map(|x| x.as_str()).collect::<Vec<_>>().join(", ")).unwrap_or_default())),
        ("cast", sv(&m["cast"])), ("imdb_id", id), ("source", json!("cinemeta")),
    ])
}

pub fn norm_jellyfin(i: &Value) -> Value {
    let ticks = i["RunTimeTicks"].as_f64().filter(|t| *t != 0.0);
    clean(vec![
        ("synopsis", json!(text(&i["Overview"]))), ("rating", opt(num(&i["CommunityRating"]))), ("rating_source", json!("Jellyfin")),
        ("genres", sv(&i["Genres"])), ("year", sv(&i["ProductionYear"])),
        ("runtime", opt(ticks.map(|t| (t / 600_000_000.0).round() as i64))),
        ("certification", sv(&i["OfficialRating"])), ("studio", sv(&i["Studios"][0]["Name"])), ("status", sv(&i["Status"])), ("source", json!("jellyfin")),
    ])
}

// ---- the sources ----

pub fn from_jikan(title: &Title, http: &dyn Http, sleep: &dyn Fn(f64)) -> Result<Option<Value>, HttpFail> {
    let data = {
        let _g = JIKAN_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        sleep(0.45);
        http.json(&format!("https://api.jikan.moe/v4/anime?{}", q(&[("q", title.name.clone()), ("limit", "10".into()), ("sfw", "true".into())])))?
    };
    let mut cands = vec![];
    for a in data.as_ref().and_then(|d| d["data"].as_array()).cloned().unwrap_or_default() {
        let mut ns: Vec<Option<String>> = ["title", "title_english", "title_japanese"].iter().map(|k| a[*k].as_str().map(String::from)).collect();
        ns.extend(a["titles"].as_array().cloned().unwrap_or_default().iter().map(|t| t["title"].as_str().map(String::from)));
        cands.push((ns, posters::year_value(&a["year"]).or_else(|| a["aired"]["prop"]["from"]["year"].as_i64()), a.clone(), true));
    }
    Ok(best(&cands, title).map(|a| norm_jikan(&a)))
}

pub fn from_tvmaze(title: &Title, http: &dyn Http) -> Result<Option<Value>, HttpFail> {
    let data = http.json(&format!("https://api.tvmaze.com/search/shows?{}", q(&[("q", title.name.clone())])))?;
    let mut cands = vec![];
    for h in data.as_ref().and_then(|d| d.as_array()).cloned().unwrap_or_default() {
        let s = h["show"].clone();
        cands.push((vec![s["name"].as_str().map(String::from)], posters::premiered_year(&s), s, true));
    }
    Ok(best(&cands, title).map(|s| norm_tvmaze(&s)))
}

fn enc(s: &str) -> String {
    use percent_encoding::{utf8_percent_encode, AsciiSet, NON_ALPHANUMERIC};
    const S: &AsciiSet = &NON_ALPHANUMERIC.remove(b'_').remove(b'.').remove(b'-').remove(b'~');
    utf8_percent_encode(s, S).to_string()
}

/// Stremio's Cinemeta, no API key: search by name, take a hit with the same title and a year within
/// one of ours, then read its full record.
pub fn cinemeta_meta(title: &Title, http: &dyn Http) -> Result<Option<Value>, HttpFail> {
    let kind = if title.lib == "movies" { "movie" } else { "series" };
    let want = norm_key(&title.name);
    let found = http.json(&format!("{CINEMETA}/catalog/{kind}/top/search={}.json", enc(&title.name)))?;
    for hit in found.as_ref().and_then(|f| f["metas"].as_array()).cloned().unwrap_or_default() {
        if norm_key(&html_escape::decode_html_entities(hit["name"].as_str().unwrap_or(""))) != want {
            continue;
        }
        if let (Some(y), Some(got)) = (title.year, posters::year_of(&hit)) {
            if (got - y as i64).abs() > 1 {
                continue;
            }
        }
        let ident = if num_nonzero(&hit["imdb_id"]) { hit["imdb_id"].clone() } else { sv(&hit["id"]) };
        let full = if num_nonzero(&ident) {
            let id = ident.as_str().map(String::from).unwrap_or_else(|| ident.to_string());
            http.json(&format!("{CINEMETA}/meta/{kind}/{}.json", enc(&id)))?
        } else {
            None
        };
        return Ok(Some(full.and_then(|f| f.get("meta").filter(|m| m.as_object().map(|o| !o.is_empty()).unwrap_or(false)).cloned()).unwrap_or(hit)));
    }
    Ok(None)
}

pub fn from_cinemeta(title: &Title, http: &dyn Http) -> Result<Option<Value>, HttpFail> {
    Ok(cinemeta_meta(title, http)?.map(|m| norm_cinemeta(&m)))
}

pub struct Opts<'a> {
    pub refresh: bool,
    pub cache: PathBuf,
    pub now: f64,
    pub sleep: &'a dyn Fn(f64),
}
impl Default for Opts<'_> {
    fn default() -> Self {
        Opts { refresh: false, cache: cache_dir(), now: crate::state::now(), sleep: &crate::posters::jikan_pace }
    }
}

/// -> (status, meta). status: have | fetched | miss | skipped | error.
pub fn fetch(title: &Title, http: &dyn Http, jellyfin_item: Option<&dyn Fn(&str) -> Result<Value, String>>, o: &Opts) -> (&'static str, Option<Value>) {
    if !o.refresh {
        if let Some(old) = read(title, &o.cache) {
            if old.get("miss").is_none() && (num_nonzero(&old["imdb_id"]) || title.lib != "shows" || old["source"] != "tvmaze") {
                return ("have", Some(old));
            }
            if let Some(m) = old.get("miss").and_then(|m| m.as_f64()) {
                if o.now - m < MISS_RETRY_DAYS * 86400.0 {
                    return ("skipped", None);
                }
            }
        }
    }
    let mut data: Option<Value>;
    if title.source == "jellyfin" {
        let Some(j) = jellyfin_item else { return ("skipped", None) };
        if title.remote_id.is_empty() {
            data = None;
        } else {
            match j(&title.remote_id) {
                Ok(i) => data = Some(norm_jellyfin(&i)),
                Err(e) => return ("error", Some(json!({"error": e}))),
            }
        }
    } else {
        let r = match title.lib.as_str() {
            "anime" => from_jikan(title, http, o.sleep),
            "shows" => from_tvmaze(title, http),
            _ => from_cinemeta(title, http),
        };
        match r {
            Ok(d) => data = d,
            Err(e) => return ("error", Some(json!({"error": e.0}))),
        }
    }
    match data.as_mut() {
        Some(d) if d.as_object().map(|o| !o.is_empty()).unwrap_or(false) => {
            d["fetched"] = json!(o.now);
            write(title, d, &o.cache);
            ("fetched", data)
        }
        _ => {
            write(title, &json!({"miss": o.now}), &o.cache);
            ("miss", None)
        }
    }
}

#[allow(dead_code)]
fn unused(_: Map<String, Value>) {}
