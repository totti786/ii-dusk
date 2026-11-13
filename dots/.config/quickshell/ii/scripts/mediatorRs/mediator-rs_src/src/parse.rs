//! Filename and directory-name parsing. Pure functions, no I/O. Port of `mediator/parse.py`;
//! the differential test in `tests/parse_corpus.rs` compares it with the Python output.
use fancy_regex::{Captures, Regex};
use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use unicode_normalization::UnicodeNormalization;

pub const VIDEO_EXTS: &[&str] = &[".mkv", ".mp4", ".avi", ".m4v", ".webm", ".mov", ".wmv", ".flv", ".mpg", ".mpeg"];

const DEC: char = '․'; // stands in for the dot of a half-episode
const SEP: &str = " \t-–—:_.,~";
const MAX_YEAR: i32 = 2035;
const SITE_JUNK: &[&str] = &["primewire", "eztv", "rarbg", "yts", "yify", "ettv", "tgx", "tbd", "tba", "galaxyrg"];

/// Compile once, keep for the life of the process.
pub fn rx(pattern: &str) -> &'static Regex {
    static CACHE: OnceLock<Mutex<HashMap<String, &'static Regex>>> = OnceLock::new();
    let mut m = CACHE.get_or_init(Default::default).lock().unwrap();
    if let Some(r) = m.get(pattern) {
        return r;
    }
    let r: &'static Regex = Box::leak(Box::new(Regex::new(pattern).unwrap_or_else(|e| panic!("bad regex {pattern}: {e}"))));
    m.insert(pattern.to_string(), r);
    r
}

fn search<'t>(p: &str, s: &'t str) -> Option<Captures<'t, str>> {
    rx(p).captures(s).ok().flatten()
}
fn is_match(p: &str, s: &str) -> bool {
    rx(p).is_match(s).unwrap_or(false)
}
fn sub(p: &str, rep: &str, s: &str) -> String {
    rx(p).replace_all(s, rep).into_owned()
}

fn squash(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}
fn strip_chars<'a>(s: &'a str, set: &str) -> &'a str {
    s.trim_matches(|c| set.contains(c))
}
fn tidy(s: &str) -> String {
    squash(strip_chars(s, &format!("{SEP} ")))
}

fn strip_groups(s: &str) -> String {
    let mut s = s.to_string();
    loop {
        let n = sub(r"\[[^\[\]]*\]|\([^()]*\)|\{[^{}]*\}", " ", &s);
        if n == s {
            return s;
        }
        s = n;
    }
}

/// Comparison key: case, punctuation and spacing do not matter.
pub fn norm_key(s: &str) -> String {
    let n: String = s.nfkc().collect::<String>().to_lowercase().replace('ß', "ss");
    squash(&n.chars().map(|c| if c.is_alphanumeric() { c } else { ' ' }).collect::<String>())
}

const STRONG: &str = r"(?i)(?<![A-Za-z0-9])(?:\d{3,4}[pi]|[248]k|uhd|blu-?ray|bd-?rip|br-?rip|bd-?remux|remux|bdmv|web-?dl|web-?rip|hdtv|hd-?rip|dvd-?rip|hdr10\+?|hdr|x26[45]|h[ .]?26[45]|hevc|avc|av1|xvid|divx|vp9|aac\d*|e?ac-?3|dts(?:-?hd)?|ddp?\d*|flac|opus\d*|truehd|atmos|\d{1,2}[ -]?bits?|dual[ -]?audio|multi[ -]?(?:audio|subs?)|eng[ -]?subs?)(?![A-Za-z0-9])";
const WEAK: &str = r"(?i)(?<![A-Za-z0-9])(?:complete|batch|remastered|extended|unrated|proper|repack|internal|multi|dual|web|bd|bluray|korean|japanese|chinese|french|german|spanish|italian|russian|hindi|nf|amzn|dsnp|hmax|atvp|hulu|pcok)(?![A-Za-z0-9])";
const ORDINAL: &str = r"\d{1,2}(?:st|nd|rd|th)[ ._]+Season";
const YEAR_PAREN: &str = r"[(\[]\s*((?:19|20)\d\d)\s*[)\]]";
const X: &str = r"(?<![A-Za-z0-9])";

fn season_mark() -> String {
    format!(r"(?i)(?<![A-Za-z0-9])(?:Seasons?[ ._]*\d|{ORDINAL}|S\d{{1,2}}(?:[ ._+-]|E\d|$))")
}
const RANGE_MARK: &str = r"(?<![A-Za-z0-9])\d{1,4}\s*[~–-]\s*\d{1,4}(?![A-Za-z0-9])";
const COMPLETE_MARK: &str = r"(?i)(?<![A-Za-z0-9])(?:complete|batch|episodes?[ ._]*\d)";

#[derive(Debug, Clone, PartialEq)]
pub struct FileInfo {
    pub kind: String,
    pub show: String,
    pub year: Option<i32>,
    pub season: Option<i32>,
    pub episode: Option<f64>,
    pub episode_end: Option<i32>,
    pub version: i32,
    pub title: String,
    pub rule: String,
    pub confidence: String,
}

impl Default for FileInfo {
    fn default() -> Self {
        FileInfo { kind: String::new(), show: String::new(), year: None, season: None, episode: None,
            episode_end: None, version: 1, title: String::new(), rule: String::new(), confidence: "high".into() }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct DirInfo {
    pub title: String,
    pub year: Option<i32>,
    pub season: Option<i32>,
    pub kind: String,
}

fn release_head(s: &str, weak: bool) -> &str {
    let Some(m) = rx(STRONG).find(s).ok().flatten() else { return s };
    let head = &s[..m.start()];
    if weak {
        if let Some(w) = rx(WEAK).find(head).ok().flatten() {
            return &head[..w.start()];
        }
    }
    head
}

fn bare_year(head: &str) -> Option<(i32, usize)> {
    let mut best = None;
    let trim = format!("{SEP}(");
    for m in rx(r"(?<![0-9])((?:19|20)\d\d)(?![0-9])").find_iter(head).flatten() {
        let y: i32 = m.as_str().parse().unwrap();
        if y > MAX_YEAR {
            continue;
        }
        if m.start() > 0 && !strip_chars(&head[..m.start()], &trim).is_empty() {
            best = Some((y, m.start()));
        }
    }
    best
}

fn num(s: &str) -> f64 {
    s.replace(DEC, ".").parse().unwrap_or(0.0)
}

/// Strip tags and flatten separators. Returns (work, paren_year).
fn prep(stem: &str) -> (String, Option<i32>) {
    let year = search(YEAR_PAREN, stem).and_then(|c| c[1].parse().ok());
    let mut s = strip_groups(stem).replace('_', " ");
    let half = r"(?i)((?<![A-Za-z])E\d{1,4}|\bEp\s*\d{1,4}|\bEpisode\s*\d{1,4}|(?<=\s)[-–]\s*\d{1,4})\.5(?![0-9A-Za-z])";
    s = rx(half).replace_all(&s, |c: &Captures<'_, str>| format!("{}{}5", &c[1], DEC)).into_owned();
    if s.matches('.').count() > s.matches(' ').count() {
        s = s.replace('.', " ");
    }
    (squash(&s), year)
}

struct Hit {
    rule: &'static str,
    confidence: &'static str,
    span: (usize, usize),
    season: Option<i32>,
    episode: Option<f64>,
    end: Option<i32>,
    version: i32,
    special: bool,
}

fn hit(rule: &'static str, confidence: &'static str, span: (usize, usize), season: Option<i32>, episode: f64) -> Hit {
    Hit { rule, confidence, span, season, episode: Some(episode), end: None, version: 1, special: false }
}

fn epnum() -> String {
    format!(r"(\d{{1,4}}(?:{DEC}5)?)")
}
fn ver(c: &Captures<'_, str>, i: usize) -> i32 {
    c.get(i).and_then(|m| m.as_str().parse().ok()).unwrap_or(1)
}
fn span(c: &Captures<'_, str>) -> (usize, usize) {
    let m = c.get(0).unwrap();
    (m.start(), m.end())
}

fn hit_sxxexx(w: &str) -> Option<Hit> {
    let p = format!(r"(?i){X}S(\d{{1,2}})[ ._-]?E{}(?:(?:[ ._-]?E|-)(\d{{1,4}})(?![0-9A-Za-z]))?(?:v(\d))?(?![0-9])", epnum());
    let c = search(&p, w)?;
    let (season, ep) = (c[1].parse::<i32>().unwrap(), num(&c[2]));
    let end = c.get(3).and_then(|m| m.as_str().parse::<i32>().ok()).filter(|&e| (e as f64) > ep);
    Some(Hit { end, version: ver(&c, 4), special: season == 0, ..hit("sxxexx", "high", span(&c), Some(season), ep) })
}

fn hit_season_episode(w: &str) -> Option<Hit> {
    let p = format!(r"(?i){X}Season[ ._]*(\d{{1,2}})[ ,._-]*(?:Episode|Ep)[ ._]*{}(?![0-9A-Za-z])", epnum());
    let c = search(&p, w)?;
    Some(hit("season-episode", "high", span(&c), Some(c[1].parse().unwrap()), num(&c[2])))
}

fn hit_nxm(w: &str) -> Option<Hit> {
    let c = search(&format!(r"{X}(\d{{1,2}})x(\d{{2,3}})(?![0-9A-Za-z])"), w)?;
    Some(hit("nxm", "high", span(&c), Some(c[1].parse().unwrap()), c[2].parse::<f64>().unwrap()))
}

fn hit_season_special(w: &str) -> Option<Hit> {
    let c = search(&format!(r"(?i){X}S(\d{{1,2}})[ ._]*-[ ._]*S(\d{{1,3}})(?![0-9A-Za-z])"), w)?;
    Some(Hit { special: true, ..hit("season-special", "high", span(&c), Some(c[1].parse().unwrap()), c[2].parse::<f64>().unwrap()) })
}

fn hit_season_dash(w: &str) -> Option<Hit> {
    let c = search(&format!(r"(?i){X}S(\d{{1,2}})[ ._]*-[ ._]*{}(?:v(\d))?(?![0-9A-Za-z])", epnum()), w)?;
    Some(Hit { version: ver(&c, 3), ..hit("season-dash", "high", span(&c), Some(c[1].parse().unwrap()), num(&c[2])) })
}

fn hit_episode_word(w: &str) -> Option<Hit> {
    let e = epnum();
    if let Some(c) = search(&format!(r"(?i){X}(?:Episode|Ep)\.?[ ._-]*{e}(?:v(\d))?(?![0-9A-Za-z])"), w) {
        return Some(Hit { version: ver(&c, 2), ..hit("episode-word", "high", span(&c), None, num(&c[1])) });
    }
    let c = search(&format!(r"{X}E{e}(?:v(\d))?(?![0-9A-Za-z])"), w)?;
    Some(Hit { version: ver(&c, 2), ..hit("e-number", "high", span(&c), None, num(&c[1])) })
}

fn hit_dash_number(w: &str) -> Option<Hit> {
    let p = format!(r"(?i)(?<=\s)[-–—~]\s*{}(?:v(\d))?(?=\s|$)", epnum());
    for c in rx(&p).captures_iter(w).flatten() {
        let val = num(&c[1]);
        if [360., 480., 540., 576., 720., 1080., 1440., 2160.].contains(&val)
            || (c[1].chars().count() == 4 && (1900.0..=2099.0).contains(&val))
        {
            continue;
        }
        let end = c.get(0).unwrap().end();
        let tail = w[end..].trim_start();
        let conf = if tail.is_empty() || tail.starts_with(['-', '–', '—', '~']) { "high" } else { "medium" };
        return Some(Hit { version: ver(&c, 2), ..hit("dash-number", conf, span(&c), None, val) });
    }
    None
}

fn hit_leading_number(w: &str) -> Option<Hit> {
    let c = search(r"\A(\d{1,4})(?:v(\d))?(?:\s*[-\u{2013}.]\s+|\s*$)", w)?;
    let n: i32 = c[1].parse().unwrap();
    if c[1].len() == 4 && (1900..=2099).contains(&n) {
        return None;
    }
    Some(Hit { version: ver(&c, 2), ..hit("leading-number", "medium", span(&c), None, n as f64) })
}

fn hit_bare_trailing(w: &str) -> Option<Hit> {
    let c = search(r"(?<=\s)(\d{1,3})(?:v(\d))?\s*$", w)?;
    Some(Hit { version: ver(&c, 2), ..hit("bare-number", "low", span(&c), None, c[1].parse::<f64>().unwrap()) })
}

const EXTRA_STRONG: &str = r"(?i)(?<![A-Za-z0-9])(?:NCED|NCOP|creditless|non[ ._-]?credit\w*|clean[ ._-]?(?:op|ed|opening|ending))(?![A-Za-z]|$)|(?<![A-Za-z0-9])(?:NCED|NCOP)(?![A-Za-z])";
const EXTRA_WEAK: &str = r"(?i)(?<![A-Za-z0-9])(?:trailer|teaser|promo|preview|featurette|bonus|extras?|opening|ending|credits?|making[ ._-]of|behind[ ._-]the[ ._-]scenes|deleted[ ._-]scenes)(?![A-Za-z0-9])|(?<![A-Za-z0-9])(?:PV|CM)(?:[ ._-]?\d{1,2})?(?![A-Za-z0-9])|^(?:OP|ED)[ ._-]?\d{0,2}(?![A-Za-z0-9])";
const SPECIAL_TOKEN: &str = r"(?<![A-Za-z0-9])(?:(?i:OVA|OAD|ONA|specials?)|SP)(?:[ ._-]*(\d{1,3}))?(?![A-Za-z0-9])";
const MOVIE_TOKEN: &str = r"(?i)(?<![A-Za-z0-9])(?:the[ ._-]+)?(?:movie|film)(?:[ ._-]*(\d{1,2}))?(?![A-Za-z0-9])";
const SAMPLE: &str = r"(?i)^(?:sample|.*[ ._\[(-]sample[\])]?)$";

fn split_year(show: &str, year: Option<i32>) -> (String, Option<i32>) {
    if let Some(c) = search(r"\s+((?:19|20)\d\d)$", show) {
        let y: i32 = c[1].parse().unwrap();
        let start = c.get(0).unwrap().start();
        if y <= MAX_YEAR && !show[..start].trim().is_empty() {
            return (show[..start].to_string(), year.or(Some(y)));
        }
    }
    (show.to_string(), year)
}

fn clean_show(raw: &str) -> String {
    let mut s = squash(raw);
    s = sub(r"(?i)[\s\-–—]*\bSeasons?\s*\d+\s*[\s\-–—]*$", "", &s);
    s = sub(r"(?i)[\s\-–—]+S\d{1,2}(?:[\s\-–—]*(?:Opening|Ending))?$", "", &s);
    s = sub(&format!(r"(?i)[\s\-–—]*\b{ORDINAL}[\s\-–—]*$"), "", &s);
    tidy(&s)
}

fn clean_episode_title(rest: &str) -> String {
    let had_tail = is_match(STRONG, rest);
    let mut r = release_head(rest, true).to_string();
    if had_tail {
        r = sub(r"\s+(?:19|20)\d\d\s*$", "", &r);
    }
    let r = tidy(&r);
    let parts: Vec<String> = rx(r"\s[-–—]\s").split(&r).flatten().filter(|p| !p.trim().is_empty())
        .filter(|p| !SITE_JUNK.contains(&norm_key(p).as_str())).map(String::from).collect();
    let t = tidy(&parts.join(" - "));
    if SITE_JUNK.contains(&norm_key(&t).as_str()) || is_match(r"\A[\d\W]*\z", &t) {
        return String::new();
    }
    t
}

/// Parse the filename (no extension) of a file in a show / anime library.
pub fn parse_episode(stem: &str) -> FileInfo {
    let sample = |r: &str| FileInfo { kind: "sample".into(), rule: r.into(), ..Default::default() };
    if is_match(SAMPLE, stem.trim()) {
        return sample("sample");
    }
    let (mut work, mut year) = prep(stem);
    if is_match(EXTRA_STRONG, &work) {
        return FileInfo { kind: "extra".into(), show: clean_show(release_head(&work, true)), year, rule: "extra-token".into(), ..Default::default() };
    }
    let rules: [fn(&str) -> Option<Hit>; 7] = [hit_sxxexx, hit_season_episode, hit_nxm, hit_season_special, hit_season_dash, hit_episode_word, hit_dash_number];
    let mut h = rules.iter().find_map(|f| f(&work));
    if h.is_none() {
        let inner = sub(r"(?i)\[(?:\d{3,4}p|[a-f0-9]{8})\]", " ", stem);
        if let Some(c) = search(r"\[(\d{1,3})(?:v(\d))?\]", &inner) {
            let m0 = c.get(0).unwrap();
            if !is_match(&format!(r"\A(?:{YEAR_PAREN})\z"), m0.as_str()) {
                let pre = squash(&strip_groups(&inner[..m0.start()]).replace('_', " "));
                h = Some(Hit { version: ver(&c, 2), ..hit("bracket-number", "medium", (pre.len(), pre.len()), None, c[1].parse::<f64>().unwrap()) });
                work = pre;
            }
        }
    }
    let h = match h {
        Some(h) => h,
        None => {
            if is_match(EXTRA_WEAK, &work) {
                return FileInfo { kind: "extra".into(), show: clean_show(release_head(&work, true)), year, rule: "extra-token".into(), confidence: "medium".into(), ..Default::default() };
            }
            if let Some(c) = search(MOVIE_TOKEN, &work) {
                let m = c.get(0).unwrap();
                return FileInfo {
                    kind: "movie".into(), show: clean_show(&work[..m.start()]), year,
                    episode: c.get(1).and_then(|x| x.as_str().parse::<f64>().ok()),
                    title: clean_episode_title(&work[m.end()..]), rule: "movie-token".into(), ..Default::default()
                };
            }
            if let Some(c) = search(SPECIAL_TOKEN, &work) {
                let m = c.get(0).unwrap();
                return FileInfo {
                    kind: "special".into(), show: clean_show(&work[..m.start()]), year,
                    episode: c.get(1).and_then(|x| x.as_str().parse::<f64>().ok()),
                    title: clean_episode_title(&work[m.end()..]), rule: "special-token".into(),
                    confidence: "medium".into(), ..Default::default()
                };
            }
            let head = release_head(&work, true).to_string();
            match hit_leading_number(&head).or_else(|| hit_bare_trailing(&head)) {
                Some(h) => {
                    work = head;
                    h
                }
                None => {
                    return FileInfo { kind: "episode".into(), show: clean_show(&head), year, rule: "none".into(), confidence: "low".into(), ..Default::default() };
                }
            }
        }
    };
    let (a, b) = h.span;
    let (show, y2) = split_year(&clean_show(&work[..a]), year);
    year = y2;
    let tagged_special = is_match(r"(?i)\[(?:OVA|OAD|ONA|SP|specials?)\]", stem);
    FileInfo {
        kind: if h.special || tagged_special { "special" } else { "episode" }.into(),
        show, year, season: h.season, episode: h.episode, episode_end: h.end, version: h.version,
        title: clean_episode_title(&work[b..]), rule: h.rule.into(), confidence: h.confidence.into(),
    }
}

/// Parse a movie filename or movie directory name into title + year.
pub fn parse_movie(stem: &str) -> FileInfo {
    if is_match(SAMPLE, stem.trim()) {
        return FileInfo { kind: "sample".into(), rule: "sample".into(), ..Default::default() };
    }
    let (work, mut year) = prep(stem);
    let movie = |show: String, year: Option<i32>| FileInfo { kind: "movie".into(), show, year, rule: "movie-name".into(), ..Default::default() };
    if let Some(m) = rx(YEAR_PAREN).find(stem).ok().flatten() {
        if !strip_chars(&stem[..m.start()], " ._-[(").is_empty() {
            let (before, _) = prep(&stem[..m.start()]);
            return movie(tidy(&before), year);
        }
    }
    let strong_only = release_head(&work, false);
    if year.is_none() {
        if let Some((y, at)) = bare_year(strong_only) {
            return movie(tidy(&strong_only[..at]), Some(y));
        }
    }
    let t = tidy(release_head(&work, true));
    year = year.or(None);
    movie(t, year)
}

pub fn parse_dirname(name: &str) -> DirInfo {
    let (work, mut year) = prep(name);
    let kind = if is_match(r"(?i)(?<![A-Za-z0-9])(?:extras?|featurettes?|bonus|creditless|NCs?|NCOPs?|NCEDs?|trailers?|samples?|behind[ ._-]the[ ._-]scenes)(?![A-Za-z0-9])", &work) {
        "extra"
    } else if is_match(r"(?i)(?<![A-Za-z0-9])(?:specials?|ovas?|oads?)(?![A-Za-z0-9])", &work) {
        "special"
    } else if is_match(r"(?i)(?<![A-Za-z0-9])(?:movies?|films?)(?![A-Za-z0-9])", &work) {
        "movie"
    } else {
        "container"
    };
    let season_re = r"(?i)(?<![A-Za-z0-9])(?:Season[ ._]*(\d{1,2})|S(\d{1,2})|(\d{1,2})(?:st|nd|rd|th)[ ._]+Season)(?![0-9A-Za-z])";
    let mut seasons: Vec<i32> = rx(season_re).captures_iter(&work).flatten()
        .filter_map(|c| (1..=3).find_map(|i| c.get(i)).and_then(|m| m.as_str().parse().ok())).collect();
    seasons.sort();
    seasons.dedup();
    let season = if seasons.len() == 1 { Some(seasons[0]) } else { None };

    let mut s = release_head(&work, true).to_string();
    let sm = season_mark();
    for (pat, is_season) in [(sm.as_str(), true), (COMPLETE_MARK, false), (RANGE_MARK, false)] {
        if let Some(m) = rx(pat).find(&s).ok().flatten() {
            if m.start() > 0 || is_season {
                s.truncate(m.start());
            }
        }
    }
    let mut title = tidy(&s);
    if year.is_none() {
        if let Some((y, at)) = bare_year(&s) {
            year = Some(y);
            title = tidy(&s[..at]);
        }
    }
    if kind != "container" && !title.is_empty() {
        for pat in [
            r"(?i)(?<![A-Za-z0-9])(?:extras?|featurettes?|bonus|creditless|NCs?|NCOPs?|NCEDs?|trailers?|samples?|behind[ ._-]the[ ._-]scenes)(?![A-Za-z0-9])",
            r"(?i)(?<![A-Za-z0-9])(?:specials?|ovas?|oads?)(?![A-Za-z0-9])",
            r"(?i)(?<![A-Za-z0-9])(?:movies?|films?)(?![A-Za-z0-9])",
        ] {
            if let Some(m) = rx(pat).find(&title).ok().flatten() {
                title = tidy(&title[..m.start()]);
            }
        }
    }
    DirInfo { title, year, season, kind: kind.into() }
}

pub fn fmt_num(n: Option<f64>) -> String {
    match n {
        None => "?".into(),
        Some(x) if x == x.trunc() => format!("{}", x as i64),
        Some(x) => format!("{x}"),
    }
}

pub fn episode_code(season: Option<i32>, episode: Option<f64>, end: Option<i32>) -> String {
    let Some(_) = episode else { return String::new() };
    let ep = fmt_num(episode);
    let ep = if ep.contains('.') { format!("{ep:0>4}") } else { format!("{ep:0>2}") };
    let mut code = format!("S{:02}E{ep}", season.unwrap_or(1));
    if let Some(e) = end.filter(|&e| e != 0) {
        code.push_str(&format!("-E{e:02}"));
    }
    code
}
