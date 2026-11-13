//! Safe shared JSON state: atomic writes, and a lock for read-modify-write.
//! Same on-disk protocol as `mediator/fileio.py`: flock on `<file>.lock`, temp file + rename.
//! Python and Rust processes can therefore update the same file during the migration.
use serde_json::{Map, Value};
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::io::AsRawFd;
use std::path::{Path, PathBuf};

pub fn atomic_write_text(path: &Path, text: &str, mode: u32) -> io::Result<()> {
    let dir = path.parent().filter(|p| !p.as_os_str().is_empty()).unwrap_or(Path::new("."));
    fs::create_dir_all(dir)?;
    let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let tmp = dir.join(format!("{name}.{}.{}.tmp", std::process::id(), nanos()));
    let result = (|| {
        let mut f = OpenOptions::new().write(true).create_new(true).open(&tmp)?;
        f.write_all(text.as_bytes())?;
        f.flush()?;
        f.sync_all()?;
        fs::set_permissions(&tmp, fs::Permissions::from_mode(mode))?;
        fs::rename(&tmp, path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    result
}

fn nanos() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0)
}

pub fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

/// The JSON at `path`, or `Value::Object({})` when missing or unreadable.
pub fn read_json(path: &Path) -> Value {
    fs::read_to_string(path)
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_else(|| Value::Object(Map::new()))
}

/// Exclusive lock on the sidecar `<path>.lock`; released on drop.
pub struct Lock(File);

pub fn locked(path: &Path) -> io::Result<Lock> {
    if let Some(dir) = path.parent().filter(|p| !p.as_os_str().is_empty()) {
        fs::create_dir_all(dir)?;
    }
    let mut lock: PathBuf = path.as_os_str().to_owned().into();
    lock.as_mut_os_string().push(".lock");
    let f = OpenOptions::new().read(true).append(true).create(true).open(lock)?;
    if unsafe { libc::flock(f.as_raw_fd(), libc::LOCK_EX) } != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(Lock(f))
}

impl Drop for Lock {
    fn drop(&mut self) {
        unsafe { libc::flock(self.0.as_raw_fd(), libc::LOCK_UN) };
    }
}

/// Read the object at `path`, let `change` edit it, write it back. Locked and atomic.
pub fn update_json(path: &Path, change: impl FnOnce(&mut Map<String, Value>)) -> io::Result<Map<String, Value>> {
    let _guard = locked(path)?;
    let mut data = match read_json(path) {
        Value::Object(m) => m,
        _ => Map::new(),
    };
    change(&mut data);
    atomic_write_text(path, &serde_json::to_string(&data).map_err(io::Error::other)?, 0o600)?;
    Ok(data)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn missing_file_reads_as_empty_object() {
        let d = tempfile::tempdir().unwrap();
        assert_eq!(read_json(&d.path().join("nope.json")), json!({}));
    }

    #[test]
    fn update_creates_and_keeps_mode() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("sub/state.json");
        update_json(&p, |m| { m.insert("a".into(), json!(1)); }).unwrap();
        update_json(&p, |m| { m.insert("b".into(), json!(2)); }).unwrap();
        assert_eq!(read_json(&p), json!({"a": 1, "b": 2}));
        assert_eq!(fs::metadata(&p).unwrap().permissions().mode() & 0o777, 0o600);
    }

    #[test]
    fn concurrent_updates_lose_nothing() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("s.json");
        let hs: Vec<_> = (0..8).map(|i| {
            let p = p.clone();
            std::thread::spawn(move || {
                for j in 0..10 {
                    update_json(&p, |m| { m.insert(format!("{i}-{j}"), json!(true)); }).unwrap();
                }
            })
        }).collect();
        for h in hs { h.join().unwrap(); }
        assert_eq!(read_json(&p).as_object().unwrap().len(), 80);
    }

    #[test]
    fn python_written_file_is_readable() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("py.json");
        let ok = std::process::Command::new("python3")
            .args(["-c", "import sys,json;json.dump({'é':1},open(sys.argv[1],'w'),ensure_ascii=False)"])
            .arg(&p).status().map(|s| s.success()).unwrap_or(false);
        if ok { assert_eq!(read_json(&p), json!({"é": 1})); }
    }
}
