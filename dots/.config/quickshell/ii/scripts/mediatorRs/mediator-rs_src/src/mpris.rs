//! MPRIS publishing for the daemon (port of `mediator/mpris.py`).
//! The pure helpers live here; `make` returns the D-Bus handle once the D-Bus side is built, and
//! `None` (the same as Python without dbus-python) until then, so the daemon runs without it.
use crate::daemon::Daemon;
use std::sync::Arc;

pub const BUS_NAME: &str = "org.mpris.MediaPlayer2.mediator";

/// mpv's 0-130 volume as MPRIS's 0.0-1.0; None means it has not reported one yet.
pub fn volume_fraction(volume: Option<f64>) -> f64 {
    volume.map(|v| (v / 100.0).clamp(0.0, 1.0)).unwrap_or(1.0)
}

/// A local poster path or a provider URL as a valid MPRIS art URI.
pub fn art_url(path: &str) -> Option<String> {
    if path.is_empty() {
        return None;
    }
    Some(if ["http://", "https://", "file://"].iter().any(|p| path.starts_with(p)) { path.to_string() } else { format!("file://{path}") })
}

pub trait Handle: Send + Sync {
    /// Tell listeners what changed since last time (position excluded: it ticks by itself).
    fn sync(&self);
    /// Drop the bus name so an idle daemon shows no empty "mediator" player.
    fn retire(&self);
}

use serde_json::{json, Value as Json};
use std::collections::{BTreeMap, HashMap};
use std::sync::Mutex;
use zbus::blocking::Connection;
use zbus::zvariant::{ObjectPath, OwnedValue, Value};

pub const PATH: &str = "/org/mpris/MediaPlayer2";
const PLAYER: &str = "org.mpris.MediaPlayer2.Player";

fn ov<'a, T: Into<Value<'a>>>(v: T) -> OwnedValue {
    OwnedValue::try_from(v.into()).expect("plain values convert")
}

fn current(d: &Daemon) -> Option<Json> {
    d.snapshot()["sessions"].get(0).cloned()
}

fn metadata(s: &Option<Json>) -> HashMap<String, OwnedValue> {
    let mut md: HashMap<String, OwnedValue> = HashMap::new();
    let Some(s) = s else {
        md.insert("mpris:trackid".into(), ov(ObjectPath::try_from("/org/mpris/MediaPlayer2/TrackList/NoTrack").unwrap()));
        return md;
    };
    let path = s["path"].as_str().filter(|p| !p.is_empty()).unwrap_or("x");
    let tid: String = path.chars().map(|c| if c.is_alphanumeric() || c == '_' { c } else { '_' }).collect();
    let tail: String = { let n = tid.chars().count(); tid.chars().skip(n.saturating_sub(80)).collect() };
    md.insert("mpris:trackid".into(), ov(ObjectPath::try_from(format!("/org/mpris/MediaPlayer2/Track/{tail}")).unwrap()));
    md.insert("mpris:length".into(), ov((s["duration"].as_f64().unwrap_or(0.0) * 1e6) as i64));
    let title = ["episode_title", "label", "media_title"].iter().filter_map(|k| s[*k].as_str()).find(|v| !v.is_empty()).unwrap_or("");
    md.insert("xesam:title".into(), ov(title.to_string()));
    if let Some(t) = s["title"].as_str().filter(|t| !t.is_empty()) {
        md.insert("xesam:artist".into(), ov(vec![t.to_string()]));
    }
    if let Some(c) = s["code"].as_str().filter(|c| !c.is_empty()) {
        md.insert("xesam:album".into(), ov(c.to_string()));
    }
    if let Some(art) = s["poster"].as_str().and_then(art_url) {
        md.insert("mpris:artUrl".into(), ov(art));
    }
    md
}

/// Every Player property except Position.
fn player_props(d: &Daemon) -> BTreeMap<&'static str, OwnedValue> {
    let s = current(d);
    let status = match &s {
        None => "Stopped",
        // MPRIS has no buffering state; a stalled stream reads as Paused so the shell's progress clock stops with it
        Some(s) if s["paused"] == true || s["buffering"] == true => "Paused",
        Some(_) => "Playing",
    };
    let has = s.is_some();
    let mut m: BTreeMap<&'static str, OwnedValue> = BTreeMap::new();
    m.insert("PlaybackStatus", ov(status.to_string()));
    m.insert("LoopStatus", ov("None".to_string()));
    m.insert("Shuffle", ov(false));
    m.insert("Rate", ov(s.as_ref().and_then(|s| s["speed"].as_f64()).unwrap_or(1.0)));
    m.insert("MinimumRate", ov(0.1f64));
    m.insert("MaximumRate", ov(4.0f64));
    m.insert("Metadata", ov(Value::from(metadata(&s))));
    m.insert("Volume", ov(if has { volume_fraction(s.as_ref().and_then(|s| s["volume"].as_f64())) } else { 1.0 }));
    for k in ["CanGoNext", "CanGoPrevious", "CanPlay", "CanPause", "CanSeek"] {
        m.insert(k, ov(has));
    }
    m.insert("CanControl", ov(true));
    m
}

struct Root;

#[zbus::interface(name = "org.mpris.MediaPlayer2")]
impl Root {
    fn raise(&self) {}
    fn quit(&self) {}
    #[zbus(property)]
    fn can_quit(&self) -> bool { false }
    #[zbus(property)]
    fn can_raise(&self) -> bool { false }
    #[zbus(property)]
    fn has_track_list(&self) -> bool { false }
    #[zbus(property)]
    fn identity(&self) -> String { "Mediator".into() }
    #[zbus(property)]
    fn desktop_entry(&self) -> String { String::new() }
    #[zbus(property)]
    fn supported_uri_schemes(&self) -> Vec<String> { vec![] }
    #[zbus(property)]
    fn supported_mime_types(&self) -> Vec<String> { vec![] }
}

struct Player(Arc<Daemon>);

impl Player {
    fn act(&self, action: &str, value: Json) {
        self.0.control(&json!({"action": action, "value": value}));
    }
}

#[zbus::interface(name = "org.mpris.MediaPlayer2.Player")]
impl Player {
    fn next(&self) { self.act("next", Json::Null) }
    fn previous(&self) { self.act("prev", Json::Null) }
    fn pause(&self) { self.act("pause", Json::Null) }
    fn play_pause(&self) { self.act("toggle", Json::Null) }
    fn stop(&self) { self.act("stop", Json::Null) }
    fn play(&self) { self.act("play", Json::Null) }
    fn seek(&self, offset: i64) { self.act("seek", json!(offset as f64 / 1e6)) }
    fn set_position(&self, _track_id: ObjectPath<'_>, position: i64) { self.act("seek_to", json!((position as f64 / 1e6).max(0.0))) }
    fn open_uri(&self, _uri: String) {}

    #[zbus(property)]
    fn playback_status(&self) -> String { prop_string(&self.0, "PlaybackStatus") }
    #[zbus(property)]
    fn loop_status(&self) -> String { "None".into() }
    #[zbus(property)]
    fn shuffle(&self) -> bool { false }
    #[zbus(property)]
    fn rate(&self) -> f64 { current(&self.0).and_then(|s| s["speed"].as_f64()).unwrap_or(1.0) }
    #[zbus(property)]
    fn set_rate(&self, v: f64) { self.act("speed", json!(v.clamp(0.1, 4.0))) }
    #[zbus(property)]
    fn minimum_rate(&self) -> f64 { 0.1 }
    #[zbus(property)]
    fn maximum_rate(&self) -> f64 { 4.0 }
    #[zbus(property)]
    fn metadata(&self) -> HashMap<String, OwnedValue> { metadata(&current(&self.0)) }
    #[zbus(property)]
    fn volume(&self) -> f64 { current(&self.0).map(|s| volume_fraction(s["volume"].as_f64())).unwrap_or(1.0) }
    #[zbus(property)]
    fn set_volume(&self, v: f64) { self.act("volume", json!((v * 100.0).clamp(0.0, 130.0))) }
    #[zbus(property(emits_changed_signal = "false"))]
    fn position(&self) -> i64 { (current(&self.0).and_then(|s| s["position"].as_f64()).unwrap_or(0.0) * 1e6) as i64 }
    #[zbus(property)]
    fn can_go_next(&self) -> bool { current(&self.0).is_some() }
    #[zbus(property)]
    fn can_go_previous(&self) -> bool { current(&self.0).is_some() }
    #[zbus(property)]
    fn can_play(&self) -> bool { current(&self.0).is_some() }
    #[zbus(property)]
    fn can_pause(&self) -> bool { current(&self.0).is_some() }
    #[zbus(property)]
    fn can_seek(&self) -> bool { current(&self.0).is_some() }
    #[zbus(property)]
    fn can_control(&self) -> bool { true }
}

fn prop_string(d: &Daemon, k: &str) -> String {
    let status = match current(d) {
        None => "Stopped",
        Some(s) if s["paused"] == true || s["buffering"] == true => "Paused",
        Some(_) => "Playing",
    };
    if k == "PlaybackStatus" { status.to_string() } else { String::new() }
}

struct DbusHandle {
    daemon: Arc<Daemon>,
    conn: Mutex<Option<Connection>>,
    last: Mutex<BTreeMap<&'static str, String>>,
}

impl Handle for DbusHandle {
    fn sync(&self) {
        let now = player_props(&self.daemon);
        let mut last = self.last.lock().unwrap();
        let mut changed: HashMap<&str, Value> = HashMap::new();
        let mut seen = BTreeMap::new();
        for (k, v) in &now {
            let repr = format!("{v:?}");
            if last.get(k) != Some(&repr) {
                changed.insert(*k, Value::from(v.clone()));
            }
            seen.insert(*k, repr);
        }
        if changed.is_empty() {
            return;
        }
        *last = seen;
        if let Some(conn) = self.conn.lock().unwrap().as_ref() {
            let invalidated: Vec<&str> = vec![];
            let _ = conn.emit_signal(None::<&str>, PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged", &(PLAYER, changed, invalidated));
        }
    }

    fn retire(&self) {
        // dropping the connection releases the bus name
        self.conn.lock().unwrap().take();
    }
}

/// Publish on the session bus; None without a bus, or when another mediator daemon owns the name.
pub fn make(daemon: &Arc<Daemon>) -> Option<Box<dyn Handle>> {
    let conn = zbus::blocking::connection::Builder::session().ok()?
        .name(BUS_NAME).ok()?
        .serve_at(PATH, Root).ok()?
        .serve_at(PATH, Player(daemon.clone())).ok()?
        .build().ok()?;
    Some(Box::new(DbusHandle { daemon: daemon.clone(), conn: Mutex::new(Some(conn)), last: Mutex::new(BTreeMap::new()) }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn volume_and_art() {
        assert_eq!(volume_fraction(None), 1.0);
        assert_eq!(volume_fraction(Some(130.0)), 1.0);
        assert_eq!(volume_fraction(Some(50.0)), 0.5);
        assert_eq!(volume_fraction(Some(-4.0)), 0.0);
        assert_eq!(art_url("/a/b.jpg").as_deref(), Some("file:///a/b.jpg"));
        assert_eq!(art_url("https://x/y.png").as_deref(), Some("https://x/y.png"));
        assert_eq!(art_url(""), None);
    }
}
