// Pure boundaries shared by both media-mode presentations.
function seekTarget(position, length, offset) {
    return Math.max(0, Math.min(length > 0 ? length : Infinity, position + offset));
}

function rateTarget(minimum, maximum, value) {
    if (!(minimum > 0 && maximum > minimum) || !Number.isFinite(value)) return null;
    return Math.max(minimum, Math.min(maximum, Math.round(value * 100) / 100));
}

function uriAllowed(uri, schemes) {
    const text = String(uri).trim();
    return /^[a-z][a-z0-9+.-]*:/i.test(text)
        && Array.from(schemes ?? []).indexOf(text.split(":")[0].toLowerCase()) >= 0;
}
