//! Desktop notifications for runs that have no terminal (keybinds, launchers).
use std::io::IsTerminal;
use std::process::{Command, Stdio};

const NOTIFY_ID: &str = "12"; // replace the previous mediator notification instead of stacking

pub fn interactive() -> bool {
    std::io::stderr().is_terminal()
}

pub fn which(name: &str) -> Option<std::path::PathBuf> {
    std::env::var_os("PATH").and_then(|p| {
        std::env::split_paths(&p).map(|d| d.join(name)).find(|f| {
            use std::os::unix::fs::PermissionsExt;
            f.metadata().map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0).unwrap_or(false)
        })
    })
}

/// Show `msg` with notify-send unless someone is watching the terminal. Never fails.
pub fn notify(msg: &str, always: bool) {
    if (interactive() && !always) || msg.is_empty() {
        return;
    }
    if let Some(exe) = which("notify-send") {
        let body: String = msg.chars().take(300).collect();
        let _ = Command::new(exe)
            .args(["-a", "mediator", "-u", "low", "-r", NOTIFY_ID, "mediator", &body])
            .stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null())
            .status();
    }
}

/// Print to stderr and notify when headless.
pub fn warn(msg: &str) {
    eprintln!("{msg}");
    notify(msg.strip_prefix("mediator: ").unwrap_or(msg), false);
}
