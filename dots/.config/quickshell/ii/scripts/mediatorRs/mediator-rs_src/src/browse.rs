//! What the Streaming tab shows before anything plays: Stremio (Cinemeta) catalogs, search,
//! titles and stream lists, the AniList anime catalogs, and remembering a hand-picked stream.
//! Replaces the shell's `scripts/stremio/stremio.py` and `scripts/anime/browse.py`; every
//! command prints one JSON value, and a failure is `{"error": "..."}` (the interface never crashes).
use crate::fileio;
use crate::http::Request;
use crate::parse::rx;
use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};
use std::path::PathBuf;

pub const CINEMETA: &str = "https://v3-cinemeta.strem.io";
const UA: &str = "ii-shell-stremio/1";
const CATALOG_TTL: f64 = 30.0 * 60.0;
const SEARCH_TTL: f64 = 10.0 * 60.0;
const META_TTL: f64 = 60.0 * 60.0;

type Res = Result<Value, String>;

fn quote(s: &str) -> String {
    percent_encoding::utf8_percent_encode(s, percent_encoding::NON_ALPHANUMERIC).to_string()
}

fn http_dir() -> PathBuf {
    crate::config::cache_dir().join("http")
}

fn cache_file(key: &str) -> PathBuf {
    http_dir().join(format!("{}.json", fileio::hex(&Sha256::digest(key.as_bytes()))))
}

fn fresh(path: &std::path::Path, ttl: f64) -> Option<Value> {
    let age = std::fs::metadata(path).ok()?.modified().ok()?.elapsed().ok()?.as_secs_f64();
    if age >= ttl {
        return None;
    }
    serde_json::from_str(&std::fs::read_to_string(path).ok()?).ok()
}

/// GET with a small disk cache: catalogs and metadata change slowly, so a repeat visit is
/// instant. A stale copy still answers when the network does not.
fn cached_fetch(url: &str, ttl: f64) -> Res {
    let path = cache_file(url);
    if let Some(v) = fresh(&path, ttl) {
        return Ok(v);
    }
    match Request::get(url).header("Content-Type", "application/json").agent(UA).json() {
        Ok(v) => {
            let _ = fileio::atomic_write_text(&path, &v.to_string(), 0o644);
            Ok(v)
        }
        Err(e) => match std::fs::read_to_string(&path).ok().and_then(|t| serde_json::from_str(&t).ok()) {
            Some(stale) => Ok(stale), // stale beats nothing
            None => Err(e.describe()),
        },
    }
}

fn truthy(v: &Value) -> bool {
    match v {
        Value::Null => false,
        Value::Bool(b) => *b,
        Value::Number(n) => n.as_f64().map(|f| f != 0.0).unwrap_or(true),
        Value::String(s) => !s.is_empty(),
        Value::Array(a) => !a.is_empty(),
        Value::Object(o) => !o.is_empty(),
    }
}

/// Python's `a or b or c`.
fn first(vals: &[&Value]) -> Value {
    vals.iter().find(|v| truthy(v)).map(|v| (*v).clone()).unwrap_or(Value::Null)
}

/// `str(value or "")`
fn text(v: &Value) -> String {
    match v {
        Value::Null => String::new(),
        Value::String(s) => s.clone(),
        Value::Bool(false) => String::new(),
        other => other.to_string(),
    }
}

fn or_str(v: &Value) -> Value {
    json!(text(v))
}

fn or_list(vals: &[&Value]) -> Value {
    let v = first(vals);
    if v.is_null() { json!([]) } else { v }
}

fn card(m: &Value) -> Value {
    let year: String = text(&first(&[&m["releaseInfo"], &m["year"]])).chars().take(9).collect();
    json!({
        "id": first(&[&m["imdb_id"], &m["id"]]),
        "type": m["type"],
        "name": or_str(&m["name"]),
        "year": year,
        "poster": or_str(&m["poster"]),
        "rating": or_str(&m["imdbRating"]),
        "background": or_str(&m["background"]),
        "logo": or_str(&m["logo"]),
        "description": or_str(&m["description"]),
        "genres": or_list(&[&m["genres"], &m["genre"]]),
        "runtime": or_str(&m["runtime"]),
    })
}

fn metas(v: &Value) -> Vec<Value> {
    v["metas"].as_array().cloned().unwrap_or_default()
}

pub fn search(query: &str) -> Res {
    let one = |kind: &str| -> Vec<Value> {
        let url = format!("{CINEMETA}/catalog/{kind}/top/search={}.json", quote(query));
        cached_fetch(&url, SEARCH_TTL).map(|v| metas(&v).iter().take(12).map(card).collect()).unwrap_or_default()
    };
    let (movies, series) = std::thread::scope(|s| {
        let m = s.spawn(|| one("movie"));
        let t = s.spawn(|| one("series"));
        (m.join().unwrap_or_default(), t.join().unwrap_or_default())
    });
    Ok(Value::Array(movies.into_iter().chain(series).collect()))
}

pub fn top(kind: &str) -> Res {
    let v = cached_fetch(&format!("{CINEMETA}/catalog/{kind}/top.json"), CATALOG_TTL)?;
    Ok(Value::Array(metas(&v).iter().take(30).map(card).collect()))
}

/// One page (~50) of a Cinemeta catalog: sort is popular|top|year, filter a genre (or a year for
/// sort=year), skip the number of titles already shown.
pub fn browse(kind: &str, sort: &str, filter: &str, skip: i64) -> Res {
    let catalog = match sort { "popular" => "top", "top" => "imdbRating", "year" => "year", _ => "imdbRating" };
    let mut extras = vec![];
    if !filter.is_empty() {
        extras.push(format!("genre={}", quote(filter)));
    }
    if skip > 0 {
        extras.push(format!("skip={skip}"));
    }
    let tail = if extras.is_empty() { String::new() } else { format!("/{}", extras.join("&")) };
    let v = cached_fetch(&format!("{CINEMETA}/catalog/{kind}/{catalog}{tail}.json"), CATALOG_TTL)?;
    Ok(Value::Array(metas(&v).iter().map(card).collect()))
}

/// Cinemeta leaves HTML entities in names and text (O&apos;Connor).
fn clean(v: &Value) -> Value {
    match v {
        Value::String(s) => json!(html_escape::decode_html_entities(s).into_owned()),
        Value::Array(a) => Value::Array(a.iter().map(clean).collect()),
        Value::Object(o) => Value::Object(o.iter().map(|(k, x)| (k.clone(), clean(x))).collect()),
        other => other.clone(),
    }
}

fn num(v: &Value) -> f64 {
    v.as_f64().unwrap_or(0.0)
}

pub fn meta(kind: &str, ident: &str) -> Res {
    let raw = cached_fetch(&format!("{CINEMETA}/meta/{kind}/{}.json", quote(ident)), META_TTL)?;
    let m = clean(&raw["meta"]);
    let mut videos: Vec<Value> = vec![];
    for v in m["videos"].as_array().cloned().unwrap_or_default() {
        if !truthy(&v["season"]) && kind == "series" {
            continue; // specials without a season number
        }
        let overview = text(&first(&[&v["overview"], &v["description"]])).replace('\r', "");
        let episode = first(&[&v["episode"], &v["number"]]);
        videos.push(json!({
            "id": v["id"],
            "season": first(&[&v["season"]]).as_i64().map(|n| json!(n)).unwrap_or(json!(0)),
            "episode": if episode.is_null() { json!(0) } else { episode },
            "title": text(&first(&[&v["title"], &v["name"]])),
            "released": text(&v["released"]).chars().take(10).collect::<String>(),
            "thumbnail": or_str(&v["thumbnail"]),
            "overview": overview.trim(),
        }));
    }
    videos.sort_by(|a, b| (num(&a["season"]), num(&a["episode"])).partial_cmp(&(num(&b["season"]), num(&b["episode"]))).unwrap_or(std::cmp::Ordering::Equal));
    if kind == "series" && !videos.is_empty() {
        warm_episode_cache(ident, &videos);
    }
    let mut out = card(&m).as_object().cloned().unwrap_or_default();
    let take = |v: &Value, n: usize| -> Value { Value::Array(v.as_array().map(|a| a.iter().take(n).cloned().collect()).unwrap_or_default()) };
    out.insert("description".into(), or_str(&m["description"]));
    out.insert("runtime".into(), or_str(&m["runtime"]));
    out.insert("genres".into(), or_list(&[&m["genres"]]));
    out.insert("background".into(), or_str(&m["background"]));
    out.insert("logo".into(), or_str(&m["logo"]));
    out.insert("cast".into(), take(&m["cast"], 12));
    out.insert("director".into(), or_list(&[&m["director"]]));
    out.insert("country".into(), or_str(&m["country"]));
    out.insert("writer".into(), take(&m["writer"], 4));
    out.insert("released".into(), json!(text(&m["released"]).chars().take(10).collect::<String>()));
    out.insert("awards".into(), or_str(&m["awards"]));
    out.insert("status".into(), or_str(&m["status"]));
    let trailer = m["trailers"].as_array().and_then(|t| t.iter().find_map(|t| t["source"].as_str().filter(|s| !s.is_empty()))).unwrap_or("");
    out.insert("trailer".into(), json!(trailer));
    out.insert("videos".into(), Value::Array(videos));
    Ok(Value::Object(out))
}

/// Share the episode list with the player (same file, same shape as its own fetch), so pressing
/// Play right after opening a title needs no second Cinemeta request.
fn warm_episode_cache(imdb: &str, videos: &[Value]) {
    let eps: Vec<Value> = videos.iter().filter(|v| truthy(&v["id"]) && truthy(&v["season"])).map(|v| json!({
        "id": v["id"], "number": format!("S{:02}E{:02}", v["season"].as_i64().unwrap_or(0), v["episode"].as_i64().unwrap_or(0)), "title": v["title"],
    })).collect();
    if !eps.is_empty() {
        crate::stremio::store_episodes(imdb, &eps);
    }
}

fn parse_stream(s: &Value, addon: &str) -> Value {
    let title = text(&first(&[&s["title"], &s["description"]]));
    let name = text(&s["name"]).replace('\n', " ");
    let seeds = rx(r"👤\s*(\d+)").captures(title.as_str()).ok().flatten().and_then(|c| c[1].parse::<i64>().ok()).unwrap_or(0);
    let size = rx(r"💾\s*([\d.]+\s*[KMGT]B)").captures(title.as_str()).ok().flatten().map(|c| c[1].to_string()).unwrap_or_default();
    let quality = rx(r"(?i)\b(2160p|4k|1080p|720p|480p)\b").captures(format!("{name} {title}").as_str()).ok().flatten().map(|c| c[1].to_lowercase()).unwrap_or_default();
    let hints = &s["behaviorHints"];
    json!({
        "name": name, "title": title.replace('\n', "  ·  "), "seeds": seeds, "size": size, "quality": quality,
        "infoHash": or_str(&s["infoHash"]),
        "fileIdx": if s["fileIdx"].is_null() { json!(-1) } else { s["fileIdx"].clone() },
        "url": or_str(&s["url"]), "filename": or_str(&hints["filename"]), "bingeGroup": or_str(&hints["bingeGroup"]),
        "sources": or_list(&[&s["sources"]]), "addon": addon,
    })
}

pub fn streams(kind: &str, ident: &str) -> Res {
    let mut out: Vec<Value> = vec![];
    for base in crate::stremio::addons(&crate::stremio::Endpoints::default()) {
        let url = format!("{base}/stream/{kind}/{}.json", quote(ident));
        let Ok(data) = Request::get(&url).header("Content-Type", "application/json").agent(UA).timeout(25.0).json() else { continue };
        out.extend(data["streams"].as_array().cloned().unwrap_or_default().iter()
            .filter(|s| truthy(&s["infoHash"]) || truthy(&s["url"])).map(|s| parse_stream(s, &base)));
    }
    out.sort_by_key(|s| std::cmp::Reverse(s["seeds"].as_i64().unwrap_or(0)));
    out.truncate(40);
    Ok(Value::Array(out))
}

/// Remember the stream picked for an episode; the player reads this file.
pub fn choose(args: &Value) -> Res {
    let show = text(&args["showId"]);
    let ep = text(&args["episodeId"]);
    if show.is_empty() || ep.is_empty() {
        return Err("showId and episodeId are required".into());
    }
    let path = crate::stremio::store_path();
    if truthy(&args["clear"]) {
        // "Use the direct stream": forget a hand-picked torrent so the player resolves normally
        fileio::update_json(&path, |d| {
            d.remove(&format!("{show}|{ep}"));
            d.remove(&format!("{show}|last"));
        }).map_err(|e| e.to_string())?;
        return Ok(json!({"ok": true}));
    }
    let mut keep = Map::new();
    for k in ["infoHash", "fileIdx", "url", "quality", "bingeGroup", "filename"] {
        keep.insert(k.into(), args.get(k).cloned().unwrap_or(Value::Null));
    }
    keep.insert("chosen".into(), json!(true)); // picked by hand: played instead of the direct HLS stream
    let keep = Value::Object(keep);
    fileio::update_json(&path, |d| {
        d.insert(format!("{show}|{ep}"), keep.clone());
        d.insert(format!("{show}|last"), keep.clone());
    }).map_err(|e| e.to_string())?;
    Ok(json!({"ok": true}))
}

// ---- anime catalogs (AniList, no login) ----

const ANILIST: &str = "https://graphql.anilist.co";
const ANIME_QUERY: &str = "
query ($sort: [MediaSort], $search: String, $season: MediaSeason, $year: Int, $id: Int) {
  Page(perPage: 30) {
    media(id: $id, type: ANIME, sort: $sort, search: $search, season: $season, seasonYear: $year, isAdult: false) {
      id format episodes seasonYear averageScore description(asHtml: false) genres duration
      title { romaji english }
      bannerImage status season source
      studios(isMain: true) { nodes { name } }
      trailer { id site }
      coverImage { extraLarge large }
    }
  }
}
";

fn current_season() -> (&'static str, i64) {
    let secs = crate::state::now() as i64;
    let days = secs.div_euclid(86400);
    // civil date from days since 1970-01-01
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z.rem_euclid(146097);
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + if month <= 2 { 1 } else { 0 };
    (["WINTER", "WINTER", "WINTER", "SPRING", "SPRING", "SPRING", "SUMMER", "SUMMER", "SUMMER", "FALL", "FALL", "FALL"][(month - 1) as usize], year)
}

fn title_case(s: &str) -> String {
    s.replace('_', " ").split(' ').map(|w| {
        let mut c = w.chars();
        match c.next() {
            Some(f) => f.to_uppercase().collect::<String>() + &c.as_str().to_lowercase(),
            None => String::new(),
        }
    }).collect::<Vec<_>>().join(" ")
}

pub fn anime(mode: &str, arg: &str) -> Res {
    let variables = match mode {
        "season" => { let (s, y) = current_season(); json!({"sort": ["POPULARITY_DESC"], "season": s, "year": y}) }
        "popular" => json!({"sort": ["POPULARITY_DESC"]}),
        "top" => json!({"sort": ["SCORE_DESC"]}),
        "media" => json!({"id": arg.parse::<i64>().map_err(|_| "media needs an AniList id".to_string())?}),
        "search" => json!({"sort": ["SEARCH_MATCH"], "search": arg}),
        _ => json!({"sort": ["TRENDING_DESC"]}),
    };
    // Lists change slowly: a repeat visit is answered from disk (a searched title for a few
    // minutes, a list for half an hour). A stale copy covers a dead network.
    let ttl = if mode == "search" { 600.0 } else if mode == "media" { 3600.0 } else { 1800.0 };
    let path = http_dir().join(format!("anilist-{}.json", fileio::hex(&Sha256::digest(format!("{variables}v2").as_bytes()))));
    let media = match fresh(&path, ttl) {
        Some(m) => m,
        None => {
            let body = json!({"query": ANIME_QUERY, "variables": variables}).to_string();
            let fetched = Request::get(ANILIST).header("Content-Type", "application/json").header("Accept", "application/json")
                .agent("ii-shell-anime/1").post(body.as_bytes()).json().map(|v| v["data"]["Page"]["media"].clone());
            match fetched {
                Ok(m) if m.is_array() => {
                    let _ = fileio::atomic_write_text(&path, &m.to_string(), 0o644);
                    m
                }
                other => match std::fs::read_to_string(&path).ok().and_then(|t| serde_json::from_str::<Value>(&t).ok()) {
                    Some(stale) => stale,
                    None => return Err(match other { Err(e) => e.describe(), _ => "AniList sent no list".into() }),
                },
            }
        }
    };
    let cards: Vec<Value> = media.as_array().cloned().unwrap_or_default().iter().map(|m| {
        let t = &m["title"];
        let cover = &m["coverImage"];
        let desc = rx(r"<[^>]+>").replace_all(&text(&m["description"]).replace("<br>", " "), "").trim().to_string();
        let trailer = if m["trailer"]["site"] == "youtube" { m["trailer"]["id"].clone() } else { json!("") };
        json!({
            "id": m["id"],
            "title": text(&first(&[&t["english"], &t["romaji"]])),
            "search": text(&first(&[&t["romaji"], &t["english"]])),
            "poster": text(&first(&[&cover["extraLarge"], &cover["large"]])),
            "year": first(&[&m["seasonYear"]]).as_i64().map(|n| json!(n)).unwrap_or(json!("")),
            "rating": if truthy(&m["averageScore"]) { json!(format!("{:.1}", num(&m["averageScore"]) / 10.0)) } else { json!("") },
            "format": or_str(&m["format"]),
            "episodes": first(&[&m["episodes"]]).as_i64().map(|n| json!(n)).unwrap_or(json!(0)),
            "description": desc,
            "genres": or_list(&[&m["genres"]]),
            "banner": or_str(&m["bannerImage"]),
            "runtime": if truthy(&m["duration"]) { json!(format!("{} min", m["duration"])) } else { json!("") },
            "status": title_case(&text(&m["status"])),
            "season": title_case(&text(&m["season"])),
            "source": title_case(&text(&m["source"])),
            "studios": m["studios"]["nodes"].as_array().map(|a| a.iter().filter_map(|n| n["name"].as_str().filter(|s| !s.is_empty()).map(|s| json!(s))).collect::<Vec<_>>()).unwrap_or_default(),
            "trailer": trailer,
        })
    }).collect();
    Ok(Value::Array(cards))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cards_take_the_first_filled_field() {
        let c = card(&json!({"id": "tt1", "imdb_id": "", "type": "movie", "name": "Dune", "releaseInfo": "", "year": 2021, "genre": ["Sci-Fi"]}));
        assert_eq!(c["id"], "tt1");
        assert_eq!(c["year"], "2021");
        assert_eq!(c["genres"], json!(["Sci-Fi"]));
        assert_eq!(c["poster"], "");
    }

    #[test]
    fn streams_are_read_the_way_the_picker_expects() {
        let s = parse_stream(&json!({"name": "Torrentio\n1080p", "title": "Dune.2021.mkv\n👤 42 💾 3.1 GB", "infoHash": "abc", "behaviorHints": {"filename": "Dune.mkv"}}), "https://a");
        assert_eq!((s["seeds"].as_i64(), s["size"].as_str(), s["quality"].as_str()), (Some(42), Some("3.1 GB"), Some("1080p")));
        assert_eq!(s["fileIdx"], -1);
        assert_eq!(s["title"], "Dune.2021.mkv  ·  👤 42 💾 3.1 GB");
        assert_eq!(s["filename"], "Dune.mkv");
    }

    #[test]
    fn entities_and_titles_are_cleaned() {
        assert_eq!(clean(&json!({"a": ["O&apos;Connor"]})), json!({"a": ["O'Connor"]}));
        assert_eq!(title_case("NOT_YET_RELEASED"), "Not Yet Released");
        let (season, year) = current_season();
        assert!(["WINTER", "SPRING", "SUMMER", "FALL"].contains(&season) && year >= 2025);
    }
}
