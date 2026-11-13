.pragma library

function time(sec) {
    sec = Math.max(0, Math.round(Number(sec) || 0));
    const m = Math.floor(sec / 60), s = sec % 60;
    return `${m}:${s < 10 ? "0" : ""}${s}`;
}

function bytes(n) {
    n = Number(n) || 0;
    if (n <= 0)
        return "0 B";
    const units = ["B", "KB", "MB", "GB"];
    let i = 0;
    while (n >= 1024 && i < units.length - 1) {
        n /= 1024;
        i++;
    }
    return `${n >= 100 || i === 0 ? Math.round(n) : n.toFixed(1)} ${units[i]}`;
}

function fileUrl(path) {
    if (!path || path.length === 0)
        return "";
    // A cover that is not saved yet comes as its web address
    return path.startsWith("https://") ? path : "file://" + path;
}
