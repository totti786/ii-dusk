//! Interactive browsing on top of any Picker: library -> title -> season -> episode
//! (port of `mediator/ui.py`).
use crate::catalog::{Entry, Title};
use crate::config::Config;
use crate::jellyfin;
use crate::notify::warn;
use crate::picker::Picker;
use crate::resume::{episode_status, fmt_time, mark_watched, plan_for, Plan, MIN_RESUME};
use crate::state::{Progress, State};
use std::collections::HashMap;

pub const KIND_WORDS: [(&str, &str); 3] = [("special", "Specials"), ("movie", "Movies"), ("extra", "Extras")];
pub const LIB_WORDS: [(&str, &str); 3] = [("anime", "Anime"), ("shows", "Shows"), ("movies", "Movies")];

fn lib_word(k: &str) -> Option<&'static str> {
    LIB_WORDS.iter().find(|(a, _)| *a == k).map(|(_, b)| *b)
}

pub fn shelf_word(shelf: &str) -> String {
    if let Some(rest) = shelf.strip_prefix("jellyfin:") {
        return format!("Jellyfin · {}", lib_word(rest).unwrap_or(shelf));
    }
    lib_word(shelf).unwrap_or(shelf).to_string()
}

pub fn watched_count(t: &Title, prog: &HashMap<String, Progress>) -> (usize, usize) {
    let order = t.play_order();
    (order.iter().filter(|e| prog.get(&e.path).map(|p| p.watched).unwrap_or(false)).count(), order.len())
}

/// Short status for menus: '5/17 · next S01E06', 'resume S01E05 12:30', 'new'.
pub fn title_summary(t: &Title, prog: &HashMap<String, Progress>) -> String {
    let plan = plan_for(t, prog);
    let (done, total) = watched_count(t, prog);
    if t.lib == "movies" {
        if plan.reason == "resume" {
            return format!("resume {}", fmt_time(plan.position));
        }
        return if done > 0 { "watched".into() } else { String::new() };
    }
    if prog.is_empty() {
        return if total > 0 { format!("{total} ep{}", if total == 1 { "" } else { "s" }) } else { String::new() };
    }
    let code = plan.entry.as_ref().map(|e| e.code()).unwrap_or_default();
    match plan.reason {
        "resume" => format!("{done}/{total} · resume {code} {}", fmt_time(plan.position)),
        "finished" => format!("{done}/{total} · finished"),
        _ => format!("{done}/{total} · next {code}"),
    }
}

pub fn plan_verb(plan: &Plan) -> String {
    let Some(e) = &plan.entry else { return "Nothing to play".into() };
    let code = if e.code().is_empty() { e.label() } else { e.code() };
    match plan.reason {
        "resume" => format!("Resume {code} at {}", fmt_time(plan.position)),
        "next" => format!("Continue with {code}"),
        "first" => if e.code().is_empty() { "Play".into() } else { format!("Start {code}") },
        "finished" => format!("Watch again from {code}"),
        _ => "Play again".into(),
    }
}

pub fn entry_row(e: &Entry, p: Option<&Progress>) -> String {
    let st = episode_status(p);
    let mark = if st == "watched" { "✓ " } else if !st.is_empty() { "◐ " } else { "  " };
    let suffix = if !st.is_empty() && st != "watched" { format!("   {st}") } else { String::new() };
    format!("{mark}{}{suffix}", e.label())
}

pub type PlayFn<'a> = Box<dyn Fn(&Title, &[Entry], f64, &State, &Config) + 'a>;
pub type RemoteFn<'a> = Box<dyn Fn(bool) -> (Vec<Title>, Vec<String>) + 'a>;

/// The default player: record progress through `session::play_queue`, report problems.
pub fn default_play<'a>() -> PlayFn<'a> {
    Box::new(|t, q, start, state, cfg| {
        if let Err(e) = crate::session::play_queue(t, q, start, state, cfg, None, None) {
            eprintln!("mediator: {e}");
        }
    })
}

#[derive(Clone)]
enum Act {
    Recent,
    Shelf(String),
    Plan,
    Browse,
    Start,
    Kind(&'static str),
    Watch,
    Forget,
    Resume,
    From,
    One,
    Toggle,
}

pub struct Browser<'a> {
    pub cfg: &'a Config,
    pub state: &'a State,
    pub picker: &'a dyn Picker,
    pub titles: Vec<Title>,
    play_fn: PlayFn<'a>,
    pub once: bool,
    remote: Option<RemoteFn<'a>>,
    remote_done: bool,
    remote_fast: bool,
    pub finished: bool, // set after playback when `once`
}

impl<'a> Browser<'a> {
    pub fn new(cfg: &'a Config, state: &'a State, picker: &'a dyn Picker, titles: Vec<Title>, play: PlayFn<'a>, once: bool, remote: Option<RemoteFn<'a>>) -> Self {
        Browser { cfg, state, picker, titles, play_fn: play, once, remote, remote_done: false, remote_fast: false, finished: false }
    }

    fn prog(&self, id: &str) -> HashMap<String, Progress> {
        self.state.for_title(id).unwrap_or_default()
    }

    fn pick(&self, labels: &[String], prompt: &str) -> Option<usize> {
        self.picker.choose(labels, prompt)
    }

    // ---- playback
    pub fn play(&mut self, t: &Title, queue: &[Entry], start: f64) {
        if queue.is_empty() {
            return;
        }
        (self.play_fn)(t, queue, start, self.state, self.cfg);
        if self.once {
            self.finished = true;
        }
    }

    fn play_plan(&mut self, t: &Title, plan: &Plan) {
        if plan.entry.is_some() {
            self.play(t, &plan.queue, plan.position);
        }
    }

    fn row(&self, t: &Title) -> String {
        format!("{}    {}", t.display(), title_summary(t, &self.prog(&t.id))).trim_end().to_string()
    }

    // ---- menus
    /// Load the server's libraries. `fast` takes cached listings of any age so the menu opens at
    /// once; a later full call reloads them.
    pub fn ensure_remote(&mut self, fast: bool) {
        if self.remote.is_none() || (self.remote_done && !(self.remote_fast && !fast)) {
            return;
        }
        if self.remote_done {
            self.titles.retain(|t| t.source != "jellyfin");
        }
        self.remote_done = true;
        self.remote_fast = fast;
        let (titles, problems) = (self.remote.as_ref().unwrap())(fast);
        self.titles.extend(titles);
        for m in problems {
            warn(&format!("mediator: {m}"));
        }
    }

    pub fn run(&mut self, only_lib: Option<&str>) {
        let mut shelves: Vec<String> = LIB_WORDS.iter().map(|(k, _)| k.to_string()).filter(|k| self.titles.iter().any(|t| t.shelf() == *k)).collect();
        if self.remote.is_some() {
            shelves.extend(LIB_WORDS.iter().map(|(k, _)| format!("jellyfin:{k}")).filter(|k| self.cfg.jellyfin.libraries.get(&k["jellyfin:".len()..]).map(|v| !v.is_empty()).unwrap_or(false)));
        }
        match only_lib {
            Some("jellyfin") => shelves.retain(|k| k.starts_with("jellyfin:")),
            Some(l) => shelves = if shelves.iter().any(|k| k == l) { vec![l.to_string()] } else { vec![] },
            None => {}
        }
        if shelves.len() == 1 {
            self.library_menu(&shelves[0]);
            return;
        }
        while !self.finished {
            let mut items: Vec<(String, Act)> = vec![];
            if self.state.recent_titles(1).map(|r| !r.is_empty()).unwrap_or(false) {
                items.push(("Continue watching".into(), Act::Recent));
            }
            for k in &shelves {
                if k.starts_with("jellyfin:") && !self.remote_done {
                    items.push((shelf_word(k), Act::Shelf(k.clone())));
                } else {
                    let n = self.titles.iter().filter(|t| t.shelf() == *k).count();
                    items.push((format!("{}  ({n})", shelf_word(k)), Act::Shelf(k.clone())));
                }
            }
            let labels: Vec<String> = items.iter().map(|i| i.0.clone()).collect();
            let Some(i) = self.pick(&labels, "mediator") else { return };
            match items[i].1.clone() {
                Act::Recent => self.recent_menu(),
                Act::Shelf(k) => self.library_menu(&k),
                _ => {}
            }
        }
    }

    fn recent_menu(&mut self) {
        if self.state.recent_titles(25).unwrap_or_default().iter().any(|p| p.title_id.starts_with("jellyfin/")) {
            self.ensure_remote(true);
        }
        while !self.finished {
            let recent = self.state.recent_titles(25).unwrap_or_default();
            let found: Vec<Title> = recent.iter().filter_map(|p| self.titles.iter().find(|t| t.id == p.title_id).cloned()).collect();
            let labels: Vec<String> = found.iter().map(|t| self.row(t)).collect();
            let Some(i) = self.pick(&labels, "Continue watching") else { return };
            let t = found[i].clone();
            let plan = plan_for(&t, &self.prog(&t.id));
            if plan.reason == "finished" {
                self.title_menu(&t);
            } else {
                self.play_plan(&t, &plan);
            }
        }
    }

    fn library_menu(&mut self, lib: &str) {
        if lib.starts_with("jellyfin:") {
            self.ensure_remote(false);
        }
        let titles: Vec<Title> = self.titles.iter().filter(|t| t.shelf() == lib).cloned().collect();
        if titles.is_empty() {
            warn(&format!("mediator: nothing in {}", shelf_word(lib)));
            return;
        }
        while !self.finished {
            let labels: Vec<String> = titles.iter().map(|t| self.row(t)).collect();
            let Some(i) = self.pick(&labels, &shelf_word(lib)) else { return };
            self.title_menu(&titles[i]);
        }
    }

    fn title_menu(&mut self, t: &Title) {
        while !self.finished {
            let prog = self.prog(&t.id);
            let plan = plan_for(t, &prog);
            let mut items: Vec<(String, Act)> = vec![];
            if plan.entry.is_some() {
                items.push((format!("▶ {}", plan_verb(&plan)), Act::Plan));
            }
            if t.lib != "movies" {
                if !t.episodes().is_empty() {
                    items.push(("Browse episodes".into(), Act::Browse));
                }
                if plan.entry.is_some() && (plan.reason == "resume" || plan.reason == "next") {
                    items.push(("Play from the beginning".into(), Act::Start));
                }
                for (kind, word) in KIND_WORDS {
                    let n = t.of_kind(kind).len();
                    if n > 0 {
                        items.push((format!("{word}  ({n})"), Act::Kind(kind)));
                    }
                }
                items.push(("Mark all watched".into(), Act::Watch));
                if !prog.is_empty() {
                    items.push(("Forget progress".into(), Act::Forget));
                }
            } else if plan.reason == "resume" {
                items.push(("Play from the start".into(), Act::Start));
            }
            let labels: Vec<String> = items.iter().map(|i| i.0.clone()).collect();
            let Some(i) = self.pick(&labels, &t.display()) else { return };
            let order: Vec<Entry> = t.play_order().into_iter().cloned().collect();
            match items[i].1.clone() {
                Act::Plan => self.play_plan(t, &plan),
                Act::Start => self.play(t, &order, 0.0),
                Act::Browse => self.browse_episodes(t),
                Act::Watch => self.mark(t, &order, true),
                Act::Forget => {
                    let _ = self.state.forget_title(&t.id);
                }
                Act::Kind(k) => self.kind_menu(t, k),
                _ => {}
            }
        }
    }

    fn browse_episodes(&mut self, t: &Title) {
        let seasons: Vec<(i32, Vec<Entry>)> = t.seasons().into_iter().map(|(s, v)| (s, v.into_iter().cloned().collect())).collect();
        if seasons.len() <= 1 {
            let eps = seasons.into_iter().next().map(|s| s.1).unwrap_or_default();
            self.episode_list(t, &eps, &t.display());
            return;
        }
        while !self.finished {
            let prog = self.prog(&t.id);
            let labels: Vec<String> = seasons.iter().map(|(s, eps)| {
                let done = eps.iter().filter(|e| prog.get(&e.path).map(|p| p.watched).unwrap_or(false)).count();
                format!("Season {s}    {done}/{}", eps.len())
            }).collect();
            let Some(i) = self.pick(&labels, &t.display()) else { return };
            self.episode_list(t, &seasons[i].1, &format!("{} · Season {}", t.display(), seasons[i].0));
        }
    }

    fn episode_list(&mut self, t: &Title, eps: &[Entry], prompt: &str) {
        while !self.finished {
            let prog = self.prog(&t.id);
            let labels: Vec<String> = eps.iter().map(|e| entry_row(e, prog.get(&e.path))).collect();
            let Some(i) = self.pick(&labels, prompt) else { return };
            self.episode_menu(t, &eps[i]);
        }
    }

    fn episode_menu(&mut self, t: &Title, e: &Entry) {
        let order: Vec<Entry> = t.play_order().into_iter().cloned().collect();
        let idx = order.iter().position(|x| x.path == e.path);
        while !self.finished {
            let p = self.state.get(&e.path, e.size).ok().flatten();
            let mut items: Vec<(String, Act)> = vec![];
            if let Some(p) = p.as_ref().filter(|p| !p.watched && p.position >= 5.0) {
                items.push((format!("▶ Resume at {}", fmt_time(p.position)), Act::Resume));
            }
            if idx.is_some() {
                items.push(("▶ Play from here (keeps going through the series)".into(), Act::From));
            }
            items.push(("▶ Play only this one".into(), Act::One));
            let is_watched = p.as_ref().map(|p| p.watched).unwrap_or(false);
            items.push((if is_watched { "Mark unwatched" } else { "Mark watched" }.into(), Act::Toggle));
            let labels: Vec<String> = items.iter().map(|i| i.0.clone()).collect();
            let Some(i) = self.pick(&labels, &e.label()) else { return };
            let act = items[i].1.clone();
            match act {
                Act::Resume => {
                    let q: Vec<Entry> = match idx { Some(i) => order[i..].to_vec(), None => vec![e.clone()] };
                    self.play(t, &q, p.as_ref().map(|p| p.position).unwrap_or(0.0));
                }
                Act::From => self.play(t, &order[idx.unwrap_or(0)..], 0.0),
                Act::One => self.play(t, std::slice::from_ref(e), 0.0),
                Act::Toggle => self.mark(t, std::slice::from_ref(e), !is_watched),
                _ => {}
            }
            if matches!(act, Act::Resume | Act::From | Act::One) {
                return;
            }
        }
    }

    fn kind_menu(&mut self, t: &Title, kind: &str) {
        let entries: Vec<Entry> = t.of_kind(kind).into_iter().cloned().collect();
        let word = KIND_WORDS.iter().find(|(k, _)| *k == kind).map(|(_, w)| *w).unwrap_or("");
        while !self.finished {
            let prog = self.prog(&t.id);
            let labels: Vec<String> = entries.iter().map(|e| entry_row(e, prog.get(&e.path))).collect();
            let Some(i) = self.pick(&labels, &format!("{} · {word}", t.display())) else { return };
            let e = &entries[i];
            let start = prog.get(&e.path).filter(|p| !p.watched && p.position >= MIN_RESUME).map(|p| p.position).unwrap_or(0.0);
            self.play(t, std::slice::from_ref(e), start);
        }
    }

    fn mark(&mut self, t: &Title, entries: &[Entry], watched: bool) {
        if watched {
            let _ = mark_watched(self.state, t, entries);
        } else {
            let items: Vec<(String, i64, String)> = entries.iter().map(|e| (e.path.clone(), e.size, e.label())).collect();
            let _ = self.state.mark(&items, &t.id, false, false);
        }
        if let Some(problem) = jellyfin::push_marks(&self.cfg.jellyfin, entries, watched, None) {
            warn(&format!("mediator: {problem}"));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::{Cell, RefCell};

    struct Script(RefCell<Vec<Option<usize>>>, RefCell<Vec<String>>);
    impl Picker for Script {
        fn name(&self) -> &'static str {
            "script"
        }
        fn choose(&self, labels: &[String], prompt: &str) -> Option<usize> {
            self.1.borrow_mut().push(format!("{prompt}: {}", labels.join(" | ")));
            let mut s = self.0.borrow_mut();
            if s.is_empty() { None } else { s.remove(0) }
        }
    }

    fn title() -> Title {
        let mut t = Title::new("shows/x".into(), "shows", "X".into(), None);
        for n in 1..=3 {
            t.entries.push(Entry { path: format!("/x/{n}.mkv"), rel: format!("X/{n}.mkv"), size: 10, kind: "episode".into(), season: Some(1), episode: Some(n as f64),
                episode_end: None, version: 1, name: String::new(), rule: "t".into(), confidence: "high".into(), stem: format!("{n}"), remote_id: String::new() });
        }
        t
    }

    #[test]
    fn plays_the_plan_from_the_title_menu() {
        let st = State::memory().unwrap();
        let cfg = Config::default();
        let picker = Script(RefCell::new(vec![Some(0), Some(0)]), RefCell::new(vec![]));
        let played = RefCell::new(vec![]);
        let calls = Cell::new(0);
        let play: PlayFn = Box::new(|_, q, start, _, _| {
            calls.set(calls.get() + 1);
            played.borrow_mut().push((q.len(), start));
        });
        let mut b = Browser::new(&cfg, &st, &picker, vec![title()], play, true, None);
        b.run(None);
        assert_eq!(calls.get(), 1);
        assert_eq!(played.borrow()[0], (3, 0.0));
        assert!(b.finished);
        assert!(picker.1.borrow()[0].starts_with("Shows: X    3 eps"), "{:?}", picker.1.borrow());
        assert!(picker.1.borrow()[1].contains("▶ Start S01E01"), "{:?}", picker.1.borrow());
    }

    #[test]
    fn summary_reads_like_the_menu() {
        let t = title();
        assert_eq!(title_summary(&t, &HashMap::new()), "3 eps");
    }
}
