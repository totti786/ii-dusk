//! Browsing and playback commands: list, show, continue, play, playlist, watched, history, browse,
//! import-legacy, cache, doctor, parse.
use super::{die, kinds_of, load_jellyfin, pretty, Cmd, Ctx, CliError, Res, Span};
use crate::catalog::{diagnose, Entry, Title};
use crate::jellyfin as jf;
use crate::notify::{notify, warn};
use crate::parse::{fmt_num, parse_dirname, parse_episode, parse_movie};
use crate::picker::make_picker;
use crate::resume::{episode_status, fmt_time, mark_watched, plan_for};
use crate::selection::{pick, py_str, slice_order};
use crate::session::play_queue;
use crate::state::Progress;
use crate::ui::{default_play, title_summary, watched_count, Browser};
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::io::{BufRead, IsTerminal, Write};

pub fn run(cmd: Cmd, ctx: &mut Ctx) -> Res {
    match cmd {
        Cmd::List { k, f } => list(ctx, k.kind, f.json, f.tsv),
        Cmd::Show { query, all, f } => show(ctx, &query, all, f.json, f.tsv),
        Cmd::Continue { query, dry_run, rewatch, detach, json } => cont(ctx, &query, dry_run, rewatch, detach, json),
        Cmd::Play { query, span, one, path, resume, detach } => play(ctx, &query, span, one, path, resume, detach),
        Cmd::Playlist { query, span, specials, output } => playlist(ctx, &query, span, specials, output),
        Cmd::Watched { query, span } => mark(ctx, &query, span, true),
        Cmd::Unwatched { query, span } => mark(ctx, &query, span, false),
        Cmd::History { n, clear, yes, f } => history(ctx, n, clear, yes, f.json, f.tsv),
        Cmd::Browse { k, picker, once } => browse(ctx, k.kind, picker, once),
        Cmd::ImportLegacy { file, dry_run } => import_legacy(ctx, file, dry_run),
        Cmd::Cache { prune, json } => cache(prune, json),
        Cmd::Doctor { k, verbose } => doctor(ctx, k.kind, verbose),
        Cmd::Parse { names, movie, json } => parse(&names, movie, json),
        _ => unreachable!(),
    }
}

// ---- JSON shapes ----

pub fn entry_json(e: &Entry, p: Option<&Progress>, ep: Option<Value>) -> Value {
    let mut d = Map::new();
    d.insert("path".into(), json!(e.path));
    d.insert("kind".into(), json!(e.kind));
    d.insert("season".into(), json!(e.season));
    d.insert("episode".into(), crate::cli::library::episode_value(e.episode));
    d.insert("episode_end".into(), json!(e.episode_end));
    d.insert("code".into(), json!(e.code()));
    d.insert("label".into(), json!(e.label()));
    d.insert("name".into(), json!(e.name));
    d.insert("size".into(), json!(e.size));
    d.insert("rule".into(), json!(e.rule));
    d.insert("confidence".into(), json!(e.confidence));
    if let Some(ep) = ep {
        d.insert("episode_info".into(), ep); // keep "episode" the number; the record is extra detail
    }
    if e.path.starts_with('/') {
        if let Some(media) = crate::probe::cached(&e.path) {
            d.insert("media".into(), media);
        }
    }
    if let Some(p) = p {
        d.insert("progress".into(), json!({"position": p.position, "duration": p.duration, "watched": p.watched, "updated": p.updated}));
    }
    Value::Object(d)
}

/// Python keeps `episode` a float (1.0), which json.dumps prints as 1.0.
pub fn episode_value(n: Option<f64>) -> Value {
    n.map(|x| json!(x)).unwrap_or(Value::Null)
}

fn truthy(v: &Value) -> bool {
    match v { Value::Null => false, Value::Bool(b) => *b, Value::Number(n) => n.as_f64() != Some(0.0), Value::String(s) => !s.is_empty(), Value::Array(a) => !a.is_empty(), Value::Object(o) => !o.is_empty() }
}
fn first(a: Option<&Value>, b: Option<&Value>) -> Value {
    for v in [a, b].into_iter().flatten() {
        if truthy(v) {
            return v.clone();
        }
    }
    Value::Null
}

/// The first sentences of a description, short enough for a card or a hero.
pub fn blurb(text: &Value, limit: usize) -> Value {
    let Some(t) = text.as_str().filter(|s| !s.is_empty()) else { return Value::Null };
    let t = t.split_whitespace().collect::<Vec<_>>().join(" ");
    if t.chars().count() <= limit {
        return json!(t);
    }
    let cut: String = t.chars().take(limit).collect();
    let head = cut.rsplit_once(' ').map(|(h, _)| h).unwrap_or(&cut);
    json!(format!("{}…", head.trim_end_matches([',', ';', ':'])))
}

pub fn title_json(t: &Title, prog: &HashMap<String, Progress>, full: bool) -> Value {
    let (done, total) = watched_count(t, prog);
    let plan = plan_for(t, prog);
    let m = crate::meta::find(t);
    let inf = crate::info::find(t);
    let null = Value::Null;
    let (mv, iv) = (m.as_ref().unwrap_or(&null), inf.as_ref().unwrap_or(&null));
    let genres = match first(iv.get("genres"), mv.get("genres")) {
        Value::Array(a) => Value::Array(a.into_iter().take(3).collect()),
        _ => json!([]),
    };
    let next = plan.entry.as_ref().map(|e| {
        json!({"reason": plan.reason, "code": e.code(), "label": e.label(), "path": e.path, "position": plan.position,
               "duration": prog.get(&e.path).map(|p| json!(p.duration)).unwrap_or(json!(0))})
    });
    let mut d = Map::new();
    d.insert("poster".into(), crate::posters::find(t).map(|p| json!(p.to_string_lossy())).unwrap_or(Value::Null));
    d.insert("banner".into(), crate::info::banner_path(t, &crate::info::info_dir()).map(|p| json!(p.to_string_lossy())).unwrap_or(Value::Null));
    // field-level fallback: an info record can exist without a rating or genres
    d.insert("rating".into(), { let r = first(iv.get("rating"), mv.get("rating")); r });
    d.insert("genres".into(), genres);
    d.insert("status".into(), iv.get("status").cloned().unwrap_or(Value::Null));
    d.insert("blurb".into(), blurb(&first(iv.get("description"), mv.get("synopsis")), 240));
    d.insert("next_airing".into(), iv.get("next_airing").cloned().unwrap_or(Value::Null));
    d.insert("color".into(), iv.get("color").cloned().unwrap_or(Value::Null));
    d.insert("id".into(), json!(t.id));
    d.insert("lib".into(), json!(t.lib));
    d.insert("source".into(), json!(t.source));
    d.insert("name".into(), json!(t.name));
    d.insert("year".into(), json!(t.year));
    d.insert("display".into(), json!(t.display()));
    d.insert("episodes".into(), json!(t.episodes().len()));
    d.insert("seasons".into(), json!(t.seasons().len()));
    d.insert("files".into(), json!(t.entries.len()));
    d.insert("watched".into(), json!(done));
    d.insert("total".into(), json!(total));
    d.insert("next".into(), next.unwrap_or(Value::Null));
    if full {
        d.insert("meta".into(), m.clone().unwrap_or(Value::Null));
        d.insert("info".into(), inf.clone().unwrap_or(Value::Null));
        let entries: Vec<Value> = t.entries.iter().map(|e| {
            let ep = inf.as_ref().and_then(|i| crate::info::episode_for(i, &json!(e.season.unwrap_or(1)), &e.episode.map(whole_or_float).unwrap_or(Value::Null)));
            entry_json(e, prog.get(&e.path), ep)
        }).collect();
        d.insert("entries".into(), Value::Array(entries));
    }
    Value::Object(d)
}

/// An episode number the way JSON stored it: whole numbers as integers.
pub fn whole_or_float(f: f64) -> Value {
    if f == f.trunc() { json!(f as i64) } else { json!(f) }
}

fn counts(t: &Title) -> String {
    if t.lib == "movies" {
        return String::new();
    }
    let mut bits = vec![];
    let n = t.seasons().len();
    if n > 0 {
        bits.push(format!("{n} season{}, {} eps", if n != 1 { "s" } else { "" }, t.episodes().len()));
    }
    for (kind, word) in [("special", "specials"), ("movie", "movies"), ("extra", "extras")] {
        let c = t.of_kind(kind).len();
        if c > 0 {
            bits.push(format!("{c} {word}"));
        }
    }
    bits.join(", ")
}

fn ago(ts: f64) -> String {
    let d = (crate::state::now() - ts).max(0.0);
    for (unit, sec) in [("d", 86400.0), ("h", 3600.0), ("m", 60.0)] {
        if d >= sec {
            return format!("{}{unit} ago", (d / sec).floor() as i64);
        }
    }
    "just now".into()
}

/// Re-fetch any server listing older than its TTL in a detached process, so the next call finds it
/// fresh. The caller already answered from the cache and must not wait on the network.
fn refresh_jellyfin_behind(ctx: &Ctx) {
    if !ctx.cfg.jellyfin.configured() {
        return;
    }
    let client = jf::Jellyfin::new(&ctx.cfg.jellyfin);
    let ttl = ctx.cfg.jellyfin.cache_ttl as f64;
    let stale = client.kinds().iter().any(|k| {
        let cache = crate::fileio::read_json(&jf::cache_dir().join(format!("{k}.json")));
        cache.is_null() || cache.as_object().map(|o| o.is_empty()).unwrap_or(true) || crate::state::now() - cache["fetched"].as_f64().unwrap_or(0.0) >= ttl
    });
    if stale {
        use std::os::unix::process::CommandExt;
        if let Ok(exe) = std::env::current_exe() {
            let mut c = std::process::Command::new(exe);
            c.args(["jellyfin", "refresh"]).stdin(std::process::Stdio::null()).stdout(std::process::Stdio::null()).stderr(std::process::Stdio::null());
            unsafe {
                c.pre_exec(|| {
                    libc::setsid();
                    Ok(())
                });
            }
            let _ = c.spawn();
        }
    }
}

// ---- commands ----

fn list(ctx: &mut Ctx, kind: Option<String>, json: bool, tsv: bool) -> Res {
    ctx.kinds = kinds_of(&kind);
    if json && ctx.jellyfin {
        // the shell opens on this: a cached server listing is shown at once, however old, and refreshed behind it
        ctx.jellyfin_any_age = true;
    }
    let rows: Vec<(&Title, HashMap<String, Progress>)> = ctx.titles().iter().map(|t| (t, ctx.state().for_title(&t.id).unwrap_or_default())).collect();
    if json {
        let arr: Vec<Value> = rows.iter().map(|(t, p)| title_json(t, p, false)).collect();
        println!("{}", pretty(&Value::Array(arr)));
        let _ = std::io::stdout().flush();
        if ctx.jellyfin_any_age {
            refresh_jellyfin_behind(ctx);
        }
    } else if tsv {
        for (t, p) in &rows {
            println!("{}\t{}\t{}", t.id, t.display(), title_summary(t, p));
        }
    } else {
        let w = rows.iter().map(|(t, _)| t.display().chars().count()).max().unwrap_or(0);
        for (t, p) in &rows {
            let extra = if !p.is_empty() { title_summary(t, p) } else { counts(t) };
            println!("{}  {:<44} {}", pad(&t.display(), w), t.id, extra);
        }
    }
    Ok(0)
}

fn pad(s: &str, w: usize) -> String {
    let n = s.chars().count();
    format!("{s}{}", " ".repeat(w.saturating_sub(n)))
}

fn pick_title(ctx: &Ctx, q: &str) -> Result<Title, CliError> {
    Ok(pick(ctx.titles(), q)?.clone())
}

fn show(ctx: &mut Ctx, query: &str, all: bool, json: bool, tsv: bool) -> Res {
    let t = pick_title(ctx, query)?;
    let prog = ctx.state().for_title(&t.id).unwrap_or_default();
    if json {
        println!("{}", pretty(&title_json(&t, &prog, true)));
        return Ok(0);
    }
    if tsv {
        for e in &t.entries {
            if all || e.kind == "episode" || e.kind == "movie" {
                println!("{}\t{}\t{}\t{}\t{}", e.path, e.label(), e.kind, e.season.map(|s| s.to_string()).unwrap_or_default(), episode_status(prog.get(&e.path)));
            }
        }
        return Ok(0);
    }
    println!("{}   [{}]", t.display(), t.id);
    if t.lib == "movies" {
        let e = &t.entries[0];
        println!("  {}", e.path);
        let st = episode_status(prog.get(&e.path));
        if !st.is_empty() {
            println!("  {st}");
        }
        return Ok(0);
    }
    let plan = plan_for(&t, &prog);
    if !prog.is_empty() && plan.entry.is_some() {
        println!("  {}", plan.describe());
    }
    let row = |e: &Entry| {
        let st = episode_status(prog.get(&e.path));
        let mark = if st == "watched" { "✓" } else if !st.is_empty() { "◐" } else { " " };
        let tail = if st.is_empty() || st == "watched" { String::new() } else { format!("  {st}") };
        format!("    {mark} {}{tail}", e.label())
    };
    for (season, eps) in t.seasons() {
        println!("  Season {season}  ({} episodes)", eps.len());
        for e in eps {
            println!("{}", row(e));
        }
    }
    for (kind, head) in [("special", "Specials"), ("movie", "Movies"), ("extra", "Extras")] {
        let items = t.of_kind(kind);
        if items.is_empty() {
            continue;
        }
        if kind == "extra" && !all {
            println!("  Extras: {} hidden (use --all)", items.len());
            continue;
        }
        println!("  {head}  ({})", items.len());
        for e in items {
            println!("{}", row(e));
        }
    }
    Ok(0)
}

fn history(ctx: &mut Ctx, n: i64, clear: bool, yes: bool, json: bool, tsv: bool) -> Res {
    if clear {
        let count = ctx.state().count().unwrap_or(0);
        if count == 0 {
            println!("nothing to clear");
            return Ok(0);
        }
        if !yes {
            if !std::io::stdin().is_terminal() {
                return die("--clear deletes all saved progress; pass --yes to confirm");
            }
            print!("Delete progress for {count} files? [y/N] ");
            let _ = std::io::stdout().flush();
            let mut line = String::new();
            let _ = std::io::stdin().lock().read_line(&mut line);
            if !["y", "yes"].contains(&line.trim().to_lowercase().as_str()) {
                println!("kept");
                return Ok(1);
            }
        }
        let _ = ctx.state().clear();
        println!("cleared progress for {count} files");
        return Ok(0);
    }
    let recent = ctx.state().recent_titles(n).unwrap_or_default();
    if !ctx.jellyfin && recent.iter().any(|p| p.title_id.starts_with("jellyfin/")) {
        // only to name what was played: the shell runs this on every refresh
        ctx.jellyfin = true;
        ctx.jellyfin_any_age = true;
    }
    let by_id: HashMap<&str, &Title> = ctx.titles().iter().map(|t| (t.id.as_str(), t)).collect();
    let rows: Vec<(&Title, &Progress)> = recent.iter().filter_map(|p| by_id.get(p.title_id.as_str()).map(|t| (*t, p))).collect();
    let prog = |t: &Title| ctx.state().for_title(&t.id).unwrap_or_default();
    if json {
        let arr: Vec<Value> = rows.iter().map(|(t, p)| {
            let mut v = title_json(t, &prog(t), false);
            v.as_object_mut().unwrap().insert("last_played".into(), json!(p.updated));
            v
        }).collect();
        println!("{}", pretty(&Value::Array(arr)));
    } else if tsv {
        for (t, _) in &rows {
            println!("{}\t{}\t{}", t.id, t.display(), title_summary(t, &prog(t)));
        }
    } else {
        for (t, p) in &rows {
            println!("{:>9}  {}  ·  {}", ago(p.updated), t.display(), title_summary(t, &prog(t)));
        }
    }
    Ok(0)
}

// ---- playback ----

fn launch(ctx: &mut Ctx, t: &Title, queue: &[Entry], start: f64, detach: bool) -> Res {
    if queue.is_empty() {
        warn("mediator: nothing to play");
        return Ok(1);
    }
    if detach {
        ctx.close_state(); // a SQLite connection must not cross fork()
        let pid = unsafe { libc::fork() };
        if pid < 0 {
            return die("could not detach");
        }
        if pid != 0 {
            return Ok(0);
        }
        unsafe {
            libc::setsid();
            let dn = libc::open(c"/dev/null".as_ptr(), libc::O_RDWR);
            libc::dup2(dn, 0);
            libc::dup2(dn, 1);
        }
        let dir = crate::config::state_dir();
        let _ = std::fs::create_dir_all(&dir);
        if let Ok(log) = std::fs::OpenOptions::new().create(true).append(true).open(dir.join("mediator.log")) {
            use std::os::fd::AsRawFd;
            unsafe { libc::dup2(log.as_raw_fd(), 2) }; // a detached run has no terminal; errors go to the log
        }
        let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| play_queue(t, queue, start, ctx.state(), &ctx.cfg, Some(false), None)));
        match outcome {
            Ok(Err(e)) => {
                eprintln!("mediator: {e}");
                notify(&format!("playback failed: {e}"), false);
            }
            Err(_) => notify("playback failed", false),
            _ => {}
        }
        unsafe { libc::_exit(0) };
    }
    play_queue(t, queue, start, ctx.state(), &ctx.cfg, None, None).map_err(CliError)
}

fn cont(ctx: &mut Ctx, query: &str, dry_run: bool, rewatch: bool, detach: bool, json: bool) -> Res {
    let t = pick_title(ctx, query)?;
    let plan = plan_for(&t, &ctx.state().for_title(&t.id).unwrap_or_default());
    if dry_run {
        if json {
            let e = plan.entry.as_ref();
            println!("{}", json!({"id": t.id, "reason": plan.reason, "description": plan.describe(), "code": e.map(|e| e.code()), "label": e.map(|e| e.label()),
                "path": e.map(|e| e.path.clone()), "position": plan.position, "queue": plan.queue.len()}));
        } else {
            println!("{}", plan.describe());
        }
        return Ok(0);
    }
    if plan.entry.is_none() {
        warn(&format!("mediator: {} has nothing playable", t.display()));
        return Ok(1);
    }
    if plan.reason == "finished" && !rewatch {
        warn(&format!("{}: everything is watched. `mediator play {}` starts over.", t.display(), t.id));
        return Ok(3);
    }
    eprintln!("{}: {}", t.display(), plan.describe());
    launch(ctx, &t, &plan.queue, plan.position, detach)
}

fn play(ctx: &mut Ctx, query: &str, span: Span, one: bool, path: Option<String>, resume: bool, detach: bool) -> Res {
    let t = pick_title(ctx, query)?;
    let mut queue: Vec<Entry> = if let Some(p) = &path {
        match t.entries.iter().find(|e| &e.path == p) {
            Some(e) => vec![e.clone()],
            None => return die(format!("{p} is not part of {}", t.display())),
        }
    } else {
        let mut q = slice_order(&t, span.start.as_deref(), span.end.as_deref(), span.season)?;
        if one {
            q.truncate(1);
        }
        q
    };
    let mut start = 0.0;
    if resume && !queue.is_empty() {
        if let Ok(Some(p)) = ctx.state().get(&queue[0].path, queue[0].size) {
            if !p.watched && p.position >= 5.0 {
                start = p.position;
            }
        }
    }
    let from = if !queue.is_empty() && !queue[0].code().is_empty() { format!(", from {}", queue[0].label()) } else { String::new() };
    eprintln!("{}: {} file{}{from}", t.display(), queue.len(), if queue.len() != 1 { "s" } else { "" });
    let q = std::mem::take(&mut queue);
    launch(ctx, &t, &q, start, detach)
}

fn playlist(ctx: &mut Ctx, query: &str, span: Span, specials: bool, output: Option<String>) -> Res {
    let t = pick_title(ctx, query)?;
    let mut queue = slice_order(&t, span.start.as_deref(), span.end.as_deref(), span.season)?;
    if specials {
        queue.extend(t.of_kind("special").into_iter().cloned());
        queue.sort_by(|a, b| {
            let k = |x: &Entry| (x.season.unwrap_or(0), if x.kind == "special" { 1 } else { 0 }, x.episode.unwrap_or(0.0));
            let (x, y) = (k(a), k(b));
            x.0.cmp(&y.0).then(x.1.cmp(&y.1)).then(x.2.partial_cmp(&y.2).unwrap_or(std::cmp::Ordering::Equal))
        });
    }
    let mut lines = vec!["#EXTM3U".to_string()];
    for item in &queue {
        lines.push(format!("#EXTINF:-1,{} - {}", t.display(), item.label()));
        lines.push(item.path.clone());
    }
    let out = lines.join("\n") + "\n";
    match output {
        Some(f) => {
            std::fs::write(&f, out).map_err(|e| CliError(e.to_string()))?;
            eprintln!("{} entries -> {f}", queue.len());
        }
        None => print!("{out}"),
    }
    Ok(0)
}

fn mark(ctx: &mut Ctx, query: &str, span: Span, watched: bool) -> Res {
    let t = pick_title(ctx, query)?;
    let queue = slice_order(&t, span.start.as_deref(), span.end.as_deref(), span.season)?;
    if watched {
        let _ = mark_watched(ctx.state(), &t, &queue);
    } else {
        let items: Vec<(String, i64, String)> = queue.iter().map(|e| (e.path.clone(), e.size, e.label())).collect();
        let _ = ctx.state().mark(&items, &t.id, false, false);
    }
    eprintln!("{}: {} marked {}", t.display(), queue.len(), if watched { "watched" } else { "unwatched" });
    let problem = jf::push_marks(&ctx.cfg.jellyfin, &queue, watched, None);
    if watched && crate::anilist::schedule(&t, &ctx.cfg) && !crate::anilist::flush(5.0) {
        warn("mediator: AniList did not answer in time; run `mediator anilist sync` later");
    }
    if let Some(p) = problem {
        warn(&format!("mediator: {p}"));
        return Ok(1);
    }
    Ok(0)
}

fn browse(ctx: &mut Ctx, kind: Option<String>, picker: Option<String>, once: bool) -> Res {
    let local_kind = kind.as_deref().filter(|k| crate::catalog::KINDS.contains(k)).map(String::from);
    ctx.kinds = local_kind.clone().map(|k| vec![k]);
    let picker = make_picker(picker.as_deref().unwrap_or(&ctx.cfg.picker))?;
    let local: Vec<Title> = if kind.as_deref() == Some("jellyfin") { vec![] } else { ctx.titles().to_vec() };
    let ctx = &*ctx;
    let kinds: Vec<String> = match &local_kind { Some(k) => vec![k.clone()], None => crate::catalog::KINDS.iter().map(|s| s.to_string()).collect() };
    let remote: Option<crate::ui::RemoteFn> = if ctx.cfg.jellyfin.configured() {
        Some(Box::new(move |fast| {
            let out = load_jellyfin(&ctx.cfg, &kinds, Some(ctx.state()), fast);
            if fast {
                // refresh the cache behind the menu
                let (cfg, ks) = (ctx.cfg.jellyfin.clone(), kinds.clone());
                std::thread::spawn(move || {
                    let client = jf::Jellyfin::new(&cfg);
                    for k in ks {
                        if client.kinds().contains(&k.as_str()) {
                            let _ = client.library(&k, false, false); // a no-op while the cache is fresh
                        }
                    }
                });
            }
            out
        }))
    } else {
        None
    };
    let mut b = Browser::new(&ctx.cfg, ctx.state(), picker.as_ref(), local, default_play(), once, remote);
    b.run(kind.as_deref());
    Ok(0)
}

fn import_legacy(ctx: &mut Ctx, file: Option<String>, dry_run: bool) -> Res {
    let path = file.unwrap_or_else(|| crate::config::expand_user("~/.local/state/mediator").join("media_history.txt").to_string_lossy().into_owned());
    let text = match std::fs::read(&path) {
        Ok(b) => String::from_utf8_lossy(&b).into_owned(),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return die(format!("{path} not found")),
        Err(e) => return die(e.to_string()),
    };
    let by_path: HashMap<String, (Title, Entry)> = ctx.titles().iter().flat_map(|t| t.entries.iter().map(move |e| (e.path.clone(), (t.clone(), e.clone())))).collect();
    let (mut imported, mut skipped) = (0, 0);
    for line in text.lines() {
        let cols: Vec<&str> = line.split('\t').collect();
        if cols.len() < 4 {
            continue;
        }
        let (pos, fpath, pct) = (cols[1], cols[2], cols[3]);
        let Some((t, e)) = by_path.get(fpath) else {
            println!("skip   {fpath}  (not in the library any more)");
            skipped += 1;
            continue;
        };
        let (Ok(position), Ok(pct)) = (pos.trim().parse::<f64>(), pct.trim().parse::<f64>()) else { continue };
        let ratio = pct / 100.0;
        let watched = ratio >= ctx.cfg.finish_ratio;
        if ctx.state().get(&e.path, 0).ok().flatten().is_some() {
            println!("keep   {}  (already has progress)", e.label());
            skipped += 1;
            continue;
        }
        let duration = if ratio > 0.0 { position / ratio } else { 0.0 };
        println!("{:<7}{} · {}{}", if watched { "watched" } else { "resume " }, t.display(), e.label(), if watched { String::new() } else { format!("  at {}", fmt_time(position)) });
        if !dry_run {
            let _ = ctx.state().put(&e.path, &t.id, if watched { 0.0 } else { position }, duration, watched, e.size, &e.label(), None);
        }
        imported += 1;
    }
    println!("\n{imported} imported, {skipped} skipped{}", if dry_run { " (dry run)" } else { "" });
    Ok(0)
}

/// Show how big Mediator's caches are; --prune trims images, http, subtitles and expired stream links.
fn cache(prune: bool, json: bool) -> Res {
    let result = if prune { Some(crate::housekeeping::run()) } else { None };
    let sizes = crate::housekeeping::sizes();
    if json {
        let pruned = result.as_ref().map(|r| json!({"files": r.files, "bytes": r.bytes, "stream_entries": r.stream_entries})).unwrap_or(Value::Null);
        println!("{}", json!({"ok": true, "sizes": sizes, "pruned": pruned}));
        return Ok(0);
    }
    let mut rows: Vec<(&String, &u64)> = sizes.iter().collect();
    rows.sort_by(|a, b| b.1.cmp(a.1));
    for (name, size) in rows {
        println!("{:8.1} MB  {name}", *size as f64 / 1048576.0);
    }
    if let Some(r) = result {
        println!("pruned {} files ({:.1} MB) and {} expired stream links", r.files, r.bytes as f64 / 1048576.0, r.stream_entries);
    }
    Ok(0)
}

fn doctor(ctx: &mut Ctx, kind: Option<String>, verbose: bool) -> Res {
    ctx.kinds = kinds_of(&kind);
    let problems = diagnose(ctx.titles());
    let shown: Vec<_> = problems.iter().filter(|p| verbose || p.0 == "warn").collect();
    for (sev, title, msg) in &shown {
        println!("{sev:<5} {title}: {msg}");
    }
    for (kind, files) in ctx.skipped() {
        for f in files {
            println!("skip  {kind}: {f}");
        }
    }
    let hidden = problems.len() - shown.len();
    let n_files: usize = ctx.titles().iter().map(|t| t.entries.len()).sum();
    let warns = problems.iter().filter(|p| p.0 == "warn").count();
    println!("\n{} titles, {n_files} files, {warns} warnings{}", ctx.titles().len(), if hidden > 0 { format!(" (+{hidden} notes, use -v)") } else { String::new() });
    Ok(if warns > 0 { 1 } else { 0 })
}

fn opt<T: ToString>(v: Option<T>) -> String {
    v.map(|x| x.to_string()).unwrap_or_else(|| "None".into())
}

fn parse(names: &[String], movie: bool, json_out: bool) -> Res {
    for raw in names {
        let trimmed = raw.trim_end_matches('/');
        let base = std::path::Path::new(trimmed).file_name().map(|b| b.to_string_lossy().into_owned()).unwrap_or_default();
        let (stem0, ext) = crate::catalog::splitext(&base);
        let stem: String = if [".mkv", ".mp4", ".avi", ".m4v", ".webm", ".mov"].contains(&ext.to_lowercase().as_str()) { stem0.to_string() } else { base.clone() };
        let info = if movie { parse_movie(&stem) } else { parse_episode(&stem) };
        let d = parse_dirname(&base);
        if json_out {
            let file = json!({"kind": info.kind, "show": info.show, "year": info.year, "season": info.season, "episode": info.episode, "episode_end": info.episode_end,
                "version": info.version, "title": info.title, "rule": info.rule, "confidence": info.confidence});
            println!("{}", json!({"input": raw, "file": file, "dir": {"title": d.title, "year": d.year, "season": d.season, "kind": d.kind}}));
            continue;
        }
        println!("{raw}");
        println!("  file: {:<8} show={} year={} S={} E={}{} v{} title={}  [{}, {}]", info.kind, py_str(&info.show), opt(info.year), opt(info.season), fmt_num(info.episode),
            info.episode_end.filter(|&e| e != 0).map(|e| format!("-{e}")).unwrap_or_default(), info.version, py_str(&info.title), info.rule, info.confidence);
        println!("  dir : {:<9} title={} year={} season={}", d.kind, py_str(&d.title), opt(d.year), opt(d.season));
    }
    Ok(0)
}
