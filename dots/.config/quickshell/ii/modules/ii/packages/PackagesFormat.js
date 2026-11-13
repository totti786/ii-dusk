.pragma library

/** 1536 -> "1.5 KiB": sizes the way pacman prints them. */
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

/** Packages after which a restart is the safe thing: the kernel and what boots it. */
function needsRestart(name) {
    return /^(linux(-[a-z]+)?|linux-.*-headers|systemd|systemd-libs|glibc|nvidia(-.*)?|mesa|intel-ucode|amd-ucode|linux-firmware.*)$/.test(name);
}

function ago(ms) {
    if (!ms)
        return "";
    const s = Math.max(0, Math.round((Date.now() - ms) / 1000));
    if (s < 60)
        return "just now";
    if (s < 3600)
        return Math.round(s / 60) + " min ago";
    return Math.round(s / 3600) + " h ago";
}
