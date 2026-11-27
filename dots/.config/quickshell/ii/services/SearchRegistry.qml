pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    // A plain JS array, not list<var>: every push() onto a list<var> converted
    // the object and rewrote the property (~800 ms across 460 sections), and
    // every read handed back a fresh deep copy, so each search re-copied the
    // whole index and preset names pushed onto a section were lost.
    property var sections: []
    property var fileImportsBySource: ({})
    // Headings, labels and chips the redesigned pages draw outside any cloneable
    // control ({ pageId, subPage, key, text, subPageTitle }); see scripts/settings/search_landmarks.py.
    property var landmarks: []
    // Clone sources of the settings components that draw landmarks, by block id:
    // { type, source, imports, dir, rootId }.
    property var landmarkBlocks: ({})
    // Components are built live; past this many per query the rest stay links.
    readonly property int maxComponentsPerQuery: 3
    readonly property int maxLandmarksPerGroup: 6
    readonly property int maxControlsPerCard: 8
    readonly property int maxPartialResults: 12
    property bool settingsActive: false
    property bool indexing: false
    property bool indexed: false
    property var presetNames: []

    signal indexReady

    // Accepting a search scores the query in SettingsWindow and again in
    // SearchPage; the second pass reuses the first while the index is unchanged.
    property string _memoQuery: ""
    property var _memoResults: null

    // Every indexed text split once, by text: a keystroke only looks words up.
    // Scoring used to re-normalize and re-split ~5000 texts on every query,
    // which is what kept search off the keystroke (cf. the launcher's
    // AiSettingsIntegration.scoreIndex).
    property var _textCache: Object.create(null)
    // Word -> the entries holding it (sections first, then landmarks), so a
    // keystroke scores only the entries every word of the query can be found in.
    property var _postings: Object.create(null)
    // How many entries are in _postings; the rest are added in slices.
    property int _prepared: 0
    // Every word the index holds, as a set and sorted. Typo and synonym matching
    // run once per query word over this, not once per indexed text.
    property var _words: Object.create(null)
    property var _vocabulary: null
    // Query word -> { indexed word: score }, for the index in hand.
    property var _wordHits: Object.create(null)
    property var _synonymIndex: null

    // What the results page shows. Separate from currentSearch, which also
    // means "flash this heading" and is cleared by whatever it flashed.
    property string query: ""

    property string currentSearch: ""
    onCurrentSearchChanged: {
        console.log("Current found search result string:", currentSearch);
    }

    function startIndexing() {
        if (!root.settingsActive || root.indexing)
            return;

        root.dropIndex();
        root.indexing = true;
        const configRoot = FileUtils.trimFileProtocol(Directories.config) + "/quickshell/ii/";
        const pages = SettingsPageRegistry.pages.map(p => ({
            id: p.id,
            component: p.component,
            subPages: p.subPages ?? [],
            searchSources: p.searchSources ?? [],
            searchSubPages: p.searchSubPages ?? ({}),
            searchComponent: p.searchComponent !== false,
            searchable: p.searchable !== false
        }));
        indexWatchdog.restart();
        // A reader still running from before is left to finish and answers this
        // run: its output does not depend on the language.
        if (!indexReader.running) {
            indexReader.command = ["python3", Directories.scriptPath + "/settings/search_index.py", configRoot,
                JSON.stringify(pages), FileUtils.trimFileProtocol(Directories.cache) + "/settings-search.json"];
            indexReader.running = true;
        }
        listPresetsSearchProc.running = false;
        listPresetsSearchProc.running = true;
    }

    // The index scripts/settings/search_index.py printed. It holds untranslated
    // strings only; they are translated here.
    function loadIndex(text) {
        let payload = null;
        try {
            payload = JSON.parse(text);
        } catch (e) {
            root.failIndexing();
            return;
        }
        indexWatchdog.stop();
        root.fileImportsBySource = payload.imports ?? ({});
        root.landmarkBlocks = payload.blocks ?? ({});
        let loaded = [];
        for (const section of payload.sections ?? [])
            loaded.push(root.registerSection(section));
        root.sections = loaded;
        root.landmarks = (payload.landmarks ?? []).map(l => ({
            pageId: l.pageId,
            subPage: l.subPage,
            key: l.key,
            block: l.block ?? "",
            text: Translation.tr(l.key),
            subPageTitle: l.subPageTitle ? Translation.tr(l.subPageTitle) : ""
        }));
        root.addPageWords();
        root.presetNames.forEach(root.applyPresetName);
        prepareTimer.restart();
    }

    function addPageWords() {
        for (const page of SettingsPageRegistry.pages) {
            root.addWords(Translation.tr(page.name ?? ""));
            root.addWords(page.name);
            (page.aliases ?? []).forEach(root.addWords);
        }
    }

    function registerSection(data) {
        // The registry's page name and aliases describe everything on the page, so
        // they belong to each of its sections: without them a page was findable
        // only under the words printed on its own sections.
        const page = SettingsPageRegistry.pageById(data.pageId);
        let terms = [data.title];
        for (const sub of data.subsections)
            if (sub.title)
                terms.push(sub.title);
        for (const term of [page?.name ?? "", ...(page?.aliases ?? [])])
            if (term.length > 0 && terms.indexOf(term) === -1)
                terms.push(term);
        // Shown and searched in the language on screen; `key` keeps the English
        // label findable, which is what guides and forum answers quote.
        const control = item => {
            item.key = item.text;
            item.text = Translation.tr(item.key);
            item.extra = item.extra.map(e => Translation.tr(e)).join(" · ");
        };
        data.items.forEach(control);
        for (const sub of data.subsections) {
            sub.titleKey = sub.title;
            sub.title = Translation.tr(sub.titleKey);
            sub.items.forEach(control);
        }
        data.titleKey = data.title;
        data.title = Translation.tr(data.titleKey);
        data.searchStrings = terms.map(s => Translation.tr(s));
        return data;
    }

    function addWords(text) {
        if (text)
            for (const t of root.textRecord(text).tokens)
                root._words[t] = true;
    }

    // Files every word of the strings under `entry`. `joined` lists the strings
    // scoring reads as one, whose neighbouring words also count as one word.
    function post(entry, texts, joined) {
        let seen = Object.create(null);
        const file = t => {
            if (seen[t])
                return;
            seen[t] = true;
            let list = root._postings[t];
            if (list === undefined)
                root._postings[t] = list = [];
            list.push(entry);
        };
        for (const text of texts) {
            if (!text)
                continue;
            for (const t of root.textRecord(text).tokens) {
                root._words[t] = true;
                file(t);
            }
        }
        for (const parts of joined) {
            let last = "";
            for (const text of parts) {
                if (!text)
                    continue;
                const rec = root.textRecord(text);
                if (rec.first === "")
                    continue;
                if (last !== "")
                    file(last + rec.first);
                last = rec.last;
            }
        }
    }

    function prepareEntry(entry) {
        const count = root.sections.length;
        if (entry >= count) {
            const l = root.landmarks[entry - count];
            const page = Translation.tr(SettingsPageRegistry.pageById(l.pageId)?.name ?? "");
            root.post(entry, [l.text, l.key, l.subPageTitle, page], [[page, l.subPageTitle, l.text]]);
            return;
        }
        const section = root.sections[entry];
        let texts = [section.title];
        let joined = [];
        section.searchStrings.forEach(root.addWords);
        // The English strings too: in a translated interface a query may use them,
        // and a heading can be translated where its controls are not.
        texts.push(section.titleKey);
        const control = (item, context, contextKeys) => {
            texts.push(item.text, item.extra, item.key);
            joined.push([...context, item.text], [item.text, item.extra], [...contextKeys, item.key]);
        };
        for (const item of section.items)
            control(item, [section.title], [section.titleKey]);
        for (const sub of section.subsections) {
            texts.push(sub.title, sub.titleKey);
            for (const item of sub.items)
                control(item, [section.title, sub.title], [section.titleKey, sub.titleKey]);
        }
        root.post(entry, texts, joined);
    }

    // Splitting every text takes a few hundred milliseconds, so it is done in
    // slices that leave frames free. The index counts as ready once it is done.
    function prepareSlice(budgetMs) {
        const deadline = Date.now() + budgetMs;
        const total = root.sections.length + root.landmarks.length;
        while (root._prepared < total) {
            root.prepareEntry(root._prepared);
            root._prepared++;
            if (Date.now() >= deadline)
                break;
        }
        if (root._prepared < total) {
            prepareTimer.restart();
            return;
        }
        root._vocabulary = null;
        root._wordHits = Object.create(null);
        root.vocabulary();
        root.indexing = false;
        root.indexed = true;
        root.indexReady();
    }

    function failIndexing() {
        indexWatchdog.stop();
        if (!root.indexing)
            return;
        console.warn("[SearchRegistry] the settings index could not be built; only page names are searchable");
        root.addPageWords();
        root._vocabulary = null;
        root._wordHits = Object.create(null);
        root.indexing = false;
        root.indexed = true;
        root.indexReady();
    }

    function setSettingsActive(active) {
        root.settingsActive = active;
        if (!active) {
            root.clearIndex();
        }
    }

    function ensureIndexing() {
        if (!root.settingsActive || root.indexing || root.indexed)
            return;
        root.startIndexing();
    }

    // Forgets what was searched for. The index stays until Settings closes.
    function resetQuery() {
        root.query = "";
        root.currentSearch = "";
    }

    function dropIndex() {
        root.indexing = false;
        root.indexed = false;
        indexWatchdog.stop();
        prepareTimer.stop();
        root.sections = [];
        root.fileImportsBySource = ({});
        root.landmarks = [];
        root.landmarkBlocks = ({});
        root._memoResults = null;
        root._memoQuery = "";
        root._textCache = Object.create(null);
        root._postings = Object.create(null);
        root._prepared = 0;
        root._words = Object.create(null);
        root._vocabulary = null;
        root._wordHits = Object.create(null);
    }

    function clearIndex() {
        root.dropIndex();
        root.presetNames = [];
        root.resetQuery();
        listPresetsSearchProc.running = false;
    }

    Connections {
        target: Translation
        function onLanguageCodeChanged() {
            if (root.settingsActive && (root.indexed || root.indexing)) {
                root.dropIndex();
                root.startIndexing();
            }
        }
    }

    Process {
        id: indexReader
        stdout: StdioCollector {
            id: indexOutput
            onStreamFinished: {
                if (root.indexing && root._prepared === 0)
                    root.loadIndex(indexOutput.text);
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    console.warn("[SearchRegistry]", text.trim());
            }
        }
    }

    // A reader that never starts (no python3) never finishes its stream either.
    Timer {
        id: indexWatchdog
        // Generous: right after a reload the shell is busy recompiling and the
        // reader's output waits for it.
        interval: 30000
        onTriggered: {
            indexReader.running = false;
            root.failIndexing();
        }
    }

    Timer {
        id: prepareTimer
        interval: 1
        onTriggered: root.prepareSlice(8)
    }

    Process {
        id: listPresetsSearchProc
        command: ["bash", "-c", Directories.scriptPath + "/presets.sh list"]
        stdout: SplitParser {
            onRead: data => {
                if (!root.settingsActive || (!root.indexing && !root.indexed))
                    return;
                let str = data.trim();
                if (!str)
                    return;
                try {
                    let obj = JSON.parse(str);
                    if (obj && obj.name) {
                        root.addDynamicPresetName(obj.name);
                    }
                } catch (e) {
                    // Ignore parse errors
                }
            }
        }
    }

    function addDynamicPresetName(name) {
        root.presetNames.push(name);
        root.applyPresetName(name);
    }

    function applyPresetName(name) {
        root._memoResults = null;
        let added = false;
        for (const section of root.sections) {
            if (section.pageId === "presets" && section.searchStrings.indexOf(name) === -1) {
                section.searchStrings.push(name);
                added = true;
            }
        }
        if (added) {
            root.addWords(name);
            root._vocabulary = null;
            root._wordHits = Object.create(null);
        }
    }

    function getBlockSource(item) {
        return item?.source ?? "";
    }

    // Words end at spaces and punctuation, in any script: splitting on "not a
    // Latin letter" left Arabic, Cyrillic and CJK queries with no words at all.
    // _ - . / and ' join words instead (see textRecord).
    readonly property var wordBreak: /[\x00-\x26\x28-\x2c:-@\[-\^`{-\xbf\xd7\xf7՚-՟։֊־،؛؟٪-٭۔ -⯿　-〿︰-﹯＀-／：-＠［-｀｛-･]+/
    readonly property var wordJoint: /[_\-.\/']+/
    readonly property var beyondAscii: /[^\x00-\x7f]/
    // Chinese and Japanese put no spaces between words.
    readonly property var unspaced: /[぀-ヿ㐀-鿿]/

    // Lower case without accents: "Réseau" used to lose its "é" and split in two.
    // Arabic drops its vowel marks and tatweel, and letters typed either way
    // (أ إ آ for ا, ى for ي, ة for ه) read the same.
    function normalize(text) {
        let s = String(text ?? "").toLowerCase();
        if (!root.beyondAscii.test(s) || typeof s.normalize !== "function")
            return s;
        return s.normalize("NFKD").replace(/[̀-ًͯ-ٰٟـ]/g, "")
            .replace(/ٱ/g, "ا").replace(/ى/g, "ي").replace(/ة/g, "ه");
    }

    // A query keeps joined words whole: "wi-fi" must not need a word "fi".
    function queryWords(query) {
        let words = [];
        for (const chunk of root.normalize(query).split(root.wordBreak)) {
            const joined = chunk.split(root.wordJoint).join("");
            if (joined.length > 1)
                words.push(joined);
        }
        return words;
    }

    /*
     * A text's words, each joined word also whole: "Wi-Fi" is wi, fi and wifi,
     * so "wifi" finds it. Neighbouring words are also joined, so "lockscreen"
     * finds "Lock screen". `first` and `last` are its outermost words, for
     * joining across strings read as one.
     */
    function textRecord(text) {
        let rec = root._textCache[text];
        if (rec !== undefined)
            return rec;
        const norm = root.normalize(text);
        let tokens = [];
        let first = "";
        let last = "";
        const chunks = norm.split(root.wordBreak);
        for (let c = 0; c < chunks.length; c++) {
            const chunk = chunks[c];
            if (chunk === "")
                continue;
            let joined = chunk;
            if (root.wordJoint.test(chunk)) {
                const parts = chunk.split(root.wordJoint).filter(p => p.length > 0);
                if (parts.length === 0)
                    continue;
                joined = parts.join("");
                for (const p of parts)
                    if (p.length > 1)
                        tokens.push(p);
                if (parts.length > 1 && joined.length > 1)
                    tokens.push(joined);
            } else if (joined.length > 1) {
                tokens.push(joined);
            }
            if (root.beyondAscii.test(joined)) {
                // "الشاشة" is also found as "شاشة".
                if (joined.length > 3 && joined.startsWith("\u0627\u0644"))
                    tokens.push(joined.substring(2));
                // A run of unspaced script is found from any character in it.
                if (root.unspaced.test(joined))
                    for (let i = 1; i < joined.length - 1; i++)
                        tokens.push(joined.substring(i));
            }
            if (first === "")
                first = joined;
            else
                tokens.push(last + joined);
            last = joined;
        }
        rec = { norm: norm, tokens: tokens, first: first, last: last };
        root._textCache[text] = rec;
        return rec;
    }

    function vocabulary() {
        if (root._vocabulary === null)
            root._vocabulary = Object.keys(root._words).sort();
        return root._vocabulary;
    }

    // The words starting with `prefix` in the sorted vocabulary: [from, to).
    function prefixRange(words, prefix) {
        let low = 0;
        let high = words.length;
        while (low < high) {
            const mid = (low + high) >> 1;
            if (words[mid] < prefix)
                low = mid + 1;
            else
                high = mid;
        }
        let end = low;
        while (end < words.length && words[end].startsWith(prefix))
            end++;
        return [low, end];
    }

    /*
     * What people type for what the pages call something else. A word answers
     * for every other word of its group, a little below the word itself.
     */
    function synonymsOf(word) {
        if (root._synonymIndex === null) {
            const groups = [
                ["sleep", "suspend", "hibernate"],
                ["dnd", "disturb"],
                ["hotkey", "hotkeys", "shortcut", "shortcuts", "keybind", "keybinds", "keybinding", "keybindings", "binds"],
                ["audio", "sound"],
                ["wifi", "wireless", "wlan"],
                ["bt", "bluetooth"],
                ["display", "displays", "monitor", "monitors"],
                ["opacity", "transparency", "transparent", "translucent"],
                ["brightness", "backlight"],
                ["rounding", "radius", "corner", "corners", "roundness"],
                ["theme", "scheme", "pack"],
                ["font", "fonts", "typeface"],
                ["animation", "animations", "motion"],
                ["mouse", "pointer", "cursor"],
                ["touchpad", "trackpad"],
                ["mic", "microphone"],
                ["language", "locale"],
                ["update", "updates", "upgrade"],
                ["osk", "keyboard"],
                ["screenshot", "screengrab", "printscreen"]
            ];
            let index = {};
            for (const group of groups)
                for (const w of group)
                    index[w] = (index[w] ?? []).concat(group.filter(other => other !== w));
            root._synonymIndex = index;
        }
        return root._synonymIndex[word] ?? [];
    }

    // Whether `a` is at most `max` edits from `b`; a swap of two letters is one.
    function editDistanceWithin(a, b, max) {
        const n = a.length;
        const m = b.length;
        if (Math.abs(n - m) > max)
            return false;
        let before = null;
        let prev = [];
        for (let j = 0; j <= m; j++)
            prev.push(j);
        for (let i = 1; i <= n; i++) {
            let cur = [i];
            let rowMin = i;
            for (let j = 1; j <= m; j++) {
                let v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
                if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1])
                    v = Math.min(v, before[j - 2] + 1);
                cur.push(v);
                rowMin = Math.min(rowMin, v);
            }
            if (rowMin > max)
                return false;
            before = prev;
            prev = cur;
        }
        return prev[m] <= max;
    }

    /*
     * Every indexed word a query word answers to, with how well: itself 500,
     * a word it starts 200, a synonym 300 (250 for a word the synonym starts),
     * a typo 120 (100 for the start of a longer word still being typed).
     * Typos only count for a word that names nothing as typed, so "dock"
     * never also finds "deck".
     */
    function wordHits(word) {
        const cached = root._wordHits[word];
        if (cached !== undefined)
            return cached;
        const words = root.vocabulary();
        let hits = Object.create(null);
        const [from, to] = root.prefixRange(words, word);
        const direct = to > from;
        for (let i = from; i < to; i++)
            hits[words[i]] = words[i] === word ? 500 : 200;
        for (const s of root.synonymsOf(word)) {
            const range = root.prefixRange(words, s);
            for (let i = range[0]; i < range[1]; i++) {
                const t = words[i];
                // Plurals only: "pack" is not "package".
                const score = t === s ? 300 : (s.length >= 4 && t.length <= s.length + 2 ? 250 : 0);
                if (score > (hits[t] ?? 0))
                    hits[t] = score;
            }
        }
        if (!direct && word.length >= 4) {
            const budget = word.length >= 8 ? 2 : 1;
            // Only words with the same first letter are taken for typos.
            const range = root.prefixRange(words, word[0]);
            for (let i = range[0]; i < range[1]; i++) {
                const t = words[i];
                if (hits[t] !== undefined || t.length < word.length - budget)
                    continue;
                if (root.editDistanceWithin(word, t, budget))
                    hits[t] = 120;
                else if (t.length > word.length && root.editDistanceWithin(word, t.substring(0, word.length), budget))
                    hits[t] = 100;
            }
        }
        root._wordHits[word] = hits;
        return hits;
    }

    /*
     * Which entries can answer the query: result[entry] is the number of query
     * words, counted from the first, found among its words. A word is found as
     * itself, or joined to a neighbour ("time zone" in "Timezone"). A superset
     * of what scores, so scoring can skip everything else.
     */
    function candidates(queryTokens) {
        const total = root.sections.length + root.landmarks.length;
        let found = new Array(total);
        for (let i = 0; i < total; i++)
            found[i] = 0;
        for (let i = 0; i < queryTokens.length; i++) {
            const mark = word => {
                const list = root._postings[word];
                if (list === undefined)
                    return;
                for (let k = 0; k < list.length; k++)
                    if (found[list[k]] === i)
                        found[list[k]] = i + 1;
            };
            const q = queryTokens[i];
            for (const word in q.hits)
                mark(word);
            if (i + 1 < queryTokens.length)
                mark(q.word + queryTokens[i + 1].word);
            if (i > 0)
                mark(queryTokens[i - 1].word + q.word);
        }
        return found;
    }

    // The query as scoring reads it: its normalized text and, per word, the
    // indexed words that answer it.
    function prepareQuery(query) {
        return root.queryWords(query).map(w => ({ word: w, hits: root.wordHits(w) }));
    }

    // `query` is normalized, `queryTokens` from prepareQuery().
    function getMatchScore(text, query, queryTokens) {
        if (!text) return 0;
        const rec = root.textRecord(text);
        let score = 0;

        // Multi-word queries are conjunctive. Previously any one token was
        // enough, so "bar popups" returned every setting containing "bar".
        for (let i = 0; i < queryTokens.length; i++) {
            const q = queryTokens[i];
            // "time zone" in a text that writes it "Timezone".
            const next = queryTokens[i + 1];
            if (next !== undefined && rec.tokens.indexOf(q.word + next.word) !== -1) {
                score += 1000;
                i++;
                continue;
            }
            let tokenScore = 0;
            for (const t of rec.tokens) {
                const s = q.hits[t];
                if (s !== undefined && s > tokenScore)
                    tokenScore = s;
            }
            if (tokenScore === 0)
                return 0;
            score += tokenScore;
        }
        if (rec.norm.indexOf(query) !== -1)
            score += 1000;
        return score;
    }

    // A control's own words count for more than the headings it sits under,
    // and its very label most of all; what it shows besides (tooltip, options)
    // counts half. Context alone still finds it.
    function itemMatchScore(item, context, contextKey, query, queryTokens) {
        const text = item.text;
        let own = getMatchScore(text, query, queryTokens);
        if (item.key !== text)
            own = Math.max(own, getMatchScore(item.key, query, queryTokens));
        if (own > 0)
            return own + 500 + (root.textRecord(text).norm === query || root.textRecord(item.key).norm === query ? 4000 : 0);
        // Not for two-letter words: "on" is in half the tooltips.
        const described = item.extra && queryTokens.every(q => q.word.length >= 3)
            ? Math.round(getMatchScore(text + " " + item.extra, query, queryTokens) / 2) : 0;
        let inContext = getMatchScore(context + " " + text, query, queryTokens);
        if (item.key !== text)
            inContext = Math.max(inContext, getMatchScore(contextKey + " " + item.key, query, queryTokens));
        return Math.max(described, inContext);
    }

    // A section ranks by its best control. Summing them let the biggest
    // section win: twenty switches under "Dock" beat the Dock page.
    function groupScore(scores) {
        if (scores.length === 0)
            return 0;
        let best = 0;
        let total = 0;
        for (const s of scores) {
            best = Math.max(best, s);
            total += s;
        }
        return best + Math.round(Math.min((total - best) * 0.1, best * 0.5));
    }

    /*
     * A query that names a page offers the page itself, a few at most:
     * "network" opens Network even where no control on it says the word.
     */
    function matchPages(query, queryTokens) {
        let out = [];
        for (const page of SettingsPageRegistry.pages) {
            if (page.id === "search" || !SettingsPageRegistry.availableForFamily(page, PanelFamily.current))
                continue;
            const names = [Translation.tr(page.name ?? ""), page.name ?? ""];
            let nameScore = 0;
            for (const n of names)
                nameScore = Math.max(nameScore, getMatchScore(n, query, queryTokens));
            let aliasScore = 0;
            for (const n of (page.aliases ?? []))
                aliasScore = Math.max(aliasScore, getMatchScore(n, query, queryTokens));
            if (nameScore === 0 && aliasScore === 0)
                continue;
            // Its name tops the list; an alias ("Automation" for Modes) ranks
            // below a heading that shows the word.
            // "lockscreen" is the Lock Screen page's name too.
            const spaceless = text => root.normalize(text).replace(/\s+/g, "");
            const exact = names.some(n => n !== "" && spaceless(n) === spaceless(query));
            // Every word of the name, typed short or misspelled: "notif",
            // "notifcations" still mean the page.
            // A synonym is not the name: "color scheme" is not "Colors & Themes".
            const nameTokens = root.textRecord(names[0]).tokens;
            const whole = nameScore > 0 && root.queryWords(names[0]).length === queryTokens.length
                && queryTokens.every(q => nameTokens.some(t => q.hits[t] !== undefined && q.hits[t] !== 300 && q.hits[t] !== 250));
            const best = Math.max(nameScore * 2 + (whole ? 4000 : 0), Math.round(aliasScore / 2));
            out.push({
                page: true,
                pageId: page.id,
                subPage: "",
                title: Translation.tr(page.name ?? page.id),
                icon: page.icon ?? "",
                items: [],
                subsections: [],
                score: exact ? 100000 : best
            });
        }
        out.sort((a, b) => b.score - a.score);
        return out.slice(0, 3);
    }

    // What people call a setting, where the pages say it in other words.
    readonly property var phraseAliases: [
        ["keyboard shortcuts", "keybinds"],
        ["key bindings", "keybinds"],
        ["border radius", "corner radius"],
        ["auto start", "startup"],
        ["autostart", "startup"],
        ["screen timeout", "turn the screen off"],
        ["screen saver", "turn the screen off"]
    ]

    function getDynamicSearchResults(query) {
        if (!query || query.trim() === "") return [];
        query = root.normalize(query.trim());
        const memoKey = PanelFamily.current + "|" + query;
        if (root._memoResults !== null && root._memoQuery === memoKey)
            return root._memoResults;
        const queryTokens = prepareQuery(query);
        if (queryTokens.length === 0) return [];
        let results = root.matchEntries(query, queryTokens);

        for (const [phrase, meaning] of root.phraseAliases) {
            if (query.indexOf(phrase) === -1)
                continue;
            const other = query.replace(phrase, meaning);
            root.mergeResults(results, root.matchEntries(other, root.prepareQuery(other)), 0.9);
        }

        // Nothing but page names holds every word ("gemini api key"): offer what
        // holds all of them but one, below anything that matched in full.
        if (queryTokens.length > 1 && !results.some(r => !r.page)) {
            const words = root.queryWords(query);
            let partial = [];
            for (let skip = 0; skip < words.length; skip++) {
                const rest = words.filter((w, i) => i !== skip).join(" ");
                // A leftover of two letters ("on", "to") names nothing.
                if (rest.length < 3)
                    continue;
                root.mergeResults(partial, root.matchEntries(rest, root.prepareQuery(rest)), 0.25);
            }
            partial.sort((a, b) => b.score - a.score);
            root.mergeResults(results, partial.slice(0, root.maxPartialResults), 1);
        }

        // A query that names a page ("lock screen") wants that page first, not
        // the same words drawn on another one.
        for (let r of results) {
            if (r.page)
                continue;
            const page = SettingsPageRegistry.pageById(r.pageId);
            const names = [page?.name ?? "", ...(page?.aliases ?? [])];
            if (names.some(n => n !== "" && (root.normalize(Translation.tr(n)) === query || root.normalize(n) === query)))
                r.score += 5000;
        }
        results.sort((a, b) => b.score - a.score);
        results = root.withoutRepeats(results);
        root.assignLandmarkComponents(results);
        results.forEach(root.limitControls);
        root._memoQuery = memoKey;
        root._memoResults = results;
        return results;
    }

    function resultIdentity(r) {
        const kind = r.page ? "page" : r.landmarks ? "marks" : "section|" + r.sourceKey;
        return [r.pageId, r.subPage, r.title, kind].join("|");
    }

    // Adds the results of another reading of the query, scored down by `weight`.
    function mergeResults(into, more, weight) {
        let at = Object.create(null);
        for (let i = 0; i < into.length; i++)
            at[root.resultIdentity(into[i])] = i;
        for (const r of more) {
            r.score = Math.round(r.score * weight);
            const key = root.resultIdentity(r);
            const i = at[key];
            if (i === undefined) {
                at[key] = into.length;
                into.push(r);
            } else if (r.score > into[i].score) {
                into[i] = r;
            }
        }
    }

    // A section a page draws and its sub-page draws again is listed once. Two
    // sections of one page (a dictation engine each) are both kept.
    function withoutRepeats(results) {
        let seen = Object.create(null);
        return results.filter(r => {
            if (r.page || r.landmarks)
                return true;
            const direct = r.items.map(i => i.type + ":" + i.text).join(",");
            const grouped = r.subsections.map(s => s.title + "=" + s.items.map(i => i.type).join(",")).join(";");
            const key = [r.pageId, r.title, direct, grouped].join("|");
            if (seen[key] !== undefined && seen[key] !== r.subPage)
                return false;
            seen[key] = r.subPage;
            return true;
        });
    }

    // A heading that matches brings every control under it; a card shows the
    // best of them and says how many more the page has.
    function limitControls(result) {
        const scores = result.itemScores;
        result.more = 0;
        if (!scores || scores.length <= root.maxControlsPerCard)
            return;
        const kept = scores.map((s, i) => i).sort((a, b) => scores[b] - scores[a] || a - b)
            .slice(0, root.maxControlsPerCard);
        let keep = Object.create(null);
        for (const i of kept)
            keep[i] = true;
        // itemScores follows the order the controls are listed in.
        let at = 0;
        const filter = items => items.filter(() => keep[at++] === true);
        result.items = filter(result.items);
        result.subsections = result.subsections
            .map(sub => ({ title: sub.title, icon: sub.icon, items: filter(sub.items) }))
            .filter(sub => sub.items.length > 0);
        result.more = scores.length - kept.length;
    }

    // The sections, landmark groups and pages that hold every word of the query.
    function matchEntries(query, queryTokens) {
        if (queryTokens.length === 0)
            return [];
        let results = [];
        const found = root.candidates(queryTokens);
        // A page the running panel family has no surface for is not offered.
        let unavailable = Object.create(null);
        for (const page of SettingsPageRegistry.pages)
            if (!SettingsPageRegistry.availableForFamily(page, PanelFamily.current))
                unavailable[page.id] = true;

        for (let index = 0; index < root.sections.length; index++) {
            if (found[index] !== queryTokens.length)
                continue;
            const section = root.sections[index];
            if (unavailable[section.pageId])
                continue;
            let sectionScore = 0;

            let matchedItems = [];
            let matchedSubsections = [];
            let itemScores = [];
            let subTitleBest = 0;

            let sectionTitleScore = getMatchScore(section.title, query, queryTokens);
            if (section.titleKey !== section.title)
                sectionTitleScore = Math.max(sectionTitleScore, getMatchScore(section.titleKey, query, queryTokens));
            let searchStringScore = 0;
            for (let sStr of section.searchStrings) {
                let sScore = getMatchScore(sStr, query, queryTokens);
                if (sScore > 0) {
                    searchStringScore = Math.max(searchStringScore, sScore);
                }
            }

            // Page names and aliases are context for ranking, not identity for
            // every control on that page. Treating them as a direct match made
            // searches such as "policy" or "bar" dump unrelated widgets.
            let sectionTitleMatched = sectionTitleScore > 0;
            if (sectionTitleMatched) {
                sectionScore += sectionTitleScore;
            }

            // Context string: section.title + " " + item.text
            for (let item of section.items) {
                const itemScore = itemMatchScore(item, section.title, section.titleKey, query, queryTokens);
                if (itemScore > 0 || sectionTitleMatched) {
                    matchedItems.push(item);
                    itemScores.push(itemScore);
                }
            }

            for (let sub of section.subsections) {
                let subTitleScore = getMatchScore(sub.title, query, queryTokens);
                if (sub.titleKey !== sub.title)
                    subTitleScore = Math.max(subTitleScore, getMatchScore(sub.titleKey, query, queryTokens));
                let subMatchedItems = [];
                let subMatches = false;

                subTitleBest = Math.max(subTitleBest, subTitleScore);

                for (let item of sub.items) {
                    const itemScore = itemMatchScore(item, section.title + " " + sub.title,
                        section.titleKey + " " + sub.titleKey, query, queryTokens);
                    if (itemScore > 0 || subTitleScore > 0 || sectionTitleMatched) {
                        subMatchedItems.push(item);
                        itemScores.push(itemScore);
                        subMatches = true;
                    }
                }

                if (subMatches) {
                    matchedSubsections.push({
                        title: sub.title,
                        icon: sub.icon,
                        items: subMatchedItems
                    });
                }
            }

            const hasRenderableItems = matchedItems.length > 0
                || matchedSubsections.some(sub => sub.items.length > 0);
            if (hasRenderableItems) {
                sectionScore += subTitleBest + root.groupScore(itemScores);
                // Context can break ties once the control proved its own
                // relevance, but it can never create a result by itself.
                if (!sectionTitleMatched && searchStringScore > 0)
                    sectionScore += Math.round(searchStringScore / 4);
                results.push({
                    pageId: section.pageId,
                    subPage: section.subPage || "",
                    title: section.title,
                    icon: section.icon,
                    fileImports: root.fileImportsBySource[section.sourceKey] || "",
                    sourceKey: section.sourceKey,
                    items: matchedItems,
                    itemScores: itemScores,
                    subsections: matchedSubsections,
                    score: sectionScore
                });
            }
        }

        results.push(...matchLandmarks(query, queryTokens, results, found).filter(r => !unavailable[r.pageId]));
        results.push(...matchPages(query, queryTokens).filter(r => !unavailable[r.pageId]));
        return results;
    }

    function sharesToken(text, queryTokens) {
        const tokens = root.textRecord(text).tokens;
        return queryTokens.some(q => tokens.some(t => q.hits[t] !== undefined));
    }

    /*
     * Landmark hits, one group per page (or sub-page), as results that carry
     * `landmarks` instead of cloneable `items`. A heading a cloned section
     * already shows for that page is left to the clone.
     */
    function matchLandmarks(query, queryTokens, sectionResults, found) {
        let shown = {};
        // Headings and control labels a clone already shows on that page (or sub-page).
        for (let r of sectionResults) {
            let labels = [r.title, ...r.items.map(i => i.text)];
            for (let sub of r.subsections)
                labels.push(sub.title, ...sub.items.map(i => i.text));
            for (let label of labels)
                if (label)
                    shown[r.pageId + "|" + (r.subPage || "") + "|" + Translation.tr(label).toLowerCase()] = true;
        }

        let groups = {};
        let order = [];
        const first = root.sections.length;
        for (let index = 0; index < root.landmarks.length; index++) {
            if (found[first + index] !== queryTokens.length)
                continue;
            const l = root.landmarks[index];
            const lower = l.text.toLowerCase();
            // A component that draws it still shows: it is what is on the page,
            // the clone may come from a search proxy. As a row it is dropped.
            const duplicate = !!shown[l.pageId + "|" + l.subPage + "|" + lower];
            if (duplicate && !l.block)
                continue;
            let score = getMatchScore(l.text, query, queryTokens);
            if (score === 0 && l.key !== l.text)
                score = getMatchScore(l.key, query, queryTokens);
            if (score === 0) {
                // "dock color" may name the page and a heading on it, but the
                // heading must hold one of the words itself.
                if (!sharesToken(l.text, queryTokens))
                    continue;
                const page = SettingsPageRegistry.pageById(l.pageId);
                const context = Translation.tr(page?.name ?? "") + " " + (l.subPageTitle || "");
                const contextScore = getMatchScore(context + " " + l.text, query, queryTokens);
                if (contextScore === 0)
                    continue;
                score = Math.round(contextScore / 2);
            }
            // The very words of a heading: what the user is looking at.
            if (root.textRecord(l.text).norm === query || root.textRecord(l.key).norm === query)
                score += 4000;

            const groupKey = l.pageId + "|" + l.subPage;
            if (!groups[groupKey]) {
                const page = SettingsPageRegistry.pageById(l.pageId);
                groups[groupKey] = {
                    pageId: l.pageId,
                    subPage: l.subPage,
                    title: l.subPageTitle || Translation.tr(page?.name ?? l.pageId),
                    icon: page?.icon ?? "",
                    landmarks: [],
                    items: [],
                    subsections: [],
                    score: 0
                };
                order.push(groupKey);
            }
            if (!groups[groupKey].landmarks.some(other => other.text.toLowerCase() === lower))
                groups[groupKey].landmarks.push({ text: l.text, score: score, block: l.block, duplicate: duplicate });
        }

        let out = [];
        for (let key of order) {
            let g = groups[key];
            g.landmarks.sort((a, b) => b.score - a.score);
            g.landmarks = g.landmarks.slice(0, root.maxLandmarksPerGroup);
            g.score = g.landmarks[0].score;
            out.push(g);
        }
        return out;
    }

    /*
     * The best landmark hits are shown as the component that draws them (the
     * pane, the tile), cloned like a control; a landmark inside a component
     * already shown is covered by it. The rest stay link rows.
     */
    function assignLandmarkComponents(results) {
        let budget = root.maxComponentsPerQuery;
        for (let r of results) {
            if (!r.landmarks)
                continue;
            let components = [];
            let covered = [];
            let rows = [];
            for (let l of r.landmarks) {
                if (l.block && components.indexOf(l.block) !== -1) {
                    covered.push(l);
                    continue;
                }
                if (l.block && budget > 0 && root.landmarkBlocks[l.block]) {
                    components.push(l.block);
                    covered.push(l);
                    budget--;
                    continue;
                }
                if (!l.duplicate)
                    rows.push(l);
            }
            r.components = components;
            r.coveredLandmarks = covered;
            r.landmarks = rows;
        }
        // A group whose only hits were duplicates of clones has nothing left.
        for (let i = results.length - 1; i >= 0; i--) {
            const r = results[i];
            if (r.landmarks && r.landmarks.length === 0 && r.components.length === 0)
                results.splice(i, 1);
        }
    }

    function getResultsRanked(text) {
        return getSearchResult(text);
    }
    
    function getSearchResult(query) {
        if (!query || query.trim() === "") return [];
        let dyn = getDynamicSearchResults(query);
        let flat = [];
        for (let r of dyn) {
            flat.push({ pageIndex: 0, matchedString: r.title, score: r.score });
        }
        return flat;
    }
}
