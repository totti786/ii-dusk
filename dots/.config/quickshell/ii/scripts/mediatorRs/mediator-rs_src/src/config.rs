//! Configuration: ~/.config/mediator/config.toml (override with $MEDIATOR_CONFIG).
//! Mirrors `mediator/config.py`, including its leniency: wrong-typed values fall back to defaults.
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use toml::Value as T;

fn xdg(var: &str, default: &str) -> PathBuf {
    match env::var(var) {
        Ok(v) if !v.is_empty() => PathBuf::from(v),
        _ => home().join(default),
    }
}

pub fn home() -> PathBuf {
    env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"))
}

pub fn expand_user(p: &str) -> PathBuf {
    if p == "~" {
        home()
    } else if let Some(rest) = p.strip_prefix("~/") {
        home().join(rest)
    } else {
        PathBuf::from(p)
    }
}

pub fn config_path() -> PathBuf {
    match env::var("MEDIATOR_CONFIG") {
        Ok(v) if !v.is_empty() => PathBuf::from(v),
        _ => xdg("XDG_CONFIG_HOME", ".config").join("mediator/config.toml"),
    }
}

pub fn state_dir() -> PathBuf {
    match env::var("MEDIATOR_STATE_DIR") {
        Ok(v) if !v.trim().is_empty() => PathBuf::from(v.trim()),
        _ => match env::var("XDG_STATE_HOME") {
            Ok(v) if !v.trim().is_empty() => PathBuf::from(v.trim()).join("mediator"),
            _ => home().join(".local/state/mediator"),
        },
    }
}

pub fn cache_dir() -> PathBuf {
    match env::var("MEDIATOR_CACHE_DIR") {
        Ok(v) if !v.is_empty() => PathBuf::from(v),
        _ => xdg("XDG_CACHE_HOME", ".cache").join("mediator"),
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Jellyfin {
    pub url: String,
    pub user_id: String,
    pub username: String,
    pub token: String,
    pub libraries: BTreeMap<String, String>,
    pub cache_ttl: i64,
    pub include: bool,
}

impl Jellyfin {
    pub fn configured(&self) -> bool {
        !self.url.is_empty() && !self.token.is_empty() && (!self.user_id.is_empty() || !self.username.is_empty())
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct AniList {
    pub token: String,
    pub user_id: i64,
    pub username: String,
    pub client_id: String,
    pub auto: bool,
    pub add_missing: bool,
    pub rewatch: bool,
    pub complete: bool,
    pub dates: bool,
}

impl AniList {
    pub fn configured(&self) -> bool {
        !self.token.is_empty()
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Streaming {
    pub hls: bool,
    pub prefer_stremio: bool,
    pub stremio: bool,
    /// when a direct stream fails, ask before playing a torrent instead of switching silently
    pub ask_before_torrent: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Config {
    pub libraries: BTreeMap<String, String>,
    pub speed: f64,
    pub speed_by_library: BTreeMap<String, f64>,
    pub mpv_args: Vec<String>,
    pub finish_ratio: f64,
    pub finish_tail: f64,
    pub picker: String,
    pub player: String,
    pub syncplay_args: Vec<String>,
    pub jellyfin: Jellyfin,
    pub anilist: AniList,
    pub streaming: Streaming,
    pub auto_fetch: bool,
}

impl Default for Config {
    fn default() -> Self {
        let m = |a: &[(&str, &str)]| a.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
        Config {
            libraries: m(&[("anime", "~/Videos/Anime"), ("shows", "~/Videos/Shows"), ("movies", "~/Videos/Movies")]),
            speed: 1.0,
            speed_by_library: BTreeMap::new(),
            mpv_args: vec![],
            finish_ratio: 0.9,
            finish_tail: 120.0,
            picker: "auto".into(),
            player: "mpv".into(),
            syncplay_args: vec![],
            jellyfin: Jellyfin {
                url: String::new(), user_id: String::new(), username: String::new(), token: String::new(),
                libraries: m(&[("anime", "Anime"), ("shows", "Shows"), ("movies", "Movies")]),
                cache_ttl: 300, include: false,
            },
            anilist: AniList {
                token: String::new(), user_id: 0, username: String::new(), client_id: String::new(),
                auto: true, add_missing: false, rewatch: false, complete: true, dates: true,
            },
            streaming: Streaming { hls: false, prefer_stremio: false, stremio: true, ask_before_torrent: true },
            auto_fetch: true,
        }
    }
}

impl Config {
    pub fn speed_for(&self, lib: &str) -> f64 {
        self.speed_by_library.get(lib).copied().unwrap_or(self.speed)
    }
}

fn tbl<'a>(v: &'a T, key: &str) -> Option<&'a toml::Table> {
    v.get(key).and_then(|x| x.as_table())
}
fn f(t: Option<&toml::Table>, k: &str, d: f64) -> f64 {
    match t.and_then(|t| t.get(k)) {
        Some(T::Float(x)) => *x,
        Some(T::Integer(x)) => *x as f64,
        Some(T::String(s)) => s.parse().unwrap_or(d),
        _ => d,
    }
}
fn b(t: Option<&toml::Table>, k: &str, d: bool) -> bool {
    match t.and_then(|t| t.get(k)) {
        Some(T::Boolean(x)) => *x,
        Some(T::Integer(x)) => *x != 0,
        Some(T::String(s)) => !s.is_empty(),
        _ => d,
    }
}
fn s(t: Option<&toml::Table>, k: &str, d: &str) -> String {
    match t.and_then(|t| t.get(k)) {
        Some(T::String(x)) => x.clone(),
        Some(T::Integer(x)) => x.to_string(),
        Some(T::Float(x)) => x.to_string(),
        Some(T::Boolean(x)) => if *x { "True".into() } else { "False".into() },
        _ => d.to_string(),
    }
}
fn strs(t: Option<&toml::Table>, k: &str, d: &[String]) -> Vec<String> {
    match t.and_then(|t| t.get(k)).and_then(|x| x.as_array()) {
        Some(a) => a.iter().map(|x| x.as_str().map(String::from).unwrap_or_else(|| x.to_string())).collect(),
        None => d.to_vec(),
    }
}
fn smap(t: Option<&toml::Table>) -> impl Iterator<Item = (String, String)> + '_ {
    t.into_iter().flat_map(|t| t.iter().map(|(k, v)| {
        (k.clone(), v.as_str().map(String::from).unwrap_or_else(|| v.to_string()))
    }))
}

pub fn load() -> Config {
    load_from(&config_path())
}

pub fn load_from(path: &Path) -> Config {
    let text = match fs::read_to_string(path) {
        Ok(t) => t,
        Err(_) => return Config::default(),
    };
    parse(&text)
}

pub fn parse(text: &str) -> Config {
    let data: T = T::Table(toml::from_str::<toml::Table>(text).unwrap_or_default());
    let mut c = Config::default();
    c.libraries.extend(smap(tbl(&data, "libraries")));
    let pb = tbl(&data, "playback");
    c.speed = f(pb, "speed", c.speed);
    if let Some(m) = pb.and_then(|p| p.get("speed_by_library")).and_then(|x| x.as_table()) {
        c.speed_by_library = m.iter().filter_map(|(k, v)| {
            match v { T::Float(x) => Some(*x), T::Integer(x) => Some(*x as f64), _ => None }.map(|x| (k.clone(), x))
        }).collect();
    }
    c.mpv_args = strs(pb, "mpv_args", &c.mpv_args);
    c.player = s(pb, "player", &c.player);
    c.syncplay_args = strs(tbl(&data, "syncplay"), "args", &c.syncplay_args);
    c.finish_ratio = f(pb, "finish_ratio", c.finish_ratio);
    c.finish_tail = f(pb, "finish_tail", c.finish_tail);
    c.picker = s(tbl(&data, "ui"), "picker", &c.picker);
    c.auto_fetch = b(tbl(&data, "posters"), "auto_fetch", c.auto_fetch);
    let jf = tbl(&data, "jellyfin");
    let mut url = s(jf, "url", "").trim().trim_end_matches('/').to_string();
    if !url.is_empty() && !url.contains("://") {
        url = format!("https://{url}");
    }
    let mut libs = c.jellyfin.libraries.clone();
    libs.extend(smap(jf.and_then(|t| t.get("libraries")).and_then(|x| x.as_table())));
    c.jellyfin = Jellyfin {
        url,
        user_id: s(jf, "user_id", ""),
        username: s(jf, "username", ""),
        token: s(jf, "token", ""),
        libraries: libs,
        cache_ttl: f(jf, "cache_ttl", c.jellyfin.cache_ttl as f64) as i64,
        include: b(jf, "include", c.jellyfin.include),
    };
    let st = tbl(&data, "streaming");
    c.streaming = Streaming {
        hls: b(st, "hls", c.streaming.hls),
        stremio: b(st, "stremio", c.streaming.stremio),
        prefer_stremio: b(st, "prefer_stremio", c.streaming.prefer_stremio),
        ask_before_torrent: b(st, "ask_before_torrent", c.streaming.ask_before_torrent),
    };
    let al = tbl(&data, "anilist");
    let d = c.anilist.clone();
    c.anilist = AniList {
        token: s(al, "token", ""),
        user_id: f(al, "user_id", 0.0) as i64,
        username: s(al, "username", ""),
        client_id: s(al, "client_id", ""),
        auto: b(al, "auto", d.auto),
        add_missing: b(al, "add_missing", d.add_missing),
        rewatch: b(al, "rewatch", d.rewatch),
        complete: b(al, "complete", d.complete),
        dates: b(al, "dates", d.dates),
    };
    c
}

// ---- writing ----

fn toml_str(v: &str) -> String {
    format!("\"{}\"", v.replace('\\', "\\\\").replace('"', "\\\""))
}

fn toml_val(v: &Value) -> String {
    match v {
        Value::Bool(x) => x.to_string(),
        Value::Number(n) => n.to_string(),
        Value::String(x) => toml_str(x),
        other => toml_str(&other.to_string()),
    }
}

/// Set keys inside `[section]`, keeping every other line as written.
pub fn update_section(section: &str, values: &[(String, Value)], path: &Path) -> io::Result<()> {
    let text = fs::read_to_string(path).unwrap_or_default();
    let mut lines: Vec<String> = text.split('\n').map(String::from).collect();
    let header = format!("[{section}]");
    let start = match lines.iter().position(|l| l.trim() == header) {
        Some(i) => i,
        None => {
            while lines.last().map(|l| l.is_empty()).unwrap_or(false) {
                lines.pop();
            }
            if !lines.is_empty() {
                lines.push(String::new());
            }
            lines.push(header);
            lines.len() - 1
        }
    };
    let mut end = (start + 1..lines.len()).find(|&i| lines[i].trim_start().starts_with('[')).unwrap_or(lines.len());
    for (key, val) in values {
        let row = format!("{key} = {}", toml_val(val));
        let hit = (start + 1..end).find(|&i| lines[i].contains('=') && lines[i].split('=').next().unwrap().trim() == key);
        match hit {
            Some(i) => lines[i] = row,
            None => {
                let mut at = end;
                while at > start + 1 && lines[at - 1].trim().is_empty() {
                    at -= 1;
                }
                lines.insert(at, row);
                end += 1;
            }
        }
    }
    let out = format!("{}\n", lines.join("\n").trim_end_matches('\n'));
    crate::fileio::atomic_write_text(path, &out, 0o600)
}

#[derive(Clone, Copy, PartialEq)]
enum Kind { Str, Float, Bool }

fn setting_kind(key: &str) -> Option<Kind> {
    use Kind::*;
    Some(match key {
        "libraries.anime" | "libraries.shows" | "libraries.movies" => Str,
        "playback.speed" | "playback.finish_ratio" | "playback.finish_tail" => Float,
        "posters.auto_fetch" => Bool,
        "jellyfin.url" | "jellyfin.username" | "jellyfin.user_id" | "jellyfin.token" => Str,
        "jellyfin.include" => Bool,
        "streaming.hls" | "streaming.stremio" | "streaming.prefer_stremio" | "streaming.ask_before_torrent" => Bool,
        "anilist.token" | "anilist.username" | "anilist.client_id" => Str,
        "anilist.auto" | "anilist.add_missing" | "anilist.rewatch" | "anilist.complete" | "anilist.dates" => Bool,
        _ => return None,
    })
}

pub fn settings_view(c: &Config) -> Value {
    let lib = |k: &str| c.libraries.get(k).cloned().unwrap_or_default();
    json!({
        "path": config_path().to_string_lossy(),
        "libraries": {"anime": lib("anime"), "shows": lib("shows"), "movies": lib("movies")},
        "playback": {"speed": c.speed, "finish_ratio": c.finish_ratio, "finish_tail": c.finish_tail},
        "posters": {"auto_fetch": c.auto_fetch},
        "jellyfin": {"url": c.jellyfin.url, "username": c.jellyfin.username, "user_id": c.jellyfin.user_id,
            "token_set": !c.jellyfin.token.is_empty(), "include": c.jellyfin.include, "configured": c.jellyfin.configured()},
        "streaming": {"hls": c.streaming.hls, "stremio": c.streaming.stremio, "prefer_stremio": c.streaming.prefer_stremio, "ask_before_torrent": c.streaming.ask_before_torrent},
        "anilist": {"username": c.anilist.username, "user_id": c.anilist.user_id, "token_set": !c.anilist.token.is_empty(),
            "configured": c.anilist.configured(), "client_id": c.anilist.client_id, "auto": c.anilist.auto,
            "add_missing": c.anilist.add_missing, "rewatch": c.anilist.rewatch, "complete": c.anilist.complete,
            "dates": c.anilist.dates},
    })
}

/// Write {"section.key": value}; unknown keys and bad values are errors. Returns the sorted keys.
pub fn apply_settings(patch: &serde_json::Map<String, Value>, path: &Path) -> Result<Vec<String>, String> {
    let mut by: BTreeMap<String, Vec<(String, Value)>> = BTreeMap::new();
    for (key, raw) in patch {
        let kind = setting_kind(key).ok_or_else(|| format!("unknown setting '{key}'"))?;
        let mut val = match kind {
            Kind::Bool => match raw {
                Value::Bool(_) => raw.clone(),
                _ => return Err(format!("{key}: expected true or false")),
            },
            Kind::Float => {
                let x = match raw {
                    Value::Number(n) => n.as_f64(),
                    Value::String(t) => t.trim().parse().ok(),
                    _ => None,
                }.ok_or_else(|| format!("{key}: could not convert to a number"))?;
                if x <= 0.0 {
                    return Err(format!("{key}: must be positive"));
                }
                json!(x)
            }
            Kind::Str => json!(match raw { Value::String(t) => t.trim().to_string(), o => o.to_string() }),
        };
        if key == "jellyfin.url" {
            let u = val.as_str().unwrap_or("").trim_end_matches('/').to_string();
            val = json!(if !u.is_empty() && !u.contains("://") { format!("https://{u}") } else { u });
        }
        let (sec, name) = key.split_once('.').unwrap();
        by.entry(sec.into()).or_default().push((name.into(), val));
    }
    for (sec, vals) in &by {
        update_section(sec, vals, path).map_err(|e| e.to_string())?;
    }
    let mut keys: Vec<String> = patch.keys().cloned().collect();
    keys.sort();
    Ok(keys)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_without_file() {
        let d = tempfile::tempdir().unwrap();
        assert_eq!(load_from(&d.path().join("x.toml")), Config::default());
    }

    #[test]
    fn parses_sections_and_normalises_jellyfin_url() {
        let c = parse("[playback]\nspeed = 1.5\nmpv_args = [\"--fs\"]\n[jellyfin]\nurl = \"jf.example.com/\"\ntoken=\"t\"\nusername=\"u\"\n[streaming]\nhls = true\n[libraries]\nanime = \"/a\"\n");
        assert_eq!(c.speed, 1.5);
        assert_eq!(c.mpv_args, vec!["--fs"]);
        assert_eq!(c.jellyfin.url, "https://jf.example.com");
        assert!(c.jellyfin.configured());
        assert!(c.streaming.hls && c.streaming.stremio);
        assert_eq!(c.libraries["anime"], "/a");
        assert_eq!(c.libraries["shows"], "~/Videos/Shows");
    }

    #[test]
    fn bad_toml_is_defaults() {
        assert_eq!(parse("= = ["), Config::default());
    }

    #[test]
    fn update_keeps_comments_and_adds_missing() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("c.toml");
        fs::write(&p, "# mine\n[playback]\nspeed = 1.0\n\n[ui]\npicker = \"fzf\"\n").unwrap();
        let patch = json!({"playback.speed": 1.25, "playback.finish_tail": 90, "streaming.hls": true});
        let keys = apply_settings(patch.as_object().unwrap(), &p).unwrap();
        assert_eq!(keys, vec!["playback.finish_tail", "playback.speed", "streaming.hls"]);
        let t = fs::read_to_string(&p).unwrap();
        assert!(t.starts_with("# mine\n[playback]\nspeed = 1.25\nfinish_tail = 90.0\n\n[ui]"), "{t}");
        assert!(t.ends_with("[streaming]\nhls = true\n"), "{t}");
        let c = load_from(&p);
        assert_eq!((c.speed, c.finish_tail, c.streaming.hls), (1.25, 90.0, true));
    }

    #[test]
    fn rejects_unknown_and_bad_values() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("c.toml");
        for patch in [json!({"nope.x": 1}), json!({"streaming.hls": "yes"}), json!({"playback.speed": -1})] {
            assert!(apply_settings(patch.as_object().unwrap(), &p).is_err());
        }
    }

    #[test]
    fn python_reads_what_rust_wrote() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("c.toml");
        apply_settings(json!({"jellyfin.url": "jf.local/", "anilist.auto": false}).as_object().unwrap(), &p).unwrap();
        let out = std::process::Command::new("python3")
            .current_dir("..")
            .args(["-c", "import sys;from mediator import config as c;x=c.load(sys.argv[1]);print(x.jellyfin.url,x.anilist.auto)"])
            .arg(&p).output();
        if let Ok(o) = out {
            if o.status.success() {
                assert_eq!(String::from_utf8_lossy(&o.stdout).trim(), "https://jf.local False");
            }
        }
    }
}
