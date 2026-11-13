//! Glue between catalog, saved progress and the player (port of `mediator/session.py`).
use crate::anilist;
use crate::catalog::{Entry, Title};
use crate::config::Config;
use crate::jellyfin as jf;
use crate::player::{self, FileResult};
use crate::resume::MIN_RESUME;
use crate::state::{finished, State};
use std::collections::HashMap;

/// Play `queue` in mpv and record progress for every file as it ends. `Err` is a message for
/// `mediator: …` on stderr.
pub fn play_queue(title: &Title, queue: &[Entry], start: f64, state: &State, cfg: &Config, terminal: Option<bool>, sock_path: Option<String>) -> Result<i32, String> {
    let mut extra = cfg.mpv_args.clone();
    let mut auth_file: Option<std::path::PathBuf> = None;
    let client: Option<jf::Jellyfin>;
    let reporter: Option<jf::Reporter>;
    if title.source == "jellyfin" {
        if !cfg.jellyfin.configured() {
            return Err("Jellyfin is not configured (see `mediator jellyfin login`)".into());
        }
        let path = jf::write_mpv_auth(&cfg.jellyfin.token).map_err(|e| format!("could not write the Jellyfin auth file: {e}"))?;
        extra.push(format!("--include={}", path.display()));
        auth_file = Some(path);
        client = Some(jf::Jellyfin::with_http(&cfg.jellyfin, Box::new(jf::Http::new(&cfg.jellyfin.url, &cfg.jellyfin.token).with_timeout(4.0)), jf::cache_dir(), Box::new(crate::state::now)));
        reporter = client.as_ref().map(|c| jf::Reporter::new(c, queue));
    } else {
        client = None;
        reporter = None;
    }
    let _ = &client;

    let by_path: HashMap<&str, &Entry> = queue.iter().map(|e| (e.path.as_str(), e)).collect();
    let sink = |r: FileResult| {
        let Some(e) = by_path.get(r.path.as_str()) else { return };
        let watched = finished(r.position, r.duration, r.eof, cfg.finish_ratio, cfg.finish_tail);
        let pos = if watched { 0.0 } else if r.position >= MIN_RESUME { r.position } else { 0.0 };
        let _ = state.put(&e.path, &title.id, pos, r.duration, watched, e.size, &e.label(), None);
        if let Some(rep) = &reporter {
            rep.report(&e.path, pos, r.duration, watched);
        }
        if watched {
            anilist::schedule(title, cfg);
        }
    };

    let titles: HashMap<String, String> = queue.iter().map(|e| (e.path.clone(), if title.lib == "movies" { title.display() } else { format!("{} · {}", title.display(), e.label()) })).collect();
    let syncing = cfg.player == "syncplay";
    let result = player::run(queue, sink, start, if syncing { 1.0 } else { cfg.speed_for(&title.lib) }, extra, titles, 5.0, sock_path, terminal,
        if syncing { Some(cfg.syncplay_args.clone()) } else { None });
    if let Some(p) = auth_file {
        let _ = std::fs::remove_file(p);
    }
    if cfg.anilist.auto && !cfg.anilist.token.is_empty() {
        anilist::flush(5.0);
    }
    result.map_err(|e| e.to_string())
}
