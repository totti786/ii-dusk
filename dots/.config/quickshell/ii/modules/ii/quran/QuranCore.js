.pragma library

// Ported from the Quran Reader Kit (src/core/quran.ts + quranAudio.ts, MIT, from syrianzone):
// Madina 15-line page model, juz/page math and the karaoke helpers. No UI in here.
// Text is never word-split during layout, so Arabic letter joining survives; splitting for
// karaoke happens only at whitespace.

var TOTAL_PAGES = 604;
var RLM = "⁤";

var manifests = { 16: null, 24: null };
var surahs = [];       // surahs[s].ayahs[a] = { p, r: [{l, t, s16, s24}] } | null
var ready = false;

function setData(m16, m24, unifiedText) {
    manifests[16] = JSON.parse(m16);
    manifests[24] = JSON.parse(m24);
    surahs = manifests[16].suras.map(function (s) {
        var a = new Array(s[1]);
        for (var i = 0; i < a.length; i++) a[i] = null;
        return { name: s[0], ayahs: a };
    });
    var data = JSON.parse(unifiedText);
    for (var j = 0; j < data.length; j++) {
        var juz = data[j];
        for (var k = 0; k < juz.length; k++) {
            var rec = juz[k];
            var surah = surahs[rec[0]];
            if (surah && rec[1] < surah.ayahs.length) {
                surah.ayahs[rec[1]] = {
                    p: rec[2],
                    r: rec[3].map(function (pt) { return { l: pt[0], t: pt[1], s16: pt[2], s24: pt[3] }; })
                };
            }
        }
    }
    ready = true;
}

function isReady() { return ready; }

// --- anchors -----------------------------------------------------------------

function nearestAnchor(size) { return Math.abs(size - 16) <= Math.abs(size - 24) ? 16 : 24; }

function fittedLineWidth(size, lw16, lw24) {
    return Math.round(lw16 + (lw24 - lw16) * ((size - 16) / 8));
}

function stretchScaleFor(size, lw16, lw24) {
    var near = nearestAnchor(size);
    var lwNear = near === 16 ? lw16 : lw24;
    var lwS = fittedLineWidth(size, lw16, lw24);
    return (lwS * near) / (lwNear * size);
}

// --- navigation ----------------------------------------------------------------

function surahCount() { return surahs.length; }
function ayahCount(s1) { return surahs[s1 - 1] ? surahs[s1 - 1].ayahs.length - 2 : 0; }

function juzNumberForPage(page) {
    var juz = manifests[16].juz;
    var n = 1;
    for (var i = 0; i < juz.length; i++) {
        if (page >= juz[i][2]) n = i + 1;
        else break;
    }
    return n;
}

function juzStartPage(juz1) {
    var j = manifests[16].juz[juz1 - 1];
    return j ? j[2] : 1;
}

/** Page containing a real ayah (1-based surah + ayah), or 0. */
function findPageForAyah(surah1, ayah1) {
    if (!(surah1 >= 1 && surah1 <= 114 && ayah1 >= 1)) return 0;
    var pages = manifests[16].pages;
    var s0 = surah1 - 1;
    var a = ayah1 + 1;
    for (var p = 0; p < pages.length; p++) {
        var b = pages[p];
        var afterStart = b[0] < s0 || (b[0] === s0 && b[1] <= a);
        var beforeEnd = b[2] > s0 || (b[2] === s0 && b[3] >= a);
        if (afterStart && beforeEnd) return p + 1;
    }
    return 0;
}

/** First page of a surah (its title frame). */
function surahStartPage(surah1) {
    var pages = manifests[16].pages;
    for (var p = 0; p < pages.length; p++) {
        var b = pages[p];
        if (b[0] <= surah1 - 1 && b[2] >= surah1 - 1) return p + 1;
    }
    return 1;
}

/** Surah (1-based) whose text starts the page. */
function surahForPage(page) {
    var b = manifests[16].pages[page - 1];
    return b ? b[0] + 1 : 1;
}

/** Accepts "2:255" or a page number; returns {page, key} or null. */
function parseJump(text) {
    var t = String(text).trim();
    var m = t.match(/^(\d{1,3})\s*[:\/.\s]\s*(\d{1,3})$/);
    if (m) {
        var p = findPageForAyah(+m[1], +m[2]);
        return p ? { page: p, key: (+m[1]) + ":" + (+m[2]) } : null;
    }
    if (/^\d+$/.test(t)) {
        var n = +t;
        return n >= 1 && n <= TOTAL_PAGES ? { page: n, key: "" } : null;
    }
    return null;
}

// --- page model ----------------------------------------------------------------

/**
 * The 15-line model of a page. Each line: { n, stretch, kind: "text"|"title"|"basmalah",
 * title, basmalah, parts: [{ text, surah, ayah, realAyah, key }] }.
 */
function buildPage(page, fontSize) {
    var anchor = nearestAnchor(fontSize);
    var man = manifests[anchor];
    var lw16 = manifests[16].line_width;
    var lw24 = manifests[24].line_width;
    var bounds = man.pages[page - 1];
    var lines = [];
    var wordCounters = {};
    for (var l = 1; l <= 15; l++)
        lines.push({ n: l, stretch: -1, kind: "text", title: "", basmalah: "", parts: [] });

    for (var s = bounds[0]; s <= bounds[2]; s++) {
        var startA = s === bounds[0] ? bounds[1] : 0;
        var total = surahs[s] ? surahs[s].ayahs.length : 0;
        var endA = s === bounds[2] ? bounds[3] : total - 1;
        for (var a = startA; a <= endA; a++) {
            var ayah = surahs[s] ? surahs[s].ayahs[a] : null;
            if (!ayah || ayah.p !== page) continue;
            for (var i = 0; i < ayah.r.length; i++) {
                var part = ayah.r[i];
                var line = lines[part.l - 1];
                if (!line) continue;
                var stretch = anchor === 16 ? part.s16 : part.s24;
                if (stretch >= 0 && line.stretch < 0) line.stretch = stretch;
                var titleSlot = (s === 0 && a === 1) || (s > 0 && a === 0);
                if (titleSlot && part.t && part.t.trim().length > 0) {
                    line.kind = "title";
                    line.title = part.t.trim();
                    line.stretch = -1;
                    continue;
                }
                var basmalahSlot = s > 0 && s !== 8 && a === 1;
                if (basmalahSlot && part.t && part.t.trim().length > 0) {
                    line.kind = "basmalah";
                    line.stretch = -1;
                    if (!line.basmalah) line.basmalah = part.t;
                    continue;
                }
                if (part.t && part.t.length > 0) {
                    var real = a >= 2 ? a - 1 : 0;
                    var key = real > 0 ? (s + 1) + ":" + real : "";
                    var tokens = tokenize(part.t, key, wordCounters);
                    line.parts.push({
                        tokens: tokens,
                        segs: segments(tokens),
                        surah: s + 1,
                        ayah: a,
                        realAyah: real,
                        key: key
                    });
                }
            }
        }
    }
    return {
        page: page,
        juz: juzNumberForPage(page),
        surah: surahForPage(page),
        lines: lines,
        lineWidth: anchor === 16 ? lw16 : lw24,
        stretchScale: stretchScaleFor(fontSize, lw16, lw24)
    };
}

/**
 * Tokens of a part: { k: "w" word | "s" space | "y" symbol | "m" marker, v, i } where i is the
 * word's index inside its ayah (counted across the parts of the page). Splitting happens only
 * at whitespace and around markers, so Arabic letter joining is never broken.
 */
function tokenize(text, key, counters) {
    var out = [];
    var pieces = splitMarkers(text);
    for (var i = 0; i < pieces.length; i++) {
        if (pieces[i].kind === "marker") { out.push({ k: "m", v: pieces[i].value, i: -1 }); continue; }
        var runs = pieces[i].value.match(/\s+|\S+/g) || [];
        for (var j = 0; j < runs.length; j++) {
            var run = runs[j];
            if (/^\s/.test(run)) out.push({ k: "s", v: run, i: -1 });
            else if (normalizeArabicWord(run) === "") out.push({ k: "y", v: run, i: -1 });
            else {
                var idx = key ? (counters[key] || 0) : -1;
                if (key) counters[key] = idx + 1;
                out.push({ k: "w", v: run, i: idx });
            }
        }
    }
    return out;
}

/**
 * The same part as a few big pieces: consecutive words, spaces and symbols joined into one text
 * run, markers kept apart. Cheap to build; the per-word tokens are used only for the ayah that
 * is being recited.
 */
function segments(tokens) {
    var out = [];
    var run = "";
    for (var i = 0; i < tokens.length; i++) {
        if (tokens[i].k === "m") {
            if (run !== "") out.push({ k: "t", v: run, i: -1 });
            run = "";
            out.push(tokens[i]);
        } else {
            run += tokens[i].v;
        }
    }
    if (run !== "") out.push({ k: "t", v: run, i: -1 });
    return out;
}

/** Local words of every ayah on a page: { "2:255": [words] }. */
function pageWords(model) {
    var map = {};
    if (model.qcf) {
        for (var q = 0; q < model.lines.length; q++) {
            var ws = model.lines[q].words || [];
            for (var r = 0; r < ws.length; r++)
                if (ws[r].i >= 0) {
                    if (!map[ws[r].key]) map[ws[r].key] = [];
                    map[ws[r].key][ws[r].i] = ws[r].ar;
                }
        }
        return map;
    }
    for (var l = 0; l < model.lines.length; l++)
        for (var p = 0; p < model.lines[l].parts.length; p++) {
            var part = model.lines[l].parts[p];
            if (!part.key) continue;
            if (!map[part.key]) map[part.key] = [];
            for (var t = 0; t < part.tokens.length; t++)
                if (part.tokens[t].k === "w") map[part.key][part.tokens[t].i] = part.tokens[t].v;
        }
    return map;
}

/** Next/previous real ayah (1-based surah:ayah) crossing surah boundaries. */
/** Plain text of an ayah ("surah:ayah" numbers), without its end marker; "" when unknown. */
function ayahText(surah1, ayah1) {
    var sur = surahs[surah1 - 1];
    var ayah = sur ? sur.ayahs[ayah1 + 1] : null;
    if (!ayah) return "";
    var text = "";
    for (var i = 0; i < ayah.r.length; i++) text += " " + (ayah.r[i].t || "");
    return text.replace(/﴿[٠-٩]{1,3}﴾/g, "").replace(/\s+/g, " ").trim();
}

/** The first `n` words of an ayah, with an ellipsis when there is more. */
function ayahPreview(surah1, ayah1, n) {
    var words = ayahText(surah1, ayah1).split(" ");
    return words.slice(0, n).join(" ") + (words.length > n ? " …" : "");
}

function stepAyah(surah, ayah, delta) {
    var a = ayah + delta;
    var s = surah;
    if (a < 1) {
        if (s <= 1) return null;
        s -= 1;
        a = ayahCount(s);
    } else if (a > ayahCount(s)) {
        if (s >= 114) return null;
        s += 1;
        a = 1;
    }
    return { surah: s, ayah: a };
}

// --- tokens + karaoke ------------------------------------------------------------

/** Parts of a display text: [{ kind: "text"|"marker", value }], concatenation reproduces it. */
function splitMarkers(text) {
    var out = [];
    var last = 0;
    text.replace(/﴿([٠-٩]{1,3})﴾/g, function (all, digits, index) {
        if (index > last) out.push({ kind: "text", value: text.slice(last, index) });
        out.push({ kind: "marker", value: digits });
        last = index + all.length;
        return all;
    });
    if (last < text.length) out.push({ kind: "text", value: text.slice(last) });
    return out;
}

function normalizeArabicWord(word) {
    return word
        .replace(/[ؐ-ًؚ-ٰٟۖ-ۤۧ-ۭـࣰ-ࣿ]/g, "")
        .replace(/ۥ/g, "و")
        .replace(/ۦ/g, "ي")
        .replace(/[​-‏⁦-⁩﻿]/g, "")
        .replace(/[أإآٱٲٳ]/g, "ا")
        .replace(/ى/g, "ي")
        .replace(/ة/g, "ه")
        .replace(/ئ/g, "ي")
        .replace(/ؤ/g, "و")
        .replace(/ء/g, "")
        .replace(/[^ء-ي]/g, "")
        .replace(/(.)\1+/g, "$1");
}

/** Whole words of an ayah's text (markers, symbols and whitespace dropped). */
function wordsOfText(text) {
    var words = [];
    var parts = splitMarkers(text);
    for (var i = 0; i < parts.length; i++) {
        if (parts[i].kind !== "text") continue;
        var pieces = parts[i].value.split(/\s+/);
        for (var j = 0; j < pieces.length; j++)
            if (pieces[j] !== "" && normalizeArabicWord(pieces[j]) !== "") words.push(pieces[j]);
    }
    return words;
}

/** API word index -> local word index, or null when the two cannot be reconciled. */
function alignWordIndexes(local, api) {
    if (local.length === 0 || api.length === 0) return null;
    var L = local.map(normalizeArabicWord);
    var A = api.map(normalizeArabicWord);
    var map = [];
    for (var x = 0; x < A.length; x++) map.push(-1);
    var i = 0, j = 0;
    while (i < L.length && j < A.length) {
        if (L[i] !== "" && L[i] === A[j]) { map[j] = i; i++; j++; continue; }
        if (i + 1 < L.length && L[i] + L[i + 1] === A[j]) { map[j] = i; i += 2; j++; continue; }
        if (j + 1 < A.length && L[i] === A[j] + A[j + 1]) { map[j] = i; map[j + 1] = i; i++; j += 2; continue; }
        return null;
    }
    if (i !== L.length || j !== A.length) return null;
    return map;
}

/** Ayah timing [ayah, start, end] sounding at positionMs, or null. */
function findAyahAt(timings, positionMs) {
    var lo = 0, hi = timings.length - 1;
    while (lo <= hi) {
        var mid = (lo + hi) >> 1;
        if (positionMs < timings[mid][1]) hi = mid - 1;
        else if (positionMs >= timings[mid][2]) lo = mid + 1;
        else return timings[mid];
    }
    return null;
}

/** Word timing [ayah, pos, start, end, occ] sounding at positionMs, or null. */
function findWordAt(words, positionMs) {
    var lo = 0, hi = words.length - 1, cand = -1;
    while (lo <= hi) {
        var mid = (lo + hi) >> 1;
        if (words[mid][2] <= positionMs) { cand = mid; lo = mid + 1; }
        else hi = mid - 1;
    }
    if (cand < 0) return null;
    return positionMs < words[cand][3] ? words[cand] : null;
}

// --- recitations -------------------------------------------------------------------

var RECITATIONS = [
    { code: "mahmoud-husary/r1", nameAr: "محمود خليل الحصري" },
    { code: "mahmoud-husary/r2", nameAr: "محمود خليل الحصري (مجوّد)" },
    { code: "muhammad-minshawi/r1", nameAr: "محمد صديق المنشاوي" },
    { code: "abdulbasit-abdulsamad/r3", nameAr: "عبدالباسط عبدالصمد" },
    { code: "mishary-alafasy/r1", nameAr: "مشاري العفاسي" },
    { code: "maher-muaiqly/r1", nameAr: "ماهر المعيقلي" },
    { code: "ahmad-hawashi/r1", nameAr: "أحمد الحواشي" },
    { code: "ahmad-suwailem/r1", nameAr: "أحمد السويلم" },
    { code: "ahmad-nufais/r1", nameAr: "أحمد النفيس" },
    { code: "ahmad-ajmi/r1", nameAr: "أحمد بن علي العجمي" },
    { code: "ahmad-tarabulsi/r2", nameAr: "أحمد خضر الطرابلسي" },
    { code: "ahmad-shaheen/r1", nameAr: "أحمد خليل شاهين" },
    { code: "ahmad-deeban/r1", nameAr: "أحمد ديبان" },
    { code: "ahmad-saber/r1", nameAr: "أحمد صابر" },
    { code: "ahmad-amer/r1", nameAr: "أحمد عامر" },
    { code: "ahmad-masarawi/r1", nameAr: "أحمد عيسى المعصراوي" },
    { code: "ahmad-naina/r1", nameAr: "أحمد نعينع" },
    { code: "akram-alaqmi/r1", nameAr: "أكرم العلاقمي" },
    { code: "anas-emadi/r1", nameAr: "أنس العمادي" },
    { code: "ibrahim-akhdar/r1", nameAr: "إبراهيم الأخضر" },
    { code: "ibrahim-jormy/r1", nameAr: "إبراهيم الجرمي" },
    { code: "ibrahim-dosari/r2", nameAr: "إبراهيم الدوسري" },
    { code: "ibrahim-asiri/r1", nameAr: "إبراهيم العسيري" },
    { code: "idrees-abkar/r1", nameAr: "إدريس أبكر" },
    { code: "zain-ahmad/r1", nameAr: "الزين محمد أحمد" },
    { code: "badr-turki/r1", nameAr: "بدر التركي" },
    { code: "bandar-baleela/r1", nameAr: "بندر بليله" },
    { code: "peshawa-kurdi/r1", nameAr: "بيشه وا قادر الكردي" },
    { code: "tawfeeq-sayegh/r1", nameAr: "توفيق الصايغ" },
    { code: "jamal-abdullah/r1", nameAr: "جمال شاكر عبدالله" },
    { code: "jamaan-osaimi/r1", nameAr: "جمعان العصيمي" },
    { code: "junaid-abdullah/r1", nameAr: "جنيد آدم عبدالله" },
    { code: "hatem-waer/r1", nameAr: "حاتم فريد الواعر" },
    { code: "hassan-daghriri/r1", nameAr: "حسن الدغريري" },
    { code: "hassan-saleh/r1", nameAr: "حسن صالح" },
    { code: "khalid-jalil/r1", nameAr: "خالد الجليل" },
    { code: "khalid-ziyadi/r1", nameAr: "خالد الزيادي" },
    { code: "khalid-qahtani/r1", nameAr: "خالد القحطاني" },
    { code: "khalid-mohanna/r1", nameAr: "خالد المهنا" },
    { code: "khalid-abdulkafi/r1", nameAr: "خالد عبدالكافي" },
    { code: "khalid-mohammadi/r1", nameAr: "خالد كريم محمدي" },
    { code: "khalifa-tunaiji/r1", nameAr: "خليفة الطنيجي" },
    { code: "dawood-hamza/r1", nameAr: "داود حمزة" },
    { code: "rami-duais/r1", nameAr: "رامي الدعيس" },
    { code: "raad-kurdi/r1", nameAr: "رعد محمد الكردي" },
    { code: "zaki-daghistani/r1", nameAr: "زكي داغستاني" },
    { code: "saad-ghamdi/r1", nameAr: "سعد الغامدي" },
    { code: "saad-muqrin/r1", nameAr: "سعد المقرن" },
    { code: "saud-shuraim/r1", nameAr: "سعود الشريم" },
    { code: "salman-siddiq/r1", nameAr: "سلمان الصديق" },
    { code: "sahl-yassin/r1", nameAr: "سهل ياسين" },
    { code: "sayed-hashemi/r1", nameAr: "سيد أحمد هاشمي" },
    { code: "sayed-ramadan/r1", nameAr: "سيد رمضان" },
    { code: "abubakr-shatri/r1", nameAr: "شيخ أبو بكر الشاطري" },
    { code: "shirzad-taher/r1", nameAr: "شيرزاد عبدالرحمن طاهر" },
    { code: "saber-abdulhakam/r1", nameAr: "صابر عبدالحكم" },
    { code: "saleh-shamrani/r1", nameAr: "صالح الشمراني" },
    { code: "saleh-sahood/r1", nameAr: "صالح الصاهود" },
    { code: "saleh-quraishi/r1", nameAr: "صالح القريشي" },
    { code: "saleh-habdan/r1", nameAr: "صالح الهبدان" },
    { code: "salah-budair/r1", nameAr: "صلاح البدير" },
    { code: "salah-hashim/r1", nameAr: "صلاح الهاشم" },
    { code: "salah-bukhatir/r1", nameAr: "صلاح بو خاطر" },
    { code: "adel-kalbani/r1", nameAr: "عادل الكلباني" },
    { code: "adel-rayyan/r1", nameAr: "عادل ريان" },
    { code: "asim-luhaidan/r1", nameAr: "عاصم اللحیدان" },
    { code: "abdulelah-aoun/r1", nameAr: "عبدالإله بن عون" },
    { code: "abdulbari-thubaiti/r1", nameAr: "عبدالبارئ الثبيتي" },
    { code: "abdulbari-muhammad/r1", nameAr: "عبدالبارئ محمد" },
    { code: "abdulbasit-abdulsamad/r1", nameAr: "عبدالباسط عبدالصمد (مجوّد)" },
    { code: "abdulbadi-ghailan/r1", nameAr: "عبدالبديع غيلان" },
    { code: "abdulrahman-sudais/r1", nameAr: "عبدالرحمن السديس" },
    { code: "abdulrahman-shahat/r1", nameAr: "عبدالرحمن الشحات" },
    { code: "abdulrahman-oosi/r1", nameAr: "عبدالرحمن العوسي" },
    { code: "abdulrahman-majed/r1", nameAr: "عبدالرحمن الماجد" },
    { code: "abdulrahman-badr/r1", nameAr: "عبدالرحمن بن عبدالرزاق البدر" },
    { code: "abdulrasheed-sufi/r3", nameAr: "عبدالرشيد صوفي" },
    { code: "abdulaziz-ahmad/r1", nameAr: "عبدالعزيز الأحمد" },
    { code: "abdulaziz-turki/r1", nameAr: "عبدالعزيز التركي" },
    { code: "abdulaziz-zahrani/r1", nameAr: "عبدالعزيز الزهراني" },
    { code: "abdulkareem-hazmi/r1", nameAr: "عبدالكريم الحازمي" },
    { code: "abdullah-buaijan/r1", nameAr: "عبدالله البعيجان" },
    { code: "abdullah-khalaf/r1", nameAr: "عبدالله الخلف" },
    { code: "abdullah-qarafi/r1", nameAr: "عبدالله القرافي" },
    { code: "abdullah-kandari/r1", nameAr: "عبدالله الكندري" },
    { code: "abdullah-matrood/r1", nameAr: "عبدالله المطرود" },
    { code: "abdullah-mousa/r1", nameAr: "عبدالله الموسى" },
    { code: "abdullah-basfar/r1", nameAr: "عبدالله بصفر" },
    { code: "abdullah-khayyat/r1", nameAr: "عبدالله خياط" },
    { code: "abdullah-abdal/r1", nameAr: "عبدالله عبدل" },
    { code: "abdullah-juhani/r1", nameAr: "عبدالله عواد الجهني" },
    { code: "abdullah-ghailan/r1", nameAr: "عبدالله غيلان" },
    { code: "abdullah-kamel/r1", nameAr: "عبدالله كامل" },
    { code: "abdulmohsen-harthi/r1", nameAr: "عبدالمحسن الحارثي" },
    { code: "abdulmohsen-obaikan/r1", nameAr: "عبدالمحسن العبيكان" },
    { code: "abdulmohsen-qasim/r1", nameAr: "عبدالمحسن القاسم" },
    { code: "abdulhadi-kanakeri/r1", nameAr: "عبدالهادي أحمد كناكري" },
    { code: "abdulwadood-haneef/r1", nameAr: "عبدالودود حنيف" },
    { code: "abdulwali-arkani/r1", nameAr: "عبدالولي الأركاني" },
    { code: "ali-hudhaifi/r1", nameAr: "علي بن عبدالرحمن الحذيفي" },
    { code: "ali-jaber/r1", nameAr: "علي جابر" },
    { code: "ali-souissi/r1", nameAr: "علي حجاج السويسي" },
    { code: "alijon-hamdan/r1", nameAr: "عليجان قوري حمدان" },
    { code: "imad-hafez/r1", nameAr: "عماد زهير حافظ" },
    { code: "omar-duraiwiz/r1", nameAr: "عمر الدريويز" },
    { code: "issa-sanankoua/r1", nameAr: "عيسى عمر سناكو" },
    { code: "fouad-khamiri/r1", nameAr: "فؤاد الخامري" },
    { code: "fares-abbad/r1", nameAr: "فارس عباد" },
    { code: "faisal-hajri/r1", nameAr: "فيصل الهاجري" },
    { code: "majed-zamil/r1", nameAr: "ماجد الزامل" },
    { code: "malallah-jaber/r1", nameAr: "مال الله عبدالرحمن الجابر" },
    { code: "maher-muaiqly/r3", nameAr: "ماهر المعيقلي (مجوّد)" },
    { code: "maher-shakhashiro/r1", nameAr: "ماهر شخاشيرو" },
    { code: "muhammad-ayyub/r1", nameAr: "محمد أيوب" },
    { code: "muhammad-ayyub/r2", nameAr: "محمد أيوب (مميّز)" },
    { code: "muhammad-bukhait/r1", nameAr: "محمد البخيت" },
    { code: "muhammad-zubaidi/r1", nameAr: "محمد الزبيدي" },
    { code: "muhammad-tablawi/r1", nameAr: "محمد الطبلاوي" },
    { code: "muhammad-tablawi/r2", nameAr: "محمد الطبلاوي (مجوّد)" },
    { code: "muhammad-faqih/r1", nameAr: "محمد الفقيه" },
    { code: "muhammad-luhaidan/r1", nameAr: "محمد اللحيدان" },
    { code: "muhammad-muhaisni/r1", nameAr: "محمد المحيسني" },
    { code: "muhammad-burhaji/r1", nameAr: "محمد برهجي" },
    { code: "muhammad-jibreel/r1", nameAr: "محمد جبريل" },
    { code: "muhammad-khalil/r1", nameAr: "محمد خليل القارئ" },
    { code: "muhammad-shareef/r1", nameAr: "محمد رشاد الشريف" },
    { code: "muhammad-shah/r1", nameAr: "محمد صالح عالم شاه" },
    { code: "muhammad-minshawi/r2", nameAr: "محمد صديق المنشاوي (مجوّد)" },
    { code: "muhammad-abdulkareem/r1", nameAr: "محمد عبدالكريم" },
    { code: "muhammad-khan/r1", nameAr: "محمد عثمان خان" },
    { code: "mahmoud-rifai/r1", nameAr: "محمود الرفاعي" },
    { code: "mahmoud-harfoush/r1", nameAr: "محمود حرفوش" },
    { code: "mahmoud-abdulhakam/r1", nameAr: "محمود عبدالحكم" },
    { code: "mahmoud-banna/r1", nameAr: "محمود علي البنا" },
    { code: "mahmoud-banna/r2", nameAr: "محمود علي البنا (مجوّد)" },
    { code: "mukhtar-haj/r1", nameAr: "مختار الحاج" },
    { code: "mustafa-ismail/r1", nameAr: "مصطفى إسماعيل" },
    { code: "mustafa-ismail/r2", nameAr: "مصطفى إسماعيل (مجوّد)" },
    { code: "mustafa-lahouni/r1", nameAr: "مصطفى اللاهوني" },
    { code: "mustafa-azzawi/r1", nameAr: "مصطفى رعد العزاوي" },
    { code: "moeedh-harthi/r1", nameAr: "معيض الحارثي" },
    { code: "muftah-saltani/r3", nameAr: "مفتاح السلطني" },
    { code: "mansour-salimi/r1", nameAr: "منصور السالمي" },
    { code: "musa-bilal/r1", nameAr: "موسى بلال" },
    { code: "nasser-asfour/r1", nameAr: "ناصر العصفور" },
    { code: "nasser-qatami/r1", nameAr: "ناصر القطامي" },
    { code: "nasser-majed/r1", nameAr: "ناصر الماجد" },
    { code: "nabil-rifai/r1", nameAr: "نبيل الرفاعي" },
    { code: "nadhir-maliki/r1", nameAr: "نذير المالكي" },
    { code: "neama-hassan/r1", nameAr: "نعمة الحسان" },
    { code: "hashim-abudalal/r1", nameAr: "هاشم أبو دلال" },
    { code: "hani-rifai/r1", nameAr: "هاني الرفاعي" },
    { code: "haitham-dukhain/r1", nameAr: "هيثم الدخين (مميّز)" },
    { code: "wadee-yamani/r1", nameAr: "وديع اليمني" },
    { code: "yasser-dosari/r1", nameAr: "ياسر الدوسري" },
    { code: "yasser-qurashi/r1", nameAr: "ياسر القرشي" },
    { code: "yasser-salama/r1", nameAr: "ياسر سلامة" },
    { code: "yahya-hawwa/r1", nameAr: "يحيى حوا" },
    { code: "yousef-shoaey/r1", nameAr: "يوسف الشويعي" },
    { code: "yousef-aidarous/r1", nameAr: "يوسف العيدروس (مميّز)" },
    { code: "yousef-ahmad/r1", nameAr: "يوسف بن نوح أحمد" }
];

var SURAH_NAMES_AR = ["", "الفاتحة", "البقرة", "آل عمران", "النساء", "المائدة", "الأنعام", "الأعراف", "الأنفال", "التوبة", "يونس", "هود", "يوسف", "الرعد", "إبراهيم", "الحجر", "النحل", "الإسراء", "الكهف", "مريم", "طه", "الأنبياء", "الحج", "المؤمنون", "النور", "الفرقان", "الشعراء", "النمل", "القصص", "العنكبوت", "الروم", "لقمان", "السجدة", "الأحزاب", "سبأ", "فاطر", "يس", "الصافات", "ص", "الزمر", "غافر", "فصلت", "الشورى", "الزخرف", "الدخان", "الجاثية", "الأحقاف", "محمد", "الفتح", "الحجرات", "ق", "الذاريات", "الطور", "النجم", "القمر", "الرحمن", "الواقعة", "الحديد", "المجادلة", "الحشر", "الممتحنة", "الصف", "الجمعة", "المنافقون", "التغابن", "الطلاق", "التحريم", "الملك", "القلم", "الحاقة", "المعارج", "نوح", "الجن", "المزمل", "المدثر", "القيامة", "الإنسان", "المرسلات", "النبأ", "النازعات", "عبس", "التكوير", "الانفطار", "المطففين", "الانشقاق", "البروج", "الطارق", "الأعلى", "الغاشية", "الفجر", "البلد", "الشمس", "الليل", "الضحى", "الشرح", "التين", "العلق", "القدر", "البينة", "الزلزلة", "العاديات", "القارعة", "التكاثر", "العصر", "الهمزة", "الفيل", "قريش", "الماعون", "الكوثر", "الكافرون", "النصر", "المسد", "الإخلاص", "الفلق", "الناس"];

function toArabicDigits(n) {
    return String(n).replace(/\d/g, function (d) { return String.fromCharCode(0x0660 + (+d)); });
}
