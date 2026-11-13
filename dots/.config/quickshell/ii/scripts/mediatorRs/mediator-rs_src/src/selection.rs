//! Pick a slice of a title's play order from user-facing codes ('S01E05', '2x03', '12')
//! (port of `mediator/selection.py`).
use crate::catalog::{Entry, Title};
use crate::parse::{norm_key, rx};

#[derive(Debug, Clone, PartialEq)]
pub struct SelectionError(pub String);
impl std::fmt::Display for SelectionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for SelectionError {}

/// Python's repr() of a string.
pub fn py_str(s: &str) -> String {
    let q = if s.contains('\'') && !s.contains('"') { '"' } else { '\'' };
    let mut out = String::from(q);
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c == q => {
                out.push('\\');
                out.push(c)
            }
            c if (c as u32) < 0x20 || c as u32 == 0x7f => out.push_str(&format!("\\x{:02x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push(q);
    out
}

fn g(x: f64) -> String {
    if x == x.trunc() { format!("{}", x as i64) } else { format!("{x}") }
}

pub fn parse_code(code: &str, title: &Title) -> Result<(i32, f64), SelectionError> {
    let c = code.trim();
    for pat in [r"(?i)^s(\d{1,2})[ ._-]?e(\d{1,4}(?:\.5)?)$", r"(?i)^(\d{1,2})x(\d{1,4}(?:\.5)?)$"] {
        if let Ok(Some(m)) = rx(pat).captures(c) {
            return Ok((m[1].parse().unwrap(), m[2].parse().unwrap()));
        }
    }
    if let Ok(Some(m)) = rx(r"^(\d{1,4}(?:\.5)?)$").captures(c) {
        let mut seasons: Vec<i32> = title.episodes().iter().filter_map(|e| e.season).collect();
        seasons.sort();
        seasons.dedup();
        if seasons.len() > 1 {
            let list: Vec<String> = seasons.iter().map(|s| s.to_string()).collect();
            return Err(SelectionError(format!("{} is ambiguous: {} has seasons {}; use S01E05 style", py_str(code), title.display(), list.join(", "))));
        }
        return Ok((seasons.first().copied().unwrap_or(1), m[1].parse().unwrap()));
    }
    Err(SelectionError(format!("can't read episode {} (try S01E05, 1x05 or 5)", py_str(code))))
}

/// Index of the episode `code` in the title's play order.
pub fn locate(title: &Title, code: &str) -> Result<usize, SelectionError> {
    let (season, ep) = parse_code(code, title)?;
    title.play_order().iter().position(|e| e.season == Some(season) && e.episode == Some(ep))
        .ok_or_else(|| SelectionError(format!("{} has no S{:02}E{}", title.display(), season, g(ep))))
}

pub fn slice_order(title: &Title, start: Option<&str>, end: Option<&str>, season: Option<i32>) -> Result<Vec<Entry>, SelectionError> {
    let mut order: Vec<Entry> = title.play_order().into_iter().cloned().collect();
    let sub;
    let sub = if let Some(s) = season {
        order.retain(|e| e.season == Some(s));
        if order.is_empty() {
            return Err(SelectionError(format!("{} has no season {s}", title.display())));
        }
        let mut t = Title::new(title.id.clone(), &title.lib, title.name.clone(), title.year);
        t.entries = order.clone();
        sub = t;
        &sub
    } else {
        title
    };
    let lo = match start.filter(|s| !s.is_empty()) { Some(s) => locate(sub, s)?, None => 0 };
    let hi = match end.filter(|s| !s.is_empty()) { Some(s) => locate(sub, s)?, None => order.len().saturating_sub(1) };
    if hi < lo {
        return Err(SelectionError("--to comes before --from".into()));
    }
    Ok(order[lo..=hi.min(order.len().saturating_sub(1))].to_vec())
}

/// Exact id, then exact name, then substring match on the normalised name.
pub fn resolve<'a>(titles: &'a [Title], query: &str) -> Vec<&'a Title> {
    if let Some(t) = titles.iter().find(|t| t.id == query) {
        return vec![t];
    }
    let q = norm_key(query);
    let exact: Vec<&Title> = titles.iter().filter(|t| norm_key(&t.display()) == q || norm_key(&t.name) == q).collect();
    if !exact.is_empty() {
        return exact;
    }
    titles.iter().filter(|t| norm_key(&t.display()).contains(&q)).collect()
}

/// `Err` is a message for `mediator: …` on stderr.
pub fn pick<'a>(titles: &'a [Title], query: &str) -> Result<&'a Title, String> {
    let found = resolve(titles, query);
    match found.len() {
        0 => Err(format!("nothing matches {}", py_str(query))),
        1 => Ok(found[0]),
        _ => {
            let lines: Vec<String> = found.iter().map(|t| format!("  {}\t{}", t.id, t.display())).collect();
            Err(format!("{} is ambiguous, use an id:\n{}", py_str(query), lines.join("\n")))
        }
    }
}
