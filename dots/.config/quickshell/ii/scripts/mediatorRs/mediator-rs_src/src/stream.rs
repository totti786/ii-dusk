//! Stream an episode through ani-cli, then push it to AniList (port of `mediator/stream.py`).
//! ani-cli owns the provider/search/player flow. Its mpv gets an IPC socket through
//! `ANI_CLI_PLAYER_FLAGS`; the episode is pushed only when it actually finished. There is no local
//! file, so local progress is not touched; AniList is the record for streamed episodes.
use crate::anilist::{self, SeasonRow};
use crate::catalog::Title;
use crate::config::Config;
use crate::notify::{warn, which};
use crate::player::{self, FileResult, RunOptions};
use crate::state::{finished, State};
use serde_json::Value;

pub fn ani_cli_command() -> Vec<String> {
    match std::env::var("MEDIATOR_ANI_CLI") {
        Ok(v) if !v.is_empty() => shlex::split(&v).unwrap_or_default(),
        _ => vec!["ani-cli".into()],
    }
}

fn local_next(title: &Title, state: &State, season: i64) -> i64 {
    let progress = state.for_title(&title.id).unwrap_or_default();
    let seasons = title.seasons();
    let best = seasons.get(&(season as i32)).into_iter().flatten().filter_map(|e| {
        let n = e.episode?;
        progress.get(&e.path).filter(|p| p.watched)?;
        Some(e.episode_end.filter(|&x| x != 0).map(|x| x as i64).unwrap_or(n as i64))
    }).max();
    best.map(|n| n + 1).unwrap_or(1)
}

/// (season, AniList id, label, total) from the info cache, or a bare season.
pub fn choose_season(title: &Title, state: &State, rec: Option<&Value>, season: Option<i64>) -> Result<SeasonRow, String> {
    let seasons = rec.map(|r| anilist::media_seasons(title, r)).unwrap_or_default();
    if let Some(s) = season {
        let hit = seasons.iter().find(|x| x.0 == s).cloned();
        if !seasons.is_empty() && hit.is_none() {
            let labels: Vec<_> = seasons.iter().map(|x| x.2.clone()).collect();
            return Err(format!("season {s} is not in the AniList info ({})", labels.join(", ")));
        }
        return Ok(hit.unwrap_or((s, 0, format!("S{s:02}"), None)));
    }
    if seasons.len() == 1 {
        return Ok(seasons[0].clone());
    }
    if !seasons.is_empty() {
        return Ok(anilist::latest_season(title, state, &seasons).unwrap_or_else(|| seasons[0].clone()));
    }
    Ok((1, 0, "S01".into(), None))
}

pub fn stream_command(episode: Option<i64>, query: &str, dub: bool, quality: &str, skip: bool, select: Option<i64>) -> Vec<String> {
    let mut cmd = ani_cli_command();
    if let Some(e) = episode {
        cmd.extend(["-e".into(), e.to_string()]);
    }
    cmd.extend(["--exit-after-play".into(), "--no-detach".into()]);
    if dub {
        cmd.push("--dub".into());
    }
    if !quality.is_empty() {
        cmd.extend(["-q".into(), quality.into()]);
    }
    if skip {
        cmd.push("--skip".into());
    }
    if let Some(s) = select.filter(|&s| s != 0) {
        cmd.extend(["-S".into(), s.to_string()]);
    }
    cmd.push(query.into());
    cmd
}

pub fn stream_env(sock_path: &str) -> Vec<(String, String)> {
    // ani-cli starts mpv itself. Force mpv (VLC cannot speak this IPC protocol) and give it our
    // socket, so the Tracker sees position/EOF.
    let mpv = std::env::var("MEDIATOR_STREAM_MPV").ok().filter(|v| !v.is_empty())
        .or_else(|| which("mpv").map(|p| p.to_string_lossy().into_owned())).unwrap_or_else(|| "mpv".into());
    let extra = std::env::var("ANI_CLI_PLAYER_FLAGS").unwrap_or_default();
    let extra = extra.trim();
    let scripts: Vec<String> = player::script_flags().into_iter().chain(player::NETWORK_CACHE.iter().map(|s| s.to_string())).map(|f| shlex::try_quote(&f).map(|c| c.into_owned()).unwrap_or(f)).collect();
    let flags = format!("{extra} --input-ipc-server={sock_path} {}", scripts.join(" "));
    vec![("ANI_CLI_PLAYER".into(), mpv), ("ANI_CLI_PLAYER_FLAGS".into(), flags.trim().to_string()),
         ("ANI_CLI_EXIT_AFTER_PLAY".into(), "1".into()), ("ANI_CLI_NO_DETACH".into(), "1".into())]
}

fn quoted(cmd: &[String]) -> String {
    cmd.iter().map(|p| shlex::try_quote(p).map(|c| c.into_owned()).unwrap_or_else(|_| p.clone())).collect::<Vec<_>>().join(" ")
}

fn require_tools() -> Result<(), String> {
    if which(&ani_cli_command()[0]).is_none() && std::env::var("MEDIATOR_ANI_CLI").map(|v| v.is_empty()).unwrap_or(true) {
        return Err("ani-cli is not installed (or set MEDIATOR_ANI_CLI)".into());
    }
    if std::env::var("MEDIATOR_STREAM_MPV").map(|v| v.is_empty()).unwrap_or(true) && which("mpv").is_none() {
        return Err("mpv is required for stream tracking".into());
    }
    Ok(())
}

#[derive(Default)]
pub struct Options {
    pub season: Option<i64>,
    pub episode: Option<i64>,
    pub dub: bool,
    pub quality: String,
    pub skip: bool,
    pub select: Option<i64>,
    pub no_sync: bool,
    pub dry_run: bool,
    pub terminal: Option<bool>,
}

pub fn run(title: &Title, state: &State, cfg: &Config, o: &Options) -> Result<i32, String> {
    require_tools()?;
    let mut rec = crate::info::find(title);
    if rec.is_none() {
        // streaming is already online; one lookup is worth it for the episode map and AniList ids
        eprintln!("Looking up AniList info…");
        let http = crate::posters::RealHttp::new(15.0);
        let (status, got) = crate::info::fetch(title, &http, &crate::info::Opts::default());
        if status == "error" {
            warn("mediator: could not fetch info; streaming without AniList sync");
        } else {
            rec = got;
        }
    }
    if rec.as_ref().map(|r| r["schema"].as_i64() != Some(crate::info::SCHEMA)).unwrap_or(false) {
        rec = None;
    }

    let (season, media_id, label, mut total) = choose_season(title, state, rec.as_ref(), o.season)?;
    let episode = match o.episode {
        Some(e) => e,
        None => {
            let mut next: Option<i64> = None;
            if media_id != 0 && !cfg.anilist.token.is_empty() && !o.no_sync {
                let (n, _status, api_total, problem) = anilist::next_episode(media_id, cfg, None);
                next = n;
                if next.is_none() && !problem.is_empty() {
                    if problem.contains("already completed") {
                        return Err(problem);
                    }
                    warn(&format!("mediator: {problem}"));
                }
                total = total.filter(|&t| t != 0).or(api_total);
            }
            next.unwrap_or_else(|| local_next(title, state, season))
        }
    };
    if episode < 1 {
        return Err("the episode must be positive".into());
    }
    if let Some(t) = total.filter(|&t| t != 0) {
        if episode > t {
            return Err(format!("{label} has only {t} episodes"));
        }
    }

    let query = anilist::season_title(title, rec.as_ref(), season);
    let where_ = if season != 0 { format!("{label}E{episode:02}") } else { "movie".to_string() };
    let cmd = stream_command(Some(episode), &query, o.dub, &o.quality, o.skip, o.select);
    let sock = player::socket_path();
    let env = stream_env(&sock);
    if o.dry_run {
        println!("{}", quoted(&cmd));
        eprintln!("{}: {where_} via ani-cli", title.display());
        return Ok(0);
    }

    eprintln!("Streaming {} {where_} via ani-cli", title.display());
    let pushed = std::cell::Cell::new(false);
    let sink = |r: FileResult| {
        if pushed.get() || !finished(r.position, r.duration, r.eof, cfg.finish_ratio, cfg.finish_tail) {
            return;
        }
        pushed.set(true);
        if o.no_sync {
            eprintln!("AniList: skipped (--no-sync)");
        } else if media_id == 0 {
            eprintln!("AniList: no info record; progress not pushed");
        } else if cfg.anilist.token.is_empty() {
            eprintln!("AniList: not logged in; progress not pushed");
        } else {
            let out = anilist::push_episode(title, media_id, season, episode, total, cfg, None, None);
            if !out.errors.is_empty() {
                warn(&format!("mediator: AniList: {}", out.errors.join("; ")));
            } else if let Some(s) = out.saves.last() {
                eprintln!("AniList: {where_} -> {} ({})", s.progress, s.status.as_deref().unwrap_or("None"));
            } else if let Some(s) = out.skipped.first() {
                eprintln!("AniList: {}", s.reason);
            }
        }
    };
    let rc = player::run_external(&cmd, sink, RunOptions { sock_path: Some(sock), env, terminal: o.terminal, ..Default::default() })
        .map_err(|e| format!("could not start ani-cli: {e}"))?;
    if rc != 0 {
        warn(&format!("mediator: ani-cli exited with code {rc} before the episode finished. It scrapes anime sites that change often: update it, or run it by hand to see its message"));
        return Ok(1);
    }
    if !pushed.get() {
        eprintln!("AniList: episode did not finish; progress not pushed");
    }
    Ok(0)
}

/// Stream an arbitrary ani-cli search without pretending it is a library title (no AniList sync).
pub fn run_search(query: &str, episode: Option<i64>, dub: bool, quality: &str, skip: bool, select: Option<i64>, dry_run: bool, terminal: Option<bool>) -> Result<i32, String> {
    let q = query.trim();
    if q.is_empty() {
        return Err("`stream --search` needs an anime query".into());
    }
    require_tools()?;
    if episode.map(|e| e < 1).unwrap_or(false) {
        return Err("the episode must be positive".into());
    }
    // with no explicit episode ani-cli offers its own result/episode picker
    let cmd = stream_command(episode, q, dub, quality, skip, select);
    let sock = player::socket_path();
    let env = stream_env(&sock);
    if dry_run {
        println!("{}", quoted(&cmd));
        eprintln!("{q}: online ani-cli search (AniList sync disabled)");
        return Ok(0);
    }
    eprintln!("Streaming search {q} via ani-cli (AniList sync disabled)");
    player::run_external(&cmd, |_| {}, RunOptions { sock_path: Some(sock), env, terminal, ..Default::default() }).map_err(|e| format!("could not start ani-cli: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn command_matches_ani_cli_flags() {
        std::env::remove_var("MEDIATOR_ANI_CLI");
        assert_eq!(stream_command(Some(3), "Frieren", true, "720", true, Some(2)),
            ["ani-cli", "-e", "3", "--exit-after-play", "--no-detach", "--dub", "-q", "720", "--skip", "-S", "2", "Frieren"]);
        assert_eq!(stream_command(None, "x", false, "", false, None), ["ani-cli", "--exit-after-play", "--no-detach", "x"]);
    }

    #[test]
    fn bare_season_without_info() {
        let t = Title::new("anime/x".into(), "anime", "X".into(), None);
        let d = tempfile::tempdir().unwrap();
        let st = State::open(&d.path().join("p.db")).unwrap();
        assert_eq!(choose_season(&t, &st, None, None).unwrap(), (1, 0, "S01".into(), None));
        assert_eq!(choose_season(&t, &st, None, Some(3)).unwrap().2, "S03");
    }
}
