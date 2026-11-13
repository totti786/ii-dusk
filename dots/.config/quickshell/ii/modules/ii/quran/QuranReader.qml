pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "QuranCore.js" as Core
import "QuranText.js" as Verses
import "QuranQcf.js" as Qcf

/**
 * The Quran reader: a two-page Madina mushaf spread, an index (surah, juz, saved ayahs), a jump field ("2:255" or a page),
 * bookmarks and recitation that follows the page. Left/Right turn pages the way the book does
 * (Left is forward), Space plays or pauses, N and P step ayahs, B bookmarks, Ctrl+C copies the ayah, G jumps, Esc closes.
 */
FocusScope {
    id: root

    signal closeRequested()
    signal windowRequested()
    signal overlayRequested()

    /// True when hosted in a floating window rather than the full-screen overlay
    property bool windowed: false

    property bool loaded: Core.isReady()
    property string loadError: ""
    /// Kept here and saved to the config after a pause, so turning pages does not write it each time
    property int page: Math.max(1, Math.min(Core.TOTAL_PAGES, Config.options.quran.page))
    Timer {
        id: savePage
        interval: 800
        onTriggered: Config.options.quran.page = root.page
    }
    /// The spread: right-hand page (odd) and left-hand page (even), as in the printed book
    readonly property int spreadRight: page % 2 === 1 ? page : page - 1
    /// A window too small for two pages to read well shows one page at a time. Two pages are
    /// kept while each would be drawn at 80% or more of the size a single page would get.
    readonly property real sheetW: root.pageModel && root.pageModel.qcf ? 470 : 418
    readonly property real sheetH: 698
    readonly property real fitTwo: Math.min((pageArea.width - 176) / 2 / root.sheetW, pageArea.height / root.sheetH)
    readonly property real fitOne: Math.min((pageArea.width - 112) / root.sheetW, pageArea.height / root.sheetH)
    readonly property bool single: pageArea.width > 0 && root.fitTwo < 0.8 * root.fitOne
    /// The first page on show: the page itself when single, the right-hand page of the spread otherwise
    readonly property int leadPage: root.single ? root.page : root.spreadRight
    /// How much of the top bar fits: 0 everything, 1 no progress line, 2 no volume or follow
    /// toggle, 3 only the essentials
    readonly property int barLevel: root.width >= 1620 ? 0 : root.width >= 1380 ? 1 : root.width >= 1090 ? 2 : 3
    readonly property var tView: tLoader.item
    FontLoader { id: hafsFont; source: Qt.resolvedUrl("../../../assets/quran/quran-hafs.ttf") }
    property var pageModel: null
    property var leftModel: null
    property string selectedKey: ""
    property bool contentsOpen: false
    property bool tafsirOpen: false
    property int tafsirSurah: 1
    property int tafsirAyah: 1
    property bool reciterOpen: false
    property bool jumpFailed: false

    readonly property var savedMap: {
        const out = {};
        for (const k of String(Config.options.quran.bookmarks).split(","))
            if (k !== "")
                out[k] = true;
        return out;
    }

    readonly property bool reading: Config.options.quran.mode === "reading"
    property bool searchOpen: false
    property bool settingsOpen: false
    property int dataRevision: 0
    property bool downloading: false
    property string translationError: ""
    property var translationList: []
    /// Where the page was last left in the verse view, kept for switching to the mushaf and back
    property int topSurah: Math.max(1, Math.min(114, Config.options.quran.surah))
    property int topAyah: Math.max(1, Config.options.quran.ayah)
    readonly property string translationHome: Quickshell.env("HOME") + "/.local/share/ii-quran"
    readonly property var translationInfo: {
        for (const t of root.translationList)
            if (t[0] === Config.options.quran.translation)
                return t;
        return null;
    }
    readonly property string translationLabel: root.translationInfo ? root.translationInfo[2] : ""
    readonly property bool translationRtl: root.translationInfo ? ["arabic", "urdu", "persian"].indexOf(root.translationInfo[3]) >= 0 : false

    /// The page data is on its way (or not wanted): until then no page is built, so none is built twice
    property bool qcfChecked: !Config.options.quran.pageFonts || Qcf.ready()
    /// Set when the data was just fetched again, so the next load replaces the one in memory
    property bool qcfReload: false
    property string qcfProgress: ""
    property bool pageFontsPresent: false
    readonly property string qcfDir: root.translationHome + "/qcf"
    /// Starts the Madani page-font download (opt-in; remembered so the fonts load next start)
    /// Switches the Madani glyph font on or off. Turning it on fetches the data when it is missing.
    function setPageFonts(on: bool): void {
        Config.options.quran.pageFonts = on;
        if (on && !root.pageFontsPresent) {
            if (!pagesFetcher.running)
                pagesFetcher.running = true;
            return;
        }
        root.pageCache = ({});
        root.pageOrder = [];
        root.rebuild();
    }
    /// Deletes the page fonts and data; the mushaf spread falls back to the Hafs font
    function removePageFonts() {
        if (pagesFetcher.running)
            return;
        Config.options.quran.pageFonts = false;
        Qcf.clear();
        root.pageCache = ({});
        root.pageOrder = [];
        root.rebuild();
        fontRemover.running = true;
    }
    Process {
        id: fontRemover
        command: ["rm", "-rf", "--", root.qcfDir + "/fonts", root.qcfDir + "/fonts.orig", root.qcfDir + "/pages", root.qcfDir + "/raw", root.qcfDir + "/pages.json"]
        onExited: {
            root.qcfReload = true;
            fQcf.reload();
        }
    }
    FileView {
        id: fQcf
        path: root.qcfDir + "/pages.json"
        onLoaded: {
            root.pageFontsPresent = true;
            // The page data outlives the reader: parsing it again and throwing the built pages
            // away made every open draw the Hafs pages first and the Madani ones after
            if (Qcf.ready() && !root.qcfReload) {
                root.qcfChecked = true;
                return;
            }
            root.qcfReload = false;
            try {
                Qcf.set(fQcf.text(), root.qcfDir + "/fonts");
                root.pageCache = ({});
                root.pageOrder = [];
            } catch (e) {
                console.warn("[Quran] page data unreadable:", e);
            }
            root.qcfChecked = true;
            root.rebuild();
        }
        // Not downloaded: the Hafs pages show. Fetch only when the user has asked for the fonts.
        onLoadFailed: {
            root.pageFontsPresent = false;
            root.qcfChecked = true;
            root.rebuild();
            if (Config.options.quran.pageFonts && !pagesFetcher.running)
                pagesFetcher.running = true;
        }
    }
    Process {
        id: pagesFetcher
        command: ["python3", Quickshell.shellPath("scripts/quran/pages.py")]
        stdout: SplitParser {
            onRead: line => root.qcfProgress = line === "ok" ? "" : line
        }
        onExited: code => {
            root.qcfProgress = "";
            // A failed or interrupted download leaves the switch off, so nothing starts again by itself
            if (code !== 0 && !root.pageFontsPresent)
                Config.options.quran.pageFonts = false;
            if (code === 0) {
                root.qcfReload = true;
                fQcf.reload();
            }
        }
    }

    FileView { id: fChapters; path: Quickshell.shellPath("assets/quran/chapters.json"); blockLoading: true }
    FileView {
        id: fSearchIndex
        path: Quickshell.shellPath("assets/quran/search-ar.json")
        onLoaded: Verses.setArabicIndex(fSearchIndex.text())
    }
    FileView { id: fTranslations; path: Quickshell.shellPath("assets/quran/translations.json"); blockLoading: true }

    // The chosen translation: the bundled one from the shell, any other from the local cache
    FileView {
        id: fTr
        path: Config.options.quran.translation === 20 ? Quickshell.shellPath("assets/quran/tr-20.json")
            : root.translationHome + "/tr-" + Config.options.quran.translation + ".json"
        onLoaded: {
            try {
                Verses.setTranslation(fTr.text(), root.translationLabel, Config.options.quran.translation);
                root.translationError = "";
                root.dataRevision++;
            } catch (e) {
                root.translationError = Translation.tr("Could not read the translation");
            }
        }
        onLoadFailed: {
            if (Config.options.quran.translation !== 20)
                root.fetchTranslation(Config.options.quran.translation);
        }
    }

    Process {
        id: fetcher
        property int wanted: 0
        onExited: (code) => {
            root.downloading = false;
            if (code === 0 && wanted === Config.options.quran.translation)
                fTr.reload();
            else if (code !== 0)
                root.translationError = Translation.tr("Download failed, check the connection");
        }
    }

    function fetchTranslation(id: int): void {
        if (fetcher.running)
            return;
        root.downloading = true;
        root.translationError = "";
        fetcher.wanted = id;
        fetcher.command = ["python3", Quickshell.shellPath("scripts/quran/translation.py"), String(id)];
        fetcher.running = true;
    }

    FileView { id: fTafsirs; path: Quickshell.shellPath("assets/quran/tafsirs.json"); blockLoading: true; watchChanges: true; onFileChanged: reload() }
    readonly property var tafsirList: {
        try {
            return JSON.parse(fTafsirs.text());
        } catch (e) {
            return [];
        }
    }

    function openTafsir(key: string): void {
        const p = String(key).split(":");
        if (p.length !== 2)
            return;
        root.tafsirSurah = +p[0];
        root.tafsirAyah = +p[1];
        root.searchOpen = false;
        root.settingsOpen = false;
        root.contentsOpen = false;
        root.reciterOpen = false;
        root.tafsirOpen = true;
    }

    function stepTafsir(delta: int): void {
        const next = Core.stepAyah(root.tafsirSurah, root.tafsirAyah, delta);
        if (!next)
            return;
        root.tafsirSurah = next.surah;
        root.tafsirAyah = next.ayah;
    }

    function pickTranslation(id: int): void {
        Config.options.quran.translation = id;
        root.settingsOpen = false;
        root.forceActiveFocus();
    }

    FileView { id: fManifest16; path: Quickshell.shellPath("assets/quran/manifest-16.json"); blockLoading: true }
    FileView { id: fManifest24; path: Quickshell.shellPath("assets/quran/manifest-24.json"); blockLoading: true }
    FileView { id: fUnified; path: Quickshell.shellPath("assets/quran/mushaf-unified.json"); blockLoading: true }

    function loadData(): void {
        // The page data is shared with every other reader, so it may already be there. The list of
        // translations is this reader's own: reading it after that early return left the settings empty.
        try {
            if (root.translationList.length === 0)
                root.translationList = JSON.parse(fTranslations.text());
        } catch (e) {
            root.translationError = Translation.tr("Could not read the list of translations");
        }
        if (Core.isReady()) {
            root.loaded = true;
            return;
        }
        try {
            Core.setData(fManifest16.text(), fManifest24.text(), fUnified.text());
            Verses.setChapters(fChapters.text());
            root.loaded = true;
        } catch (e) {
            root.loadError = String(e);
        }
    }

    /// Built pages, kept for the neighbouring spreads: a turn then only swaps models, and the
    /// next spreads are built one page at a time while the reader sits idle.
    property var pageCache: ({})
    property var pageOrder: []

    function builtPage(n: int): var {
        if (n < 1 || n > Core.TOTAL_PAGES)
            return null;
        let m = root.pageCache[n];
        if (!m) {
            m = Core.buildPage(n, 25);
            if (Config.options.quran.pageFonts && Qcf.ready())
                Qcf.attach(m, Core.SURAH_NAMES_AR);
            root.pageCache[n] = m;
            root.pageOrder.push(n);
            while (root.pageOrder.length > 14)
                delete root.pageCache[root.pageOrder.shift()];
        }
        return m;
    }

    function rebuild(): void {
        if (!root.loaded || !root.reading || !root.qcfChecked)
            return;
        root.pageModel = root.builtPage(root.leadPage);
        root.leftModel = root.single ? null : root.builtPage(root.spreadRight + 1);
        prefetch.restart();
    }

    Timer {
        id: prefetch
        interval: 150
        onTriggered: {
            // The spreads either side, nearest first, one page per tick
            if (!root.reading)
                return;
            const r = root.leadPage;
            const want = root.single ? [r + 1, r - 1, r + 2, r - 2, r + 3] : [r + 2, r + 3, r - 2, r - 1, r + 4, r + 5];
            for (const n of want) {
                if (n >= 1 && n <= Core.TOTAL_PAGES && !root.pageCache[n]) {
                    root.builtPage(n);
                    prefetch.restart();
                    return;
                }
            }
        }
    }

    onLeadPageChanged: rebuild()
    onSingleChanged: rebuild()
    onLoadedChanged: rebuild()
    onReadingChanged: rebuild()
    /// An ayah asked for from outside (IPC): go there, select it, and recite when asked
    function takePending(): void {
        const key = GlobalStates.quranPendingKey;
        if (key === "" || !root.loaded)
            return;
        const play = GlobalStates.quranPendingPlay;
        const tafsir = GlobalStates.quranPendingTafsir;
        GlobalStates.quranPendingKey = "";
        GlobalStates.quranPendingPlay = false;
        GlobalStates.quranPendingTafsir = false;
        if (root.jump(key) && play)
            root.playKey(root.selectedKey);
        if (tafsir)
            root.openTafsir(key);
    }

    // The layer surface is not focused yet when the reader is created, so ask again once it is
    Timer {
        interval: 200
        repeat: true
        running: !root.activeFocus
        property int tries: 0
        onTriggered: {
            root.forceActiveFocus();
            if (++tries >= 10)
                running = false;
        }
    }

    Connections {
        target: GlobalStates
        function onQuranPendingKeyChanged() { root.takePending(); }
    }

    Component.onCompleted: {
        root.loadData();
        root.player.localWordsFor = key => {
            // Both pages of a spread are on screen, and an ayah can run from one onto the other
            for (const m of [root.pageModel, root.leftModel]) {
                const w = m ? Core.pageWords(m)[key] : null;
                if (w)
                    return w;
            }
            return null;
        };
        const asked = GlobalStates.quranPendingKey !== "";
        root.takePending();
        // Reopened while reciting: show the page being recited
        if (!asked && root.player.currentKey !== "") {
            const p = root.player.currentKey.split(":");
            root.goToPage(Core.findPageForAyah(+p[0], +p[1]));
        }
        root.forceActiveFocus();
    }

    function goToPage(p: int): void {
        const n = Math.max(1, Math.min(Core.TOTAL_PAGES, p));
        if (n !== root.page) {
            root.page = n;
            savePage.restart();
        }
    }

    /// One step through the book: dir 1 forward (to the left), -1 back. A spread turns two pages.
    function turn(dir: int): void {
        root.goToPage(root.single ? root.page + dir : root.spreadRight + 2 * dir);
    }
    readonly property bool canForward: root.single ? root.page < Core.TOTAL_PAGES : root.spreadRight + 1 < Core.TOTAL_PAGES
    readonly property bool canBack: root.single ? root.page > 1 : root.spreadRight > 1

    function jump(text: string): bool {
        const j = Core.parseJump(text);
        if (!j) {
            root.jumpFailed = true;
            jumpReset.restart();
            return false;
        }
        if (root.reading) {
            root.goToPage(j.page);
        } else if (j.key !== "") {
            const p = j.key.split(":");
            root.showVerse(+p[0], +p[1]);
        } else {
            const a = root.firstAyahOnPage(j.page);
            root.showVerse(a.surah, a.ayah);
        }
        root.selectedKey = j.key;
        return true;
    }

    /// First real ayah drawn on a mushaf page
    function firstAyahOnPage(page: int): var {
        const b = Core.manifests[16].pages[page - 1];
        if (!b)
            return { surah: 1, ayah: 1 };
        return { surah: b[0] + 1, ayah: b[1] >= 2 ? b[1] - 1 : 1 };
    }

    /// Show a verse in whichever mode is on
    function showVerse(s: int, a: int): void {
        root.selectedKey = s + ":" + a;
        if (root.reading) {
            root.goToPage(Core.findPageForAyah(s, a));
        } else {
            root.topSurah = s;
            root.topAyah = a;
            Config.options.quran.surah = s;
            Config.options.quran.ayah = a;
            root.tView?.goTo(s, a);
        }
    }

    function showSurah(s: int): void {
        if (root.reading) {
            root.goToPage(Core.surahStartPage(s));
        } else {
            root.selectedKey = "";
            root.showVerse(s, 1);
            root.selectedKey = "";
        }
    }

    function setMode(mode: string): void {
        if (Config.options.quran.mode === mode)
            return;
        if (mode === "reading") {
            const p = Core.findPageForAyah(root.topSurah, root.topAyah);
            if (p > 0)
                root.goToPage(p);
        } else {
            const a = root.firstAyahOnPage(root.leadPage);
            root.topSurah = a.surah;
            root.topAyah = a.ayah;
            Config.options.quran.surah = a.surah;
            Config.options.quran.ayah = a.ayah;
            Qt.callLater(() => root.tView?.goTo(a.surah, a.ayah));
        }
        Config.options.quran.mode = mode;
        root.searchOpen = false;
        root.settingsOpen = false;
        root.contentsOpen = false;
        root.forceActiveFocus();
    }

    Timer { id: jumpReset; interval: 1200; onTriggered: root.jumpFailed = false }

    function toggleBookmark(key: string): void {
        if (key === "")
            return;
        const set = Object.keys(root.savedMap);
        const i = set.indexOf(key);
        if (i >= 0)
            set.splice(i, 1);
        else
            set.push(key);
        Config.options.quran.bookmarks = set.join(",");
    }

    /// Copies the selected (or recited) ayah with its number and reference
    function copyAyah(): void {
        const key = root.selectedKey !== "" ? root.selectedKey : root.player.currentKey;
        const p = key.split(":");
        if (p.length !== 2)
            return;
        const text = Core.ayahText(+p[0], +p[1]);
        if (text === "")
            return;
        Quickshell.clipboardText = text + " ﴿" + Core.toArabicDigits(+p[1]) + "﴾ [" + Core.SURAH_NAMES_AR[+p[0]] + ": " + p[1] + "]";
        root.copied = true;
        copiedReset.restart();
    }
    property bool copied: false
    Timer { id: copiedReset; interval: 1500; onTriggered: root.copied = false }

    function codeList(text: string): var {
        return String(text).split(",").filter(c => c !== "");
    }

    function toggleFavoriteReciter(code: string): void {
        const list = root.codeList(Config.options.quran.favoriteReciters);
        const i = list.indexOf(code);
        if (i >= 0)
            list.splice(i, 1);
        else
            list.push(code);
        Config.options.quran.favoriteReciters = list.join(",");
    }

    /// The last three reciters picked, newest first
    function noteRecentReciter(code: string): void {
        const list = root.codeList(Config.options.quran.recentReciters).filter(c => c !== code);
        list.unshift(code);
        Config.options.quran.recentReciters = list.slice(0, 3).join(",");
    }

    function playSelectedOrFirst(): void {
        if (player.currentKey !== "") {
            player.toggle();
            return;
        }
        let key = root.selectedKey;
        if (key === "" && root.pageModel) {
            for (const line of root.pageModel.lines)
                for (const part of line.parts)
                    if (key === "" && part.key !== "")
                        key = part.key;
        }
        root.playKey(key);
    }

    function playKey(key: string): void {
        const p = key.split(":");
        if (p.length === 2)
            player.playFrom(+p[0], +p[1]);
    }

    /// The player lives in QuranApp so the recitation carries on while the reader is hidden;
    /// the reader lends it the words on screen (for the word highlight) and follows its ayah.
    required property var player
    Connections {
        target: root.player
        function onAyahStarted(surah, ayah) {
            if (!Config.options.quran.followAudio)
                return;
            if (!root.reading) {
                root.tView?.goTo(surah, ayah);
                return;
            }
            const p = Core.findPageForAyah(surah, ayah);
            if (p > 0 && p !== root.page)
                root.goToPage(p);
        }
    }
    Component.onDestruction: root.player.localWordsFor = null

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (root.searchOpen)
                root.searchOpen = false;
            else if (root.settingsOpen)
                root.settingsOpen = false;
            else if (root.reciterOpen)
                root.reciterOpen = false;
            else if (root.tafsirOpen)
                root.tafsirOpen = false;
            else if (root.contentsOpen)
                root.contentsOpen = false;
            else if (root.selectedKey !== "")
                root.selectedKey = "";
            else
                root.closeRequested();
        } else if (!root.reading && (event.key === Qt.Key_Down || event.key === Qt.Key_Up || event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)) {
            const big = event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp;
            root.tView?.scrollBy((event.key === Qt.Key_Down || event.key === Qt.Key_PageDown ? 1 : -1) * (big ? root.tView.height * 0.85 : 90));
        } else if (!root.reading && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
            const next = root.topSurah + (event.key === Qt.Key_Left ? 1 : -1);
            if (next >= 1 && next <= 114)
                root.showSurah(next);
        } else if (!root.reading && event.key === Qt.Key_Home) {
            root.showVerse(root.topSurah, 1);
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_PageDown) {
            root.turn(1);
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_PageUp) {
            root.turn(-1);
        } else if (event.key === Qt.Key_Home) {
            root.goToPage(1);
        } else if (event.key === Qt.Key_End) {
            root.goToPage(Core.TOTAL_PAGES);
        } else if (event.key === Qt.Key_Space) {
            root.playSelectedOrFirst();
        } else if (event.key === Qt.Key_N) {
            player.step(1);
        } else if (event.key === Qt.Key_P) {
            player.step(-1);
        } else if (event.key === Qt.Key_B) {
            root.toggleBookmark(root.selectedKey !== "" ? root.selectedKey : player.currentKey);
        } else if (event.key === Qt.Key_G || event.key === Qt.Key_Slash || (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier))) {
            jumpField.forceActiveFocus();
        } else if (event.key === Qt.Key_T) {
            root.setMode(root.reading ? "translation" : "reading");
        } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
            root.copyAyah();
        } else if (event.key === Qt.Key_C) {
            root.contentsOpen = !root.contentsOpen;
        } else {
            return;
        }
        event.accepted = true;
    }

    readonly property bool selectedSaved: root.selectedKey !== "" && root.savedMap[root.selectedKey] === true
    readonly property string selectedLabel: {
        if (root.selectedKey === "")
            return "";
        const p = root.selectedKey.split(":");
        return Core.SURAH_NAMES_AR[+p[0]] + " · " + p[1];
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // ── top bar: where you are, and ways to go elsewhere ──
        Item {
            Layout.fillWidth: true
            // The bar may overflow a narrow window, but it must not widen the reader: the book
            // below is centred on the reader's width
            Layout.minimumWidth: 0
            Layout.preferredHeight: 48

            // The transport sits dead centre of the window, whatever the sides hold
            QuranPlayerBar {
                id: controls
                anchors.verticalCenter: parent.verticalCenter
                // dead centre unless the buttons on either side need the room
                x: {
                    const lo = modeBox.x + modeBox.width + 16;
                    const hi = searchBox.x - 16 - controls.width;
                    return Math.max(lo, Math.min((parent.width - controls.width) / 2, hi));
                }
                player: root.player
                level: root.barLevel
                reciterOpen: root.reciterOpen
                onPlayRequested: root.playSelectedOrFirst()
                onReciterToggled: root.reciterOpen = !root.reciterOpen
            }

        RowLayout {
            anchors.fill: parent
            spacing: 10

            QuranButton { icon: "close"; onClicked: root.closeRequested() }
            QuranButton {
                icon: root.windowed ? "fullscreen" : "open_in_new"
                onClicked: root.windowed ? root.overlayRequested() : root.windowRequested()
            }

            // quran.com's two ways to read: verse by verse with a translation, or the mushaf page
            Rectangle {
                id: modeBox
                Layout.leftMargin: 6
                implicitHeight: 40
                implicitWidth: modeRow.implicitWidth + 8
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer1
                RowLayout {
                    id: modeRow
                    anchors.centerIn: parent
                    spacing: 2
                    QuranPill {
                        implicitHeight: 32
                        icon: "translate"
                        text: root.barLevel >= 2 ? "" : Translation.tr("Translation")
                        active: !root.reading
                        onClicked: root.setMode("translation")
                    }
                    QuranPill {
                        implicitHeight: 32
                        icon: "auto_stories"
                        text: root.barLevel >= 2 ? "" : Translation.tr("Reading")
                        active: root.reading
                        onClicked: root.setMode("reading")
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Go to an ayah ("2:255") or a page, the same pill as the Mediator's search
            Rectangle {
                id: searchBox
                Layout.preferredWidth: root.barLevel >= 2 ? 130 : 210
                Layout.minimumWidth: 100
                implicitHeight: 32
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer1
                border.width: jumpField.activeFocus || root.jumpFailed ? 2 : 0
                border.color: root.jumpFailed ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 11
                    anchors.rightMargin: 11
                    spacing: 6
                    MaterialSymbol { text: "search"; iconSize: 17; color: Appearance.colors.colSubtext }
                    TextInput {
                        id: jumpField
                        Layout.fillWidth: true
                        color: Appearance.colors.colOnLayer0
                        selectByMouse: true
                        clip: true
                        font.pixelSize: Appearance.font.pixelSize.small
                        onTextChanged: if (activeFocus || text !== "") root.searchOpen = true
                        onActiveFocusChanged: {
                            if (activeFocus)
                                root.searchOpen = true;
                            else if (!searchPanel.hovered)
                                root.searchOpen = false;
                        }
                        onAccepted: {
                            if (searchPanel.pickable.length > 0) {
                                searchPanel.activate();
                            } else if (root.jump(text)) {
                                text = "";
                                root.searchOpen = false;
                            }
                        }
                        Keys.onDownPressed: searchPanel.move(1)
                        Keys.onUpPressed: searchPanel.move(-1)
                        Keys.onEscapePressed: {
                            text = "";
                            root.searchOpen = false;
                            root.forceActiveFocus();
                        }
                        StyledText {
                            visible: !jumpField.text && !jumpField.activeFocus
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Search · 2:255")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            QuranButton {
                icon: "tune"
                active: root.settingsOpen
                onClicked: {
                    root.settingsOpen = !root.settingsOpen;
                    root.searchOpen = false;
                }
            }

            QuranPill {
                icon: "menu_book"
                text: root.barLevel >= 3 ? "" : Translation.tr("Contents")
                active: root.contentsOpen
                onClicked: root.contentsOpen = !root.contentsOpen
            }
        }
        }

        // ── the book ──
        Item {
            id: pageArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledText {
                anchors.centerIn: parent
                visible: !root.pageModel
                text: root.loadError !== "" ? root.loadError : Translation.tr("Loading…")
                color: Appearance.colors.colSubtext
            }

            // The spread, right page first, both against the gutter
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 56
                anchors.rightMargin: 56
                visible: root.pageModel !== null && root.reading
                spacing: 64
                layoutDirection: Qt.RightToLeft

                Repeater {
                    // Two persistent views: a turn swaps their models instead of rebuilding them
                    model: root.reading ? 2 : 0
                    delegate: QuranPageView {
                        required property int index
                        // One page alone is centred; a pair sits against the gutter
                        sheetAlign: root.single ? Qt.AlignHCenter : index === 0 ? Qt.AlignLeft : Qt.AlignRight
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        pageModel: index === 0 ? root.pageModel : root.leftModel
                        visible: pageModel !== null && (index === 0 || !root.single)
                        selectedKey: root.selectedKey
                        playingKey: player.currentKey
                        activeWordKey: player.activeWordKey
                        savedKeys: root.savedMap
                        onAyahClicked: key => {
                            root.selectedKey = key;
                            root.forceActiveFocus();
                        }
                        onAyahPlayRequested: key => {
                            root.selectedKey = key;
                            root.playKey(key);
                        }
                    }
                }
            }

            Rectangle {
                visible: root.pageModel !== null && !root.single && root.reading
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: Qt.alpha(Appearance.colors.colOnLayer0, 0.18)
            }

            // Left is forward in a right-to-left book
            QuranButton {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: root.reading
                icon: "chevron_left"
                enabled: root.canForward
                onClicked: root.turn(1)
            }
            QuranButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.reading
                icon: "chevron_right"
                enabled: root.canBack
                onClicked: root.turn(-1)
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.reading
                acceptedButtons: Qt.NoButton
                onWheel: wheel => {
                    root.turn(wheel.angleDelta.y < 0 ? 1 : -1);
                    wheel.accepted = true;
                }
            }

            // What you can do with the selected ayah
            Rectangle {
                id: selectionBar
                visible: root.reading && root.selectedKey !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                implicitHeight: 52
                implicitWidth: selectionRow.implicitWidth + 24
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                z: 5
                RowLayout {
                    id: selectionRow
                    anchors.centerIn: parent
                    spacing: 6
                    StyledText {
                        Layout.leftMargin: 8
                        Layout.rightMargin: 6
                        text: root.selectedLabel
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }
                    QuranButton { icon: "play_arrow"; primary: true; onClicked: root.playKey(root.selectedKey) }
                    QuranButton {
                        icon: root.copied ? "check" : "content_copy"
                        active: root.copied
                        onClicked: root.copyAyah()
                    }
                    QuranButton {
                        icon: "bookmark"
                        active: root.selectedSaved
                        onClicked: root.toggleBookmark(root.selectedKey)
                    }
                    QuranButton {
                        icon: "menu_book"
                        active: root.tafsirOpen
                        onClicked: root.openTafsir(root.selectedKey)
                    }
                    QuranButton { icon: "close"; onClicked: root.selectedKey = "" }
                }
            }

            // Verse by verse, with the translation. Only built while that mode is on.
            Loader {
                id: tLoader
                anchors.fill: parent
                active: !root.reading
                sourceComponent: QuranTranslationView {
                    surah: root.topSurah
                    ready: root.loaded
                    savedKeys: root.savedMap
                    playingKey: root.player.currentKey
                    selectedKey: root.selectedKey
                    arabicSize: Config.options.quran.arabicSize
                    transSize: Config.options.quran.translationSize
                    showTranslation: Config.options.quran.showTranslation
                    translationLabel: root.translationLabel
                    translationRtl: root.translationRtl
                    dataRevision: root.dataRevision
                    Component.onCompleted: Qt.callLater(() => goTo(root.topSurah, root.topAyah))
                    onSurahRequested: s => root.showSurah(s)
                    onVerseSelected: key => {
                        root.selectedKey = root.selectedKey === key ? "" : key;
                        root.searchOpen = false;
                        root.settingsOpen = false;
                        root.forceActiveFocus();
                    }
                    onPlayRequested: key => root.playKey(key)
                    onBookmarkRequested: key => root.toggleBookmark(key)
                    onTafsirRequested: key => root.openTafsir(key)
                    onCopyRequested: key => {
                        const p = key.split(":");
                        const text = Core.ayahText(+p[0], +p[1]);
                        const tr = Verses.translationFor(+p[0], +p[1]);
                        Quickshell.clipboardText = text + " ﴿" + Core.toArabicDigits(+p[1]) + "﴾\n" + (Config.options.quran.showTranslation && tr !== "" ? tr + "\n" : "") + "[" + Core.SURAH_NAMES_AR[+p[0]] + ": " + p[1] + "]";
                        root.copied = true;
                        copiedReset.restart();
                    }
                    onTopVerseChanged: (s, a) => {
                        if (!root.reading) {
                            root.topSurah = s;
                            root.topAyah = a;
                            saveTop.restart();
                        }
                    }
                }
            }
            Timer {
                id: saveTop
                interval: 800
                onTriggered: {
                    Config.options.quran.surah = root.topSurah;
                    Config.options.quran.ayah = root.topAyah;
                }
            }

            QuranSearchPanel {
                id: searchPanel
                property bool hovered: panelHover.hovered
                visible: root.searchOpen
                anchors.top: parent.top
                anchors.topMargin: 2
                anchors.right: parent.right
                anchors.rightMargin: 4
                width: Math.min(parent.width - 16, 540)
                height: Math.min(parent.height - 8, searchPanel.wantedHeight)
                z: 12
                query: jumpField.text
                dataRevision: root.dataRevision
                fontFamily: hafsFont.name !== "" ? hafsFont.name : "serif"
                HoverHandler { id: panelHover }
                onSurahPicked: s => {
                    root.searchOpen = false;
                    jumpField.text = "";
                    root.showSurah(s);
                    root.forceActiveFocus();
                }
                onVersePicked: (s, a) => {
                    root.searchOpen = false;
                    jumpField.text = "";
                    root.showVerse(s, a);
                    root.forceActiveFocus();
                }
            }

            // A click anywhere else closes the open menu (settings, contents, reciters, search) and is not passed
            // on: it only dismisses. Below every menu, above the pages.
            MouseArea {
                anchors.fill: parent
                visible: root.settingsOpen || root.contentsOpen || root.reciterOpen || root.tafsirOpen || root.searchOpen || jumpField.activeFocus
                z: 9
                acceptedButtons: Qt.AllButtons
                onPressed: mouse => {
                    root.settingsOpen = false;
                    root.contentsOpen = false;
                    root.reciterOpen = false;
                    root.tafsirOpen = false;
                    // The search field keeps focus when the click lands on something that takes none,
                    // so it is closed and emptied here, like Escape does
                    if (root.searchOpen || jumpField.activeFocus) {
                        jumpField.text = "";
                        jumpField.focus = false;
                        root.searchOpen = false;
                    }
                    root.forceActiveFocus();
                    mouse.accepted = true;
                }
                onWheel: wheel => wheel.accepted = true
            }

            // Built the first time it is opened, then kept
            Loader {
                anchors.fill: parent
                z: 12
                active: root.settingsOpen || item !== null
                sourceComponent: Component {
 Item {
 anchors.fill: parent

                QuranSettingsPanel {
                    id: settingsPanel
                    visible: root.settingsOpen
                    onCloseRequested: {
                        root.settingsOpen = false;
                        root.forceActiveFocus();
                    }
                    anchors.top: parent.top
                    anchors.topMargin: 2
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    width: Math.min(parent.width - 16, 380)
                    height: Math.min(parent.height - 8, settingsPanel.wantedHeight)
                    z: 12
                    translations: root.translationList
                    translationId: Config.options.quran.translation
                    showTranslation: Config.options.quran.showTranslation
                    arabicSize: Config.options.quran.arabicSize
                    transSize: Config.options.quran.translationSize
                    downloading: root.downloading
                    error: root.translationError
                    pageFontsPresent: root.pageFontsPresent
                    pageFontsBusy: pagesFetcher.running
                    pageFontsProgress: root.qcfProgress
                    pageFontsOn: Config.options.quran.pageFonts
                    onPageFontsToggled: on => root.setPageFonts(on)
                    onPageFontsRemoveRequested: root.removePageFonts()
                    mushaf: root.reading
                    onMushafToggled: on => root.setMode(on ? "reading" : "translation")
                    onTranslationPicked: id => root.pickTranslation(id)
                    onShowTranslationToggled: on => Config.options.quran.showTranslation = on
                    onArabicSizeChanged2: size => Config.options.quran.arabicSize = size
                    onTransSizeChanged2: size => Config.options.quran.translationSize = size
                }
                
 }
}
            }

            // Index drawer, built the first time it is opened
            Loader {
                anchors.fill: parent
                z: 10
                active: root.contentsOpen || item !== null
                sourceComponent: Component {
 Item {
 anchors.fill: parent

                QuranContents {
                    visible: root.contentsOpen
                    anchors.top: parent.top
                    anchors.topMargin: 2
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    width: Math.min(parent.width - 16, 380)
                    height: Math.min(parent.height - 8, 460)
                    z: 10
                    ready: root.loaded
                    savedMap: root.savedMap
                    currentPage: root.spreadRight
                    onPageRequested: (page, key) => {
                        if (root.reading) {
                            root.goToPage(page);
                            root.selectedKey = key;
                        } else if (key !== "") {
                            const p = key.split(":");
                            root.showVerse(+p[0], +p[1]);
                        } else {
                            const a = root.firstAyahOnPage(page);
                            root.showVerse(a.surah, a.ayah);
                            root.selectedKey = "";
                        }
                        root.contentsOpen = false;
                        root.forceActiveFocus();
                    }
                    onSurahRequested: s => {
                        root.showSurah(s);
                        root.contentsOpen = false;
                        root.forceActiveFocus();
                    }
                }
                
 }
}
            }

            Loader {
                anchors.fill: parent
                z: 12
                active: root.tafsirOpen || item !== null
                sourceComponent: Component {
 Item {
 anchors.fill: parent

                QuranTafsirPanel {
                    id: tafsirPanel
                    // A sheet that rises from the bottom edge and keeps showing while it slides back out
                    readonly property bool shown: root.tafsirOpen
                    // 0 closed, 1 risen: it is what the slide and the visibility follow, not the geometry,
                    // which is still settling while the reader opens
                    property real rise: shown ? 1 : 0
                    Behavior on rise { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                    visible: shown || rise > 0
                    x: Math.round((parent.width - width) / 2)
                    y: parent.height - rise * (height + 4)
                    width: Math.min(parent.width - 16, 1180)
                    height: Math.min(parent.height - 8, Math.max(380, parent.height * 0.72))
                    z: 12
                    surah: root.tafsirSurah
                    ayah: root.tafsirAyah
                    surahName: Core.SURAH_NAMES_AR[root.tafsirSurah] ?? ""
                    tafsirId: Config.options.quran.tafsir
                    tafsirs: root.tafsirList
                    home: root.translationHome
                    fontSize: Config.options.quran.tafsirSize
                    canStepBack: Core.stepAyah(root.tafsirSurah, root.tafsirAyah, -1) !== null
                    canStepForward: Core.stepAyah(root.tafsirSurah, root.tafsirAyah, 1) !== null
                    onTafsirPicked: id => Config.options.quran.tafsir = id
                    onFontSizeRequested: size => Config.options.quran.tafsirSize = size
                    onStepRequested: delta => root.stepTafsir(delta)
                    onCloseRequested: {
                        root.tafsirOpen = false;
                        root.forceActiveFocus();
                    }
                }
                
 }
}
            }

            // Reciter menu, under the player cluster: filter field, then the scrolling list
            Rectangle {
                id: reciterMenu
                visible: root.reciterOpen
                anchors.top: parent.top
                anchors.topMargin: 2
                x: {
                    root.reciterOpen;
                    return Math.max(0, Math.min(parent.width - width, pageArea.mapFromItem(controls, 0, 0).x));
                }
                width: 320
                height: Math.min(parent.height - 8, 520)
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                z: 10

                onVisibleChanged: {
                    if (visible) {
                        recFilter.text = "";
                        recFilter.forceActiveFocus();
                    }
                }

                // Swallow clicks and the wheel so they never reach the pages
                MouseArea {
                    anchors.fill: parent
                    onWheel: wheel => wheel.accepted = true
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colLayer2
                        border.width: recFilter.activeFocus ? 2 : 0
                        border.color: Appearance.colors.colPrimary
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 8
                            MaterialSymbol { text: "search"; iconSize: 20; color: Appearance.colors.colSubtext }
                            TextInput {
                                id: recFilter
                                Layout.fillWidth: true
                                color: Appearance.colors.colOnLayer0
                                selectByMouse: true
                                clip: true
                                font.pixelSize: Appearance.font.pixelSize.normal
                                Keys.onEscapePressed: event => {
                                    if (text !== "") {
                                        text = "";
                                        event.accepted = true;
                                    } else {
                                        event.accepted = false;
                                    }
                                }
                                Keys.onReturnPressed: {
                                    if (reciterList.count > 0)
                                        reciterList.itemAtIndex(0)?.choose();
                                }
                                StyledText {
                                    visible: !recFilter.text
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Translation.tr("Find a reciter")
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }
                    }

                    StyledListView {
                        id: reciterList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        popin: false
                        animateAppearance: false
                        animatePopulate: false
                        model: {
                            const q = recFilter.text.trim();
                            const favs = root.codeList(Config.options.quran.favoriteReciters);
                            const recents = root.codeList(Config.options.quran.recentReciters);
                            const rows = Core.RECITATIONS.map(r => ({
                                code: r.code, nameAr: r.nameAr,
                                fav: favs.indexOf(r.code) >= 0,
                                recent: recents.indexOf(r.code) >= 0,
                                rank: favs.indexOf(r.code) >= 0 ? 0 : recents.indexOf(r.code) >= 0 ? 1 : 2
                            })).filter(r => q === "" || r.nameAr.indexOf(q) >= 0 || r.code.indexOf(q.toLowerCase()) >= 0);
                            // Starred first, then the last few used, then the rest in book order (stable)
                            return rows.map((r, i) => [r, i]).sort((a, b) => (a[0].rank - b[0].rank) || (a[1] - b[1])).map(x => x[0]);
                        }
                        delegate: Rectangle {
                            id: rec
                            required property var modelData
                            readonly property bool current: Config.options.quran.recitation === modelData.code
                            function choose(): void {
                                root.noteRecentReciter(rec.modelData.code);
                                Config.options.quran.recitation = rec.modelData.code;
                                root.reciterOpen = false;
                                root.forceActiveFocus();
                            }
                            width: reciterList.width
                            height: 44
                            radius: Appearance.rounding.normal
                            color: rec.current ? Appearance.colors.colSecondaryContainer
                                : recArea.containsMouse ? Appearance.colors.colLayer2 : "transparent"
                            RowLayout {
                                z: 2  // above the row's own click area, so the star gets its clicks
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                // Star to keep a reciter at the top; a clock marks the recently used
                                MaterialSymbol {
                                    text: !rec.modelData.fav && rec.modelData.recent ? "history" : "star"
                                    fill: rec.modelData.fav ? 1 : 0
                                    iconSize: 20
                                    opacity: rec.modelData.fav ? 1 : starArea.containsMouse || recArea.containsMouse || rec.modelData.recent ? 0.6 : 0
                                    color: rec.modelData.fav ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                    MouseArea {
                                        id: starArea
                                        anchors.fill: parent
                                        anchors.margins: -8
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleFavoriteReciter(rec.modelData.code)
                                    }
                                }
                                MaterialSymbol {
                                    text: "check"
                                    iconSize: 20
                                    opacity: rec.current ? 1 : 0
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                                Item { Layout.fillWidth: true }
                                StyledText {
                                    text: rec.modelData.nameAr
                                    color: rec.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                }
                            }
                            MouseArea {
                                id: recArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rec.choose()
                            }
                        }
                    }
                }
            }
        }
    }
}
