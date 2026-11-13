//! Plain-language reasons for failures, so a broken source says what is wrong.
//! Mirrors `mediator/errors.py`; the wording is part of the contract (tests compare it).
use std::fmt;

/// A streaming source could not give a stream. Every source maps its failure to this one type.
#[derive(Debug, Clone, PartialEq)]
pub struct StreamError(pub String);

impl fmt::Display for StreamError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for StreamError {}

pub fn http_reason(code: u16) -> &'static str {
    match code {
        400 => "rejected the request",
        401 => "wants a login",
        403 => "refused the request (blocked, or the service changed)",
        404 => "has nothing at that address (the link expired, or the service moved)",
        410 => "has removed that link",
        429 => "is rate limiting us (too many requests)",
        c if c >= 500 => "had a server error",
        _ => "answered unexpectedly",
    }
}

pub fn describe_http(code: u16) -> String {
    format!("HTTP {code}: {}", http_reason(code))
}

pub fn describe_io(kind: std::io::ErrorKind, fallback: &str) -> String {
    use std::io::ErrorKind::*;
    match kind {
        TimedOut | WouldBlock => "timed out".into(),
        ConnectionRefused => "connection refused (the service is down)".into(),
        ConnectionReset => "connection was reset".into(),
        _ => fallback.to_string(),
    }
}

pub fn source_error(source: &str, detail: &str) -> String {
    format!("{source}: {detail}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn http_codes_read_like_the_python_ones() {
        assert_eq!(describe_http(403), "HTTP 403: refused the request (blocked, or the service changed)");
        assert_eq!(describe_http(503), "HTTP 503: had a server error");
        assert_eq!(describe_http(418), "HTTP 418: answered unexpectedly");
    }

    #[test]
    fn io_kinds() {
        assert_eq!(describe_io(std::io::ErrorKind::TimedOut, "x"), "timed out");
        assert_eq!(describe_io(std::io::ErrorKind::NotFound, "gone"), "gone");
    }
}
