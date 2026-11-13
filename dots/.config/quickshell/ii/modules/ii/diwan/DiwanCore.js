.pragma library

// Arabic diacritics (tashkeel), Quranic marks and the tatweel: stripped when measuring or searching
const MARKS = /[ؐ-ًؚ-ٰٟۖ-ۭـ]/g;
const INDIC = "٠١٢٣٤٥٦٧٨٩";

function bare(text) {
    return (text || "").replace(MARKS, "");
}

/// 12 → "١٢"
function digits(n) {
    return String(n).replace(/[0-9]/g, d => INDIC[Number(d)]);
}

/// The n longest half-lines by letter count. Width tracks length closely enough that
/// measuring a handful finds the one that decides the font size.
function widest(verses, n) {
    const seen = {};
    const halves = [];
    verses.forEach(v => v.forEach(h => {
        if (!seen[h]) {
            seen[h] = true;
            halves.push({ s: h, w: bare(h).length });
        }
    }));
    halves.sort((a, b) => b.w - a.w);
    return halves.slice(0, n).map(h => h.s);
}

/// A classical (ʿamūdī) poem is mostly two-hemistich verses; free verse and prose-like poems are not
function isMetric(verses) {
    if (verses.length === 0)
        return false;
    const paired = verses.filter(v => v.length >= 2).length;
    return paired / verses.length >= 0.6;
}

function favList(csv) {
    return (csv || "").split(",").filter(s => s.length > 0);
}

function hasFav(csv, slug) {
    return favList(csv).indexOf(slug) >= 0;
}

/// Add to the front, or remove
function toggleFav(csv, slug) {
    const list = favList(csv);
    const at = list.indexOf(slug);
    if (at >= 0)
        list.splice(at, 1);
    else
        list.unshift(slug);
    return list.slice(0, 300).join(",");
}

/// The poem as plain text for the clipboard: title, poet, then each verse with *** between halves
function plainText(poem) {
    const lines = [poem.title, poem.poet, ""];
    poem.verses.forEach(v => lines.push(v.join("   ***   ")));
    return lines.join("\n");
}

/// The verses as shown: with the diacritics, or bare
function shown(verses, tashkeel) {
    return tashkeel ? verses : verses.map(v => v.map(h => bare(h)));
}

/// "slug:index", how a saved verse is kept
function verseKey(slug, index) {
    return slug + ":" + index;
}

/// The saved verses of one poem as { index: true }
function savedIndexes(csv, slug) {
    const out = {};
    favList(csv).forEach(k => {
        const at = k.lastIndexOf(":");
        if (k.slice(0, at) === slug)
            out[Number(k.slice(at + 1))] = true;
    });
    return out;
}

/// A verse and where it comes from, for the clipboard
function quote(poem, index) {
    const v = poem.verses[index];
    return v.join("   ***   ") + "\n— " + [poem.poet, poem.title].filter(s => s).join("، ");
}

/// Newest first, no repeats, at most n
function pushRecent(csv, slug, n) {
    return [slug].concat(favList(csv).filter(s => s !== slug)).slice(0, n).join(",");
}

/// "٣ أبيات" for verse, "٣ أسطر" for the lines of free verse: the counted noun follows Arabic number rules
function verseCount(n, metric) {
    const one = metric ? "بيت واحد" : "سطر واحد";
    const two = metric ? "بيتان" : "سطران";
    const few = metric ? " أبيات" : " أسطر";
    const many = metric ? " بيتًا" : " سطرًا";
    if (n === 1)
        return one;
    if (n === 2)
        return two;
    return digits(n) + (n <= 10 ? few : many);
}

/// 46656 → "٤٦٬٦٥٦"
function count(n) {
    return digits(String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, "٬"));
}

/// A Material symbol for each theme of the catalogue
function themeIcon(slug) {
    return ({
        "alnasib": "favorite", "almadih": "workspace_premium", "alhikma": "lightbulb",
        "alhija": "bolt", "alitab": "forum", "alzuhd": "spa", "alritha": "water_drop",
        "alhamasa": "shield", "alwasf": "landscape", "almutafarriqat": "auto_awesome_mosaic"
    })[slug] || "menu_book";
}
