//! Command line interface (port of `mediator/cli.py`). Every listing can be plain text for
//! humans, `--tsv` for menus and pipelines, or `--json` for anything else.
mod library;
mod online;
mod services;

use crate::catalog::{scan, Title, KINDS};
use crate::config::{self, Config};
use crate::jellyfin as jf;
use crate::notify::{notify, warn};
use crate::state::State;
use clap::{Args, Parser, Subcommand};
use serde_json::Value;
use std::cell::{OnceCell, RefCell};
use std::collections::BTreeMap;

/// A failure to report as `mediator: <message>` (exit 1).
#[derive(Debug)]
pub struct CliError(pub String);
impl<T: Into<String>> From<T> for CliError {
    fn from(s: T) -> Self {
        CliError(s.into())
    }
}
pub type Res = Result<i32, CliError>;
pub fn die<T>(msg: impl Into<String>) -> Result<T, CliError> {
    Err(CliError(msg.into()))
}

// ---- arguments ----

const KIND_ARGS: [&str; 4] = ["anime", "shows", "movies", "jellyfin"];

#[derive(Args, Clone, Default)]
pub struct Fmt {
    /// machine-readable output
    #[arg(long, conflicts_with = "tsv")]
    pub json: bool,
    /// tab separated, for menus and pipes
    #[arg(long)]
    pub tsv: bool,
}

#[derive(Args, Clone, Default)]
pub struct Span {
    /// first episode (S01E05, 1x05, 5)
    #[arg(long = "from", value_name = "EP")]
    pub start: Option<String>,
    /// last episode
    #[arg(long = "to", value_name = "EP")]
    pub end: Option<String>,
    /// only this season
    #[arg(long)]
    pub season: Option<i32>,
}

#[derive(Parser)]
#[command(name = "mediator", about = "Local media library browser and player.", infer_long_args = true, disable_help_subcommand = true)]
pub struct Cli {
    /// include your Jellyfin libraries (ids start with jellyfin/)
    #[arg(short = 'j', long, global = true)]
    pub jellyfin: bool,
    /// watch together: play through syncplay (speed forced to 1.0)
    #[arg(short = 's', long, global = true)]
    pub syncplay: bool,
    #[command(subcommand)]
    pub cmd: Cmd,
}

#[derive(Args)]
pub struct KindArg {
    #[arg(value_parser = KIND_ARGS)]
    pub kind: Option<String>,
}

#[derive(Subcommand)]
pub enum Cmd {
    /// list titles with progress
    List { #[command(flatten)] k: KindArg, #[command(flatten)] f: Fmt },
    /// seasons and episodes of a title, with watch status
    Show { query: String, #[arg(short, long)] all: bool, #[command(flatten)] f: Fmt },
    /// resume where you left off, or play the next episode
    Continue {
        query: String,
        #[arg(short = 'n', long)] dry_run: bool,
        #[arg(long)] rewatch: bool,
        #[arg(long)] detach: bool,
        #[arg(long)] json: bool,
    },
    /// stream an episode through ani-cli and sync it to AniList
    Stream {
        query: String,
        #[arg(long)] search: bool,
        #[arg(short, long)] episode: Option<i64>,
        #[arg(long)] season: Option<i64>,
        #[arg(long)] dub: bool,
        #[arg(short, long)] quality: Option<String>,
        #[arg(long)] skip: bool,
        #[arg(short = 'S', long)] select: Option<i64>,
        #[arg(long)] no_sync: bool,
        #[arg(long)] dry_run: bool,
    },
    /// search the native anime provider (JSON for GUI clients)
    StreamSearch { query: String, #[command(flatten)] f: Fmt },
    /// download instead of streaming: add|auto|hls|batch JSON, status, finalize HASH IDX; anime-episode|anime-season JSON, anime-status JSON|SHOW, anime-cancel SHOW
    Download { #[arg(value_parser = ["add", "auto", "hls", "batch", "status", "finalize", "anime-episode", "anime-season", "anime-feed", "anime-status", "anime-cancel"])] action: String, #[arg(num_args = 0..)] args: Vec<String> },
    /// anime catalogs from AniList: trending | season | popular | top | search QUERY | media ID (JSON)
    AnimeBrowse { #[arg(default_value = "trending")] mode: String, #[arg(num_args = 0..)] arg: Vec<String> },
    /// list native provider episodes for an exact title id
    StreamEpisodes { provider_id: String, #[command(flatten)] f: Fmt },
    /// cache sizes; --prune trims what is cheap to fetch again
    Cache { #[arg(long)] prune: bool, #[arg(long)] json: bool },
    /// resolve a native provider episode to its stream URL (JSON)
    StreamResolve {
        provider_id: String,
        episode_id: String,
        #[arg(long)] dub: bool,
        #[arg(short, long, default_value = "best")] quality: String,
    },
    /// control an exact native player socket
    StreamControl {
        pid: i64,
        #[arg(value_parser = ["stop", "toggle", "pause", "play", "seek_to"])] action: String,
        #[arg(long, allow_negative_numbers = true)] value: Option<f64>,
        #[arg(long)] json: bool,
    },
    /// read cached native provider playback state
    StreamState { #[arg(long)] all: bool, #[arg(long, requires = "all")] shows: bool, #[command(flatten)] f: Fmt },
    /// remove streamed shows from Continue watching
    StreamForget { #[arg(required = true)] show_id: Vec<String>, #[command(flatten)] f: Fmt },
    /// play one exact native provider episode
    StreamPlay {
        provider_id: String,
        episode_id: String,
        #[arg(long, default_value = "")] title: String,
        #[arg(long, default_value = "")] poster: String,
        #[arg(long)] dub: bool,
        #[arg(short, long, default_value = "best")] quality: String,
        #[arg(long)] start: Option<f64>,
        #[arg(long)] anilist_id: Option<i64>,
        #[arg(long)] season: Option<i64>,
        #[arg(long)] total: Option<i64>,
        #[arg(long)] single: bool,
        #[arg(long)] no_sync: bool,
        #[arg(long)] dry_run: bool,
        #[arg(long)] json: bool,
    },
    /// continue the last native stream or its next episode
    StreamResume { #[arg(long)] no_sync: bool, #[arg(long)] dry_run: bool, #[arg(long)] json: bool, #[arg(long)] single: bool },
    /// retry AniList for watched native episodes
    StreamSync { #[arg(long)] all: bool, #[arg(long)] json: bool },
    /// save native progress from an adopted player (internal)
    StreamCheckpoint {
        show_id: String,
        episode_id: String,
        #[arg(long, required = true, allow_negative_numbers = true)] position: f64,
        #[arg(long, required = true, allow_negative_numbers = true)] duration: f64,
        #[arg(long)] eof: bool,
        #[arg(long)] json: bool,
    },
    /// manage the Stremio streaming server
    Stremio { #[command(subcommand)] cmd: StremioCmd },
    /// play a title, or a span of episodes, as one mpv playlist
    Play {
        query: String,
        #[command(flatten)] span: Span,
        /// only the first selected episode
        #[arg(long)] one: bool,
        /// play exactly this file (as listed by `show --tsv`)
        #[arg(long)] path: Option<String>,
        /// start the first file at its saved position
        #[arg(long)] resume: bool,
        #[arg(long)] detach: bool,
    },
    /// write an .m3u8 playlist (stdout or -o FILE)
    Playlist {
        query: String,
        #[command(flatten)] span: Span,
        /// interleave specials / OVAs
        #[arg(long)] specials: bool,
        #[arg(short, long)] output: Option<String>,
    },
    /// mark episodes watched
    Watched { query: String, #[command(flatten)] span: Span },
    /// forget progress for episodes
    Unwatched { query: String, #[command(flatten)] span: Span },
    /// recently watched titles
    History {
        #[arg(short = 'n', default_value_t = 15)] n: i64,
        /// delete ALL saved progress
        #[arg(long)] clear: bool,
        /// with --clear: do not ask
        #[arg(long)] yes: bool,
        #[command(flatten)] f: Fmt,
    },
    /// interactive menus (fzf or numbered)
    Browse {
        #[command(flatten)] k: KindArg,
        /// auto | fzf | terminal
        #[arg(long)] picker: Option<String>,
        /// exit after one playback (handy for launchers)
        #[arg(long)] once: bool,
    },
    /// import resume points from the old bash mediator
    ImportLegacy { file: Option<String>, #[arg(short = 'n', long)] dry_run: bool },
    /// show where posters come from, fetch missing ones, or set one
    Posters {
        #[arg(value_parser = ["list", "fetch", "set"], default_value = "list")] action: String,
        query: Option<String>,
        image: Option<String>,
        #[arg(short, long, value_parser = KIND_ARGS)] kind: Option<String>,
        #[arg(long)] refresh: bool,
        #[arg(short, long)] verbose: bool,
        #[arg(long)] json: bool,
    },
    /// cache remote cover images for frontends
    CacheImages { #[arg(required = true)] urls: Vec<String>, #[arg(long)] json: bool },
    /// open the config file
    Edit,
    /// log in to, check, or refresh your Jellyfin server
    Jellyfin {
        #[arg(value_parser = ["status", "login", "refresh"], default_value = "status")] action: String,
        #[arg(long)] url: Option<String>,
        #[arg(long)] user: Option<String>,
        #[arg(long)] json: bool,
    },
    /// sync watch progress with AniList (local anime only)
    Anilist {
        #[arg(value_parser = ["status", "login", "logout", "sync", "watching", "score", "set"], default_value = "status")] action: String,
        /// for `sync`/`score`/`set`: one title
        query: Option<String>,
        /// for `score`: the score; for `set`: the status
        value: Option<String>,
        #[arg(long, default_value_t = 30)] limit: i64,
        #[arg(long)] all: bool,
        #[arg(long)] pending: bool,
        #[arg(long)] fetch: bool,
        #[arg(long)] dry_run: bool,
        #[arg(long)] season: Option<i64>,
        #[arg(long)] client_id: Option<String>,
        #[arg(long)] token_stdin: bool,
        #[arg(long)] json: bool,
        #[arg(short, long)] verbose: bool,
    },
    /// synopsis, rating and genres for a title (fetched once, then cached)
    Meta {
        query: Option<String>,
        #[arg(value_parser = KIND_ARGS)] kind: Option<String>,
        #[arg(long)] cached: bool,
        #[arg(long)] refresh: bool,
        #[arg(short, long)] verbose: bool,
    },
    /// banner, description, cast, trailer, next airing and episode names
    Info {
        query: Option<String>,
        #[arg(value_parser = KIND_ARGS)] kind: Option<String>,
        #[arg(long)] cached: bool,
        #[arg(long)] refresh: bool,
        #[arg(short, long)] verbose: bool,
    },
    /// read tracks and resolution from a title's files (ffprobe, cached)
    Probe { query: String, #[arg(long)] refresh: bool, #[arg(short, long)] verbose: bool },
    /// background companion for shells: now playing, change events, enrichment
    Daemon { #[arg(value_parser = ["start", "run", "status"], default_value = "start")] action: String },
    /// show settings, or change them from a front end
    Config { #[arg(value_parser = ["show", "set"], default_value = "show")] action: String, #[arg(long)] json: bool },
    /// report files that were guessed, duplicated or are missing
    Doctor { #[command(flatten)] k: KindArg, #[arg(short, long)] verbose: bool },
    /// show how a filename or folder name is understood
    Parse { #[arg(required = true)] names: Vec<String>, #[arg(long)] movie: bool, #[arg(long)] json: bool },
}

#[derive(Subcommand)]
pub enum StremioCmd {
    /// stop the Stremio streaming server
    Stop {
        #[arg(long)] json: bool,
        #[arg(long, default_value_t = 0.0, hide = true)] delay: f64,
        #[arg(long, hide = true)] if_idle: bool,
    },
    /// show whether the Stremio server is running
    Status { #[arg(long)] json: bool },
    /// search movies and series (JSON for GUI clients)
    Search { #[arg(required = true)] query: Vec<String> },
    /// the top titles of a kind: movie or series (JSON)
    Top { kind: String },
    /// one page of a catalog: KIND SORT [FILTER] [SKIP] (JSON)
    Browse { kind: String, sort: String, #[arg(default_value = "")] filter: String, #[arg(default_value_t = 0)] skip: i64 },
    /// one title with its episodes (JSON)
    Meta { kind: String, id: String },
    /// the streams addons offer for a title or episode (JSON)
    Streams { kind: String, id: String },
    /// remember (or with "clear": true, forget) the stream picked for an episode: JSON argument
    Choose { json: String },
}

// ---- catalog access ----

pub fn load_jellyfin(cfg: &Config, kinds: &[String], state: Option<&State>, any_age: bool) -> (Vec<Title>, Vec<String>) {
    if !cfg.jellyfin.configured() {
        return (vec![], vec!["Jellyfin is not configured (run `mediator jellyfin login`)".into()]);
    }
    let client = jf::Jellyfin::new(&cfg.jellyfin);
    let (mut titles, mut problems) = (vec![], vec![]);
    for kind in kinds {
        if !client.kinds().contains(&kind.as_str()) {
            continue;
        }
        match client.library(kind, false, any_age) {
            Err(e) => {
                problems.push(format!("{kind}: {e}"));
                continue;
            }
            Ok(lib) => {
                if lib.stale {
                    problems.push(format!("{kind}: server unreachable, showing the last known listing"));
                }
                if let Some(s) = state {
                    jf::merge_into_state(s, &lib);
                }
                titles.extend(lib.titles);
            }
        }
    }
    (titles, problems)
}

/// Local libraries always; the Jellyfin ones only when asked (they cost a network round trip).
pub fn load_catalog(cfg: &Config, kinds: Option<&[String]>, jellyfin: bool, state: Option<&State>, any_age: bool) -> (Vec<Title>, BTreeMap<String, Vec<String>>) {
    let mut titles = vec![];
    let mut skipped: BTreeMap<String, Vec<String>> = BTreeMap::new();
    let local: Vec<String> = kinds.map(|k| k.iter().filter(|x| KINDS.contains(&x.as_str())).cloned().collect()).unwrap_or_else(|| KINDS.iter().map(|s| s.to_string()).collect());
    for kind in &local {
        let Some(root) = cfg.libraries.get(kind).filter(|r| !r.is_empty()) else { continue };
        let (t, s) = scan(kind, root);
        titles.extend(t);
        skipped.insert(kind.clone(), s);
    }
    let wants_remote = kinds.map(|k| k.iter().any(|x| x == "jellyfin")).unwrap_or(false);
    if jellyfin || wants_remote {
        let which: Vec<String> = if kinds.is_some() && !local.is_empty() { local.clone() } else { KINDS.iter().map(|s| s.to_string()).collect() };
        let (t, problems) = load_jellyfin(cfg, &which, state, any_age);
        titles.extend(t);
        if !problems.is_empty() {
            skipped.insert("jellyfin".into(), problems);
        }
    }
    (titles, skipped)
}

/// Config + catalog + state, loaded lazily so cheap commands stay cheap.
pub struct Ctx {
    pub cfg: Config,
    pub kinds: Option<Vec<String>>,
    pub jellyfin: bool,
    pub jellyfin_any_age: bool,
    titles: OnceCell<Vec<Title>>,
    skipped: RefCell<BTreeMap<String, Vec<String>>>,
    state: OnceCell<State>,
}

impl Ctx {
    pub fn new() -> Ctx {
        Ctx { cfg: config::load(), kinds: None, jellyfin: false, jellyfin_any_age: false, titles: OnceCell::new(), skipped: RefCell::new(BTreeMap::new()), state: OnceCell::new() }
    }

    pub fn state(&self) -> &State {
        self.state.get_or_init(|| State::open(&crate::state::default_path()).unwrap_or_else(|e| {
            eprintln!("mediator: cannot open the progress database: {e}");
            std::process::exit(1)
        }))
    }

    pub fn titles(&self) -> &[Title] {
        self.titles.get_or_init(|| {
            let remote = self.jellyfin || self.kinds.as_ref().map(|k| k.iter().any(|x| x == "jellyfin")).unwrap_or(false);
            let (t, skipped) = load_catalog(&self.cfg, self.kinds.as_deref(), self.jellyfin, if remote { Some(self.state()) } else { None }, self.jellyfin_any_age);
            for msg in skipped.get("jellyfin").into_iter().flatten() {
                warn(&format!("mediator: {msg}"));
            }
            *self.skipped.borrow_mut() = skipped;
            t
        })
    }

    pub fn skipped(&self) -> BTreeMap<String, Vec<String>> {
        self.titles();
        self.skipped.borrow().clone()
    }

    /// A SQLite connection must not cross fork().
    pub fn close_state(&mut self) {
        self.state.take();
    }
}

pub fn kinds_of(kind: &Option<String>) -> Option<Vec<String>> {
    kind.as_ref().map(|k| vec![k.clone()])
}

/// Python's `json.dumps(indent=2, ensure_ascii=False)`.
pub fn pretty(v: &Value) -> String {
    serde_json::to_string_pretty(v).unwrap_or_default()
}

// ---- entry point ----

/// No arguments, or an old-style `--anime`, means `browse`.
pub fn normalize_argv(mut argv: Vec<String>) -> Vec<String> {
    let mut lead = vec![];
    while argv.first().map(|a| ["-s", "--syncplay", "-j", "--jellyfin"].contains(&a.as_str())).unwrap_or(false) {
        lead.push(argv.remove(0));
    }
    if argv.is_empty() {
        lead.push("browse".into());
        return lead;
    }
    if let Some(kind) = match argv[0].as_str() { "--anime" => Some("anime"), "--shows" => Some("shows"), "--movies" => Some("movies"), _ => None } {
        argv.remove(0);
        lead.push("browse".into());
        lead.push(kind.into());
    }
    lead.extend(argv);
    lead
}

fn edit_config() -> i32 {
    let path = config::config_path();
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    std::process::Command::new("xdg-open").arg(&path).status().map(|s| s.code().unwrap_or(1)).unwrap_or(1)
}

pub fn main(argv: Vec<String>) -> i32 {
    let argv = normalize_argv(argv);
    if ["edit", "--edit", "-e"].contains(&argv[0].as_str()) {
        return edit_config();
    }
    let cli = match Cli::try_parse_from(std::iter::once("mediator".to_string()).chain(argv)) {
        Ok(c) => c,
        Err(e) => {
            let code = e.exit_code();
            let _ = e.print();
            return code;
        }
    };
    let mut ctx = Ctx::new();
    let query_is_remote = match &cli.cmd {
        Cmd::Show { query, .. } | Cmd::Continue { query, .. } | Cmd::Play { query, .. } | Cmd::Playlist { query, .. } | Cmd::Watched { query, .. } | Cmd::Unwatched { query, .. }
        | Cmd::Probe { query, .. } | Cmd::Stream { query, .. } => query.starts_with("jellyfin/"),
        Cmd::Meta { query: Some(q), .. } | Cmd::Info { query: Some(q), .. } | Cmd::Posters { query: Some(q), .. } | Cmd::Anilist { query: Some(q), .. } => q.starts_with("jellyfin/"),
        _ => false,
    };
    ctx.jellyfin = cli.jellyfin || ctx.cfg.jellyfin.include || query_is_remote;
    if cli.syncplay {
        ctx.cfg.player = "syncplay".into();
    }
    if ctx.cfg.player == "syncplay" && crate::notify::which(&crate::player::syncplay_command()[0]).is_none() {
        eprintln!("mediator: syncplay is not installed");
        notify("syncplay is not installed", false);
        return 1;
    }
    let result = dispatch(cli.cmd, &mut ctx);
    match result {
        Ok(code) => code,
        Err(CliError(msg)) => {
            eprintln!("mediator: {msg}");
            notify(&msg, false);
            1
        }
    }
}

fn dispatch(cmd: Cmd, ctx: &mut Ctx) -> Res {
    match cmd {
        Cmd::Edit => Ok(edit_config()),
        c @ (Cmd::List { .. } | Cmd::Show { .. } | Cmd::Continue { .. } | Cmd::Play { .. } | Cmd::Playlist { .. } | Cmd::Watched { .. } | Cmd::Unwatched { .. }
            | Cmd::History { .. } | Cmd::Browse { .. } | Cmd::ImportLegacy { .. } | Cmd::Cache { .. } | Cmd::Doctor { .. } | Cmd::Parse { .. }) => library::run(c, ctx),
        c @ (Cmd::Stream { .. } | Cmd::StreamSearch { .. } | Cmd::StreamEpisodes { .. } | Cmd::StreamResolve { .. } | Cmd::StreamControl { .. } | Cmd::StreamState { .. }
            | Cmd::StreamForget { .. } | Cmd::StreamPlay { .. } | Cmd::StreamResume { .. } | Cmd::StreamSync { .. } | Cmd::StreamCheckpoint { .. } | Cmd::Stremio { .. } | Cmd::AnimeBrowse { .. } | Cmd::Download { .. }) => online::run(c, ctx),
        c => services::run(c, ctx),
    }
}

/// Python's `format(x, "g")`: six significant digits, no trailing zeros.
pub fn fmt_g(x: f64) -> String {
    if x == 0.0 {
        return "0".into();
    }
    if !x.is_finite() {
        return if x.is_nan() { "nan".into() } else if x > 0.0 { "inf".into() } else { "-inf".into() };
    }
    let exp = x.abs().log10().floor() as i32;
    let s = format!("{:.5e}", x); // d.dddddeN, already rounded to 6 significant digits
    let (mant, e) = s.split_once('e').unwrap();
    let e: i32 = e.parse().unwrap_or(exp);
    if e < -4 || e >= 6 {
        let m = mant.trim_end_matches('0').trim_end_matches('.');
        return format!("{m}e{}{:02}", if e < 0 { '-' } else { '+' }, e.abs());
    }
    let decimals = (5 - e).max(0) as usize;
    let t = format!("{:.*}", decimals, x);
    if t.contains('.') { t.trim_end_matches('0').trim_end_matches('.').to_string() } else { t }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn g_formatting_matches_python() {
        for (x, want) in [(0.0, "0"), (5.0, "5"), (1234.5, "1234.5"), (0.1, "0.1"), (1420.045, "1420.05"), (1e6, "1e+06"), (123456.0, "123456"), (1234567.0, "1.23457e+06"), (0.0001, "0.0001"), (0.00001, "1e-05"), (-2.5, "-2.5"), (3600.0, "3600")] {
            assert_eq!(fmt_g(x), want, "{x}");
        }
    }

    #[test]
    fn legacy_flags_become_browse() {
        let a = |v: &[&str]| normalize_argv(v.iter().map(|s| s.to_string()).collect());
        assert_eq!(a(&[]), ["browse"]);
        assert_eq!(a(&["--anime", "--once"]), ["browse", "anime", "--once"]);
        assert_eq!(a(&["-j", "list"]), ["-j", "list"]);
        assert_eq!(a(&["-s"]), ["-s", "browse"]);
    }
}

impl From<crate::selection::SelectionError> for CliError {
    fn from(e: crate::selection::SelectionError) -> Self {
        CliError(e.0)
    }
}

/// Run `f` over `items` on up to `workers` threads; results come back in input order.
pub fn par_map<T: Sync, R: Send>(items: &[T], workers: usize, f: impl Fn(&T) -> R + Sync) -> Vec<R> {
    use std::sync::atomic::{AtomicUsize, Ordering};
    let next = AtomicUsize::new(0);
    let out: std::sync::Mutex<Vec<Option<R>>> = std::sync::Mutex::new((0..items.len()).map(|_| None).collect());
    std::thread::scope(|s| {
        for _ in 0..workers.max(1).min(items.len().max(1)) {
            s.spawn(|| loop {
                let i = next.fetch_add(1, Ordering::SeqCst);
                if i >= items.len() {
                    break;
                }
                let r = f(&items[i]);
                out.lock().unwrap()[i] = Some(r);
            });
        }
    });
    out.into_inner().unwrap().into_iter().map(|r| r.unwrap()).collect()
}
