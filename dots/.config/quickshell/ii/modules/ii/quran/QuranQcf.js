.pragma library

// quran.com's Madani page data: every text line of a page as glyph codes for that page's own
// font (the v2 "QCF" fonts), so lines break and look exactly like the printed mushaf.
// Fetched once by scripts/quran/pages.py.

var pages = null;       // one JSON string per page, parsed on first use
var parsed = {};
var fontDir = "";

function pageData(n) {
    var p = pages[n - 1];
    if (typeof p !== "string") return p;
    var d = parsed[n];
    if (!d) { d = JSON.parse(p); parsed[n] = d; }
    return d;
}

function set(json, dir) {
    pages = JSON.parse(json);
    parsed = {};
    fontDir = dir;
}

function clear() {
    pages = null;
    parsed = {};
    fontDir = "";
}

function ready() { return pages !== null; }

var BASMALAH = "\u0628\u0650\u0633\u0652\u0645\u0650 \u0671\u0644\u0644\u0651\u064e\u0647\u0650 \u0671\u0644\u0631\u0651\u064e\u062d\u0652\u0645\u064e\u0640\u0670\u0646\u0650 \u0671\u0644\u0631\u0651\u064e\u062d\u0650\u064a\u0645\u0650";

function wordsOf(raw) {
    return raw.map(function (w) {
        return { key: w[0], i: w[1], end: w[2] === 1, sign: w[2] === 2, code: w[3], ar: w[4] };
    });
}

function blankLine(n) {
    return { n: n, stretch: -1, kind: "text", title: "", basmalah: "", parts: [] };
}

/**
 * Pages whose line numbering differs from the manifest (another print of the same verses): the 15
 * lines are rebuilt from quran.com's own data. A line number with no words is a surah banner, then
 * the basmalah, in front of the line that opens verse 1. `names` are the Arabic surah names.
 */
function fromApi(model, data, names) {
    var lines = [];
    var n = 1;
    while (n <= 15) {
        var raw = data[String(n)];
        if (raw) {
            var ln = blankLine(n);
            ln.words = wordsOf(raw);
            var seen = {};
            for (var i = 0; i < ln.words.length; i++) {
                var key = ln.words[i].key;
                if (key && !seen[key]) {
                    seen[key] = true;
                    var kp = key.split(":");
                    ln.parts.push({ tokens: [], segs: [], surah: +kp[0], ayah: +kp[1], realAyah: +kp[1], key: key });
                }
            }
            lines.push(ln);
            n++;
            continue;
        }
        var start = n;
        while (n <= 15 && !data[String(n)]) n++;
        var next = n <= 15 ? data[String(n)] : null;
        var first = next && next[0] && next[0][0] ? String(next[0][0]).split(":") : null;
        var banner = first !== null && +first[1] === 1 && names && names[+first[0]];
        for (var k = start; k < n; k++) {
            var b = blankLine(k);
            if (banner && k === start) {
                b.kind = "title";
                b.title = "\u0633\u0648\u0631\u0629 " + names[+first[0]];
            } else if (banner && k === start + 1 && +first[0] !== 9) {
                b.kind = "basmalah";
                b.basmalah = BASMALAH;
            }
            lines.push(b);
        }
    }
    model.lines = lines;
    return model;
}

/** Adds `qcf` words to the text lines of a Core page model; rebuilds the lines from the page data when they do not fit. */
function attach(model, names) {
    if (!pages || !pages[model.page - 1]) return model;
    var data = pageData(model.page).l;
    var per = {};
    var used = 0;
    var fits = true;
    for (var i = 0; i < model.lines.length; i++) {
        var line = model.lines[i];
        var words = data[String(line.n)];
        if (words && line.kind !== "text") { fits = false; break; }
        if (line.kind === "text" && words) {
            per[line.n] = wordsOf(words);
            used++;
        }
    }
    // every line of the API must have landed on a text line
    if (fits && used !== Object.keys(data).length) fits = false;
    if (fits) {
        for (var j = 0; j < model.lines.length; j++)
            if (per[model.lines[j].n]) model.lines[j].words = per[model.lines[j].n];
    } else {
        fromApi(model, data, names);
    }
    model.qcf = true;
    model.fontUrl = "file://" + fontDir + "/p" + model.page + ".woff2";
    return model;
}
