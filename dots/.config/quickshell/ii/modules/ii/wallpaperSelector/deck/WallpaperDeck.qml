import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The deck wallpaper picker: every wallpaper is a paint-chip card in the colour scheme it would
 * give the desktop, fanned out like a hand along the bottom of the screen, and the screen behind
 * shows the card in front at full size. Left/Right (or the wheel) move, Enter sets, Esc closes,
 * Tab switches between the folder and your favourites, F hearts the card, R jumps to a random one.
 *
 * The look is taken from https://github.com/dhrruvsharma/qs-wallpaperpicker (GPL-3.0). The
 * wallpapers, thumbnails, sorting, favourites and the places a pick can go (desktop, lock screen,
 * light mode, one screen) are the shell's own, shared with the grid picker.
 */
PanelWindow {
    id: win

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:wallpaperSelector"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: "transparent"

    // ── state ───────────────────────────────────────────────────────────────
    property string source: "folder" // "folder" | "favourites" | "wallhaven"
    property var entries: [] // { path, name, bytes } (+ remote, id, thumb, preview, colors, detail for Wallhaven)
    property int index: 0
    property real pos: 0 // `index`, eased: the cards are laid out around this
    property bool animatePos: false
    property bool started: false
    property real shown: 0 // 0..1: the deal-in

    // The deck's own chrome sits on top of a picture, so it uses the theme's solid colours: the
    // shell's layer colours turn see-through in glass mode and would show the wallpaper through.
    readonly property color panelBg: Appearance.m3colors.m3surfaceContainer
    readonly property color chipBg: Appearance.m3colors.m3surfaceContainerHigh
    readonly property color chipBgHover: Appearance.m3colors.m3surfaceContainerHighest
    readonly property color inkOn: Appearance.m3colors.m3onSurface
    readonly property color inkDim: Appearance.m3colors.m3onSurfaceVariant
    readonly property color hairline: Appearance.m3colors.m3outlineVariant

    readonly property real u: Math.max(0.7, Math.min(1.6, height / 1080))
    readonly property real dpr: win.screen?.devicePixelRatio ?? 1
    readonly property var current: win.entries.length > 0 ? win.entries[Math.max(0, Math.min(win.entries.length - 1, win.index))] : null
    readonly property bool remote: win.source === "wallhaven"
    readonly property var currentPalette: win.current && !win.current.remote ? WallpaperPalettes.palettes[win.current.path] ?? null : null
    property color accent: win.currentPalette?.primary ?? Appearance.colors.colPrimary
    readonly property color accentInk: win.currentPalette?.on_primary ?? Appearance.colors.colOnPrimary
    Behavior on accent { ColorAnimation { duration: 220 } }

    readonly property string targetScreen: GlobalStates.wallpaperSelectorTarget.startsWith("screen:")
        ? GlobalStates.wallpaperSelectorTarget.substring(7) : ""
    readonly property string targetLabel: {
        if (GlobalStates.wallpaperSelectorTarget === "lockscreen") return Translation.tr("Lockscreen");
        if (GlobalStates.wallpaperSelectorTarget === "lightmode") return Translation.tr("Light mode");
        if (win.targetScreen !== "") return win.targetScreen;
        return "";
    }

    onIndexChanged: {
        win.pos = win.index;
        // The full picture of the card just left is not wanted any more, and its download would
        // slow the thumbnail of the card now in front.
        win.previewWanted = false;
        backdrop.cancelPending();
        previewTimer.restart();
        paletteTimer.restart();
        if (win.remote && win.index >= win.entries.length - 6) win.whMore();
    }
    Behavior on pos {
        enabled: win.animatePos
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
    }

    // ── geometry of the fan ─────────────────────────────────────────────────
    DeckCard { id: probe; visible: false; path: ""; u: win.u }
    readonly property real cardW: probe.width
    readonly property real cardH: probe.height
    readonly property real arcR: win.height * 1.6
    readonly property real step: (win.cardW * 0.82) / win.arcR // radians between neighbours
    readonly property real bottomMargin: 30 * win.u
    readonly property real frontCenterY: win.height - win.cardH / 2 - win.bottomMargin
    readonly property real lift: 46 * win.u
    readonly property int reach: 9 // cards drawn each side of the front one

    // ── the wallpaper being applied, per target ────────────────────────────
    function currentTargetPath() {
        const background = Config.options?.background;
        if (!background) return "";
        if (GlobalStates.wallpaperSelectorTarget === "lockscreen")
            return FileUtils.trimFileProtocol(String(background.lockscreenWallpaperPath || ""));
        if (GlobalStates.wallpaperSelectorTarget === "lightmode")
            return FileUtils.trimFileProtocol(String(background.lightModeWallpaperPath || ""));
        if (win.targetScreen !== "")
            return WallpaperLayout.ownPathFor(win.targetScreen);
        return FileUtils.trimFileProtocol(String(background.wallpaperPath || ""));
    }

    function applyPath(filePath) {
        if (!filePath) return;
        const dark = Appearance.m3colors.darkmode;
        if (GlobalStates.wallpaperSelectorTarget === "lockscreen") {
            Wallpapers.selectLockscreen(filePath, dark);
        } else if (GlobalStates.wallpaperSelectorTarget === "lightmode") {
            Wallpapers.selectLightmode(filePath, dark);
        } else if (win.targetScreen !== "") {
            if (!WallpaperLayout.setOwnWallpaper(win.targetScreen, filePath))
                Quickshell.execDetached(["notify-send", "-a", "Shell", Translation.tr("Wallpaper"),
                    Translation.tr("A screen with its own wallpaper can only show a picture. Videos play on the shared wallpaper.")]);
        } else {
            Wallpapers.select(filePath, dark);
        }
        GlobalStates.wallpaperSelectorOpen = false;
    }

    function close() { GlobalStates.wallpaperSelectorOpen = false; }

    // ── the list ────────────────────────────────────────────────────────────
    property var favouriteSet: ({})
    function refreshFavourites() {
        const set = {};
        const favs = Persistent.states.wallpaper.favourites;
        for (let i = 0; i < favs.length; i++) set[favs[i]] = true;
        win.favouriteSet = set;
    }
    function toggleFavourite(path) {
        const favs = Array.from(Persistent.states.wallpaper.favourites);
        const at = favs.indexOf(path);
        if (at >= 0) favs.splice(at, 1); else favs.push(path);
        Persistent.states.wallpaper.favourites = favs;
    }

    function rebuild() {
        const keep = win.current ? win.current.path : "";
        const out = [];
        if (win.source === "favourites") {
            const favs = Persistent.states.wallpaper.favourites;
            for (let i = 0; i < favs.length; i++)
                out.push({ "path": favs[i], "name": favs[i].substring(favs[i].lastIndexOf("/") + 1), "bytes": 0 });
        } else if (win.source === "wallhaven") {
            for (let i = 0; i < win.whEntries.length; i++) out.push(win.whEntries[i]);
        } else if (win.subfolders && win.scanned !== null) {
            for (let i = 0; i < win.scanned.length; i++) out.push(win.scanned[i]);
        } else {
            const model = Wallpapers.sortedFolderModel;
            for (let i = 0; i < model.count; i++) {
                const item = model.get(i);
                if (item.fileIsDir) continue;
                out.push({ "path": FileUtils.trimFileProtocol(String(item.filePath)), "name": item.fileName, "bytes": item.fileSize || 0 });
            }
        }
        win.entries = out;
        let at = -1;
        const wanted = win.started ? keep : win.currentTargetPath();
        if (wanted !== "")
            for (let i = 0; i < out.length; i++) if (out[i].path === wanted) { at = i; break; }
        if (!win.started && out.length > 0) {
            win.animatePos = false;
            win.index = Math.max(0, at);
            win.pos = win.index;
            win.started = true;
            Qt.callLater(() => win.animatePos = true);
        } else if (at >= 0) {
            win.index = at;
        } else {
            win.index = Math.max(0, Math.min(out.length - 1, win.index));
        }
        restTimer.restart();
        paletteTimer.restart();
    }
    Timer { id: rebuildTimer; interval: 80; onTriggered: win.rebuild() }

    Connections {
        target: Wallpapers.sortedFolderModel
        function onCountChanged() { if (win.source === "folder") rebuildTimer.restart(); }
    }
    Connections {
        target: Wallpapers
        function onSortChanged() { if (win.source === "folder") rebuildTimer.restart(); }
    }
    Connections {
        target: Persistent.states.wallpaper
        function onFavouritesChanged() {
            win.refreshFavourites();
            if (win.source === "favourites") rebuildTimer.restart();
        }
    }
    onSourceChanged: {
        win.rebuild();
        if (win.source === "wallhaven" && win.whEntries.length === 0 && !win.whLoading) win.whSearch(win.whQuery);
    }

    // ── the folder, sub-folders included ──────────────────────────────────
    readonly property bool subfolders: Config.options.wallpaperSelector.deckSubfolders !== false
    property var scanned: null // null until the scan has answered
    property var scanRaw: []
    readonly property string scanRoot: Wallpapers.effectiveDirectory

    function sortScanned(list) {
        const field = Wallpapers.sortField;
        const sign = Wallpapers.sortReversed ? -1 : 1;
        const cmp = field === "name" ? (a, b) => a.rel.localeCompare(b.rel, undefined, { "numeric": true })
            : field === "size" ? (a, b) => a.bytes - b.bytes
            : (a, b) => b.mtime - a.mtime;
        return list.slice().sort((a, b) => sign * cmp(a, b));
    }
    function applyScan() {
        win.scanned = win.sortScanned(win.scanRaw).map(f => ({ "path": f.path, "name": f.rel.indexOf("/") >= 0 ? f.rel : f.name, "bytes": f.bytes }));
        if (win.source === "folder") win.rebuild();
    }
    function scan() {
        if (!win.subfolders || win.scanRoot === "") { win.scanned = null; return; }
        scanProc.running = false;
        scanProc.running = true;
    }
    onSubfoldersChanged: { win.scanned = null; win.scan(); if (win.source === "folder") win.rebuild(); }
    onScanRootChanged: win.scan()

    Process {
        id: scanProc
        command: ["bash", "-c", 'cd "$1" && shift && find . -type f \\( "$@" \\) -not -path "*/.*" -printf "%T@\\t%s\\t%P\\n" 2>/dev/null',
            "_", win.scanRoot, ...Wallpapers.extensions.map(ext => `-iname *.${ext}`).join(" -o ").split(" ")]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = [];
                const lines = text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    const f = lines[i].split("\t");
                    if (f.length < 3 || f[2] === "") continue;
                    const rel = f.slice(2).join("\t");
                    raw.push({ "path": win.scanRoot + "/" + rel, "rel": rel, "name": rel.substring(rel.lastIndexOf("/") + 1),
                        "mtime": parseFloat(f[0]) || 0, "bytes": parseInt(f[1]) || 0 });
                }
                win.scanRaw = raw;
                win.applyScan();
            }
        }
    }
    Connections {
        target: Wallpapers
        function onSortChanged() { if (win.scanRaw.length > 0) win.applyScan(); }
    }

    // ── Wallhaven ─────────────────────────────────────────────────────────
    property var whEntries: []
    property string whQuery: ""
    property int whPage: 0
    property bool whHasMore: false
    property bool whLoading: false
    property string whError: ""
    property bool searching: false // the search field has the keys
    property string downloading: "" // id of the Wallhaven picture being fetched

    function whSearch(query) {
        win.whQuery = query.trim();
        win.whEntries = [];
        win.whPage = 0;
        win.whHasMore = false;
        win.whError = "";
        if (win.source === "wallhaven") win.rebuild();
        win.whMore();
    }
    function whMore() {
        if (win.whLoading || (win.whPage > 0 && !win.whHasMore)) return;
        win.whLoading = true;
        const page = win.whPage + 1;
        const query = win.whQuery;
        const tags = query.length > 0 ? query.split(/\s+/) : [];
        const xhr = new XMLHttpRequest();
        xhr.open("GET", "https://wallhaven.cc/api/v1/search?" + WallpaperBrowser.wallhavenParams(tags, page, "").join("&"));
        if (WallpaperBrowser.wallhavenApiToken) xhr.setRequestHeader("X-API-Key", WallpaperBrowser.wallhavenApiToken);
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (query !== win.whQuery) return; // a newer search replaced this one
            win.whLoading = false;
            if (xhr.status !== 200) {
                win.whError = WallpaperBrowser.httpFailMessage(xhr.status);
                return;
            }
            try {
                const reply = JSON.parse(xhr.responseText);
                if (page === 1 && reply.meta?.seed) WallpaperBrowser.randomSeed = reply.meta.seed;
                const add = (reply.data ?? []).map(item => ({
                    "path": item.path, "name": "wallhaven-" + item.id, "bytes": item.file_size || 0,
                    "remote": true, "id": item.id, "thumb": item.thumbs?.large ?? item.thumbs?.original ?? "",
                    "preview": item.path, "colors": item.colors ?? [],
                    "detail": [item.resolution, item.file_size > 0 ? (item.file_size / 1048576).toFixed(1) + " MB" : "", "♥ " + (item.favorites ?? 0)]
                        .filter(t => t !== "").join("  ·  ")
                }));
                win.whPage = page;
                win.whHasMore = page < (reply.meta?.last_page ?? 1) && add.length > 0;
                win.whError = add.length === 0 && page === 1 ? Translation.tr("Nothing found") : "";
                win.whEntries = win.whEntries.concat(add);
                if (win.source === "wallhaven") win.rebuild();
            } catch (e) {
                win.whError = Translation.tr("Wallhaven sent something unreadable");
            }
        };
        xhr.send();
    }
    // ── the filters ───────────────────────────────────────────────────────
    readonly property var whSorts: ["toplist", "hot", "favorites", "date_added", "views", "random", "relevance"]
    readonly property var whRanges: ["1d", "3d", "1w", "1M", "3M", "6M", "1y"]
    readonly property var whResolutions: ["", "1920x1080", "2560x1440", "3840x2160"]
    readonly property var resolutionNames: ({ "": Translation.tr("Any"), "1920x1080": "1080p +", "2560x1440": "1440p +", "3840x2160": "4K +" })
    readonly property var whRatios: ["", "16x9", "16x10", "21x9", "32x9", "9x16"]
    readonly property var whPalette: ["cc0000", "ea4c88", "993399", "333399", "0066cc", "66cccc", "77cc33", "ffff00", "ff9900", "996633", "000000", "999999", "ffffff"]
    readonly property bool hasKey: WallpaperBrowser.wallhavenApiToken !== ""

    function bit(str, i) { return String(str).padEnd(3, "0")[i] === "1"; }
    function flipBit(str, i) {
        const a = String(str).padEnd(3, "0").substring(0, 3).split("");
        a[i] = a[i] === "1" ? "0" : "1";
        return a.join("");
    }
    function toggleCategory(i) {
        let next = win.flipBit(WallpaperBrowser.effectiveCategories, i);
        if (next === "000") return; // wallhaven wants at least one
        Config.options.wallhaven.categories = next;
        if (i === 1) Config.options.wallpapers.showAnimeResults = next[1] === "1";
        win.whSearch(win.whQuery);
    }
    function togglePurity(i) {
        if (i === 2 && !win.hasKey) {
            win.whError = Translation.tr("NSFW needs a Wallhaven API key (set it with the sidebar's api command)");
            return;
        }
        const next = win.flipBit(Config.options.wallhaven.purity, i);
        if (next === "000") return;
        Config.options.wallhaven.purity = next;
        win.whSearch(win.whQuery);
    }
    function cycleOf(list, value, by) {
        const at = list.indexOf(value);
        return list[(Math.max(0, at) + by + list.length) % list.length];
    }
    function setWh(key, value) { Config.options.wallhaven[key] = value; win.whSearch(win.whQuery); }
    readonly property var rangeNames: ({ "1d": Translation.tr("Day"), "3d": Translation.tr("3 days"), "1w": Translation.tr("Week"),
        "1M": Translation.tr("Month"), "3M": Translation.tr("3 months"), "6M": Translation.tr("6 months"), "1y": Translation.tr("Year") })
    // Wallhaven only filters by date through its toplist, so a period is "the toplist of that span";
    // "Any time" leaves the toplist for the newest uploads.
    function pickPeriod(range) {
        if (range === "") {
            if (WallpaperBrowser.currentSortType === "toplist") WallpaperBrowser.setSort("date_added");
        } else {
            Config.options.wallhaven.topRange = range;
            WallpaperBrowser.setSort("toplist");
        }
        win.whSearch(win.whQuery);
    }
    function cycleRange() { win.setWh("topRange", win.cycleOf(win.whRanges, Config.options.wallhaven.topRange, 1)); }
    function cycleRes() { win.setWh("atleast", win.cycleOf(win.whResolutions, Config.options.wallhaven.atleast, 1)); }
    function cycleRatio() { win.setWh("ratios", win.cycleOf(win.whRatios, Config.options.wallhaven.ratios, 1)); }
    function toggleOrder() { win.setWh("order", Config.options.wallhaven.order === "asc" ? "desc" : "asc"); }
    function pickColor(hex) { win.setWh("colors", Config.options.wallhaven.colors === hex ? "" : hex); }

    property bool filtersOpen: false
    // How many filters differ from the defaults.
    readonly property int filterCount: {
        const wh = Config.options.wallhaven;
        return (WallpaperBrowser.effectiveCategories !== "100" ? 1 : 0) + (wh.purity !== "100" ? 1 : 0)
            + (wh.colors ? 1 : 0) + (wh.ratios ? 1 : 0) + (wh.atleast !== "1920x1080" ? 1 : 0) + (wh.order === "asc" ? 1 : 0);
    }
    function resetFilters() {
        const wh = Config.options.wallhaven;
        wh.categories = "100";
        Config.options.wallpapers.showAnimeResults = false;
        wh.purity = "100";
        wh.atleast = "1920x1080";
        wh.ratios = "";
        wh.colors = "";
        wh.order = "desc";
        wh.topRange = "1M";
        win.whSearch(win.whQuery);
    }

    function cycleSort() {
        WallpaperBrowser.setSort(win.cycleOf(win.whSorts, WallpaperBrowser.currentSortType, 1));
        win.whSearch(win.whQuery);
    }

    // Downloads the picture, then sets it.
    Process {
        id: fetchProc
        stdout: StdioCollector {
            onStreamFinished: {
                win.downloading = "";
                const saved = text.trim();
                if (saved !== "") win.applyPath(saved);
            }
        }
    }
    function fetchAndApply(entry) {
        if (win.downloading !== "" || !entry) return;
        win.downloading = entry.id;
        const name = decodeURIComponent(entry.path.substring(entry.path.lastIndexOf("/") + 1));
        const dir = WallpaperBrowser.downloadDirFor(FileUtils.trimFileProtocol(String(Config.options.wallpapers.paths.download)),
            win.whQuery.length > 0 ? win.whQuery.split(/\s+/) : []);
        fetchProc.command = ["bash", "-c", WallpaperBrowser.downloadScript, "_", dir, entry.path, name, entry.id, "print"];
        fetchProc.running = true;
    }
    function activate(entry) {
        if (!entry) return;
        if (entry.remote) win.fetchAndApply(entry); else win.applyPath(entry.path);
    }

    // ── palettes: what is in view first, then the rest of the list ────────
    function nearPaths(count) {
        const out = [];
        for (let k = 0; k <= count; k++) {
            if (win.remote) break;
            if (win.index + k < win.entries.length) out.push(win.entries[win.index + k].path);
            if (k > 0 && win.index - k >= 0) out.push(win.entries[win.index - k].path);
        }
        return out;
    }
    Timer {
        id: paletteTimer
        interval: 120
        onTriggered: WallpaperPalettes.request(win.nearPaths(win.reach + 5))
    }
    Timer {
        id: restTimer
        interval: 500
        onTriggered: WallpaperPalettes.request(win.nearPaths(win.entries.length))
    }

    // ── the picture behind the deck ───────────────────────────────────────
    property string previewPath: ""
    // A Wallhaven picture is only fetched once the card in front has its thumbnail, so the
    // thumbnail (a few KB) never queues behind a multi-megabyte download. The backdrop keeps the
    // previous picture until the new one is ready.
    property bool previewWanted: false
    function showPreview() {
        win.previewWanted = false;
        win.previewPath = win.current ? win.current.path : "";
        if (!win.previewIsVideo) backdrop.load(win.previewPath, win.current?.remote === true);
    }
    Timer {
        id: previewTimer
        interval: 160
        onTriggered: {
            if (win.current?.remote === true && remoteThumb.status !== Image.Ready) {
                win.previewWanted = true;
                return;
            }
            win.showPreview();
        }
    }
    readonly property bool previewIsVideo: win.current && !win.current.remote ? Wallpapers.isVideoFile(win.current.path.toLowerCase()) : false

    // ── navigation ───────────────────────────────────────────────────────
    function move(by) {
        if (win.entries.length === 0) return;
        win.index = Math.max(0, Math.min(win.entries.length - 1, win.index + by));
    }
    function jump(to) {
        if (win.entries.length === 0) return;
        win.index = Math.max(0, Math.min(win.entries.length - 1, to));
    }

    Component.onCompleted: {
        WallpaperPalettes.acquire();
        win.refreshFavourites();
        win.rebuild();
        win.scan();
        Wallpapers.generateThumbnail(probe.thumbSizeName);
        dealIn.start();
        keys.forceActiveFocus();
    }
    Component.onDestruction: WallpaperPalettes.release()

    NumberAnimation {
        id: dealIn
        target: win
        property: "shown"
        from: 0
        to: 1
        duration: 420
        easing.type: Easing.OutCubic
    }

    // ── the scene ────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        opacity: win.shown

        // Under a Wallhaven picture something opaque has to be: with the scrim alone, a moment
        // with no picture shows the desktop through the window.
        Rectangle {
            anchors.fill: parent
            visible: win.current?.remote === true
            color: "black"
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.55)
        }

        // The card in front, full size. Its card thumbnail shows at once (the size the deck
        // generated, so it exists), then the real file fades in over it. The real file loads into
        // the layer that is not showing and swaps in only when it is ready, so browsing never
        // goes blank while the next picture decodes.
        ThumbnailImage {
            anchors.fill: parent
            visible: win.current !== null && !win.current.remote
            sourcePath: win.current && !win.current.remote ? win.current.path : ""
            generateThumbnail: !win.remote
            thumbnailSizeName: probe.thumbSizeName
            thumbnailService: Wallpapers
            fillMode: Image.PreserveAspectCrop
        }
        Image {
            id: remoteThumb
            anchors.fill: parent
            visible: win.current?.remote === true
            source: win.current?.remote === true ? win.current.thumb : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            onStatusChanged: if (status === Image.Ready && win.previewWanted) win.showPreview()
            // A 432 px thumbnail stretched over the screen looks like a bad picture; blurred it
            // reads as a wash of the picture's colours until the real one arrives.
            layer.enabled: win.current?.remote === true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
                blurMax: 48
                autoPaddingEnabled: false
            }
        }

        Item {
            id: backdrop
            anchors.fill: parent
            property var sources: ["", ""]
            property int onTop: 0
            property int pending: -1
            // The card in front is a Wallhaven picture whose full file is not on top yet and whose
            // thumbnail is ready: the old picture steps aside for the blurred thumbnail underneath.
            // Waiting for the thumbnail first means the screen never goes blank in between.
            readonly property bool awaitingFull: win.current?.remote === true
                && backdrop.sources[backdrop.onTop] !== win.current.path
                && remoteThumb.status === Image.Ready

            function fileUrl(path) {
                return "file://" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F");
            }
            // Drops a download that is still running for a card that is no longer in front
            function cancelPending() {
                if (backdrop.pending < 0) return;
                const next = backdrop.sources.slice();
                next[backdrop.pending] = "";
                backdrop.sources = next;
                backdrop.pending = -1;
            }
            function load(path, remote) {
                if (path === "") return;
                const url = remote ? path : backdrop.fileUrl(path);
                if (backdrop.sources[backdrop.onTop] === url) { backdrop.pending = -1; return; }
                const idle = 1 - backdrop.onTop;
                const next = backdrop.sources.slice();
                next[idle] = url;
                backdrop.sources = next;
                backdrop.pending = idle;
                Qt.callLater(backdrop.check);
            }
            function check() {
                if (backdrop.pending < 0) return;
                const layer = layers.itemAt(backdrop.pending);
                // Only the idle layer is ever pending, and a newer load into it sets it Loading again,
                // so Ready here is always the latest picture (no URL comparison: Qt rewrites URLs).
                if (layer && layer.status === Image.Ready) {
                    backdrop.onTop = backdrop.pending;
                    backdrop.pending = -1;
                }
            }

            Repeater {
                id: layers
                model: 2
                delegate: Image {
                    required property int index
                    anchors.fill: parent
                    source: backdrop.sources[index]
                    sourceSize: Qt.size(Math.round(win.width * win.dpr), Math.round(win.height * win.dpr))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    z: backdrop.onTop === index ? 1 : 0
                    opacity: backdrop.onTop === index && !backdrop.awaitingFull ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 240 } }
                    onStatusChanged: {
                        if (status === Image.Error)
                            console.log("[Deck] backdrop failed to load:", source);
                        backdrop.check();
                    }
                }
            }
        }

        // Darkens toward the bottom so the cards read against any picture.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.25) }
                GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.05) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.7) }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: win.close()
            onWheel: wheel => {
                const delta = Math.abs(wheel.angleDelta.y) > Math.abs(wheel.angleDelta.x) ? wheel.angleDelta.y : wheel.angleDelta.x;
                win.move(delta > 0 ? -1 : 1);
            }
        }

        // ── the fan ───────────────────────────────────────────────────────
        Repeater {
            model: win.reach * 2 + 1
            delegate: Item {
                id: slot
                required property int index
                readonly property int cardIndex: Math.round(win.pos) + slot.index - win.reach
                readonly property bool inRange: cardIndex >= 0 && cardIndex < win.entries.length
                readonly property var entry: inRange ? win.entries[cardIndex] : null
                readonly property real d: cardIndex - win.pos
                readonly property real ad: Math.abs(d)
                readonly property real front: Math.max(0, 1 - ad)
                readonly property real theta: d * win.step

                visible: inRange
                width: win.cardW
                height: win.cardH
                x: win.width / 2 + win.arcR * Math.sin(theta) - width / 2
                y: win.frontCenterY + win.arcR * (1 - Math.cos(theta)) - height / 2 - front * win.lift
                    + (1 - win.shown) * win.cardH * 1.4
                rotation: theta * 180 / Math.PI
                scale: 1 + 0.2 * front
                z: 100 - Math.round(ad * 10)

                DeckCard {
                    id: slotCard
                    anchors.fill: parent
                    u: win.u
                    path: slot.entry ? slot.entry.path : ""
                    fileName: slot.entry ? slot.entry.name : ""
                    fileBytes: slot.entry ? slot.entry.bytes : 0
                    palette: slot.entry && !slot.entry.remote ? WallpaperPalettes.palettes[slot.entry.path] ?? null : null
                    imageSize: slot.entry && !slot.entry.remote ? WallpaperPalettes.sizes[slot.entry.path] ?? null : null
                    thumbUrl: slot.entry?.remote ? slot.entry.thumb : ""
                    imageColors: slot.entry?.remote ? slot.entry.colors : []
                    detailText: slot.entry?.remote ? slot.entry.detail : ""
                    favourite: slot.entry ? win.favouriteSet[slot.entry.path] === true : false
                    current: slot.entry && !slot.entry.remote ? slot.entry.path === win.currentTargetPath() : false
                    front: slot.front
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (slot.ad < 0.5) win.activate(slot.entry);
                        else win.jump(slot.cardIndex);
                    }
                    onWheel: wheel => win.move(wheel.angleDelta.y > 0 ? -1 : 1)
                }
            }
        }

        // ── the actions above the card in front ───────────────────────────
        Row {
            visible: win.current !== null
            spacing: 10 * win.u
            anchors.horizontalCenter: parent.horizontalCenter
            y: win.frontCenterY - win.cardH * 0.6 - win.lift - 54 * win.u
            z: 200

            Rectangle {
                visible: !win.remote
                width: 38 * win.u
                height: 38 * win.u
                radius: height / 2
                color: ColorUtils.transparentize(win.panelBg, 0.06)
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "favorite"
                    fill: win.current && win.favouriteSet[win.current.path] === true ? 1 : 0
                    iconSize: 20 * win.u
                    color: win.accent
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.toggleFavourite(win.current.path)
                }
            }
            Rectangle {
                width: setRow.implicitWidth + 28 * win.u
                height: 38 * win.u
                radius: height / 2
                color: win.accent
                Row {
                    id: setRow
                    anchors.centerIn: parent
                    spacing: 8 * win.u
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "wallpaper"
                        iconSize: 18 * win.u
                        color: win.accentInk
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.downloading !== "" ? Translation.tr("Downloading…")
                            : win.remote ? Translation.tr("Download and set")
                            : win.targetLabel !== "" ? Translation.tr("Set for %1").arg(win.targetLabel)
                            : Translation.tr("Set wallpaper")
                        font.pixelSize: 14 * win.u
                        font.weight: Font.DemiBold
                        color: win.accentInk
                    }
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "keyboard_return"
                        iconSize: 16 * win.u
                        color: win.accentInk
                        opacity: 0.7
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.activate(win.current)
                }
            }
        }

        // ── the source and the count ──────────────────────────────────────
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 26 * win.u
            spacing: 6 * win.u
            z: 200

            Repeater {
                model: [
                    { "key": "folder", "label": Translation.tr("Folder"), "icon": "folder" },
                    { "key": "favourites", "label": Translation.tr("Favourites"), "icon": "favorite" },
                    { "key": "wallhaven", "label": "Wallhaven", "icon": "travel_explore" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: win.source === modelData.key
                    width: tabRow.implicitWidth + 24 * win.u
                    height: 32 * win.u
                    radius: height / 2
                    color: on ? win.accent : ColorUtils.transparentize(win.panelBg, 0.06)
                    Row {
                        id: tabRow
                        anchors.centerIn: parent
                        spacing: 6 * win.u
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.icon
                            fill: on ? 1 : 0
                            iconSize: 16 * win.u
                            color: on ? win.accentInk : win.inkOn
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            font.pixelSize: 13 * win.u
                            color: on ? win.accentInk : win.inkOn
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.source = modelData.key
                    }
                }
            }
            Rectangle { // sub-folders on or off (folder tab)
                visible: win.source === "folder"
                width: subRow.implicitWidth + 24 * win.u
                height: 32 * win.u
                radius: height / 2
                color: win.subfolders ? ColorUtils.transparentize(win.accent, 0.55) : ColorUtils.transparentize(win.panelBg, 0.06)
                Row {
                    id: subRow
                    anchors.centerIn: parent
                    spacing: 6 * win.u
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "account_tree"
                        iconSize: 16 * win.u
                        color: win.inkOn
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Subfolders")
                        font.pixelSize: 13 * win.u
                        color: win.inkOn
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Config.options.wallpaperSelector.deckSubfolders = !win.subfolders
                }
            }
            Rectangle {
                width: countText.implicitWidth + 24 * win.u
                height: 32 * win.u
                radius: height / 2
                color: ColorUtils.transparentize(win.panelBg, 0.06)
                StyledText {
                    id: countText
                    anchors.centerIn: parent
                    text: win.entries.length > 0 ? (win.index + 1) + " / " + win.entries.length : "0"
                    font.pixelSize: 13 * win.u
                    color: win.inkOn
                }
            }
        }

        // The Wallhaven search field: / focuses it, Enter searches, Esc returns to the cards.
        Rectangle {
            id: whSearchBar
            visible: win.remote
            anchors.horizontalCenter: parent.horizontalCenter
            y: 72 * win.u
            z: 200
            width: 420 * win.u
            height: 36 * win.u
            radius: height / 2
            color: win.panelBg
            border.width: win.searching ? 2 : 0
            border.color: win.accent
            MaterialSymbol {
                x: 12 * win.u
                anchors.verticalCenter: parent.verticalCenter
                text: win.whLoading ? "hourglass_top" : "search"
                iconSize: 18 * win.u
                color: win.inkDim
            }
            TextInput {
                id: searchInput
                anchors.fill: parent
                anchors.leftMargin: 40 * win.u
                anchors.rightMargin: 14 * win.u
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                font.pixelSize: 14 * win.u
                color: win.inkOn
                selectionColor: win.accent
                selectedTextColor: win.accentInk
                onAccepted: { win.whSearch(text); win.searching = false; keys.forceActiveFocus(); }
                Keys.onEscapePressed: { win.searching = false; keys.forceActiveFocus(); }
                onActiveFocusChanged: win.searching = activeFocus
                StyledText {
                    visible: searchInput.text.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("Search Wallhaven   ( / )   ·   S sort: %1").arg(WallpaperBrowser.currentSortType)
                    font.pixelSize: 13 * win.u
                    color: win.inkDim
                }
            }
        }

        // ── the filters: a pill beside the search field opens a panel of grouped choices ──
        component Seg: Item {
            id: seg
            property string title: ""
            property var options: [] // { label, on, dim }
            signal picked(int index)
            implicitHeight: segTitle.implicitHeight + 7 * win.u + segFlow.implicitHeight
            height: implicitHeight
            StyledText {
                id: segTitle
                text: seg.title.toUpperCase()
                font.pixelSize: 10 * win.u
                font.weight: Font.Bold
                font.letterSpacing: 0.8
                color: win.inkDim
                opacity: 0.8
            }
            Flow {
                id: segFlow
                y: segTitle.implicitHeight + 7 * win.u
                width: parent.width
                spacing: 5 * win.u
                Repeater {
                    model: seg.options
                    delegate: Rectangle {
                        id: opt
                        required property var modelData
                        required property int index
                        width: optText.implicitWidth + 24 * win.u
                        height: 30 * win.u
                        radius: height / 2
                        color: modelData.on ? win.accent : optMouse.containsMouse ? win.chipBgHover : win.chipBg
                        border.width: modelData.on ? 0 : 1
                        border.color: ColorUtils.transparentize(win.hairline, 0.35)
                        opacity: modelData.dim ? 0.5 : 1
                        Behavior on color { ColorAnimation { duration: 140 } }
                        StyledText {
                            id: optText
                            anchors.centerIn: parent
                            text: modelData.label
                            font.pixelSize: 12 * win.u
                            font.weight: modelData.on ? Font.DemiBold : Font.Normal
                            color: modelData.on ? win.accentInk : win.inkOn
                        }
                        MouseArea {
                            id: optMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: seg.picked(opt.index)
                        }
                    }
                }
            }
        }

        Rectangle { // the pill
            id: filterPill
            visible: win.remote
            x: whSearchBar.x + whSearchBar.width + 10 * win.u
            y: whSearchBar.y
            z: 210
            width: pillRow.implicitWidth + 24 * win.u
            height: whSearchBar.height
            radius: height / 2
            color: win.filtersOpen ? win.accent : win.panelBg
            border.width: win.filtersOpen ? 0 : 1
            border.color: ColorUtils.transparentize(win.hairline, 0.35)
            Behavior on color { ColorAnimation { duration: 140 } }
            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: 6 * win.u
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "tune"
                    iconSize: 18 * win.u
                    color: win.filtersOpen ? win.accentInk : win.inkOn
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.filterCount > 0 ? Translation.tr("Filters · %1").arg(win.filterCount) : Translation.tr("Filters")
                    font.pixelSize: 13 * win.u
                    color: win.filtersOpen ? win.accentInk : win.inkOn
                }
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "expand_more"
                    iconSize: 18 * win.u
                    rotation: win.filtersOpen ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    color: win.filtersOpen ? win.accentInk : win.inkOn
                }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.filtersOpen = !win.filtersOpen }
        }

        RectangularShadow {
            visible: filterPanel.visible
            anchors.fill: filterPanel
            offset.y: 10 * win.u
            blur: 36 * win.u
            radius: filterPanel.radius
            color: Qt.rgba(0, 0, 0, 0.5 * filterPanel.opacity)
            z: 204
        }
        Rectangle { // the panel
            id: filterPanel
            visible: win.remote && height > 1
            anchors.horizontalCenter: parent.horizontalCenter
            y: whSearchBar.y + whSearchBar.height + 12 * win.u
            z: 205
            width: Math.min(parent.width - 80 * win.u, 720 * win.u)
            height: win.filtersOpen ? filterColumn.implicitHeight + 40 * win.u : 0
            radius: 20 * win.u
            clip: true
            opacity: win.filtersOpen ? 1 : 0
            color: win.panelBg
            border.width: 1
            border.color: ColorUtils.transparentize(win.hairline, 0.3)
            Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 160 } }
            MouseArea { anchors.fill: parent } // keeps clicks off the backdrop

            Column {
                id: filterColumn
                x: 22 * win.u
                y: 18 * win.u
                width: parent.width - 44 * win.u
                spacing: 16 * win.u

                // header
                Item {
                    width: parent.width
                    height: 28 * win.u
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8 * win.u
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "tune"
                            iconSize: 20 * win.u
                            color: win.accent
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Wallhaven filters")
                            font.pixelSize: 15 * win.u
                            font.weight: Font.DemiBold
                            color: win.inkOn
                        }
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: win.filterCount > 0
                        width: resetRow.implicitWidth + 22 * win.u
                        height: 28 * win.u
                        radius: height / 2
                        color: resetMouse.containsMouse ? win.chipBgHover : win.chipBg
                        Row {
                            id: resetRow
                            anchors.centerIn: parent
                            spacing: 5 * win.u
                            MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "restart_alt"; iconSize: 16 * win.u; color: win.inkOn }
                            StyledText { anchors.verticalCenter: parent.verticalCenter; text: Translation.tr("Reset"); font.pixelSize: 12 * win.u; color: win.inkOn }
                        }
                        MouseArea { id: resetMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.resetFilters() }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: ColorUtils.transparentize(win.hairline, 0.5) }

                Row {
                    width: parent.width
                    spacing: 20 * win.u
                    readonly property real cell: (width - spacing * 2) / 3
                    Seg {
                        width: parent.cell
                        title: Translation.tr("Category")
                        options: [
                            { "label": Translation.tr("General"), "on": win.bit(WallpaperBrowser.effectiveCategories, 0) },
                            { "label": Translation.tr("Anime"), "on": win.bit(WallpaperBrowser.effectiveCategories, 1) },
                            { "label": Translation.tr("People"), "on": win.bit(WallpaperBrowser.effectiveCategories, 2) }
                        ]
                        onPicked: i => win.toggleCategory(i)
                    }
                    Seg {
                        width: parent.cell
                        title: Translation.tr("Purity")
                        options: [
                            { "label": "SFW", "on": win.bit(Config.options.wallhaven.purity, 0) },
                            { "label": Translation.tr("Sketchy"), "on": win.bit(Config.options.wallhaven.purity, 1) },
                            { "label": win.hasKey ? "NSFW" : "NSFW 🔒", "on": win.hasKey && win.bit(Config.options.wallhaven.purity, 2), "dim": !win.hasKey }
                        ]
                        onPicked: i => win.togglePurity(i)
                    }
                    Seg {
                        width: parent.cell
                        title: Translation.tr("Order")
                        options: [
                            { "label": Translation.tr("Newest"), "on": Config.options.wallhaven.order !== "asc" },
                            { "label": Translation.tr("Oldest"), "on": Config.options.wallhaven.order === "asc" }
                        ]
                        onPicked: i => win.setWh("order", i === 1 ? "asc" : "desc")
                    }
                }

                Seg {
                    width: parent.width
                    title: Translation.tr("Sort by")
                    options: win.whSorts.map(v => ({ "label": v.replace("_", " "), "on": WallpaperBrowser.currentSortType === v }))
                    onPicked: i => { WallpaperBrowser.setSort(win.whSorts[i]); win.whSearch(win.whQuery); }
                }
                Seg {
                    width: parent.width
                    title: Translation.tr("Period")
                    options: [{ "label": Translation.tr("Any time"), "on": WallpaperBrowser.currentSortType !== "toplist" }].concat(
                        win.whRanges.map(v => ({ "label": win.rangeNames[v], "on": WallpaperBrowser.currentSortType === "toplist" && Config.options.wallhaven.topRange === v })))
                    onPicked: i => win.pickPeriod(i === 0 ? "" : win.whRanges[i - 1])
                }

                Row {
                    width: parent.width
                    spacing: 20 * win.u
                    readonly property real cell: (width - spacing) / 2
                    Seg {
                        width: parent.cell
                        title: Translation.tr("Minimum size")
                        options: win.whResolutions.map(v => ({ "label": win.resolutionNames[v] ?? v, "on": Config.options.wallhaven.atleast === v }))
                        onPicked: i => win.setWh("atleast", win.whResolutions[i])
                    }
                    Seg {
                        width: parent.cell
                        title: Translation.tr("Aspect ratio")
                        options: win.whRatios.map(v => ({ "label": v === "" ? Translation.tr("Any") : v.replace("x", ":"), "on": Config.options.wallhaven.ratios === v }))
                        onPicked: i => win.setWh("ratios", win.whRatios[i])
                    }
                }

                Item {
                    width: parent.width
                    height: colourTitle.implicitHeight + 9 * win.u + 26 * win.u
                    StyledText {
                        id: colourTitle
                        text: Translation.tr("Colour").toUpperCase()
                        font.pixelSize: 10 * win.u
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                        color: win.inkDim
                        opacity: 0.8
                    }
                    Row {
                        y: colourTitle.implicitHeight + 9 * win.u
                        spacing: 9 * win.u
                        Repeater {
                            model: win.whPalette
                            delegate: Rectangle {
                                required property string modelData
                                readonly property bool chosen: Config.options.wallhaven.colors === modelData
                                width: 24 * win.u
                                height: width
                                radius: width / 2
                                color: "#" + modelData
                                scale: chosen ? 1.2 : swatchMouse.containsMouse ? 1.1 : 1
                                Behavior on scale { NumberAnimation { duration: 120 } }
                                border.width: chosen ? 3 * win.u : 1
                                border.color: chosen ? win.accent : ColorUtils.transparentize(win.inkOn, 0.7)
                                MouseArea { id: swatchMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.pickColor(modelData) }
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            visible: win.entries.length === 0
            anchors.centerIn: parent
            text: win.remote ? (win.whLoading ? Translation.tr("Loading…") : win.whError !== "" ? win.whError : Translation.tr("Nothing found"))
                : Wallpapers.directoryLoading ? Translation.tr("Loading…")
                : win.source === "favourites" ? Translation.tr("No favourites yet. Press F on a card.")
                : Translation.tr("No wallpapers in this folder")
            font.pixelSize: 18 * win.u
            color: win.inkOn
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8 * win.u
            text: win.remote ? Translation.tr("←/→ move  ·  Enter download & set  ·  / search  ·  V filters  ·  S sort  ·  Tab source  ·  Esc close")
                : Translation.tr("←/→ move  ·  Enter set  ·  F favourite  ·  R random  ·  Tab source  ·  Esc close")
            font.pixelSize: 11 * win.u
            color: ColorUtils.transparentize(win.inkOn, 0.35)
            z: 200
        }
    }

    // ── keys ─────────────────────────────────────────────────────────────
    FocusScope {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            const k = event.key;
            if (k === Qt.Key_Escape) { if (win.filtersOpen) win.filtersOpen = false; else win.close(); }
            else if (k === Qt.Key_V && win.remote) win.filtersOpen = !win.filtersOpen;
            else if (k === Qt.Key_Left || k === Qt.Key_H || k === Qt.Key_A) win.move(-1);
            else if (k === Qt.Key_Right || k === Qt.Key_L || k === Qt.Key_D) win.move(1);
            else if (k === Qt.Key_PageUp) win.move(-5);
            else if (k === Qt.Key_PageDown) win.move(5);
            else if (k === Qt.Key_Home) win.jump(0);
            else if (k === Qt.Key_End) win.jump(win.entries.length - 1);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
                win.activate(win.current);
            } else if (k === Qt.Key_F) {
                if (win.current && !win.remote) win.toggleFavourite(win.current.path);
            } else if (k === Qt.Key_Slash && win.remote) {
                searchInput.forceActiveFocus();
            } else if (k === Qt.Key_S && win.remote) {
                win.cycleSort();
            } else if (win.remote && k >= Qt.Key_1 && k <= Qt.Key_3) {
                win.toggleCategory(k - Qt.Key_1);
            } else if (win.remote && k >= Qt.Key_4 && k <= Qt.Key_6) {
                win.togglePurity(k - Qt.Key_4);
            } else if (k === Qt.Key_O && win.remote) {
                win.toggleOrder();
            } else if (k === Qt.Key_T && win.remote) {
                win.cycleRange();
            } else if (k === Qt.Key_E && win.remote) {
                win.cycleRes();
            } else if (k === Qt.Key_X && win.remote) {
                win.cycleRatio();
            } else if (k === Qt.Key_R) {
                win.jump(Math.floor(Math.random() * win.entries.length));
            } else if (k === Qt.Key_Tab) {
                const order = ["folder", "favourites", "wallhaven"];
                win.source = order[(order.indexOf(win.source) + 1) % order.length];
            } else return;
            event.accepted = true;
        }
    }
}
