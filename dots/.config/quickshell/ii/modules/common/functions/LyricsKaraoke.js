.pragma library

// Word-by-word ("karaoke") rendering helpers for synced lyrics, shared by the media view
// (modules/ii/background/MediaModeLyrics.qml) and the Music app (modules/ii/music/LyricsView.qml)
// so both read word timing the same way.
//
// computeWordRanges: per-word {begin, end, startFrac, endFrac} for a line, from the provider's
//   word timings when it has them, otherwise synthesised from the line's own timing.
// karaokeHtml: StyledText markup for the line at `pos` seconds, each word fading in as it is sung.

function computeWordRanges(lineText, words, lineStartTime, lineEndTime, nextLineStartTime) {
    if (!lineText || !lineText.trim())
        return [];

    const totalChars = lineText.length;
    if (totalChars === 0)
        return [];

    // 1. If explicit word/syllable timestamps exist (e.g. BetterLyrics syllable TTML):
    if (words && words.length > 0) {
        const ranges = [];
        let searchPos = 0;

        for (let i = 0; i < words.length; i++) {
            const w = words[i];
            const wText = (w.text || "").trim();
            if (!wText)
                continue;

            let idx = lineText.indexOf(wText, searchPos);
            if (idx === -1) {
                idx = lineText.indexOf(wText);
            }

            const begin = w.begin !== undefined ? w.begin : (w.startTime || 0);
            const end = w.end !== undefined ? w.end : (w.endTime || begin + 0.3);

            if (idx !== -1) {
                const startFrac = idx / totalChars;
                const endFrac = (idx + wText.length) / totalChars;
                ranges.push({
                    begin: begin,
                    end: end,
                    startFrac: startFrac,
                    endFrac: endFrac
                });
                searchPos = idx + wText.length;
            } else {
                const prevEnd = ranges.length > 0 ? ranges[ranges.length - 1].endFrac : 0;
                const remainingWords = words.length - i;
                const step = (1.0 - prevEnd) / remainingWords;
                ranges.push({
                    begin: begin,
                    end: end,
                    startFrac: prevEnd,
                    endFrac: prevEnd + step
                });
                searchPos = Math.round((prevEnd + step) * totalChars);
            }
        }

        if (ranges.length > 0)
            return ranges;
    }

    // 2. Synthesize word ranges from line timing (for line-synced lyrics from LRCLib or line-only TTML)
    const lineStart = (lineStartTime !== undefined && !isNaN(lineStartTime)) ? lineStartTime : 0;
    let lineEnd = (lineEndTime !== undefined && !isNaN(lineEndTime) && lineEndTime > lineStart) ? lineEndTime : 0;

    if (lineEnd <= lineStart) {
        if (nextLineStartTime !== undefined && !isNaN(nextLineStartTime) && nextLineStartTime > lineStart) {
            const gap = nextLineStartTime - lineStart;
            lineEnd = lineStart + Math.max(0.6, Math.min(gap * 0.85, gap - 0.25));
        } else {
            lineEnd = lineStart + Math.max(2.5, lineText.length * 0.16);
        }
    }

    const lineDuration = Math.max(0.4, lineEnd - lineStart);
    const ranges = [];
    const wordRegex = /\S+/g;
    const matches = [];
    let totalWordChars = 0;
    let m;
    while ((m = wordRegex.exec(lineText)) !== null) {
        matches.push({ text: m[0], index: m.index });
        totalWordChars += m[0].length;
    }

    if (matches.length > 0 && totalWordChars > 0) {
        let currentOffset = lineStart;
        for (let i = 0; i < matches.length; i++) {
            const wordMatch = matches[i];
            const charShare = wordMatch.text.length / totalWordChars;
            const wordDur = lineDuration * charShare;
            const bTime = currentOffset;
            const eTime = (i === matches.length - 1) ? lineEnd : (bTime + wordDur);
            ranges.push({
                begin: bTime,
                end: eTime,
                startFrac: wordMatch.index / totalChars,
                endFrac: (wordMatch.index + wordMatch.text.length) / totalChars
            });
            currentOffset = eTime;
        }
    }

    return ranges;
}

function colorHex(c) {
const q = Qt.color(c);
    const h = v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0");
    return "#" + h(q.a) + h(q.r) + h(q.g) + h(q.b);
}

function escapeHtml(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function karaokeHtml(lineText, wordRanges, pos, base, unsungOpacity) {
    const total = lineText.length;
    const steps = 6;
    let html = "";
    let cursor = 0;

    for (let i = 0; i < wordRanges.length; i++) {
        const r = wordRanges[i];
        const start = Math.max(cursor, Math.round(r.startFrac * total));
        const end = Math.max(start, Math.min(total, Math.round(r.endFrac * total)));

        if (start > cursor)
            html += escapeHtml(lineText.slice(cursor, start));

        const span = Math.max(0.001, r.end - r.begin);
        const progress = Math.max(0, Math.min(1, (pos - r.begin) / span));
        const level = Math.round(progress * steps) / steps;
        const color = colorHex(Qt.rgba(base.r, base.g, base.b,
            unsungOpacity + (1 - unsungOpacity) * level));

        html += "<font color=\"" + color + "\">"
            + escapeHtml(lineText.slice(start, end)) + "</font>";
        cursor = end;
    }

    if (cursor < total)
        html += "<font color=\"" + colorHex(base) + "\">"
            + escapeHtml(lineText.slice(cursor)) + "</font>";

    return html;
}
