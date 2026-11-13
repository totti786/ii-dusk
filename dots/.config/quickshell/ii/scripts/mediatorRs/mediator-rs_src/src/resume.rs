//! Decide what to play next. Pure: catalog + progress in, plan out.
use crate::catalog::{Entry, Title};
use crate::state::{finished, Progress, State};
use std::collections::HashMap;

pub const MIN_RESUME: f64 = 5.0;

#[derive(Debug, Clone, PartialEq)]
pub struct Plan {
    pub reason: &'static str, // resume | next | first | finished | replay
    pub entry: Option<Entry>,
    pub position: f64,
    pub queue: Vec<Entry>,
}

impl Plan {
    pub fn describe(&self) -> String {
        let Some(e) = &self.entry else { return "nothing to play".into() };
        let what = if e.kind != "movie" { e.label() } else { e.stem.clone() };
        match self.reason {
            "resume" => format!("resume {what} at {}", fmt_time(self.position)),
            "next" => format!("next: {what}"),
            "finished" => format!("all watched; start over with {what}"),
            "replay" => "watched; play again".into(),
            _ => format!("start: {what}"),
        }
    }
}

pub fn fmt_time(sec: f64) -> String {
    let sec = sec as i64;
    let (h, rem) = (sec / 3600, sec % 3600);
    let (m, s) = (rem / 60, rem % 60);
    if h > 0 { format!("{h}:{m:02}:{s:02}") } else { format!("{m}:{s:02}") }
}

/// Watched, or stopped with only the credits left (records saved before the tail rule).
fn done(p: &Progress) -> bool {
    p.watched || finished(p.position, p.duration, false, 1.01, 120.0)
}

fn unfinished(p: Option<&Progress>) -> bool {
    p.map(|p| !done(p) && p.position >= MIN_RESUME).unwrap_or(false)
}

fn plan(reason: &'static str, entry: Option<&Entry>, position: f64, queue: &[&Entry]) -> Plan {
    Plan { reason, entry: entry.cloned(), position, queue: queue.iter().map(|e| (*e).clone()).collect() }
}

/// What "continue" should do for `title` given everything recorded so far.
pub fn plan_for(title: &Title, progress: &HashMap<String, Progress>) -> Plan {
    let order = title.play_order();
    if order.is_empty() {
        return plan("first", None, 0.0, &[]);
    }
    let in_chain: HashMap<&str, usize> = order.iter().enumerate().map(|(i, e)| (e.path.as_str(), i)).collect();
    let others: Vec<&Entry> = title.entries.iter().filter(|e| !in_chain.contains_key(e.path.as_str())).collect();

    let latest = |entries: &[&Entry]| -> Option<(Entry, Progress)> {
        let mut best: Option<(&Entry, &Progress)> = None;
        for e in entries {
            if let Some(p) = progress.get(&e.path) {
                if best.map(|(_, b)| p.updated > b.updated).unwrap_or(true) {
                    best = Some((e, p));
                }
            }
        }
        best.map(|(e, p)| ((*e).clone(), p.clone()))
    };
    let chain = latest(&order);
    let other = latest(&others);

    if let Some((oe, op)) = &other {
        if unfinished(Some(op)) && chain.as_ref().map(|(_, cp)| op.updated > cp.updated).unwrap_or(true) {
            return plan("resume", Some(oe), op.position, &[oe]);
        }
    }
    let Some((ce, cp)) = chain else {
        return plan("first", Some(order[0]), 0.0, &order);
    };
    let i = in_chain[ce.path.as_str()];
    if unfinished(Some(&cp)) {
        return plan("resume", Some(&ce), cp.position, &order[i..]);
    }
    if !done(&cp) {
        return plan(if i == 0 { "first" } else { "next" }, Some(&ce), 0.0, &order[i..]);
    }
    if i + 1 < order.len() {
        return plan("next", Some(order[i + 1]), 0.0, &order[i + 1..]);
    }
    if title.lib == "movies" || order.len() == 1 {
        return plan("replay", Some(order[0]), 0.0, &order);
    }
    plan("finished", Some(order[0]), 0.0, &order)
}

/// "" unwatched, "watched", or a percentage for partly watched.
pub fn episode_status(p: Option<&Progress>) -> String {
    let Some(p) = p else { return String::new() };
    if p.watched {
        "watched".into()
    } else if p.position >= MIN_RESUME {
        if p.duration > 0.0 { format!("{}%", (p.ratio() * 100.0) as i64) } else { fmt_time(p.position) }
    } else {
        String::new()
    }
}

/// Mark `entries` watched. The "you are here" pointer only moves forward.
pub fn mark_watched(state: &State, title: &Title, entries: &[Entry]) -> rusqlite::Result<()> {
    let order: Vec<&str> = title.play_order().iter().map(|e| e.path.as_str()).collect::<Vec<_>>();
    let prog = state.for_title(&title.id)?;
    let (mut cur, mut best): (i64, Option<f64>) = (-1, None);
    for (i, path) in order.iter().enumerate() {
        if let Some(pr) = prog.get(*path) {
            if best.map(|b| pr.updated > b).unwrap_or(true) {
                best = Some(pr.updated);
                cur = i as i64;
            }
        }
    }
    let last = entries.iter().filter_map(|e| order.iter().position(|p| *p == e.path)).max().map(|x| x as i64).unwrap_or(-1);
    let advance = best.is_none() || last > cur;
    let items: Vec<(String, i64, String)> = entries.iter().map(|e| (e.path.clone(), e.size, e.label())).collect();
    state.mark(&items, &title.id, true, advance)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::catalog::build_catalog;

    fn show() -> Title {
        let files: Vec<(String, i64)> = (1..=3).map(|i| (format!("Show/Show S01E0{i}.mkv"), 100)).collect();
        build_catalog("shows", &files, "/l").0.remove(0)
    }
    fn prog(path: &str, pos: f64, dur: f64, watched: bool, updated: f64) -> (String, Progress) {
        (path.into(), Progress { path: path.into(), title_id: "t".into(), position: pos, duration: dur, watched, updated, size: 0, name: String::new() })
    }

    #[test]
    fn fresh_title_starts_at_first() {
        let p = plan_for(&show(), &HashMap::new());
        assert_eq!((p.reason, p.queue.len()), ("first", 3));
    }

    #[test]
    fn half_watched_resumes_and_watched_moves_on() {
        let t = show();
        let p: HashMap<_, _> = [prog("/l/Show/Show S01E01.mkv", 300.0, 1400.0, false, 1.0)].into();
        let r = plan_for(&t, &p);
        assert_eq!((r.reason, r.position, r.queue.len()), ("resume", 300.0, 3));
        let p: HashMap<_, _> = [prog("/l/Show/Show S01E01.mkv", 0.0, 1400.0, true, 1.0)].into();
        let n = plan_for(&t, &p);
        assert_eq!(n.reason, "next");
        assert_eq!(n.entry.as_ref().unwrap().code(), "S01E02");
        assert_eq!(n.describe(), "next: S01E02");
    }

    #[test]
    fn finished_show_starts_over() {
        let t = show();
        let p: HashMap<_, _> = [prog("/l/Show/Show S01E03.mkv", 0.0, 1400.0, true, 5.0)].into();
        assert_eq!(plan_for(&t, &p).reason, "finished");
    }

    #[test]
    fn status_text() {
        assert_eq!(episode_status(None), "");
        assert_eq!(episode_status(Some(&prog("a", 500.0, 1000.0, false, 1.0).1)), "50%");
        assert_eq!(fmt_time(3725.0), "1:02:05");
    }
}
