//! Commands that talk to other services or to the config: posters, cache-images, meta, info, probe,
//! daemon, anilist, config, jellyfin.
use super::{die, fmt_g, kinds_of, par_map, Cmd, Ctx, CliError, Res};
use crate::anilist as al;
use crate::config;
use crate::jellyfin as jf;
use crate::notify::warn;
use crate::posters::{self, Http as _, RealHttp};
use crate::selection::pick;
use serde_json::{json, Map, Value};
use std::io::{BufRead, IsTerminal, Read, Write};

pub fn run(cmd: Cmd, ctx: &mut Ctx) -> Res {
    match cmd {
        Cmd::Posters { action, query, image, kind, refresh, verbose, json } => cmd_posters(ctx, &action, query, image, kind, refresh, verbose, json),
        Cmd::CacheImages { urls, json } => cache_images(&urls, json),
        Cmd::Meta { query, kind, cached, refresh, verbose } => meta(ctx, query, kind, cached, refresh, verbose),
        Cmd::Info { query, kind, cached, refresh, verbose } => info(ctx, query, kind, cached, refresh, verbose),
        Cmd::Probe { query, refresh, verbose } => probe(ctx, &query, refresh, verbose),
        Cmd::Daemon { action } => daemon(&action),
        Cmd::Config { action, json } => config_cmd(ctx, &action, json),
        Cmd::Jellyfin { action, url, user, json } => jellyfin(ctx, &action, url, user, json),
        Cmd::Anilist { action, query, value, limit, all, pending, fetch, dry_run, season, client_id, token_stdin, json, verbose } =>
            anilist(ctx, &action, query, value, limit, all, pending, fetch, dry_run, season, client_id, token_stdin, json, verbose),
        _ => unreachable!(),
    }
}

fn jf_client(ctx: &Ctx) -> Option<jf::Jellyfin> {
    if ctx.cfg.jellyfin.configured() { Some(jf::Jellyfin::new(&ctx.cfg.jellyfin)) } else { None }
}

#[allow(clippy::too_many_arguments)]
fn cmd_posters(ctx: &mut Ctx, action: &str, query: Option<String>, image: Option<String>, kind: Option<String>, refresh: bool, verbose: bool, json_out: bool) -> Res {
    ctx.kinds = kinds_of(&kind);
    let titles: Vec<crate::catalog::Title> = match &query {
        Some(q) => vec![pick(ctx.titles(), q)?.clone()],
        None => ctx.titles().to_vec(),
    };
    if action == "set" {
        let (Some(_), Some(image)) = (&query, &image) else { return die("usage: posters set TITLE IMAGE") };
        if titles.len() != 1 {
            return die("usage: posters set TITLE IMAGE");
        }
        let src = image.trim();
        let data = if src.starts_with("http://") || src.starts_with("https://") {
            RealHttp::new(15.0).bytes(src).map_err(|e| CliError(e.0))?
        } else {
            std::fs::read(config::expand_user(src)).map_err(|e| CliError(crate::errors::describe_io(e.kind(), &e.to_string())))?
        };
        let path = posters::store(&titles[0], &data, &posters::cache_dir()).map_err(|e| CliError(e.0))?;
        let p = path.to_string_lossy();
        println!("{}", if json_out { json!({"id": titles[0].id, "path": p}).to_string() } else { p.into_owned() });
        return Ok(0);
    }
    let mut rc = 0;
    let http = RealHttp::new(15.0);
    let client = jf_client(ctx);
    let jfp = client.as_ref().map(|c| move |id: &str| c.poster(id).map_err(|e| e.to_string()));
    for t in &titles {
        if action == "list" {
            let src = posters::source_of(t, &posters::cache_dir(), &posters::legacy_dir());
            if json_out {
                println!("{}", json!({"id": t.id, "source": src, "path": posters::find(t).map(|p| p.to_string_lossy().into_owned())}));
            } else {
                println!("{src:<7} {}", t.id);
            }
            continue;
        }
        let r = posters::fetch(t, &http, jfp.as_ref().map(|f| f as &dyn Fn(&str) -> Result<Vec<u8>, String>), &posters::FetchOpts { refresh, ..Default::default() });
        if r.status == "error" {
            rc = 1;
        }
        if r.status != "have" || verbose {
            println!("{:<8} {}{}", r.status, t.id, if r.detail.is_empty() { String::new() } else { format!("  {}", r.detail) });
        }
    }
    Ok(rc)
}

/// Persist remote provider/AniList covers so frontends do not redownload them.
fn cache_images(urls: &[String], json_out: bool) -> Res {
    let (images, errors) = posters::cache_images(urls, &RealHttp::new(15.0), &posters::cache_dir());
    if json_out {
        println!("{}", json!({"ok": errors.is_empty(), "images": images, "errors": errors}));
    } else {
        for (url, path) in &images {
            println!("{path}\t{url}");
        }
        for (url, error) in &errors {
            warn(&format!("mediator: {url}: {error}"));
        }
    }
    Ok(if errors.is_empty() { 0 } else { 1 })
}

fn report(results: Vec<(crate::catalog::Title, &'static str, Option<Value>)>, single: bool, key: &str, verbose: bool) -> Res {
    let mut rc = 0;
    for (t, status, rec) in results {
        if status == "error" {
            rc = 1;
        }
        if single {
            println!("{}", json!({"id": t.id, "status": status, key: rec}));
        } else if status != "have" || verbose {
            let err = if status == "error" { rec.as_ref().and_then(|m| m["error"].as_str()).map(|e| format!("  {e}")).unwrap_or_default() } else { String::new() };
            println!("{status:<8} {}{err}", t.id);
        }
    }
    Ok(rc)
}

/// Synopsis, rating and genres. One title prints its record as JSON (fetched when missing).
fn meta(ctx: &mut Ctx, query: Option<String>, kind: Option<String>, cached: bool, refresh: bool, verbose: bool) -> Res {
    ctx.kinds = kinds_of(&kind);
    let titles: Vec<crate::catalog::Title> = match &query { Some(q) => vec![pick(ctx.titles(), q)?.clone()], None => ctx.titles().to_vec() };
    let jfcfg = ctx.cfg.jellyfin.clone();
    let results = par_map(&titles, 4, |t| {
        if cached {
            return (t.clone(), "have", crate::meta::find(t));
        }
        let http = RealHttp::new(15.0);
        let client = if jfcfg.configured() { Some(jf::Jellyfin::new(&jfcfg)) } else { None };
        let jfi = client.as_ref().map(|c| move |id: &str| c.item(id).map_err(|e| e.to_string()));
        let (status, m) = crate::meta::fetch(t, &http, jfi.as_ref().map(|f| f as &dyn Fn(&str) -> Result<Value, String>), &crate::meta::Opts { refresh, ..Default::default() });
        (t.clone(), status, m)
    });
    report(results, query.is_some(), "meta", verbose)
}

/// Banner, description, cast, trailer, next airing and per-episode names.
fn info(ctx: &mut Ctx, query: Option<String>, kind: Option<String>, cached: bool, refresh: bool, verbose: bool) -> Res {
    ctx.kinds = kinds_of(&kind);
    let titles: Vec<crate::catalog::Title> = match &query { Some(q) => vec![pick(ctx.titles(), q)?.clone()], None => ctx.titles().to_vec() };
    let results = par_map(&titles, 3, |t| {
        if cached {
            return (t.clone(), "have", crate::info::find(t));
        }
        // one bad title must not lose the rest of the run
        let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| crate::info::fetch(t, &RealHttp::new(15.0), &crate::info::Opts { refresh, ..Default::default() })));
        match r {
            Ok((status, rec)) => (t.clone(), status, rec),
            Err(_) => (t.clone(), "error", Some(json!({"error": "internal error while fetching"}))),
        }
    });
    report(results, query.is_some(), "info", verbose)
}

/// Open each file of a title with ffprobe and remember what is in it (tracks, resolution).
fn probe(ctx: &mut Ctx, query: &str, refresh: bool, verbose: bool) -> Res {
    let t = pick(ctx.titles(), query)?.clone();
    let entries: Vec<&crate::catalog::Entry> = t.entries.iter().filter(|e| e.path.starts_with('/')).collect();
    // ffprobe spends its time waiting on the disk: a few at once, results printed in file order
    let recs = par_map(&entries, 4, |e| crate::probe::probe(&e.path, refresh, false));
    crate::probe::flush();
    let mut rc = 0;
    for (e, rec) in entries.iter().zip(recs) {
        match rec {
            None => {
                rc = 1;
                eprintln!("unreadable  {}", e.rel);
            }
            Some(r) if verbose => println!("{}: {}", e.label(), r["summary"].as_str().unwrap_or("")),
            _ => {}
        }
    }
    let n = entries.len();
    println!("{n} file{} probed", if n != 1 { "s" } else { "" });
    Ok(rc)
}

/// The live companion for shells: now playing, change events, background enrichment.
fn daemon(action: &str) -> Res {
    match action {
        "run" => Ok(crate::daemon::run()),
        "start" => Ok(crate::daemon::start()),
        _ => {
            let up = crate::daemon::running();
            println!("{}", if up { "running" } else { "stopped" });
            Ok(if up { 0 } else { 1 })
        }
    }
}

fn config_cmd(ctx: &Ctx, action: &str, json_out: bool) -> Res {
    if action == "set" {
        let raw = match std::env::var("MEDIATOR_CONFIG_PATCH").ok().filter(|v| !v.is_empty()) {
            Some(r) => r,
            None if std::io::stdin().is_terminal() => String::new(),
            None => {
                let mut s = String::new();
                let _ = std::io::stdin().read_to_string(&mut s);
                s
            }
        };
        let patch: Value = serde_json::from_str(if raw.trim().is_empty() { "{}" } else { &raw }).map_err(|e| CliError(format!("invalid JSON: {e}")))?;
        let obj = patch.as_object().filter(|o| !o.is_empty());
        let Some(obj) = obj else { return die("give a non-empty JSON object in $MEDIATOR_CONFIG_PATCH or on stdin, e.g. {\"streaming.hls\": true}") };
        let done = config::apply_settings(obj, &config::config_path())?;
        println!("{}", if json_out { json!({"saved": done}).to_string() } else { format!("saved {}", done.join(", ")) });
        return Ok(0);
    }
    let view = config::settings_view(&ctx.cfg);
    if json_out {
        println!("{view}");
    } else if let Some(o) = view.as_object() {
        for (section, vals) in o {
            if let Some(m) = vals.as_object() {
                println!("[{section}]");
                for (k, v) in m {
                    println!("  {k} = {}", py_display(v));
                }
            }
        }
    }
    Ok(0)
}

/// Python's str() of a JSON value.
fn py_display(v: &Value) -> String {
    match v {
        Value::Null => "None".into(),
        Value::Bool(b) => if *b { "True".into() } else { "False".into() },
        Value::String(s) => s.clone(),
        o => o.to_string(),
    }
}

// ---- reading from the terminal ----

fn prompt(text: &str) -> Option<String> {
    print!("{text}");
    let _ = std::io::stdout().flush();
    let mut line = String::new();
    if std::io::stdin().lock().read_line(&mut line).ok()? == 0 {
        return None;
    }
    Some(line.trim_end_matches(['\n', '\r']).to_string())
}

/// Like getpass: no echo while typing.
fn read_secret(text: &str) -> Option<String> {
    eprint!("{text}");
    let _ = std::io::stderr().flush();
    unsafe {
        let mut old: libc::termios = std::mem::zeroed();
        let tty = libc::tcgetattr(0, &mut old) == 0;
        if tty {
            let mut new = old;
            new.c_lflag &= !libc::ECHO;
            libc::tcsetattr(0, libc::TCSAFLUSH, &new);
        }
        let mut line = String::new();
        let n = std::io::stdin().lock().read_line(&mut line).ok();
        if tty {
            libc::tcsetattr(0, libc::TCSAFLUSH, &old);
            eprintln!();
        }
        if n? == 0 {
            return None;
        }
        Some(line.trim_end_matches(['\n', '\r']).to_string())
    }
}

fn open_browser(url: &str) -> bool {
    std::process::Command::new("xdg-open").arg(url).stdin(std::process::Stdio::null()).stdout(std::process::Stdio::null()).stderr(std::process::Stdio::null()).spawn().is_ok()
}

fn jellyfin(ctx: &Ctx, action: &str, url: Option<String>, user: Option<String>, json_out: bool) -> Res {
    let jfc = &ctx.cfg.jellyfin;
    if action == "login" {
        let mut url = match url {
            Some(u) => u,
            None => { let r = prompt(&format!("Server URL [{}]: ", jfc.url)).unwrap_or_default(); let r = r.trim().to_string(); if r.is_empty() { jfc.url.clone() } else { r } }
        };
        url = url.trim_end_matches('/').to_string();
        if !url.is_empty() && !url.contains("://") {
            url = format!("https://{url}");
        }
        let user = match user {
            Some(u) => u,
            None => { let r = prompt(&format!("Username [{}]: ", jfc.username)).unwrap_or_default(); let r = r.trim().to_string(); if r.is_empty() { jfc.username.clone() } else { r } }
        };
        let pw = match std::env::var("MEDIATOR_JELLYFIN_PASSWORD").ok().filter(|v| !v.is_empty()) {
            Some(p) => p,
            None => read_secret("Password: ").unwrap_or_default(),
        };
        let (token, uid) = jf::Jellyfin::authenticate(&jf::Http::new(&url, ""), &user, &pw).map_err(|e| CliError(e.0))?;
        let vals = vec![("url".to_string(), json!(url)), ("username".into(), json!(user)), ("user_id".into(), json!(uid)), ("token".into(), json!(token))];
        config::update_section("jellyfin", &vals, &config::config_path()).map_err(|e| CliError(e.to_string()))?;
        println!("logged in as {user}; saved to {}", config::config_path().display());
        return Ok(0);
    }
    if !jfc.configured() {
        if json_out {
            println!("{}", json!({"ok": false, "error": "needs a URL, an API key and a username"}));
            return Ok(1);
        }
        return die("Jellyfin is not configured; run `mediator jellyfin login`");
    }
    let client = jf::Jellyfin::new(jfc);
    let fail = |e: jf::JellyfinError| -> Res {
        if json_out {
            println!("{}", json!({"ok": false, "error": e.0}));
            return Ok(1);
        }
        die(e.0)
    };
    if action == "refresh" {
        for kind in client.kinds() {
            match client.library(kind, true, false) {
                Ok(lib) => println!("{kind:<7} {} titles", lib.titles.len()),
                Err(e) => return fail(e),
            }
        }
        return Ok(0);
    }
    let st = match client.status() {
        Ok(s) => s,
        Err(e) => return fail(e),
    };
    if json_out {
        let mut o = Map::new();
        o.insert("ok".into(), json!(true));
        o.extend(st.as_object().cloned().unwrap_or_default());
        println!("{}", Value::Object(o));
        return Ok(0);
    }
    println!("{} {} at {}", py_display(&st["server"]), py_display(&st["version"]), jfc.url);
    let names: std::collections::HashMap<String, &String> = jfc.libraries.iter().map(|(k, v)| (v.to_lowercase(), k)).collect();
    for v in st["libraries"].as_array().cloned().unwrap_or_default() {
        let name = v["name"].as_str().unwrap_or("");
        let ty = v["type"].as_str().filter(|t| !t.is_empty()).unwrap_or("-");
        let mapped = names.get(&name.to_lowercase());
        println!("  {name:<16} {ty:<10} {}", mapped.map(|m| format!("-> {m}")).unwrap_or_else(|| "(not mapped)".into()));
    }
    Ok(0)
}

fn save_json(s: &al::Save) -> Value {
    json!({"media_id": s.media_id, "progress": s.progress, "status": s.status, "season": s.season, "label": s.label, "started_at": s.started_at, "completed_at": s.completed_at})
}
fn skip_json(s: &al::Skip) -> Value {
    json!({"media_id": s.media_id, "label": s.label, "reason": s.reason})
}

fn save_and_report(token: &str, explicit_client_id: &str, json_out: bool) -> Res {
    let viewer = al::verify(token, None).map_err(|e| CliError(e.message))?;
    let uid = viewer["id"].as_i64().unwrap_or(0);
    let mut vals = vec![("token".to_string(), json!(token)), ("user_id".into(), json!(uid)), ("username".into(), json!(viewer["name"].as_str().unwrap_or("")))];
    if !explicit_client_id.is_empty() {
        vals.push(("client_id".into(), json!(explicit_client_id)));
    }
    let path = config::config_path();
    config::update_section("anilist", &vals, &path).map_err(|e| CliError(e.to_string()))?;
    let name = viewer["name"].as_str().unwrap_or("None");
    if json_out {
        println!("{}", json!({"ok": true, "username": viewer["name"], "user_id": uid, "config": path.to_string_lossy()}));
    } else {
        println!("logged in as {name} (id {uid}); saved to {}", path.display());
    }
    Ok(0)
}

#[allow(clippy::too_many_arguments)]
fn anilist(ctx: &mut Ctx, action: &str, query: Option<String>, value: Option<String>, limit: i64, all: bool, pending: bool, fetch: bool, dry_run: bool, season: Option<i64>,
           client_id: Option<String>, token_stdin: bool, json_out: bool, verbose: bool) -> Res {
    let conf = ctx.cfg.anilist.clone();
    match action {
        "login" => {
            if let Some(c) = client_id.as_deref().filter(|c| !c.trim().chars().all(|x| x.is_ascii_digit()) || c.trim().is_empty()) {
                let _ = c;
                return die("an AniList client id is numeric");
            }
            if token_stdin || !std::io::stdin().is_terminal() {
                let mut line = String::new();
                let _ = std::io::stdin().lock().read_line(&mut line);
                let token = al::token_from_input(&line);
                if !token.is_empty() {
                    return save_and_report(&token, client_id.as_deref().unwrap_or(""), json_out);
                }
                if token_stdin {
                    return die("no token on stdin");
                }
            }
            let mut cid = client_id.clone().filter(|c| !c.is_empty()).unwrap_or_else(|| if conf.client_id.is_empty() { al::DEFAULT_CLIENT_ID.to_string() } else { conf.client_id.clone() }).trim().to_string();
            if cid.is_empty() {
                println!("AniList needs a registered app so the consent page names mediator, not another tool.");
                println!("One-time setup:");
                println!("  1. Sign in at https://anilist.co/settings/developer");
                println!("  2. Create a client named 'mediator'");
                println!("  3. Set its Redirect URL to {}", al::PIN_REDIRECT);
                println!("  4. Paste its Client ID here (the secret is not needed).");
                println!("Developer settings: https://anilist.co/settings/developer");
                open_browser("https://anilist.co/settings/developer");
                let Some(c) = prompt("Client ID: ") else {
                    eprintln!();
                    return Ok(1);
                };
                cid = c.trim().to_string();
                if cid.is_empty() {
                    return die("no client id given");
                }
                if !cid.chars().all(|c| c.is_ascii_digit()) {
                    return die("an AniList client id is numeric");
                }
                config::update_section("anilist", &[("client_id".to_string(), json!(cid))], &config::config_path()).map_err(|e| CliError(e.to_string()))?;
                println!("Saved. The consent page will now name your app (mediator).");
            }
            let url = al::auth_url(&cid)?;
            println!("Opening AniList in your browser. Authorize, then paste the token from the address bar.");
            if !open_browser(&url) {
                println!("Open this URL manually:\n{url}");
            } else {
                println!("{url}");
            }
            let Some(raw) = read_secret("AniList token (or pasted URL): ") else { return Ok(1) };
            let token = al::token_from_input(&raw);
            if token.is_empty() {
                return die("no token given");
            }
            save_and_report(&token, client_id.as_deref().unwrap_or(""), json_out)
        }
        "logout" => {
            let vals = vec![("token".to_string(), json!("")), ("user_id".into(), json!(0)), ("username".into(), json!(""))];
            config::update_section("anilist", &vals, &config::config_path()).map_err(|e| CliError(e.to_string()))?;
            println!("{}", if json_out { json!({"ok": true}).to_string() } else { "logged out of AniList".to_string() });
            Ok(0)
        }
        "status" => {
            let cid = if conf.client_id.is_empty() { al::DEFAULT_CLIENT_ID.to_string() } else { conf.client_id.clone() };
            let cid = cid.trim().to_string();
            let mut out = Map::new();
            out.insert("configured".into(), json!(conf.configured()));
            out.insert("username".into(), json!(conf.username));
            out.insert("user_id".into(), json!(conf.user_id));
            out.insert("client_id".into(), json!(cid));
            out.insert("auth_url".into(), json!(if cid.is_empty() { String::new() } else { al::auth_url(&cid).unwrap_or_default() }));
            for (k, v) in [("auto", conf.auto), ("add_missing", conf.add_missing), ("rewatch", conf.rewatch), ("complete", conf.complete), ("dates", conf.dates)] {
                out.insert(k.into(), json!(v));
            }
            out.insert("pending".into(), json!(al::pending_count()));
            if conf.configured() {
                match al::verify(&conf.token, None) {
                    Ok(v) => {
                        out.insert("ok".into(), json!(true));
                        out.insert("username".into(), v["name"].clone());
                        out.insert("user_id".into(), json!(v["id"].as_i64().unwrap_or(0)));
                    }
                    Err(e) => {
                        out.insert("ok".into(), json!(false));
                        out.insert("error".into(), json!(e.message));
                    }
                }
            } else {
                out.insert("ok".into(), json!(false));
                out.insert("error".into(), json!("not logged in (run `mediator anilist login`)"));
            }
            let ok = out["ok"] == json!(true);
            if json_out {
                println!("{}", Value::Object(out.clone()));
            } else if ok {
                println!("AniList: {} (id {})\nauto={} add_missing={} rewatch={} complete={} dates={} pending={}", py_display(&out["username"]), out["user_id"],
                    py(conf.auto), py(conf.add_missing), py(conf.rewatch), py(conf.complete), py(conf.dates), out["pending"]);
            } else {
                warn(&format!("mediator: AniList {}", py_display(&out["error"])));
            }
            Ok(if ok { 0 } else { 1 })
        }
        "watching" => {
            if !conf.configured() {
                return die("not logged in (run `mediator anilist login`)");
            }
            match al::Client::new(&conf.token, conf.user_id).watching(limit) {
                Err(e) => {
                    if json_out {
                        println!("{}", json!({"ok": false, "error": e.message}));
                        return Ok(1);
                    }
                    die(e.message)
                }
                Ok(entries) => {
                    if json_out {
                        println!("{}", json!({"ok": true, "entries": entries}));
                    } else {
                        for e in &entries {
                            let total = if e["total"].as_i64().unwrap_or(0) != 0 { e["total"].to_string() } else { "?".into() };
                            println!("{}\t{}/{}\t{}", py_display(&e["title"]), e["progress"], total, py_display(&e["status"]));
                        }
                    }
                    Ok(0)
                }
            }
        }
        "score" | "set" => {
            if !conf.configured() {
                return die("not logged in (run `mediator anilist login`)");
            }
            let (Some(q), Some(v)) = (query.as_deref().filter(|q| !q.is_empty()), value.as_deref()) else {
                return die(if action == "score" { "`anilist score` needs a title and a score" } else { "`anilist set` needs a title and a status" });
            };
            let http = RealHttp::new(15.0);
            if action == "score" {
                let value: f64 = v.trim().parse().map_err(|_| CliError("the score must be a number".into()))?;
                let t = pick(ctx.titles(), q)?.clone();
                let res = al::score_title(&t, ctx.state(), &ctx.cfg, value, season, None, Some(&http), dry_run, None);
                if !res.errors.is_empty() {
                    for e in &res.errors {
                        warn(&format!("mediator: {}: {e}", t.display()));
                    }
                    return Ok(1);
                }
                if json_out {
                    println!("{}", json!({"title_id": res.title_id, "media_id": res.media_id, "season": res.season, "label": res.label, "value": res.value, "raw": res.raw,
                        "score_format": res.score_format, "old_score": res.old_score, "dry_run": res.dry_run, "errors": res.errors}));
                } else if res.value == Some(0.0) {
                    println!("{}: {} {} the score", t.display(), res.label, if res.dry_run { "would clear" } else { "cleared" });
                } else {
                    let maximum = al::score_format(&res.score_format).0;
                    println!("{}: {} {} score {}/{} ({})", t.display(), res.label, if res.dry_run { "would set" } else { "set" }, fmt_g(res.value.unwrap_or(0.0)), fmt_g(maximum), res.score_format);
                }
                return Ok(0);
            }
            let t = pick(ctx.titles(), q)?.clone();
            let r = al::set_status_title(&t, ctx.state(), &ctx.cfg, v, season, None, Some(&http), dry_run, None);
            if !r.errors.is_empty() {
                for e in &r.errors {
                    warn(&format!("mediator: {}: {e}", t.display()));
                }
                return Ok(1);
            }
            if json_out {
                println!("{}", json!({"title_id": r.title_id, "media_id": r.media_id, "season": r.season, "label": r.label, "status": r.status, "previous": r.previous, "dry_run": r.dry_run, "errors": r.errors}));
            } else {
                let was = r.previous.as_ref().map(|p| format!(" (was {p})")).unwrap_or_default();
                println!("{}: {} {} status {}{was}", t.display(), r.label, if r.dry_run { "would set" } else { "set" }, r.status);
            }
            Ok(0)
        }
        _ => sync(ctx, query, all, pending, fetch, dry_run, json_out, verbose),
    }
}

fn py(b: bool) -> &'static str {
    if b { "True" } else { "False" }
}

#[allow(clippy::too_many_arguments)]
fn sync(ctx: &mut Ctx, query: Option<String>, all: bool, pending: bool, fetch: bool, dry_run: bool, json_out: bool, verbose: bool) -> Res {
    let conf = ctx.cfg.anilist.clone();
    if !conf.configured() {
        let msg = "not logged in (run `mediator anilist login`)";
        if json_out {
            println!("{}", json!({"error": msg}));
            return Ok(1);
        }
        return die(msg);
    }
    let query = query.filter(|q| !q.is_empty());
    if pending && (query.is_some() || all) {
        return die("--pending cannot be combined with a title or --all");
    }
    if query.is_some() && all {
        return die("give a title or --all, not both");
    }
    let titles: Vec<crate::catalog::Title> = if pending {
        let wanted: std::collections::BTreeSet<String> = al::pending_ids().into_iter().collect();
        ctx.kinds = Some(vec!["anime".into()]);
        let found: Vec<_> = ctx.titles().iter().filter(|t| wanted.contains(&t.id)).cloned().collect();
        for missing in wanted.iter().filter(|w| !found.iter().any(|t| &t.id == *w)) {
            al::clear_pending(missing);
        }
        if found.is_empty() {
            println!("{}", if json_out { "[]".to_string() } else { "nothing pending".to_string() });
            return Ok(0);
        }
        found
    } else if let Some(q) = &query {
        vec![pick(ctx.titles(), q)?.clone()]
    } else if all {
        ctx.kinds = Some(vec!["anime".into()]);
        ctx.titles().iter().filter(|t| t.lib == "anime" && t.source == "local").cloned().collect()
    } else {
        return die("`anilist sync` needs a title, --all or --pending");
    };
    let (mut rows, mut rc, mut changed) = (vec![], 0, 0);
    let batch = all || pending;
    let (mut client, mut states) = (None, None);
    if batch {
        let c = al::Client::new(&conf.token, conf.user_id);
        match c.entries(conf.user_id, &conf.username) {
            Ok(s) => states = Some(s),
            Err(e) => warn(&format!("mediator: could not read your AniList list ({}); checking titles one by one", e.message)),
        }
        client = Some(c);
    }
    let http = RealHttp::new(15.0);
    for t in &titles {
        let outcome = al::sync_title(t, ctx.state(), &ctx.cfg, None, if fetch || query.is_some() { Some(&http) } else { None }, dry_run, client.as_ref(), states.as_ref(), !batch, None);
        if !dry_run {
            if !outcome.errors.is_empty() {
                al::mark_pending(&t.id, &outcome.errors.join("; "));
            } else if outcome.skipped.iter().any(|s| s.reason.contains("no AniList info")) {
                al::mark_pending(&t.id, "no AniList info cached");
            } else {
                al::clear_pending(&t.id);
            }
        }
        rows.push(json!({"id": t.id, "title": t.display(), "dry_run": outcome.dry_run, "saves": outcome.saves.iter().map(save_json).collect::<Vec<_>>(),
            "skipped": outcome.skipped.iter().map(skip_json).collect::<Vec<_>>(), "errors": outcome.errors}));
        if !outcome.saves.is_empty() {
            changed += 1;
        }
        if !outcome.errors.is_empty() {
            rc = 1;
            for e in &outcome.errors {
                warn(&format!("mediator: {}: {e}", t.display()));
            }
        }
        if !json_out {
            for s in &outcome.saves {
                let status = s.status.as_ref().map(|x| format!(" ({x})")).unwrap_or_default();
                println!("{}: {} {} episode {}{status}", t.display(), s.label, if dry_run { "would set" } else { "set" }, s.progress);
            }
            if verbose {
                for sk in &outcome.skipped {
                    let place = if sk.label.is_empty() { t.display() } else { format!("{} · {}", t.display(), sk.label) };
                    println!("{place}: skipped — {}", sk.reason);
                }
            }
        }
    }
    if json_out {
        println!("{}", Value::Array(rows));
    } else if changed == 0 && !verbose {
        println!("nothing to update");
    } else if changed > 0 {
        eprintln!("{} {changed} title{}", if dry_run { "would update" } else { "updated" }, if changed != 1 { "s" } else { "" });
    }
    Ok(rc)
}
