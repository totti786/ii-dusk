.pragma library

function bytes(n) {
    n = Number(n) || 0;
    const units = ["B", "KiB", "MiB", "GiB", "TiB"];
    let i = 0;
    while (n >= 1024 && i < units.length - 1) {
        n /= 1024;
        i++;
    }
    return (i === 0 || n >= 100 ? Math.round(n) : n.toFixed(1)) + " " + units[i];
}

function speed(n) {
    return bytes(n) + "/s";
}

function eta(seconds) {
    if (seconds === undefined || seconds < 0 || seconds >= 8640000)
        return "";
    if (seconds < 60)
        return seconds + " s";
    if (seconds < 3600)
        return Math.floor(seconds / 60) + " min";
    if (seconds < 86400)
        return Math.floor(seconds / 3600) + " h " + Math.floor((seconds % 3600) / 60) + " min";
    return Math.floor(seconds / 86400) + " d";
}

function percent(p) {
    return Math.round((Number(p) || 0) * 100) + " %";
}

// What a state means to a person, and the group it belongs to
function group(state) {
    if (["downloading", "forcedDL", "metaDL", "forcedMetaDL", "stalledDL", "queuedDL", "checkingDL", "allocating"].includes(state))
        return "downloading";
    if (["uploading", "forcedUP", "stalledUP", "queuedUP", "checkingUP"].includes(state))
        return "seeding";
    if (state === "error" || state === "missingFiles")
        return "errored";
    if (state.startsWith("stopped") || state.startsWith("paused"))
        return "paused";
    return "other";
}

function label(state) {
    switch (state) {
    case "downloading": case "forcedDL": return "Downloading";
    case "metaDL": case "forcedMetaDL": return "Fetching info";
    case "stalledDL": return "Stalled";
    case "queuedDL": case "queuedUP": return "Queued";
    case "checkingDL": case "checkingUP": case "checkingResumeData": return "Checking";
    case "uploading": case "forcedUP": return "Seeding";
    case "stalledUP": return "Seeding, no peers";
    case "stoppedDL": case "pausedDL": return "Paused";
    case "stoppedUP": case "pausedUP": return "Finished";
    case "error": return "Error";
    case "missingFiles": return "Files missing";
    case "moving": return "Moving";
    case "allocating": return "Allocating";
    default: return state;
    }
}

function isPaused(state) {
    return state.startsWith("stopped") || state.startsWith("paused");
}

function date(ts) {
    if (!ts || ts <= 0)
        return "";
    const d = new Date(ts * 1000);
    return Qt.formatDateTime(d, "d MMM yyyy, hh:mm");
}

function duration(seconds) {
    seconds = Math.max(0, Number(seconds) || 0);
    if (seconds < 60)
        return seconds + " s";
    if (seconds < 3600)
        return Math.floor(seconds / 60) + " min";
    if (seconds < 86400)
        return Math.floor(seconds / 3600) + " h " + Math.floor((seconds % 3600) / 60) + " min";
    return Math.floor(seconds / 86400) + " d " + Math.floor((seconds % 86400) / 3600) + " h";
}

function priorityLabel(p) {
    return p === 0 ? "Skipped" : p === 1 ? "Normal" : p === 6 ? "High" : p === 7 ? "Maximum" : "Normal";
}

/// The next priority when a file's priority button is pressed
function nextPriority(p) {
    return p === 1 ? 6 : p === 6 ? 7 : 1;
}
