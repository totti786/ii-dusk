//! Everything worth knowing about a title, fetched once and kept on disk (port of `mediator/info.py`).
//! Sources, tried in order and merged into one shape: `.nfo` next to the media (always wins), then
//! AniList (+ Kitsu/Jikan episodes) for anime, TVmaze for shows, Cinemeta for movies.
//! `find()` never touches the network; `fetch()` does and remembers a miss for two weeks.
use crate::catalog::Title;
use crate::meta::{self, minutes, num, text};
use crate::parse::{norm_key, rx};
use crate::posters::{self, best, q, slug, Http, HttpFail};
use serde_json::{json, Map, Value};
use std::path::{Path, PathBuf};
use unicode_normalization::UnicodeNormalization;

pub const MISS_RETRY_DAYS: f64 = 14.0;
pub const SCHEMA: i64 = 2;
pub const SEASON_KINDS: [&str; 3] = ["TV", "TV_SHORT", "ONA"];
pub const ANILIST_URL: &str = "https://graphql.anilist.co";

const MEDIA_FIELDS: &str = "\n  id idMal title { romaji english native } synonyms description(asHtml: false)\n  genres tags { name rank isMediaSpoiler } averageScore seasonYear season status format episodes duration\n  startDate { year } studios(isMain: true) { nodes { name } } bannerImage coverImage { extraLarge color }\n  trailer { id site } streamingEpisodes { title thumbnail } nextAiringEpisode { episode airingAt }\n  relations { edges { relationType node { id idMal type format title { romaji english } episodes seasonYear } } }\n  characters(sort: [ROLE, RELEVANCE], perPage: 10) { edges { role node { name { full } image { large } } } }\n";

fn q_search() -> String {
    format!("query($q:String){{Page(perPage:10){{media(search:$q,type:ANIME){{{MEDIA_FIELDS}}}}}}}")
}
fn q_id() -> String {
    format!("query($id:Int){{Media(id:$id,type:ANIME){{{MEDIA_FIELDS}}}}}")
}

pub fn info_dir() -> PathBuf {
    posters::cache_root().join("info")
}
pub fn art_dir() -> PathBuf {
    posters::cache_root().join("art")
}

fn path(title: &Title, dir: &Path) -> PathBuf {
    dir.join(format!("{}.json", slug(&title.id)))
}
fn read(title: &Title, dir: &Path) -> Option<Value> {
    serde_json::from_str(&std::fs::read_to_string(path(title, dir)).ok()?).ok()
}
fn write(title: &Title, data: &Value, dir: &Path) {
    let _ = crate::fileio::atomic_write_text(&path(title, dir), &data.to_string(), 0o644);
}

pub fn find(title: &Title) -> Option<Value> {
    find_in(title, &info_dir())
}
pub fn find_in(title: &Title, dir: &Path) -> Option<Value> {
    read(title, dir).filter(|d| d.as_object().map(|o| !o.is_empty() && !o.contains_key("miss")).unwrap_or(false) && !(d["miss"].as_f64().map(|m| m != 0.0).unwrap_or(false)))
}

pub fn banner_path(title: &Title, dir: &Path) -> Option<PathBuf> {
    let base = dir.join(format!("{}-banner", slug(&title.id)));
    [".jpg", ".png", ".webp"].iter().map(|e| PathBuf::from(format!("{}{e}", base.display()))).find(|p| p.is_file())
}

fn store_banner(title: &Title, url: &str, http: &dyn Http, dir: &Path) -> Option<PathBuf> {
    let data = http.bytes(url).ok()?;
    if !posters::looks_like_image(&data) {
        return None;
    }
    let base = dir.join(format!("{}-banner", slug(&title.id)));
    let target = PathBuf::from(format!("{}{}", base.display(), posters::ext_for(&data)));
    std::fs::create_dir_all(dir).ok()?;
    for ext in [".jpg", ".png", ".webp"] {
        let _ = std::fs::remove_file(format!("{}{ext}", base.display()));
    }
    let tmp = PathBuf::from(format!("{}.tmp{}", target.display(), std::process::id()));
    std::fs::write(&tmp, &data).ok()?;
    std::fs::rename(tmp, &target).ok()?;
    Some(target)
}

// ---- .nfo ----

fn nfo_candidates(title: &Title) -> Vec<PathBuf> {
    if title.source != "local" || title.entries.is_empty() {
        return vec![];
    }
    let mut out: Vec<PathBuf> = vec![];
    for e in &title.entries {
        let root = &e.path[..e.path.len().saturating_sub(e.rel.len())];
        let parts: Vec<&str> = e.rel.split('/').collect();
        if title.lib == "movies" {
            let p = Path::new(&e.path);
            out.push(p.with_extension("nfo"));
            out.push(p.parent().unwrap_or(Path::new("")).join("movie.nfo"));
        } else if parts.len() > 1 {
            out.push(Path::new(root).join(parts[0]).join("tvshow.nfo"));
        }
    }
    let mut seen: Vec<PathBuf> = vec![];
    for p in out {
        if !seen.contains(&p) {
            seen.push(p);
        }
    }
    seen
}

fn child_text(node: roxmltree::Node, tag_path: &str) -> String {
    let mut cur = Some(node);
    for tag in tag_path.split('/') {
        cur = cur.and_then(|n| n.children().find(|c| c.is_element() && c.tag_name().name() == tag));
    }
    cur.and_then(|n| n.text()).map(|t| t.trim().to_string()).unwrap_or_default()
}

/// Plot, rating, genres, year, studio and cast from a Kodi-style .nfo, if there is one.
pub fn read_nfo(title: &Title) -> Value {
    for p in nfo_candidates(title) {
        let Ok(text_) = std::fs::read_to_string(&p) else { continue };
        let Ok(doc) = roxmltree::Document::parse(&text_) else { continue };
        let root = doc.root_element();
        let txt = |t: &str| child_text(root, t);
        let rating: Option<f64> = {
            let r = if txt("rating").is_empty() { txt("ratings/rating/value") } else { txt("rating") };
            r.parse::<f64>().ok().map(|x| (x * 10.0).round() / 10.0).filter(|x| *x != 0.0)
        };
        let ys = { let y = txt("year"); if y.is_empty() { let p = txt("premiered"); if p.is_empty() { txt("releasedate") } else { p } } else { y } };
        let year = rx(r"\A\d{4}").find(ys.as_str()).ok().flatten().and_then(|m| m.as_str().parse::<i64>().ok());
        let cast: Vec<Value> = root.children().filter(|c| c.is_element() && c.tag_name().name() == "actor")
            .map(|a| child_text(a, "name")).filter(|n| !n.is_empty()).take(12).map(|n| json!({"name": n})).collect();
        let genres: Vec<Value> = root.children().filter(|c| c.is_element() && c.tag_name().name() == "genre")
            .filter_map(|g| g.text()).map(|t| json!(t.trim())).collect();
        let plot = { let p = txt("plot"); if p.is_empty() { txt("outline") } else { p } };
        return clean(vec![
            ("description", json!(text(&json!(plot)))), ("rating", rating.map(|r| json!(r)).unwrap_or(Value::Null)),
            ("genres", json!(genres)), ("year", year.map(|y| json!(y)).unwrap_or(Value::Null)), ("studio", json!(txt("studio"))),
            ("certification", json!(txt("mpaa"))), ("cast", json!(cast)), ("nfo", json!(p.to_string_lossy())),
        ]);
    }
    json!({})
}

// ---- helpers ----

fn empty(v: &Value) -> bool {
    match v {
        Value::Null => true,
        Value::String(s) => s.is_empty() || s == "N/A",
        Value::Array(a) => a.is_empty(),
        Value::Object(o) => o.is_empty(),
        _ => false,
    }
}
/// Drop empty values (`None`, `""`, `[]`, `{}`, `"N/A"`).
pub fn clean(pairs: Vec<(&str, Value)>) -> Value {
    Value::Object(pairs.into_iter().filter(|(_, v)| !empty(v)).map(|(k, v)| (k.to_string(), v)).collect())
}
fn truthy(v: &Value) -> bool {
    match v { Value::Null => false, Value::Bool(b) => *b, Value::Number(n) => n.as_f64() != Some(0.0), Value::String(s) => !s.is_empty(), Value::Array(a) => !a.is_empty(), Value::Object(o) => !o.is_empty() }
}
fn or(a: &Value, b: &Value) -> Value {
    if truthy(a) { a.clone() } else { b.clone() }
}

fn anilist(http: &dyn Http, query: &str, vars: Value) -> Result<Value, HttpFail> {
    let d = http.post_json(ANILIST_URL, &json!({"query": query, "variables": vars}))?;
    Ok(d.map(|d| d["data"].clone()).filter(|d| d.is_object()).unwrap_or_else(|| json!({})))
}

/// `norm_key` with accents removed: AniList writes "Rozé", a folder says "Roze".
pub fn fold(name: &str) -> String {
    norm_key(&name.nfkd().filter(|c| !unicode_normalization::char::is_combining_mark(*c)).collect::<String>())
}

fn media_names(m: &Value) -> Vec<String> {
    let t = &m["title"];
    let mut v: Vec<Value> = vec![t["romaji"].clone(), t["english"].clone(), t["native"].clone()];
    v.extend(m["synonyms"].as_array().cloned().unwrap_or_default());
    v.iter().filter_map(|x| x.as_str()).filter(|s| !s.is_empty()).map(String::from).collect()
}

/// The AniList entry for a title. With a year in the folder name the year decides (a remake shares
/// the old show's exact name); otherwise the exact name does.
pub fn pick_anime(media: &[Value], title: &Title) -> Option<Value> {
    let want = fold(&title.name);
    let mut best: Option<((bool, bool, bool, i64), Value)> = None;
    for (i, m) in media.iter().enumerate() {
        let f = m["format"].as_str();
        if !(f.is_none() || SEASON_KINDS.contains(&f.unwrap()) || matches!(f, Some("MOVIE" | "OVA" | "SPECIAL"))) {
            continue;
        }
        let names: Vec<String> = media_names(m).iter().map(|n| fold(n)).collect();
        let exact = names.contains(&want);
        let starts = names.iter().any(|n| n.starts_with(&want));
        if !(exact || starts) {
            continue;
        }
        let year = if truthy(&m["seasonYear"]) { m["seasonYear"].as_i64() } else { m["startDate"]["year"].as_i64() };
        let yr = title.year.is_some() && title.year.map(|y| y as i64) == year;
        let key = (if title.year.is_some() { yr } else { false }, exact, starts, -(i as i64));
        if best.as_ref().map(|(k, _)| key > *k).unwrap_or(true) {
            best = Some((key, m.clone()));
        }
    }
    best.map(|(_, m)| m)
}

fn titlecase(s: &str) -> String {
    s.split(' ').map(|w| { let mut c = w.chars(); c.next().map(|f| f.to_uppercase().collect::<String>() + &c.as_str().to_lowercase()).unwrap_or_default() }).collect::<Vec<_>>().join(" ")
}

pub fn anime_record(m: &Value) -> Value {
    let t = &m["title"];
    let mut tags: Vec<&Value> = m["tags"].as_array().map(|a| a.iter().filter(|x| !truthy(&x["isMediaSpoiler"])).collect()).unwrap_or_default();
    tags.sort_by_key(|x| -x["rank"].as_i64().unwrap_or(0)); // stable
    let tr = &m["trailer"];
    let url = match (tr["site"].as_str(), tr["id"].as_str().filter(|i| !i.is_empty())) {
        (Some("youtube"), Some(id)) => json!(format!("https://www.youtube.com/watch?v={id}")),
        (Some("dailymotion"), Some(id)) => json!(format!("https://www.dailymotion.com/video/{id}")),
        _ => Value::Null,
    };
    let nxt = &m["nextAiringEpisode"];
    let score = &m["averageScore"];
    let studio = m["studios"]["nodes"].as_array().and_then(|a| a.first()).map(|n| n["name"].clone()).unwrap_or(Value::Null);
    let cast: Vec<Value> = m["characters"]["edges"].as_array().cloned().unwrap_or_default().iter().map(|e| {
        let role = e["role"].as_str().map(titlecase).unwrap_or_default();
        clean(vec![("name", e["node"]["name"]["full"].clone()), ("role", json!(role)), ("image", e["node"]["image"]["large"].clone())])
    }).collect();
    let related: Vec<Value> = m["relations"]["edges"].as_array().cloned().unwrap_or_default().iter()
        .filter(|e| matches!(e["relationType"].as_str(), Some("PREQUEL" | "SEQUEL" | "SIDE_STORY" | "SPIN_OFF" | "ALTERNATIVE")) && e["node"]["type"] == "ANIME")
        .map(|e| clean(vec![
            ("relation", json!(titlecase(&e["relationType"].as_str().unwrap_or("").replace('_', " ")))),
            ("title", or(&e["node"]["title"]["english"], &e["node"]["title"]["romaji"])),
            ("format", e["node"]["format"].clone()), ("year", e["node"]["seasonYear"].clone()), ("anilist", e["node"]["id"].clone()),
        ])).collect();
    clean(vec![
        ("ids", clean(vec![("anilist", m["id"].clone()), ("mal", m["idMal"].clone())])),
        ("titles", clean(vec![("main", t["romaji"].clone()), ("english", t["english"].clone()), ("native", t["native"].clone())])),
        ("description", json!(text(&m["description"]))),
        ("genres", if truthy(&m["genres"]) { m["genres"].clone() } else { json!([]) }),
        ("tags", json!(tags.iter().take(8).map(|x| x["name"].clone()).collect::<Vec<_>>())),
        ("rating", if truthy(score) { json!((score.as_f64().unwrap_or(0.0) / 10.0 * 10.0).round() / 10.0) } else { Value::Null }),
        ("rating_source", json!("AniList")),
        ("year", or(&m["seasonYear"], &m["startDate"]["year"])),
        ("season", json!(m["season"].as_str().map(titlecase).unwrap_or_default())),
        ("status", json!(titlecase(&m["status"].as_str().unwrap_or("").replace('_', " ")))),
        ("format", m["format"].clone()), ("episodes_total", m["episodes"].clone()), ("runtime", m["duration"].clone()),
        ("studio", studio), ("banner", m["bannerImage"].clone()), ("color", m["coverImage"]["color"].clone()), ("trailer", url),
        ("next_airing", if truthy(&nxt["episode"]) { json!({"episode": nxt["episode"], "at": nxt["airingAt"]}) } else { Value::Null }),
        ("cast", json!(cast)), ("related", json!(related)),
    ])
}

fn sequel(m: &Value) -> Option<Value> {
    m["relations"]["edges"].as_array()?.iter().find_map(|e| {
        let n = &e["node"];
        (e["relationType"] == "SEQUEL" && n["type"] == "ANIME" && n["format"].as_str().map(|f| SEASON_KINDS.contains(&f)).unwrap_or(false)).then(|| n.clone())
    })
}

static JIKAN_DOWN_UNTIL: std::sync::Mutex<Option<std::time::Instant>> = std::sync::Mutex::new(None);

/// Episode names and filler flags. After a failure Jikan is left alone for five minutes.
fn jikan_episodes(mal: i64, http: &dyn Http, sleep: &dyn Fn(f64)) -> Result<Vec<Value>, HttpFail> {
    if JIKAN_DOWN_UNTIL.lock().unwrap().map(|t| std::time::Instant::now() < t).unwrap_or(false) {
        return Ok(vec![]);
    }
    let mut out = vec![];
    for page in 1..8 {
        let data = {
            let _g = meta::JIKAN_LOCK.lock().unwrap_or_else(|e| e.into_inner());
            sleep(0.45);
            match http.json(&format!("https://api.jikan.moe/v4/anime/{mal}/episodes?page={page}")) {
                Ok(d) => d,
                Err(e) => {
                    *JIKAN_DOWN_UNTIL.lock().unwrap() = Some(std::time::Instant::now() + std::time::Duration::from_secs(300));
                    return Err(e);
                }
            }
        };
        let data = data.unwrap_or(Value::Null);
        for e in data["data"].as_array().cloned().unwrap_or_default() {
            let aired = e["aired"].as_str().unwrap_or("");
            out.push(clean(vec![
                ("number", e["mal_id"].clone()), ("title", e["title"].clone()), ("title_ja", e["title_japanese"].clone()),
                ("airdate", json!(aired.chars().take(10).collect::<String>())),
                ("filler", if truthy(&e["filler"]) { json!(true) } else { Value::Null }), ("recap", if truthy(&e["recap"]) { json!(true) } else { Value::Null }),
            ]));
        }
        if !truthy(&data["pagination"]["has_next_page"]) {
            break;
        }
    }
    Ok(out)
}

/// Episode names, summaries, stills and air dates from Kitsu, found through its AniList mapping.
fn kitsu_episodes(anilist_id: i64, http: &dyn Http) -> Result<Vec<Value>, HttpFail> {
    let m = http.json(&format!("https://kitsu.io/api/edge/mappings?{}", q(&[
        ("filter[externalSite]", "anilist/anime".into()), ("filter[externalId]", anilist_id.to_string()), ("include", "item".into())])))?;
    let inc = m.as_ref().and_then(|m| m["included"].as_array()).cloned().unwrap_or_default();
    let Some(first) = inc.first() else { return Ok(vec![]) };
    let kid = first["id"].as_str().map(String::from).unwrap_or_else(|| first["id"].to_string());
    let base = format!("https://kitsu.io/api/edge/anime/{kid}/episodes?{}", q(&[("page[limit]", "20".into()), ("sort", "number".into())]));
    let first = http.json(&base)?.unwrap_or(Value::Null);
    let mut out = kitsu_rows(&first);
    let count = first["meta"]["count"].as_i64().unwrap_or(0);
    let next = |d: &Value| d["links"]["next"].as_str().filter(|s| !s.is_empty()).map(String::from);
    if next(&first).is_some() && count > 20 {
        // Kitsu serves 20 episodes a page: with the total known, the rest can be asked for together
        let urls: Vec<String> = (20..count.min(800)).step_by(20).map(|off| format!("{base}&{}", q(&[("page[offset]", off.to_string())]))).collect();
        for page in http.json_many(&urls) {
            out.extend(kitsu_rows(&page?.unwrap_or(Value::Null)));
        }
    } else if let Some(mut url) = next(&first) {
        for _ in 0..39 {
            let data = http.json(&url)?.unwrap_or(Value::Null);
            out.extend(kitsu_rows(&data));
            match next(&data) {
                Some(u) => url = u,
                None => break,
            }
        }
    }
    Ok(out)
}

fn kitsu_rows(data: &Value) -> Vec<Value> {
    let mut out = vec![];
    for e in data["data"].as_array().cloned().unwrap_or_default() {
        let a = &e["attributes"];
        if !truthy(&a["number"]) {
            continue;
        }
        let titles = &a["titles"];
        let mut name = or(&or(&a["canonicalTitle"], &titles["en_us"]), &titles["en_jp"]);
        if name.as_str().map(|n| rx(r"(?i)\Aepisode\s*\d+\z").is_match(n.trim()).unwrap_or(false)).unwrap_or(false) {
            name = Value::Null; // a placeholder says nothing
        }
        out.push(clean(vec![
            ("number", a["number"].clone()), ("title", name), ("title_ja", titles["ja_jp"].clone()), ("summary", json!(text(&a["synopsis"]))),
            ("airdate", a["airdate"].clone()), ("runtime", a["length"].clone()), ("image", a["thumbnail"]["original"].clone()),
        ]));
    }
    out
}

fn streaming_episodes(m: &Value) -> Vec<Value> {
    let mut out: Vec<Value> = vec![];
    for e in m["streamingEpisodes"].as_array().cloned().unwrap_or_default() {
        let t = e["title"].as_str().unwrap_or("");
        if let Some(c) = rx(r"(?i)\Aepisode\s+(\d+)\s*[-:–]\s*(.+)").captures(t).ok().flatten() {
            out.push(clean(vec![("number", json!(c[1].parse::<i64>().unwrap())), ("title", json!(c[2].trim())), ("image", e["thumbnail"].clone())]));
        }
    }
    out.sort_by_key(|x| x["number"].as_i64().unwrap_or(0));
    out
}

/// Merge every source by episode number: the first to name a field wins.
fn season_episodes(m: &Value, mal: Option<i64>, http: &dyn Http, sleep: &dyn Fn(f64)) -> Vec<Value> {
    let mut merged: std::collections::BTreeMap<i64, Map<String, Value>> = Default::default();
    for n in 0..3 {
        let need = merged.is_empty() || merged.values().any(|e| !e.contains_key("title") || !e.contains_key("image"));
        if n == 2 && !need {
            break; // Jikan is slow and flaky; only ask it when something is still missing
        }
        let eps = match n {
            0 => kitsu_episodes(m["id"].as_i64().unwrap_or(0), http),
            1 => Ok(streaming_episodes(m)),
            _ => match mal { Some(mal) if mal != 0 => jikan_episodes(mal, http, sleep), _ => Ok(vec![]) },
        };
        let Ok(eps) = eps else { continue };
        for e in eps {
            let num = e["number"].as_i64().unwrap_or(0);
            let cur = merged.entry(num).or_insert_with(|| { let mut m = Map::new(); m.insert("number".into(), json!(num)); m });
            for (k, v) in e.as_object().unwrap() {
                cur.entry(k.clone()).or_insert_with(|| v.clone());
            }
        }
    }
    merged.into_values().map(Value::Object).collect()
}

pub fn from_anilist(title: &Title, http: &dyn Http, sleep: &dyn Fn(f64)) -> Result<Option<Value>, HttpFail> {
    let media = anilist(http, &q_search(), json!({"q": title.name}))?["Page"]["media"].as_array().cloned().unwrap_or_default();
    let Some(first) = pick_anime(&media, title) else { return Ok(None) };
    let mut info = anime_record(&first);
    let wanted = title.seasons().len().max(1);
    let mut chain = vec![first];
    while chain.len() < wanted {
        let Some(nxt) = sequel(chain.last().unwrap()) else { break };
        let m = anilist(http, &q_id(), json!({"id": nxt["id"]}))?["Media"].clone();
        if !truthy(&m) {
            break;
        }
        chain.push(m);
    }
    let (mut seasons, mut episodes) = (vec![], vec![]);
    for (i, m) in chain.iter().enumerate() {
        let i = i + 1;
        let rec = anime_record(m);
        seasons.push(clean(vec![
            ("season", json!(i)), ("title", or(&rec["titles"]["english"], &rec["titles"]["main"])), ("year", rec["year"].clone()),
            ("episodes", rec["episodes_total"].clone()), ("anilist", rec["ids"]["anilist"].clone()), ("mal", rec["ids"]["mal"].clone()),
            ("banner", rec["banner"].clone()),
        ]));
        for e in season_episodes(m, rec["ids"]["mal"].as_i64(), http, sleep) {
            let mut o = Map::new();
            o.insert("season".into(), json!(i));
            o.extend(e.as_object().unwrap().clone());
            episodes.push(Value::Object(o));
        }
    }
    info["seasons"] = json!(seasons);
    info["episodes"] = json!(episodes);
    info["source"] = json!("anilist");
    Ok(Some(info))
}

// ---- shows ----

pub fn from_tvmaze(title: &Title, http: &dyn Http) -> Result<Option<Value>, HttpFail> {
    let data = http.json(&format!("https://api.tvmaze.com/search/shows?{}", q(&[("q", title.name.clone())])))?;
    let mut cands = vec![];
    for h in data.as_ref().and_then(|d| d.as_array()).cloned().unwrap_or_default() {
        let s = h["show"].clone();
        cands.push((vec![s["name"].as_str().map(String::from)], posters::premiered_year(&s), s, true));
    }
    let Some(hit) = best(&cands, title) else { return Ok(None) };
    let sid = hit["id"].clone();
    let full = http.json(&format!("https://api.tvmaze.com/shows/{}?embed[]=episodes&embed[]=cast&embed[]=images", sid))?.filter(truthy).unwrap_or(hit);
    let emb = &full["_embedded"];
    let net = if truthy(&full["network"]) { &full["network"] } else { &full["webChannel"] };
    let images = emb["images"].as_array().cloned().unwrap_or_default();
    let bg = images.iter().find(|i| i["type"] == "background" && truthy(&i["main"])).or_else(|| images.iter().find(|i| i["type"] == "background"));
    let banner = images.iter().find(|i| i["type"] == "banner");
    let pick = bg.or(banner);
    let ext = &full["externals"];
    let mut eps: Vec<Value> = vec![];
    for e in emb["episodes"].as_array().cloned().unwrap_or_default() {
        let ty = if !e["type"].is_null() && e["type"] != "regular" { e["type"].clone() } else { Value::Null };
        eps.push(clean(vec![
            ("season", e["season"].clone()), ("number", e["number"].clone()), ("title", e["name"].clone()), ("summary", json!(text(&e["summary"]))),
            ("airdate", e["airdate"].clone()), ("runtime", e["runtime"].clone()),
            ("image", or(&e["image"]["original"], &e["image"]["medium"])), ("rating", num(&e["rating"]["average"]).map(|r| json!(r)).unwrap_or(Value::Null)), ("type", ty),
        ]));
    }
    let mut seasons: std::collections::BTreeMap<i64, i64> = Default::default();
    for e in &eps {
        if e.get("type").is_none() && truthy(&e["number"]) {
            *seasons.entry(e["season"].as_i64().unwrap_or(0)).or_insert(0) += 1;
        }
    }
    let rt = if truthy(&full["averageRuntime"]) { full["averageRuntime"].clone() } else { full["runtime"].clone() };
    let next = next_tvmaze(&eps, None);
    Ok(Some(clean(vec![
        ("ids", clean(vec![("tvmaze", sid), ("imdb", ext["imdb"].clone()), ("tvdb", ext["thetvdb"].clone())])),
        ("titles", json!({"main": full["name"]})),
        ("description", json!(text(&full["summary"]))),
        ("genres", if truthy(&full["genres"]) { full["genres"].clone() } else { json!([]) }),
        ("rating", num(&full["rating"]["average"]).map(|r| json!(r)).unwrap_or(Value::Null)), ("rating_source", json!("TVmaze")),
        ("year", posters::premiered_year(&full).map(|y| json!(y)).unwrap_or(Value::Null)),
        ("status", full["status"].clone()), ("format", full["type"].clone()), ("runtime", rt), ("studio", net["name"].clone()),
        ("banner", pick.map(|p| p["resolutions"]["original"]["url"].clone()).unwrap_or(Value::Null)),
        ("cast", json!(emb["cast"].as_array().cloned().unwrap_or_default().iter().take(12).map(|c| clean(vec![
            ("name", c["person"]["name"].clone()), ("role", c["character"]["name"].clone()), ("image", c["person"]["image"]["medium"].clone())])).collect::<Vec<_>>())),
        ("seasons", json!(seasons.iter().map(|(k, v)| json!({"season": k, "episodes": v})).collect::<Vec<_>>())),
        ("episodes", json!(eps)), ("source", json!("tvmaze")),
        ("next_airing", next.unwrap_or(Value::Null)),
    ])))
}

pub fn next_tvmaze(eps: &[Value], now: Option<f64>) -> Option<Value> {
    let secs = now.unwrap_or_else(crate::state::now) as i64;
    let today = civil_date(secs);
    let future: Vec<&Value> = eps.iter().filter(|e| e["airdate"].as_str().map(|a| a > today.as_str()).unwrap_or(false) && truthy(&e["number"])).collect();
    future.iter().min_by(|a, b| a["airdate"].as_str().cmp(&b["airdate"].as_str())).map(|e| json!({"episode": e["number"], "season": e["season"], "date": e["airdate"]}))
}

/// `YYYY-MM-DD` (UTC) for a unix time.
pub fn civil_date(secs: i64) -> String {
    let days = secs.div_euclid(86400);
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    format!("{:04}-{:02}-{:02}", if m <= 2 { y + 1 } else { y }, m, d)
}

// ---- movies ----

pub fn from_cinemeta(title: &Title, http: &dyn Http) -> Result<Option<Value>, HttpFail> {
    let Some(m) = meta::cinemeta_meta(title, http)? else { return Ok(None) };
    let join = |k: &str| json!(m[k].as_array().map(|a| a.iter().filter_map(|x| x.as_str()).collect::<Vec<_>>().join(", ")).unwrap_or_default());
    let imdb = or(&m["imdb_id"], &m["id"]);
    let year = {
        let v = if truthy(&m["year"]) { &m["year"] } else { &m["releaseInfo"] };
        let s = match v { Value::Null => String::new(), Value::String(s) => s.clone(), o => o.to_string() };
        rx(r"\A\d{4}").find(s.as_str()).ok().flatten().and_then(|x| x.as_str().parse::<i64>().ok())
    };
    Ok(Some(clean(vec![
        ("ids", clean(vec![("imdb", imdb)])), ("titles", json!({"main": m["name"]})), ("description", json!(text(&m["description"]))),
        ("genres", if truthy(&m["genres"]) { m["genres"].clone() } else { json!([]) }),
        ("rating", num(&m["imdbRating"]).map(|r| json!(r)).unwrap_or(Value::Null)), ("rating_source", json!("IMDb")),
        ("year", year.map(|y| json!(y)).unwrap_or(Value::Null)), ("runtime", minutes(&m["runtime"]).map(|r| json!(r)).unwrap_or(Value::Null)),
        ("director", join("director")), ("writer", join("writer")), ("awards", m["awards"].clone()), ("country", m["country"].clone()),
        ("cast", json!(m["cast"].as_array().cloned().unwrap_or_default().iter().filter(|a| truthy(a)).map(|a| json!({"name": a})).collect::<Vec<_>>())),
        ("source", json!("cinemeta")),
    ])))
}

/// The record for one episode, or None.
pub fn episode_for(info: &Value, season: &Value, number: &Value) -> Option<Value> {
    if number.is_null() {
        return None;
    }
    info["episodes"].as_array()?.iter().find(|e| e["number"] == *number && e["season"] == *season).cloned()
}

pub struct Opts<'a> {
    pub refresh: bool,
    pub cache: PathBuf,
    pub art: PathBuf,
    pub now: f64,
    pub sleep: &'a dyn Fn(f64),
}
impl Default for Opts<'_> {
    fn default() -> Self {
        Opts { refresh: false, cache: info_dir(), art: art_dir(), now: crate::state::now(), sleep: &crate::posters::jikan_pace }
    }
}

/// -> (status, info). status: have | fetched | miss | skipped | error.
pub fn fetch(title: &Title, http: &dyn Http, o: &Opts) -> (&'static str, Option<Value>) {
    let old = read(title, &o.cache);
    if !o.refresh {
        if let Some(old) = &old {
            if old.get("miss").is_none() && old["schema"].as_i64() == Some(SCHEMA) {
                return ("have", Some(old.clone()));
            }
            if let Some(m) = old.get("miss").and_then(|m| m.as_f64()) {
                if o.now - m < MISS_RETRY_DAYS * 86400.0 {
                    return ("skipped", None);
                }
            }
        }
    }
    if title.source != "local" {
        return ("skipped", None);
    }
    let nfo = read_nfo(title);
    let r = match title.lib.as_str() {
        "anime" => from_anilist(title, http, o.sleep),
        "shows" => from_tvmaze(title, http),
        _ => from_cinemeta(title, http),
    };
    let (data, failure) = match r {
        Ok(d) => (d, None),
        Err(e) => (None, Some(e)),
    };
    let nfo_empty = nfo.as_object().map(|o| o.is_empty()).unwrap_or(true);
    if data.is_none() && nfo_empty {
        if let Some(f) = failure {
            return ("error", Some(json!({"error": f.0})));
        }
        write(title, &json!({"miss": o.now}), &o.cache);
        return ("miss", None);
    }
    let mut data = data.unwrap_or_else(|| json!({}));
    if let Some(n) = nfo.as_object() {
        for (k, v) in n.iter().filter(|(k, _)| *k != "nfo") {
            data[k] = v.clone(); // the user's .nfo wins
        }
        if let Some(p) = n.get("nfo") {
            data["nfo"] = p.clone();
        }
    }
    if let Some(old) = &old {
        if old.get("miss").is_none() && !truthy(&data["episodes"]) && truthy(&old["episodes"]) {
            data["episodes"] = old["episodes"].clone();
        }
    }
    if let Some(b) = data["banner"].as_str().filter(|b| !b.is_empty()) {
        if let Some(stored) = store_banner(title, b, http, &o.art) {
            data["banner_file"] = json!(stored.to_string_lossy());
        }
    }
    data["schema"] = json!(SCHEMA);
    data["fetched"] = json!(o.now);
    write(title, &data, &o.cache);
    ("fetched", Some(data))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dates() {
        assert_eq!(civil_date(0), "1970-01-01");
        assert_eq!(civil_date(1_762_128_000), "2025-11-03");
        assert_eq!(civil_date(951_782_400), "2000-02-29");
    }

    #[test]
    fn fold_removes_accents() {
        assert_eq!(fold("Rozé"), "roze");
    }
}
