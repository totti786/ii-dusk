.pragma library
.import "QuranCore.js" as Core

// Verse-by-verse data for the translation view and the search: chapter facts, the loaded
// translation, and the indexes the search runs on. Core holds the Arabic text.

var chapters = [];          // chapters[s] = { id, name, meaning, place, order, bismillah, count }
var offsets = [];           // offsets[s] = index of surah s verse 1 in a flat 6236 list
var translation = null;     // flat list of strings
var translationName = "";
var arabicIndex = null;     // normalised Arabic of every verse, flat
var transIndex = null;      // lower-cased translation, flat

function setChapters(json) {
    var rows = JSON.parse(json);
    chapters = [null];
    offsets = [0, 0];
    var total = 0;
    for (var i = 0; i < rows.length; i++) {
        var r = rows[i];
        chapters.push({ id: r[0], name: r[1], meaning: r[2], place: r[3], order: r[4], bismillah: r[5] === 1, count: r[6] });
        offsets[r[0]] = total;
        total += r[6];
    }
}

function chapter(s) { return chapters[s] || null; }

function flatIndex(s, a) { return offsets[s] + a - 1; }

var translationId = -1;     // which translation `translation` holds, so a reopened reader does not parse it again

function setTranslation(json, name, id) {
    if (translation !== null && id !== undefined && id === translationId) {
        translationName = name;
        return;
    }
    translation = JSON.parse(json);
    translationName = name;
    translationId = id === undefined ? -1 : id;
    transIndex = null;
}

function translationFor(s, a) {
    return translation ? (translation[flatIndex(s, a)] || "") : "";
}

function hasTranslation() { return translation !== null; }

// --- search -----------------------------------------------------------------------

function normAr(text) {
    // Whole text, word by word, so it matches how a person types without marks
    var words = String(text).split(/\s+/), out = [];
    for (var i = 0; i < words.length; i++) {
        var n = Core.normalizeArabicWord(words[i]);
        if (n !== "") out.push(n);
    }
    return out.join(" ");
}

/** The prebuilt index (scripts/quran/build_search_index.js); without it the first search builds it. */
function setArabicIndex(json) {
    if (arabicIndex) return;
    var a = JSON.parse(json);
    if (a.length === 6236) arabicIndex = a;
}

function ensureArabicIndex() {
    if (arabicIndex) return;
    arabicIndex = new Array(6236);
    for (var s = 1; s <= 114; s++) {
        var n = chapters[s].count;
        for (var a = 1; a <= n; a++)
            arabicIndex[offsets[s] + a - 1] = normAr(Core.ayahText(s, a));
    }
}

function ensureTransIndex() {
    if (transIndex || !translation) return;
    transIndex = translation.map(function (t) { return t.toLowerCase(); });
}

function surahNameMatches(q) {
    var out = [];
    var ql = q.toLowerCase().replace(/^surah\s+|^sura\s+|^سورة\s*/, "").replace(/[-' ]/g, "");
    var qa = normAr(q.replace(/^سورة\s*/, "")).replace(/ /g, "");
    for (var s = 1; s <= 114; s++) {
        var c = chapters[s];
        var en = c.name.toLowerCase().replace(/[-' ]/g, "").replace(/[āâ]/g, "a");
        var mean = c.meaning.toLowerCase().replace(/[-' ]/g, "");
        var ar = normAr(Core.SURAH_NAMES_AR[s]).replace(/ /g, "");
        var hit = (ql.length > 0 && (en.indexOf(ql) >= 0 || mean.indexOf(ql) === 0)) || (qa.length > 0 && ar.indexOf(qa) >= 0);
        if (hit) out.push(s);
    }
    return out;
}

/**
 * { jump: {s, a}|null, surahs: [s], verses: [{s, a, kind}], total, arabic: bool }.
 * "2:255" and "2 255" jump; a bare number is a surah; Arabic text matches the unmarked
 * Arabic of the verse; anything else matches the translation. Every word must be present.
 */
function search(query, limit) {
    var q = String(query).trim();
    var res = { jump: null, surahs: [], verses: [], total: 0, arabic: false, words: [] };
    if (q === "" || chapters.length === 0) return res;
    var m = q.match(/^(\d{1,3})\s*[:\/. ]\s*(\d{1,3})$/);
    if (m) {
        var s = +m[1], a = +m[2];
        if (s >= 1 && s <= 114 && a >= 1 && a <= chapters[s].count) { res.jump = { s: s, a: a }; return res; }
    }
    if (/^\d{1,3}$/.test(q) && +q >= 1 && +q <= 114) res.surahs.push(+q);
    else res.surahs = surahNameMatches(q);

    var arabic = /[ء-ي]/.test(q);
    res.arabic = arabic;
    var words;
    var hay;
    if (arabic) {
        ensureArabicIndex();
        words = normAr(q).split(" ").filter(function (w) { return w !== ""; });
        hay = arabicIndex;
    } else {
        if (q.length < 3 || !translation) return res;
        ensureTransIndex();
        words = q.toLowerCase().split(/\s+/).filter(function (w) { return w !== ""; });
        hay = transIndex;
    }
    res.words = words;
    if (words.length === 0) return res;
    var max = limit || 100;
    for (var s2 = 1; s2 <= 114; s2++) {
        var n = chapters[s2].count;
        for (var a2 = 1; a2 <= n; a2++) {
            var text = hay[offsets[s2] + a2 - 1];
            var ok = true;
            for (var w = 0; w < words.length; w++)
                if (text.indexOf(words[w]) < 0) { ok = false; break; }
            if (!ok) continue;
            res.total++;
            if (res.verses.length < max) res.verses.push({ s: s2, a: a2 });
        }
    }
    return res;
}

function escapeHtml(t) {
    return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

/** Translation text as HTML with the searched words marked. */
function highlightTranslation(text, words, color) {
    var safe = escapeHtml(text);
    if (!words || words.length === 0) return safe;
    var re = new RegExp("(" + words.map(function (w) { return w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }).join("|") + ")", "gi");
    return safe.replace(re, '<b><font color="' + color + '">$1</font></b>');
}
