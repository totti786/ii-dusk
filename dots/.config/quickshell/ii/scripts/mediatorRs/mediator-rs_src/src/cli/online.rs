//! The `stream-*`, `stremio` and `stream` commands: native streaming from the command line
//! (port of `mediator/cli_stream.py`).
use super::{die, fmt_g, Cmd, Ctx, Res, StremioCmd};
use crate::anime_provider::{Provider, ProviderError};
use crate::native_play::{native_play, provider_json, Options};
use crate::{anilist, native_progress as np, stremio};
use serde_json::{json, Value};
use std::io::Write;

pub fn run(cmd: Cmd, ctx: &mut Ctx) -> Res {
    match cmd {
        Cmd::Stream { query, search, episode, season, dub, quality, skip, select, no_sync, dry_run } => stream(ctx, &query, search, episode, season, dub, quality.unwrap_or_default(), skip, select, no_sync, dry_run),
        Cmd::StreamSearch { query, f } => search(&query, f.json),
        Cmd::StreamEpisodes { provider_id, f } => episodes(&provider_id, f.json, f.tsv),
        Cmd::StreamResolve { provider_id, episode_id, dub, quality } => resolve(ctx, &provider_id, &episode_id, dub, &quality),
        Cmd::StreamControl { pid, action, value, json } => control(pid, &action, value, json),
        Cmd::StreamState { all, shows, f } => state(all, shows, f.json),
        Cmd::StreamForget { show_id, f } => forget(&show_id, f.json),
        Cmd::StreamPlay { provider_id, episode_id, title, poster, dub, quality, start, anilist_id, season, total, single, no_sync, dry_run, json, allow_torrent } =>
            stream_play(ctx, provider_id, episode_id, title, poster, dub, quality, start, anilist_id, season, total, single, no_sync, dry_run, json, allow_torrent),
        Cmd::StreamResume { no_sync, dry_run, json, single } => resume(ctx, no_sync, dry_run, json, single),
        Cmd::StreamSync { all, json } => sync(ctx, all, json),
        Cmd::StreamCheckpoint { show_id, episode_id, position, duration, eof, json } => checkpoint(ctx, &show_id, &episode_id, position, duration, eof, json),
        Cmd::Stremio { cmd } => match cmd {
            StremioCmd::Stop { json, delay, if_idle } => stremio_stop(json, delay, if_idle),
            StremioCmd::Status { json } => stremio_status(json),
            StremioCmd::Search { query } => browse_out(crate::browse::search(&query.join(" "))),
            StremioCmd::Top { kind } => browse_out(crate::browse::top(&kind)),
            StremioCmd::Browse { kind, sort, filter, skip } => browse_out(crate::browse::browse(&kind, &sort, &filter, skip)),
            StremioCmd::Meta { kind, id } => browse_out(crate::browse::meta(&kind, &id)),
            StremioCmd::Streams { kind, id } => browse_out(crate::browse::streams(&kind, &id)),
            StremioCmd::Choose { json } => browse_out(serde_json::from_str(&json).map_err(|e| format!("bad JSON: {e}")).and_then(|v| crate::browse::choose(&v))),
        },
        Cmd::Download { action, args } => {
            let json_arg = || args.first().ok_or_else(|| "this needs a JSON argument".to_string()).and_then(|a| serde_json::from_str::<serde_json::Value>(a).map_err(|e| format!("bad JSON: {e}")));
            match action.as_str() {
                "status" => browse_out(crate::download::status()),
                "finalize" => {
                    let pick = args.get(1).and_then(|p| p.parse().ok()).unwrap_or(-1);
                    crate::download::finalize(args.first().map(String::as_str).unwrap_or(""), pick);
                    Ok(0)
                }
                "add" => browse_out(json_arg().and_then(|a| crate::download::add(&ctx.cfg, &a))),
                "auto" => browse_out(json_arg().and_then(|a| crate::download::auto(&ctx.cfg, &a))),
                "hls" => browse_out(json_arg().and_then(|a| crate::download::hls(&ctx.cfg, &a))),
                "batch" => browse_out(json_arg().and_then(|a| crate::download::batch(&ctx.cfg, &a))),
                "anime-episode" => browse_out(crate::download::anime_episode(&ctx.cfg, args.first().map(String::as_str).unwrap_or(""))),
                "anime-season" => browse_out(crate::download::anime_season(args.first().map(String::as_str).unwrap_or(""))),
                "anime-feed" => {
                    crate::download::anime_feed(&ctx.cfg, args.first().map(String::as_str).unwrap_or(""));
                    Ok(0)
                }
                "anime-status" => browse_out(crate::download::anime_status(&ctx.cfg, args.first().map(String::as_str).unwrap_or(""))),
                _ => browse_out(crate::download::anime_cancel(args.first().map(String::as_str).unwrap_or(""))),
            }
        }
        Cmd::AnimeBrowse { mode, arg } => browse_out(crate::browse::anime(&mode, &arg.join(" "))),
        _ => unreachable!(),
    }
}

/// One JSON value on stdout; a failure is `{"error": ...}` and still exits 0, as the interface expects.
fn browse_out(r: Result<serde_json::Value, String>) -> Res {
    let v = r.unwrap_or_else(|e| serde_json::json!({"error": e}));
    println!("{v}");
    Ok(0)
}

/// Stream one episode through ani-cli, tracking and syncing it to AniList.
#[allow(clippy::too_many_arguments)]
fn stream(ctx: &mut Ctx, query: &str, search: bool, episode: Option<i64>, season: Option<i64>, dub: bool, quality: String, skip: bool, select: Option<i64>, no_sync: bool, dry_run: bool) -> Res {
    if search {
        return Ok(crate::stream::run_search(query, episode, dub, &quality, skip, select, dry_run, None)?);
    }
    let t = crate::selection::pick(ctx.titles(), query)?.clone();
    let o = crate::stream::Options { season, episode, dub, quality, skip, select, no_sync, dry_run, terminal: None };
    Ok(crate::stream::run(&t, ctx.state(), &ctx.cfg, &o)?)
}

fn search(query: &str, json_out: bool) -> Res {
    match Provider::new().search(query) {
        Err(ProviderError(e)) => {
            if json_out {
                provider_json(&json!({"ok": false, "error": e, "results": []}));
                return Ok(1);
            }
            die(e)
        }
        Ok(results) => {
            if json_out {
                provider_json(&json!({"ok": true, "query": query, "results": results}));
            } else {
                for r in &results {
                    println!("{}\t{}", s(&r["id"]), s(&r["title"]));
                }
            }
            Ok(0)
        }
    }
}

/// Python's str() of a JSON value in a row.
fn s(v: &Value) -> String {
    match v { Value::String(x) => x.clone(), Value::Null => "None".into(), o => o.to_string() }
}

fn episodes(provider_id: &str, json_out: bool, tsv: bool) -> Res {
    match Provider::new().episodes(provider_id) {
        Err(ProviderError(e)) => {
            if json_out {
                provider_json(&json!({"ok": false, "error": e, "episodes": []}));
                return Ok(1);
            }
            die(e)
        }
        Ok(eps) => {
            if json_out {
                provider_json(&json!({"ok": true, "id": provider_id, "episodes": eps}));
            } else if tsv {
                for e in &eps {
                    println!("{}\t{}\t{}", s(&e["id"]), s(&e["number"]), s(&e["title"]));
                }
            } else {
                for e in &eps {
                    println!("{}\t{}\t{}", s(&e["number"]), s(&e["title"]), s(&e["id"]));
                }
            }
            Ok(0)
        }
    }
}

/// Resolve one episode to a playable URL without starting a player (downloaders use this).
fn resolve(ctx: &Ctx, provider_id: &str, episode_id: &str, dub: bool, quality: &str) -> Res {
    let run = || -> Result<Value, ProviderError> {
        if stremio::is_show(provider_id) {
            // movies and series: the direct HLS stream (torrents are downloaded by qBittorrent)
            if !ctx.cfg.streaming.hls {
                return Err(ProviderError("direct streams are turned off in the settings".into()));
            }
            let stream = stremio::hls_stream(&stremio::Endpoints::default(), provider_id, episode_id, true).map_err(|e| ProviderError(e.to_string()))?;
            return Ok(json!({"ok": true, "url": stream["url"], "referer": stream["referer"].as_str().unwrap_or(""), "subtitles": "",
                "quality": stream["quality"].as_str().filter(|q| !q.is_empty()).unwrap_or("hls"), "episode": {"id": episode_id}}));
        }
        let provider = Provider::new();
        let eps = provider.episodes(provider_id)?;
        let (source, episode) = provider.resolve(provider_id, episode_id, dub, quality, Some(&eps))?;
        Ok(json!({"ok": true, "url": source.url, "referer": source.referer, "subtitles": source.subtitles, "quality": source.quality, "episode": episode}))
    };
    match run() {
        Ok(v) => {
            provider_json(&v);
            Ok(0)
        }
        Err(ProviderError(e)) => {
            provider_json(&json!({"ok": false, "error": e}));
            Ok(1)
        }
    }
}

/// Control one explicitly identified Mediator socket, without daemon discovery delay.
fn control(pid: i64, action: &str, value: Option<f64>, json_out: bool) -> Res {
    let mut command: Option<Vec<Value>> = match action {
        "stop" => Some(vec![json!("quit")]),
        "toggle" => Some(vec![json!("cycle"), json!("pause")]),
        "pause" => Some(vec![json!("set_property"), json!("pause"), json!(true)]),
        "play" => Some(vec![json!("set_property"), json!("pause"), json!(false)]),
        _ => None,
    };
    if action == "seek_to" {
        if let Some(v) = value.filter(|v| v.is_finite()) {
            command = Some(vec![json!("seek"), json!(v.max(0.0)), json!("absolute")]);
        }
    }
    let Some(command) = command.filter(|_| pid > 0) else { return die("invalid native player control") };
    let path = format!("{}/mediator-{pid}.sock", std::env::var("XDG_RUNTIME_DIR").ok().filter(|v| !v.is_empty()).unwrap_or_else(|| "/tmp".into()));
    let sent = (|| -> std::io::Result<()> {
        let mut c = std::os::unix::net::UnixStream::connect(&path)?;
        c.set_write_timeout(Some(std::time::Duration::from_secs(2)))?;
        c.write_all(format!("{}\n", json!({"command": command})).as_bytes())
    })();
    if let Err(e) = sent {
        let msg = crate::errors::describe_io(e.kind(), &e.to_string());
        if json_out {
            provider_json(&json!({"ok": false, "error": msg}));
            return Ok(1);
        }
        return die(format!("could not control native player: {msg}"));
    }
    if json_out {
        provider_json(&json!({"ok": true}));
    }
    Ok(0)
}

fn num(v: &Value) -> f64 {
    v.as_f64().unwrap_or(0.0)
}
fn text<'a>(state: &'a Value, k: &str, fallback: &'a str) -> String {
    match state.get(k) { Some(Value::String(x)) if !x.is_empty() => x.clone(), Some(Value::Null) | None => fallback.to_string(), Some(Value::String(_)) => fallback.to_string(), Some(o) => s(o) }
}

/// Read the cached native provider session without fetching the provider.
fn state(all: bool, shows: bool, json_out: bool) -> Res {
    if all {
        let recent = if shows { np::recent_shows(25) } else { np::recent(25) };
        if json_out {
            provider_json(&json!({"ok": true, "recent": recent}));
        } else {
            for st in &recent {
                let mark = if st["watched"].as_bool().unwrap_or(false) { "watched" } else { "resume" };
                println!("{}\t{}\t{}\t{}/{}\t{}", text(st, "title", &text(st, "show_id", "")), text(st, "episode_number", ""), text(st, "episode_title", ""), fmt_g(num(&st["position"])), fmt_g(num(&st["duration"])), mark);
            }
        }
        return Ok(0);
    }
    let payload = np::json_state();
    if json_out {
        provider_json(&payload);
    } else {
        let st = &payload["state"];
        if np::is_empty(st) || st.as_object().map(|o| o.is_empty()).unwrap_or(true) {
            return Ok(0);
        }
        println!("{}\t{}\t{}\t{}/{}", text(st, "title", &text(st, "show_id", "")), text(st, "episode_number", ""), text(st, "episode_title", ""), fmt_g(num(&st["position"])), fmt_g(num(&st["duration"])));
    }
    Ok(0)
}

fn forget(show_ids: &[String], json_out: bool) -> Res {
    let removed: usize = show_ids.iter().map(|s| np::forget(s)).sum();
    if json_out {
        provider_json(&json!({"ok": true, "removed": removed}));
    } else {
        println!("{removed}");
    }
    Ok(0)
}

#[allow(clippy::too_many_arguments)]
fn stream_play(ctx: &mut Ctx, provider_id: String, episode_id: String, title: String, poster: String, dub: bool, quality: String, start: Option<f64>, anilist_id: Option<i64>, season: Option<i64>, total: Option<i64>, single: bool, mut no_sync: bool, dry_run: bool, json_out: bool, allow_torrent: bool) -> Res {
    let anilist_id = anilist_id.unwrap_or(0);
    let mut season = season;
    let total = total.unwrap_or(0);
    let mut lazy_title = String::new();
    if stremio::is_show(&provider_id) {
        no_sync = true; // AniList only knows anime provider ids
        season = Some(season.unwrap_or(0));
    } else if !no_sync && !ctx.cfg.anilist.token.is_empty() && anilist_id == 0 {
        lazy_title = title.clone(); // mapped when the episode finishes, not before it starts
        if season.is_none() {
            season = Some(1);
        }
    } else if season.is_none() {
        season = Some(if anilist_id != 0 || no_sync { 1 } else { 0 });
    }
    Ok(native_play(&ctx.cfg, &provider_id, &episode_id, Options {
        title, poster, dub, quality: if quality.is_empty() { "best".into() } else { quality }, start, anilist_id, season: season.unwrap_or(0), total,
        no_sync, dry_run, json_output: json_out, lazy_title, queue_next: !single, allow_torrent,
    }))
}

fn int_of(v: &Value) -> i64 {
    v.as_i64().or_else(|| v.as_f64().map(|f| f as i64)).or_else(|| v.as_str().and_then(|x| x.trim().parse().ok())).unwrap_or(0)
}
fn str_of(v: &Value) -> String {
    match v { Value::Null => String::new(), Value::String(x) => x.clone(), o => o.to_string() }
}

/// Continue the last native stream, or its next episode.
fn resume(ctx: &mut Ctx, no_sync: bool, dry_run: bool, json_out: bool, single: bool) -> Res {
    let state = np::load();
    if np::is_empty(&state) {
        return die("no native stream to resume");
    }
    let sock = state["session"].as_object().and_then(|s| s.get("socket")).map(str_of).unwrap_or_default();
    if !sock.is_empty() && std::path::Path::new(&sock).exists() {
        return die("that native stream is already playing");
    }
    let mut episode_id = str_of(&state["episode_id"]);
    if state["watched"].as_bool().unwrap_or(false) {
        match np::next_episode(Some(&state)) {
            Some(f) => episode_id = str_of(&f["id"]),
            None => return die("no next episode in the remembered list"),
        }
    }
    if episode_id.is_empty() {
        return die("no episode to resume");
    }
    let q = str_of(&state["quality"]);
    Ok(native_play(&ctx.cfg, &str_of(&state["show_id"]), &episode_id, Options {
        title: str_of(&state["title"]), poster: str_of(&state["poster"]), dub: state["dub"].as_bool().unwrap_or(false), quality: if q.is_empty() { "best".into() } else { q },
        start: None, anilist_id: int_of(&state["anilist_id"]), season: int_of(&state["season"]), total: int_of(&state["total"]),
        no_sync, dry_run, json_output: json_out, queue_next: !single, ..Options::default()
    }))
}

fn save_json(s: &anilist::Save) -> Value {
    json!({"media_id": s.media_id, "progress": s.progress, "status": s.status, "season": s.season, "label": s.label, "started_at": s.started_at, "completed_at": s.completed_at})
}
fn skip_json(s: &anilist::Skip) -> Value {
    json!({"media_id": s.media_id, "label": s.label, "reason": s.reason})
}

/// Retry AniList for watched native episodes whose push failed.
fn sync(ctx: &mut Ctx, all: bool, json_out: bool) -> Res {
    let states: Vec<Value> = if all { np::recent(25) } else { vec![np::load()] };
    let states: Vec<Value> = states.into_iter().filter(|s| !np::is_empty(s) && s["watched"].as_bool().unwrap_or(false)).collect();
    let (mut rows, mut rc) = (vec![], 0);
    for st in &states {
        let outcome = anilist::push_online(&str_of(&st["show_id"]), &str_of(&st["title"]), &st["episode_number"], &ctx.cfg, int_of(&st["anilist_id"]), int_of(&st["season"]), int_of(&st["total"]), None);
        let name = { let t = str_of(&st["title"]); if t.is_empty() { str_of(&st["show_id"]) } else { t } };
        rows.push(json!({"id": format!("online/{}", str_of(&st["show_id"])), "title": str_of(&st["title"]), "episode": st["episode_number"].clone(),
            "saves": outcome.saves.iter().map(save_json).collect::<Vec<_>>(), "skipped": outcome.skipped.iter().map(skip_json).collect::<Vec<_>>(), "errors": outcome.errors}));
        if !outcome.errors.is_empty() {
            rc = 1;
            for e in &outcome.errors {
                crate::notify::warn(&format!("mediator: {name}: {e}"));
            }
        }
        if !json_out {
            for sv in &outcome.saves {
                println!("{name}: episode {} -> {} ({})", str_of(&st["episode_number"]), sv.progress, sv.status.as_deref().unwrap_or("None"));
            }
            if outcome.saves.is_empty() {
                for sk in &outcome.skipped {
                    println!("{name}: skipped — {}", sk.reason);
                }
            }
        }
    }
    if json_out {
        println!("{}", Value::Array(rows));
    } else if states.is_empty() {
        println!("nothing watched to sync");
    }
    Ok(rc)
}

/// Persist a position adopted through MPRIS when the worker is gone (shell reload).
fn checkpoint(ctx: &Ctx, show_id: &str, episode_id: &str, position: f64, duration: f64, eof: bool, json_out: bool) -> Res {
    let st = np::checkpoint(show_id, episode_id, position, duration, eof, ctx.cfg.finish_ratio, ctx.cfg.finish_tail);
    if np::is_empty(&st) || st.as_object().map(|o| o.is_empty()).unwrap_or(true) {
        if json_out {
            provider_json(&json!({"ok": false, "error": "no matching native episode"}));
        }
        return Ok(1);
    }
    if json_out {
        provider_json(&json!({"ok": true, "state": st}));
    }
    Ok(0)
}

fn stremio_stop(json_out: bool, delay: f64, if_idle: bool) -> Res {
    if delay > 0.0 {
        std::thread::sleep(std::time::Duration::from_secs_f64(delay));
    }
    if if_idle {
        let sessions = stremio::active_sessions();
        if !sessions.is_empty() {
            if json_out {
                provider_json(&json!({"ok": true, "stopped": false, "reason": "in use", "sessions": sessions}));
            } else {
                println!("in use (pid {})", sessions.iter().map(|p| p.to_string()).collect::<Vec<_>>().join(", "));
            }
            return Ok(0);
        }
    }
    let result = stremio::stop_server();
    if json_out {
        provider_json(&result);
    } else if result["stopped"].as_bool().unwrap_or(false) {
        println!("stopped");
    } else if result["port_open"].as_bool().unwrap_or(false) {
        println!("port 11470 is still in use");
    } else {
        println!("not running");
    }
    Ok(if result["ok"].as_bool().unwrap_or(false) && !result["port_open"].as_bool().unwrap_or(false) { 0 } else { 1 })
}

fn stremio_status(json_out: bool) -> Res {
    let r = stremio::server_status();
    if json_out {
        provider_json(&r);
    } else if r["running"].as_bool().unwrap_or(false) {
        let pids: Vec<String> = r["pids"].as_array().cloned().unwrap_or_default().iter().map(s).collect();
        println!("running (pid {})", pids.join(", "));
    } else if r["port"].as_bool().unwrap_or(false) {
        println!("port 11470 is in use");
    } else {
        println!("stopped");
    }
    Ok(0)
}
