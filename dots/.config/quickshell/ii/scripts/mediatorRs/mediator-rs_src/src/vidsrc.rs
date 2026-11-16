//! Direct HLS streams from vidsrc.buzz, looked up by IMDb id.
//! Unlike the old vaplayer path there is no token mint and no captcha: the embed page
//! carries a `var Q = {...}` config with signed per-server refs (~1h), and each ref is
//! traded at `/pl/api.php?a=play` for a `/_stream` HLS master. Failing fast matters:
//! callers fall back to other providers/torrents, so a dead source costs seconds.
use crate::errors::{describe_http, StreamError};
use crate::http::{HttpError, Request};
use serde_json::{json, Value};
use std::time::Duration;

pub const RETRIES: usize = 2;
pub const BACKOFF: f64 = 1.0;
pub const TIMEOUT: f64 = 8.0;

#[derive(Clone)]
pub struct Endpoints {
    pub base: String,
}

impl Default for Endpoints {
    fn default() -> Self {
        let base = std::env::var("MEDIATOR_VIDSRC_URL").ok().filter(|v| !v.is_empty()).unwrap_or_else(|| "https://vidsrc.buzz".into());
        Endpoints { base }
    }
}

fn err(s: impl Into<String>) -> StreamError {
    StreamError(s.into())
}

/// The player page a real client opens for this media.
pub fn embed(ep: &Endpoints, kind: &str, id: &str, season: i64, episode: i64) -> String {
    if kind == "movie" {
        format!("{}/embed/movie/{id}", ep.base)
    } else {
        format!("{}/embed/tv/{id}/{season}/{episode}", ep.base)
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

/// Preflight: does the stream really play? Providers hand out playlists whose variants are an
/// HTML error page or whose segment host is down, so follow one variant to its first segment.
pub fn manifest_ok(url: &str, referer: &str, backoff: f64) -> bool {
    let origin = url::Url::parse(referer).ok().map(|u| format!("{}://{}", u.scheme(), u.host_str().unwrap_or_default())).unwrap_or_default();
    let headers = [("Referer", referer), ("Origin", origin.as_str())];
    let playlist = |u: &str| -> Option<String> {
        let body = get(u, &headers, TIMEOUT, backoff).ok()?;
        let t = String::from_utf8_lossy(&body).into_owned();
        t.starts_with("#EXTM3U").then_some(t)
    };
    let first_uri = |t: &str| t.lines().map(str::trim).find(|l| !l.is_empty() && !l.starts_with('#')).map(str::to_string);
    let Some(mut text) = playlist(url) else { return false };
    let mut base = url.to_string();
    if text.contains("#EXT-X-STREAM-INF") {
        let Some(v) = first_uri(&text) else { return false };
        base = join(&base, &v);
        let Some(t) = playlist(&base) else { return false };
        text = t;
    }
    if !text.contains("#EXTINF") {
        return false;
    }
    let Some(seg) = first_uri(&text) else { return false };
    let seg = join(&base, &seg);
    match Request::get(&seg).timeout(5.0).header("Referer", referer).header("Origin", origin.as_str()).header("Range", "bytes=0-1023").send() {
        Ok(b) => !b.is_empty() && !b.starts_with(b"<"),
        Err(_) => false,
    }
}

fn pct(s: &str) -> String {
    const KEEP: &percent_encoding::AsciiSet = &percent_encoding::NON_ALPHANUMERIC
        .remove(b'_')
        .remove(b'.')
        .remove(b'-')
        .remove(b'~');
    percent_encoding::utf8_percent_encode(s, KEEP).to_string()
}

fn join(base: &str, rel: &str) -> String {
    url::Url::parse(base).and_then(|b| b.join(rel)).map(|u| u.to_string()).unwrap_or_else(|_| rel.to_string())
}

fn player_config(html: &str) -> Option<Value> {
    let cap = crate::parse::rx(r"(?s)var Q = (\{.*?\});").captures(html).ok().flatten()?;
    serde_json::from_str(cap.get(1)?.as_str()).ok()
}

fn json_body(body: &[u8]) -> Result<Value, StreamError> {
    serde_json::from_slice(body).map_err(|e| err(format!("the stream API answered with invalid JSON ({e})")))
}

/// Stream dicts in the shape `stremio` uses, best source first.
pub fn streams(ep: &Endpoints, kind: &str, imdb: &str, season: i64, episode: i64, check: bool) -> Result<Vec<Value>, StreamError> {
    streams_with(ep, kind, imdb, season, episode, check, TIMEOUT, BACKOFF)
}

#[allow(clippy::too_many_arguments)]
pub fn streams_with(
    ep: &Endpoints,
    kind: &str,
    imdb: &str,
    season: i64,
    episode: i64,
    check: bool,
    timeout: f64,
    backoff: f64,
) -> Result<Vec<Value>, StreamError> {
    if kind != "movie" && kind != "tv" {
        return Err(err(format!("unsupported kind '{kind}'")));
    }
    let emb = embed(ep, kind, imdb, season, episode);
    let home = format!("{}/", ep.base);
    let origin = ep.base.as_str();
    let html = get(&emb, &[("Referer", home.as_str())], timeout, backoff)?;
    let html = String::from_utf8_lossy(&html);
    let q = player_config(&html).ok_or_else(|| err("the embed page did not contain a player config (the site may have changed)"))?;

    let mut servers: Vec<Value> = q["ssr"]["servers"].as_array().cloned().unwrap_or_default();
    if servers.is_empty() {
        // Some titles render their server list on demand instead of server-side.
        let id = q["id"].as_str().filter(|s| !s.is_empty()).unwrap_or(imdb);
        let typ = q["type"].as_str().filter(|s| !s.is_empty()).unwrap_or(kind);
        let s = q["s"].as_i64().unwrap_or(season);
        let e = q["e"].as_i64().unwrap_or(episode);
        let t = q["t"].as_str().unwrap_or("");
        let qs = format!("a=sources&type={}&id={}&s={s}&e={e}&t={}", pct(typ), pct(id), pct(t));
        let body = get(
            &format!("{}/pl/api.php?{qs}", ep.base),
            &[("Accept", "application/json"), ("Referer", emb.as_str()), ("Origin", origin)],
            timeout,
            backoff,
        )?;
        servers = json_body(&body)?["servers"].as_array().cloned().unwrap_or_default();
    }
    if servers.is_empty() {
        return Err(err("no streams for this title"));
    }

    let mut out = vec![];
    let mut problems: Vec<String> = vec![];
    for (i, s) in servers.iter().enumerate() {
        let Some(reference) = s["ref"].as_str().filter(|r| !r.is_empty()) else { continue };
        let qs = format!("a=play&ref={}", pct(reference));
        let body = match get(
            &format!("{}/pl/api.php?{qs}", ep.base),
            &[("Accept", "application/json"), ("Referer", emb.as_str()), ("Origin", origin)],
            timeout,
            backoff,
        ) {
            Ok(b) => b,
            Err(e) => {
                problems.push(e.0);
                continue;
            }
        };
        let Some(url) = json_body(&body).ok().and_then(|j| j["url"].as_str().map(str::to_string)).filter(|u| !u.is_empty()) else {
            problems.push(format!("server {} returned no source", i + 1));
            continue;
        };
        let url = join(&ep.base, &url);
        if check && !manifest_ok(&url, &emb, backoff) {
            problems.push(format!("server {} did not serve a playlist", i + 1));
            continue;
        }
        out.push(json!({"infoHash": "", "fileIdx": -1, "url": url, "quality": "hls", "seeds": 0,
            "bingeGroup": "vidsrc", "filename": s["name"].as_str().unwrap_or(""), "referer": emb, "source": i + 1}));
        if check {
            break;
        }
    }
    if out.is_empty() {
        return Err(err(if problems.is_empty() { "every source failed its playlist check".into() } else { problems.join("; ") }));
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::http::testserver::serve;
    use std::collections::HashMap;

    fn ep(base: &str) -> Endpoints {
        Endpoints { base: base.into() }
    }

    fn config(servers: &str) -> String {
        format!(r#"<html><script>var Q = {{"type":"movie","id":"tt1","t":"tok","ssr":{{"servers":[{servers}]}}}};</script></html>"#)
    }

    #[test]
    fn lists_sources_without_check() {
        let page = config(r#"{"name":"A","ref":"r1"},{"name":"B","ref":"r2"}"#);
        let s = serve(HashMap::from([
            ("/embed/movie/tt1".into(), (200, page)),
            ("/pl/api.php?a=play&ref=r1".into(), (200, r#"{"url":"/_stream?id=one","type":"hls"}"#.into())),
            ("/pl/api.php?a=play&ref=r2".into(), (200, r#"{"url":"/_stream?id=two","type":"hls"}"#.into())),
        ]));
        let v = streams_with(&ep(&s.base), "movie", "tt1", 0, 0, false, 3.0, 0.0).unwrap();
        assert_eq!(v.len(), 2);
        assert_eq!(v[0]["url"], format!("{}/_stream?id=one", s.base));
        assert_eq!(v[1]["source"], 2);
        assert_eq!(v[0]["bingeGroup"], "vidsrc");
        assert_eq!(v[0]["referer"], format!("{}/embed/movie/tt1", s.base));
    }

    #[test]
    fn check_picks_first_live_manifest() {
        let page = config(r#"{"name":"A","ref":"r1"},{"name":"B","ref":"r2"}"#);
        let s = serve(HashMap::from([
            ("/embed/movie/tt1".into(), (200, page)),
            ("/pl/api.php?a=play&ref=r1".into(), (200, r#"{"url":"/dead.m3u8"}"#.into())),
            ("/pl/api.php?a=play&ref=r2".into(), (200, r#"{"url":"/ok.m3u8"}"#.into())),
            ("/dead.m3u8".into(), (404, "nope".into())),
            ("/ok.m3u8".into(), (200, "#EXTM3U\n#EXTINF:4,\n/seg0.ts\n".into())),
            ("/seg0.ts".into(), (200, "GGGGGGGG".into())),
        ]));
        let v = streams_with(&ep(&s.base), "movie", "tt1", 0, 0, true, 3.0, 0.0).unwrap();
        assert_eq!(v.len(), 1);
        assert_eq!(v[0]["source"], 2);
    }

    #[test]
    fn check_rejects_streams_that_cannot_play() {
        let page = config(r#"{"name":"A","ref":"r1"},{"name":"B","ref":"r2"},{"name":"C","ref":"r3"}"#);
        let s = serve(HashMap::from([
            ("/embed/movie/tt1".into(), (200, page)),
            ("/pl/api.php?a=play&ref=r1".into(), (200, r#"{"url":"/fake.m3u8"}"#.into())),
            ("/pl/api.php?a=play&ref=r2".into(), (200, r#"{"url":"/nosegs.m3u8"}"#.into())),
            ("/pl/api.php?a=play&ref=r3".into(), (200, r#"{"url":"/good.m3u8"}"#.into())),
            // master whose variant is an HTML page
            ("/fake.m3u8".into(), (200, "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\n/v.m3u8\n".into())),
            ("/v.m3u8".into(), (200, "<!doctype html><html></html>".into())),
            // media playlist whose segment host is down
            ("/nosegs.m3u8".into(), (200, "#EXTM3U\n#EXTINF:4,\n/gone.ts\n".into())),
            ("/gone.ts".into(), (502, "Upstream unreachable".into())),
            // master -> variant -> segment
            ("/good.m3u8".into(), (200, "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\n/gv.m3u8\n".into())),
            ("/gv.m3u8".into(), (200, "#EXTM3U\n#EXTINF:4,\nseg.ts\n".into())),
            ("/seg.ts".into(), (200, "GGGGGGGG".into())),
        ]));
        let v = streams_with(&ep(&s.base), "movie", "tt1", 0, 0, true, 3.0, 0.0).unwrap();
        assert_eq!(v[0]["source"], 3);
        let only_bad = config(r#"{"name":"A","ref":"r1"}"#);
        let s = serve(HashMap::from([
            ("/embed/movie/tt1".into(), (200, only_bad)),
            ("/pl/api.php?a=play&ref=r1".into(), (200, r#"{"url":"/nosegs.m3u8"}"#.into())),
            ("/nosegs.m3u8".into(), (200, "#EXTM3U\n#EXTINF:4,\n/gone.ts\n".into())),
            ("/gone.ts".into(), (502, "x".into())),
        ]));
        assert!(streams_with(&ep(&s.base), "movie", "tt1", 0, 0, true, 3.0, 0.0).is_err());
    }

    #[test]
    fn falls_back_to_sources_api() {
        let page = r#"<script>var Q = {"type":"tv","id":"tt1","s":2,"e":3,"t":"tok","ssr":{"servers":[]}};</script>"#;
        let s = serve(HashMap::from([
            ("/embed/tv/tt1/2/3".into(), (200, page.into())),
            ("/pl/api.php?a=sources&type=tv&id=tt1&s=2&e=3&t=tok".into(), (200, r#"{"servers":[{"name":"A","ref":"r1"}]}"#.into())),
            ("/pl/api.php?a=play&ref=r1".into(), (200, r#"{"url":"/_stream?id=one"}"#.into())),
        ]));
        let v = streams_with(&ep(&s.base), "tv", "tt1", 2, 3, false, 3.0, 0.0).unwrap();
        assert_eq!(v.len(), 1);
        assert_eq!(v[0]["url"], format!("{}/_stream?id=one", s.base));
    }

    #[test]
    fn clear_errors() {
        let e = |body: &str| {
            let s = serve(HashMap::from([("/embed/movie/tt1".into(), (200, body.into()))]));
            streams_with(&ep(&s.base), "movie", "tt1", 0, 0, false, 3.0, 0.0).unwrap_err().0
        };
        assert_eq!(e("<html></html>"), "the embed page did not contain a player config (the site may have changed)");
        assert_eq!(streams_with(&ep("http://127.0.0.1:1"), "show", "tt1", 0, 0, false, 2.0, 0.0).unwrap_err().0,
                   "unsupported kind 'show'");
    }
}
