//! Blocking HTTP with plain-language errors. One agent per call keeps behaviour predictable:
//! redirects followed, short timeouts, no cookies. Errors read like `errors::describe` in Python.
use crate::errors::describe_http;
use std::io::Read;
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, PartialEq)]
pub enum HttpError {
    Status(u16),
    Other(String),
}

impl HttpError {
    /// One short phrase for why the request failed, e.g. "timed out" or "HTTP 403: refused…".
    pub fn describe(&self) -> String {
        match self {
            HttpError::Status(c) => describe_http(*c),
            HttpError::Other(s) => s.clone(),
        }
    }
    pub fn status(&self) -> Option<u16> {
        if let HttpError::Status(c) = self { Some(*c) } else { None }
    }
}

impl std::fmt::Display for HttpError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.describe())
    }
}
impl std::error::Error for HttpError {}

fn convert(e: ureq::Error) -> HttpError {
    use ureq::Error as E;
    match e {
        E::StatusCode(c) => HttpError::Status(c),
        E::Timeout(_) => HttpError::Other("timed out".into()),
        E::HostNotFound => HttpError::Other("could not find the host (offline, or DNS is down)".into()),
        E::ConnectionFailed => HttpError::Other("connection failed (the service is down or unreachable)".into()),
        E::Io(io) => HttpError::Other(crate::errors::describe_io(io.kind(), &io.to_string())),
        other => {
            let s = other.to_string();
            if s.to_lowercase().contains("tls") || s.to_lowercase().contains("certificate") {
                HttpError::Other("secure connection failed".into())
            } else {
                HttpError::Other(s)
            }
        }
    }
}

/// Hosts that told us to slow down (HTTP 429): nobody asks again until the time given.
static BLOCKED: Mutex<Option<HashMap<String, Instant>>> = Mutex::new(None);
const RATE_RETRIES: usize = 3;
const RATE_WAIT_MAX: f64 = 30.0;

fn host_key(url: &str) -> String {
    url.split("//").nth(1).unwrap_or(url).split('/').next().unwrap_or("").to_lowercase()
}

fn wait_for_host(host: &str) {
    let until = BLOCKED.lock().unwrap().as_ref().and_then(|m| m.get(host).copied());
    if let Some(t) = until {
        let now = Instant::now();
        if t > now {
            std::thread::sleep(t - now);
        }
    }
}

fn block_host(host: &str, secs: f64) {
    let until = Instant::now() + Duration::from_secs_f64(secs);
    let mut g = BLOCKED.lock().unwrap();
    let e = g.get_or_insert_with(HashMap::new).entry(host.to_string()).or_insert(until);
    if *e < until {
        *e = until;
    }
}

enum Attempt {
    Done(Vec<u8>),
    Failed(HttpError),
    Slow(f64), // 429: seconds the server asked us to wait
}

pub const UA: &str = "Mozilla/5.0 (X11; Linux x86_64; rv:134.0) Gecko/20100101 Firefox/134.0";

#[derive(Clone)]
pub struct Request<'a> {
    pub url: &'a str,
    pub headers: Vec<(&'a str, &'a str)>,
    pub body: Option<&'a [u8]>,
    pub timeout: f64,
    pub user_agent: &'a str,
}

impl<'a> Request<'a> {
    pub fn get(url: &'a str) -> Self {
        Request { url, headers: vec![], body: None, timeout: 15.0, user_agent: UA }
    }
    pub fn header(mut self, k: &'a str, v: &'a str) -> Self {
        self.headers.push((k, v));
        self
    }
    pub fn timeout(mut self, secs: f64) -> Self {
        self.timeout = secs;
        self
    }
    pub fn agent(mut self, ua: &'a str) -> Self {
        self.user_agent = ua;
        self
    }
    pub fn post(mut self, body: &'a [u8]) -> Self {
        self.body = Some(body);
        self
    }

    /// One request, retried when the host answers 429: every thread then waits out the host's
    /// `Retry-After` (capped), so a burst of parallel lookups slows down together.
    pub fn send(&self) -> Result<Vec<u8>, HttpError> {
        let host = host_key(self.url);
        for attempt in 0..=RATE_RETRIES {
            wait_for_host(&host);
            match self.send_once() {
                Attempt::Done(b) => return Ok(b),
                Attempt::Failed(e) => return Err(e),
                Attempt::Slow(secs) => {
                    block_host(&host, secs);
                    if attempt == RATE_RETRIES {
                        return Err(HttpError::Status(429));
                    }
                }
            }
        }
        unreachable!()
    }

    fn send_once(&self) -> Attempt {
        let agent: ureq::Agent = ureq::Agent::config_builder()
            .timeout_global(Some(Duration::from_secs_f64(self.timeout)))
            .http_status_as_error(false)
            .user_agent(self.user_agent)
            .build()
            .into();
        let result = match self.body {
            Some(body) => {
                let mut r = agent.post(self.url);
                for (k, v) in &self.headers {
                    r = r.header(*k, *v);
                }
                r.send(body)
            }
            None => {
                let mut r = agent.get(self.url);
                for (k, v) in &self.headers {
                    r = r.header(*k, *v);
                }
                r.call()
            }
        };
        let resp = match result {
            Ok(r) => r,
            Err(e) => return Attempt::Failed(convert(e)),
        };
        let code = resp.status().as_u16();
        if code == 429 {
            let secs = resp.headers().get("retry-after").and_then(|v| v.to_str().ok()).and_then(|v| v.trim().parse::<f64>().ok())
                .unwrap_or(5.0).clamp(1.0, RATE_WAIT_MAX);
            return Attempt::Slow(secs);
        }
        if code >= 400 {
            return Attempt::Failed(HttpError::Status(code));
        }
        let mut out = vec![];
        match resp.into_body().into_reader().take(64 * 1024 * 1024).read_to_end(&mut out) {
            Ok(_) => Attempt::Done(out),
            Err(e) => Attempt::Failed(HttpError::Other(crate::errors::describe_io(e.kind(), &e.to_string()))),
        }
    }

    pub fn text(&self) -> Result<String, HttpError> {
        self.send().map(|b| String::from_utf8_lossy(&b).into_owned())
    }

    pub fn json(&self) -> Result<serde_json::Value, HttpError> {
        let b = self.send()?;
        serde_json::from_slice(&b).map_err(|e| HttpError::Other(format!("invalid JSON ({e})")))
    }
}

/// Fetch JSON, retrying transient failures (addon CDNs drop a TLS handshake now and then).
pub fn get_json_retry(url: &str, timeout: f64, tries: usize) -> Result<serde_json::Value, HttpError> {
    let mut last = HttpError::Other("no answer".into());
    for _ in 0..tries.max(1) {
        match Request::get(url).header("Content-Type", "application/json").timeout(timeout).json() {
            Ok(v) => return Ok(v),
            Err(e) => last = e,
        }
    }
    Err(last)
}

#[doc(hidden)]
pub mod testserver {
    //! A tiny one-thread HTTP server for tests: maps path -> (status, body).
    use std::collections::HashMap;
    use std::io::{BufRead, BufReader, Write};
    use std::net::TcpListener;
    use std::sync::{Arc, Mutex};

    pub struct Server {
        pub base: String,
        pub hits: Arc<Mutex<Vec<String>>>,
    }

    pub fn serve(routes: HashMap<String, (u16, String)>) -> Server {
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", l.local_addr().unwrap());
        let hits = Arc::new(Mutex::new(vec![]));
        let h2 = hits.clone();
        std::thread::spawn(move || {
            for stream in l.incoming().flatten() {
                let mut s = stream;
                let mut r = BufReader::new(s.try_clone().unwrap());
                let mut line = String::new();
                if r.read_line(&mut line).is_err() { continue }
                let path = line.split_whitespace().nth(1).unwrap_or("/").to_string();
                loop {
                    let mut h = String::new();
                    if r.read_line(&mut h).unwrap_or(0) <= 2 { break }
                }
                h2.lock().unwrap().push(path.clone());
                let (code, body) = routes.get(&path).cloned().unwrap_or((404, "nope".into()));
                let _ = write!(s, "HTTP/1.1 {code} X\r\nContent-Length: {}\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n{body}", body.len());
            }
        });
        Server { base, hits }
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn waits_out_retry_after_then_succeeds() {
        use std::io::{Read, Write};
        let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = l.local_addr().unwrap().port();
        std::thread::spawn(move || {
            for n in 0..2 {
                let (mut c, _) = l.accept().unwrap();
                let mut buf = [0u8; 2048];
                let _ = c.read(&mut buf);
                let reply = if n == 0 {
                    "HTTP/1.1 429 Too Many Requests\r\nRetry-After: 1\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                } else {
                    "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
                };
                c.write_all(reply.as_bytes()).unwrap();
            }
        });
        let url = format!("http://127.0.0.1:{port}/");
        let t = Instant::now();
        let body = Request::get(&url).timeout(5.0).send().unwrap();
        assert_eq!(body, b"ok");
        assert!(t.elapsed() >= Duration::from_millis(900));
    }

    use super::*;
    use std::collections::HashMap;

    #[test]
    fn json_and_status_errors() {
        let s = testserver::serve(HashMap::from([("/ok".into(), (200, r#"{"a":1}"#.into())), ("/gone".into(), (403, "x".into()))]));
        assert_eq!(Request::get(&format!("{}/ok", s.base)).json().unwrap()["a"], 1);
        let e = Request::get(&format!("{}/gone", s.base)).text().unwrap_err();
        assert_eq!(e.describe(), "HTTP 403: refused the request (blocked, or the service changed)");
        assert_eq!(Request::get(&format!("{}/missing", s.base)).text().unwrap_err().status(), Some(404));
    }

    #[test]
    fn refused_connection_is_described() {
        let e = Request::get("http://127.0.0.1:1/").timeout(2.0).text().unwrap_err();
        assert!(matches!(e, HttpError::Other(_)), "{e:?}");
        assert!(!e.describe().is_empty());
    }
}
