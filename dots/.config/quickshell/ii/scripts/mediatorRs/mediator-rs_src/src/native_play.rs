//! Playing a native (online) episode: Stremio movies and series, and provider anime
//! (port of `mediator/native_play.py`). Resolves the stream, starts mpv through `Provider::play`,
//! queues the episodes after it, and pushes finished episodes to AniList.
use crate::anilist;
use crate::anime_provider::{Provider, ProviderError, Source};
use crate::config::{Config, Streaming};
use crate::errors::StreamError;
use crate::native_player::Play;
use crate::stremio::{self, Endpoints};
use serde_json::{json, Value};
use std::time::Instant;

/// Prefix of the error `run` returns when a direct stream failed and the user should decide.
const DIRECT_FAILED: &str = "\u{1}direct-failed:";

pub const QUEUE_WINDOW: i64 = 2; // episodes kept queued behind the one playing

/// How long the detached stopper waits before stopping an idle Stremio server.
pub const STOP_DELAY: f64 = 90.0;

pub fn provider_json(value: &Value) {
    println!("{}", value);
}

/// (AniList id, season, total) for a provider title, when an exact match exists.
pub fn native_media_mapping(cfg: &Config, title: &str) -> (i64, i64, i64) {
    if cfg.anilist.token.is_empty() || title.is_empty() {
        return (0, 0, 0);
    }
    let client = anilist::Client::new(&cfg.anilist.token, cfg.anilist.user_id);
    match client.search_media(title, None, false) {
        Ok(Some(m)) => (
            m["id"].as_i64().unwrap_or(0),
            if m["format"] == "MOVIE" { 0 } else { 1 },
            m["episodes"].as_i64().unwrap_or(0),
        ),
        _ => (0, 0, 0),
    }
}

pub struct Mapping {
    pub anilist_id: i64,
    pub season: i64,
    pub total: i64,
}

/// The callback run when an episode counts as watched.
pub fn native_sync_callback<'a>(cfg: &'a Config, mut m: Mapping, disabled: bool, lazy_title: String) -> Box<dyn FnMut(&Value) + 'a> {
    Box::new(move |state: &Value| {
        if disabled || cfg.anilist.token.is_empty() {
            return;
        }
        if !lazy_title.is_empty() && m.anilist_id == 0 {
            // looked up now, when the episode is finished, so starting playback never waits for AniList
            let (id, s, t) = native_media_mapping(cfg, &lazy_title);
            if id != 0 {
                m.anilist_id = id;
                m.season = s;
                if m.total == 0 {
                    m.total = t;
                }
            }
        }
        let n = |v: &Value| v.as_i64().unwrap_or(0);
        let or = |a: i64, b: i64| if a != 0 { a } else { b };
        let text = |k: &str| state[k].as_str().unwrap_or("").to_string();
        let outcome = anilist::push_online(
            &text("show_id"), &text("title"), &state["episode_number"], cfg,
            or(m.anilist_id, n(&state["anilist_id"])), or(m.season, n(&state["season"])), or(m.total, n(&state["total"])), None);
        if !outcome.errors.is_empty() {
            eprintln!("AniList: {}", outcome.errors.join("; "));
        } else if let Some(save) = outcome.saves.last() {
            eprintln!("AniList: episode {} -> {}", save.progress, save.status.as_deref().unwrap_or("None"));
        } else if let Some(s) = outcome.skipped.first() {
            eprintln!("AniList: {}", s.reason);
        }
    })
}

#[derive(Clone)]
pub struct Options {
    pub title: String,
    pub poster: String,
    pub dub: bool,
    pub quality: String,
    pub start: Option<f64>,
    pub anilist_id: i64,
    pub season: i64,
    pub total: i64,
    pub no_sync: bool,
    pub dry_run: bool,
    pub json_output: bool,
    pub lazy_title: String,
    pub queue_next: bool,
    /// the user agreed to a torrent after the direct stream failed
    pub allow_torrent: bool,
}
impl Default for Options {
    fn default() -> Self {
        Options { title: String::new(), poster: String::new(), dub: false, quality: String::new(), start: None, anilist_id: 0, season: 0, total: 0,
            no_sync: false, dry_run: false, json_output: false, lazy_title: String::new(), queue_next: true, allow_torrent: false }
    }
}

fn to_source(ep: &Endpoints, stream: &Value) -> Result<Source, StreamError> {
    let mut s = Source::new(stremio::stream_url(ep, stream)?);
    s.referer = stream["referer"].as_str().unwrap_or("").into();
    s.quality = stream["quality"].as_str().filter(|q| !q.is_empty()).unwrap_or("best").into();
    Ok(s)
}

/// Play one native episode; returns the process exit code. Errors are printed like the Python CLI.
pub fn native_play(cfg: &Config, provider_id: &str, episode_id: &str, o: Options) -> i32 {
    let ep = Endpoints::default();
    let is_stremio = stremio::is_show(provider_id);
    let session = if is_stremio && !o.dry_run { stremio::register_session() } else { None };
    let mut result = run(cfg, &ep, provider_id, episode_id, &o, is_stremio);
    if let Err(ProviderError(m)) = &result {
        if let Some(reason) = m.strip_prefix(DIRECT_FAILED) {
            if !o.json_output && confirm_torrent(reason) {
                result = run(cfg, &ep, provider_id, episode_id, &Options { allow_torrent: true, ..o.clone() }, is_stremio);
            }
        }
    }
    let code = match result {
        Ok(c) => c,
        Err(e) if e.0.starts_with(DIRECT_FAILED) => {
            let reason = e.0.trim_start_matches(DIRECT_FAILED).to_string();
            if o.json_output {
                // the GUI offers "play a torrent instead" and calls again with --allow-torrent
                provider_json(&json!({"ok": false, "direct_failed": true, "reason": reason, "error": format!("The direct stream failed: {reason}")}));
            } else {
                eprintln!("mediator: the direct stream failed: {reason} (rerun with --allow-torrent to use a torrent)");
            }
            3
        }
        Err(e) => {
            if o.json_output {
                provider_json(&json!({"ok": false, "error": e.0}));
                1
            } else {
                eprintln!("mediator: {}", e.0);
                1
            }
        }
    };
    stremio::unregister_session(session.as_ref());
    if is_stremio && !o.dry_run {
        stremio::schedule_stop(STOP_DELAY);
    }
    code
}

/// Ask on the terminal whether a torrent should stand in for the failed direct stream.
fn confirm_torrent(reason: &str) -> bool {
    use std::io::{BufRead, IsTerminal, Write};
    if !(std::io::stdin().is_terminal() && std::io::stderr().is_terminal()) {
        return false;
    }
    eprint!("mediator: the direct stream failed: {reason}\nPlay a torrent instead? [Y/n] ");
    let _ = std::io::stderr().flush();
    let mut line = String::new();
    std::io::stdin().lock().read_line(&mut line).is_ok() && !matches!(line.trim().to_lowercase().as_str(), "n" | "no")
}

/// A status line for GUI clients (`stream-play --json`): what the resolver is doing right now.
fn progress(o: &Options, text: &str) {
    if o.json_output && !o.dry_run {
        provider_json(&json!({"ok": true, "progress": text}));
    }
}

fn run(cfg: &Config, ep: &Endpoints, provider_id: &str, episode_id: &str, o: &Options, is_stremio: bool) -> Result<i32, ProviderError> {
    let kind = if is_stremio && provider_id.matches(':').count() >= 2 { provider_id.split(':').nth(1).unwrap_or("") } else { "" };
    let speed = cfg.speed_for(match kind { "series" => "shows", "movie" => "movies", _ => "anime" });
    let mut direct: Option<(Vec<Value>, Value, Source)> = None;
    // direct stream first with torrents behind it: tell the user instead of switching silently
    let ask = is_stremio && !o.dry_run && !o.allow_torrent && cfg.player != "syncplay" && cfg.streaming.hls && cfg.streaming.stremio
        && !cfg.streaming.prefer_stremio && cfg.streaming.ask_before_torrent;
    if is_stremio {
        progress(o, if o.allow_torrent || !cfg.streaming.hls || cfg.streaming.prefer_stremio { "Finding a torrent…" } else { "Finding a direct stream…" });
        let hand_picked = stremio::recall(provider_id, episode_id).map(|s| s["chosen"].as_bool().unwrap_or(false)).unwrap_or(false);
        let direct_only = Streaming { hls: true, prefer_stremio: false, stremio: false, ask_before_torrent: false };
        let st = if ask && !hand_picked { &direct_only } else { &cfg.streaming };
        let r = stremio::resolve(ep, provider_id, episode_id, Some(st)).map_err(|e| {
            if std::ptr::eq(st, &direct_only) { ProviderError(format!("{DIRECT_FAILED}{}", e.0)) } else { ProviderError(e.to_string()) }
        })?;
        let src = to_source(ep, &r.stream).map_err(|e| ProviderError(e.to_string()))?;
        progress(o, "Opening the player…");
        direct = Some((r.episodes, r.episode, src));
    }
    let announced = std::cell::Cell::new(false);
    let syncplay_args = if cfg.player == "syncplay" { Some(cfg.syncplay_args.clone()) } else { None };

    // a series plays as one mpv playlist: later episodes are appended while it plays
    let provider = Provider::new();
    let mut provider_eps: Vec<Value> = vec![];
    let mut queue_ids: Vec<String> = vec![];
    let mut order_ids: Vec<String> = vec![];
    if o.queue_next && (syncplay_args.is_none() || crate::native_player::syncplay_control().is_some()) && !o.dry_run {
        let ids: Vec<String> = if let (Some(d), "series") = (&direct, kind) {
            d.0.iter().filter_map(|e| e["id"].as_str().map(String::from)).collect()
        } else if !is_stremio {
            provider_eps = provider.episodes(provider_id).unwrap_or_default();
            provider_eps.iter().filter_map(|e| e["id"].as_str().map(String::from)).collect()
        } else {
            vec![]
        };
        if let Some(i) = ids.iter().position(|x| x == episode_id) {
            queue_ids = ids[i + 1..].to_vec();
            order_ids = ids.clone();
        }
    }

    let resolve_next = |eid: &str| -> Result<(Value, Source), ProviderError> {
        if !is_stremio {
            let (source, e) = provider.resolve(provider_id, eid, o.dub, &o.quality, if provider_eps.is_empty() { None } else { Some(&provider_eps) })?;
            return Ok((e, source));
        }
        let r = stremio::resolve(ep, provider_id, eid, Some(&cfg.streaming)).map_err(|e| ProviderError(e.to_string()))?;
        let src = to_source(ep, &r.stream).map_err(|e| ProviderError(e.to_string()))?;
        Ok((r.episode, src))
    };

    let play = |direct: Option<(Vec<Value>, Value, Source)>, watched: Option<Box<dyn FnMut(&Value) + '_>>| -> Result<i32, ProviderError> {
        let announce: Option<Box<dyn FnMut() + '_>> = if o.json_output && !o.dry_run {
            Some(Box::new(|| {
                // the GUI consumes this line before the long-running mpv process exits
                if !announced.get() {
                    announced.set(true);
                    println!("{}", json!({"ok": true, "started": true, "pid": std::process::id()}));
                }
            }))
        } else {
            None
        };
        Provider::new().play(provider_id, episode_id, Play {
            title: o.title.clone(), poster: o.poster.clone(), dub: o.dub,
            quality: if o.quality.is_empty() { "best".into() } else { o.quality.clone() },
            start: o.start, dry_run: o.dry_run, on_resolved: announce,
            finish_ratio: cfg.finish_ratio, finish_tail: cfg.finish_tail,
            anilist_id: o.anilist_id, season: o.season, total: o.total,
            direct, speed, on_watched: watched, syncplay: syncplay_args.clone(),
            queue: queue_ids.clone(), order: order_ids.clone(), queue_window: QUEUE_WINDOW,
            resolve_next: Some(&resolve_next), ..Play::default()
        })
    };

    let watched = if direct.is_some() { None } else {
        Some(native_sync_callback(cfg, Mapping { anilist_id: o.anilist_id, season: o.season, total: o.total }, o.no_sync, o.lazy_title.clone()))
    };
    let began = Instant::now();
    let hls_played = direct.as_ref().map(|d| !d.2.url.starts_with(&ep.server)).unwrap_or(false);
    match play(direct, watched) {
        Err(e) => {
            // a direct stream that resolved but would not open falls back to a torrent while Stremio
            // is enabled; a stream that played is never retried
            if !(is_stremio && hls_played && cfg.streaming.stremio && !o.dry_run && syncplay_args.is_none() && began.elapsed().as_secs_f64() < 45.0) {
                return Err(e);
            }
            if ask {
                return Err(ProviderError(format!("{DIRECT_FAILED}{}", e.0)));
            }
            eprintln!("mediator: the direct stream would not play ({}); trying torrents instead", e.0);
            let fallback = Streaming { hls: false, prefer_stremio: false, stremio: true, ask_before_torrent: false };
            let r = stremio::resolve(ep, provider_id, episode_id, Some(&fallback)).map_err(|e| ProviderError(e.to_string()))?;
            let mut src = Source::new(stremio::stream_url(ep, &r.stream).map_err(|e| ProviderError(e.to_string()))?);
            src.quality = r.stream["quality"].as_str().filter(|q| !q.is_empty()).unwrap_or("best").into();
            play(Some((r.episodes, r.episode, src)), None)
        }
        ok => ok,
    }
}
