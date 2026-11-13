//! Play a queue in mpv and record progress through mpv's JSON IPC (port of `mediator/player.py`).
//! mpv owns playback; we only listen. We observe `path`, `time-pos` and `duration` and flush a
//! result whenever a file ends, whenever mpv moves on, and every few seconds as a checkpoint.
use crate::catalog::Entry;
use serde_json::{json, Value};
use std::collections::HashSet;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, PartialEq)]
pub struct FileResult {
    pub path: String,
    pub position: f64,
    pub duration: f64,
    pub eof: bool, // mpv reported end-file with reason "eof"
}

/// Turns mpv IPC messages into per-file results. No I/O, easy to test.
pub struct Tracker<'a> {
    sink: Box<dyn FnMut(FileResult) + 'a>,
    on_path: Option<Box<dyn FnMut(&str) + 'a>>,
    pub path: Option<String>,
    pos: Option<f64>,
    dur: Option<f64>,
    dirty: bool,
}

impl<'a> Tracker<'a> {
    pub fn new(sink: impl FnMut(FileResult) + 'a, on_path: Option<Box<dyn FnMut(&str) + 'a>>) -> Self {
        Tracker { sink: Box::new(sink), on_path, path: None, pos: None, dur: None, dirty: false }
    }

    fn reset(&mut self, path: Option<String>) {
        self.path = path;
        self.pos = None;
        self.dur = None;
        self.dirty = false;
    }

    pub fn feed(&mut self, msg: &Value) {
        match msg["event"].as_str() {
            Some("property-change") => {
                let data = &msg["data"];
                match msg["name"].as_str() {
                    Some("path") => {
                        let new = data.as_str().map(String::from);
                        if new != self.path {
                            self.emit(false); // moved on without an end-file (shouldn't happen)
                            self.reset(new.clone());
                            if let (Some(cb), Some(p)) = (self.on_path.as_mut(), new.as_deref()) {
                                if !p.is_empty() {
                                    cb(p);
                                }
                            }
                        }
                    }
                    Some("time-pos") if data.is_number() => {
                        self.pos = data.as_f64();
                        self.dirty = true;
                    }
                    Some("duration") if data.is_number() => {
                        self.dur = data.as_f64();
                        self.dirty = true;
                    }
                    _ => {}
                }
            }
            Some("end-file") => {
                let reason = msg["reason"].as_str();
                if reason == Some("error") {
                    self.reset(None);
                    return;
                }
                self.emit(reason == Some("eof"));
                self.reset(None);
            }
            _ => {}
        }
    }

    pub fn checkpoint(&mut self) {
        if self.dirty {
            self.emit(false);
            self.dirty = false;
        }
    }

    pub fn close(&mut self) {
        self.emit(false);
        self.path = None;
        self.pos = None;
        self.dur = None;
    }

    fn emit(&mut self, eof: bool) {
        let Some(path) = self.path.clone() else { return };
        if self.pos.is_none() && !eof {
            return;
        }
        (self.sink)(FileResult { path, position: self.pos.unwrap_or(0.0), duration: self.dur.unwrap_or(0.0), eof });
    }
}

/// `$MEDIATOR_MPV` (shell-split) overrides the binary and its base args.
pub fn mpv_command() -> Vec<String> {
    match std::env::var("MEDIATOR_MPV") {
        Ok(v) if !v.is_empty() => shlex::split(&v).unwrap_or_default(),
        _ => vec!["mpv".into()],
    }
}

/// `$MEDIATOR_SYNCPLAY` (shell-split) overrides the syncplay binary and its base args.
pub fn syncplay_command() -> Vec<String> {
    match std::env::var("MEDIATOR_SYNCPLAY") {
        Ok(v) if !v.is_empty() => shlex::split(&v).unwrap_or_default(),
        _ => vec!["syncplay".into()],
    }
}

/// Only these scripts load in Mediator's mpv (autoloading would also bring in the system mpris
/// plugin, which publishes a second player next to Mediator's own).
pub const SCRIPTS: [&str; 3] = ["uosc", "thumbfast.lua", "autosub.lua"];
pub const SCRIPT_DIRS: [&str; 3] = ["/etc/mpv/scripts", "~/.config/mpv/scripts", "/usr/share/mpv/scripts"];

/// A stream needs a real read-ahead; a user's `cache=no` would leave about a second of buffer.
pub const NETWORK_CACHE: [&str; 4] = ["--cache=yes", "--demuxer-max-bytes=400MiB", "--demuxer-max-back-bytes=100MiB", "--demuxer-readahead-secs=120"];

pub fn is_remote(path: &str) -> bool {
    let p = path.to_lowercase();
    p.starts_with("http://") || p.starts_with("https://")
}

static MISSING_WARNED: Mutex<Option<HashSet<String>>> = Mutex::new(None);

/// `--load-scripts=no` plus an explicit `--script=` for each wanted script that exists.
/// A missing script is reported once on stderr (its keys would otherwise silently do nothing).
pub fn script_flags() -> Vec<String> {
    let mut flags = vec!["--load-scripts=no".to_string()];
    for name in SCRIPTS {
        let found = SCRIPT_DIRS.iter().map(|d| crate::config::expand_user(d).join(name)).find(|p| p.exists());
        match found {
            Some(p) => flags.push(format!("--script={}", p.display())),
            None => {
                let mut g = MISSING_WARNED.lock().unwrap();
                if g.get_or_insert_with(HashSet::new).insert(name.to_string()) {
                    eprintln!("mediator: mpv script '{name}' not found in {}; it will not be loaded", SCRIPT_DIRS.join(", "));
                }
            }
        }
    }
    flags
}

pub fn socket_path() -> String {
    let base = std::env::var("XDG_RUNTIME_DIR").ok().filter(|v| !v.is_empty()).map(std::path::PathBuf::from).unwrap_or_else(std::env::temp_dir);
    base.join(format!("mediator-{}.sock", std::process::id())).to_string_lossy().into_owned()
}

#[derive(Default)]
pub struct BuildOptions<'a> {
    pub start: f64,
    pub speed: f64,
    pub extra: Vec<String>,
    pub titles: std::collections::HashMap<String, String>,
    pub terminal: Option<bool>,
    pub sock: &'a str,
}

fn is_tty() -> bool {
    use std::io::IsTerminal;
    std::io::stdout().is_terminal()
}

fn g(x: f64) -> String {
    // Python's `{:g}` for the speeds we use
    if x == x.trunc() && x.abs() < 1e15 { format!("{}", x as i64) } else { let s = format!("{x}"); s }
}

pub fn build_command(queue: &[Entry], o: &BuildOptions) -> Vec<String> {
    let mut cmd = mpv_command();
    cmd.extend([
        format!("--input-ipc-server={}", o.sock),
        "--resume-playback=no".into(),
        "--save-position-on-quit=no".into(),
        format!("--speed={}", g(if o.speed == 0.0 { 1.0 } else { o.speed })),
    ]);
    cmd.extend(script_flags());
    if !o.terminal.unwrap_or_else(is_tty) {
        cmd.push("--no-terminal".into());
    }
    if queue.iter().any(|e| is_remote(&e.path)) {
        cmd.extend(NETWORK_CACHE.iter().map(|s| s.to_string()));
    }
    cmd.extend(o.extra.clone());
    for (i, e) in queue.iter().enumerate() {
        cmd.push("--{".into());
        if i == 0 && o.start > 0.0 {
            cmd.push(format!("--start={:.2}", o.start));
        }
        if let Some(t) = o.titles.get(&e.path) {
            cmd.push(format!("--force-media-title={t}"));
        }
        cmd.push(e.path.clone());
        cmd.push("--}".into());
    }
    cmd
}

/// How a queue entry is named in the room's shared playlist: a local file as its bare file name
/// (everyone finds files by name in their own media directories), a URL whole.
pub fn syncplay_playlist_entry(path: &str) -> String {
    if is_remote(path) {
        return path.to_string();
    }
    std::path::Path::new(path).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| path.to_string())
}

/// Quoted strings in a Python list literal such as `['/a', "/b"]`.
fn py_string_list(raw: &str) -> Option<Vec<String>> {
    let raw = raw.trim();
    if raw.is_empty() {
        return Some(Vec::new());
    }
    let inner = raw.strip_prefix('[')?.strip_suffix(']')?;
    let mut out = Vec::new();
    let mut chars = inner.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\'' || c == '"' {
            let mut item = String::new();
            loop {
                match chars.next()? {
                    '\\' => item.push(chars.next()?),
                    ch if ch == c => break,
                    ch => item.push(ch),
                }
            }
            out.push(item);
        } else if !(c == ',' || c.is_whitespace()) {
            return None;
        }
    }
    Some(out)
}

/// syncplay's configured media search directories, or None when its config cannot be read.
pub fn syncplay_media_dirs() -> Option<Vec<String>> {
    let home = std::env::var("HOME").unwrap_or_default();
    let base = std::env::var("XDG_CONFIG_HOME").ok().filter(|v| !v.is_empty()).unwrap_or_else(|| format!("{home}/.config"));
    let text = [format!("{base}/syncplay.ini"), format!("{home}/.syncplay")].iter().find_map(|p| std::fs::read_to_string(p).ok())?;
    let mut in_section = false;
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') && line.ends_with(']') {
            in_section = line[1..line.len() - 1].eq_ignore_ascii_case("client_settings");
        } else if in_section {
            if let Some((key, value)) = line.split_once('=') {
                if key.trim().eq_ignore_ascii_case("mediasearchdirectories") {
                    return py_string_list(value);
                }
            }
        }
    }
    Some(Vec::new())
}

/// Why the room's shared playlist might not advance past the first file on this machine.
pub fn syncplay_queue_warnings(queue: &[Entry]) -> Vec<String> {
    let local: Vec<&str> = queue.iter().map(|e| e.path.as_str()).filter(|p| !is_remote(p)).collect();
    let mut out = Vec::new();
    if local.len() < 2 {
        return out;
    }
    let names: HashSet<String> = local.iter().map(|p| syncplay_playlist_entry(p)).collect();
    if names.len() != local.len() {
        out.push("two queued files share a file name; syncplay's shared playlist identifies files by name, so it cannot tell them apart".to_string());
    }
    let Some(dirs) = syncplay_media_dirs() else {
        out.push("could not read syncplay's media directories; if it cannot find the next file it will not switch to it".to_string());
        return out;
    };
    let real = |p: &str| std::fs::canonicalize(p).map(|r| r.to_string_lossy().into_owned()).unwrap_or_else(|_| p.to_string());
    let roots: Vec<String> = dirs.iter().map(|d| format!("{}/", real(d).trim_end_matches('/'))).collect();
    if let Some(outside) = local[1..].iter().find(|p| !roots.iter().any(|r| real(p).starts_with(r.as_str()))) {
        let dir = std::path::Path::new(outside).parent().map(|d| d.to_string_lossy().into_owned()).unwrap_or_default();
        out.push(format!("{dir} is not in syncplay's media directories (Syncplay > File > Set media directories); it cannot switch to the next episode there"));
    }
    out
}

/// syncplay owns mpv, so everything for mpv goes after `--` as plain `--key=value`.
pub fn build_syncplay_command(queue: &[Entry], sock: &str, playlist: &str, speed: f64, extra: &[String], syncplay_args: &[String]) -> Vec<String> {
    let mpv = mpv_command();
    let mpv_path = crate::notify::which(&mpv[0]).map(|p| p.to_string_lossy().into_owned()).unwrap_or_else(|| mpv[0].clone());
    let mut cmd = syncplay_command();
    cmd.extend(syncplay_args.iter().cloned());
    cmd.extend(["--player-path".into(), mpv_path, "--load-playlist-from-file".into(), playlist.into(), queue[0].path.clone(), "--".into()]);
    cmd.extend(mpv[1..].iter().cloned());
    cmd.extend([format!("--input-ipc-server={sock}"), "--resume-playback=no".into(), "--save-position-on-quit=no".into(), format!("--speed={}", g(speed))]);
    cmd.extend(extra.iter().cloned());
    cmd
}

fn connect(path: &str, child: &mut Child, timeout: f64) -> Option<UnixStream> {
    let deadline = Instant::now() + Duration::from_secs_f64(timeout);
    while Instant::now() < deadline {
        match UnixStream::connect(path) {
            Ok(s) => return Some(s),
            Err(e) if matches!(e.kind(), std::io::ErrorKind::NotFound | std::io::ErrorKind::ConnectionRefused) => {
                if child.try_wait().ok().flatten().is_some() {
                    return None;
                }
                std::thread::sleep(Duration::from_millis(50));
            }
            Err(_) => return None,
        }
    }
    None
}

/// Send one command to mpv's IPC socket on its own short connection and return the reply.
/// mpv accepts several clients, so this never disturbs the connection that tracks progress.
pub fn ipc_command(sock_path: &str, command: &[Value], timeout: f64) -> Option<Value> {
    let mut s = UnixStream::connect(sock_path).ok()?;
    let t = Some(Duration::from_secs_f64(timeout));
    s.set_read_timeout(t).ok()?;
    s.set_write_timeout(t).ok()?;
    let mut line = serde_json::to_vec(&json!({"command": command, "request_id": 7})).unwrap();
    line.push(b'\n');
    s.write_all(&line).ok()?;
    let mut buf: Vec<u8> = vec![];
    let mut chunk = [0u8; 65536];
    loop {
        let n = s.read(&mut chunk).ok()?;
        if n == 0 {
            return None;
        }
        buf.extend_from_slice(&chunk[..n]);
        while let Some(i) = buf.iter().position(|&b| b == b'\n') {
            let l: Vec<u8> = buf.drain(..=i).collect();
            if let Ok(m) = serde_json::from_slice::<Value>(&l) {
                if m["request_id"] == 7 {
                    return Some(m);
                }
            }
        }
    }
}

/// mpv key=value lists need `%len%value` for values that may contain commas or `=`.
pub fn kv_value(value: &str) -> String {
    format!("%{}%{value}", value.len()) // mpv counts bytes (the Python version counted characters)
}

static INTERRUPTED: AtomicBool = AtomicBool::new(false);
extern "C" fn on_sigint(_: libc::c_int) {
    INTERRUPTED.store(true, Ordering::SeqCst);
}
fn install_sigint() {
    unsafe {
        let mut sa: libc::sigaction = std::mem::zeroed();
        sa.sa_sigaction = on_sigint as *const () as usize;
        libc::sigemptyset(&mut sa.sa_mask);
        sa.sa_flags = 0; // no SA_RESTART: a blocked read returns so the flag is seen
        libc::sigaction(libc::SIGINT, &sa, std::ptr::null_mut());
    }
    INTERRUPTED.store(false, Ordering::SeqCst);
}

pub struct RunOptions<'a> {
    pub sock_path: Option<String>,
    pub env: Vec<(String, String)>,
    pub terminal: Option<bool>,
    pub checkpoint_every: f64,
    pub connect_timeout: f64,
    pub on_ready: Option<Box<dyn FnMut() + 'a>>,
    pub on_ready_pid: Option<Box<dyn FnMut(u32) + 'a>>,
    pub on_path: Option<Box<dyn FnMut(&str) + 'a>>,
}

impl Default for RunOptions<'_> {
    fn default() -> Self {
        RunOptions { sock_path: None, env: vec![], terminal: None, checkpoint_every: 5.0, connect_timeout: 600.0, on_ready: None, on_ready_pid: None, on_path: None }
    }
}

fn spawn(cmd: &[String], env: &[(String, String)], terminal: bool) -> std::io::Result<Child> {
    let mut c = Command::new(&cmd[0]);
    c.args(&cmd[1..]);
    for (k, v) in env {
        c.env(k, v);
    }
    if !terminal {
        c.stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
    }
    c.spawn()
}

fn finish(child: &mut Child, sock: Option<UnixStream>, leftovers: &[&str]) -> i32 {
    drop(sock);
    if child.try_wait().ok().flatten().is_none() {
        unsafe { libc::kill(child.id() as i32, libc::SIGTERM) };
        let end = Instant::now() + Duration::from_secs(3);
        while Instant::now() < end && child.try_wait().ok().flatten().is_none() {
            std::thread::sleep(Duration::from_millis(50));
        }
        if child.try_wait().ok().flatten().is_none() {
            let _ = child.kill();
        }
    }
    let code = child.wait().ok().and_then(|s| s.code()).unwrap_or(-1);
    for l in leftovers {
        let _ = std::fs::remove_file(l);
    }
    code
}

/// The shared read loop. `per_msg` sees every parsed message after the tracker.
fn track(sock: &mut UnixStream, tracker: &mut Tracker, checkpoint_every: f64, mut per_msg: impl FnMut(&Value, &Tracker, &mut UnixStream)) -> bool {
    let log = std::env::var("MEDIATOR_IPC_LOG").ok().and_then(|p| std::fs::OpenOptions::new().append(true).create(true).open(p).ok());
    let mut log = log;
    for (i, prop) in ["path", "time-pos", "duration"].iter().enumerate() {
        let mut l = serde_json::to_vec(&json!({"command": ["observe_property", i + 1, prop]})).unwrap();
        l.push(b'\n');
        if sock.write_all(&l).is_err() {
            return false;
        }
    }
    let _ = sock.set_read_timeout(Some(Duration::from_secs(1)));
    let mut buf: Vec<u8> = vec![];
    let mut last = Instant::now();
    let mut chunk = [0u8; 65536];
    loop {
        if INTERRUPTED.load(Ordering::SeqCst) {
            return true;
        }
        match sock.read(&mut chunk) {
            Ok(0) => return false,
            Ok(n) => {
                buf.extend_from_slice(&chunk[..n]);
                while let Some(i) = buf.iter().position(|&b| b == b'\n') {
                    let line: Vec<u8> = buf.drain(..=i).collect();
                    if let Some(f) = log.as_mut() {
                        let _ = writeln!(f, "{}", String::from_utf8_lossy(&line[..line.len() - 1]));
                    }
                    if let Ok(msg) = serde_json::from_slice::<Value>(&line) {
                        tracker.feed(&msg);
                        per_msg(&msg, tracker, sock);
                    }
                }
            }
            Err(e) if matches!(e.kind(), std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut | std::io::ErrorKind::Interrupted) => {}
            Err(_) => return false,
        }
        if last.elapsed().as_secs_f64() >= checkpoint_every {
            tracker.checkpoint();
            last = Instant::now();
        }
    }
}

/// Run a command that starts mpv with our IPC socket, and track that mpv. Returns its exit code
/// (130 when interrupted).
pub fn run_external(cmd: &[String], sink: impl FnMut(FileResult), mut o: RunOptions) -> std::io::Result<i32> {
    let sock_path = o.sock_path.clone().unwrap_or_else(socket_path);
    let _ = std::fs::remove_file(&sock_path);
    install_sigint();
    let mut tracker = Tracker::new(sink, o.on_path.take());
    let mut child = spawn(cmd, &o.env, o.terminal.unwrap_or_else(is_tty))?;
    let mut sock = connect(&sock_path, &mut child, o.connect_timeout);
    let mut ready = false;
    let mut interrupted = false;
    if let Some(s) = sock.as_mut() {
        interrupted = track(s, &mut tracker, o.checkpoint_every, |msg, _t, _s| {
            if (o.on_ready.is_some() || o.on_ready_pid.is_some()) && !ready && msg["event"] == "property-change" && msg["name"] == "time-pos" && msg["data"].as_f64().map(|d| d >= 0.0).unwrap_or(false) {
                if let Some(cb) = o.on_ready_pid.as_mut() {
                    cb(std::process::id());
                }
                if let Some(cb) = o.on_ready.as_mut() {
                    cb();
                }
                ready = true;
            }
        });
    }
    let code = if interrupted { None } else { child.wait().ok().and_then(|s| s.code()) };
    tracker.close();
    let rc = finish(&mut child, sock, &[&sock_path]);
    Ok(if interrupted { 130 } else { code.unwrap_or(rc) })
}

/// Block until the player exits and return its exit code. `syncplay` (extra syncplay args,
/// possibly empty) plays through syncplay instead of straight in mpv.
pub fn run(queue: &[Entry], sink: impl FnMut(FileResult), start: f64, speed: f64, extra: Vec<String>, titles: std::collections::HashMap<String, String>,
           checkpoint_every: f64, sock_path: Option<String>, terminal: Option<bool>, syncplay: Option<Vec<String>>) -> std::io::Result<i32> {
    let sock_path = sock_path.unwrap_or_else(socket_path);
    let _ = std::fs::remove_file(&sock_path);
    install_sigint();
    let mut playlist_file: Option<String> = None;
    let mut pending_seek = 0.0;
    let cmd = match &syncplay {
        None => build_command(queue, &BuildOptions { start, speed, extra, titles, terminal, sock: &sock_path }),
        Some(args) => {
            let p = std::env::temp_dir().join(format!("mediator-playlist-{}.txt", std::process::id()));
            std::fs::write(&p, queue.iter().map(|e| syncplay_playlist_entry(&e.path)).collect::<Vec<_>>().join("\n") + "\n")?;
            for warning in syncplay_queue_warnings(queue) {
                eprintln!("mediator: {warning}");
            }
            playlist_file = Some(p.to_string_lossy().into_owned());
            pending_seek = start;
            build_syncplay_command(queue, &sock_path, playlist_file.as_deref().unwrap(), speed, &extra, args)
        }
    };
    let mut tracker = Tracker::new(sink, None);
    let mut child = spawn(&cmd, &[], terminal.unwrap_or_else(is_tty))?;
    let mut sock = connect(&sock_path, &mut child, 15.0);
    let mut interrupted = false;
    let first = queue.first().map(|e| e.path.clone()).unwrap_or_default();
    if let Some(s) = sock.as_mut() {
        interrupted = track(s, &mut tracker, checkpoint_every, |msg, t, s| {
            if pending_seek > 0.0 && msg["name"] == "duration" && t.path.as_deref() == Some(first.as_str()) {
                let mut l = serde_json::to_vec(&json!({"command": ["seek", pending_seek, "absolute"]})).unwrap();
                l.push(b'\n');
                let _ = s.write_all(&l);
                pending_seek = 0.0;
            }
        });
    }
    let code = if interrupted { None } else { child.wait().ok().and_then(|s| s.code()) };
    tracker.close();
    let mut left: Vec<&str> = vec![&sock_path];
    if let Some(p) = &playlist_file {
        left.push(p);
    }
    let rc = finish(&mut child, sock, &left);
    Ok(if interrupted { 130 } else { code.unwrap_or(rc) })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::os::unix::net::UnixListener;

    fn pc(name: &str, data: Value) -> Value {
        json!({"event": "property-change", "name": name, "data": data})
    }

    #[test]
    fn syncplay_playlist_names_and_config_list() {
        assert_eq!(syncplay_playlist_entry("/a/b/Show S01E01.mkv"), "Show S01E01.mkv");
        assert_eq!(syncplay_playlist_entry("https://x/y.m3u8"), "https://x/y.m3u8");
        assert_eq!(py_string_list("['/a', \"/b c\"]"), Some(vec!["/a".to_string(), "/b c".to_string()]));
        assert_eq!(py_string_list("[]"), Some(vec![]));
        assert_eq!(py_string_list("nope"), None);
    }

    #[test]
    fn tracker_records_each_file_as_it_ends() {
        let seen = RefCell::new(vec![]);
        let paths = RefCell::new(vec![]);
        {
            let mut t = Tracker::new(|r| seen.borrow_mut().push(r), Some(Box::new(|p: &str| paths.borrow_mut().push(p.to_string()))));
            t.feed(&pc("path", json!("/a.mkv")));
            t.feed(&pc("duration", json!(100.0)));
            t.feed(&pc("time-pos", json!(40.0)));
            t.checkpoint();
            t.feed(&json!({"event": "end-file", "reason": "eof"}));
            t.feed(&pc("path", json!("/b.mkv")));
            t.feed(&pc("time-pos", json!(5.0)));
            t.close();
        }
        let s = seen.borrow();
        assert_eq!(s.len(), 3);
        assert_eq!((s[0].position, s[0].eof), (40.0, false));
        assert_eq!((s[1].path.as_str(), s[1].eof, s[1].duration), ("/a.mkv", true, 100.0));
        assert_eq!((s[2].path.as_str(), s[2].position), ("/b.mkv", 5.0));
        assert_eq!(*paths.borrow(), ["/a.mkv", "/b.mkv"]);
    }

    #[test]
    fn error_end_file_drops_the_file() {
        let seen = RefCell::new(vec![]);
        {
            let mut t = Tracker::new(|r| seen.borrow_mut().push(r), None);
            t.feed(&pc("path", json!("/a")));
            t.feed(&pc("time-pos", json!(3.0)));
            t.feed(&json!({"event": "end-file", "reason": "error"}));
            t.close();
        }
        assert!(seen.borrow().is_empty());
    }

    #[test]
    fn kv_value_counts_bytes_like_mpv_wants() {
        assert_eq!(kv_value("a,b=c"), "%5%a,b=c");
    }

    #[test]
    fn command_has_per_file_groups() {
        let e = |p: &str| crate::catalog::Entry { path: p.into(), rel: p.into(), size: 1, kind: "episode".into(), season: None, episode: None, episode_end: None, version: 1, name: String::new(), rule: String::new(), confidence: String::new(), stem: String::new(), remote_id: String::new() };
        let q = [e("/a.mkv"), e("http://x/b.mkv")];
        let mut titles = std::collections::HashMap::new();
        titles.insert("/a.mkv".to_string(), "Title A".to_string());
        let c = build_command(&q, &BuildOptions { start: 12.5, speed: 1.5, extra: vec!["--fs".into()], titles, terminal: Some(false), sock: "/s" });
        let j = c.join(" ");
        assert!(j.contains("--input-ipc-server=/s") && j.contains("--speed=1.5") && j.contains("--no-terminal") && j.contains("--demuxer-readahead-secs=120"));
        assert!(j.contains("--{ --start=12.50 --force-media-title=Title A /a.mkv --} --{ http://x/b.mkv --}"), "{j}");
    }

    #[test]
    fn ipc_command_and_run_external_against_a_fake_mpv() {
        let d = tempfile::tempdir().unwrap();
        let sock = d.path().join("mpv.sock").to_string_lossy().into_owned();
        let sock2 = sock.clone();
        let server = std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(150));
            let l = UnixListener::bind(&sock2).unwrap();
            // 1st connection: the tracker. 2nd: an ipc_command.
            let (mut a, _) = l.accept().unwrap();
            let mut seen = [0u8; 4096];
            let _ = a.read(&mut seen); // the observe_property lines
            for m in [pc("path", json!("/f.mkv")), pc("duration", json!(90.0)), pc("time-pos", json!(30.0)), json!({"event": "end-file", "reason": "quit"})] {
                a.write_all(format!("{m}\n").as_bytes()).unwrap();
            }
            let (mut b, _) = l.accept().unwrap();
            let n = b.read(&mut seen).unwrap();
            let req: Value = serde_json::from_slice(&seen[..n - 1]).unwrap();
            assert_eq!(req["command"][0], "get_property");
            b.write_all(format!("{}\n", json!({"event": "x"})).as_bytes()).unwrap();
            b.write_all(format!("{}\n", json!({"request_id": 7, "error": "success", "data": 42})).as_bytes()).unwrap();
            std::thread::sleep(Duration::from_millis(300));
        });
        let results = RefCell::new(vec![]);
        let sock3 = sock.clone();
        let asker = std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(700));
            ipc_command(&sock3, &[json!("get_property"), json!("path")], 3.0)
        });
        let code = run_external(&["sh".into(), "-c".into(), "sleep 1.2".into()], |r| results.borrow_mut().push(r),
            RunOptions { sock_path: Some(sock.clone()), terminal: Some(false), connect_timeout: 5.0, ..Default::default() }).unwrap();
        assert_eq!(code, 0);
        let r = results.borrow();
        assert_eq!(r.len(), 1);
        assert_eq!((r[0].path.as_str(), r[0].position, r[0].duration, r[0].eof), ("/f.mkv", 30.0, 90.0, false));
        let reply = asker.join().unwrap().expect("reply");
        assert_eq!(reply["data"], 42);
        server.join().unwrap();
    }
}
