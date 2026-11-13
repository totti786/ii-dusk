.pragma library

function bytes(n) {
    n = Number(n) || 0;
    const units = ["B", "KB", "MB", "GB", "TB"];
    let i = 0;
    while (n >= 1024 && i < units.length - 1) {
        n /= 1024;
        i++;
    }
    return `${n >= 100 || i === 0 ? Math.round(n) : n.toFixed(1)} ${units[i]}`;
}

function rate(n) {
    return bytes(n) + "/s";
}

function percent(n) {
    return `${Math.round(Number(n) || 0)}%`;
}

function ms(v) {
    if (v === undefined || v === null || v < 0)
        return "–";
    return v < 10 ? `${v.toFixed(1)} ms` : `${Math.round(v)} ms`;
}

function duration(sec) {
    sec = Math.max(0, Math.floor(Number(sec) || 0));
    const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60);
    return d > 0 ? `${d}d ${h}h` : h > 0 ? `${h}h ${m}m` : `${m}m ${sec % 60}s`;
}

/// How good a round trip is: 0 fine, 1 slow, 2 bad, -1 lost
function quality(v) {
    if (v === undefined || v === null || v < 0)
        return -1;
    return v < 60 ? 0 : v < 150 ? 1 : 2;
}
