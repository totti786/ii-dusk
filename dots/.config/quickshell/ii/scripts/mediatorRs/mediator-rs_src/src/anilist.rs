//! Push what mediator has watched to AniList (port of `mediator/anilist.py`).
//! A file is watched when it ends (or passes `finish_ratio`) and progress is stored per file. This
//! maps that state onto the user's list: only local anime, one entry per library season, progress
//! only moves forward, DROPPED is left alone, COMPLETED stays unless `rewatch`, missing entries are
//! only added with `add_missing`, and the last episode sets COMPLETED unless `complete = false`.
use crate::catalog::Title;
use crate::config::{AniList as AniListConfig, Config};
use crate::state::State;
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, HashSet};
use std::time::Duration;

pub const TIMEOUT: f64 = 10.0;
pub const DEFAULT_CLIENT_ID: &str = "54582";
pub const PIN_REDIRECT: &str = "https://anilist.co/api/v2/oauth/pin";
pub const USER_AGENT: &str = "mediator (local media browser)";

pub fn api_url() -> String {
    std::env::var("MEDIATOR_ANILIST_URL").ok().filter(|v| !v.is_empty()).unwrap_or_else(|| "https://graphql.anilist.co".into())
}

pub fn pending_path() -> std::path::PathBuf {
    std::env::var("MEDIATOR_STATE_DIR").ok().filter(|v| !v.is_empty()).map(Into::into).unwrap_or_else(crate::config::state_dir).join("anilist-pending.json")
}

/// AniList scoreFormat -> (max, step)
pub fn score_format(fmt: &str) -> (f64, f64) {
    match fmt {
        "POINT_10_DECIMAL" => (10.0, 0.1),
        "POINT_10" => (10.0, 1.0),
        "POINT_5" => (5.0, 1.0),
        "POINT_3" => (3.0, 1.0),
        _ => (100.0, 1.0),
    }
}

/// The authorization page for mediator's own AniList app.
pub fn auth_url(client_id: &str) -> std::result::Result<String, String> {
    let id = client_id.trim();
    if id.is_empty() {
        return Err("an AniList client id is required".into());
    }
    Ok(format!("https://anilist.co/api/v2/oauth/authorize?client_id={id}&response_type=token"))
}

/// Accept a bare token or the whole redirected URL (the token lives in its fragment).
pub fn token_from_input(text: &str) -> String {
    let t = text.trim();
    match crate::parse::rx(r"(?:access_token|token)=([^&#\s]+)").captures(t).ok().flatten() {
        Some(c) => percent_encoding::percent_decode_str(&c[1]).decode_utf8_lossy().into_owned(),
        None => t.to_string(),
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct AniListError {
    pub message: String,
    pub status: Option<i64>,
    pub retry_after: Option<f64>,
}
impl AniListError {
    pub fn new(m: impl Into<String>) -> Self {
        AniListError { message: m.into(), status: None, retry_after: None }
    }
}
impl std::fmt::Display for AniListError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}
impl std::error::Error for AniListError {}

#[derive(Debug, Clone, PartialEq)]
pub struct Candidate {
    pub media_id: i64,
    pub season: i64,
    pub progress: i64,
    pub complete: bool,
    pub label: String,
    pub total: Option<i64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Save {
    pub media_id: i64,
    pub progress: i64,
    pub status: Option<String>,
    pub season: i64,
    pub label: String,
    pub started_at: Option<Value>,
    pub completed_at: Option<Value>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Skip {
    pub media_id: Option<i64>,
    pub label: String,
    pub reason: String,
}

#[derive(Debug, Clone, Default)]
pub struct ScoreResult {
    pub title_id: String,
    pub media_id: i64,
    pub season: i64,
    pub label: String,
    pub value: Option<f64>,
    pub raw: Option<i64>,
    pub score_format: String,
    pub old_score: Option<f64>,
    pub dry_run: bool,
    pub errors: Vec<String>,
}
impl ScoreResult {
    pub fn changed(&self) -> bool {
        self.raw.is_some() && self.errors.is_empty()
    }
}

#[derive(Debug, Clone, Default)]
pub struct StatusResult {
    pub title_id: String,
    pub media_id: i64,
    pub season: i64,
    pub label: String,
    pub status: String,
    pub previous: Option<String>,
    pub dry_run: bool,
    pub errors: Vec<String>,
}

#[derive(Debug, Clone, Default)]
pub struct Result {
    pub title_id: String,
    pub saves: Vec<Save>,
    pub skipped: Vec<Skip>,
    pub errors: Vec<String>,
    pub dry_run: bool,
}
impl Result {
    pub fn new(id: &str) -> Self {
        Result { title_id: id.into(), ..Default::default() }
    }
    pub fn changed(&self) -> bool {
        !self.saves.is_empty()
    }
}

// ---- HTTP ----

pub type Post = Box<dyn Fn(&str, &Value, &str) -> std::result::Result<Value, AniListError> + Send + Sync>;

/// One GraphQL request.
pub fn post(query: &str, variables: &Value, token: &str) -> std::result::Result<Value, AniListError> {
    let body = json!({"query": query, "variables": variables}).to_string();
    let url = api_url();
    let mut req = crate::http::Request::get(&url).agent(USER_AGENT).timeout(TIMEOUT).header("Content-Type", "application/json").header("Accept", "application/json").post(body.as_bytes());
    let bearer;
    if !token.is_empty() {
        bearer = format!("Bearer {token}");
        req = req.header("Authorization", &bearer);
    }
    let raw = match req.send() {
        Ok(b) => b,
        Err(crate::http::HttpError::Status(c)) => {
            // ureq discards the body on an error status; AniList's message is in it, so ask again
            // through a plain reader only when we need the text
            let message = error_body_message(&url, &body, token).unwrap_or_else(|| crate::errors::http_reason(c).to_string());
            return Err(AniListError { message, status: Some(c as i64), retry_after: if c == 429 { Some(30.0) } else { None } });
        }
        Err(e) => return Err(AniListError::new(format!("couldn't reach AniList: {}", e.describe()))),
    };
    parse_response(&raw)
}

fn error_body_message(url: &str, body: &str, token: &str) -> Option<String> {
    let agent: ureq::Agent = ureq::Agent::config_builder().http_status_as_error(false).timeout_global(Some(Duration::from_secs_f64(TIMEOUT))).user_agent(USER_AGENT).build().into();
    let mut r = agent.post(url).header("Content-Type", "application/json").header("Accept", "application/json");
    if !token.is_empty() {
        r = r.header("Authorization", format!("Bearer {token}"));
    }
    let mut resp = r.send(body.as_bytes()).ok()?;
    let v: Value = serde_json::from_str(&resp.body_mut().read_to_string().ok()?).ok()?;
    v["errors"][0]["message"].as_str().map(String::from)
}

pub fn parse_response(raw: &[u8]) -> std::result::Result<Value, AniListError> {
    let payload: Value = serde_json::from_slice(raw).map_err(|_| AniListError::new("AniList sent an unreadable response"))?;
    let Some(obj) = payload.as_object() else { return Err(AniListError::new("AniList sent an unreadable response")) };
    if obj.get("errors").map(|e| e.as_array().map(|a| !a.is_empty()).unwrap_or(true)).unwrap_or(false) {
        let err = &obj["errors"][0];
        let msg = err["message"].as_str().filter(|m| !m.is_empty()).unwrap_or("AniList returned an error");
        return Err(AniListError { message: msg.into(), status: err["status"].as_i64(), retry_after: None });
    }
    Ok(match obj.get("data") { Some(d) if d.as_object().map(|o| !o.is_empty()).unwrap_or(false) => d.clone(), _ => json!({}) })
}

pub struct Client {
    pub token: String,
    pub user_id: i64,
    post: Post,
    sleep: Box<dyn Fn(f64) + Send + Sync>,
}

fn truthy(v: &Value) -> bool {
    match v { Value::Null => false, Value::Bool(b) => *b, Value::Number(n) => n.as_f64() != Some(0.0), Value::String(s) => !s.is_empty(), Value::Array(a) => !a.is_empty(), Value::Object(o) => !o.is_empty() }
}
fn i(v: &Value) -> i64 {
    v.as_i64().or_else(|| v.as_f64().map(|f| f as i64)).or_else(|| v.as_str().and_then(|s| s.parse().ok())).unwrap_or(0)
}

type R<T> = std::result::Result<T, AniListError>;

impl Client {
    pub fn new(token: &str, user_id: i64) -> Client {
        Client { token: token.into(), user_id, post: Box::new(post), sleep: Box::new(|s| std::thread::sleep(Duration::from_secs_f64(s))) }
    }
    pub fn with_post(token: &str, user_id: i64, post: Post) -> Client {
        Client { token: token.into(), user_id, post, sleep: Box::new(|_| {}) }
    }

    fn call(&self, query: &str, variables: Value) -> R<Value> {
        match (self.post)(query, &variables, &self.token) {
            Err(e) if e.retry_after.is_some() => {
                (self.sleep)(e.retry_after.unwrap().max(1.0).min(60.0));
                (self.post)(query, &variables, &self.token)
            }
            r => r,
        }
    }

    pub fn viewer(&self) -> R<Value> {
        Ok(self.call("query { Viewer { id name } }", json!({}))?["Viewer"].clone())
    }

    /// Read every entry in one request; a missing entry comes back as null.
    pub fn media_states(&self, ids: &[i64]) -> R<BTreeMap<i64, Value>> {
        let mut unique: Vec<i64> = vec![];
        for &x in ids {
            if !unique.contains(&x) {
                unique.push(x);
            }
        }
        if unique.is_empty() {
            return Ok(BTreeMap::new());
        }
        let parts: Vec<String> = unique.iter().enumerate().map(|(n, mid)| format!(
            "m{n}: Media(id: {mid}, type: ANIME) {{ id episodes format mediaListEntry {{ status progress startedAt {{ year month day }} completedAt {{ year month day }} }} }}")).collect();
        let data = self.call(&format!("query {{ {} }}", parts.join(" ")), json!({}))?;
        Ok(unique.iter().enumerate().map(|(n, mid)| (*mid, data[format!("m{n}")].clone())).collect())
    }

    /// The user's CURRENT/REPEATING anime, newest first, with title/cover metadata.
    pub fn watching(&self, limit: i64) -> R<Vec<Value>> {
        if self.user_id == 0 {
            return Err(AniListError::new("no AniList user id; run `mediator anilist login`"));
        }
        let limit = limit.clamp(1, 100);
        let query = "query($id: Int, $page: Int, $perPage: Int) { Page(page: $page, perPage: $perPage) { mediaList(userId: $id, type: ANIME, status_in: [CURRENT, REPEATING], sort: UPDATED_TIME_DESC) { status progress updatedAt media { id title { romaji english native } coverImage { extraLarge large } episodes format seasonYear } } } }";
        let mut out: Vec<Value> = vec![];
        let mut page = 1;
        while (out.len() as i64) < limit {
            let per_page = 50.min(limit - out.len() as i64);
            let data = self.call(query, json!({"id": self.user_id, "page": page, "perPage": per_page}))?;
            let entries = data["Page"]["mediaList"].as_array().cloned().unwrap_or_default();
            for entry in &entries {
                let media = &entry["media"];
                let media_id = i(&media["id"]);
                if media_id == 0 {
                    continue;
                }
                let names = &media["title"];
                let title = ["english", "romaji", "native"].iter().map(|k| &names[*k]).find(|v| truthy(v)).map(|v| v.as_str().unwrap_or("").to_string()).unwrap_or_else(|| media_id.to_string());
                let progress = i(&entry["progress"]);
                let poster = ["extraLarge", "large"].iter().map(|k| &media["coverImage"][*k]).find(|v| truthy(v)).and_then(|v| v.as_str()).unwrap_or("");
                out.push(json!({
                    "id": media_id, "title": title, "poster": poster, "progress": progress,
                    "total": if truthy(&media["episodes"]) { i(&media["episodes"]) } else { 0 }, "next_episode": progress + 1,
                    "status": if truthy(&entry["status"]) { entry["status"].clone() } else { json!("CURRENT") },
                    "format": if truthy(&media["format"]) { media["format"].clone() } else { json!("") }, "year": media["seasonYear"],
                    "updated_at": if truthy(&entry["updatedAt"]) { entry["updatedAt"].clone() } else { json!(0) },
                    "url": format!("https://anilist.co/anime/{media_id}"),
                }));
                if out.len() as i64 >= limit {
                    break;
                }
            }
            if (entries.len() as i64) < per_page {
                break;
            }
            page += 1;
        }
        Ok(out)
    }

    pub fn save(&self, media_id: i64, progress: i64, status: Option<&str>, started_at: Option<&Value>, completed_at: Option<&Value>) -> R<Value> {
        let mut parts = vec!["$mediaId: Int".to_string(), "$progress: Int".to_string()];
        let mut args = vec!["mediaId: $mediaId".to_string(), "progress: $progress".to_string()];
        let mut vars = Map::new();
        vars.insert("mediaId".into(), json!(media_id));
        vars.insert("progress".into(), json!(progress));
        if let Some(s) = status {
            parts.push("$status: MediaListStatus".into());
            args.push("status: $status".into());
            vars.insert("status".into(), json!(s));
        }
        for (name, value) in [("startedAt", started_at), ("completedAt", completed_at)] {
            if let Some(v) = value.filter(|v| truthy(v)) {
                parts.push(format!("${name}: FuzzyDateInput"));
                args.push(format!("{name}: ${name}"));
                vars.insert(name.into(), v.clone());
            }
        }
        let query = format!("mutation({}) {{ SaveMediaListEntry({}) {{ status progress }} }}", parts.join(", "), args.join(", "));
        Ok(self.call(&query, Value::Object(vars))?["SaveMediaListEntry"].clone())
    }

    /// The user's score format and the current entry, in one request.
    pub fn score_context(&self, media_id: i64) -> R<(Value, Value)> {
        let query = "query($id: Int) { Viewer { mediaListOptions { scoreFormat } } Media(id: $id, type: ANIME) { id episodes format mediaListEntry { id status progress score } } }";
        let data = self.call(query, json!({"id": media_id}))?;
        Ok((data["Viewer"].clone(), data["Media"].clone()))
    }

    /// Find one AniList entry by title; exact by default so a stream never syncs to the wrong show.
    pub fn search_media(&self, title: &str, year: Option<i64>, prefix: bool) -> R<Option<Value>> {
        let query = "query($q: String) { Page(perPage: 10) { media(search: $q, type: ANIME) { id episodes format seasonYear title { romaji english native } synonyms } } }";
        let data = self.call(query, json!({"q": title.trim()}))?;
        let media = data["Page"]["media"].as_array().cloned().unwrap_or_default();
        let want = crate::info::fold(title);
        let mut best: Option<((bool, bool, bool, i64), Value)> = None;
        for (index, item) in media.iter().enumerate() {
            let mut names: Vec<String> = ["romaji", "english", "native"].iter().filter_map(|k| item["title"][*k].as_str()).filter(|s| !s.is_empty()).map(crate::info::fold).collect();
            names.extend(item["synonyms"].as_array().cloned().unwrap_or_default().iter().filter_map(|s| s.as_str()).filter(|s| !s.is_empty()).map(crate::info::fold));
            let exact = names.contains(&want);
            let starts = names.iter().any(|n| n.starts_with(&want));
            if !(exact || (prefix && starts)) {
                continue;
            }
            let my = year.is_some() && item["seasonYear"].as_i64() == year;
            let key = (my, exact, starts, -(index as i64));
            if best.as_ref().map(|(k, _)| key > *k).unwrap_or(true) {
                best = Some((key, item.clone()));
            }
        }
        Ok(best.map(|(_, v)| v))
    }

    pub fn set_score(&self, media_id: i64, raw: i64) -> R<Value> {
        let query = "mutation($mediaId: Int, $scoreRaw: Int) { SaveMediaListEntry(mediaId: $mediaId, scoreRaw: $scoreRaw) { score scoreRaw status progress } }";
        Ok(self.call(query, json!({"mediaId": media_id, "scoreRaw": raw}))?["SaveMediaListEntry"].clone())
    }

    pub fn set_status(&self, media_id: i64, status: &str) -> R<Value> {
        let query = "mutation($mediaId: Int, $status: MediaListStatus) { SaveMediaListEntry(mediaId: $mediaId, status: $status) { status progress } }";
        Ok(self.call(query, json!({"mediaId": media_id, "status": status}))?["SaveMediaListEntry"].clone())
    }

    /// The user's whole anime list in one request, shaped like `media_states`.
    pub fn entries(&self, user_id: i64, username: &str) -> R<BTreeMap<i64, Value>> {
        let fields = "{ lists { entries { status progress startedAt { year month day } completedAt { year month day } media { id episodes } } } }";
        let (query, vars) = if user_id != 0 {
            (format!("query($userId: Int) {{ MediaListCollection(userId: $userId, type: ANIME) {fields} }}"), json!({"userId": user_id}))
        } else if !username.is_empty() {
            (format!("query($userName: String) {{ MediaListCollection(userName: $userName, type: ANIME) {fields} }}"), json!({"userName": username}))
        } else {
            return Err(AniListError::new("no AniList user id; run `mediator anilist login`"));
        };
        let data = self.call(&query, vars)?;
        let mut out = BTreeMap::new();
        for group in data["MediaListCollection"]["lists"].as_array().cloned().unwrap_or_default() {
            for e in group["entries"].as_array().cloned().unwrap_or_default() {
                let id = i(&e["media"]["id"]);
                if id != 0 {
                    out.insert(id, json!({"episodes": e["media"]["episodes"], "mediaListEntry": {"status": e["status"], "progress": e["progress"], "startedAt": e["startedAt"], "completedAt": e["completedAt"]}}));
                }
            }
        }
        Ok(out)
    }
}

/// The account behind `token`; errors when it is not valid.
pub fn verify(token: &str, client: Option<&Client>) -> R<Value> {
    let owned;
    let c = match client { Some(c) => c, None => { owned = Client::new(token, 0); &owned } };
    let v = c.viewer()?;
    if !truthy(&v["id"]) {
        return Err(AniListError::new("AniList did not recognize that token"));
    }
    Ok(v)
}

// ---- what should change ----

pub type SeasonRow = (i64, i64, String, Option<i64>); // season, media id, label, total

/// (season, AniList media id, label, total episodes) for the seasons the info knows.
pub fn media_seasons(title: &Title, info: &Value) -> Vec<SeasonRow> {
    if title.lib != "anime" || title.source != "local" {
        return vec![];
    }
    let info_seasons = info["seasons"].as_array().cloned().unwrap_or_default();
    let local: Vec<i32> = title.seasons().keys().copied().collect();
    if local.is_empty() {
        let id = &info["ids"]["anilist"];
        if truthy(id) && info["format"] == "MOVIE" {
            return vec![(0, i(id), "movie".into(), Some(1))];
        }
        return vec![];
    }
    let mut out = vec![];
    for (n, season) in local.iter().enumerate() {
        if n >= info_seasons.len() {
            break;
        }
        let s = &info_seasons[n];
        if !truthy(&s["anilist"]) {
            continue;
        }
        out.push((*season as i64, i(&s["anilist"]), format!("S{season:02}"), if truthy(&s["episodes"]) { Some(i(&s["episodes"])) } else { None }));
    }
    out
}

/// The seasons of `title` that have watched episodes, paired with their AniList ids.
pub fn candidates(title: &Title, info: &Value, watched: &HashSet<String>) -> Vec<Candidate> {
    if title.lib != "anime" || title.source != "local" {
        return vec![];
    }
    let seasons = media_seasons(title, info);
    let by_season = title.seasons();
    if by_season.is_empty() {
        if let Some(m) = seasons.iter().find(|s| s.0 == 0) {
            if title.entries.iter().any(|e| e.kind == "movie" && watched.contains(&e.path)) {
                return vec![Candidate { media_id: m.1, season: 0, progress: 1, complete: true, label: "movie".into(), total: Some(1) }];
            }
        }
        return vec![];
    }
    let mut out = vec![];
    for (season, media_id, label, total) in seasons {
        let Some(eps) = by_season.get(&(season as i32)) else { continue };
        let eps: Vec<_> = eps.iter().filter(|e| e.kind == "episode" && e.episode.is_some()).collect();
        let mut starts: Vec<i64> = eps.iter().map(|e| e.episode.unwrap() as i64).filter(|&n| n > 0).collect();
        starts.sort();
        let mut numbers: Vec<i64> = eps.iter().filter(|e| watched.contains(&e.path)).map(|e| e.episode_end.map(|x| x as i64).filter(|&x| x != 0).unwrap_or(e.episode.unwrap() as i64)).filter(|&n| n > 0).collect();
        numbers.sort();
        if numbers.is_empty() {
            continue;
        }
        if let (Some(t), Some(&first)) = (total.filter(|&t| t != 0), starts.first()) {
            if first > t {
                // absolute numbering (13-24 in a season folder): AniList counts from 1
                let base = first - 1;
                numbers = numbers.iter().map(|n| n - base).collect();
            }
        }
        let mut progress = *numbers.iter().max().unwrap();
        if let Some(t) = total.filter(|&t| t != 0) {
            if progress > t {
                progress = t;
            }
        }
        let complete = total.filter(|&t| t != 0).map(|t| progress >= t).unwrap_or(false);
        out.push(Candidate { media_id, season, progress, complete, label, total });
    }
    out
}

/// The user's score in AniList's 100-point `scoreRaw`.
pub fn score_to_raw(value: f64, fmt: &str) -> i64 {
    if value == 0.0 {
        return 0;
    }
    let r = |x: f64| -> i64 { // Python's round(): half to even
        let f = x.floor();
        let d = x - f;
        (if d > 0.5 || (d == 0.5 && (f as i64) % 2 != 0) { f + 1.0 } else { f }) as i64
    };
    match fmt {
        "POINT_10" | "POINT_10_DECIMAL" => r(value * 10.0),
        "POINT_5" => r(value * 20.0),
        "POINT_3" => r(value * 25.0),
        _ => r(value),
    }
}

pub fn latest_season(title: &Title, state: &State, seasons: &[SeasonRow]) -> Option<SeasonRow> {
    let progress = state.for_title(&title.id).ok()?;
    let by_season = title.seasons();
    let mut best: Option<(f64, SeasonRow)> = None;
    for item in seasons {
        let times: Vec<f64> = by_season.get(&(item.0 as i32)).map(|v| v.iter().filter_map(|e| progress.get(&e.path)).filter(|p| p.watched).map(|p| p.updated).collect()).unwrap_or_default();
        if let Some(m) = times.iter().cloned().fold(None, |a: Option<f64>, x| Some(a.map_or(x, |a| a.max(x)))) {
            if best.as_ref().map(|(b, _)| m > *b).unwrap_or(true) {
                best = Some((m, item.clone()));
            }
        }
    }
    best.map(|(_, i)| i)
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Day {
    pub year: i32,
    pub month: u32,
    pub day: u32,
}
pub fn today() -> Day {
    let d = crate::info::civil_date(crate::state::now() as i64);
    let p: Vec<&str> = d.split('-').collect();
    Day { year: p[0].parse().unwrap(), month: p[1].parse().unwrap(), day: p[2].parse().unwrap() }
}

/// What to write for one season, given AniList's current entry. Never lowers progress.
pub fn decide(c: &Candidate, media: &Value, cfg: &AniListConfig, today_: Option<Day>) -> (Vec<Save>, Option<Skip>) {
    let skip = |why: String| (vec![], Some(Skip { media_id: Some(c.media_id), label: c.label.clone(), reason: why }));
    if media.is_null() {
        return skip("AniList has no media with that id".into());
    }
    let episodes = i(&media["episodes"]);
    let (mut progress, mut complete) = (c.progress, c.complete);
    if episodes != 0 {
        progress = progress.min(episodes);
        complete = progress >= episodes;
    }
    let entry = &media["mediaListEntry"];
    let day = if cfg.dates { let t = today_.unwrap_or_else(today); Some(json!({"year": t.year, "month": t.month, "day": t.day})) } else { None };
    let started = truthy(&entry["startedAt"]);
    let completed = truthy(&entry["completedAt"]);
    let make = |status: &str, prog: Option<i64>| -> Save {
        let value = prog.unwrap_or(progress);
        Save { media_id: c.media_id, progress: value, status: Some(status.into()), season: c.season, label: c.label.clone(),
            started_at: day.clone().filter(|_| value > 0 && !started), completed_at: day.clone().filter(|_| status == "COMPLETED" && !completed) }
    };
    if !truthy(entry) {
        if !cfg.add_missing {
            return skip("not on your AniList list".into());
        }
        return (vec![make(if complete && cfg.complete { "COMPLETED" } else { "CURRENT" }, None)], None);
    }
    let status = entry["status"].as_str().unwrap_or("").to_uppercase();
    let current = i(&entry["progress"]);
    if status == "COMPLETED" {
        if !cfg.rewatch {
            return skip("already completed (set [anilist] rewatch = true to track)".into());
        }
        if progress != 1 {
            return skip("already completed (watch episode 1 to rewatch)".into());
        }
        // AniList resets progress when an entry moves to REPEATING in the same request, so the
        // repeat starts at 0 and the episode goes in a second write.
        return (vec![Save { media_id: c.media_id, progress: 0, status: Some("REPEATING".into()), season: c.season, label: c.label.clone(), started_at: None, completed_at: None },
            make(if complete { "COMPLETED" } else { "REPEATING" }, None)], None);
    }
    if status == "DROPPED" {
        return skip("dropped on AniList".into());
    }
    if progress <= current {
        return skip(format!("already at episode {current}"));
    }
    let new_status = if complete && cfg.complete { "COMPLETED" } else if status == "REPEATING" { "REPEATING" } else { "CURRENT" };
    (vec![make(new_status, None)], None)
}

/// The name to search for: the AniList season title when we have it.
pub fn season_title(title: &Title, info: Option<&Value>, season: i64) -> String {
    if let Some(info) = info {
        let local: Vec<i32> = title.seasons().keys().copied().collect();
        if let Some(index) = local.iter().position(|s| *s as i64 == season) {
            if let Some(name) = info["seasons"].as_array().and_then(|a| a.get(index)).and_then(|s| s["title"].as_str()).filter(|n| !n.is_empty()) {
                return name.into();
            }
        }
    }
    if season > 1 { format!("{} Season {season}", title.name) } else { title.name.clone() }
}

/// (next episode, status, AniList total, error) for a streamed season.
pub fn next_episode(media_id: i64, cfg: &Config, client: Option<&Client>) -> (Option<i64>, Option<String>, Option<i64>, String) {
    if cfg.anilist.token.is_empty() {
        return (None, None, None, "no AniList token".into());
    }
    let owned;
    let client = match client { Some(c) => c, None => { owned = Client::new(&cfg.anilist.token, cfg.anilist.user_id); &owned } };
    let media = match client.media_states(&[media_id]) {
        Ok(m) => m.get(&media_id).cloned().unwrap_or(Value::Null),
        Err(e) => return (None, None, None, e.message),
    };
    if !truthy(&media) {
        return (None, None, None, "AniList has no media with that id".into());
    }
    let total = if truthy(&media["episodes"]) { Some(i(&media["episodes"])) } else { None };
    let entry = &media["mediaListEntry"];
    if !truthy(entry) {
        return (Some(1), None, total, String::new());
    }
    let status = entry["status"].as_str().unwrap_or("").to_uppercase();
    let progress = i(&entry["progress"]);
    if status == "COMPLETED" {
        return (None, Some(status), total, "already completed; pass --episode 1 to rewatch".into());
    }
    (Some(progress + 1), Some(status), total, String::new())
}

/// Push one streamed episode without touching local progress (there is no local file).
pub fn push_episode(title: &Title, media_id: i64, season: i64, episode: i64, total: Option<i64>, cfg: &Config, client: Option<&Client>, today_: Option<Day>) -> Result {
    let mut result = Result::new(&title.id);
    if cfg.anilist.token.is_empty() {
        result.errors.push("no AniList token (run `mediator anilist login`)".into());
        return result;
    }
    if title.lib != "anime" || title.source != "local" {
        result.errors.push("only local anime can be synced".into());
        return result;
    }
    let owned;
    let client = match client { Some(c) => c, None => { owned = Client::new(&cfg.anilist.token, cfg.anilist.user_id); &owned } };
    let media = match client.media_states(&[media_id]) {
        Ok(m) => m.get(&media_id).cloned().unwrap_or(Value::Null),
        Err(e) => {
            result.errors.push(e.message);
            return result;
        }
    };
    let label = if season == 0 { "movie".to_string() } else { format!("S{season:02}") };
    let candidate = Candidate { media_id, season, progress: episode, complete: total.filter(|&t| t != 0).map(|t| episode >= t).unwrap_or(false), label, total };
    let (saves, skip) = decide(&candidate, &media, &cfg.anilist, today_);
    if let Some(s) = skip {
        result.skipped.push(s);
        return result;
    }
    for s in saves {
        if let Err(e) = client.save(s.media_id, s.progress, s.status.as_deref(), s.started_at.as_ref(), s.completed_at.as_ref()) {
            result.errors.push(e.message);
            break;
        }
        result.saves.push(s);
    }
    result
}

/// Push a native-provider episode, resolving the AniList entry by title when needed.
pub fn push_online(show_id: &str, show_title: &str, episode_number: &Value, cfg: &Config, media_id: i64, season: i64, total: i64, client: Option<&Client>) -> Result {
    let name = if show_title.is_empty() { show_id } else { show_title };
    let title = Title::new(format!("online/{show_id}"), "anime", name.into(), None);
    let mut result = Result::new(&title.id);
    if cfg.anilist.token.is_empty() {
        result.errors.push("no AniList token (run `mediator anilist login`)".into());
        return result;
    }
    let shown = match episode_number { Value::String(s) => s.clone(), o => o.to_string() };
    let f: Option<f64> = match episode_number { Value::Number(n) => n.as_f64(), Value::String(s) => s.trim().parse().ok(), _ => None };
    let episode = match f.filter(|f| (f - f.round()).abs() <= 1e-9) {
        Some(f) => f as i64,
        None => {
            result.errors.push(format!("episode '{shown}' is not a whole number"));
            return result;
        }
    };
    if episode < 1 {
        result.errors.push("episode must be positive".into());
        return result;
    }
    let owned;
    let client = match client { Some(c) => c, None => { owned = Client::new(&cfg.anilist.token, cfg.anilist.user_id); &owned } };
    let (mut media_id, mut total, mut season) = (media_id, total, season);
    if media_id == 0 {
        match client.search_media(name, None, false) {
            Err(e) => {
                result.errors.push(e.message);
                return result;
            }
            Ok(None) => {
                result.errors.push(format!("no AniList match for '{name}'"));
                return result;
            }
            Ok(Some(media)) => {
                media_id = i(&media["id"]);
                if total == 0 {
                    total = i(&media["episodes"]);
                }
                if season == 0 {
                    season = if media["format"] == "MOVIE" { 0 } else { 1 };
                }
            }
        }
    }
    push_episode(&title, media_id, season, episode, if total != 0 { Some(total) } else { None }, cfg, Some(client), None)
}

/// (record, problem). With `fetch`, a missing info record is looked up (network).
pub fn resolve_info(title: &Title, info: Option<&Value>, fetch: Option<&dyn crate::posters::Http>) -> (Option<Value>, String) {
    let mut rec: Option<Value> = match info { Some(i) => Some(i.clone()), None => crate::info::find(title) };
    if rec.as_ref().map(|r| r["schema"].as_i64() != Some(crate::info::SCHEMA)).unwrap_or(false) {
        rec = None;
    }
    if rec.as_ref().map(|r| r["source"] != "anilist").unwrap_or(true) {
        if let Some(http) = fetch {
            let (status, got) = crate::info::fetch(title, http, &crate::info::Opts::default());
            if status == "error" {
                let msg = got.as_ref().and_then(|g| g["error"].as_str()).filter(|s| !s.is_empty()).unwrap_or("could not fetch info").to_string();
                return (None, msg);
            }
            rec = got;
        }
    }
    match rec {
        Some(r) if r["source"] == "anilist" => (Some(r), String::new()),
        _ => (None, "no AniList info cached (run `mediator info`)".into()),
    }
}

fn pick_season(title: &Title, state: &State, seasons: &[SeasonRow], season: Option<i64>, none_msg: &str) -> std::result::Result<SeasonRow, String> {
    let labels = || seasons.iter().map(|s| s.2.clone()).collect::<Vec<_>>().join(", ");
    if let Some(s) = season {
        return seasons.iter().find(|x| x.0 == s).cloned().ok_or_else(|| none_msg.replace("{season}", &s.to_string()).replace("{labels}", &labels()));
    }
    if seasons.len() == 1 {
        return Ok(seasons[0].clone());
    }
    latest_season(title, state, seasons).ok_or_else(|| format!("pick a season with --season ({})", labels()))
}

/// Change one season's AniList status without rewriting progress.
#[allow(clippy::too_many_arguments)]
pub fn set_status_title(title: &Title, state: &State, cfg: &Config, status: &str, season: Option<i64>, info: Option<&Value>, fetch: Option<&dyn crate::posters::Http>, dry_run: bool, client: Option<&Client>) -> StatusResult {
    let mut r = StatusResult { title_id: title.id.clone(), status: status.to_uppercase(), dry_run, ..Default::default() };
    const ALLOWED: [&str; 6] = ["CURRENT", "COMPLETED", "REPEATING", "PAUSED", "DROPPED", "PLANNING"];
    if !ALLOWED.contains(&r.status.as_str()) {
        let mut a = ALLOWED.to_vec();
        a.sort();
        r.errors.push(format!("status must be one of {}", a.join(", ")));
        return r;
    }
    if cfg.anilist.token.is_empty() {
        r.errors.push("no AniList token (run `mediator anilist login`)".into());
        return r;
    }
    if title.lib != "anime" || title.source != "local" {
        r.errors.push("only local anime can be synced".into());
        return r;
    }
    let (rec, problem) = resolve_info(title, info, fetch);
    let Some(rec) = rec else {
        r.errors.push(problem);
        return r;
    };
    let seasons = media_seasons(title, &rec);
    if seasons.is_empty() {
        r.errors.push("no AniList seasons in the info record".into());
        return r;
    }
    let chosen = match pick_season(title, state, &seasons, season, "season {season} is not in the AniList info") {
        Ok(c) => c,
        Err(e) => {
            r.errors.push(e);
            return r;
        }
    };
    r.media_id = chosen.1;
    r.season = chosen.0;
    r.label = chosen.2.clone();
    let owned;
    let client = match client { Some(c) => c, None => { owned = Client::new(&cfg.anilist.token, cfg.anilist.user_id); &owned } };
    let media = match client.media_states(&[r.media_id]) {
        Ok(m) => m.get(&r.media_id).cloned().unwrap_or(Value::Null),
        Err(e) => {
            r.errors.push(e.message);
            return r;
        }
    };
    let entry = &media["mediaListEntry"];
    if !truthy(entry) && !cfg.anilist.add_missing {
        r.errors.push("not on your AniList list; add it before changing the status".into());
        return r;
    }
    r.previous = entry["status"].as_str().map(String::from);
    if r.previous.as_deref() == Some(r.status.as_str()) {
        return r;
    }
    if !dry_run {
        if let Err(e) = client.set_status(r.media_id, &r.status) {
            r.errors.push(e.message);
        }
    }
    r
}

/// Sync one title. `fetch` lets a missing info record be looked up (network).
#[allow(clippy::too_many_arguments)]
pub fn sync_title(title: &Title, state: &State, cfg: &Config, info: Option<&Value>, fetch: Option<&dyn crate::posters::Http>, dry_run: bool, client: Option<&Client>,
                  states: Option<&BTreeMap<i64, Value>>, states_complete: bool, today_: Option<Day>) -> Result {
    let mut result = Result::new(&title.id);
    result.dry_run = dry_run;
    if cfg.anilist.token.is_empty() {
        result.errors.push("no AniList token (run `mediator anilist login`)".into());
        return result;
    }
    if title.lib != "anime" || title.source != "local" {
        result.skipped.push(Skip { media_id: None, label: title.display(), reason: "not a local anime".into() });
        return result;
    }
    let (rec, problem) = resolve_info(title, info, fetch);
    let Some(rec) = rec else {
        if problem.starts_with("could not") {
            result.errors.push(problem);
        } else {
            result.skipped.push(Skip { media_id: None, label: title.display(), reason: problem });
        }
        return result;
    };
    let watched: HashSet<String> = state.for_title(&title.id).unwrap_or_default().into_iter().filter(|(_, p)| p.watched).map(|(k, _)| k).collect();
    let found = candidates(title, &rec, &watched);
    if found.is_empty() {
        result.skipped.push(Skip { media_id: None, label: title.display(), reason: "nothing watched".into() });
        return result;
    }
    let owned;
    let client = match client { Some(c) => c, None => { owned = Client::new(&cfg.anilist.token, cfg.anilist.user_id); &owned } };
    let fetched;
    let states = match states {
        Some(s) => s,
        None => match client.media_states(&found.iter().map(|c| c.media_id).collect::<Vec<_>>()) {
            Ok(s) => {
                fetched = s;
                &fetched
            }
            Err(e) => {
                result.errors.push(e.message);
                return result;
            }
        },
    };
    for c in found {
        let mut media = states.get(&c.media_id).cloned().unwrap_or(Value::Null);
        if media.is_null() && !states_complete {
            // `entries()` only knows titles already on the list; a missing one can still be added
            media = json!({"episodes": c.total, "mediaListEntry": null});
        }
        let mut c = c;
        if truthy(&media["episodes"]) {
            let episodes = i(&media["episodes"]);
            let progress = c.progress.min(episodes);
            c.progress = progress;
            c.complete = progress >= episodes;
        }
        let (saves, skip) = decide(&c, &media, &cfg.anilist, today_);
        if let Some(s) = skip {
            result.skipped.push(s);
            continue;
        }
        for s in saves {
            if dry_run {
                result.saves.push(s);
                continue;
            }
            if let Err(e) = client.save(s.media_id, s.progress, s.status.as_deref(), s.started_at.as_ref(), s.completed_at.as_ref()) {
                result.errors.push(format!("{}: {e}", c.label));
                break;
            }
            result.saves.push(s);
        }
    }
    result
}

/// Set the AniList score for one season and return what was sent.
#[allow(clippy::too_many_arguments)]
pub fn score_title(title: &Title, state: &State, cfg: &Config, value: f64, season: Option<i64>, info: Option<&Value>, fetch: Option<&dyn crate::posters::Http>, dry_run: bool, client: Option<&Client>) -> ScoreResult {
    let mut r = ScoreResult { title_id: title.id.clone(), value: Some(value), dry_run, ..Default::default() };
    if cfg.anilist.token.is_empty() {
        r.errors.push("no AniList token (run `mediator anilist login`)".into());
        return r;
    }
    if title.lib != "anime" || title.source != "local" {
        r.errors.push("only local anime can be scored".into());
        return r;
    }
    let (rec, problem) = resolve_info(title, info, fetch);
    let Some(rec) = rec else {
        r.errors.push(problem);
        return r;
    };
    let seasons = media_seasons(title, &rec);
    if seasons.is_empty() {
        r.errors.push("no AniList seasons in the info record".into());
        return r;
    }
    let chosen = match pick_season(title, state, &seasons, season, "season {season} is not in the AniList info ({labels})") {
        Ok(c) => c,
        Err(e) => {
            r.errors.push(e);
            return r;
        }
    };
    r.media_id = chosen.1;
    r.season = chosen.0;
    r.label = chosen.2.clone();
    let owned;
    let client = match client { Some(c) => c, None => { owned = Client::new(&cfg.anilist.token, cfg.anilist.user_id); &owned } };
    let (viewer, media) = match client.score_context(r.media_id) {
        Ok(x) => x,
        Err(e) => {
            r.errors.push(e.message);
            return r;
        }
    };
    let entry = &media["mediaListEntry"];
    if !truthy(entry) {
        r.errors.push("not on your AniList list; add it before scoring".into());
        return r;
    }
    let fmt = viewer["mediaListOptions"]["scoreFormat"].as_str().filter(|s| !s.is_empty()).unwrap_or("POINT_100").to_string();
    let (maximum, step) = score_format(&fmt);
    if value < 0.0 || value > maximum {
        r.errors.push(format!("score must be between 0 and {} for {fmt}", g(maximum)));
        return r;
    }
    let steps = value / step;
    if (steps - steps.round()).abs() > 1e-9 {
        r.errors.push(format!("score must be in steps of {} for {fmt}", g(step)));
        return r;
    }
    r.value = Some(value);
    r.score_format = fmt.clone();
    r.raw = Some(score_to_raw(value, &fmt));
    r.old_score = entry["score"].as_f64();
    if !dry_run {
        if let Err(e) = client.set_score(r.media_id, r.raw.unwrap()) {
            r.errors.push(e.message);
        }
    }
    r
}

fn g(x: f64) -> String {
    if x == x.trunc() { format!("{}", x as i64) } else { format!("{x}") }
}

// ---- failed pushes remembered for a later retry ----

static PENDING_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

fn read_pending(path: &std::path::Path) -> Map<String, Value> {
    match crate::fileio::read_json(path) {
        Value::Object(m) => m,
        _ => Map::new(),
    }
}

/// Titles whose last push failed; the local DB still has the truth.
pub fn pending() -> Map<String, Value> {
    let _g = PENDING_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    read_pending(&pending_path())
}
pub fn pending_ids() -> Vec<String> {
    let mut v: Vec<String> = pending().keys().cloned().collect();
    v.sort();
    v
}
pub fn pending_count() -> usize {
    pending().len()
}
pub fn mark_pending(title_id: &str, error: &str) {
    let _g = PENDING_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let path = pending_path();
    let mut d = read_pending(&path);
    d.insert(title_id.into(), json!({"at": crate::state::now(), "error": error.chars().take(300).collect::<String>()}));
    let _ = crate::fileio::atomic_write_text(&path, &Value::Object(d).to_string(), 0o644);
}
pub fn clear_pending(title_id: &str) {
    let _g = PENDING_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let path = pending_path();
    let mut d = read_pending(&path);
    if d.remove(title_id).is_some() {
        let _ = crate::fileio::atomic_write_text(&path, &Value::Object(d).to_string(), 0o644);
    }
}

// ---- automatic pushes: one worker, so episode 2 can never land before episode 1 ----

struct Job {
    title: Title,
    cfg: Config,
}
struct Queue {
    tx: Option<std::sync::mpsc::Sender<Job>>,
    pending: HashSet<String>,
    outstanding: usize,
}
static QUEUE: std::sync::LazyLock<std::sync::Mutex<Queue>> = std::sync::LazyLock::new(|| std::sync::Mutex::new(Queue { tx: None, pending: HashSet::new(), outstanding: 0 }));

/// Queue a title for a background push. Returns false when auto-sync is off.
pub fn schedule(title: &Title, cfg: &Config) -> bool {
    if cfg.anilist.token.is_empty() || !cfg.anilist.auto || title.lib != "anime" || title.source != "local" {
        return false;
    }
    let mut q = QUEUE.lock().unwrap();
    if !q.pending.insert(title.id.clone()) {
        return false;
    }
    q.outstanding += 1;
    if q.tx.is_none() {
        let (tx, rx) = std::sync::mpsc::channel::<Job>();
        q.tx = Some(tx);
        std::thread::Builder::new().name("mediator-anilist".into()).spawn(move || {
            for job in rx {
                drain_one(&job);
                let mut q = QUEUE.lock().unwrap();
                q.pending.remove(&job.title.id);
                q.outstanding -= 1;
            }
        }).ok();
    }
    let _ = q.tx.as_ref().unwrap().send(Job { title: title.clone(), cfg: cfg.clone() });
    true
}

fn drain_one(job: &Job) {
    let run = std::panic::catch_unwind(|| {
        let state = State::open(&crate::state::default_path()).ok();
        let result = match &state {
            Some(s) => sync_title(&job.title, s, &job.cfg, None, None, false, None, None, true, None),
            None => return Err("could not open the progress database".to_string()),
        };
        Ok(result)
    });
    match run {
        Ok(Ok(result)) => {
            if !result.errors.is_empty() {
                mark_pending(&job.title.id, &result.errors.join("; "));
            } else if result.skipped.iter().any(|s| s.reason.contains("no AniList info")) {
                mark_pending(&job.title.id, "no AniList info cached");
            } else {
                clear_pending(&job.title.id);
            }
        }
        Ok(Err(e)) => mark_pending(&job.title.id, &e),
        Err(_) => mark_pending(&job.title.id, "panic in background sync"),
    }
}

/// Wait for queued pushes, up to `timeout`; the local state stays the source of truth.
pub fn flush(timeout: f64) -> bool {
    let end = std::time::Instant::now() + Duration::from_secs_f64(timeout);
    while std::time::Instant::now() < end {
        if QUEUE.lock().unwrap().outstanding == 0 {
            return true;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cfg() -> AniListConfig {
        let mut c = Config::default().anilist;
        c.dates = false;
        c
    }
    fn cand(p: i64, complete: bool) -> Candidate {
        Candidate { media_id: 7, season: 1, progress: p, complete, label: "S01".into(), total: Some(12) }
    }

    #[test]
    fn never_lowers_progress() {
        let media = json!({"episodes": 12, "mediaListEntry": {"status": "CURRENT", "progress": 5}});
        let (saves, skip) = decide(&cand(3, false), &media, &cfg(), None);
        assert!(saves.is_empty());
        assert_eq!(skip.unwrap().reason, "already at episode 5");
        let (saves, _) = decide(&cand(6, false), &media, &cfg(), None);
        assert_eq!(saves[0].progress, 6);
        assert_eq!(saves[0].status.as_deref(), Some("CURRENT"));
    }

    #[test]
    fn dropped_and_completed_are_left_alone() {
        let dropped = json!({"episodes": 12, "mediaListEntry": {"status": "DROPPED", "progress": 1}});
        assert!(decide(&cand(4, false), &dropped, &cfg(), None).1.is_some());
        let done = json!({"episodes": 12, "mediaListEntry": {"status": "COMPLETED", "progress": 12}});
        assert!(decide(&cand(4, false), &done, &cfg(), None).1.is_some());
    }

    #[test]
    fn last_episode_completes_and_missing_needs_opt_in() {
        let media = json!({"episodes": 12, "mediaListEntry": {"status": "CURRENT", "progress": 11}});
        let (saves, _) = decide(&cand(12, true), &media, &cfg(), None);
        assert_eq!(saves[0].status.as_deref(), Some("COMPLETED"));
        let none = json!({"episodes": 12, "mediaListEntry": null});
        assert!(decide(&cand(1, false), &none, &cfg(), None).1.is_some());
        let mut c = cfg();
        c.add_missing = true;
        assert_eq!(decide(&cand(1, false), &none, &c, None).0[0].status.as_deref(), Some("CURRENT"));
    }

    #[test]
    fn score_conversion_and_token() {
        assert_eq!(score_to_raw(7.5, "POINT_10_DECIMAL"), 75);
        assert_eq!(score_to_raw(4.0, "POINT_5"), 80);
        assert_eq!(score_to_raw(2.0, "POINT_3"), 50);
        assert_eq!(score_to_raw(85.0, "POINT_100"), 85);
        assert_eq!(token_from_input("http://x/#access_token=abc.def&token_type=Bearer"), "abc.def");
        assert_eq!(token_from_input("  plain "), "plain");
    }

    #[test]
    fn graphql_errors_surface() {
        let e = parse_response(br#"{"errors":[{"message":"Invalid token","status":400}]}"#).unwrap_err();
        assert_eq!((e.message.as_str(), e.status), ("Invalid token", Some(400)));
        assert_eq!(parse_response(br#"{"data":{"a":1}}"#).unwrap()["a"], 1);
    }
}
