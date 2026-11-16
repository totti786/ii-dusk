.pragma library

function localPaths(urls) {
    const paths = [];
    for (const value of urls || []) {
        const raw = String(value);
        let path = raw;
        if (raw.startsWith("file://")) {
            const match = /^file:\/\/(?:localhost)?(\/.*)$/.exec(raw);
            if (!match) continue;
            try { path = decodeURIComponent(match[1]); } catch (e) { continue; }
        } else if (!raw.startsWith("/")) continue;
        if (!path || path.indexOf("\0") >= 0 || paths.indexOf(path) >= 0) continue;
        paths.push(path);
    }
    return paths;
}
