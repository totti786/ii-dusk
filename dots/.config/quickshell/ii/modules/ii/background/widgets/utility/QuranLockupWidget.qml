pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets
import "../../../quran/QuranCore.js" as Core
import "../../../quran/QuranText.js" as Verses

/*
 * An ayah set straight on the wallpaper, no card, as a piece of calligraphy. Three compositions
 * share this file (the placed widget picks one through `design`):
 *   lockup  the words are cut into lines and every line is scaled to one width: a block
 *   lens    the same, but the lines swell towards the middle, a lens-shaped silhouette
 *   ring    the words follow two arcs round a ring, the surah's name in the middle
 *   hero    a large opening phrase over a smaller body
 *   hilye   large opening and closing lines around a small body, rosettes between, a fine frame
 * The verse comes from the day's pick, the bookmarked verses (one after another, changing each day,
 * six hours or hour) or the last place read. While the Quran player recites, the words already said
 * stay lit, the one being said takes the accent colour and the rest wait dimmed. A tap opens the
 * reader at that ayah.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "quran_lockup"
    property string design: "lockup"
    showCard: false
    needsColText: true

    readonly property bool ring: root.design === "ring"
    readonly property bool hier: root.design === "hero" || root.design === "hilye"
    supportedSizes: root.ring ? ["2x2", "3x3"] : root.design === "hilye" ? ["2x2", "3x2"] : root.hier ? ["2x1", "2x2", "3x2"] : ["1x1", "2x1", "2x2", "3x2"]
    defaultSize: "2x2"
    readonly property bool tile: !root.ring && root.sizeClass === "1x1"
    readonly property bool roomy: !root.ring && (root.sizeClass === "2x2" || root.sizeClass === "3x2")

    // ── what the person chose ──
    readonly property string inkMode: root.options?.ink ?? "light"
    readonly property string fontKey: root.options?.font ?? "hafs"
    readonly property string source: root.options?.source ?? "daily"
    readonly property string rotate: root.options?.rotate ?? "day"

    // The ink: a pale tint of the theme by default, since the wallpaper decides nothing here
    readonly property color ink: {
        const p = Appearance.colors.colPrimary;
        switch (root.inkMode) {
        case "dark": return ColorUtils.colorWithLightness(p, 0.14);
        case "accent": return ColorUtils.colorWithLightness(p, 0.74);
        case "auto": return root.colText;
        default: return ColorUtils.colorWithLightness(p, 0.93);
        }
    }
    readonly property bool inkIsLight: root.ink.hslLightness > 0.5
    readonly property color subInk: Qt.alpha(root.ink, 0.72)
    readonly property color liveInk: ColorUtils.colorWithLightness(Appearance.colors.colTertiary, root.inkIsLight ? 0.84 : 0.22)

    // ── fonts. The decorative ones lack some of the small recitation signs, which are left out ──
    FontLoader { id: fHafs; source: Qt.resolvedUrl("../../../../../assets/quran/quran-hafs.ttf") }
    FontLoader { id: fRuqaa; source: root.fontKey === "ruqaa" ? Qt.resolvedUrl("../../../../../assets/quran/fonts/ArefRuqaa-Regular.ttf") : "" }
    FontLoader { id: fKatibeh; source: root.fontKey === "katibeh" ? Qt.resolvedUrl("../../../../../assets/quran/fonts/Katibeh-Regular.ttf") : "" }
    FontLoader { id: fMirza; source: root.fontKey === "mirza" ? Qt.resolvedUrl("../../../../../assets/quran/fonts/Mirza-Regular.ttf") : "" }
    readonly property string family: {
        const n = root.fontKey === "ruqaa" ? fRuqaa.name : root.fontKey === "katibeh" ? fKatibeh.name : root.fontKey === "mirza" ? fMirza.name : fHafs.name;
        return n !== "" ? n : (fHafs.name !== "" ? fHafs.name : "serif");
    }
    /// the Hafs face is kept for the small reference text whatever font the verse is in
    readonly property string refFamily: fHafs.name !== "" ? fHafs.name : "serif"
    readonly property real lineHeight: root.fontKey === "ruqaa" ? 1.5 : root.fontKey === "katibeh" ? 1.4 : root.fontKey === "mirza" ? 1.5 : 1.62
    function shaped(w: string): string {
        if (root.fontKey === "ruqaa")
            return w.replace(/[ۖ-ۭ]/g, "");
        if (root.fontKey === "katibeh" || root.fontKey === "mirza")
            return w.replace(/ۥ/g, "");
        return w;
    }

    // ── data: the reader's shared libraries, loaded here only when nothing has loaded them yet ──
    property int rev: 0
    FileView { id: fManifest16; path: Core.isReady() ? "" : Quickshell.shellPath("assets/quran/manifest-16.json"); blockLoading: true }
    FileView { id: fManifest24; path: Core.isReady() ? "" : Quickshell.shellPath("assets/quran/manifest-24.json"); blockLoading: true }
    FileView { id: fUnified; path: Core.isReady() ? "" : Quickshell.shellPath("assets/quran/mushaf-unified.json"); blockLoading: true }
    FileView { id: fChapters; path: Verses.chapter(1) ? "" : Quickshell.shellPath("assets/quran/chapters.json"); blockLoading: true }
    FileView { id: fTr; path: Verses.hasTranslation() ? "" : Quickshell.shellPath("assets/quran/tr-20.json"); blockLoading: true }

    function loadData(): void {
        try {
            if (!Core.isReady())
                Core.setData(fManifest16.text(), fManifest24.text(), fUnified.text());
            if (!Verses.chapter(1))
                Verses.setChapters(fChapters.text());
            if (!Verses.hasTranslation())
                Verses.setTranslation(fTr.text(), "Saheeh International", 20);
        } catch (e) {
            console.log("[QuranLockupWidget] data load failed: " + e);
        }
        root.rev++;
    }
    Component.onCompleted: Qt.callLater(root.loadData)

    // ── which verse ──
    readonly property var q: GlobalStates.quranPlayer
    readonly property bool live: (root.q?.active ?? false) && (root.q?.currentKey ?? "") !== ""

    /// Counts the day, the six hours or the hour; the picks are a function of it
    readonly property int period: {
        const t = DateTime.clock.date.getTime() - DateTime.clock.date.getTimezoneOffset() * 60000;
        return Math.floor(t / (root.rotate === "hour" ? 3600000 : root.rotate === "6h" ? 21600000 : 86400000));
    }
    readonly property var bookmarked: String(Config.options.quran.bookmarks ?? "").split(",").filter(k => /^[0-9]+:[0-9]+$/.test(k))
    readonly property var picked: { root.rev; root.period; root.source; root.bookmarked; root.wordCap; return root.pick(); }
    readonly property var shown: {
        if (root.live) {
            const p = root.q.currentKey.split(":");
            return { s: +p[0], a: +p[1] };
        }
        return root.picked;
    }
    readonly property int surah: root.shown ? (root.shown.s || 0) : 0
    readonly property int ayah: root.shown ? (root.shown.a || 0) : 0

    function pick(): var {
        if (!Core.isReady())
            return null;
        if (root.source === "bookmarks" && root.bookmarked.length > 0) {
            const k = root.bookmarked[root.period % root.bookmarked.length].split(":");
            if (Core.ayahText(+k[0], +k[1]) !== "")
                return { s: +k[0], a: +k[1] };
        }
        if (root.source === "last") {
            const s = Math.max(1, Math.min(114, Config.options.quran.surah));
            return { s: s, a: Math.max(1, Math.min(Core.ayahCount(s), Config.options.quran.ayah)) };
        }
        // an ayah of the day: a hashed start, then the first one of a length that makes a good piece
        const total = 6236;
        const start = (root.period * 2654435761) % total;
        const most = root.tile ? 22 : Math.max(8, root.wordCap);
        for (let k = 0; k < total; k++) {
            let f = (start + k) % total;
            let s = 1;
            while (s <= 114 && f >= Core.ayahCount(s)) {
                f -= Core.ayahCount(s);
                s++;
            }
            const n = Core.ayahText(s, f + 1).split(" ").length;
            if (n >= 6 && n <= most)
                return { s: s, a: f + 1 };
        }
        return { s: 1, a: 1 };
    }

    readonly property string plain: { root.rev; return root.surah > 0 ? Core.ayahText(root.surah, root.ayah) : ""; }
    readonly property string translation: { root.rev; return root.surah > 0 && Verses.hasTranslation() ? (Verses.translationFor(root.surah, root.ayah) ?? "") : ""; }
    readonly property string surahNameAr: root.surah > 0 ? Core.SURAH_NAMES_AR[root.surah] : ""

    /// How many words a piece of this shape can carry before the text turns too small to be calligraphy
    readonly property int wordCap: root.ring ? (root.sizeClass === "3x3" ? 22 : 13)
        : root.tile ? 5 : root.sizeClass === "2x1" ? 14 : root.sizeClass === "2x2" ? 26 : 34
    readonly property var allWords: root.plain.split(" ").filter(w => w !== "")
    readonly property var words: {
        const all = root.allWords;
        if (all.length <= root.wordCap && !root.tile)
            return all.map(w => root.shaped(w));
        let n = 0, letters = 0;
        const limit = root.tile ? 13 : 1e9;
        while (n < all.length && n < root.wordCap && letters < limit) {
            letters += all[n].replace(/[ؐ-ًؚ-ٰٟۖ-ۭ]/g, "").length;
            n++;
        }
        return all.slice(0, Math.max(1, n)).map(w => root.shaped(w));
    }
    readonly property bool truncated: root.words.length < root.allWords.length

    /// Index of the word being recited among the words shown (the API's count can differ a little); -1 before the first
    readonly property int current: {
        if (!root.live)
            return -1;
        const on = root.q.apiWordPos;
        if (on < 1)
            return -1;
        const entry = root.q.entry;
        const total = entry && entry.surah === root.surah && entry.wordText[root.ayah] ? entry.wordText[root.ayah].length : root.allWords.length;
        return Math.min(root.words.length - 1, Math.round((on - 1) * root.words.length / Math.max(1, total)));
    }
    function wordColor(at: int): color {
        return root.live && at === root.current ? root.liveInk : root.ink;
    }
    function wordOpacity(at: int): real {
        if (!root.live)
            return 1;
        return root.current < 0 ? 0.32 : at < root.current ? 0.82 : at === root.current ? 1 : 0.32;
    }

    // ── measuring: each word at a fixed 100 px, to know how wide it is; everything is scaled from these ──
    property int measureRev: 0
    TextMetrics { id: spaceMeter; font.family: root.family; font.pixelSize: 100; text: "ا ا" }
    TextMetrics { id: noSpaceMeter; font.family: root.family; font.pixelSize: 100; text: "اا" }
    Repeater {
        id: meter
        model: root.words
        delegate: Text {
            required property string modelData
            visible: false
            text: modelData
            textFormat: Text.PlainText
            font.family: root.family
            font.pixelSize: 100
            onImplicitWidthChanged: Qt.callLater(() => root.measureRev++)
        }
    }
    function measured(): var {
        const w = [];
        for (let i = 0; i < root.words.length; i++) {
            const it = meter.itemAt(i);
            w.push(it ? it.implicitWidth : 0);
        }
        return w;
    }
    readonly property real wordGap: Math.max(0, spaceMeter.advanceWidth - noSpaceMeter.advanceWidth) || 25

    // ── lockup and lens ──
    readonly property real pad: root.ring || root.tile ? 22 : root.design === "hilye" ? 40 : 30
    readonly property real blockW: root.designWidth - root.pad * 2
    readonly property real refH: root.tile || root.ring ? 0 : 34
    readonly property real transH: root.roomy && root.translation !== "" ? (root.sizeClass === "3x2" ? 46 : 62) : 0
    readonly property real blockH: root.designHeight - root.pad * 2 - root.refH - root.transH
    readonly property real maxSize: root.tile ? 64 : root.sizeClass === "2x1" ? 70 : 92
    readonly property real sepH: 26
    readonly property int maxLines: root.tile ? 3 : root.sizeClass === "2x1" ? 4 : 7

    /// How wide line `l` of `L` may be, as a share of the block: all of it for a block, swelling and
    /// thinning again for a lens
    function share(l: int, L: int): real {
        if (root.design !== "lens" || L < 3)
            return 1;
        return 0.55 + 0.45 * Math.sin(Math.PI * (l + 0.5) / L);
    }

    /// Cut words a..b into L lines whose longest is as short as it can be; `span(a, b)` is the width of words a..b
    function breakRange(span, a: int, b: int, L: int): var {
        const m = b - a;
        L = Math.max(1, Math.min(L, m));
        const dp = [], cut = [];
        for (let l = 0; l <= L; l++) {
            dp.push(new Array(m + 1).fill(Infinity));
            cut.push(new Array(m + 1).fill(0));
        }
        dp[0][0] = 0;
        for (let l = 1; l <= L; l++)
            for (let i = l; i <= m; i++)
                for (let j = l - 1; j < i; j++) {
                    const v = Math.max(dp[l - 1][j], span(a + j, a + i));
                    if (v < dp[l][i]) {
                        dp[l][i] = v;
                        cut[l][i] = j;
                    }
                }
        const lines = [];
        let end = m;
        for (let l = L; l >= 1; l--) {
            const from = cut[l][end];
            lines.unshift({ from: a + from, to: a + end, w: span(a + from, a + end) });
            end = from;
        }
        return lines;
    }

    /// The hero and hilye plans: head line(s) large, the body small, for hilye a large closing line too.
    /// Every split is tried and the one whose text comes out biggest in the height wins.
    function hierPlan(n: int, span, gap: real): var {
        const hil = root.design === "hilye" && n >= 9;
        const bodyW = root.blockW * (hil ? 0.8 : 1);
        const headCap = root.blockH * (hil ? 0.26 : 0.34);
        const bodyLines = root.sizeClass === "2x1" ? 2 : 4;
        let best = null;
        for (let k = 1; k <= Math.min(4, n - 1); k++)
            for (let m = (hil ? 1 : 0); m <= (hil ? Math.min(3, n - k - 2) : 0); m++) {
                if (n - k - m < 1)
                    continue;
                const headSize = Math.min(headCap, 100 * root.blockW / span(0, k));
                const tailSize = m > 0 ? Math.min(headSize * 0.85, 100 * root.blockW / span(n - m, n)) : 0;
                for (let L2 = 1; L2 <= bodyLines; L2++) {
                    const body = root.breakRange(span, k, n - m, L2);
                    let total = headSize * root.lineHeight + (m > 0 ? tailSize * root.lineHeight + root.sepH : 0) + root.sepH;
                    let sum = 0;
                    for (const ln of body) {
                        ln.size = Math.min(headSize * 0.5, 100 * bodyW / ln.w);
                        total += ln.size * root.lineHeight;
                        sum += ln.size;
                    }
                    const fit = Math.min(1, root.blockH / total);
                    const score = fit * (headSize * 0.5 + sum / body.length);
                    if (best && score <= best.score)
                        continue;
                    const lines = [{ from: 0, to: k, w: span(0, k), size: headSize }, { sep: true, size: root.sepH }];
                    for (const ln of body)
                        lines.push(ln);
                    if (m > 0) {
                        lines.push({ sep: true, size: root.sepH });
                        lines.push({ from: n - m, to: n, w: span(n - m, n), size: tailSize });
                    }
                    best = { score: score, lines: lines, scale: fit };
                }
            }
        return best ? { lines: best.lines, scale: best.scale, gap: gap } : { lines: [], scale: 1, gap: gap };
    }

    /// Where to cut the words into lines and how large each line is. For every number of lines the words
    /// are split so that no line is far wider than its share, each line is scaled to its share of the block
    /// width, and the count that gives the biggest text still fitting the height wins.
    readonly property var plan: {
        root.measureRev;
        root.family;
        const n = root.words.length;
        const w = root.measured();
        if (root.ring || n === 0 || w.some(x => x <= 0))
            return { lines: [], scale: 1, gap: 25 };
        const gap = root.wordGap;
        const prefix = [0];
        for (let i = 0; i < n; i++)
            prefix.push(prefix[i] + w[i]);
        const span = (a, b) => prefix[b] - prefix[a] + gap * (b - a - 1);
        if (root.hier)
            return root.hierPlan(n, span, gap);

        let best = null;
        const top = Math.min(n, root.maxLines);
        for (let L = (root.design === "lens" ? Math.min(3, n) : 1); L <= top; L++) {
            // dp[l][i]: the smallest worst ratio of a line to its share when the first i words make l lines
            const dp = [], cut = [];
            for (let l = 0; l <= L; l++) {
                dp.push(new Array(n + 1).fill(Infinity));
                cut.push(new Array(n + 1).fill(0));
            }
            dp[0][0] = 0;
            for (let l = 1; l <= L; l++)
                for (let i = l; i <= n; i++)
                    for (let j = l - 1; j < i; j++) {
                        const v = Math.max(dp[l - 1][j], span(j, i) / root.share(l - 1, L));
                        if (v < dp[l][i]) {
                            dp[l][i] = v;
                            cut[l][i] = j;
                        }
                    }
            const lines = [];
            let end = n;
            for (let l = L; l >= 1; l--) {
                const from = cut[l][end];
                lines.unshift({ from: from, to: end, w: span(from, end), share: root.share(l - 1, L) });
                end = from;
            }
            let total = 0, sum = 0;
            for (const ln of lines) {
                ln.size = Math.min(root.maxSize, 100 * root.blockW * ln.share / ln.w);
                total += ln.size * root.lineHeight;
                sum += ln.size;
            }
            const fit = Math.min(1, root.blockH / total);
            const score = fit * sum / lines.length;
            if (!best || score > best.score)
                best = { score: score, lines: lines, scale: fit };
        }
        return { lines: best.lines, scale: best.scale, gap: gap };
    }

    // ── ring: the words on two arcs, the first half over the top reading right to left, the rest
    //    under the bottom, upright, carrying on right to left ──
    readonly property real ringR: Math.min(root.designWidth, root.designHeight) / 2 - root.pad
    readonly property var ringPlan: {
        root.measureRev;
        root.family;
        const n = root.words.length;
        const w = root.measured();
        if (!root.ring || n < 2 || w.some(x => x <= 0))
            return null;
        // straight words on a curve close up at their inner edge, so the ring takes a wider gap
        const gap = root.wordGap * 1.5;
        const prefix = [0];
        for (let i = 0; i < n; i++)
            prefix.push(prefix[i] + w[i]);
        const span = (a, b) => prefix[b] - prefix[a] + gap * (b - a - 1);
        // the cut that leaves the two arcs closest in length
        let k = 1, gapBest = Infinity;
        for (let c = 1; c < n; c++) {
            const d = Math.abs(span(0, c) - span(c, n));
            if (d < gapBest) {
                gapBest = d;
                k = c;
            }
        }
        const longest = Math.max(span(0, k), span(k, n));
        // text size and text radius depend on each other: settle them in a few rounds
        const frac = 0.86;
        const cap = root.sizeClass === "3x3" ? 100 : 72;
        let size = 40, rt = root.ringR - 25;
        for (let r = 0; r < 8; r++) {
            rt = root.ringR - size * 0.62;
            size = Math.min(cap, 100 * frac * Math.PI * rt / longest);
        }
        rt = root.ringR - size * 0.62;
        const out = [];
        const place = (from, to, upper) => {
            const len = span(from, to) * size / 100;
            const half = len / (2 * rt);
            let cum = 0;
            for (let i = from; i < to; i++) {
                const centre = (cum + w[i] / 2) * size / 100;
                const along = centre / rt;
                const rot = upper ? (half - along) * 180 / Math.PI : (Math.PI - half + along) * 180 / Math.PI - 180;
                out.push({ i: i, upper: upper, rot: rot, w: w[i] * size / 100 });
                cum += w[i] + gap;
            }
        };
        place(0, k, true);
        place(k, n, false);
        return { size: size, rt: rt, words: out };
    }

    // ── drawing ──
    Item {
        id: stage
        anchors.fill: parent
        opacity: (root.ring ? root.ringPlan !== null : root.plan.lines.length > 0) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 300 } }

        // With no card behind it the text has to hold up on any part of the wallpaper: a soft shadow
        // the opposite shade of the ink, wide and faint enough not to read as an outline
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: root.inkIsLight ? "#000000" : "#ffffff"
            shadowOpacity: root.inkIsLight ? 0.55 : 0.5
            shadowBlur: 0.7
            shadowVerticalOffset: 2
            shadowHorizontalOffset: 0
        }

        // the hilye's frame: two fine lines round the whole piece
        Rectangle {
            visible: root.design === "hilye"
            x: 10; y: 10
            width: root.designWidth - 20
            height: root.designHeight - 20
            radius: 6
            color: "transparent"
            border.width: 1.5
            border.color: Qt.alpha(root.ink, 0.5)
            Rectangle {
                anchors.fill: parent
                anchors.margins: 6
                radius: 3
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(root.ink, 0.28)
            }
        }

        Column {
            id: lockup
            visible: !root.ring
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.pad + (root.blockH - height) / 2
            spacing: 0

            Repeater {
                model: root.ring ? [] : root.plan.lines
                delegate: Item {
                    id: ln
                    required property var modelData
                    readonly property real size: modelData.size * root.plan.scale
                    width: root.blockW
                    height: modelData.sep ? size : size * root.lineHeight

                    // a rosette between two parts of the verse, a fine rule on each side
                    Item {
                        visible: ln.modelData.sep === true
                        anchors.fill: parent
                        Text {
                            id: rosette
                            anchors.centerIn: parent
                            text: "۞"
                            font.family: root.refFamily
                            font.pixelSize: ln.size * 1.6
                            color: root.subInk
                        }
                        Rectangle {
                            height: 1
                            width: root.blockW * 0.22
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: rosette.left
                            anchors.rightMargin: 10
                            color: Qt.alpha(root.ink, 0.4)
                        }
                        Rectangle {
                            height: 1
                            width: root.blockW * 0.22
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: rosette.right
                            anchors.leftMargin: 10
                            color: Qt.alpha(root.ink, 0.4)
                        }
                    }

                    Row {
                        visible: ln.modelData.sep !== true
                        anchors.centerIn: parent
                        layoutDirection: Qt.RightToLeft
                        spacing: root.plan.gap * ln.size / 100

                        Repeater {
                            model: ln.modelData.sep ? 0 : ln.modelData.to - ln.modelData.from
                            delegate: Text {
                                required property int index
                                readonly property int at: ln.modelData.from + index
                                text: root.words[at] ?? ""
                                textFormat: Text.PlainText
                                font.family: root.family
                                font.pixelSize: ln.size
                                renderType: Text.QtRendering
                                color: root.wordColor(at)
                                opacity: root.wordOpacity(at)
                                Behavior on opacity { NumberAnimation { duration: 220 } }
                                Behavior on color { ColorAnimation { duration: 220 } }
                            }
                        }
                    }
                }
            }
        }

        // Where it is from: the surah and the ayah, quietly, under the block
        Text {
            visible: !root.tile && !root.ring
            anchors.horizontalCenter: parent.horizontalCenter
            y: lockup.y + lockup.height + 6
            text: root.surahNameAr !== "" ? root.surahNameAr + "  ·  " + Core.toArabicDigits(root.ayah) : ""
            font.family: root.refFamily
            font.pixelSize: 21
            color: root.subInk
        }

        Text {
            visible: root.transH > 0
            x: root.pad + 14
            y: root.designHeight - root.pad - root.transH + 4
            width: root.designWidth - (root.pad + 14) * 2
            height: root.transH
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignTop
            wrapMode: Text.Wrap
            maximumLineCount: root.sizeClass === "3x2" ? 2 : 3
            elide: Text.ElideRight
            text: root.translation
            font.pixelSize: 14
            color: root.subInk
        }

        // A cut-off ayah ends in an ellipsis
        Text {
            visible: root.truncated && !root.ring
            anchors.horizontalCenter: parent.horizontalCenter
            y: lockup.y + lockup.height + (root.tile ? 2 : 28)
            text: "…"
            font.pixelSize: 22
            color: root.subInk
        }

        // ── the ring ──
        Item {
            id: ringBox
            visible: root.ring
            anchors.fill: parent

            Repeater {
                model: root.ring && root.ringPlan ? root.ringPlan.words : []
                delegate: Item {
                    id: rw
                    required property var modelData
                    readonly property real size: root.ringPlan.size
                    readonly property real rt: root.ringPlan.rt
                    readonly property real h: size * root.lineHeight
                    x: ringBox.width / 2
                    y: ringBox.height / 2
                    rotation: modelData.rot

                    Text {
                        x: -modelData.w / 2
                        y: (modelData.upper ? -rw.rt : rw.rt) - rw.h / 2
                        width: modelData.w
                        height: rw.h
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: root.words[modelData.i] ?? ""
                        textFormat: Text.PlainText
                        font.family: root.family
                        font.pixelSize: rw.size
                        renderType: Text.QtRendering
                        color: root.wordColor(modelData.i)
                        opacity: root.wordOpacity(modelData.i)
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                        Behavior on color { ColorAnimation { duration: 220 } }
                    }
                }
            }

            // The middle of the ring: the surah, and the ayah's number
            Column {
                anchors.centerIn: parent
                width: Math.max(10, (root.ringPlan ? root.ringPlan.rt - root.ringPlan.size * 0.62 : root.ringR * 0.6) * 1.5)
                spacing: 2
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.surahNameAr
                    font.family: root.refFamily
                    font.pixelSize: 46
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 16
                    color: root.ink
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.ayah > 0 ? Core.toArabicDigits(root.ayah) : ""
                    font.family: root.refFamily
                    font.pixelSize: 24
                    color: root.subInk
                }
            }
        }
    }

    onCardTapped: {
        if (root.surah > 0)
            GlobalStates.quranPendingKey = root.surah + ":" + root.ayah;
        GlobalStates.openQuranApp();
    }
    cursorShape: root.editModeActive ? Qt.ArrowCursor : Qt.PointingHandCursor
}
