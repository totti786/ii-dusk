//! A small companion process that lets a shell follow mediator live (port of `mediator/daemon.py`).
//!
//! Protocol: one JSON object per line over a Unix socket in $XDG_RUNTIME_DIR. Requests carry a
//! "cmd"; replies echo an optional "id". Events carry an "event". A client that sends
//! {"cmd": "subscribe"} gets the current state straight away and every change after it.
//!
//!   {"cmd":"control","action":"toggle"|"pause"|"play"|"next"|"prev"|"stop"}
//!   {"cmd":"control","action":"seek","value":-10}   {"cmd":"control","action":"seek_to","value":120}
//!   {"cmd":"control","action":"speed","value":1.25}   {"cmd":"control","action":"volume","value":80}
//!   {"cmd":"enrich","scope":"missing"|"all"|"<title id>","refresh":false,"auto":false}
//!   {"cmd":"enrich_stop"}   {"cmd":"status"}
//!
//! It exits by itself after `IDLE_EXIT` seconds with no client and nothing playing, and does no
//! disk watching while nobody is connected. Threads, not an async runtime: a handful of sockets.
use crate::catalog::{scan, Entry, Title};
use crate::config::{self, Config};
use crate::{info, meta, posters};
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, HashMap};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::os::unix::net::{UnixListener, UnixStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

pub const IDLE_EXIT: f64 = 15.0 * 60.0;
pub const OBSERVED: [&str; 11] = ["path", "time-pos", "duration", "pause", "speed", "volume", "media-title", "playlist-pos", "playlist-count", "eof-reached", "paused-for-cache"];

pub fn runtime_dir() -> String {
    std::env::var("XDG_RUNTIME_DIR").ok().filter(|v| !v.is_empty()).unwrap_or_else(|| "/tmp".into())
}
pub fn sock_path() -> String {
    std::env::var("MEDIATOR_DAEMON_SOCK").ok().filter(|v| !v.is_empty()).unwrap_or_else(|| format!("{}/mediator-daemon.sock", runtime_dir()))
}

/// Identifies the binary this process started from: path, mtime and size. A rebuilt copy changes
/// it, and the daemon then restarts.
pub fn code_stamp() -> (String, i64, u64) {
    let exe = std::env::current_exe().map(|p| p.to_string_lossy().into_owned()).unwrap_or_default();
    let exe = exe.strip_suffix(" (deleted)").unwrap_or(&exe).to_string();
    match std::fs::metadata(&exe) {
        Ok(m) => (exe, m.mtime() * 1_000_000_000 + m.mtime_nsec(), m.len()),
        Err(_) => (exe, 0, 0),
    }
}

fn pid_of(sock_path: &str) -> Option<i64> {
    let name = std::path::Path::new(sock_path).file_name()?.to_string_lossy().into_owned();
    let stem = name.strip_prefix("mediator-")?.strip_suffix(".sock")?;
    if !stem.is_empty() && stem.chars().all(|c| c.is_ascii_digit()) { stem.parse().ok() } else { None }
}

/// Is something listening on this socket? The launcher that named it may be long gone while its
/// mpv carries on (a shell reload kills the launcher, not the player).
fn answers(sock: &str) -> bool {
    UnixStream::connect(sock).is_ok()
}

/// Wakes the session scan the moment a socket appears or goes away in the runtime directory,
/// instead of waiting out the 2 s poll. Falls back to a plain sleep when inotify is unavailable.
struct RuntimeWatch(i32);

impl RuntimeWatch {
    fn new(dir: &str) -> Option<RuntimeWatch> {
        let c = std::ffi::CString::new(dir).ok()?;
        unsafe {
            let fd = libc::inotify_init1(libc::IN_NONBLOCK | libc::IN_CLOEXEC);
            if fd < 0 {
                return None;
            }
            if libc::inotify_add_watch(fd, c.as_ptr(), libc::IN_CREATE | libc::IN_DELETE | libc::IN_MOVED_TO) < 0 {
                libc::close(fd);
                return None;
            }
            Some(RuntimeWatch(fd))
        }
    }

    /// Returns after something changed (debounced) or after `timeout`, whichever is first.
    fn wait(&self, timeout: Duration) {
        let mut p = libc::pollfd { fd: self.0, events: libc::POLLIN, revents: 0 };
        let ready = unsafe { libc::poll(&mut p, 1, timeout.as_millis() as i32) };
        if ready > 0 {
            std::thread::sleep(Duration::from_millis(60)); // let a burst of events settle
            let mut buf = [0u8; 4096];
            while unsafe { libc::read(self.0, buf.as_mut_ptr() as *mut _, buf.len()) } > 0 {}
        }
    }
}

impl Drop for RuntimeWatch {
    fn drop(&mut self) {
        unsafe { libc::close(self.0) };
    }
}

fn alive(pid: i64) -> bool {
    unsafe {
        if libc::kill(pid as i32, 0) == 0 {
            return true;
        }
        std::io::Error::last_os_error().raw_os_error() == Some(libc::EPERM)
    }
}

fn truthy(v: &Value) -> bool {
    match v { Value::Null => false, Value::Bool(b) => *b, Value::Number(n) => n.as_f64() != Some(0.0), Value::String(s) => !s.is_empty(), Value::Array(a) => !a.is_empty(), Value::Object(o) => !o.is_empty() }
}
fn or_default(v: &Value, d: Value) -> Value {
    if truthy(v) { v.clone() } else { d }
}
/// An episode number the way JSON stored it: whole numbers as integers.
fn num_value(f: f64) -> Value {
    if f == f.trunc() { json!(f as i64) } else { json!(f) }
}

pub struct Client {
    writer: Mutex<UnixStream>,
}
impl Client {
    fn send(&self, data: &[u8]) -> bool {
        self.writer.lock().map(|mut w| w.write_all(data).is_ok()).unwrap_or(false)
    }
}

#[derive(Default)]
struct Index {
    map: HashMap<String, (Title, Entry)>,
    at: f64,
    miss_at: f64,
}

#[derive(Clone)]
pub struct EnrichState {
    pub running: bool,
    pub done: i64,
    pub total: i64,
    pub current: String,
    pub errors: i64,
}
impl EnrichState {
    fn json(&self) -> Value {
        json!({"event": "enrich", "running": self.running, "done": self.done, "total": self.total, "current": self.current, "errors": self.errors})
    }
}

/// One mpv started by mediator, observed over a second IPC connection.
pub struct Session {
    pub sock_path: String,
    pub pid: Option<i64>,
    pub started: f64,
    props: Mutex<Map<String, Value>>,
    writer: Mutex<Option<UnixStream>>,
    last_pos_push: Mutex<Option<Instant>>,
    held_path: Mutex<String>,
    native: Mutex<Value>,
}

fn http_path(p: &str) -> bool {
    p.starts_with("http://") || p.starts_with("https://")
}

impl Session {
    fn new(sock: &str) -> Session {
        Session { sock_path: sock.into(), pid: pid_of(sock), started: crate::state::now(), props: Mutex::new(Map::new()), writer: Mutex::new(None), last_pos_push: Mutex::new(None), held_path: Mutex::new(String::new()), native: Mutex::new(Value::Null) }
    }

    fn prop(&self, k: &str) -> Value {
        self.props.lock().unwrap().get(k).cloned().unwrap_or(Value::Null)
    }

    /// Blocks until mpv closes the connection.
    fn run(&self, d: &Arc<Daemon>) {
        // mpv creates its socket a moment before it listens on it: a session found that early gets
        // a short grace period instead of being dropped until the next scan
        let mut tries = 0;
        let stream = loop {
            match UnixStream::connect(&self.sock_path) {
                Ok(s) => break s,
                Err(_) if tries < 30 && std::path::Path::new(&self.sock_path).exists() => {
                    tries += 1;
                    std::thread::sleep(Duration::from_millis(50));
                }
                Err(_) => return,
            }
        };
        let Ok(mut w) = stream.try_clone() else { return };
        for (i, prop) in OBSERVED.iter().enumerate() {
            if w.write_all(format!("{}\n", json!({"command": ["observe_property", i + 1, prop]})).as_bytes()).is_err() {
                return;
            }
        }
        *self.writer.lock().unwrap() = Some(w);
        for line in BufReader::new(stream).lines() {
            let Ok(line) = line else { break };
            let Ok(msg) = serde_json::from_str::<Value>(&line) else { continue };
            if msg["event"] != "property-change" {
                continue;
            }
            let name = msg["name"].as_str().unwrap_or("").to_string();
            let data = msg["data"].clone();
            self.props.lock().unwrap().insert(name.clone(), data.clone());
            if name == "path" && http_path(data.as_str().unwrap_or("")) {
                // the stream worker records the new episode a moment after mpv moves on; look again once it has
                for delay in [0.3, 1.0] {
                    let d = d.clone();
                    std::thread::spawn(move || {
                        std::thread::sleep(Duration::from_secs_f64(delay));
                        d.push_now();
                    });
                }
            }
            if name == "time-pos" {
                let mut last = self.last_pos_push.lock().unwrap();
                if last.map(|t| t.elapsed() < Duration::from_secs(1)).unwrap_or(false) {
                    continue; // position ticks many times a second; a shell needs one
                }
                *last = Some(Instant::now());
            }
            d.push_now();
        }
    }

    fn close(&self) {
        if let Some(w) = self.writer.lock().unwrap().take() {
            let _ = w.shutdown(std::net::Shutdown::Both);
        }
    }

    fn command(&self, args: Vec<Value>) {
        if let Some(w) = self.writer.lock().unwrap().as_mut() {
            let _ = w.write_all(format!("{}\n", json!({"command": args})).as_bytes());
        }
    }

    pub fn view(&self, d: &Daemon) -> Value {
        let mut path = self.prop("path").as_str().unwrap_or("").to_string();
        {
            let mut held = self.held_path.lock().unwrap();
            if http_path(&path) {
                *held = path.clone();
            } else if path.is_empty() && !held.is_empty() {
                // mpv's path is empty for a moment while it opens the next queued episode
                path = held.clone();
            }
        }
        let p = self.props.lock().unwrap().clone();
        let g = |k: &str| p.get(k).cloned().unwrap_or(Value::Null);
        let mut out = Map::new();
        out.insert("pid".into(), json!(self.pid));
        out.insert("path".into(), json!(path));
        out.insert("position".into(), or_default(&g("time-pos"), json!(0.0)));
        out.insert("duration".into(), or_default(&g("duration"), json!(0.0)));
        out.insert("paused".into(), json!(truthy(&g("pause"))));
        out.insert("buffering".into(), json!(truthy(&g("paused-for-cache"))));
        out.insert("speed".into(), or_default(&g("speed"), json!(1.0)));
        out.insert("volume".into(), g("volume"));
        out.insert("playlist_pos".into(), g("playlist-pos"));
        out.insert("playlist_count".into(), g("playlist-count"));
        out.insert("media_title".into(), or_default(&g("media-title"), json!("")));
        out.insert("started".into(), json!(self.started));
        if let Some((title, entry)) = d.lookup(&path) {
            out.insert("title_id".into(), json!(title.id));
            out.insert("title".into(), json!(title.display()));
            out.insert("lib".into(), json!(title.lib));
            out.insert("label".into(), json!(entry.label()));
            out.insert("code".into(), json!(entry.code()));
            out.insert("poster".into(), posters::find(&title).map(|p| json!(p.to_string_lossy())).unwrap_or(Value::Null));
            if title.source == "jellyfin" && !entry.name.is_empty() {
                out.insert("episode_title".into(), json!(entry.name));
            }
            if title.lib != "movies" {
                // the whole series, so the card can offer an episode list and switch inside this mpv
                let eps: Vec<Value> = title.entries.iter().filter_map(|e| {
                    let n = e.episode?;
                    // "S01E03", the shape the Stremio episode lists use, so the card groups by season
                    Some(json!({"id": e.path, "number": format!("S{:02}E{:02}", e.season.unwrap_or(1), n as i64), "title": e.name}))
                }).collect();
                if eps.len() > 1 {
                    out.insert("episodes".into(), json!(eps));
                }
            }
            if let (Some(rec), Some(n)) = (info::find(&title), entry.episode) {
                if let Some(ep) = info::episode_for(&rec, &json!(entry.season.unwrap_or(1)), &num_value(n)) {
                    out.insert("episode_title".into(), ep["title"].clone());
                    out.insert("still".into(), ep["image"].clone());
                }
            }
        } else if http_path(&path) {
            let base = std::path::Path::new(&self.sock_path).file_name().map(|b| b.to_string_lossy().into_owned()).unwrap_or_default();
            let mut native = crate::native_progress::load_for_socket(&base);
            let mut held = self.native.lock().unwrap();
            if !crate::native_progress::is_empty(&native) {
                *held = native.clone();
            } else {
                native = held.clone(); // mid-switch between episodes: keep showing the last one
            }
            if truthy(&native) && !crate::native_progress::is_empty(&native) {
                let number = match &native["episode_number"] { Value::String(s) => s.trim().to_string(), Value::Null => String::new(), o => o.to_string() };
                let show_id = native["show_id"].as_str().unwrap_or("").to_string();
                out.insert("title_id".into(), json!(format!("online/{show_id}")));
                out.insert("title".into(), or_default(&native["title"], json!(show_id)));
                out.insert("lib".into(), json!("online"));
                // a movie has no episode; Stremio episodes already read "S01E02"
                let label = if number.is_empty() { String::new() } else if crate::parse::rx(r"^S\d+E\d+$").is_match(&number).unwrap_or(false) { number } else { format!("Episode {number}") };
                out.insert("label".into(), json!(label));
                out.insert("code".into(), json!(""));
                out.insert("poster".into(), or_default(&native["poster"], json!("")));
                if truthy(&native["episode_title"]) {
                    out.insert("episode_title".into(), native["episode_title"].clone());
                }
                out.insert("native".into(), json!({"show_id": show_id, "episode_id": native["episode_id"].as_str().unwrap_or("")}));
            }
        }
        Value::Object(out)
    }
}

pub struct Daemon {
    pub cfg: Mutex<Config>,
    sessions: Mutex<BTreeMap<String, Arc<Session>>>,
    clients: Mutex<Vec<Arc<Client>>>,
    index: Mutex<Index>,
    pub enrich_state: Mutex<EnrichState>,
    enrich_stop: AtomicBool,
    enrich_running: AtomicBool,
    cfg_stamp: Mutex<(i64, u64)>,
    watch: Mutex<Vec<i64>>,
    idle_since: Mutex<Instant>,
    code: (String, i64, u64),
    mpris: Mutex<Option<Box<dyn crate::mpris::Handle>>>,
}

fn config_stamp() -> (i64, u64) {
    std::fs::metadata(config::config_path()).map(|m| (m.mtime() * 1_000_000_000 + m.mtime_nsec(), m.len())).unwrap_or((0, 0))
}

fn mtime_ns(p: &std::path::Path) -> i64 {
    std::fs::metadata(p).map(|m| m.mtime() * 1_000_000_000 + m.mtime_nsec()).unwrap_or(0)
}

impl Daemon {
    pub fn new() -> Arc<Daemon> {
        let cfg = config::load();
        let d = Arc::new(Daemon {
            cfg: Mutex::new(cfg), sessions: Mutex::new(BTreeMap::new()), clients: Mutex::new(vec![]), index: Mutex::new(Index::default()),
            enrich_state: Mutex::new(EnrichState { running: false, done: 0, total: 0, current: String::new(), errors: 0 }),
            enrich_stop: AtomicBool::new(false), enrich_running: AtomicBool::new(false), cfg_stamp: Mutex::new(config_stamp()),
            watch: Mutex::new(vec![]), idle_since: Mutex::new(Instant::now()), code: code_stamp(), mpris: Mutex::new(None),
        });
        let fp = d.fingerprint();
        *d.watch.lock().unwrap() = fp;
        d
    }

    // ---- catalog index (path -> title, entry), local libraries only
    pub fn lookup(&self, path: &str) -> Option<(Title, Entry)> {
        if path.is_empty() {
            return None;
        }
        if path.contains("://") {
            // a remote stream never triggers a scan; only a Jellyfin item already indexed matches
            return self.index.lock().unwrap().map.get(path).cloned();
        }
        let (hit, rescan) = {
            let ix = self.index.lock().unwrap();
            let hit = ix.map.get(path).cloned();
            (hit.clone(), hit.is_none() && (ix.at == 0.0 || crate::state::now() - ix.miss_at > 30.0))
        };
        if hit.is_some() || !rescan {
            return hit;
        }
        // one rescan per miss window: a path that is not ours must not rescan the library every few seconds
        self.index.lock().unwrap().miss_at = crate::state::now();
        self.reindex();
        self.index.lock().unwrap().map.get(path).cloned()
    }

    pub fn reindex(&self) {
        let cfg = self.cfg.lock().unwrap().clone();
        let mut map = HashMap::new();
        for kind in ["anime", "shows", "movies"] {
            let Some(root) = cfg.libraries.get(kind).filter(|r| !r.is_empty()) else { continue };
            for t in scan(kind, root).0 {
                for e in &t.entries {
                    map.insert(e.path.clone(), (t.clone(), e.clone()));
                }
            }
        }
        if cfg.jellyfin.configured() {
            // the server's cached listing (no network): its stream URLs are the sessions' paths
            let client = crate::jellyfin::Jellyfin::new(&cfg.jellyfin);
            for kind in client.kinds() {
                if let Some(lib) = client.cached_library(kind) {
                    for t in lib.titles {
                        for e in &t.entries {
                            map.insert(e.path.clone(), (t.clone(), e.clone()));
                        }
                    }
                }
            }
        }
        let mut ix = self.index.lock().unwrap();
        ix.map = map;
        ix.at = crate::state::now();
    }

    // ---- what the clients see
    fn ordered(&self) -> Vec<Arc<Session>> {
        let mut v: Vec<Arc<Session>> = self.sessions.lock().unwrap().values().cloned().collect();
        v.sort_by(|a, b| b.started.partial_cmp(&a.started).unwrap_or(std::cmp::Ordering::Equal));
        v
    }

    pub fn snapshot(&self) -> Value {
        json!({"event": "now", "sessions": self.ordered().iter().map(|s| s.view(self)).collect::<Vec<_>>()})
    }

    pub fn broadcast(&self, msg: &Value) {
        let data = format!("{msg}\n");
        let clients: Vec<Arc<Client>> = self.clients.lock().unwrap().clone();
        let dead: Vec<Arc<Client>> = clients.into_iter().filter(|c| !c.send(data.as_bytes())).collect();
        if !dead.is_empty() {
            self.clients.lock().unwrap().retain(|c| !dead.iter().any(|d| Arc::ptr_eq(c, d)));
        }
    }

    pub fn push_now(&self) {
        self.broadcast(&self.snapshot());
        if let Some(m) = self.mpris.lock().unwrap().as_ref() {
            m.sync();
        }
    }

    fn push_enrich(&self) {
        let v = self.enrich_state.lock().unwrap().json();
        self.broadcast(&v);
    }

    // ---- sessions
    fn scan_sessions(self: &Arc<Self>) {
        let own = std::path::Path::new(&sock_path()).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        let watch = RuntimeWatch::new(&runtime_dir());
        loop {
            let found: Vec<String> = std::fs::read_dir(runtime_dir()).map(|rd| rd.filter_map(|e| e.ok()).map(|e| e.file_name().to_string_lossy().into_owned())
                .filter(|n| n.starts_with("mediator-") && n.ends_with(".sock") && *n != own).map(|n| format!("{}/{}", runtime_dir(), n)).collect()).unwrap_or_default();
            // a session whose mpv is gone must go too: its connection can outlive the process
            let known: Vec<(String, Arc<Session>)> = self.sessions.lock().unwrap().iter().map(|(k, v)| (k.clone(), v.clone())).collect();
            for (path, s) in known {
                if !found.contains(&path) || (s.pid.map(|p| !alive(p)).unwrap_or(true) && !answers(&path)) {
                    self.stop_session(&path, &s);
                }
            }
            for path in found {
                if pid_of(&path).map(|p| !alive(p)).unwrap_or(true) && !answers(&path) {
                    let _ = std::fs::remove_file(&path); // a socket left behind by a process that is gone
                    continue;
                }
                if self.sessions.lock().unwrap().contains_key(&path) {
                    continue;
                }
                let s = Arc::new(Session::new(&path));
                self.sessions.lock().unwrap().insert(path.clone(), s.clone());
                let d = self.clone();
                std::thread::spawn(move || d.run_session(path, s));
            }
            // the bus name can be taken (an older daemon) or the bus gone when a session starts:
            // retry while something plays so the player still shows up in MPRIS
            if !self.sessions.lock().unwrap().is_empty() {
                let mut m = self.mpris.lock().unwrap();
                if m.is_none() {
                    *m = crate::mpris::make(&self);
                }
            }
            match &watch {
                Some(w) => w.wait(Duration::from_secs(2)),
                None => std::thread::sleep(Duration::from_secs(2)),
            }
        }
    }

    fn stop_session(&self, path: &str, s: &Session) {
        s.close();
        self.sessions.lock().unwrap().remove(path);
        self.push_now();
    }

    fn run_session(self: Arc<Self>, path: String, s: Arc<Session>) {
        {
            let mut m = self.mpris.lock().unwrap();
            if m.is_none() {
                *m = crate::mpris::make(&self); // D-Bus is only worth having while something plays
            }
        }
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| s.run(&self)));
        self.sessions.lock().unwrap().remove(&path);
        self.push_now();
        if self.sessions.lock().unwrap().is_empty() {
            if let Some(m) = self.mpris.lock().unwrap().take() {
                m.retire();
            }
        }
        self.broadcast(&json!({"event": "changed", "why": "playback ended"}));
    }

    pub fn control(&self, msg: &Value) -> Value {
        let mut sessions = self.ordered();
        if let Some(pid) = msg["pid"].as_i64().filter(|p| *p != 0) {
            sessions.retain(|s| s.pid == Some(pid));
        }
        let Some(s) = sessions.first() else { return json!({"ok": false, "error": "nothing is playing"}) };
        let act = msg["action"].as_str().unwrap_or("");
        let val = msg["value"].as_f64();
        match (act, val) {
            ("toggle", _) => s.command(vec![json!("cycle"), json!("pause")]),
            ("pause", _) => s.command(vec![json!("set_property"), json!("pause"), json!(true)]),
            ("play", _) => s.command(vec![json!("set_property"), json!("pause"), json!(false)]),
            ("seek", Some(v)) => s.command(vec![json!("seek"), json!(v), json!("relative")]),
            ("seek_to", Some(v)) => s.command(vec![json!("seek"), json!(v), json!("absolute")]),
            ("next", _) | ("prev", _) => {
                let step: i64 = if act == "next" { 1 } else { -1 };
                let count = s.prop("playlist-count").as_i64().unwrap_or(0);
                let pos = s.prop("playlist-pos");
                match pos.as_i64().filter(|_| pos.is_i64()) {
                    Some(p) if count > 1 && p + step >= 0 && p + step < count => s.command(vec![json!(if step > 0 { "playlist-next" } else { "playlist-prev" })]),
                    // a single-file stream: the shell owns the episode list and its switch logic
                    _ => self.broadcast(&json!({"event": "step", "dir": step})),
                }
            }
            ("play_path", _) => match msg["path"].as_str().filter(|p| !p.is_empty() && self.lookup(p).is_some()) {
                // only a path of an indexed title: the shell cannot make mpv open arbitrary files
                Some(p) => s.command(vec![json!("loadfile"), json!(p), json!("replace")]),
                None => return json!({"ok": false, "error": "unknown episode"}),
            },
            ("stop", _) => s.command(vec![json!("quit")]),
            ("speed", Some(v)) if (0.1..=4.0).contains(&v) => s.command(vec![json!("set_property"), json!("speed"), json!(v)]),
            ("volume", Some(v)) if (0.0..=130.0).contains(&v) => s.command(vec![json!("set_property"), json!("volume"), json!(v)]),
            _ => return json!({"ok": false, "error": format!("unknown action {}", py_repr(&msg["action"]))}),
        }
        json!({"ok": true})
    }

    // ---- settings: a front end saves them with `mediator config set`, which never talks to us
    fn refresh_config(&self) -> bool {
        let stamp = config_stamp();
        {
            let mut cur = self.cfg_stamp.lock().unwrap();
            if *cur == stamp {
                return false;
            }
            *cur = stamp;
        }
        *self.cfg.lock().unwrap() = config::load();
        self.index.lock().unwrap().at = 0.0;
        let fp = self.fingerprint();
        *self.watch.lock().unwrap() = fp;
        self.broadcast(&json!({"event": "changed", "why": "settings"}));
        true
    }

    // ---- change detection
    fn fingerprint(&self) -> Vec<i64> {
        let mut bits = vec![];
        let db = config::state_dir().join("progress.db");
        bits.push(mtime_ns(&db));
        bits.push(mtime_ns(std::path::Path::new(&format!("{}-wal", db.display()))));
        let cfg = self.cfg.lock().unwrap().clone();
        for kind in ["anime", "shows", "movies"] {
            let Some(root) = cfg.libraries.get(kind).filter(|r| !r.is_empty()) else {
                bits.push(0);
                continue;
            };
            let root = config::expand_user(root);
            let Ok(rd) = std::fs::read_dir(&root) else {
                bits.push(0);
                continue;
            };
            // two levels: a new show folder or file, and a new episode inside a season folder
            let mut newest = mtime_ns(&root);
            for e in rd.flatten() {
                newest = newest.max(e.metadata().map(|m| m.mtime() * 1_000_000_000 + m.mtime_nsec()).unwrap_or(0));
                if e.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                    if let Ok(inner) = std::fs::read_dir(e.path()) {
                        for sub in inner.flatten() {
                            if sub.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                                newest = newest.max(sub.metadata().map(|m| m.mtime() * 1_000_000_000 + m.mtime_nsec()).unwrap_or(0));
                            }
                        }
                    }
                }
            }
            bits.push(newest);
        }
        bits
    }

    fn watch_disk(self: &Arc<Self>) {
        loop {
            std::thread::sleep(Duration::from_secs(5));
            self.refresh_config();
            if self.clients.lock().unwrap().is_empty() {
                continue;
            }
            let fp = self.fingerprint();
            let changed = {
                let mut w = self.watch.lock().unwrap();
                let c = *w != fp;
                if c {
                    *w = fp;
                }
                c
            };
            if changed {
                self.index.lock().unwrap().at = 0.0;
                self.broadcast(&json!({"event": "changed", "why": "disk"}));
            }
        }
    }

    // ---- enrich: posters, summaries, banners, episode names, in the background
    pub fn start_enrich(self: &Arc<Self>, scope: &str, refresh: bool, auto: bool) -> Value {
        if self.enrich_running.load(Ordering::SeqCst) {
            return json!({"ok": false, "error": "already running"});
        }
        self.refresh_config();
        if auto && !self.cfg.lock().unwrap().auto_fetch {
            // "Fetch missing posters automatically" is off: requests the app makes on its own do nothing.
            return json!({"ok": true, "skipped": "automatic fetching is off"});
        }
        self.enrich_stop.store(false, Ordering::SeqCst);
        self.enrich_running.store(true, Ordering::SeqCst);
        let d = self.clone();
        let scope = scope.to_string();
        std::thread::spawn(move || {
            let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| d.enrich(&scope, refresh)));
            d.enrich_running.store(false, Ordering::SeqCst);
        });
        json!({"ok": true})
    }

    fn enrich(&self, scope: &str, refresh: bool) {
        *self.enrich_state.lock().unwrap() = EnrichState { running: true, done: 0, total: 0, current: String::new(), errors: 0 };
        self.push_enrich();
        let run = || {
            let cfg = self.cfg.lock().unwrap().clone();
            let mut titles: Vec<Title> = vec![];
            for kind in ["anime", "shows", "movies"] {
                if let Some(root) = cfg.libraries.get(kind).filter(|r| !r.is_empty()) {
                    titles.extend(scan(kind, root).0);
                }
            }
            if scope != "missing" && scope != "all" {
                titles.retain(|t| t.id == scope);
            }
            let todo: Vec<Title> = titles.into_iter().filter(|t| {
                let known = info::find(t);
                let missing = posters::find(t).is_none() || known.is_none()
                    || (t.lib != "movies" && known.as_ref().map(|k| k["episodes"].as_array().map(|a| a.is_empty()).unwrap_or(true)).unwrap_or(false));
                scope != "missing" || missing || refresh
            }).collect();
            self.enrich_state.lock().unwrap().total = todo.len() as i64;
            self.push_enrich();
            let http = posters::RealHttp::new(15.0);
            // Several titles at once: the lookups spend nearly all their time waiting on the
            // network. Jikan's rate limit is shared across the workers (see `jikan_pace`).
            let workers = std::env::var("MEDIATOR_ENRICH_WORKERS").ok().and_then(|v| v.parse::<usize>().ok())
                .unwrap_or(4).clamp(1, 16).min(todo.len().max(1));
            let next = std::sync::atomic::AtomicUsize::new(0);
            std::thread::scope(|scope| {
                for _ in 0..workers {
                    scope.spawn(|| loop {
                        let i = next.fetch_add(1, Ordering::SeqCst);
                        let Some(t) = todo.get(i) else { break };
                        if self.enrich_stop.load(Ordering::SeqCst) {
                            break;
                        }
                        self.enrich_state.lock().unwrap().current = t.display();
                        self.push_enrich();
                        let ok = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                            if posters::find(t).is_none() || refresh {
                                posters::fetch(t, &http, None, &posters::FetchOpts { refresh, ..Default::default() });
                            }
                            meta::fetch(t, &http, None, &meta::Opts { refresh, ..Default::default() });
                            info::fetch(t, &http, &info::Opts { refresh, ..Default::default() }).0 != "error"
                        })).unwrap_or(false); // one bad title must not stop the rest
                        {
                            let mut st = self.enrich_state.lock().unwrap();
                            if !ok {
                                st.errors += 1;
                            }
                            st.done += 1;
                        }
                        self.broadcast(&json!({"event": "info", "id": t.id}));
                        self.push_enrich();
                    });
                }
            });
        };
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(run));
        {
            let mut st = self.enrich_state.lock().unwrap();
            st.running = false;
            st.current = String::new();
        }
        self.push_enrich();
        self.broadcast(&json!({"event": "changed", "why": "enriched"}));
    }

    // ---- clients
    fn client(self: &Arc<Self>, stream: UnixStream) {
        let Ok(writer) = stream.try_clone() else { return };
        let _ = writer.set_write_timeout(Some(Duration::from_secs(2)));
        let me = Arc::new(Client { writer: Mutex::new(writer) });
        for line in BufReader::new(stream).lines() {
            let Ok(line) = line else { break };
            let Ok(req) = serde_json::from_str::<Value>(&line) else { continue };
            let reply = |mut msg: Value| {
                if let (Some(id), Some(o)) = (req.get("id"), msg.as_object_mut()) {
                    o.insert("id".into(), id.clone());
                }
                me.send(format!("{msg}\n").as_bytes());
            };
            match req["cmd"].as_str().unwrap_or("") {
                "subscribe" => {
                    {
                        let mut cl = self.clients.lock().unwrap();
                        if !cl.iter().any(|c| Arc::ptr_eq(c, &me)) {
                            cl.push(me.clone());
                        }
                    }
                    me.send(format!("{}\n", self.snapshot()).as_bytes());
                    me.send(format!("{}\n", self.enrich_state.lock().unwrap().json()).as_bytes());
                }
                "control" => reply(self.control(&req)),
                "enrich" => {
                    let scope = req["scope"].as_str().filter(|s| !s.is_empty()).unwrap_or("missing").to_string();
                    reply(self.start_enrich(&scope, truthy(&req["refresh"]), truthy(&req["auto"])));
                }
                "enrich_stop" => {
                    self.enrich_stop.store(true, Ordering::SeqCst);
                    reply(json!({"ok": true}));
                }
                "status" => reply(json!({"ok": true, "sessions": self.sessions.lock().unwrap().len(), "clients": self.clients.lock().unwrap().len(),
                    "enrich": {"running": self.enrich_state.lock().unwrap().running, "done": self.enrich_state.lock().unwrap().done,
                               "total": self.enrich_state.lock().unwrap().total, "current": self.enrich_state.lock().unwrap().current.clone(),
                               "errors": self.enrich_state.lock().unwrap().errors}})),
                _ => reply(json!({"ok": false, "error": format!("unknown cmd {}", py_repr(&req["cmd"]))})),
            }
        }
        self.clients.lock().unwrap().retain(|c| !Arc::ptr_eq(c, &me));
    }

    /// True when the installed code changed under a daemon that is not playing anything.
    pub fn stale_code(&self) -> bool {
        self.sessions.lock().unwrap().is_empty() && code_stamp() != self.code
    }

    fn idle_watch(self: &Arc<Self>) {
        loop {
            std::thread::sleep(Duration::from_secs(20));
            if self.stale_code() {
                // the shell reconnects within 2 s and starts a fresh daemon on the new code
                println!("mediator daemon: code changed on disk; restarting");
                let _ = std::fs::remove_file(sock_path());
                std::process::exit(0);
            }
            let busy = !self.clients.lock().unwrap().is_empty() || !self.sessions.lock().unwrap().is_empty() || self.enrich_state.lock().unwrap().running;
            if busy {
                *self.idle_since.lock().unwrap() = Instant::now();
            } else if self.idle_since.lock().unwrap().elapsed().as_secs_f64() > IDLE_EXIT {
                let _ = std::fs::remove_file(sock_path());
                std::process::exit(0);
            }
        }
    }

    pub fn serve(self: &Arc<Self>) -> std::io::Result<()> {
        let sock = sock_path();
        let _ = std::fs::remove_file(&sock);
        let listener = UnixListener::bind(&sock)?;
        let _ = std::fs::set_permissions(&sock, std::fs::Permissions::from_mode(0o600));
        self.reindex();
        std::thread::spawn(|| { let _ = std::panic::catch_unwind(crate::housekeeping::run); }); // trim caches once per start
        for f in [Self::scan_sessions as fn(&Arc<Self>), Self::watch_disk, Self::idle_watch] {
            let d = self.clone();
            std::thread::spawn(move || f(&d));
        }
        for conn in listener.incoming().flatten() {
            let d = self.clone();
            std::thread::spawn(move || d.client(conn));
        }
        Ok(())
    }
}

/// Python's repr() of a JSON value, for error text that quotes a command.
fn py_repr(v: &Value) -> String {
    match v {
        Value::String(s) => format!("'{}'", s.replace('\'', "\\'")),
        Value::Null => "None".into(),
        Value::Bool(b) => if *b { "True".into() } else { "False".into() },
        o => o.to_string(),
    }
}

// ---- entry points ----

pub fn running() -> bool {
    UnixStream::connect(sock_path()).is_ok()
}

pub fn run() -> i32 {
    unsafe { libc::nice(5) }; // background fetching and watching should never compete with the player or the shell
    let d = Daemon::new();
    let rc = match d.serve() {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("mediator daemon: {e}");
            1
        }
    };
    let _ = std::fs::remove_file(sock_path());
    rc
}

/// Start the daemon in the background unless it is already up. Returns when it answers.
pub fn start() -> i32 {
    if running() {
        return 0;
    }
    let dir = config::state_dir();
    let log: std::process::Stdio = if dir.is_dir() {
        let log_path = dir.join("daemon.log");
        if std::fs::metadata(&log_path).map(|m| m.len() > 512 * 1024).unwrap_or(false) {
            let _ = std::fs::rename(&log_path, dir.join("daemon.log.1")); // one old generation is enough
        }
        match std::fs::OpenOptions::new().create(true).append(true).open(&log_path) {
            Ok(f) => f.into(),
            Err(_) => std::process::Stdio::null(),
        }
    } else {
        std::process::Stdio::null()
    };
    let Ok(exe) = std::env::current_exe() else { return 1 };
    use std::os::unix::process::CommandExt;
    let mut c = std::process::Command::new(exe);
    c.args(["daemon", "run"]).stdin(std::process::Stdio::null()).stdout(log);
    c.stderr(match std::fs::OpenOptions::new().append(true).open(dir.join("daemon.log")) { Ok(f) => f.into(), Err(_) => std::process::Stdio::null() });
    unsafe {
        c.pre_exec(|| {
            libc::setsid();
            Ok(())
        });
    }
    if c.spawn().is_err() {
        return 1;
    }
    for _ in 0..50 {
        if running() {
            return 0;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    1
}
