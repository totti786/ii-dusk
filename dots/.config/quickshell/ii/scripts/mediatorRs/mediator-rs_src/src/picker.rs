//! Menus (port of `mediator/picker.py`). A Picker takes labels and returns the chosen index, or
//! None on cancel. fzf (fuzzy, needs a terminal) and a plain numbered menu with no dependencies.
//! Labels are made unique before being sent to fzf so the mapping back never depends on its output.
use crate::notify::which;
use std::collections::HashMap;
use std::io::{BufRead, IsTerminal, Write};

pub trait Picker {
    fn name(&self) -> &'static str;
    fn choose(&self, labels: &[String], prompt: &str) -> Option<usize>;
}

pub fn unique(labels: &[String]) -> Vec<String> {
    let mut seen: HashMap<String, usize> = HashMap::new();
    labels.iter().map(|l| {
        let l = l.replace('\n', " ");
        let l = l.trim();
        let l = if l.is_empty() { "(untitled)".to_string() } else { l.to_string() };
        let n = seen.entry(l.clone()).or_insert(0);
        *n += 1;
        if *n == 1 { l } else { format!("{l} ({n})") }
    }).collect()
}

pub struct FzfPicker {
    pub argv: Vec<String>,
}
impl FzfPicker {
    pub fn new() -> Self {
        FzfPicker { argv: ["fzf", "--prompt", "{prompt} ", "--layout=reverse", "--tiebreak=index", "--no-multi"].map(String::from).to_vec() }
    }
    pub fn with_argv(argv: Vec<String>) -> Self {
        FzfPicker { argv }
    }
}
impl Picker for FzfPicker {
    fn name(&self) -> &'static str {
        "fzf"
    }
    fn choose(&self, labels: &[String], prompt: &str) -> Option<usize> {
        if labels.is_empty() {
            return None;
        }
        let labels = unique(labels);
        let argv: Vec<String> = self.argv.iter().map(|a| a.replace("{prompt}", prompt)).collect();
        let mut child = match std::process::Command::new(&argv[0]).args(&argv[1..]).stdin(std::process::Stdio::piped()).stdout(std::process::Stdio::piped()).spawn() {
            Ok(c) => c,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                eprintln!("mediator: fzf not found (use --picker terminal)");
                std::process::exit(1);
            }
            Err(_) => return None,
        };
        let mut stdin = child.stdin.take()?;
        let input = labels.join("\n") + "\n";
        let writer = std::thread::spawn(move || { let _ = stdin.write_all(input.as_bytes()); });
        let out = child.wait_with_output().ok()?;
        let _ = writer.join();
        if !out.status.success() {
            return None;
        }
        let chosen = String::from_utf8_lossy(&out.stdout).trim_end_matches('\n').to_string();
        labels.iter().position(|l| *l == chosen)
    }
}

/// Plain numbered menu; no dependencies.
pub struct TerminalPicker;
impl Picker for TerminalPicker {
    fn name(&self) -> &'static str {
        "terminal"
    }
    fn choose(&self, labels: &[String], prompt: &str) -> Option<usize> {
        if labels.is_empty() {
            return None;
        }
        println!("\n{prompt}");
        let width = labels.len().to_string().len();
        for (n, l) in labels.iter().enumerate() {
            println!("  {:>width$}  {l}", n + 1);
        }
        let stdin = std::io::stdin();
        loop {
            print!("number (empty to go back): ");
            let _ = std::io::stdout().flush();
            let mut line = String::new();
            if stdin.lock().read_line(&mut line).unwrap_or(0) == 0 {
                println!();
                return None;
            }
            let raw = line.trim();
            if raw.is_empty() || raw.eq_ignore_ascii_case("q") || raw.eq_ignore_ascii_case("b") {
                return None;
            }
            if let Ok(n) = raw.parse::<usize>() {
                if (1..=labels.len()).contains(&n) {
                    return Some(n - 1);
                }
            }
            println!("  not a number in the list");
        }
    }
}

/// `Err` is a message for `mediator: …` on stderr.
pub fn make_picker(spec: &str) -> Result<Box<dyn Picker>, String> {
    let mut spec = std::env::var("MEDIATOR_PICKER").ok().filter(|v| !v.is_empty()).unwrap_or_else(|| if spec.is_empty() { "auto".into() } else { spec.into() });
    if !["auto", "fzf", "terminal"].contains(&spec.as_str()) {
        eprintln!("mediator: picker {:?} is not supported (use fzf or terminal); using auto", spec);
        spec = "auto".into();
    }
    if spec == "auto" {
        if !(std::io::stdin().is_terminal() && std::io::stdout().is_terminal()) {
            return Err("browse needs a terminal (or use the Quickshell app, or --json)".into());
        }
        spec = if which("fzf").is_some() { "fzf".into() } else { "terminal".into() };
    }
    Ok(if spec == "fzf" { Box::new(FzfPicker::new()) } else { Box::new(TerminalPicker) })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn labels_are_made_unique() {
        let l: Vec<String> = ["a", "a", " ", "a\nb"].map(String::from).to_vec();
        assert_eq!(unique(&l), ["a", "a (2)", "(untitled)", "a b"]);
    }

    #[test]
    fn fzf_stand_in_picks_by_label() {
        // `head -n 2 | tail -n 1` stands in for fzf choosing the second line
        let p = FzfPicker::with_argv(vec!["sh".into(), "-c".into(), "head -n 2 | tail -n 1".into()]);
        let l: Vec<String> = ["x", "y", "y"].map(String::from).to_vec();
        assert_eq!(p.choose(&l, "p"), Some(1));
    }
}
