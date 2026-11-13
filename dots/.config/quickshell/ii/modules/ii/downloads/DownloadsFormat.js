.pragma library

function duration(sec) {
    sec = Math.round(Number(sec) || 0);
    if (sec <= 0)
        return "";
    const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
    const pad = n => (n < 10 ? "0" : "") + n;
    return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}

function bytes(n) {
    n = Number(n) || 0;
    if (n <= 0)
        return "";
    const units = ["B", "KB", "MB", "GB", "TB"];
    let i = 0;
    while (n >= 1024 && i < units.length - 1) {
        n /= 1024;
        i++;
    }
    return `${n >= 100 || i === 0 ? Math.round(n) : n.toFixed(1)} ${units[i]}`;
}

function ago(ts) {
    const s = Math.max(0, Date.now() / 1000 - ts);
    if (s < 60) return "just now";
    if (s < 3600) return `${Math.floor(s / 60)} min ago`;
    if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
    return `${Math.floor(s / 86400)} d ago`;
}

/// One line under a job's title: what it is doing right now
function jobLine(job) {
    const parts = [];
    switch (job.status) {
    case "queued": return "Waiting for a free slot";
    case "processing": return "Merging and tagging";
    case "cancelled": return "Cancelled";
    case "error": return job.error || "Failed";
    case "done":
        if (job.count > 1) parts.push(`${job.count} items`);
        if (job.total) parts.push(bytes(job.total));
        parts.push(ago(job.finished));
        return parts.join(" · ");
    }
    if (job.count > 1) parts.push(`Item ${job.index} of ${job.count}`);
    parts.push(`${job.percent.toFixed(0)}%`);
    if (job.total) parts.push(`${bytes(job.downloaded)} of ${bytes(job.total)}`);
    if (job.speed) parts.push(`${bytes(job.speed)}/s`);
    if (job.eta) parts.push(`${duration(job.eta)} left`);
    return parts.join(" · ");
}
