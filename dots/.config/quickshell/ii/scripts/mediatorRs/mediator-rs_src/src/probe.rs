//! What is inside a video file: resolution, codecs, audio and subtitle tracks, chapters
//! (port of `mediator/probe.py`). Read with ffprobe and cached by (path, size, mtime) in the same
//! `probe.json` Python uses. `cached()` never runs anything; `probe()` does.
use serde_json::{json, Map, Value};
use std::io::Read;
use std::sync::Mutex;
use std::time::{Duration, Instant};

static MEM: Mutex<Option<Map<String, Value>>> = Mutex::new(None);

pub fn cache_file() -> std::path::PathBuf {
    crate::config::cache_dir().join("probe.json")
}

fn codec_name(c: &str) -> &str {
    match c {
        "hevc" => "HEVC", "h264" => "H.264", "av1" => "AV1", "vp9" => "VP9", "mpeg4" => "MPEG-4", "aac" => "AAC", "ac3" => "AC3",
        "eac3" => "E-AC3", "dts" => "DTS", "truehd" => "TrueHD", "flac" => "FLAC", "opus" => "Opus", "vorbis" => "Vorbis", "mp3" => "MP3",
        "ass" => "ASS", "subrip" => "SRT", "srt" => "SRT", "webvtt" => "VTT", "hdmv_pgs_subtitle" => "PGS",
        other => other,
    }
}

fn key(path: &str) -> Option<String> {
    use std::os::unix::fs::MetadataExt;
    let m = std::fs::metadata(path).ok()?;
    Some(format!("{}|{}|{}", path, m.len(), m.mtime()))
}

fn with_mem<T>(f: impl FnOnce(&mut Map<String, Value>) -> T) -> T {
    let mut g = MEM.lock().unwrap_or_else(|e| e.into_inner());
    let m = g.get_or_insert_with(|| match crate::fileio::read_json(&cache_file()) {
        Value::Object(m) => m,
        _ => Map::new(),
    });
    f(m)
}

/// Forget the in-memory copy (tests, or after another process wrote the file).
pub fn reset() {
    *MEM.lock().unwrap_or_else(|e| e.into_inner()) = None;
}

fn save_locked(m: &Map<String, Value>) {
    let _ = crate::fileio::atomic_write_text(&cache_file(), &serde_json::to_string(m).unwrap_or_default(), 0o644);
}

pub fn cached(path: &str) -> Option<Value> {
    let k = key(path)?;
    let rec = with_mem(|m| m.get(&k).cloned())?;
    if rec.get("error").map(truthy).unwrap_or(false) { None } else { Some(rec) }
}

fn truthy(v: &Value) -> bool {
    match v { Value::Null => false, Value::Bool(b) => *b, Value::Number(n) => n.as_f64() != Some(0.0), Value::String(s) => !s.is_empty(), Value::Array(a) => !a.is_empty(), Value::Object(o) => !o.is_empty() }
}

fn fps(rate: Option<&str>) -> Option<f64> {
    let (a, b) = rate?.split_once('/')?;
    let (a, b): (i64, i64) = (a.parse().ok()?, b.parse().ok()?);
    if b == 0 { return None; }
    format!("{:.2}", a as f64 / b as f64).parse().ok()
}

fn track(s: &Value) -> Value {
    let tags = &s["tags"];
    let disp = &s["disposition"];
    let lang = tags["language"].as_str().unwrap_or("").to_lowercase();
    let codec = s["codec_name"].as_str().map(codec_name);
    let mut m = Map::new();
    let mut put = |k: &str, v: Value| {
        if !matches!(v, Value::Null) && v != json!("") {
            m.insert(k.into(), v);
        }
    };
    put("lang", if lang.is_empty() { Value::Null } else { json!(lang) });
    put("title", tags["title"].clone());
    put("codec", codec.map(|c| json!(c)).unwrap_or(Value::Null));
    put("channels", s["channels"].clone());
    put("default", if truthy(&disp["default"]) { json!(true) } else { Value::Null });
    put("forced", if truthy(&disp["forced"]) { json!(true) } else { Value::Null });
    Value::Object(m)
}

/// ffprobe's JSON -> the small record front ends use.
pub fn parse(raw: &Value) -> Value {
    let streams = raw["streams"].as_array().cloned().unwrap_or_default();
    let fmt = &raw["format"];
    let video = streams.iter().find(|s| s["codec_type"] == "video" && !truthy(&s["disposition"]["attached_pic"]));
    let mut out = Map::new();
    let dur = match &fmt["duration"] { Value::String(s) => s.trim().parse::<f64>().ok(), v => v.as_f64() };
    if let Some(d) = dur {
        out.insert("duration".into(), json!(format!("{d:.1}").parse::<f64>().unwrap_or(d)));
    }
    if truthy(&fmt["bit_rate"]) {
        let br = match &fmt["bit_rate"] { Value::String(s) => s.trim().parse::<i64>().ok(), v => v.as_i64() };
        if let Some(b) = br {
            out.insert("bitrate".into(), json!(b));
        }
    }
    if let Some(v) = video {
        let raw_depth = match &v["bits_per_raw_sample"] { Value::String(s) => s.clone(), Value::Null => String::new(), o => o.to_string() };
        let pix = match &v["pix_fmt"] { Value::String(s) => s.clone(), _ => String::new() };
        let depth = if !raw_depth.is_empty() && raw_depth.chars().all(|c| c.is_ascii_digit()) {
            Some(raw_depth.parse::<i64>().unwrap_or(0))
        } else if pix.contains("10") { Some(10) } else { None };
        let hdr = matches!(v["color_transfer"].as_str(), Some("smpte2084") | Some("arib-std-b67"));
        let mut put = |k: &str, val: Option<Value>| if let Some(x) = val.filter(|x| !x.is_null()) { out.insert(k.into(), x); };
        put("width", Some(v["width"].clone()));
        put("height", Some(v["height"].clone()));
        put("vcodec", v["codec_name"].as_str().map(|c| json!(codec_name(c))));
        put("bit_depth", depth.map(|d| json!(d)));
        put("fps", fps(v["avg_frame_rate"].as_str()).map(|f| json!(f)));
        put("hdr", if hdr { Some(json!(true)) } else { None });
    }
    let of = |t: &str| Value::Array(streams.iter().filter(|s| s["codec_type"] == t).map(track).collect());
    out.insert("audio".into(), of("audio"));
    out.insert("subs".into(), of("subtitle"));
    out.insert("chapters".into(), json!(raw["chapters"].as_array().map(|a| a.len()).unwrap_or(0)));
    let rec = Value::Object(out.clone());
    out.insert("summary".into(), json!(summary(&rec)));
    Value::Object(out)
}

pub fn summary(rec: &Value) -> String {
    let mut bits: Vec<String> = vec![];
    if truthy(&rec["height"]) {
        bits.push(format!("{}p", rec["height"].as_i64().unwrap_or(0)));
    }
    if let Some(codec) = rec["vcodec"].as_str().filter(|c| !c.is_empty()) {
        let depth = rec["bit_depth"].as_i64().unwrap_or(8);
        bits.push(format!("{codec}{}{}", if depth > 8 { format!(" {depth}-bit") } else { String::new() }, if truthy(&rec["hdr"]) { " HDR" } else { "" }));
    }
    for (k, word) in [("audio", "audio"), ("subs", "subtitle")] {
        let n = rec[k].as_array().map(|a| a.len()).unwrap_or(0);
        if n > 0 {
            bits.push(format!("{n} {word}{}", if n != 1 { "s" } else { "" }));
        }
    }
    bits.join(" · ")
}

/// (stdout, stderr), or None when ffprobe is missing or hung past `timeout`.
pub fn run_ffprobe(path: &str, timeout: f64) -> Option<(String, String)> {
    let mut child = std::process::Command::new("ffprobe")
        .args(["-v", "error", "-print_format", "json", "-show_format", "-show_streams", "-show_chapters", path])
        .stdin(std::process::Stdio::null()).stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::piped()).spawn().ok()?;
    let (mut so, mut se) = (child.stdout.take()?, child.stderr.take()?);
    let t_out = std::thread::spawn(move || { let mut b = vec![]; let _ = so.read_to_end(&mut b); b });
    let t_err = std::thread::spawn(move || { let mut b = vec![]; let _ = se.read_to_end(&mut b); b });
    let end = Instant::now() + Duration::from_secs_f64(timeout);
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) if Instant::now() < end => std::thread::sleep(Duration::from_millis(10)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return None;
            }
        }
    }
    Some((String::from_utf8_lossy(&t_out.join().ok()?).into_owned(), String::from_utf8_lossy(&t_err.join().ok()?).into_owned()))
}

/// The record, or None when ffprobe is missing or the file is unreadable (remembered, so a broken
/// file is not reopened on every listing).
pub fn probe(path: &str, force: bool, save: bool) -> Option<Value> {
    probe_with(path, force, save, &|p| run_ffprobe(p, 30.0))
}

pub fn probe_with(path: &str, force: bool, save: bool, run: &dyn Fn(&str) -> Option<(String, String)>) -> Option<Value> {
    let k = key(path)?;
    if let Some(have) = with_mem(|m| m.get(&k).cloned()) {
        if !force {
            return if truthy(&have["error"]) { None } else { Some(have) };
        }
    }
    let (stdout, stderr) = run(path)?;
    let raw: Value = serde_json::from_str(if stdout.trim().is_empty() { "{}" } else { &stdout }).ok()?;
    let rec = if raw["streams"].as_array().map(|a| !a.is_empty()).unwrap_or(false) {
        parse(&raw)
    } else {
        let msg = stderr.trim();
        json!({"error": if msg.is_empty() { "unreadable".to_string() } else { msg.chars().take(200).collect() }})
    };
    with_mem(|m| {
        m.insert(k, rec.clone());
        if save {
            save_locked(m);
        }
    });
    if truthy(&rec["error"]) { None } else { Some(rec) }
}

/// Write the cache once after a batch of `probe(.., save = false)`.
pub fn flush() {
    with_mem(|m| save_locked(m));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unreadable_file_is_remembered() {
        let d = tempfile::tempdir().unwrap();
        std::env::set_var("MEDIATOR_CACHE_DIR", d.path());
        reset();
        let f = d.path().join("a.mkv");
        std::fs::write(&f, b"x").unwrap();
        let p = f.to_str().unwrap();
        let calls = std::cell::Cell::new(0);
        let run = |_: &str| { calls.set(calls.get() + 1); Some(("{}".to_string(), " bad data\n".to_string())) };
        assert!(probe_with(p, false, true, &run).is_none());
        assert!(probe_with(p, false, true, &run).is_none());
        assert_eq!(calls.get(), 1);
        assert!(cached(p).is_none());
        assert!(std::fs::read_to_string(cache_file()).unwrap().contains("bad data"));
    }
}

#[cfg(test)]
mod fixture {
    #[test]
    fn matches_python_parse() {
        let cases: Vec<serde_json::Value> = serde_json::from_str(include_str!("../tests/fixtures/probe.json")).unwrap();
        for c in cases {
            assert_eq!(super::parse(&c["raw"]), c["want"]);
            assert_eq!(super::parse(&c["raw"]).to_string(), c["want"].to_string(), "key order");
        }
    }
}
