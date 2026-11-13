//! Turn a list of files into Titles: series with ordered seasons, or movies.
//! `build_catalog` is pure (paths + sizes in, Titles out); `scan` is the thin I/O wrapper.
use crate::parse::*;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};

pub const KINDS: [&str; 3] = ["anime", "shows", "movies"];

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub enum Tok {
    S(String),
    N(u128),
}

pub fn natural_key(s: &str) -> Vec<Tok> {
    let mut out = vec![];
    let mut cur = String::new();
    let mut digits = false;
    let flush = |cur: &mut String, digits: bool, out: &mut Vec<Tok>| {
        if digits {
            out.push(Tok::N(cur.parse().unwrap_or(u128::MAX)));
        } else {
            out.push(Tok::S(cur.to_lowercase()));
        }
        cur.clear();
    };
    // alternate string / number tokens, always starting with a (possibly empty) string
    for c in s.chars() {
        let d = c.is_ascii_digit();
        if d != digits {
            flush(&mut cur, digits, &mut out);
            digits = d;
        }
        cur.push(c);
    }
    flush(&mut cur, digits, &mut out);
    if digits {
        out.push(Tok::S(String::new()));
    }
    if out.first().map(|t| matches!(t, Tok::N(_))).unwrap_or(false) {
        out.insert(0, Tok::S(String::new()));
    }
    out
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Entry {
    pub path: String,
    pub rel: String,
    pub size: i64,
    pub kind: String,
    pub season: Option<i32>,
    pub episode: Option<f64>,
    pub episode_end: Option<i32>,
    pub version: i32,
    pub name: String,
    pub rule: String,
    pub confidence: String,
    pub stem: String,
    #[serde(default)]
    pub remote_id: String,
}

impl Entry {
    pub fn code(&self) -> String {
        if self.kind == "episode" {
            episode_code(self.season, self.episode, self.episode_end)
        } else if self.kind == "special" && self.episode.is_some() {
            format!("S{:02}SP{:0>2}", self.season.unwrap_or(0), fmt_num(self.episode))
        } else {
            String::new()
        }
    }

    pub fn label(&self) -> String {
        let code = self.code();
        if self.kind == "movie" {
            if let Some(n) = self.episode {
                return if self.name.is_empty() { format!("Movie {}", fmt_num(Some(n))) } else { format!("Movie {} · {}", fmt_num(Some(n)), self.name) };
            }
        }
        if !code.is_empty() && !self.name.is_empty() {
            return format!("{code} · {}", self.name);
        }
        if !code.is_empty() {
            return code;
        }
        if !self.name.is_empty() { self.name.clone() } else { tidy_stem(&self.stem) }
    }
}

fn tidy_stem(stem: &str) -> String {
    let s = rx(r"\[[^\]]*\]|\([^)]*\)").replace_all(stem, " ").replace('_', " ");
    let s = rx(r"\s+").replace_all(&s, " ").into_owned();
    let t = s.trim().trim_matches(|c| " -._".contains(c));
    if t.is_empty() { stem.to_string() } else { t.to_string() }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Title {
    pub id: String,
    pub lib: String,
    pub name: String,
    pub year: Option<i32>,
    #[serde(default)]
    pub entries: Vec<Entry>,
    #[serde(default)]
    pub duplicates: Vec<Entry>,
    #[serde(default = "local")]
    pub source: String,
    #[serde(default)]
    pub remote_id: String,
    #[serde(default)]
    pub remote: Value,
}

fn local() -> String {
    "local".into()
}

impl Title {
    pub fn new(id: String, lib: &str, name: String, year: Option<i32>) -> Title {
        Title { id, lib: lib.into(), name, year, entries: vec![], duplicates: vec![], source: local(), remote_id: String::new(), remote: Value::Object(Default::default()) }
    }

    /// The menu a title lives on: "anime", or "jellyfin:anime" for the server's copy.
    pub fn shelf(&self) -> String {
        if self.source == "local" { self.lib.clone() } else { format!("{}:{}", self.source, self.lib) }
    }

    pub fn display(&self) -> String {
        match self.year { Some(y) if y != 0 => format!("{} ({y})", self.name), _ => self.name.clone() }
    }

    pub fn of_kind(&self, kind: &str) -> Vec<&Entry> {
        self.entries.iter().filter(|e| e.kind == kind).collect()
    }

    pub fn episodes(&self) -> Vec<&Entry> {
        self.of_kind("episode")
    }

    pub fn seasons(&self) -> std::collections::BTreeMap<i32, Vec<&Entry>> {
        let mut out: std::collections::BTreeMap<i32, Vec<&Entry>> = Default::default();
        for e in self.episodes() {
            out.entry(e.season.unwrap_or(1)).or_default().push(e);
        }
        out
    }

    /// What "next" walks through: main episodes (or the movie itself).
    pub fn play_order(&self) -> Vec<&Entry> {
        if self.lib == "movies" {
            return self.of_kind("movie");
        }
        let eps = self.episodes();
        if eps.is_empty() { self.of_kind("movie") } else { eps }
    }
}

pub(crate) fn order_key(e: &Entry) -> (i32, f64, Vec<Tok>) {
    (e.season.unwrap_or(0), e.episode.unwrap_or(f64::INFINITY), natural_key(&e.rel))
}

pub(crate) fn cmp_order(a: &Entry, b: &Entry) -> Ordering {
    let (x, y) = (order_key(a), order_key(b));
    x.0.cmp(&y.0).then(x.1.partial_cmp(&y.1).unwrap_or(Ordering::Equal)).then(x.2.cmp(&y.2))
}

fn classify_series_file(info: &FileInfo, dirs: &[DirInfo]) -> (String, Option<i32>) {
    let sub = dirs.get(1..).unwrap_or(&[]);
    let hint = dirs.iter().rev().find_map(|d| d.season);
    let mut kind = info.kind.clone();
    if !(kind == "special" && (info.rule == "season-special" || info.rule == "sxxexx")) {
        if sub.iter().any(|d| d.kind == "extra") {
            kind = "extra".into();
        } else if kind != "extra" {
            if sub.iter().any(|d| d.kind == "special") {
                kind = "special".into();
            } else if sub.iter().any(|d| d.kind == "movie") {
                kind = "movie".into();
            }
        }
    }
    let season = match kind.as_str() {
        "episode" => info.season.or(hint).or(Some(1)),
        "special" => info.season.or(hint).or(Some(0)),
        _ => hint,
    };
    (kind, season)
}

/// files: (relative posix path, size). Returns (titles, skipped_rel_paths).
pub fn build_catalog(lib: &str, files: &[(String, i64)], root: &str) -> (Vec<Title>, Vec<String>) {
    if lib == "movies" { build_movies(files, root) } else { build_series(lib, files, root) }
}

fn stem_of(rel: &str) -> String {
    let name = rel.rsplit('/').next().unwrap_or(rel);
    splitext(name).0.to_string()
}

/// Python's os.path.splitext on a bare file name.
pub fn splitext(name: &str) -> (&str, &str) {
    match name.rfind('.') {
        Some(i) if i > 0 && name[..i].chars().any(|c| c != '.') => (&name[..i], &name[i..]),
        _ => (name, ""),
    }
}

fn mk_entry(root: &str, rel: &str, size: i64, info: &FileInfo, kind: &str, season: Option<i32>) -> Entry {
    Entry {
        path: if root.is_empty() { rel.to_string() } else { format!("{}/{rel}", root.trim_end_matches('/')) },
        rel: rel.into(), size, kind: kind.into(), season, episode: info.episode, episode_end: info.episode_end,
        version: info.version, name: info.title.clone(), rule: info.rule.clone(), confidence: info.confidence.clone(),
        stem: stem_of(rel), remote_id: String::new(),
    }
}

fn sorted_files(files: &[(String, i64)]) -> Vec<&(String, i64)> {
    let mut v: Vec<_> = files.iter().collect();
    v.sort_by_cached_key(|f| natural_key(&f.0));
    v
}

fn in_samples_dir(parts: &[&str]) -> bool {
    parts[..parts.len() - 1].iter().any(|p| matches!(p.to_lowercase().as_str(), "sample" | "samples"))
}

fn build_series(lib: &str, files: &[(String, i64)], root: &str) -> (Vec<Title>, Vec<String>) {
    let mut skipped = vec![];
    let mut order: Vec<String> = vec![];
    let mut groups: HashMap<String, Vec<(Entry, String, Option<i32>)>> = HashMap::new();
    let mut display: HashMap<String, String> = HashMap::new();
    for (rel, size) in sorted_files(files) {
        let parts: Vec<&str> = rel.split('/').collect();
        let stem = splitext(parts[parts.len() - 1]).0.to_string();
        let info = parse_episode(&stem);
        if info.kind == "sample" || in_samples_dir(&parts) {
            skipped.push(rel.clone());
            continue;
        }
        let dirs: Vec<DirInfo> = parts[..parts.len() - 1].iter().map(|p| parse_dirname(p)).collect();
        let (kind, season) = classify_series_file(&info, &dirs);
        let (mut name, year) = match dirs.first() {
            Some(d) if !d.title.is_empty() => (d.title.clone(), d.year),
            _ => (info.show.clone(), info.year),
        };
        if name.is_empty() {
            name = stem;
        }
        let key = norm_key(&name);
        let entry = mk_entry(root, rel, *size, &info, &kind, season);
        if !groups.contains_key(&key) {
            order.push(key.clone());
            display.insert(key.clone(), name.clone());
        }
        groups.entry(key).or_default().push((entry, name, year));
    }
    let mut titles = vec![];
    let mut used: HashMap<String, usize> = HashMap::new();
    for key in order {
        let items = groups.remove(&key).unwrap();
        let mut years: Vec<i32> = items.iter().filter_map(|(_, _, y)| y.filter(|&y| y != 0)).collect();
        years.sort();
        years.dedup();
        let mut buckets: Vec<(Option<i32>, Vec<Entry>)> = vec![];
        for (entry, _n, year) in items {
            match buckets.iter_mut().find(|b| b.0 == year) {
                Some(b) => b.1.push(entry),
                None => buckets.push((year, vec![entry])),
            }
        }
        if let (Some(i), false) = (buckets.iter().position(|b| b.0.is_none()), years.is_empty()) {
            let (_, none_entries) = buckets.remove(i);
            match buckets.iter_mut().find(|b| b.0 == Some(years[0])) {
                Some(b) => b.1.extend(none_entries),
                None => buckets.push((Some(years[0]), none_entries)),
            }
        }
        for (year, entries) in buckets {
            let mut t = Title::new(unique_id(lib, &key, year, &mut used), lib, display[&key].clone(), year);
            finalize_series(&mut t, entries);
            titles.push(t);
        }
    }
    titles.sort_by_cached_key(|t| natural_key(&t.display()));
    (titles, skipped)
}

fn finalize_series(t: &mut Title, mut entries: Vec<Entry>) {
    let mains: Vec<usize> = (0..entries.len()).filter(|&i| entries[i].kind == "episode").collect();
    if mains.len() == 1 && entries[mains[0]].episode.is_none() && entries.len() == 1 {
        entries[mains[0]].kind = "movie".into();
        entries[mains[0]].season = None;
    }
    let mut best: HashMap<(Option<i32>, u64), usize> = HashMap::new();
    let mut dropped: HashSet<usize> = HashSet::new();
    for i in 0..entries.len() {
        let e = &entries[i];
        let Some(ep) = e.episode.filter(|_| e.kind == "episode") else { continue };
        let k = (e.season, ep.to_bits());
        match best.get(&k).copied() {
            Some(c) if (e.version, e.size) <= (entries[c].version, entries[c].size) => {
                dropped.insert(i);
                t.duplicates.push(entries[i].clone());
            }
            Some(c) => {
                dropped.insert(c);
                t.duplicates.push(entries[c].clone());
                best.insert(k, i);
            }
            None => {
                best.insert(k, i);
            }
        }
    }
    let mut keep: Vec<Entry> = entries.into_iter().enumerate().filter(|(i, _)| !dropped.contains(i)).map(|(_, e)| e).collect();
    keep.sort_by(cmp_order);
    t.entries = keep;
}

pub(crate) fn unique_id(lib: &str, key: &str, year: Option<i32>, used: &mut HashMap<String, usize>) -> String {
    let mut slug = rx(r"\s+").replace_all(key, "-").into_owned();
    if slug.is_empty() {
        slug = "untitled".into();
    }
    if let Some(y) = year.filter(|&y| y != 0) {
        slug.push_str(&format!("-{y}"));
    }
    let base = format!("{lib}/{slug}");
    let n = used.entry(base.clone()).or_insert(0);
    *n += 1;
    if *n == 1 { base } else { format!("{base}-{n}") }
}

fn build_movies(files: &[(String, i64)], root: &str) -> (Vec<Title>, Vec<String>) {
    let mut skipped = vec![];
    let mut dirs_order: Vec<String> = vec![];
    let mut by_dir: HashMap<String, Vec<(String, i64, FileInfo)>> = HashMap::new();
    for (rel, size) in sorted_files(files) {
        let parts: Vec<&str> = rel.split('/').collect();
        let info = parse_movie(splitext(parts[parts.len() - 1]).0);
        if info.kind == "sample" || in_samples_dir(&parts) {
            skipped.push(rel.clone());
            continue;
        }
        let d = parts[..parts.len() - 1].join("/");
        if !by_dir.contains_key(&d) {
            dirs_order.push(d.clone());
        }
        by_dir.entry(d).or_default().push((rel.clone(), *size, info));
    }
    let mut titles = vec![];
    let mut used = HashMap::new();
    for dpath in dirs_order {
        let items = &by_dir[&dpath];
        let dir_info = if dpath.is_empty() { None } else { Some(parse_movie(dpath.split('/').next().unwrap())) };
        for (rel, size, info) in items {
            let (mut name, mut year) = (
                if info.show.is_empty() { splitext(rel.rsplit('/').next().unwrap()).0.to_string() } else { info.show.clone() },
                info.year,
            );
            if let Some(di) = &dir_info {
                if items.len() == 1 && !di.show.is_empty() {
                    name = di.show.clone();
                    year = di.year.filter(|&y| y != 0).or(info.year);
                }
            }
            let mut entry = mk_entry(root, rel, *size, info, "movie", None);
            entry.name.clear();
            entry.episode = None;
            let mut t = Title::new(unique_id("movies", &norm_key(&name), year, &mut used), "movies", name, year);
            t.entries = vec![entry];
            titles.push(t);
        }
    }
    titles.sort_by_cached_key(|t| natural_key(&t.display()));
    (titles, skipped)
}

// ---- scan ----

pub fn walk_videos(root: &str) -> Vec<(String, i64)> {
    let root = crate::config::expand_user(root);
    let mut out = vec![];
    if !root.is_dir() {
        return out;
    }
    let mut seen = HashSet::new();
    walk(&root, &root, &mut seen, &mut out);
    out
}

fn walk(root: &Path, dir: &Path, seen: &mut HashSet<PathBuf>, out: &mut Vec<(String, i64)>) {
    let real = fs::canonicalize(dir).unwrap_or_else(|_| dir.to_path_buf());
    if !seen.insert(real) {
        return;
    }
    let Ok(rd) = fs::read_dir(dir) else { return };
    let mut dirs = vec![];
    let mut names = vec![];
    for e in rd.flatten() {
        let name = e.file_name().to_string_lossy().into_owned();
        match fs::metadata(e.path()) {
            Ok(m) if m.is_dir() => dirs.push(name),
            Ok(m) => names.push((name, m.len())),
            Err(_) => {}
        }
    }
    for (name, size) in names {
        let ext = splitext(&name).1.to_lowercase();
        if name.starts_with('.') || !VIDEO_EXTS.contains(&ext.as_str()) {
            continue;
        }
        let rel = dir.join(&name).strip_prefix(root).map(|p| p.to_string_lossy().into_owned()).unwrap_or(name);
        out.push((rel, size as i64));
    }
    dirs.retain(|d| !d.starts_with('.'));
    dirs.sort();
    for d in dirs {
        walk(root, &dir.join(d), seen, out);
    }
}

/// Changes whenever the parsing code does, so a cached catalog never outlives its parser.
fn code_stamp() -> u64 {
    let mut h = std::collections::hash_map::DefaultHasher::new();
    concat!(include_str!("parse.rs"), include_str!("catalog.rs")).hash(&mut h);
    h.finish()
}

fn scan_cache_path(lib: &str) -> PathBuf {
    let base = match std::env::var("MEDIATOR_CACHE_DIR") {
        Ok(v) if !v.is_empty() => PathBuf::from(v),
        _ => crate::config::cache_dir(),
    };
    base.join("scan").join(format!("{lib}.rust.json"))
}

pub fn scan(lib: &str, root: &str) -> (Vec<Title>, Vec<String>) {
    let root = crate::config::expand_user(root).to_string_lossy().into_owned();
    let files = walk_videos(&root);
    let mut h = std::collections::hash_map::DefaultHasher::new();
    (lib, &root, code_stamp(), &files).hash(&mut h);
    let key = format!("{:x}", h.finish());
    let path = scan_cache_path(lib);
    if let Ok(text) = fs::read_to_string(&path) {
        if let Ok(v) = serde_json::from_str::<Value>(&text) {
            if v["key"] == key.as_str() {
                if let (Ok(t), Ok(p)) = (serde_json::from_value(v["titles"].clone()), serde_json::from_value(v["problems"].clone())) {
                    return (t, p);
                }
            }
        }
    }
    let result = build_catalog(lib, &files, &root);
    let doc = serde_json::json!({"key": key, "problems": result.1, "titles": result.0});
    let _ = crate::fileio::atomic_write_text(&path, &doc.to_string(), 0o644);
    result
}

// ---- diagnostics ----

pub fn diagnose(titles: &[Title]) -> Vec<(String, String, String)> {
    let mut out = vec![];
    let mut add = |sev: &str, t: &Title, msg: String| out.push((sev.to_string(), t.display(), msg));
    for t in titles {
        if t.lib == "movies" {
            continue;
        }
        for e in &t.entries {
            if e.kind == "extra" || e.kind == "movie" {
                continue;
            }
            if e.kind == "episode" && e.episode.is_none() {
                add("warn", t, format!("no episode number: {}", e.rel));
            } else if e.confidence == "low" {
                add("warn", t, format!("guessed ({}): {}", e.rule, e.rel));
            } else if e.confidence == "medium" && e.kind == "episode" {
                add("info", t, format!("medium confidence ({}): {}", e.rule, e.rel));
            }
        }
        for e in &t.duplicates {
            add("warn", t, format!("duplicate {}: {}", e.code(), e.rel));
        }
        for (season, eps) in t.seasons() {
            let mut nums: Vec<i64> = eps.iter().filter_map(|e| e.episode.map(|x| x as i64)).collect();
            nums.sort();
            nums.dedup();
            if nums.len() < 2 {
                continue;
            }
            let set: HashSet<i64> = nums.iter().copied().collect();
            let missing: Vec<i64> = (nums[0]..=nums[nums.len() - 1]).filter(|n| !set.contains(n)).collect();
            if !missing.is_empty() {
                add("info", t, format!("season {season} gaps: {}", ranges(&missing)));
            }
        }
    }
    out
}

fn ranges(nums: &[i64]) -> String {
    let mut runs: Vec<(i64, i64)> = vec![];
    for &n in nums {
        match runs.last_mut() {
            Some(r) if n == r.1 + 1 => r.1 = n,
            _ => runs.push((n, n)),
        }
    }
    runs.iter().map(|(a, b)| if a == b { a.to_string() } else { format!("{a}-{b}") }).collect::<Vec<_>>().join(", ")
}
