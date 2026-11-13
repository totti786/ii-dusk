//! Keep Mediator's caches from growing for ever (see `mediator/housekeeping.py`).
//! Only data that is cheap to fetch again is removed; posters, art, info, progress and settings never.
use serde_json::Value;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

const DAY: f64 = 86400.0;
pub const STREAM_URL_TTL: f64 = 2.0 * DAY;
const PROTECTED: &[&str] = &["index.json"];
/// (directory, max age days, max megabytes)
pub const CACHES: &[(&str, f64, Option<u64>)] = &[("images", 60.0, Some(300)), ("http", 30.0, Some(100)), ("subs", 7.0, None)];

pub fn cache_root() -> PathBuf {
    crate::config::cache_dir()
}

fn secs(t: SystemTime) -> f64 {
    t.duration_since(UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0)
}

fn files(dir: &Path, use_atime: bool, out: &mut Vec<(PathBuf, f64, u64)>) {
    let Ok(rd) = fs::read_dir(dir) else { return };
    for e in rd.flatten() {
        let p = e.path();
        let Ok(md) = fs::metadata(&p) else { continue };
        if md.is_dir() {
            files(&p, use_atime, out);
        } else {
            let m = md.modified().map(secs).unwrap_or(0.0);
            let t = if use_atime { m.max(md.accessed().map(secs).unwrap_or(0.0)) } else { m };
            out.push((p, t, md.len()));
        }
    }
}

/// Delete files older than `max_age_days`, then the oldest until under `max_mb`.
/// Returns (files removed, bytes freed).
pub fn prune_dir(path: &Path, max_age_days: f64, max_mb: Option<u64>, now: Option<f64>, use_atime: bool) -> (u64, u64) {
    let now = now.unwrap_or_else(crate::state::now);
    let (mut removed, mut freed) = (0, 0);
    let mut all = vec![];
    files(path, use_atime, &mut all);
    let mut keep = vec![];
    for (full, t, size) in all {
        if full.file_name().map(|n| PROTECTED.contains(&n.to_string_lossy().as_ref())).unwrap_or(false) {
            continue;
        }
        if now - t > max_age_days * DAY {
            if fs::remove_file(&full).is_ok() {
                removed += 1;
                freed += size;
            }
        } else {
            keep.push((full, t, size));
        }
    }
    if let Some(mb) = max_mb {
        let mut total: u64 = keep.iter().map(|k| k.2).sum();
        keep.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap());
        for (full, _, size) in keep {
            if total <= mb * 1024 * 1024 {
                break;
            }
            if fs::remove_file(&full).is_ok() {
                removed += 1;
                freed += size;
                total -= size;
            }
        }
    }
    (removed, freed)
}

/// Drop image-index entries whose file is gone. Returns how many went.
pub fn forget_missing_images(images_dir: &Path) -> usize {
    let idx = images_dir.join("index.json");
    let Value::Object(map) = crate::fileio::read_json(&idx) else { return 0 };
    let live: serde_json::Map<String, Value> = map
        .iter()
        .filter(|(_, v)| v.as_str().map(|p| Path::new(p).exists()).unwrap_or(false))
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect();
    let gone = map.len() - live.len();
    if gone > 0 {
        let _ = crate::fileio::atomic_write_text(&idx, &serde_json::to_string(&Value::Object(live)).unwrap(), 0o644);
    }
    gone
}

/// Forget remembered direct-stream URLs that have expired (torrents are kept).
pub fn prune_streams(state_dir: &Path, now: Option<f64>) -> usize {
    let now = now.unwrap_or_else(crate::state::now);
    let path = state_dir.join("stremio-streams.json");
    if !path.exists() {
        return 0;
    }
    let mut dropped = 0;
    let _ = crate::fileio::update_json(&path, |data| {
        let keys: Vec<String> = data.keys().cloned().collect();
        for k in keys {
            let Some(e) = data[&k].as_object() else { continue };
            let torrent = e.get("infoHash").map(|v| v.as_str().map(|s| !s.is_empty()).unwrap_or(!v.is_null())).unwrap_or(false);
            let has_url = e.get("url").and_then(|v| v.as_str()).map(|s| !s.is_empty()).unwrap_or(false);
            if torrent || !has_url {
                continue;
            }
            let at = e.get("at").and_then(|v| v.as_f64()).unwrap_or(0.0);
            if now - at > STREAM_URL_TTL {
                data.remove(&k);
                dropped += 1;
            }
        }
    });
    dropped
}

fn tree_size(p: &Path) -> u64 {
    let mut v = vec![];
    files(p, false, &mut v);
    v.iter().map(|f| f.2).sum()
}

pub fn sizes() -> BTreeMap<String, u64> {
    let mut out = BTreeMap::new();
    let Ok(rd) = fs::read_dir(cache_root()) else { return out };
    for e in rd.flatten() {
        let p = e.path();
        let n = if p.is_dir() { tree_size(&p) } else { fs::metadata(&p).map(|m| m.len()).unwrap_or(0) };
        out.insert(e.file_name().to_string_lossy().into_owned(), n);
    }
    out
}

pub struct Report {
    pub files: u64,
    pub bytes: u64,
    pub stream_entries: usize,
}

pub fn run() -> Report {
    let root = cache_root();
    let mut r = Report { files: 0, bytes: 0, stream_entries: 0 };
    for (name, days, mb) in CACHES {
        let p = root.join(name);
        if p.is_dir() {
            let (n, freed) = prune_dir(&p, *days, *mb, None, *name == "images");
            r.files += n;
            r.bytes += freed;
            if *name == "images" && n > 0 {
                forget_missing_images(&p);
            }
        }
    }
    r.stream_entries = prune_streams(&crate::config::state_dir(), None);
    r
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn touch(p: &Path, bytes: usize, age_days: f64) {
        fs::create_dir_all(p.parent().unwrap()).unwrap();
        fs::write(p, vec![0u8; bytes]).unwrap();
        let t = SystemTime::now() - std::time::Duration::from_secs_f64(age_days * DAY);
        fs::File::options().write(true).open(p).unwrap().set_modified(t).unwrap();
    }

    #[test]
    fn prunes_by_age_and_keeps_index() {
        let d = tempfile::tempdir().unwrap();
        touch(&d.path().join("old"), 10, 90.0);
        touch(&d.path().join("new"), 10, 1.0);
        touch(&d.path().join("index.json"), 10, 400.0);
        let (n, freed) = prune_dir(d.path(), 60.0, None, None, false);
        assert_eq!((n, freed), (1, 10));
        assert!(d.path().join("new").exists() && d.path().join("index.json").exists());
    }

    #[test]
    fn prunes_oldest_over_size() {
        let d = tempfile::tempdir().unwrap();
        touch(&d.path().join("a"), 700_000, 3.0);
        touch(&d.path().join("b"), 700_000, 2.0);
        touch(&d.path().join("c"), 700_000, 1.0);
        let (n, _) = prune_dir(d.path(), 60.0, Some(1), None, false);
        assert_eq!(n, 2);
        assert!(d.path().join("c").exists());
    }

    #[test]
    fn index_forgets_missing_files() {
        let d = tempfile::tempdir().unwrap();
        let keep = d.path().join("k.jpg");
        fs::write(&keep, b"x").unwrap();
        let idx = json!({"u1": keep.to_string_lossy(), "u2": d.path().join("gone.jpg").to_string_lossy()});
        fs::write(d.path().join("index.json"), idx.to_string()).unwrap();
        assert_eq!(forget_missing_images(d.path()), 1);
        assert_eq!(crate::fileio::read_json(&d.path().join("index.json")).as_object().unwrap().len(), 1);
    }

    #[test]
    fn stream_urls_expire_but_torrents_stay() {
        let d = tempfile::tempdir().unwrap();
        let t = 1_000_000.0;
        fs::write(d.path().join("stremio-streams.json"), json!({
            "old": {"url": "http://x", "at": t - 3.0 * DAY},
            "fresh": {"url": "http://y", "at": t - 1.0},
            "tor": {"infoHash": "abc", "url": "", "at": 0},
            "bare": {"url": "http://z"}
        }).to_string()).unwrap();
        assert_eq!(prune_streams(d.path(), Some(t)), 2);
        let left = crate::fileio::read_json(&d.path().join("stremio-streams.json"));
        let mut keys: Vec<_> = left.as_object().unwrap().keys().cloned().collect();
        keys.sort();
        assert_eq!(keys, ["fresh", "tor"]);
    }
}
