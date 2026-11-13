//! Playing a resolved episode in mpv: the command line, the rolling queue, resume and progress
//! (port of `mediator/native_player.py`). mpv cannot give each queued playlist entry its own start
//! time or referer, so queued entries join through small titled playlist files, the player's origin
//! is the referer for the whole run, and a resumed episode is sought once it opens.
use crate::anime_provider::{Provider, ProviderError, Source};
use crate::{native_progress as np, player};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

static ENTRY_FILES: Mutex<Vec<String>> = Mutex::new(Vec::new());

/// The shell's Syncplay control socket, when the shell exports one next to `MEDIATOR_SYNCPLAY`.
/// With it, later episodes are added to the room's shared playlist (Syncplay owns mpv, so they
/// cannot be appended to mpv's own). Without it, Syncplay plays one episode as before.
pub fn syncplay_control() -> Option<String> {
    std::env::var("MEDIATOR_SYNCPLAY_CONTROL").ok().filter(|p| !p.is_empty())
}

/// What the room's shared playlist holds: its entries and the one being played.
struct RoomList {
    items: Vec<String>,
    index: Option<usize>,
}

/// One JSON-lines request to the control socket; `want` picks the reply line to return.
fn room_call(path: &str, request: &Value, want: &str) -> Option<Value> {
    use std::io::{BufRead, BufReader, Write};
    let stream = std::os::unix::net::UnixStream::connect(path).ok()?;
    stream.set_read_timeout(Some(Duration::from_secs(5))).ok()?;
    stream.set_write_timeout(Some(Duration::from_secs(5))).ok()?;
    let mut writer = stream.try_clone().ok()?;
    writer.write_all(format!("{request}\n").as_bytes()).ok()?;
    let deadline = Instant::now() + Duration::from_secs(6);
    for line in BufReader::new(stream).lines() {
        let line = line.ok()?; // a read timeout ends it
        if let Ok(v) = serde_json::from_str::<Value>(&line) {
            if v["type"] == want {
                return Some(v);
            }
        }
        if Instant::now() > deadline {
            return None;
        }
    }
    None
}

/// Switches the room to its playlist entry `index`.
fn room_play(path: &str, index: usize) -> bool {
    room_call(path, &json!({"cmd": "playlist-play", "index": index, "id": 2}), "ack")
        .map(|v| v["ok"] == true)
        .unwrap_or(false)
}

/// mpv's own next/previous keys move inside mpv's playlist, which holds one entry when Syncplay
/// owns the player. Bind them to messages instead and turn those into room moves.
fn room_keys(control: &str, sock: &str, done: &AtomicBool, goto: &Mutex<Option<String>>) {
    use std::io::{BufRead, BufReader, Write};
    while !done.load(Ordering::SeqCst) {
        let Ok(stream) = std::os::unix::net::UnixStream::connect(sock) else {
            std::thread::sleep(Duration::from_millis(500));
            continue;
        };
        let _ = stream.set_read_timeout(Some(Duration::from_secs(1)));
        let Ok(mut writer) = stream.try_clone() else { return };
        for (key, message) in [(">", "mediator-room-next"), ("<", "mediator-room-prev")] {
            let cmd = json!({"command": ["keybind", key, format!("script-message {message}")]});
            if writer.write_all(format!("{cmd}\n").as_bytes()).is_err() {
                break;
            }
        }
        let mut reader = BufReader::new(stream);
        let mut line = String::new();
        loop {
            if done.load(Ordering::SeqCst) {
                return;
            }
            line.clear();
            match reader.read_line(&mut line) {
                Ok(0) => break, // mpv went away; the outer loop reconnects if it comes back
                Ok(_) => {
                    let Ok(msg) = serde_json::from_str::<Value>(&line) else { continue };
                    if msg["event"] != "client-message" {
                        continue;
                    }
                    if msg["args"][0] == "mediator-room-goto" {
                        // an episode the room does not hold yet: the feeder resolves and adds it
                        if let Some(eid) = msg["args"][1].as_str().filter(|e| !e.is_empty()) {
                            *goto.lock().unwrap() = Some(eid.to_string());
                        }
                        continue;
                    }
                    let step: i64 = match msg["args"][0].as_str() {
                        Some("mediator-room-next") => 1,
                        Some("mediator-room-prev") => -1,
                        _ => continue,
                    };
                    if let Some((room, true)) = room_state(control) {
                        let target = room.index.unwrap_or(0) as i64 + step;
                        if target >= 0 && (target as usize) < room.items.len() {
                            room_play(control, target as usize);
                        }
                    }
                }
                Err(e) if matches!(e.kind(), std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut) => continue,
                Err(_) => break,
            }
        }
    }
}

fn room_state(path: &str) -> Option<(RoomList, bool)> {
    let v = room_call(path, &json!({"cmd": "state"}), "state")?;
    let items = v["playlist"]["items"].as_array()?.iter().filter_map(|i| i.as_str().map(String::from)).collect();
    let index = v["playlist"]["index"].as_u64().map(|i| i as usize);
    Some((RoomList { items, index }, v["connected"] == true))
}

/// Adds a link to the room's playlist, vouching for its host (a stream host changes from one
/// episode to the next, and Syncplay will not switch to an untrusted one).
fn room_add(path: &str, url: &str) -> bool {
    room_call(path, &json!({"cmd": "playlist-add", "item": url, "trust": true, "id": 1}), "ack")
        .map(|v| v["ok"] == true)
        .unwrap_or(false)
}

/// Where a partly watched episode picks up; 0 for a new or finished one.
pub fn resume_point(saved: &Value, title_id: &str, episode_id: &str) -> f64 {
    if saved["show_id"] == title_id && saved["episode_id"] == episode_id && !np::truthy_pub(saved.get("watched")) {
        let v = np::finite(saved.get("position"), 0.0);
        return if v >= 5.0 { v } else { 0.0 };
    }
    0.0
}

/// A queued entry cannot carry `start=` (it comes through a playlist file), so seek once it is
/// open. Ready means mpv reports this entry's own path, a duration past the resume point and a
/// playing position.
pub fn seek_when_ready(sock: &str, position: f64, path: &str, timeout: f64) {
    let deadline = Instant::now() + Duration::from_secs_f64(timeout);
    while Instant::now() < deadline {
        let Some(now) = player::ipc_command(sock, &[json!("get_property"), json!("path")], 5.0) else { return };
        if now["error"] == "success" && (path.is_empty() || now["data"] == path) {
            let dur = player::ipc_command(sock, &[json!("get_property"), json!("duration")], 5.0).unwrap_or(Value::Null);
            let pos = player::ipc_command(sock, &[json!("get_property"), json!("time-pos")], 5.0).unwrap_or(Value::Null);
            if dur["error"] == "success" && pos["error"] == "success" && dur["data"].as_f64().unwrap_or(0.0) > position {
                player::ipc_command(sock, &[json!("seek"), json!(position), json!("absolute")], 5.0);
                return;
            }
        }
        std::thread::sleep(Duration::from_millis(300));
    }
}

pub fn label(name: &str, episode: &Value) -> String {
    let number = episode["number"].as_str().unwrap_or("");
    let base = if number.is_empty() {
        name.to_string()
    } else if crate::parse::rx(r"\AS\d+E\d+\z").is_match(number).unwrap_or(false) {
        format!("{name} {number}")
    } else {
        format!("{name} Episode {number}")
    };
    // The episode's own name too, when it has one that the number does not already say
    let title = episode["title"].as_str().unwrap_or("").trim();
    if title.is_empty() || number.is_empty() || base.contains(title) {
        base
    } else {
        format!("{base} \u{b7} {title}")
    }
}

/// A one-entry m3u8 (kept for the length of the player) so mpv has a title for the entry.
fn titled_entry(label: &str, url: &str) -> std::io::Result<String> {
    static N: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
    let path = std::env::temp_dir().join(format!("mediator-entry-{}-{}.m3u8", std::process::id(), N.fetch_add(1, Ordering::SeqCst))).to_string_lossy().into_owned();
    std::fs::write(&path, format!("#EXTM3U\n#EXTINF:-1,{}\n{url}\n", label.replace('\n', " ")))?;
    ENTRY_FILES.lock().unwrap().push(path.clone());
    Ok(path)
}

pub type ResolveNext<'a> = &'a (dyn Fn(&str) -> Result<(Value, Source), ProviderError> + Sync);

pub struct Play<'a> {
    pub title: String,
    pub poster: String,
    pub dub: bool,
    pub quality: String,
    pub start: Option<f64>,
    pub dry_run: bool,
    pub terminal: Option<bool>,
    pub on_resolved: Option<Box<dyn FnMut() + 'a>>,
    pub on_ready_pid: Option<Box<dyn FnMut(u32) + 'a>>,
    pub finish_ratio: f64,
    pub finish_tail: f64,
    pub anilist_id: i64,
    pub season: i64,
    pub total: i64,
    pub on_watched: Option<Box<dyn FnMut(&Value) + 'a>>,
    /// (episode list, episode, source) already resolved by another backend (Stremio)
    pub direct: Option<(Vec<Value>, Value, Source)>,
    pub speed: f64,
    pub syncplay: Option<Vec<String>>,
    pub queue: Vec<String>,
    /// Every episode id of the show in order, so a jump inside a room knows what follows it
    pub order: Vec<String>,
    pub queue_window: i64,
    pub resolve_next: Option<ResolveNext<'a>>,
}

impl Default for Play<'_> {
    fn default() -> Self {
        Play { title: String::new(), poster: String::new(), dub: false, quality: "best".into(), start: None, dry_run: false, terminal: None,
            on_resolved: None, on_ready_pid: None, finish_ratio: 0.9, finish_tail: 120.0, anilist_id: 0, season: 0, total: 0, on_watched: None,
            direct: None, speed: 1.0, syncplay: None, queue: vec![], order: vec![], queue_window: 2, resolve_next: None }
    }
}

fn quote_arg(part: &str) -> String {
    part.bytes().map(|b| if b.is_ascii_alphanumeric() || b"/:=-._~".contains(&b) { (b as char).to_string() } else { format!("%{b:02X}") }).collect()
}

fn g(x: f64) -> String {
    if x == x.trunc() { format!("{}", x as i64) } else { format!("{x}") }
}

pub fn play(provider: &Provider, title_id: &str, episode_id: &str, mut o: Play) -> Result<i32, ProviderError> {
    let mpv = player::mpv_command();
    if crate::notify::which(&mpv[0]).is_none() && std::env::var("MEDIATOR_MPV").is_err() {
        return Err(ProviderError("mpv is required for native streaming".into()));
    }
    let (episodes, episode, source) = match o.direct.take() {
        Some(d) => d,
        None => {
            let eps = provider.episodes(title_id)?;
            let (s, e) = provider.resolve(title_id, episode_id, o.dub, &o.quality, Some(&eps))?;
            (eps, e, s)
        }
    };
    let saved = np::load_episode(title_id, episode_id);
    let same = saved["show_id"] == title_id && saved["episode_id"] == episode_id;
    let mut start = match o.start {
        Some(s) => s,
        None if same && !np::truthy_pub(saved.get("watched")) => np::finite(saved.get("position"), 0.0),
        None => 0.0,
    };
    if !start.is_finite() || start < 0.0 {
        start = 0.0;
    }
    let name = if o.title.is_empty() { title_id.to_string() } else { o.title.clone() };
    let lbl = label(&name, &episode);
    let speed = if o.syncplay.is_some() { 1.0 } else { o.speed };
    // Watching together with later episodes to feed into the room's playlist
    let control = if o.syncplay.is_some() && (!o.queue.is_empty() || !o.order.is_empty()) && o.resolve_next.is_some() { syncplay_control() } else { None };
    let feeding = control.is_some();
    // Later episodes cannot carry their own referer: the player's origin stands for the whole run
    let referer_flag = match (&control, url::Url::parse(&source.referer)) {
        (Some(_), Ok(u)) if u.host_str().is_some() => format!(
            "--referrer={}://{}{}/", u.scheme(), u.host_str().unwrap_or_default(),
            u.port().map(|p| format!(":{p}")).unwrap_or_default()),
        _ => format!("--referrer={}", source.referer),
    };
    let mut flags: Vec<String> = vec![
        referer_flag, "--no-terminal".into(), "--resume-playback=no".into(), "--save-position-on-quit=no".into(),
        format!("--force-media-title={lbl}"), format!("--speed={}", g(speed)),
    ];
    flags.extend(player::script_flags());
    flags.extend(player::NETWORK_CACHE.iter().map(|s| s.to_string()));
    if !source.subtitles.is_empty() {
        flags.push(format!("--sub-file={}", source.subtitles));
    }
    if start > 0.0 && o.syncplay.is_some() && !feeding {
        flags.push(format!("--start={start:.2}")); // syncplay hands mpv plain options, no per-file groups
    }
    // (feeding: a global --start would apply to every queued episode, so the first one is sought
    // once it opens instead)
    let mut cmd: Vec<String>;
    if let Some(sp) = &o.syncplay {
        flags.retain(|f| f != "--no-terminal"); // syncplay starts mpv itself, as it does for local files
        // Keep --load-scripts=no and still load uosc/thumbfast. syncplay keeps its mpv options in a
        // dict keyed by option name and always sets "script" to its own syncplayintf.lua, so a
        // `--script=` of ours would replace it; list options also take -append, -add and -pre.
        let wanted: Vec<String> = flags.iter().filter_map(|f| f.strip_prefix("--script=").map(String::from)).collect();
        flags.retain(|f| !f.starts_with("--script="));
        if wanted.len() > 3 {
            eprintln!("mediator: syncplay can load three extra mpv scripts; skipping {}", wanted[3..].iter().map(|w| w.rsplit('/').next().unwrap_or(w)).collect::<Vec<_>>().join(", "));
        }
        for (op, path) in ["append", "add", "pre"].iter().zip(&wanted) {
            flags.push(format!("--scripts-{op}={path}"));
        }
        let mpv_path = crate::notify::which(&mpv[0]).map(|p| p.to_string_lossy().into_owned()).unwrap_or_else(|| mpv[0].clone());
        cmd = player::syncplay_command();
        cmd.extend(sp.iter().cloned());
        cmd.extend(["--player-path".into(), mpv_path, source.url.clone(), "--".into()]);
        cmd.extend(mpv[1..].iter().cloned());
        cmd.extend(flags);
    } else {
        let is_per_file = |f: &String| f.starts_with("--referrer=") || f.starts_with("--force-media-title=") || f.starts_with("--sub-file=");
        let mut per_file: Vec<String> = flags.iter().filter(|f| is_per_file(f)).cloned().collect();
        flags.retain(|f| !is_per_file(f));
        if !source.referer.is_empty() && !o.queue.is_empty() {
            // Queued episodes join through playlist files, which cannot carry their own referer
            if let Ok(u) = url::Url::parse(&source.referer) {
                if let Some(h) = u.host_str() {
                    flags.push(format!("--referrer={}://{}{}/", u.scheme(), h, u.port().map(|p| format!(":{p}")).unwrap_or_default()));
                }
            }
        }
        if start > 0.0 {
            per_file.push(format!("--start={start:.2}"));
        }
        cmd = mpv.clone();
        cmd.extend(flags);
        cmd.push("--{".into());
        cmd.extend(per_file);
        cmd.push(source.url.clone());
        cmd.push("--}".into());
    }
    if o.dry_run {
        println!("{}", cmd.iter().map(|p| quote_arg(p)).collect::<Vec<_>>().join(" "));
        return Ok(0);
    }
    let duration = if same { np::finite(saved.get("duration"), 0.0) } else { 0.0 };
    np::begin(title_id, episode_id, np::Begin {
        title: name.clone(), poster: o.poster.clone(), episodes: Some(episodes.clone()),
        episode_number: episode["number"].as_str().unwrap_or("").into(), episode_title: episode["title"].as_str().unwrap_or("").into(),
        quality: Some(o.quality.clone()), dub: o.dub, position: start, duration, anilist_id: o.anilist_id, season: o.season, total: o.total,
    });
    let sock = player::socket_path();
    if o.syncplay.is_some() {
        cmd.push(format!("--input-ipc-server={sock}")); // still after `--`: syncplay hands it to mpv
    } else {
        cmd.insert(1, format!("--input-ipc-server={sock}"));
    }
    np::attach_session(title_id, episode_id, &sock, np::Attach { worker_pid: std::process::id() as i64, media_title: lbl.clone(), position: Some(start), duration: Some(duration), paused: None });

    let by_url: Mutex<HashMap<String, (String, Value, String)>> = Mutex::new(HashMap::from([(source.url.clone(), (episode_id.to_string(), episode.clone(), lbl.clone()))]));
    let current = Mutex::new(episode_id.to_string());
    let done = AtomicBool::new(false);
    let goto: Mutex<Option<String>> = Mutex::new(None); // an episode the shell asked a room to jump to
    let mut pushed: HashSet<String> = HashSet::new();
    let (finish_ratio, finish_tail) = (o.finish_ratio, o.finish_tail);
    let mut on_watched = o.on_watched.take();
    let mut on_resolved = o.on_resolved.take();
    let mut on_ready_pid = o.on_ready_pid.take();
    let poster = o.poster.clone();
    let (quality, dub, anilist_id, season, total) = (o.quality.clone(), o.dub, o.anilist_id, o.season, o.total);
    let syncplay_on = o.syncplay.is_some();
    let queue = std::mem::take(&mut o.queue);
    let order = std::mem::take(&mut o.order);
    let resolve_next = o.resolve_next;
    let queue_window = o.queue_window;

    let result = std::thread::scope(|sc| {
        let switch_to = |eid: &str, ep: &Value, ep_label: &str, path: &str| {
            let previous = std::mem::replace(&mut *current.lock().unwrap(), eid.to_string());
            np::finish_session(title_id, &previous, &sock);
            let resume = resume_point(&np::load_episode(title_id, eid), title_id, eid);
            np::begin(title_id, eid, np::Begin {
                title: name.clone(), poster: poster.clone(), episodes: Some(episodes.clone()),
                episode_number: ep["number"].as_str().unwrap_or("").into(), episode_title: ep["title"].as_str().unwrap_or("").into(),
                quality: Some(quality.clone()), dub, position: resume, duration: 0.0, anilist_id, season, total,
            });
            np::attach_session(title_id, eid, &sock, np::Attach { worker_pid: std::process::id() as i64, media_title: ep_label.into(), position: Some(resume), duration: Some(0.0), paused: None });
            // `--force-media-title` is one value for the whole run, so a room that moves on by
            // itself would keep showing the first episode's name: set it for this one.
            if syncplay_on {
                let _ = player::ipc_command(&sock, &[json!("set_property"), json!("force-media-title"), json!(ep_label)], 3.0);
            }
            // In a room a seek is broadcast and would move everyone: the room sets the position.
            if resume > 0.0 && !syncplay_on {
                let (s, p) = (sock.clone(), path.to_string());
                sc.spawn(move || seek_when_ready(&s, resume, &p, 30.0));
            }
        };

        if !queue.is_empty() && resolve_next.is_some() && !syncplay_on {
            let resolve_next = resolve_next.unwrap();
            let (sock, by_url, done, name) = (&sock, &by_url, &done, &name);
            let queue = queue.clone();
            sc.spawn(move || {
                for _ in 0..200 {
                    if std::path::Path::new(sock).exists() {
                        break;
                    }
                    std::thread::sleep(Duration::from_millis(100));
                }
                let mut pending: std::collections::VecDeque<String> = queue.into();
                while let Some(_) = pending.front() {
                    if done.load(Ordering::SeqCst) {
                        return;
                    }
                    let pos = player::ipc_command(sock, &[json!("get_property"), json!("playlist-pos")], 5.0);
                    let count = player::ipc_command(sock, &[json!("get_property"), json!("playlist-count")], 5.0);
                    let (Some(pos), Some(count)) = (pos, count) else { return };
                    if pos["error"] != "success" || count["error"] != "success" {
                        return;
                    }
                    if count["data"].as_i64().unwrap_or(0) - pos["data"].as_i64().unwrap_or(0) - 1 >= queue_window {
                        std::thread::sleep(Duration::from_secs(2));
                        continue;
                    }
                    let eid = pending.pop_front().unwrap();
                    let Ok((ep, src)) = resolve_next(&eid) else { return }; // stop here rather than skip around it
                    let ep_label = label(name, &ep);
                    by_url.lock().unwrap().insert(src.url.clone(), (eid.clone(), ep.clone(), ep_label.clone()));
                    let reply = if !src.subtitles.is_empty() {
                        // its own subtitle file (and exact referer) can only travel as loadfile options
                        let mut opts = vec![format!("force-media-title={}", player::kv_value(&ep_label)), format!("sub-file={}", player::kv_value(&src.subtitles))];
                        if !src.referer.is_empty() {
                            opts.push(format!("referrer={}", player::kv_value(&src.referer)));
                        }
                        player::ipc_command(sock, &[json!("loadfile"), json!(src.url), json!("append"), json!(-1), json!(opts.join(","))], 5.0)
                    } else {
                        // a one-entry m3u gives the playlist menu the episode's name, not its URL
                        match titled_entry(&ep_label, &src.url) {
                            Ok(f) => player::ipc_command(sock, &[json!("loadlist"), json!(f), json!("append")], 5.0),
                            Err(_) => return,
                        }
                    };
                    if reply.map(|r| r["error"] != "success").unwrap_or(true) {
                        return;
                    }
                }
            });
        }

        if feeding && start > 0.0 {
            let (s, p) = (sock.clone(), source.url.clone());
            sc.spawn(move || seek_when_ready(&s, start, &p, 30.0));
        }

        if let Some(control) = control.clone() {
            let (done, sock) = (&done, &sock);
            let goto = &goto;
            sc.spawn(move || room_keys(&control, sock, done, goto));
        }

        if let (Some(control), Some(resolve_next)) = (control.clone(), resolve_next) {
            let (by_url, done, name, first, sock, goto, order) = (&by_url, &done, &name, source.url.clone(), &sock, &goto, &order);
            sc.spawn(move || {
                let nap = |secs: f64| {
                    let end = Instant::now() + Duration::from_secs_f64(secs);
                    while Instant::now() < end && !done.load(Ordering::SeqCst) {
                        std::thread::sleep(Duration::from_millis(200));
                    }
                };
                for _ in 0..300 {
                    if std::path::Path::new(&control).exists() || done.load(Ordering::SeqCst) {
                        break;
                    }
                    std::thread::sleep(Duration::from_millis(100));
                }
                let mut pending: std::collections::VecDeque<String> = queue.into();
                let mut ours: HashSet<String> = HashSet::new(); // what this worker put in the room
                let mut misses = 0;
                // Syncplay moves on by itself when a file ends, but two players ending together
                // can both miss it and leave the room parked on the last frame. If this player
                // sits at the end of a file while the room has a next entry, nudge the room on.
                let mut ended_polls = 0;
                let mut nudged: Option<usize> = None;
                while !done.load(Ordering::SeqCst) {
                    let Some((room, connected)) = room_state(&control) else {
                        misses += 1;
                        if misses > 60 { return; } // the session is gone
                        nap(2.0);
                        continue;
                    };
                    misses = 0;
                    if !connected {
                        nap(2.0);
                        continue;
                    }
                    let at = room.index.unwrap_or(0);
                    let at_end = player::ipc_command(&sock, &[json!("get_property"), json!("eof-reached")], 3.0)
                        .map(|r| r["data"] == true)
                        .unwrap_or(false);
                    ended_polls = if at_end { ended_polls + 1 } else { 0 };
                    if ended_polls >= 2 && at + 1 < room.items.len() && nudged != Some(at) {
                        nudged = Some(at);
                        room_play(&control, at + 1);
                        nap(2.0);
                        continue;
                    }
                    if room.items.is_empty() {
                        // The one playing goes in first, so adding the next does not switch to it
                        if room_add(&control, &first) {
                            ours.insert(first.clone());
                        }
                        nap(1.0);
                        continue;
                    }
                    // The shell picked an episode the room does not hold: add it and move the room
                    // there, so the player stays open instead of leaving and rejoining.
                    let wanted = goto.lock().unwrap().take();
                    if let Some(target) = wanted {
                        let known = by_url.lock().unwrap().iter().find(|(_, v)| v.0 == target).map(|(u, _)| u.clone());
                        let url = match known.filter(|u| room.items.contains(u)) {
                            Some(u) => Some(u),
                            None => match resolve_next(&target) {
                                Ok((ep, src)) => {
                                    let l = label(name, &ep);
                                    by_url.lock().unwrap().insert(src.url.clone(), (target.clone(), ep, l));
                                    if room_add(&control, &src.url) {
                                        ours.insert(src.url.clone());
                                        Some(src.url)
                                    } else {
                                        None
                                    }
                                }
                                Err(_) => None,
                            },
                        };
                        if let (Some(url), Some((fresh, _))) = (url, room_state(&control)) {
                            if let Some(i) = fresh.items.iter().position(|x| *x == url) {
                                room_play(&control, i);
                                if !room.items.contains(&url) {
                                    // what follows the jump is fed from here on
                                    let held: HashSet<String> = by_url.lock().unwrap().iter()
                                        .filter(|(u, _)| fresh.items.contains(*u)).map(|(_, v)| v.0.clone()).collect();
                                    let after = order.iter().position(|x| *x == target).map(|p| p + 1).unwrap_or(order.len());
                                    pending = order[after.min(order.len())..].iter().filter(|e| !held.contains(*e)).cloned().collect();
                                }
                            }
                        }
                        nap(1.0);
                        continue;
                    }
                    if pending.is_empty() {
                        nap(2.0);
                        continue;
                    }
                    if ours.is_empty() && !room.items.contains(&first) {
                        return; // the room already has someone else's list: leave it alone
                    }
                    if !room.items.last().map(|l| ours.contains(l)).unwrap_or(false) {
                        nap(2.0); // somebody else added after us: only one feeder per room
                        continue;
                    }
                    let behind = room.items.len().saturating_sub(at + 1);
                    if behind as i64 >= queue_window {
                        nap(2.0);
                        continue;
                    }
                    let eid = pending.pop_front().unwrap();
                    let Ok((ep, src)) = resolve_next(&eid) else { return }; // stop here rather than skip around it
                    let ep_label = label(name, &ep);
                    // Known before it is added, so that an advance is recognised whoever causes it
                    by_url.lock().unwrap().insert(src.url.clone(), (eid, ep, ep_label));
                    if room_add(&control, &src.url) {
                        ours.insert(src.url.clone());
                    } else {
                        return;
                    }
                }
            });
        }

        let on_path = |p: &str| {
            let known = by_url.lock().unwrap().get(p).cloned();
            if let Some((eid, ep, l)) = known {
                if eid != *current.lock().unwrap() {
                    switch_to(&eid, &ep, &l, p);
                }
            }
        };
        let checkpoint = |r: player::FileResult| {
            let known = by_url.lock().unwrap().get(&r.path).cloned();
            // In a room fed by this worker, a file it does not know was loaded by someone else:
            // it must not be credited to the episode being remembered, marked watched or synced.
            if feeding && known.is_none() {
                return;
            }
            let ep_id = known.as_ref().map(|k| k.0.clone()).unwrap_or_else(|| current.lock().unwrap().clone());
            if let Some((eid, ep, l)) = &known {
                if *eid != *current.lock().unwrap() {
                    switch_to(eid, ep, l, &r.path);
                }
            }
            let state = np::checkpoint(title_id, &ep_id, r.position, r.duration, r.eof, finish_ratio, finish_tail);
            if state["watched"] == true && pushed.insert(ep_id) {
                if let Some(cb) = on_watched.as_mut() {
                    cb(&state); // syncing must never take playback down
                }
            }
        };
        let res = player::run_external(&cmd, checkpoint, player::RunOptions {
            sock_path: Some(sock.clone()), terminal: o.terminal,
            on_ready: on_resolved.take().map(|mut f| Box::new(move || f()) as Box<dyn FnMut()>),
            on_ready_pid: on_ready_pid.take(), on_path: Some(Box::new(on_path)), ..Default::default()
        });
        done.store(true, Ordering::SeqCst);
        res
    });
    np::finish_session(title_id, &current.lock().unwrap(), &sock);
    for f in ENTRY_FILES.lock().unwrap().drain(..) {
        let _ = std::fs::remove_file(f);
    }
    match result {
        Ok(0) => Ok(0),
        Ok(rc) => Err(ProviderError(format!("mpv exited with code {rc}"))),
        Err(e) => Err(ProviderError(format!("could not start mpv: {e}"))),
    }
}

impl Provider {
    /// Play an episode in mpv (see `native_player::play`).
    pub fn play(&self, title_id: &str, episode_id: &str, o: Play) -> Result<i32, ProviderError> {
        play(self, title_id, episode_id, o)
    }
}

#[cfg(test)]
mod room_tests {
    use super::*;
    use std::io::{BufRead, BufReader, Write};
    use std::os::unix::net::UnixListener;

    /// A stand-in for the shell's control socket: replies to `state` and `playlist-add`.
    fn fake_session(name: &str, items: Vec<&'static str>, index: u64) -> (String, std::thread::JoinHandle<Vec<Value>>) {
        let path = std::env::temp_dir().join(format!("mrt-{}-{name}.sock", std::process::id()));
        let _ = std::fs::remove_file(&path);
        let listener = UnixListener::bind(&path).unwrap();
        let handle = std::thread::spawn(move || {
            let mut seen = vec![];
            for _ in 0..2 {
                let (stream, _) = listener.accept().unwrap();
                let mut line = String::new();
                BufReader::new(stream.try_clone().unwrap()).read_line(&mut line).unwrap();
                let req: Value = serde_json::from_str(&line).unwrap();
                let mut out = stream;
                // history comes first on a real session: it must be skipped
                writeln!(out, "{}", json!({"type": "msg", "kind": "system", "text": "hello"})).unwrap();
                if req["cmd"] == "state" {
                    writeln!(out, "{}", json!({"type": "state", "connected": true, "playlist": {"items": items, "index": index}})).unwrap();
                } else {
                    writeln!(out, "{}", json!({"type": "ack", "id": req["id"], "ok": true})).unwrap();
                }
                seen.push(req);
            }
            seen
        });
        (path.to_string_lossy().into_owned(), handle)
    }

    #[test]
    fn reads_the_rooms_list_and_adds_a_trusted_link() {
        let (path, handle) = fake_session("a", vec!["https://h/ep1", "https://h/ep2"], 1);
        let (room, connected) = room_state(&path).expect("state");
        assert!(connected);
        assert_eq!(room.items, vec!["https://h/ep1", "https://h/ep2"]);
        assert_eq!(room.index, Some(1));
        assert!(room_add(&path, "https://h/ep3"));
        let seen = handle.join().unwrap();
        assert_eq!(seen[1]["cmd"], "playlist-add");
        assert_eq!(seen[1]["item"], "https://h/ep3");
        assert_eq!(seen[1]["trust"], true, "the host must be vouched for");
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn a_missing_socket_is_none_not_a_panic() {
        assert!(room_state("/nonexistent/mediator-room.sock").is_none());
        assert!(!room_add("/nonexistent/mediator-room.sock", "https://h/x"));
    }

    #[test]
    fn control_socket_comes_from_the_environment_only() {
        std::env::remove_var("MEDIATOR_SYNCPLAY_CONTROL");
        assert!(syncplay_control().is_none());
    }
}

#[cfg(test)]
mod label_tests {
    use super::*;

    #[test]
    fn the_episode_name_follows_the_number() {
        assert_eq!(label("Breaking Bad", &json!({"number": "S05E16", "title": "Felina"})), "Breaking Bad S05E16 \u{b7} Felina");
        assert_eq!(label("One Piece", &json!({"number": "1100", "title": "A Title"})), "One Piece Episode 1100 \u{b7} A Title");
    }

    #[test]
    fn no_name_or_no_number_keeps_the_plain_label() {
        assert_eq!(label("Show", &json!({"number": "3", "title": ""})), "Show Episode 3");
        assert_eq!(label("Movie", &json!({"number": "", "title": "Cut"})), "Movie");
        // a title the number line already says is not repeated
        assert_eq!(label("Show", &json!({"number": "2", "title": "Show Episode 2"})), "Show Episode 2");
    }
}
