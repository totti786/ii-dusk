//! Legacy direct-HLS path for movies and series, looked up by IMDb id.
//! The stream-data API now mints a single-use token from the player page and returns
//! encrypted stream lists, so this path usually fails; `vidsrc` is the primary direct
//! provider. Failing fast matters: callers fall back to the next provider/torrents, so a
//! dead source costs seconds, not minutes.
use crate::errors::{describe_http, StreamError};
use crate::http::{HttpError, Request};
use serde_json::{json, Value};
use std::time::Duration;

pub const RETRIES: usize = 2;
pub const BACKOFF: f64 = 1.0;
pub const TIMEOUT: f64 = 8.0;

#[derive(Clone)]
pub struct Endpoints {
    pub api: String,
    pub player: String,
}

impl Default for Endpoints {
    fn default() -> Self {
        Endpoints { api: "https://streamdata.vaplayer.ru/api.php".into(), player: "https://nextgencloudfabric.com".into() }
    }
}

fn err(s: impl Into<String>) -> StreamError {
    StreamError(s.into())
}

/// The player-origin Referer a real client would send.
pub fn referer(ep: &Endpoints, kind: &str, imdb: &str, season: i64, episode: i64) -> String {
    if kind == "movie" {
        format!("{}/embed/movie/{imdb}", ep.player)
    } else {
        format!("{}/embed/tv/{imdb}/{season}/{episode}", ep.player)
    }
}

fn get(url: &str, headers: &[(&str, &str)], timeout: f64, backoff: f64) -> Result<Vec<u8>, StreamError> {
    let mut last: Option<HttpError> = None;
    for attempt in 0..RETRIES {
        let mut r = Request::get(url).timeout(timeout).header("Accept", "*/*");
        for (k, v) in headers {
            r = r.header(k, v);
        }
        match r.send() {
            Ok(b) => return Ok(b),
            Err(HttpError::Status(c)) if c < 500 => return Err(err(describe_http(c))),
            Err(e) => last = Some(e),
        }
        if attempt + 1 < RETRIES {
            std::thread::sleep(Duration::from_secs_f64(backoff));
        }
    }
    Err(err(last.map(|e| e.describe()).unwrap_or_else(|| "no answer".into())))
}

pub fn query(ep: &Endpoints, kind: &str, imdb: &str, season: i64, episode: i64) -> String {
    if kind == "movie" {
        format!("{}?imdb={imdb}&type=movie", ep.api)
    } else {
        format!("{}?imdb={imdb}&type=tv&season={season}&episode={episode}", ep.api)
    }
}

/// Cheap preflight: does the signed URL still serve a playlist?
pub fn manifest_ok(url: &str, referer: &str, backoff: f64) -> bool {
    get(url, &[("Referer", referer)], TIMEOUT, backoff).map(|b| b.starts_with(b"#EXTM3U")).unwrap_or(false)
}

/// Stream dicts in the shape `stremio` uses, best source first.
pub fn streams(ep: &Endpoints, kind: &str, imdb: &str, season: i64, episode: i64, check: bool) -> Result<Vec<Value>, StreamError> {
    streams_with(ep, kind, imdb, season, episode, check, TIMEOUT, BACKOFF)
}

#[allow(clippy::too_many_arguments)]
pub fn streams_with(ep: &Endpoints, kind: &str, imdb: &str, season: i64, episode: i64, check: bool, timeout: f64, backoff: f64) -> Result<Vec<Value>, StreamError> {
    if kind != "movie" && kind != "tv" {
        return Err(err(format!("unsupported kind '{kind}'")));
    }
    let rf = referer(ep, kind, imdb, season, episode);
    let raw = get(&query(ep, kind, imdb, season, episode), &[("Accept", "application/json"), ("Referer", &rf)], timeout, backoff)?;
    let raw = String::from_utf8_lossy(&raw).trim().to_string();
    if raw.starts_with('<') {
        return Err(err("the stream API answered with a web page (blocked)"));
    }
    let body: Value = serde_json::from_str(&raw).map_err(|e| err(format!("the stream API answered with invalid JSON ({e})")))?;
    let code = match &body["status_code"] {
        Value::String(s) => s.clone(),
        Value::Null => "None".into(),
        v => v.to_string(),
    };
    if code != "200" {
        return Err(err(if code == "404" { "no streams for this title".to_string() } else { format!("stream API error {code}") }));
    }
    let urls = &body["data"]["stream_urls"];
    if urls.is_string() {
        return Err(err("the stream list is encrypted (not supported yet)"));
    }
    let urls: Vec<&str> = urls.as_array().map(|a| a.iter().filter_map(|u| u.as_str()).filter(|u| u.starts_with("http")).collect()).unwrap_or_default();
    if urls.is_empty() {
        return Err(err("the stream API returned no sources"));
    }
    let mut out = vec![];
    for (i, url) in urls.iter().enumerate() {
        if check && !manifest_ok(url, &rf, backoff) {
            continue;
        }
        out.push(json!({"infoHash": "", "fileIdx": -1, "url": url, "quality": "hls", "seeds": 0,
            "bingeGroup": "vaplayer", "filename": "", "referer": rf, "source": i + 1}));
        if check {
            break;
        }
    }
    if out.is_empty() {
        return Err(err("every source failed its playlist check"));
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::http::testserver::serve;
    use std::collections::HashMap;

    fn ep(base: &str) -> Endpoints {
        Endpoints { api: format!("{base}/api.php"), player: base.into() }
    }
    fn route(q: &str, code: u16, body: &str) -> HashMap<String, (u16, String)> {
        HashMap::from([(format!("/api.php?{q}"), (code, body.to_string()))])
    }

    #[test]
    fn lists_sources_without_check() {
        let s = serve(route("imdb=tt1&type=tv&season=2&episode=3", 200, r#"{"status_code":"200","data":{"stream_urls":["http://a/x.m3u8","junk","http://b/y.m3u8"]}}"#));
        let v = streams_with(&ep(&s.base), "tv", "tt1", 2, 3, false, 3.0, 0.0).unwrap();
        assert_eq!(v.len(), 2);
        assert_eq!(v[1]["source"], 2);
        assert_eq!(v[0]["referer"], format!("{}/embed/tv/tt1/2/3", s.base));
    }

    #[test]
    fn clear_errors() {
        let t = |body: &str| streams_with(&ep(&serve(route("imdb=tt1&type=movie", 200, body)).base), "movie", "tt1", 0, 0, false, 3.0, 0.0).unwrap_err().0;
        assert_eq!(t("<html>"), "the stream API answered with a web page (blocked)");
        assert_eq!(t(r#"{"status_code":404}"#), "no streams for this title");
        assert_eq!(t(r#"{"status_code":500}"#), "stream API error 500");
        assert_eq!(t(r#"{"status_code":"200","data":{"stream_urls":"abc"}}"#), "the stream list is encrypted (not supported yet)");
        assert_eq!(t(r#"{"status_code":"200","data":{"stream_urls":[]}}"#), "the stream API returned no sources");
        assert!(t("nope").starts_with("the stream API answered with invalid JSON"));
        let e = streams_with(&ep(&serve(HashMap::new()).base), "movie", "tt1", 0, 0, false, 3.0, 0.0).unwrap_err().0;
        assert_eq!(e, "HTTP 404: has nothing at that address (the link expired, or the service moved)");
    }

    #[test]
    fn check_picks_first_live_manifest() {
        let mut r = route("imdb=tt1&type=movie", 200, "");
        let s0 = serve(HashMap::new());
        let _ = s0;
        // two sources: the first is dead (404), the second serves a playlist
        let l = serve(HashMap::from([("/ok.m3u8".into(), (200, "#EXTM3U\n".to_string()))]));
        let body = format!(r#"{{"status_code":"200","data":{{"stream_urls":["{b}/dead.m3u8","{b}/ok.m3u8"]}}}}"#, b = l.base);
        r.insert("/api.php?imdb=tt1&type=movie".into(), (200, body));
        let api = serve(r);
        let v = streams_with(&ep(&api.base), "movie", "tt1", 0, 0, true, 3.0, 0.0).unwrap();
        assert_eq!(v.len(), 1);
        assert_eq!(v[0]["source"], 2);
    }
}
