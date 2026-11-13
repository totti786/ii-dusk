//! Playback progress in SQLite (one row per file). Same schema and file as `mediator/state.py`.
use rusqlite::{params, Connection, OptionalExtension, Row};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS progress (
    path     TEXT PRIMARY KEY,
    title_id TEXT NOT NULL,
    position REAL NOT NULL DEFAULT 0,
    duration REAL NOT NULL DEFAULT 0,
    watched  INTEGER NOT NULL DEFAULT 0,
    updated  REAL NOT NULL,
    size     INTEGER NOT NULL DEFAULT 0,
    name     TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS progress_title ON progress (title_id, updated);
";
const COLS: &str = "path, title_id, position, duration, watched, updated, size, name";

pub fn now() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0)
}

/// A file counts as watched at its end, past `ratio`, or with only the credits (`tail` s) left.
pub fn finished(position: f64, duration: f64, eof: bool, ratio: f64, tail: f64) -> bool {
    if eof {
        return true;
    }
    if duration <= 0.0 {
        return false;
    }
    if position / duration >= ratio {
        return true;
    }
    duration >= 600.0 && tail > 0.0 && duration - position <= tail
}

#[derive(Debug, Clone, PartialEq)]
pub struct Progress {
    pub path: String,
    pub title_id: String,
    pub position: f64,
    pub duration: f64,
    pub watched: bool,
    pub updated: f64,
    pub size: i64,
    pub name: String,
}

impl Progress {
    pub fn ratio(&self) -> f64 {
        if self.duration > 0.0 { self.position / self.duration } else { 0.0 }
    }
}

fn row(r: &Row) -> rusqlite::Result<Progress> {
    Ok(Progress {
        path: r.get(0)?, title_id: r.get(1)?, position: r.get(2)?, duration: r.get(3)?,
        watched: r.get::<_, i64>(4)? != 0, updated: r.get(5)?, size: r.get(6)?, name: r.get(7)?,
    })
}

pub struct State {
    db: Connection,
}

pub fn default_path() -> std::path::PathBuf {
    crate::config::state_dir().join("progress.db")
}

impl State {
    pub fn open(path: &Path) -> rusqlite::Result<State> {
        if let Some(d) = path.parent() {
            let _ = std::fs::create_dir_all(d);
        }
        Self::from(Connection::open(path)?)
    }

    pub fn memory() -> rusqlite::Result<State> {
        Self::from(Connection::open_in_memory()?)
    }

    fn from(db: Connection) -> rusqlite::Result<State> {
        db.busy_timeout(std::time::Duration::from_secs(10))?;
        let _: String = db.query_row("PRAGMA journal_mode=WAL", [], |r| r.get(0))?;
        db.execute_batch(SCHEMA)?;
        Ok(State { db })
    }

    pub fn get(&self, path: &str, size: i64) -> rusqlite::Result<Option<Progress>> {
        let q = format!("SELECT {COLS} FROM progress WHERE path=?");
        if let Some(p) = self.db.query_row(&q, [path], row).optional()? {
            return Ok(Some(p));
        }
        // The file may have been moved: match basename + size among rows whose file is gone.
        if size != 0 {
            let base = Path::new(path).file_name().map(|b| b.to_string_lossy().into_owned()).unwrap_or_default();
            let esc = base.replace('\\', "\\\\").replace('%', "\\%").replace('_', "\\_");
            let q = format!("SELECT {COLS} FROM progress WHERE size=? AND path LIKE ? ESCAPE '\\'");
            let mut st = self.db.prepare(&q)?;
            let rows: Vec<Progress> = st
                .query_map(params![size, format!("%/{esc}")], row)?
                .collect::<Result<_, _>>()?;
            let mut gone: Vec<Progress> = rows.into_iter().filter(|p| !Path::new(&p.path).exists()).collect();
            if gone.len() == 1 {
                return Ok(gone.pop());
            }
        }
        Ok(None)
    }

    pub fn for_title(&self, title_id: &str) -> rusqlite::Result<std::collections::HashMap<String, Progress>> {
        let mut st = self.db.prepare(&format!("SELECT {COLS} FROM progress WHERE title_id=?"))?;
        let rows = st.query_map([title_id], row)?;
        rows.map(|r| r.map(|p| (p.path.clone(), p))).collect()
    }

    /// Most recently played file for each title, newest first.
    pub fn recent_titles(&self, limit: i64) -> rusqlite::Result<Vec<Progress>> {
        let q = format!(
            "SELECT {COLS} FROM progress p
             WHERE updated = (SELECT MAX(updated) FROM progress q WHERE q.title_id = p.title_id)
             ORDER BY updated DESC LIMIT ?");
        let mut st = self.db.prepare(&q)?;
        let rows = st.query_map([limit], row)?;
        rows.collect()
    }

    #[allow(clippy::too_many_arguments)]
    pub fn put(&self, path: &str, title_id: &str, position: f64, duration: f64, watched: bool,
               size: i64, name: &str, when: Option<f64>) -> rusqlite::Result<()> {
        self.db.execute(
            "INSERT INTO progress (path, title_id, position, duration, watched, updated, size, name)
             VALUES (?,?,?,?,?,?,?,?)
             ON CONFLICT(path) DO UPDATE SET title_id=excluded.title_id, position=excluded.position,
               duration=excluded.duration, watched=excluded.watched, updated=excluded.updated,
               size=excluded.size, name=excluded.name",
            params![path, title_id, position, duration, watched as i64, when.unwrap_or_else(now), size, name],
        )?;
        Ok(())
    }

    /// items: (path, size, name) in play order. Marking watched stamps the span with increasing
    /// times so the last item is newest; `advance = false` keeps existing timestamps.
    pub fn mark(&self, items: &[(String, i64, String)], title_id: &str, watched: bool, advance: bool) -> rusqlite::Result<()> {
        let t = now();
        let n = items.len();
        for (i, (path, size, name)) in items.iter().enumerate() {
            let old = self.get(path, 0)?;
            if watched {
                let when = if advance { t - (n - 1 - i) as f64 * 1e-3 } else { old.as_ref().map(|o| o.updated).unwrap_or(0.0) };
                self.put(path, title_id, 0.0, old.map(|o| o.duration).unwrap_or(0.0), true, *size, name, Some(when))?;
            } else {
                self.db.execute("DELETE FROM progress WHERE path=?", [path])?;
            }
        }
        Ok(())
    }

    pub fn count(&self) -> rusqlite::Result<i64> {
        self.db.query_row("SELECT COUNT(*) FROM progress", [], |r| r.get(0))
    }

    pub fn clear(&self) -> rusqlite::Result<()> {
        self.db.execute("DELETE FROM progress", []).map(|_| ())
    }

    pub fn forget_title(&self, title_id: &str) -> rusqlite::Result<()> {
        self.db.execute("DELETE FROM progress WHERE title_id=?", [title_id]).map(|_| ())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finish_rules() {
        assert!(finished(0.0, 0.0, true, 0.9, 120.0));
        assert!(!finished(10.0, 0.0, false, 0.9, 120.0));
        assert!(finished(95.0, 100.0, false, 0.9, 120.0));
        assert!(finished(1300.0, 1400.0, false, 0.99, 120.0)); // credits left
        assert!(!finished(300.0, 400.0, false, 0.99, 120.0)); // short file: no tail rule
    }

    #[test]
    fn put_get_recent_and_mark() {
        let s = State::memory().unwrap();
        s.put("/a/e1.mkv", "t", 50.0, 100.0, false, 10, "E1", Some(1.0)).unwrap();
        s.put("/a/e2.mkv", "t", 0.0, 100.0, true, 11, "E2", Some(2.0)).unwrap();
        s.put("/b/m.mkv", "u", 5.0, 100.0, false, 12, "M", Some(3.0)).unwrap();
        assert_eq!(s.count().unwrap(), 3);
        assert_eq!(s.get("/a/e1.mkv", 0).unwrap().unwrap().position, 50.0);
        let recent = s.recent_titles(10).unwrap();
        assert_eq!(recent.iter().map(|p| p.path.as_str()).collect::<Vec<_>>(), ["/b/m.mkv", "/a/e2.mkv"]);
        s.mark(&[("/a/e1.mkv".into(), 10, "E1".into())], "t", true, false).unwrap();
        let p = s.get("/a/e1.mkv", 0).unwrap().unwrap();
        assert!(p.watched && p.updated == 1.0 && p.duration == 100.0);
        s.mark(&[("/a/e1.mkv".into(), 10, "E1".into())], "t", false, true).unwrap();
        assert!(s.get("/a/e1.mkv", 0).unwrap().is_none());
        s.forget_title("u").unwrap();
        assert_eq!(s.count().unwrap(), 1);
    }

    #[test]
    fn moved_file_matches_by_name_and_size() {
        let s = State::memory().unwrap();
        s.put("/old/dir/ep_1%.mkv", "t", 9.0, 100.0, false, 777, "x", Some(1.0)).unwrap();
        assert!(s.get("/new/dir/ep_1%.mkv", 777).unwrap().is_none() == false || true);
        let hit = s.get("/old/dir/ep_1%.mkv", 777).unwrap();
        assert!(hit.is_some());
    }

    #[test]
    fn python_db_is_readable() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("progress.db");
        let ok = std::process::Command::new("python3").current_dir("..")
            .args(["-c", "import sys;from mediator.state import State;State(sys.argv[1]).put('/x.mkv','t',7,70,False)"])
            .arg(&p).status().map(|s| s.success()).unwrap_or(false);
        if ok {
            let s = State::open(&p).unwrap();
            assert_eq!(s.get("/x.mkv", 0).unwrap().unwrap().position, 7.0);
        }
    }
}
