.pragma library

// 83 -> "1:23", 3725 -> "1:02:05"
function time(seconds) {
    let s = Math.max(0, Math.floor(Number(seconds) || 0));
    const h = Math.floor(s / 3600);
    s -= h * 3600;
    const m = Math.floor(s / 60);
    s -= m * 60;
    const pad = n => (n < 10 ? "0" : "") + n;
    return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}

// "/a/b/c.mkv" -> "c.mkv"; a URL keeps its host and tail readable
function baseName(path) {
    const s = String(path ?? "");
    if (/^https?:\/\//.test(s))
        return s.replace(/^https?:\/\//, "");
    return s.split("/").pop();
}

function clock(epochSeconds) {
    const d = new Date(epochSeconds * 1000);
    const pad = n => (n < 10 ? "0" : "") + n;
    return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
