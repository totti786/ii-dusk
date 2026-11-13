pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The file manager. This item owns the state (tabs, the folder shown, selection, clipboard,
 * running jobs, undo) and every operation; the views, sidebar, menus and dialogs only draw and
 * report what the user did. Anything that touches files goes to fm_helper.py through `backend`.
 */
FocusScope {
    id: root

    signal closeRequested()
    signal splitToggleRequested()

    // ── split view: the window may hold two of these side by side ──
    property bool secondary: false      // the right-hand pane: no sidebar, closes by unsplitting
    property bool split: false
    property var peer: null             // the other pane while split
    property string initialPath: ""     // where a new second pane starts
    readonly property bool paneActive: root.activeFocus

    readonly property var cfg: Persistent.states.background.mediaMode

    // ── tabs and navigation ──
    property var tabs: [{ path: "", back: [], fwd: [], title: "" }]
    property int tabIndex: 0
    readonly property var tab: root.tabs[root.tabIndex]
    readonly property string path: root.tab.path
    property bool standalone: false   // a window of its own keeps its helper running by itself
    readonly property bool isTrash: root.path.startsWith("trash:")
    readonly property bool isVirtual: root.path.startsWith("recent:") || root.path.startsWith("starred:")
    readonly property bool canUp: !root.isTrash && !root.isVirtual && root.path !== "/" && root.path.length > 0

    // ── the folder ──
    property var entries: []
    property bool loading: false
    property string loadError: ""
    property real freeSpace: 0
    property real totalSpace: 0
    property bool writable: true
    property int listSerial: 0

    // ── search / filter ──
    property bool searchOpen: false
    property bool deepSearch: true
    // The folder of the other pane while the window is split; empty otherwise
    property string otherPanePath: ""
    property string query: ""
    property var searchResults: []
    property bool searchRunning: false
    property int searchJob: -1

    // Per-folder view: a folder remembers the view and sort the user last chose in it
    property var starred: []
    property var folderColors: ({})
    property var folderViews: ({})
    readonly property var starredSet: {
        const o = ({});
        for (const p of root.starred)
            o[p] = true;
        return o;
    }
    readonly property var viewPref: root.folderViews[root.path] ?? null
    readonly property string viewMode: root.viewPref?.view ?? root.cfg.fmView
    readonly property bool showHidden: root.cfg.fmHidden
    readonly property string sortKey: root.viewPref?.sortKey ?? root.cfg.fmSortKey
    readonly property bool sortDesc: root.viewPref?.sortDesc ?? root.cfg.fmSortDesc

    // Search filters; any of them makes the search go through the whole tree
    property string searchKind: ""
    property int searchDays: 0
    property int searchMinMb: 0
    property bool searchContent: false
    readonly property bool hasFilters: root.searchKind.length > 0 || root.searchDays > 0 || root.searchMinMb > 0
    readonly property bool deepActive: (root.deepSearch || root.hasFilters || root.searchContent) && !root.isTrash && !root.isVirtual
    readonly property bool searchMode: root.searchOpen && root.deepActive && (root.query.trim().length > 0 || root.hasFilters)
    property var netMounts: []

    // ── selection ──
    property var selected: ({})
    property int cursor: -1
    property int anchor: -1
    property string renamingPath: ""
    property var pendingReveal: null

    readonly property var shown: {
        const src = root.searchMode ? root.searchResults : root.entries;
        const q = root.searchOpen && !root.searchMode ? root.query.trim().toLowerCase() : "";
        const list = src.filter(e => (root.showHidden || !e.hidden || root.searchMode) && (q.length === 0 || e.name.toLowerCase().includes(q)));
        const dir = root.sortDesc ? -1 : 1;
        const key = root.sortKey;
        const cmp = (a, b) => {
            if (a.isDir !== b.isDir)
                return a.isDir ? -1 : 1;
            let r = 0;
            if (key === "size")
                r = root.sizeOf(a) - root.sizeOf(b);
            else if (key === "mtime")
                r = (root.isTrash ? String(a.deleted).localeCompare(String(b.deleted)) : a.mtime - b.mtime);
            else if (key === "type")
                r = (a.kind + a.mime).localeCompare(b.kind + b.mime);
            if (r === 0)
                r = root.natural(a.name, b.name);
            return r * dir;
        };
        return list.sort(cmp);
    }
    readonly property var selection: root.shown.filter(e => root.selected[e.path])
    readonly property int selCount: root.selection.length
    readonly property var selectionPaths: root.selection.map(e => e.path)
    readonly property real selectionSize: root.selection.reduce((s, e) => s + root.sizeOf(e, 0), 0)

    // ── clipboard, undo, jobs, side data ──
    property var clipPaths: []
    property bool clipCut: false
    property var undoStack: []
    property var jobs: []
    property var places: []
    property var bookmarks: []
    property var devices: []
    property var phones: []
    property int trashCount: 0
    property var thumbs: ({})
    property var iconMap: ({})
    property var thumbable: []
    property var thumbQueue: []
    property int thumbsBusy: 0
    property var customActions: []
    property string toastText: ""
    property bool toastUndo: false
    property string typeBuffer: ""
    property int listJob: -1
    property int sizesJob: -1
    property var folderSizes: ({})
    property string sizesSig: ""
    property real sizesAt: 0
    readonly property bool wantSizes: root.cfg.fmFolderSizes || root.sortKey === "size"
    signal newWindowRequested(string path)
    property bool typeMiss: false
    property var conflictQueue: []

    readonly property string dragUris: root.selection.map(e => "file://" + e.path.split("/").map(encodeURIComponent).join("/")).join("\r\n")

    focus: true

    // ───────────────────────── helpers ─────────────────────────

    function natural(a: string, b: string): int {
        const ax = a.toLowerCase().split(/(\d+)/), bx = b.toLowerCase().split(/(\d+)/);
        for (let i = 0; i < Math.min(ax.length, bx.length); ++i) {
            if (ax[i] === bx[i])
                continue;
            if (i % 2 === 1) {
                const d = parseInt(ax[i]) - parseInt(bx[i]);
                if (d !== 0)
                    return d;
            }
            return ax[i] < bx[i] ? -1 : 1;
        }
        return ax.length - bx.length;
    }

    function dirname(p: string): string {
        const i = p.lastIndexOf("/");
        return i <= 0 ? "/" : p.slice(0, i);
    }

    function basename(p: string): string {
        return p.slice(p.lastIndexOf("/") + 1);
    }

    function urlsToPaths(urls: var): var {
        return Array.from(urls ?? []).map(u => String(u)).filter(u => u.startsWith("file://")).map(u => decodeURIComponent(u.slice(7)));
    }

    function bytes(s: real): string {
        if (s < 1024)
            return s + " B";
        const u = ["KiB", "MiB", "GiB", "TiB"];
        let v = s / 1024, i = 0;
        while (v >= 1024 && i < u.length - 1) {
            v /= 1024;
            i++;
        }
        return v.toFixed(v < 10 ? 1 : 0) + " " + u[i];
    }

    function toast(text: string, undoable = false): void {
        root.toastText = text;
        root.toastUndo = undoable;
        toastTimer.restart();
    }

    function normalize(p: string): string {
        p = String(p);
        if (p.startsWith("trash:"))
            return "trash:///";
        if (p.startsWith("recent:"))
            return "recent:///";
        if (p.startsWith("starred:"))
            return "starred:///";
        if (p.startsWith("file://"))
            p = decodeURIComponent(p.slice(7));
        if (p === "~" || p.startsWith("~/"))
            p = backend.home + p.slice(1);
        if (!p.startsWith("/"))
            p = (root.isTrash || root.isVirtual ? backend.home : root.path) + "/" + p;
        const out = [];
        for (const seg of p.split("/")) {
            if (seg.length === 0 || seg === ".")
                continue;
            if (seg === "..")
                out.pop();
            else
                out.push(seg);
        }
        return "/" + out.join("/");
    }

    function titleFor(p: string): string {
        if (p.startsWith("trash:"))
            return qsTr("Trash");
        if (p.startsWith("recent:"))
            return qsTr("Recent");
        if (p.startsWith("starred:"))
            return qsTr("Starred");
        if (p === backend.home)
            return qsTr("Home");
        return p === "/" ? "/" : root.basename(p);
    }

    // ───────────────────────── navigation ─────────────────────────

    function patchTab(changes: var): void {
        const next = root.tabs.slice();
        next[root.tabIndex] = Object.assign({}, next[root.tabIndex], changes);
        root.tabs = next;
    }

    function go(p: string, reveal = ""): void {
        root.typeClear();
        const np = root.normalize(p);
        if (reveal.length > 0)
            root.pendingReveal = { path: reveal, rename: false };
        if (np === root.path) {
            root.reload(false);
            return;
        }
        root.patchTab({ back: root.tab.back.concat([root.path]).filter(x => x.length > 0), fwd: [], path: np, title: root.titleFor(np) });
        root.load();
    }

    function goBack(): void {
        if (root.tab.back.length === 0)
            return;
        const b = root.tab.back.slice();
        const p = b.pop();
        root.patchTab({ back: b, fwd: [root.path].concat(root.tab.fwd), path: p, title: root.titleFor(p) });
        root.load();
    }

    function goForward(): void {
        if (root.tab.fwd.length === 0)
            return;
        const f = root.tab.fwd.slice();
        const p = f.shift();
        root.patchTab({ back: root.tab.back.concat([root.path]), fwd: f, path: p, title: root.titleFor(p) });
        root.load();
    }

    function goUp(): void {
        if (root.canUp)
            root.go(root.dirname(root.path), root.path);
    }

    function load(): void {
        root.folderSizes = ({});
        root.sizesSig = "";
        root.selected = ({});
        root.cursor = -1;
        root.anchor = -1;
        root.renamingPath = "";
        root.closeSearch();
        root.reload(false);
        backend.request("watch", { watchId: "main", path: root.path }, null);
    }

    function sizeOf(e: var, unknown = -1): real {
        if (!e.isDir)
            return e.size;
        return root.folderSizes[e.path] ?? unknown;
    }

    /// Sizes of the folders in view, counted in the background and shown as they arrive
    function refreshFolderSizes(force: bool): void {
        if (!root.wantSizes || root.isVirtual || root.isTrash)
            return;
        const dirs = root.entries.filter(e => e.isDir && !e.isLink).map(e => e.path);
        const sig = root.path + "|" + dirs.join("\n");
        if (!force && sig === root.sizesSig && Date.now() - root.sizesAt < 3000)
            return;
        root.sizesSig = sig;
        root.sizesAt = Date.now();
        if (root.sizesJob >= 0)
            backend.cancel(root.sizesJob);
        if (dirs.length === 0)
            return;
        let jid = -1;
        jid = backend.request("dirsizes", { paths: dirs.slice(0, 400) }, {
            partial: m => { if (jid === root.sizesJob) root.folderSizes = Object.assign({}, root.folderSizes, m.sizes); },
            done: m => { if (jid === root.sizesJob && m.sizes) root.folderSizes = Object.assign({}, root.folderSizes, m.sizes); }
        });
        root.sizesJob = jid;
    }

    onWantSizesChanged: root.refreshFolderSizes(true)

    function reload(keepSelection: bool): void {
        const serial = ++root.listSerial;
        const wanted = root.path;
        root.loading = true;
        // The list the user left behind is no use any more; stop reading it
        if (root.listJob >= 0)
            backend.cancel(root.listJob);
        let parts = [];
        root.listJob = backend.request("list", { path: wanted }, {
            partial: m => {
                // A huge folder shows up while it is read (a refresh keeps the old rows until done)
                if (serial !== root.listSerial || keepSelection)
                    return;
                // The types come first: a row asks for its thumbnail the moment it is built
                root.thumbable = Array.from(new Set(root.thumbable.concat(m.thumbable ?? [])));
                root.iconMap = Object.assign({}, root.iconMap, m.icons ?? {});
                parts = parts.concat(m.entries);
                root.entries = parts;
            },
            done: m => {
                if (serial !== root.listSerial)
                    return;
                const all = m.streamed ? parts.concat(m.entries) : m.entries;
                root.loading = false;
                root.loadError = "";
                // Types before rows: a row asks for its thumbnail as soon as it is built, and used
                // to find the previous folder's list, so a video or a big picture got none
                root.iconMap = Object.assign({}, keepSelection ? root.iconMap : ({}), m.icons ?? {});
                root.thumbable = keepSelection ? Array.from(new Set(root.thumbable.concat(m.thumbable ?? []))) : Array.from(new Set((m.streamed ? root.thumbable : []).concat(m.thumbable ?? [])));
                root.entries = all;
                root.freeSpace = m.free ?? 0;
                root.totalSpace = m.total ?? 0;
                root.writable = m.writable ?? true;
                if (keepSelection) {
                    const keep = ({});
                    for (const e of all)
                        if (root.selected[e.path])
                            keep[e.path] = true;
                    root.selected = keep;
                } else {
                    root.thumbs = ({});
                    root.thumbQueue = [];
                }
                root.applyReveal();
                root.refreshFolderSizes(false);
                if (!keepSelection)
                    Qt.callLater(root.reclaimFocus);
            },
            error: msg => {
                if (serial !== root.listSerial)
                    return;
                root.loading = false;
                if (msg.includes("Not a folder")) {
                    // A file was asked for: show its folder with the file selected
                    root.go(root.dirname(wanted), wanted);
                    return;
                }
                root.loadError = msg;
                root.entries = [];
                if (root.tab.back.length > 0 && root.path !== backend.home) {
                    root.toast(msg);
                    root.goBack();
                }
            }
        });
    }

    /// Opening a folder replaces every row, which drops the focus the clicked row held; without
    /// it type-to-find goes nowhere. A text field, dialog or rename in progress keeps its focus.
    function reclaimFocus(): void {
        if (root.dialogItem || root.renamingPath.length > 0)
            return;
        const f = root.Window.activeFocusItem;
        if (f && f !== root && ("cursorPosition" in f))
            return;
        root.forceActiveFocus();
    }

    function applyReveal(): void {
        const r = root.pendingReveal;
        if (!r)
            return;
        const i = root.shown.findIndex(e => e.path === r.path);
        if (i < 0)
            return;
        root.pendingReveal = null;
        root.setOnly(i);
        root.ensureVisible(i);
        if (r.rename)
            root.renamingPath = r.path;
    }

    function refreshSide(): void {
        backend.request("places", {}, { done: m => {
            root.places = m.places;
            root.bookmarks = m.bookmarks;
            root.trashCount = m.trashCount;
        } });
        backend.request("devices", {}, { done: m => root.devices = m.devices });
        root.refreshPhones();
        root.refreshMeta();
        root.refreshNet();
    }

    // ───────────────────────── starred, colours, remembered views ─────────────────────────

    function refreshMeta(): void {
        backend.request("meta_get", {}, { done: m => {
            root.starred = m.starred;
            root.folderColors = m.colors;
            root.folderViews = m.views;
        } });
    }

    function toggleStar(paths: var): void {
        const on = !paths.every(p => root.starredSet[p]);
        root.starred = on ? root.starred.concat(paths.filter(p => !root.starredSet[p])) : root.starred.filter(p => paths.indexOf(p) < 0);
        backend.request("meta_set", { kind: "star", paths: paths, on: on }, { done: () => { if (root.path.startsWith("starred:")) root.reload(true); } });
        root.toast(on ? qsTr("Added to Starred") : qsTr("Removed from Starred"));
    }

    function setFolderColor(paths: var, color: string): void {
        const next = Object.assign({}, root.folderColors);
        for (const p of paths) {
            if (color.length > 0)
                next[p] = color;
            else
                delete next[p];
        }
        root.folderColors = next;
        backend.request("meta_set", { kind: "color", paths: paths, color: color }, {});
    }

    /// Remember the view or sort chosen in this folder (an empty patch forgets it)
    function rememberView(patch: var): void {
        const path = root.path;
        const next = Object.assign({}, root.folderViews);
        if (patch === null) {
            delete next[path];
        } else {
            next[path] = Object.assign({ view: root.viewMode, sortKey: root.sortKey, sortDesc: root.sortDesc }, patch);
        }
        root.folderViews = next;
        backend.request("meta_set", { kind: "view", path: path, view: patch === null ? null : next[path] }, {});
    }

    // ───────────────────────── network places, MTP ─────────────────────────

    function refreshNet(): void {
        backend.request("net_places", {}, { done: m => root.netMounts = m.mounts, error: () => { root.netMounts = []; } });
    }

    // A phone plugged in later shows up without reopening the window
    Timer {
        interval: 5000
        repeat: true
        running: root.visible
        onTriggered: root.refreshNet()
    }

    function connectServer(): void {
        root.openDialog(promptDialog, {
            title: qsTr("Connect to server"),
            message: qsTr("An address such as smb://nas/share, sftp://user@host/ or ftp://host/"),
            label: qsTr("Address"), text: "smb://", confirmText: qsTr("Connect"), selectBase: false,
            onAcceptedFn: uri => root.mountNet(uri)
        });
    }

    function mountNet(uri: string): void {
        root.toast(qsTr("Connecting…"));
        backend.request("net_mount", { uri: uri }, {
            done: m => { root.refreshNet(); root.go(m.path); },
            error: msg => root.toast(msg)
        });
    }

    function unmountNet(mount: var): void {
        backend.request("net_unmount", { uri: mount.uri }, {
            done: () => { root.refreshNet(); if (root.path.startsWith(mount.path)) root.go(backend.home); root.toast(qsTr("Disconnected")); },
            error: msg => root.toast(msg)
        });
    }

    // ───────────────────────── image tools ─────────────────────────

    function imageTool(tool: string, extra: var): void {
        const paths = root.selection.filter(e => e.kind === "image").map(e => e.path);
        if (paths.length === 0)
            return;
        root.toast(qsTr("Working on %1 image(s)…").arg(paths.length));
        backend.request("image_tool", Object.assign({ tool: tool, paths: paths }, extra), {
            done: m => { root.toast(qsTr("Created %1 file(s)").arg(m.made.length)); root.reload(true); },
            error: msg => root.toast(msg)
        });
    }

    // ───────────────────────── KDE Connect ─────────────────────────

    function refreshPhones(): void {
        backend.request("kdc_devices", {}, { done: m => root.phones = m.devices, error: () => { root.phones = []; } });
    }

    function sendToPhone(dev: var, paths: var): void {
        backend.request("kdc_send", { device: dev.id, paths: paths }, {
            done: m => root.toast(qsTr("Sent %1 to %2").arg(m.sent === 1 ? qsTr("1 file") : qsTr("%1 files").arg(m.sent)).arg(dev.name)),
            error: msg => root.toast(msg)
        });
    }

    function openPhone(dev: var): void {
        root.toast(qsTr("Connecting to %1…").arg(dev.name));
        backend.request("kdc_mount", { device: dev.id }, {
            done: m => { if (m.mount) root.go(m.mount); },
            error: msg => root.toast(msg)
        });
    }

    function loadActions(): void {
        backend.request("actionsAll", {}, { done: m => root.customActions = m.actions });
    }

    // ───────────────────────── tabs ─────────────────────────

    function newTab(p = ""): void {
        const np = p.length > 0 ? root.normalize(p) : root.path;
        root.tabs = root.tabs.concat([{ path: np, back: [], fwd: [], title: root.titleFor(np) }]);
        root.tabIndex = root.tabs.length - 1;
        root.load();
    }

    function closeTab(i: int): void {
        if (root.tabs.length <= 1) {
            root.closeRequested();
            return;
        }
        const next = root.tabs.slice();
        next.splice(i, 1);
        const wasCurrent = i === root.tabIndex;
        root.tabs = next;
        root.tabIndex = Math.min(i < root.tabIndex ? root.tabIndex - 1 : root.tabIndex, next.length - 1);
        if (wasCurrent || i < root.tabIndex + 1)
            root.load();
    }

    function switchTab(i: int): void {
        if (i === root.tabIndex || i < 0 || i >= root.tabs.length)
            return;
        root.tabIndex = i;
        root.load();
    }

    // ───────────────────────── selection ─────────────────────────

    function setSelection(paths: var): void {
        const m = ({});
        for (const p of paths)
            m[p] = true;
        root.selected = m;
    }

    function setOnly(i: int): void {
        const e = root.shown[i];
        if (!e)
            return;
        root.setSelection([e.path]);
        root.cursor = i;
        root.anchor = i;
    }

    function selectAt(i: int, mods: int): void {
        const e = root.shown[i];
        if (!e)
            return;
        if (mods & Qt.ShiftModifier) {
            const a = root.anchor >= 0 ? root.anchor : i;
            const lo = Math.min(a, i), hi = Math.max(a, i);
            const base = (mods & Qt.ControlModifier) ? Object.assign({}, root.selected) : ({});
            for (let k = lo; k <= hi; ++k)
                base[root.shown[k].path] = true;
            root.selected = base;
            root.cursor = i;
        } else if (mods & Qt.ControlModifier) {
            const m = Object.assign({}, root.selected);
            if (m[e.path])
                delete m[e.path];
            else
                m[e.path] = true;
            root.selected = m;
            root.cursor = i;
            root.anchor = i;
        } else {
            root.setOnly(i);
        }
        root.forceActiveFocus();
    }

    function selectAll(): void {
        root.setSelection(root.shown.map(e => e.path));
    }

    function clearSelection(): void {
        root.selected = ({});
        root.forceActiveFocus();
    }

    function ensureVisible(i: int): void {
        const v = root.viewMode === "grid" ? gridView : listView;
        v.ensureVisible(i);
    }

    function moveCursor(delta: int, mods: int): void {
        if (root.shown.length === 0)
            return;
        let i = root.cursor < 0 ? (delta > 0 ? 0 : root.shown.length - 1) : Math.max(0, Math.min(root.shown.length - 1, root.cursor + delta));
        if (mods & Qt.ShiftModifier)
            root.selectAt(i, Qt.ShiftModifier);
        else
            root.setOnly(i);
        root.ensureVisible(i);
    }

    /// Type-to-find. One letter jumps to the next name starting with it (repeat it to cycle);
    /// more letters narrow the match from the current row; Backspace edits, Escape clears.
    function typeKey(ev: var): void {
        if ((ev.modifiers & (Qt.AltModifier | Qt.MetaModifier)) || ev.text.length === 0)
            return;
        root.typeAhead(ev.text);
    }

    function typeAhead(ch: string): void {
        if (ch.length === 0 || root.shown.length === 0)
            return;
        root.typeBuffer += ch.toLocaleLowerCase();
        root.typeMatch(false);
    }

    function typeBackspace(): void {
        root.typeBuffer = Array.from(root.typeBuffer).slice(0, -1).join("");
        if (root.typeBuffer.length === 0) {
            root.typeMiss = false;
            return;
        }
        root.typeMatch(true);
    }

    function typeClear(): void {
        root.typeBuffer = "";
        root.typeMiss = false;
        typeTimer.stop();
    }

    function typeMatch(editing: bool): void {
        typeTimer.restart();
        const names = root.shown.map(e => e.name.toLocaleLowerCase());
        const n = names.length;
        const first = Array.from(root.typeBuffer)[0];
        const repeated = root.typeBuffer.length > 1 && Array.from(root.typeBuffer).every(c => c === first);
        // Where to start looking, and whether the current row may match again
        const from = (query, includeCurrent) => {
            const base = root.cursor >= 0 ? root.cursor : -1;
            for (let k = includeCurrent ? 0 : 1; k <= n; k++) {
                const i = (base + k + n) % n;
                if (names[i].startsWith(query))
                    return i;
            }
            return -1;
        };
        let i;
        if (root.typeBuffer.length === 1) {
            i = from(root.typeBuffer, false);
        } else {
            i = from(root.typeBuffer, true);
            if (i < 0 && repeated && !editing) {
                // "ss": no name starts with that, so cycle through the "s" names instead
                root.typeBuffer = first;
                i = from(first, false);
            }
        }
        root.typeMiss = i < 0;
        if (i >= 0) {
            root.setOnly(i);
            root.ensureVisible(i);
        }
    }

    // ───────────────────────── terminal, windows, destinations ─────────────────────────

    /// The folder a terminal should open in: the selected folder, else the one being shown
    function terminalDir(): string {
        if (root.selCount === 1 && root.selection[0].isDir)
            return root.selection[0].path;
        if (root.selCount > 0 && !root.isTrash)
            return root.dirname(root.selection[0].path);
        return root.isVirtual || root.isTrash ? backend.home : root.path;
    }

    function openTerminal(): void {
        backend.request("terminal", { dir: root.terminalDir() }, { error: m => root.toast(m) });
    }

    function openNewWindow(): void {
        root.newWindowRequested(root.terminalDir());
    }

    function setWallpaper(e: var): void {
        backend.request("wallpaper", { path: e.path }, { error: m => root.toast(m) });
        root.toast(qsTr("Wallpaper set"));
    }

    function pickDestination(mode: string): void {
        if (root.selCount === 0)
            return;
        const srcs = root.selectionPaths;
        root.openDialog(folderPickerComp, {
            backend: backend, mode: mode, srcs: srcs,
            path: root.isVirtual || root.isTrash ? backend.home : root.path,
            places: root.places.concat(root.bookmarks)
        });
        const dlg = root.dialogItem;
        if (dlg)
            dlg.destinationPicked.connect(dest => {
                root.closeDialog();
                root.startTransfer(mode, srcs, dest);
            });
    }

    function findDuplicates(): void {
        const p = root.selCount === 1 && root.selection[0].isDir ? root.selection[0].path : root.path;
        if (root.isVirtual || root.isTrash || p.length === 0)
            return;
        root.openDialog(dupesComp, { backend: backend, path: p });
    }

    function trashPaths(paths: var): void {
        root.runSimple("trash", { paths: paths }, qsTr("Moving to the Trash"), m => {
            if ((m.results ?? []).length > 0)
                root.pushUndo({ kind: "trash", pairs: m.results, label: qsTr("move to Trash") });
            root.toast(qsTr("Moved %1 to the Trash").arg(paths.length), (m.results ?? []).length > 0);
        });
    }

    function promptPassword(title: string, message: string, confirm: string, then: var): void {
        root.openDialog(promptDialog, {
            title: title, message: message, label: qsTr("Password"), text: "", secret: true,
            confirmText: confirm, selectBase: false, onAcceptedFn: t => then(t)
        });
    }

    /// The context menu from the keyboard (Menu key, Shift+F10), at the current row
    function showMenuAtCursor(): void {
        const i = root.cursor;
        if (i >= 0 && !root.selected[root.shown[i]?.path])
            root.setOnly(i);
        const grid = root.viewMode === "grid";
        const r = i >= 0 ? (grid ? gridView.cellRect(i) : listView.rowRect(i)) : Qt.rect(24, 24, 0, 0);
        menu.sideItem = null;
        menu.mode = "files";
        root.showMenu(i, grid ? r.x + r.width / 2 : Math.min(r.width / 2, 160), r.y + r.height / 2, grid ? gridView : listView);
    }

    // ───────────────────────── opening ─────────────────────────

    function openEntry(e: var): void {
        if (e.isDir) {
            if (root.isTrash)
                return;
            root.go(e.path);
        } else if (root.isTrash) {
            root.toast(qsTr("Restore it first to open it"));
        } else if (e.kind === "image") {
            GlobalStates.openImageViewerApp(e.path);
        } else if (e.kind === "audio") {
            GlobalStates.openAudioPlayerApp(e.path);
        } else {
            backend.request("open", { paths: [e.path] }, { error: m => root.toast(m) });
        }
    }

    /// Middle click: a folder opens in a new tab behind this one; anything else is left alone
    function openEntryInTab(e: var): void {
        if (e && e.isDir && !root.isTrash)
            root.openTabInBackground(e.path);
    }

    function openTabInBackground(p: string): void {
        if (p.length === 0)
            return;
        const np = root.normalize(p);
        root.tabs = root.tabs.concat([{ path: np, back: [], fwd: [], title: root.titleFor(np) }]);
    }

    /// A search result sits in some subfolder; show that folder with the file picked
    function showInFolder(e: var): void {
        root.closeSearch();
        root.go(root.dirname(e.path), e.path);
    }

    function invertSelection(): void {
        root.setSelection(root.shown.filter(e => !root.selected[e.path]).map(e => e.path));
        root.forceActiveFocus();
    }

    function selectPatternPrompt(): void {
        root.openDialog(promptDialog, {
            title: qsTr("Select by pattern"),
            message: qsTr("* matches any text and ? one character, so *.png picks every PNG here. A name without them selects names containing it."),
            label: qsTr("Pattern"), text: "*.", confirmText: qsTr("Select"), selectBase: false,
            onAcceptedFn: t => root.selectPattern(t)
        });
    }

    function selectPattern(pattern: string): void {
        const p = pattern.trim();
        if (p.length === 0)
            return;
        const esc = s => s.replace(/[.+^${}()|[\]\\]/g, "\\$&");
        const wild = /[*?]/.test(p);
        const re = new RegExp(wild ? "^" + p.split("").map(c => c === "*" ? ".*" : (c === "?" ? "." : esc(c))).join("") + "$" : esc(p), "i");
        const hits = root.shown.filter(e => re.test(e.name)).map(e => e.path);
        root.setSelection(hits);
        root.toast(hits.length === 0 ? qsTr("Nothing matches") : qsTr("%1 selected").arg(hits.length));
        root.forceActiveFocus();
    }

    function showChecksums(e: var): void {
        if (!e || e.isDir) {
            root.toast(qsTr("Checksums are for files"));
            return;
        }
        root.openDialog(checksumComp, { backend: backend, path: e.path });
    }

    function showDiskUsage(p: string): void {
        root.openDialog(duComp, { backend: backend, path: p });
    }

    function compareFolders(a: string, b: string): void {
        root.openDialog(compareComp, { backend: backend, a: a, b: b });
    }

    function comparePrompt(): void {
        root.openDialog(promptDialog, {
            title: qsTr("Compare folders"),
            message: qsTr("Compare this folder (%1) with another folder.").arg(root.basename(root.path) || "/"),
            label: qsTr("Other folder"), text: root.otherPanePath.length > 0 ? root.otherPanePath : root.path.replace(/\/[^/]*$/, "") + "/",
            confirmText: qsTr("Compare"), selectBase: false,
            onAcceptedFn: t => root.compareFolders(root.path, root.normalize(t))
        });
    }

    readonly property bool peerReady: root.split && root.peer !== null && !root.peer.isTrash && !root.peer.isVirtual && root.peer.path.length > 0

    /// Copy or move the selection into the folder shown in the other pane
    function transferToPeer(mode: string): void {
        if (!root.peerReady || root.selCount === 0)
            return;
        root.startTransfer(mode, root.selectionPaths, root.peer.path);
    }

    function openSelection(): void {
        const sel = root.selection;
        if (sel.length === 1) {
            root.openEntry(sel[0]);
        } else if (sel.length > 1) {
            if (sel.every(e => e.isDir))
                for (const e of sel)
                    root.newTab(e.path);
            else
                for (const e of sel.filter(x => !x.isDir))
                    root.openEntry(e);
        }
    }

    function openWith(paths: var, appId: string): void {
        backend.request("open", { paths: paths, app: appId }, { error: m => root.toast(m) });
    }

    // ───────────────────────── jobs and transfers ─────────────────────────

    function addJob(job: var): void {
        root.jobs = root.jobs.concat([job]);
    }

    function patchJob(id: int, changes: var): void {
        root.jobs = root.jobs.map(j => j.id === id ? Object.assign({}, j, changes) : j);
    }

    function dismissJob(id: int): void {
        root.jobs = root.jobs.filter(j => j.id !== id);
    }

    function finishJob(id: int, ok: bool, message: string): void {
        root.patchJob(id, { state: ok ? "done" : "error", message: message });
        if (ok) {
            const keep = id;
            Qt.callLater(() => doneTimer.add(keep));
        }
    }

    function startTransfer(mode: string, srcs: var, dest: string): void {
        if (srcs.length === 0)
            return;
        const label = mode === "copy" ? qsTr("Copying") : qsTr("Moving");
        const title = srcs.length === 1 ? qsTr("%1 “%2”").arg(label).arg(root.basename(srcs[0])) : qsTr("%1 %2 items").arg(label).arg(srcs.length);
        let jid = -1;
        jid = backend.request("transfer", { mode: mode, srcs: srcs, dest: dest }, {
            progress: m => root.patchJob(jid, { done: m.done, total: m.total, speed: m.speed, current: m.current }),
            conflict: m => {
                root.conflictQueue = root.conflictQueue.concat([{ job: jid, src: m.src, dst: m.dst, mismatch: m.mismatch === true }]);
                root.showNextConflict();
            },
            done: m => {
                const pairs = m.results ?? [];
                if (pairs.length > 0)
                    root.pushUndo({ kind: mode, pairs: pairs, replaced: m.replaced ?? [], label: mode === "copy" ? qsTr("copy") : qsTr("move") });
                if (m.cancelled)
                    root.finishJob(jid, false, qsTr("Cancelled"));
                else if (!m.ok)
                    root.finishJob(jid, false, (m.errors ?? []).join("; "));
                else
                    root.finishJob(jid, true, mode === "copy" ? qsTr("Copied") : qsTr("Moved"));
                root.reload(true);
                root.refreshSide();
            },
            error: msg => root.finishJob(jid, false, msg)
        });
        root.addJob({ id: jid, title: title, state: "running", done: 0, total: 0, speed: 0, current: "", icon: mode === "copy" ? "content_copy" : "drive_file_move" });
    }

    function showNextConflict(): void {
        if (root.dialogItem || root.conflictQueue.length === 0)
            return;
        const c = root.conflictQueue[0];
        root.openDialog(conflictDialog, { src: c.src, dst: c.dst, mismatch: c.mismatch, jobId: c.job });
    }

    function runSimple(op: string, payload: var, title: string, onOk: var): void {
        let jid = -1;
        jid = backend.request(op, payload, {
            progress: m => { if (m.total !== undefined) root.patchJob(jid, { done: m.done, total: m.total, current: m.current ?? "" }); },
            conflict: m => {
                root.conflictQueue = root.conflictQueue.concat([{ job: jid, src: m.src, dst: m.dst, mismatch: m.mismatch === true }]);
                root.showNextConflict();
            },
            done: m => {
                root.dismissJob(jid);
                if (m.cancelled) {
                    root.toast(qsTr("Cancelled"));
                } else {
                    if (m.ok === false && (m.errors ?? []).length > 0)
                        root.toast(m.errors.join("; "));
                    if (onOk)
                        onOk(m);
                }
                root.reload(true);
                root.refreshSide();
            },
            error: msg => {
                root.finishJob(jid, false, msg);
                root.reload(true);
            }
        });
        root.addJob({ id: jid, title: title, state: "running", done: 0, total: 0, speed: 0, current: "", icon: "sync" });
    }

    // ───────────────────────── file operations ─────────────────────────

    function copySelection(cut: bool): void {
        if (root.selCount === 0)
            return;
        root.clipPaths = root.selectionPaths;
        root.clipCut = cut;
        backend.request("clipSet", { paths: root.clipPaths, cut: cut }, null);
        root.toast(cut ? qsTr("Cut %1 — paste to move").arg(root.selCount) : qsTr("Copied %1").arg(root.selCount));
    }

    function paste(destDir = ""): void {
        const dest = destDir.length > 0 ? destDir : root.path;
        if (dest.startsWith("trash:"))
            return;
        backend.request("clipGet", {}, { done: m => {
            let paths = m.paths, cut = m.cut;
            if (paths.length === 0) {
                paths = root.clipPaths;
                cut = root.clipCut;
            }
            if (paths.length === 0) {
                root.toast(qsTr("Nothing to paste"));
                return;
            }
            root.startTransfer(cut ? "move" : "copy", paths, dest);
            if (cut) {
                root.clipPaths = [];
                root.clipCut = false;
            }
        } });
    }

    function trashSelection(): void {
        if (root.selCount === 0)
            return;
        const paths = root.selectionPaths;
        if (root.isTrash) {
            root.confirmDelete(paths);
            return;
        }
        root.runSimple("trash", { paths: paths }, qsTr("Moving to the Trash"), m => {
            if ((m.results ?? []).length > 0)
                root.pushUndo({ kind: "trash", pairs: m.results, label: qsTr("move to Trash") });
            root.toast(paths.length === 1 ? qsTr("Moved “%1” to the Trash").arg(root.basename(paths[0])) : qsTr("Moved %1 items to the Trash").arg(paths.length), (m.results ?? []).length > 0);
        });
    }

    function confirmDelete(paths: var): void {
        if (paths.length === 0)
            return;
        root.openDialog(promptDialog, {
            title: qsTr("Delete permanently?"),
            message: paths.length === 1 ? qsTr("“%1” will be deleted for good. This can’t be undone.").arg(root.basename(paths[0]))
                : qsTr("%1 items will be deleted for good. This can’t be undone.").arg(paths.length),
            input: false, danger: true, confirmText: qsTr("Delete"),
            onAcceptedFn: () => root.runSimple("delete", { paths: paths }, qsTr("Deleting"), null)
        });
    }

    function restoreSelection(): void {
        if (root.selCount === 0)
            return;
        root.runSimple("restore", { paths: root.selectionPaths }, qsTr("Restoring"), m => root.toast(qsTr("Restored")));
    }

    function emptyTrash(): void {
        root.openDialog(promptDialog, {
            title: qsTr("Empty the Trash?"), message: qsTr("Everything in the Trash will be deleted for good."),
            input: false, danger: true, confirmText: qsTr("Empty Trash"),
            onAcceptedFn: () => root.runSimple("emptyTrash", {}, qsTr("Emptying the Trash"), null)
        });
    }

    function beginRename(): void {
        if (root.selCount !== 1 || root.isTrash)
            return;
        root.renamingPath = root.selection[0].path;
    }

    function commitRename(path: string, text: string): void {
        root.renamingPath = "";
        root.forceActiveFocus();
        const name = text.trim();
        if (name.length === 0 || name === root.basename(path))
            return;
        backend.request("rename", { path: path, name: name }, {
            done: m => {
                root.pushUndo({ kind: "rename", pairs: [{ src: m.src, dst: m.dst }], label: qsTr("rename") });
                root.pendingReveal = { path: m.dst, rename: false };
                root.reload(true);
            },
            error: msg => root.toast(msg)
        });
    }

    function uniqueIn(dir: string, base: string): string {
        const have = new Set(root.entries.map(e => e.name));
        if (!have.has(base))
            return base;
        const dot = base.lastIndexOf(".");
        const stem = dot > 0 ? base.slice(0, dot) : base, ext = dot > 0 ? base.slice(dot) : "";
        for (let n = 2; ; ++n)
            if (!have.has(stem + " " + n + ext))
                return stem + " " + n + ext;
        return base;
    }

    function newFolder(): void {
        if (root.isTrash)
            return;
        const name = root.uniqueIn(root.path, qsTr("New Folder"));
        backend.request("mkdir", { dir: root.path, name: name }, {
            done: m => {
                root.pushUndo({ kind: "create", pairs: [{ dst: m.dst }], label: qsTr("new folder") });
                root.pendingReveal = { path: m.dst, rename: true };
                root.reload(true);
            },
            error: msg => root.toast(msg)
        });
    }

    function newFile(): void {
        if (root.isTrash)
            return;
        const name = root.uniqueIn(root.path, qsTr("New File.txt"));
        backend.request("newfile", { dir: root.path, name: name }, {
            done: m => {
                root.pushUndo({ kind: "create", pairs: [{ dst: m.dst }], label: qsTr("new file") });
                root.pendingReveal = { path: m.dst, rename: true };
                root.reload(true);
            },
            error: msg => root.toast(msg)
        });
    }

    function duplicateSelection(): void {
        if (root.selCount === 0 || root.isTrash)
            return;
        root.startTransfer("copy", root.selectionPaths.filter(p => root.dirname(p) === root.path), root.path);
    }

    function linkSelection(): void {
        for (const e of root.selection)
            backend.request("symlink", { target: e.path, dir: root.path }, { done: () => root.reload(true), error: msg => root.toast(msg) });
    }

    function compress(fmt: string, password = ""): void {
        if (root.selCount === 0)
            return;
        const paths = root.selectionPaths;
        root.runSimple("compress", { paths: paths, format: fmt, password: password }, qsTr("Compressing"), m => {
            root.pendingReveal = { path: m.dst, rename: false };
            root.toast(qsTr("Created “%1”").arg(root.basename(m.dst)));
        });
    }

    function compressEncrypted(fmt: string): void {
        root.promptPassword(qsTr("Protect with a password"), qsTr("Anyone opening the .%1 will need it. There is no way to recover it.").arg(fmt), qsTr("Compress"), pw => {
            if (pw.length > 0)
                root.compress(fmt, pw);
        });
    }

    function extract(here: bool): void {
        for (const e of root.selection.filter(x => x.kind === "archive"))
            root.extractOne(e, here, "");
    }

    function extractOne(e: var, here: bool, password: string): void {
        root.runSimple("extract", { path: e.path, here: here, password: password }, qsTr("Extracting “%1”").arg(e.name), m => {
            if (m.password) {
                root.promptPassword(qsTr("Password needed"),
                    m.wrong ? qsTr("That password did not work for “%1”.").arg(e.name) : qsTr("“%1” is protected.").arg(e.name),
                    qsTr("Extract"), pw => { if (pw.length > 0) root.extractOne(e, here, pw); });
                return;
            }
            if (m.ok === false)
                return;
            root.pendingReveal = { path: m.dst, rename: false };
            root.toast(qsTr("Extracted"));
        });
    }

    function copyPathText(): void {
        const paths = root.selCount > 0 ? root.selectionPaths : [root.path];
        Quickshell.execDetached(["wl-copy", "--", paths.join("\n")]);
        root.toast(qsTr("Path copied"));
    }

    function handleDrop(urls: var, folder: string, action: int): void {
        const paths = root.urlsToPaths(urls);
        const dest = folder.length > 0 ? folder : root.path;
        if (paths.length === 0 || root.isTrash && folder.length === 0)
            return;
        if (dest.startsWith("trash:")) {
            root.runSimple("trash", { paths: paths }, qsTr("Moving to the Trash"), null);
            return;
        }
        const copy = action === Qt.CopyAction;
        if (!copy && paths.every(p => root.dirname(p) === dest))
            return;
        root.startTransfer(copy ? "copy" : "move", paths, dest);
    }

    // ───────────────────────── undo ─────────────────────────

    function pushUndo(step: var): void {
        root.undoStack = root.undoStack.concat([step]).slice(-30);
    }

    function undo(): void {
        if (root.undoStack.length === 0) {
            root.toast(qsTr("Nothing to undo"));
            return;
        }
        const step = root.undoStack[root.undoStack.length - 1];
        root.undoStack = root.undoStack.slice(0, -1);
        const finish = () => {
            // Anything a "replace" moved to the Trash comes back last, once its place is free again
            const rep = step.replaced ?? [];
            const done = () => { root.reload(true); root.refreshSide(); root.toast(qsTr("Undid %1").arg(step.label)); };
            if (rep.length === 0)
                done();
            else
                backend.request("restore", { paths: rep.map(r => r.dst) }, { done: done, error: m => { done(); root.toast(m); } });
        };
        const fail = m => root.toast(m);
        if (step.kind === "trash") {
            backend.request("restore", { paths: step.pairs.map(p => p.dst) }, { done: finish, error: fail });
        } else if (step.kind === "rename") {
            const p = step.pairs[0];
            backend.request("rename", { path: p.dst, name: root.basename(p.src) }, { done: finish, error: fail });
        } else if (step.kind === "move") {
            // Put each item back where it came from, under the name it had
            let left = step.pairs.length;
            for (const p of step.pairs) {
                const names = {};
                names[p.dst] = root.basename(p.src);
                backend.request("transfer", { mode: "move", srcs: [p.dst], dest: root.dirname(p.src), names: names }, {
                    done: () => { if (--left === 0) finish(); }, error: fail
                });
            }
        } else if (step.kind === "copy" || step.kind === "create") {
            // The copies go to the Trash rather than being erased, in case they were worked on since
            backend.request("trash", { paths: step.pairs.map(p => p.dst) }, { done: finish, error: fail });
        }
    }

    // ───────────────────────── properties and dialogs ─────────────────────────

    property var dialogItem: null

    function openDialog(component: Component, props: var): void {
        root.closeDialog(true);
        const initial = {};
        for (const k in props)
            if (k !== "onAcceptedFn" && k !== "jobId")
                initial[k] = props[k];
        const it = component.createObject(dialogHost, initial);
        if (!it)
            return;
        root.dialogItem = it;
        if (props.onAcceptedFn && it.accepted)
            it.accepted.connect(text => { root.closeDialog(); props.onAcceptedFn(text); });
        // A conflict dialog is closed only by answering it
        it.closed.connect(() => { if (props.jobId === undefined) root.closeDialog(); });
        if (it.resolved)
            it.resolved.connect((action, all) => {
                const c = root.conflictQueue[0];
                root.conflictQueue = root.conflictQueue.slice(1);
                backend.resolve(c.job, action, all, "");
                root.closeDialog();
            });
        if (it.chosen)
            it.chosen.connect((appId, makeDefault) => {
                if (makeDefault)
                    backend.request("setDefaultApp", { app: appId, mime: props.mime }, null);
                root.openWith(props.paths, appId);
                root.closeDialog();
            });
        if (it.saved)
            it.saved.connect(() => root.loadActions());
        if (it.changed)
            it.changed.connect(() => root.reload(true));
        it.forceActiveFocus();
        // A menu closing, a finished job or a row losing its delegate can hand focus back to the
        // list in the same tick; take it again once those have settled, unless the dialog already
        // put focus on one of its own fields.
        Qt.callLater(() => {
            if (root.dialogItem === it && !it.activeFocus)
                it.forceActiveFocus();
        });
    }

    function closeDialog(quiet = false): void {
        if (root.dialogItem) {
            root.dialogItem.destroy();
            root.dialogItem = null;
        }
        if (quiet)
            return;
        root.forceActiveFocus();
        Qt.callLater(root.showNextConflict);
    }

    function previewInfo(e: var): string {
        const parts = [e.mime, root.bytes(e.size), Qt.formatDateTime(new Date(e.mtime * 1000), "d MMM yyyy, HH:mm")];
        return parts.filter(x => x).join("  ·  ");
    }

    function openPreview(e: var): void {
        root.thumbNeeded(e);
        root.openDialog(previewComp, { entry: e, info: root.previewInfo(e), thumbs: root.thumbs });
        if (root.dialogItem && root.dialogItem.stepRequested) {
            root.dialogItem.thumbs = Qt.binding(() => root.thumbs);
            root.dialogItem.stepRequested.connect(dir => root.stepPreview(dir));
        }
    }

    /// Left/right inside the preview moves through the files of the folder
    function stepPreview(dir: int): void {
        const files = root.shown.filter(x => !x.isDir);
        if (files.length === 0 || !root.dialogItem)
            return;
        const cur = files.findIndex(x => x.path === root.dialogItem.entry.path);
        const next = files[(cur + dir + files.length) % files.length];
        root.setSelection([next.path]);
        root.thumbNeeded(next);
        root.dialogItem.entry = next;
        root.dialogItem.info = root.previewInfo(next);
    }

    function showProperties(): void {
        const paths = root.selCount > 0 ? root.selectionPaths : [root.path];
        root.openDialog(propertiesDialog, { paths: paths, backend: backend });
    }

    function newFolderPrompt(): void {
        root.newFolder();
    }

    function bulkRename(): void {
        if (root.selCount < 2)
            return;
        root.openDialog(bulkDialog, { entries: root.selection });
    }

    function openWithDialog(): void {
        if (root.selCount < 1)
            return;
        const e = root.selection[0];
        root.openDialog(openWithDialogComp, { backend: backend, mime: e.mime, fileName: e.name, paths: root.selectionPaths });
    }

    function openActionsEditor(): void {
        root.openDialog(actionsDialog, { backend: backend });
    }

    // ───────────────────────── bookmarks and devices ─────────────────────────

    function addBookmark(p: string): void {
        backend.request("bookmark", { path: p }, { done: () => root.refreshSide() });
    }

    function removeBookmark(p: string): void {
        backend.request("bookmark", { path: p, remove: true }, { done: () => root.refreshSide() });
    }

    function mountDevice(dev: var): void {
        backend.request("mount", { dev: dev.dev }, {
            done: m => { root.refreshSide(); if (m.mount) root.go(m.mount); },
            error: msg => root.toast(msg)
        });
    }

    function unmountDevice(dev: var): void {
        backend.request("unmount", { dev: dev.dev, eject: dev.removable }, {
            done: () => { root.refreshSide(); root.toast(qsTr("“%1” can be removed").arg(dev.name)); },
            error: msg => root.toast(msg)
        });
    }

    // ───────────────────────── search ─────────────────────────

    function setFilter(spec: string): void {
        const [kind, val] = spec.split(":");
        if (kind === "kind") root.searchKind = val;
        else if (kind === "days") root.searchDays = Number(val);
        else if (kind === "size") root.searchMinMb = Number(val);
        else if (kind === "content") root.searchContent = !root.searchContent;
        root.runSearch();
    }

    function filterMenu(which: string): var {
        if (which === "kind") {
            return [["", qsTr("Any type")], ["image", qsTr("Images")], ["video", qsTr("Videos")], ["audio", qsTr("Audio")],
                ["document", qsTr("Documents")], ["archive", qsTr("Archives")], ["code", qsTr("Code")], ["folder", qsTr("Folders")]]
                .map(([v, t]) => ({ id: "sf:kind:" + v, text: t, checked: root.searchKind === v ? true : undefined }));
        }
        if (which === "days") {
            return [[0, qsTr("Any time")], [1, qsTr("Last 24 hours")], [7, qsTr("Last 7 days")], [30, qsTr("Last 30 days")], [365, qsTr("Last year")]]
                .map(([v, t]) => ({ id: "sf:days:" + v, text: t, checked: root.searchDays === v ? true : undefined }));
        }
        return [[0, qsTr("Any size")], [10, qsTr("Over 10 MB")], [100, qsTr("Over 100 MB")], [1000, qsTr("Over 1 GB")]]
            .map(([v, t]) => ({ id: "sf:size:" + v, text: t, checked: root.searchMinMb === v ? true : undefined }));
    }

    function closeSearch(): void {
        root.searchOpen = false;
        root.searchKind = "";
        root.searchDays = 0;
        root.searchMinMb = 0;
        root.searchContent = false;
        root.query = "";
        root.searchResults = [];
        if (root.searchJob >= 0)
            backend.cancel(root.searchJob);
        root.searchRunning = false;
        root.forceActiveFocus();
    }

    function runSearch(): void {
        if (root.searchJob >= 0)
            backend.cancel(root.searchJob);
        const q = root.query.trim();
        root.searchResults = [];
        if (!root.deepActive || (q.length === 0 && !root.hasFilters) || root.isTrash || root.isVirtual) {
            root.searchRunning = false;
            return;
        }
        root.searchRunning = true;
        const mine = ++root.listSerial;
        let jid = -1;
        const add = list => {
            if (jid !== root.searchJob)
                return;
            root.searchResults = root.searchResults.concat(list);
        };
        jid = backend.request("search", { path: root.path, query: q, hidden: root.showHidden, kind: root.searchKind, days: root.searchDays,
            minMb: root.searchMinMb, content: root.searchContent }, {
            partial: m => add(m.entries),
            done: m => {
                add(m.entries ?? []);
                if (jid === root.searchJob)
                    root.searchRunning = false;
            },
            error: () => { root.searchRunning = false; }
        });
        root.searchJob = jid;
    }

    // ───────────────────────── thumbnails ─────────────────────────

    /// Icon-pack names for an entry: special folders by their folder, else the file type's own names
    function iconNamesFor(e: var): var {
        if (e.isDir) {
            const special = { Desktop: "user-desktop", Documents: "folder-documents", Downloads: "folder-download", Music: "folder-music", Pictures: "folder-pictures", Videos: "folder-videos", Templates: "folder-templates", Public: "folder-public" };
            if (e.path === backend.home)
                return ["user-home", "folder-blue", "folder"];
            const col = root.folderColors[e.path];
            if (col)
                return ["folder-" + col, "folder-blue", "folder"];
            if (root.dirname(e.path) === backend.home && special[e.name])
                return [special[e.name], "folder-blue", "folder"];
            return ["folder-blue", "folder"];
        }
        return root.iconMap[e.mime] ?? [];
    }

    function thumbNeeded(e: var): void {
        const key = e.path + "|" + e.mtime;
        const direct = e.kind === "image" && e.size < 1500000 && ["image/jpeg", "image/png", "image/webp", "image/gif", "image/bmp"].indexOf(e.mime) >= 0;
        if (e.isDir || direct || root.thumbable.indexOf(e.mime) < 0 || root.thumbs[key] !== undefined || root.thumbQueue.some(q => q.path === e.path))
            return;
        root.thumbQueue = root.thumbQueue.concat([e]);
        root.pumpThumbs();
    }

    function pumpThumbs(): void {
        while (root.thumbsBusy < 4 && root.thumbQueue.length > 0) {
            const e = root.thumbQueue[root.thumbQueue.length - 1];
            root.thumbQueue = root.thumbQueue.slice(0, -1);
            root.thumbsBusy++;
            backend.request("thumb", { path: e.path, mime: e.mime, size: Math.round(root.cfg.fmZoom * 2) }, {
                done: m => {
                    const t = Object.assign({}, root.thumbs);
                    t[e.path + "|" + e.mtime] = m.thumb || "";
                    root.thumbs = t;
                    root.thumbsBusy--;
                    root.pumpThumbs();
                },
                error: () => { root.thumbsBusy--; root.pumpThumbs(); }
            });
        }
    }

    // ───────────────────────── custom actions ─────────────────────────

    function runAction(act: var): void {
        const paths = root.selCount > 0 ? root.selectionPaths : [];
        backend.request("runAction", { actionId: act.id, paths: paths, dir: root.isTrash ? backend.home : root.path }, {
            done: m => {
                if (!m.ok)
                    root.toast(qsTr("%1 failed (exit %2)%3").arg(m.name).arg(m.code).arg(m.stderr ? ": " + m.stderr.split("\n").pop() : ""));
                else
                    root.toast(m.background ? qsTr("%1 is running").arg(m.name) : qsTr("%1 done").arg(m.name));
                root.reload(true);
            },
            error: msg => root.toast(msg)
        });
    }

    function keyString(ev: var): string {
        const mods = [];
        if (ev.modifiers & Qt.ControlModifier) mods.push("Ctrl");
        if (ev.modifiers & Qt.AltModifier) mods.push("Alt");
        if (ev.modifiers & Qt.ShiftModifier) mods.push("Shift");
        if (ev.modifiers & Qt.MetaModifier) mods.push("Meta");
        let k = "";
        if (ev.key >= Qt.Key_F1 && ev.key <= Qt.Key_F12)
            k = "F" + (ev.key - Qt.Key_F1 + 1);
        else if (ev.key >= Qt.Key_A && ev.key <= Qt.Key_Z)
            k = String.fromCharCode(ev.key);
        else if (ev.key >= Qt.Key_0 && ev.key <= Qt.Key_9)
            k = String.fromCharCode(ev.key);
        else
            return "";
        return mods.concat([k]).join("+");
    }

    function tryActionShortcut(ev: var): bool {
        const ks = root.keyString(ev);
        if (ks.length === 0)
            return false;
        const act = root.customActions.find(a => a.shortcut === ks);
        if (!act)
            return false;
        const paths = root.selCount > 0 ? root.selectionPaths : [];
        backend.request("actions", { paths: paths, dir: root.isTrash ? "" : root.path }, { done: m => {
            if (m.actions.some(a => a.id === act.id))
                root.runAction(act);
        } });
        return true;
    }

    // ───────────────────────── context menus ─────────────────────────

    function actionItems(actions: var): var {
        const out = [];
        const groups = ({});
        for (const a of actions) {
            const item = { id: "uca:" + a.id, text: a.name, icon: "bolt", themeIcon: a.icon, shortcut: a.shortcut, act: a };
            if (a.submenu.length > 0) {
                if (!groups[a.submenu]) {
                    groups[a.submenu] = { text: a.submenu, icon: "bolt", themeIcon: a.icon, submenu: [] };
                    out.push(groups[a.submenu]);
                }
                groups[a.submenu].submenu.push(item);
            } else {
                out.push(item);
            }
        }
        return out;
    }

    function showMenu(index: int, vx: real, vy: real, host: Item): void {
        const p = host.mapToItem(root, vx, vy);
        const entry = index >= 0 ? root.shown[index] : null;
        const paths = entry ? root.selectionPaths : [];
        let actions = [], apps = [], pending = 2;
        const build = () => {
            if (--pending > 0)
                return;
            menu.popup(root.buildMenu(entry, actions, apps), p.x, p.y);
        };
        backend.request("actions", { paths: paths, dir: entry || root.isTrash ? "" : root.path }, { done: m => { actions = m.actions; build(); }, error: () => build() });
        if (entry && !entry.isDir && !root.isTrash && root.selCount === 1)
            backend.request("apps", { mime: entry.mime }, { done: m => { apps = m.apps; build(); }, error: () => build() });
        else
            build();
    }

    function buildMenu(entry: var, actions: var, apps: var): var {
        const sep = { separator: true };
        const m = [];
        const n = root.selCount;
        if (root.isTrash) {
            if (entry) {
                m.push({ id: "restore", text: qsTr("Restore"), icon: "restore_from_trash" });
                m.push({ id: "delete", text: qsTr("Delete permanently"), icon: "delete_forever", danger: true, shortcut: "Shift+Del" });
                m.push(sep);
                m.push({ id: "properties", text: qsTr("Properties"), icon: "info" });
            } else {
                m.push({ id: "emptyTrash", text: qsTr("Empty Trash"), icon: "delete_forever", danger: true, disabled: root.entries.length === 0 });
                m.push({ id: "selectAll", text: qsTr("Select all"), icon: "select_all", shortcut: "Ctrl+A" });
            }
            return m;
        }
        if (entry) {
            const single = n === 1;
            if (single && entry.isDir) {
                m.push({ id: "open", text: qsTr("Open"), icon: "folder_open", shortcut: "Enter" });
                m.push({ id: "newTab", text: qsTr("Open in new tab"), icon: "tab_new_right", shortcut: "Ctrl+T" });
            } else {
                m.push({ id: "open", text: qsTr("Open"), icon: "open_in_new", shortcut: "Enter" });
            }
            if (single && !entry.isDir) {
                const sub = apps.map(a => ({ id: "app:" + a.id, text: a.name + (a.default ? qsTr("  (default)") : ""), icon: "" }));
                if (sub.length > 0)
                    sub.push(sep);
                sub.push({ id: "openWith", text: qsTr("Other application…"), icon: "" });
                m.push({ text: qsTr("Open with"), icon: "apps", submenu: sub });
            }
            if (root.phones.length > 0 && root.selectionPaths.length > 0 && !root.isTrash) {
                m.push({ text: qsTr("Send to phone"), icon: "send_to_mobile",
                    submenu: root.phones.map(d => ({ id: "kdcSend:" + d.id, text: d.name, icon: "smartphone" })) });
            }
            if (root.selection.length > 0 && root.selection.every(e => !e.isDir) && !root.isTrash)
                m.push({ id: "quickShare", text: qsTr("Share with Quick Share"), icon: "send_to_mobile" });
            m.push(sep);
            m.push({ id: "cut", text: qsTr("Cut"), icon: "content_cut", shortcut: "Ctrl+X" });
            m.push({ id: "copy", text: qsTr("Copy"), icon: "content_copy", shortcut: "Ctrl+C" });
            if (single && entry.isDir)
                m.push({ id: "pasteInto", text: qsTr("Paste into folder"), icon: "content_paste", shortcut: "Ctrl+V" });
            m.push(sep);
            if (single)
                m.push({ id: "rename", text: qsTr("Rename"), icon: "edit", shortcut: "F2" });
            else
                m.push({ id: "bulkRename", text: qsTr("Rename %1 items…").arg(n), icon: "edit_note" });
            m.push({ id: "trash", text: qsTr("Move to Trash"), icon: "delete", shortcut: "Del", danger: true });
            m.push(sep);
            const fmts = ["zip", "7z", "tar.gz", "tar.xz", "tar.zst"];
            const csub = fmts.map(f => ({ id: "compress:" + f, text: "." + f, icon: "" }));
            csub.push(sep);
            csub.push({ id: "compress:zip:enc", text: qsTr(".zip with a password…"), icon: "lock" });
            csub.push({ id: "compress:7z:enc", text: qsTr(".7z with a password…"), icon: "lock" });
            m.push({ text: qsTr("Compress"), icon: "folder_zip", submenu: csub });
            if (root.selection.some(e => e.kind === "archive")) {
                m.push({ id: "extractHere", text: qsTr("Extract here"), icon: "unarchive" });
                m.push({ id: "extractTo", text: qsTr("Extract to folder"), icon: "drive_folder_upload" });
            }

            // Everything less common sits one level down so the menu stays short
            const more = [];
            more.push({ id: "copyPath", text: qsTr("Copy path"), icon: "link", shortcut: "Ctrl+Shift+C" });
            more.push({ id: "duplicate", text: qsTr("Duplicate"), icon: "difference" });
            more.push({ id: "link", text: qsTr("Create link"), icon: "add_link" });
            if (root.searchMode)
                more.push({ id: "showInFolder", text: qsTr("Show in folder"), icon: "folder_open" });
            more.push(sep);
            more.push({ id: "copyTo", text: qsTr("Copy to…"), icon: "file_copy" });
            more.push({ id: "moveTo", text: qsTr("Move to…"), icon: "drive_file_move" });
            if (root.peerReady) {
                more.push({ id: "toPaneCopy", text: qsTr("Copy to the other pane"), icon: "keyboard_double_arrow_right", shortcut: "Shift+F5" });
                more.push({ id: "toPaneMove", text: qsTr("Move to the other pane"), icon: "drive_file_move", shortcut: "Shift+F6" });
            }
            const allStarred = root.selectionPaths.every(p => root.starredSet[p]);
            more.push(sep);
            more.push({ id: "star", text: allStarred ? qsTr("Remove from Starred") : qsTr("Add to Starred"), icon: allStarred ? "star_off" : "star" });
            if (single && entry.isDir)
                more.push({ id: "bookmark", text: root.bookmarks.some(b => b.path === entry.path) ? qsTr("Remove bookmark") : qsTr("Add to bookmarks"), icon: "bookmark_add", shortcut: "Ctrl+D" });
            if (single && entry.kind === "image" && entry.mime !== "image/svg+xml")
                more.push({ id: "wallpaper", text: qsTr("Set as wallpaper"), icon: "wallpaper" });
            if (single && !entry.isDir)
                more.push({ id: "checksums", text: qsTr("Checksums…"), icon: "fingerprint" });
            if (single && entry.isDir) {
                more.push(sep);
                more.push({ id: "terminal", text: qsTr("Open in terminal"), icon: "terminal", shortcut: "F4" });
                more.push({ id: "newWindow", text: qsTr("Open in new window"), icon: "open_in_new", shortcut: "Ctrl+Alt+N" });
                more.push({ id: "diskUsage", text: qsTr("Disk usage…"), icon: "pie_chart" });
                more.push({ id: "duplicates", text: qsTr("Find duplicate files…"), icon: "content_copy" });
            }
            if (n === 2 && root.selection.every(e => e.isDir))
                more.push({ id: "compareSel", text: qsTr("Compare these folders…"), icon: "compare_arrows" });
            m.push({ text: qsTr("More"), icon: "more_horiz", submenu: more });

            if (root.selection.every(e => e.isDir)) {
                const colors = [["red", qsTr("Red")], ["orange", qsTr("Orange")], ["yellow", qsTr("Yellow")], ["green", qsTr("Green")], ["teal", qsTr("Teal")],
                    ["cyan", qsTr("Cyan")], ["blue", qsTr("Blue")], ["violet", qsTr("Violet")], ["pink", qsTr("Pink")], ["brown", qsTr("Brown")], ["grey", qsTr("Grey")]];
                const cs = colors.map(([c, t]) => ({ id: "fcolor:" + c, text: t, icon: "", checked: root.selection.every(e => root.folderColors[e.path] === c) ? true : undefined }));
                cs.push(sep);
                cs.push({ id: "fcolor:", text: qsTr("Default"), icon: "" });
                m.push({ text: qsTr("Folder colour"), icon: "palette", submenu: cs });
            }
            if (root.selection.some(e => e.kind === "image")) {
                const img = [];
                for (const pct of [75, 50, 25])
                    img.push({ id: "img:resize:" + pct, text: qsTr("Resize to %1%").arg(pct), icon: "" });
                img.push(sep);
                for (const f of ["png", "jpg", "webp"])
                    img.push({ id: "img:convert:" + f, text: qsTr("Convert to %1").arg(f.toUpperCase()), icon: "" });
                img.push(sep);
                img.push({ id: "img:rotate:90", text: qsTr("Rotate right"), icon: "" });
                img.push({ id: "img:rotate:-90", text: qsTr("Rotate left"), icon: "" });
                m.push({ text: qsTr("Image tools"), icon: "image", submenu: img });
            }
        } else {
            m.push({ id: "newFolder", text: qsTr("New folder"), icon: "create_new_folder", shortcut: "Ctrl+Shift+N", disabled: !root.writable });
            m.push({ id: "newFile", text: qsTr("New empty file"), icon: "note_add", disabled: !root.writable });
            m.push(sep);
            m.push({ id: "paste", text: qsTr("Paste"), icon: "content_paste", shortcut: "Ctrl+V", disabled: !root.writable });
            m.push({ id: "selectAll", text: qsTr("Select all"), icon: "select_all", shortcut: "Ctrl+A" });
            m.push(sep);
            m.push({ id: "terminal", text: qsTr("Open terminal here"), icon: "terminal", shortcut: "F4" });
            m.push({ text: qsTr("Sort by"), icon: "sort", submenu: root.sortItems() });
            m.push({ id: "view", text: root.viewMode === "grid" ? qsTr("List view") : qsTr("Icon view"), icon: root.viewMode === "grid" ? "view_list" : "grid_view" });
            m.push({ id: "hidden", text: qsTr("Show hidden files"), checked: root.showHidden, shortcut: "Ctrl+H" });
            const more = [];
            more.push({ id: "selectPattern", text: qsTr("Select by pattern…"), icon: "filter_alt", shortcut: "Ctrl+S" });
            more.push({ id: "invertSel", text: qsTr("Invert selection"), icon: "flip", shortcut: "Ctrl+I" });
            more.push(sep);
            more.push({ id: "copyPath", text: qsTr("Copy folder path"), icon: "link" });
            more.push({ id: "bookmark", text: root.bookmarks.some(b => b.path === root.path) ? qsTr("Remove bookmark") : qsTr("Bookmark this folder"), icon: "bookmark_add", shortcut: "Ctrl+D" });
            if (root.viewPref)
                more.push({ id: "forgetView", text: qsTr("Use the default view here"), icon: "restart_alt" });
            m.push({ text: qsTr("More"), icon: "more_horiz", submenu: more });
        }
        if (actions.length > 0) {
            m.push(sep);
            for (const it of root.actionItems(actions))
                m.push(it);
        }
        m.push(sep);
        m.push({ id: "properties", text: qsTr("Properties"), icon: "info", shortcut: "Alt+Enter" });
        return m;
    }

    function sortItems(): var {
        const items = [["name", qsTr("Name")], ["size", qsTr("Size")], ["mtime", qsTr("Modified")], ["type", qsTr("Type")]]
            .map(([k, t]) => ({ id: "sort:" + k, text: t, checked: root.sortKey === k }));
        items.push({ separator: true });
        items.push({ id: "sortDir", text: root.sortDesc ? qsTr("Descending") : qsTr("Ascending"), icon: root.sortDesc ? "arrow_downward" : "arrow_upward" });
        return items;
    }

    function moreMenu(): var {
        const m = [];
        m.push({ id: "newFolder", text: qsTr("New folder"), icon: "create_new_folder", shortcut: "Ctrl+Shift+N", disabled: root.isTrash });
        m.push({ id: "newTab", text: qsTr("New tab"), icon: "tab_new_right", shortcut: "Ctrl+T" });
        m.push({ id: "split", text: qsTr("Split view"), icon: "vertical_split", checked: root.split, shortcut: "F3" });
        if (root.peerReady)
            m.push({ id: "comparePanes", text: qsTr("Compare the two panes"), icon: "compare_arrows" });
        m.push({ separator: true });
        m.push({ id: "hidden", text: qsTr("Show hidden files"), checked: root.showHidden, shortcut: "Ctrl+H" });
        m.push({ text: qsTr("Sort by"), icon: "sort", submenu: root.sortItems() });
        if (root.viewMode === "grid") {
            m.push({ id: "zoomIn", text: qsTr("Larger icons"), icon: "zoom_in", shortcut: "Ctrl++" });
            m.push({ id: "zoomOut", text: qsTr("Smaller icons"), icon: "zoom_out", shortcut: "Ctrl+-" });
        }
        m.push({ separator: true });
        m.push({ id: "bookmark", text: qsTr("Bookmark this folder"), icon: "bookmark_add", shortcut: "Ctrl+D", disabled: root.isTrash });
        m.push({ id: "connect", text: qsTr("Connect to server…"), icon: "lan" });
        m.push({ separator: true });
        m.push({ id: "selectPattern", text: qsTr("Select by pattern…"), icon: "filter_alt", shortcut: "Ctrl+S" });
        m.push({ id: "invertSel", text: qsTr("Invert selection"), icon: "flip", shortcut: "Ctrl+I" });
        m.push({ id: "diskUsageHere", text: qsTr("Disk usage of this folder…"), icon: "pie_chart", disabled: root.isVirtual || root.isTrash });
        m.push({ id: "duplicates", text: qsTr("Find duplicate files…"), icon: "content_copy", disabled: root.isVirtual || root.isTrash });
        m.push({ id: "folderSizes", text: qsTr("Show folder sizes"), icon: "straighten", checked: root.cfg.fmFolderSizes });
        m.push({ id: "terminal", text: qsTr("Open terminal here"), icon: "terminal", shortcut: "F4" });
        m.push({ id: "newWindow", text: qsTr("New window"), icon: "open_in_new", shortcut: "Ctrl+Alt+N" });
        m.push({ id: "compareHere", text: qsTr("Compare with another folder…"), icon: "compare_arrows", disabled: root.isVirtual || root.isTrash });
        m.push({ separator: true });
        if (root.viewPref)
            m.push({ id: "forgetView", text: qsTr("Use the default view here"), icon: "restart_alt" });
        m.push({ id: "actionsEditor", text: qsTr("Custom actions…"), icon: "bolt" });
        m.push({ id: "shortcuts", text: qsTr("Keyboard shortcuts"), icon: "keyboard" });
        return m;
    }

    function sideMenu(item: var): var {
        const m = [];
        if (item.kind === "trash") {
            m.push({ id: "emptyTrash", text: qsTr("Empty Trash"), icon: "delete_forever", danger: true });
            return m;
        }
        if (item.kind !== "phone" && item.path.length > 0 && item.kind !== "connect") {
            m.push({ id: "open", text: qsTr("Open"), icon: "folder_open" });
            m.push({ id: "newTab", text: qsTr("Open in new tab"), icon: "tab_new_right" });
        }
        if (item.kind === "bookmark")
            m.push({ id: "removeBookmark", text: qsTr("Remove bookmark"), icon: "bookmark_remove" });
        if (item.kind === "net") {
            if (item.mount.mounted === false) {
                m.push({ id: "netMount", text: qsTr("Connect"), icon: "link" });
                return m;
            }
            m.push({ id: "open", text: qsTr("Open"), icon: "folder_open" });
            m.push({ id: "netUnmount", text: qsTr("Disconnect"), icon: "eject" });
            return m;
        }
        if (item.kind === "connect")
            return [{ id: "connect", text: qsTr("Connect to server…"), icon: "add_link" }];
        if (item.kind === "phone") {
            m.push({ id: "kdcBrowse", text: qsTr("Browse files"), icon: "folder_open" });
            m.push({ id: "kdcPing", text: qsTr("Send a ping"), icon: "notifications_active" });
            return m;
        }
        if (item.kind === "device") {
            m.push(item.path.length > 0 ? { id: "unmount", text: qsTr("Unmount"), icon: "eject" } : { id: "mount", text: qsTr("Mount"), icon: "play_circle" });
        }
        return m;
    }

    function onMenu(item: var, sideItem: var): void {
        const id = String(item.id ?? "");
        if (id.startsWith("uca:")) {
            root.runAction(item.act);
        } else if (id.startsWith("app:")) {
            root.openWith(root.selectionPaths, id.slice(4));
        } else if (id.startsWith("fcolor:")) {
            root.setFolderColor(root.selectionPaths, id.slice(7));
        } else if (id.startsWith("img:")) {
            const [, tool, arg] = id.split(":");
            root.imageTool(tool, tool === "resize" ? { percent: Number(arg) } : (tool === "convert" ? { format: arg } : { degrees: Number(arg) }));
        } else if (id.startsWith("sf:")) {
            root.setFilter(id.slice(3));
        } else if (id.startsWith("kdcSend:")) {
            const dev = root.phones.find(d => d.id === id.slice(8));
            if (dev)
                root.sendToPhone(dev, root.selectionPaths);
        } else if (id.startsWith("compress:")) {
            const fmt = id.slice(9);
            if (fmt.endsWith(":enc"))
                root.compressEncrypted(fmt.slice(0, -4));
            else
                root.compress(fmt);
        } else if (id.startsWith("sort:")) {
            root.rememberView({ sortKey: id.slice(5) });
        } else {
            root.dispatch(id, sideItem);
        }
    }

    function dispatch(id: string, side: var): void {
        const target = side ?? null;
        switch (id) {
        case "open": target ? root.go(target.path) : root.openSelection(); break;
        case "newTab": target ? root.newTab(target.path) : (root.selCount === 1 && root.selection[0].isDir ? root.newTab(root.selection[0].path) : root.newTab()); break;
        case "openWith": root.openWithDialog(); break;
        case "cut": root.copySelection(true); break;
        case "copy": root.copySelection(false); break;
        case "paste": root.paste(); break;
        case "pasteInto": root.paste(root.selection[0].path); break;
        case "copyPath": root.copyPathText(); break;
        case "quickShare": QuickShareService.stage(root.selectionPaths); root.toast(qsTr("Pick a phone on the island")); break;
        case "rename": root.beginRename(); break;
        case "bulkRename": root.bulkRename(); break;
        case "duplicate": root.duplicateSelection(); break;
        case "link": root.linkSelection(); break;
        case "trash": root.trashSelection(); break;
        case "delete": root.confirmDelete(root.selectionPaths); break;
        case "restore": root.restoreSelection(); break;
        case "emptyTrash": root.emptyTrash(); break;
        case "extractHere": root.extract(true); break;
        case "extractTo": root.extract(false); break;
        case "bookmark": {
            const p = root.selCount === 1 && root.selection[0].isDir ? root.selection[0].path : root.path;
            root.bookmarks.some(b => b.path === p) ? root.removeBookmark(p) : root.addBookmark(p);
            break;
        }
        case "removeBookmark": root.removeBookmark(target.path); break;
        case "star": root.toggleStar(root.selectionPaths); break;
        case "connect": root.connectServer(); break;
        case "forgetView": root.rememberView(null); break;
        case "netMount": root.mountNet(target.mount.uri); break;
        case "netUnmount": root.unmountNet(target.mount); break;
        case "kdcBrowse": root.openPhone(target.phone); break;
        case "kdcPing": backend.request("kdc_ping", { device: target.phone.id }, {}); root.toast(qsTr("Pinged %1").arg(target.phone.name)); break;
        case "mount": root.mountDevice(target.dev); break;
        case "unmount": root.unmountDevice(target.dev); break;
        case "newFolder": root.newFolder(); break;
        case "newFile": root.newFile(); break;
        case "selectAll": root.selectAll(); break;
        case "selectPattern": root.selectPatternPrompt(); break;
        case "toPaneCopy": root.transferToPeer("copy"); break;
        case "toPaneMove": root.transferToPeer("move"); break;
        case "split": root.splitToggleRequested(); break;
        case "comparePanes": root.compareFolders(root.path, root.peer.path); break;
        case "invertSel": root.invertSelection(); break;
        case "showInFolder": root.showInFolder(root.selection[0]); break;
        case "checksums": root.showChecksums(root.selection[0]); break;
        case "diskUsage": root.showDiskUsage(root.selCount === 1 && root.selection[0].isDir ? root.selection[0].path : root.path); break;
        case "diskUsageHere": root.showDiskUsage(root.path); break;
        case "compareSel": root.compareFolders(root.selection[0].path, root.selection[1].path); break;
        case "compareHere": root.comparePrompt(); break;
        case "hidden": root.cfg.fmHidden = !root.cfg.fmHidden; break;
        case "sortDir": root.rememberView({ sortDesc: !root.sortDesc }); break;
        case "view": root.rememberView({ view: root.viewMode === "grid" ? "list" : "grid" }); break;
        case "zoomIn": root.zoom(1); break;
        case "zoomOut": root.zoom(-1); break;
        case "properties": root.showProperties(); break;
        case "actionsEditor": root.openActionsEditor(); break;
        case "shortcuts": root.openDialog(helpDialog, {}); break;
        case "terminal": root.openTerminal(); break;
        case "newWindow": root.openNewWindow(); break;
        case "wallpaper": if (root.selCount === 1) root.setWallpaper(root.selection[0]); break;
        case "copyTo": root.pickDestination("copy"); break;
        case "moveTo": root.pickDestination("move"); break;
        case "duplicates": root.findDuplicates(); break;
        case "folderSizes": root.cfg.fmFolderSizes = !root.cfg.fmFolderSizes; break;
        }
    }

    function zoom(dir: int): void {
        root.cfg.fmZoom = Math.max(56, Math.min(200, root.cfg.fmZoom + dir * 16));
    }

    // ───────────────────────── keyboard ─────────────────────────

    // Mouse side buttons step through the tab's history, like the toolbar arrows
    TapHandler {
        acceptedButtons: Qt.BackButton
        onTapped: root.goBack()
    }
    TapHandler {
        acceptedButtons: Qt.ForwardButton
        onTapped: root.goForward()
    }

    Keys.onPressed: ev => {
        const ctrl = ev.modifiers & Qt.ControlModifier, alt = ev.modifiers & Qt.AltModifier, shift = ev.modifiers & Qt.ShiftModifier;
        ev.accepted = true;
        switch (ev.key) {
        case Qt.Key_Up: alt ? root.goUp() : root.moveCursor(root.viewMode === "grid" ? -(gridView.columns) : -1, ev.modifiers); break;
        case Qt.Key_Down: root.moveCursor(root.viewMode === "grid" ? gridView.columns : 1, ev.modifiers); break;
        case Qt.Key_Left: alt ? root.goBack() : root.moveCursor(root.viewMode === "grid" ? -1 : 0, ev.modifiers); break;
        case Qt.Key_Right: alt ? root.goForward() : root.moveCursor(root.viewMode === "grid" ? 1 : 0, ev.modifiers); break;
        case Qt.Key_Home: root.moveCursor(-root.shown.length, ev.modifiers); break;
        case Qt.Key_End: root.moveCursor(root.shown.length, ev.modifiers); break;
        case Qt.Key_PageUp: root.moveCursor(-12, ev.modifiers); break;
        case Qt.Key_PageDown: root.moveCursor(12, ev.modifiers); break;
        case Qt.Key_Return:
        case Qt.Key_Enter: alt ? root.showProperties() : root.openSelection(); break;
        case Qt.Key_Backspace: if (root.typeBuffer.length > 0) root.typeBackspace(); break;
        case Qt.Key_Delete: shift ? root.confirmDelete(root.selectionPaths) : root.trashSelection(); break;
        case Qt.Key_F2: root.beginRename(); break;
        case Qt.Key_F5: shift ? root.transferToPeer("copy") : root.reload(true); break;
        case Qt.Key_F6: root.transferToPeer("move"); break;
        case Qt.Key_F3: root.splitToggleRequested(); break;
        case Qt.Key_F4: root.openTerminal(); break;
        case Qt.Key_Menu: root.showMenuAtCursor(); break;
        case Qt.Key_F10: if (shift) root.showMenuAtCursor(); else ev.accepted = false; break;
        case Qt.Key_R: ctrl ? root.reload(true) : root.typeKey(ev); break;
        case Qt.Key_Escape:
            if (root.typeBuffer.length > 0) root.typeClear();
            else if (root.selCount > 0) root.clearSelection();
            else if (root.searchOpen) root.closeSearch();
            break;
        case Qt.Key_Space:
            if (root.typeBuffer.length > 0 && !ctrl)
                root.typeAhead(" ");
            else if (root.selCount === 1 && !root.selection[0].isDir)
                root.openPreview(root.selection[0]);
            else if (root.selCount === 1)
                root.showProperties();
            break;
        case Qt.Key_A: ctrl ? root.selectAll() : root.typeKey(ev); break;
        case Qt.Key_S: ctrl ? root.selectPatternPrompt() : root.typeKey(ev); break;
        case Qt.Key_I: ctrl ? root.invertSelection() : root.typeKey(ev); break;
        case Qt.Key_C: ctrl ? (shift ? root.copyPathText() : root.copySelection(false)) : root.typeKey(ev); break;
        case Qt.Key_X: ctrl ? root.copySelection(true) : root.typeKey(ev); break;
        case Qt.Key_V: ctrl ? root.paste() : root.typeKey(ev); break;
        case Qt.Key_Z: ctrl ? root.undo() : root.typeKey(ev); break;
        case Qt.Key_N: ctrl && alt ? root.openNewWindow() : (ctrl && shift ? root.newFolder() : (ctrl ? root.newFile() : root.typeKey(ev))); break;
        case Qt.Key_H: ctrl ? (root.cfg.fmHidden = !root.cfg.fmHidden) : root.typeKey(ev); break;
        case Qt.Key_T: ctrl && alt ? root.openTerminal() : (ctrl ? root.newTab() : root.typeKey(ev)); break;
        case Qt.Key_W: ctrl ? root.closeTab(root.tabIndex) : root.typeKey(ev); break;
        case Qt.Key_D: ctrl ? dispatchBookmark() : root.typeKey(ev); break;
        case Qt.Key_L: ctrl ? toolbar.pathBar.beginEdit() : root.typeKey(ev); break;
        case Qt.Key_F: ctrl ? root.openSearchBar() : root.typeKey(ev); break;
        case Qt.Key_1: ctrl ? root.rememberView({ view: "grid" }) : root.typeKey(ev); break;
        case Qt.Key_2: ctrl ? root.rememberView({ view: "list" }) : root.typeKey(ev); break;
        case Qt.Key_Tab:
        case Qt.Key_Backtab:
            if (ctrl)
                root.switchTab((root.tabIndex + (shift ? root.tabs.length - 1 : 1)) % root.tabs.length);
            else if (root.split && root.peer)
                root.peer.forceActiveFocus();
            else
                ev.accepted = false;
            break;
        case Qt.Key_Plus:
        case Qt.Key_Equal: ctrl ? root.zoom(1) : root.typeKey(ev); break;
        case Qt.Key_Minus: ctrl ? root.zoom(-1) : root.typeKey(ev); break;
        default:
            if (root.tryActionShortcut(ev))
                break;
            if (ev.text.length === 1 && !ctrl && !alt && ev.text >= " " && ev.text !== "\x7f")
                root.typeAhead(ev.text);
            else
                ev.accepted = false;
        }
    }

    function dispatchBookmark(): void {
        root.dispatch("bookmark", null);
    }

    function openSearchBar(): void {
        root.searchOpen = true;
        Qt.callLater(() => toolbar.focusSearch());
    }

    // ───────────────────────── plumbing ─────────────────────────

    FileBackend {
        id: backend
        forceRun: root.standalone
        onReadyChanged: {
            if (backend.ready && root.path.length === 0)
                root.startUp();
            else if (backend.ready) {
                // helper restarted on reopen: its watches are gone and the listing may be stale
                backend.request("watch", { watchId: "main", path: root.path }, null);
                root.reload(true);
            }
            if (backend.ready) {
                root.refreshSide();
                root.loadActions();
            }
        }
        onChanged: watchId => {
            if (watchId === "main")
                reloadTimer.restart();
        }
    }

    function startUp(): void {
        const wanted = root.secondary || root.standalone ? root.initialPath : GlobalStates.fileManagerPath;
        const start = wanted.length > 0 ? root.normalize(wanted) : backend.home;
        root.patchTab({ path: start, title: root.titleFor(start) });
        root.load();
    }

    function openRequested(): void {
        if (root.secondary || root.standalone)
            return;
        const p = GlobalStates.fileManagerPath;
        if (p.length > 0 && backend.ready)
            root.go(p);
    }

    Connections {
        target: GlobalStates
        function onFileManagerRequestChanged(): void {
            root.openRequested();
        }
    }

    Timer {
        id: reloadTimer
        interval: 120
        onTriggered: {
            root.reload(true);
            root.refreshSide();
        }
    }
    Timer { id: typeTimer; interval: 1300; onTriggered: root.typeClear() }
    Timer { id: toastTimer; interval: 4200; onTriggered: root.toastText = "" }
    Timer {
        id: searchTimer
        interval: 280
        onTriggered: root.runSearch()
    }
    Timer {
        id: devicesTimer
        interval: 6000
        repeat: true
        running: backend.ready
        onTriggered: {
            backend.request("devices", {}, { done: m => root.devices = m.devices });
            root.refreshPhones();
        }
    }
    QtObject {
        id: doneTimer
        property var ids: []
        function add(id: int): void {
            ids.push(id);
            expiry.restart();
        }
        property Timer t: Timer {
            id: expiry
            interval: 3500
            onTriggered: {
                for (const id of doneTimer.ids)
                    root.dismissJob(id);
                doneTimer.ids = [];
            }
        }
    }

    // ───────────────────────── layout ─────────────────────────

    Rectangle {
        anchors.fill: parent
        color: ClockStyle.colBackground
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        FileSidebar {
            id: sidebar
            Layout.fillHeight: true
            Layout.preferredWidth: root.width > 760 ? Math.min(184, root.cfg.fmSidebar) : 0
            visible: root.width > 760 && !root.secondary
            places: root.places
            bookmarks: root.bookmarks
            devices: root.devices
            phones: root.phones
            netMounts: root.netMounts
            onConnectRequested: root.connectServer()
            onPhoneRequested: dev => root.openPhone(dev)
            onPhoneDropped: (urls, dev) => root.sendToPhone(dev, root.urlsToPaths(urls))
            trashCount: root.trashCount
            home: backend.home
            currentPath: root.path
            onNavigate: p => root.go(p)
            onContextRequested: (item, x, y) => {
                menu.sideItem = item;
                menu.mode = "side";
                menu.popup(root.sideMenu(item), x, y);
            }
            onTabRequested: p => root.openTabInBackground(p)
            onNetMountRequested: uri => root.mountNet(uri)
            onMountRequested: dev => root.mountDevice(dev)
            onUnmountRequested: dev => root.unmountDevice(dev)
            onDropped: (urls, folder, action) => root.handleDrop(urls, folder, action)
        }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 10

        FileTabs {
            Layout.fillWidth: true
            visible: root.tabs.length > 1
            tabs: root.tabs
            current: root.tabIndex
            onActivated: i => root.switchTab(i)
            onClosed: i => root.closeTab(i)
            onAdded: root.newTab()
        }

        FileToolbar {
            id: toolbar
            Layout.fillWidth: true
            canBack: root.tab.back.length > 0
            canForward: root.tab.fwd.length > 0
            canUp: root.canUp
            path: root.path
            home: backend.home
            viewMode: root.viewMode
            searching: root.searchOpen
            deepSearch: root.deepSearch
            query: root.query
            onBack: root.goBack()
            onForward: root.goForward()
            onUp: root.goUp()
            onRefresh: root.reload(true)
            onNavigate: p => root.go(p)
            onTabRequested: p => root.openTabInBackground(p)
            onDropped: (urls, folder, action) => root.handleDrop(urls, folder, action)
            onViewChanged: mode => root.rememberView({ view: mode })
            onSearchOpened: root.openSearchBar()
            onQueryChanged2: text => {
                root.query = text;
                if (root.deepActive)
                    searchTimer.restart();
            }
            onDeepToggled: {
                root.deepSearch = !root.deepSearch;
                root.runSearch();
            }
            onSearchSubmitted: {
                if (root.shown.length > 0)
                    root.setOnly(0);
                root.forceActiveFocus();
            }
            onSearchClosed: root.closeSearch()
            onMoreRequested: (x, y) => {
                menu.sideItem = null;
                menu.mode = "more";
                menu.popup(root.moreMenu(), x, y);
            }
        }

        SearchFilters {
            Layout.fillWidth: true
            visible: root.searchOpen
            kind: root.searchKind
            days: root.searchDays
            minMb: root.searchMinMb
            content: root.searchContent
            onMenuRequested: (which, x, y) => {
                menu.sideItem = null;
                menu.mode = "more";
                menu.popup(root.filterMenu(which), x, y);
            }
            onContentToggled: root.setFilter("content:")
            onCleared: { root.searchKind = ""; root.searchDays = 0; root.searchMinMb = 0; root.runSearch(); }
        }

        Rectangle {
            id: card
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 28
            color: ClockStyle.colSurface
            clip: true

            // The folder
            Item {
                id: viewHost
                anchors.fill: parent
                anchors.margins: 6

                FileGridView {
                    id: gridView
                    anchors.fill: parent
                    visible: root.viewMode === "grid"
                    model: root.shown
                    selected: root.selected
                    cursor: root.cursor
                    renamingPath: root.renamingPath
                    iconSize: root.cfg.fmZoom
                    dragUris: root.dragUris
                    thumbs: root.thumbs
                    iconResolver: root.iconNamesFor
                    starredSet: root.starredSet
                    onSelectRequested: (i, mods) => root.selectAt(i, mods)
                    onOpenRequested: i => root.openEntry(root.shown[i])
                    onOpenInTabRequested: i => root.openEntryInTab(root.shown[i])
                    onContextRequested: (i, x, y) => { menu.sideItem = null; menu.mode = "files"; root.showMenu(i, x, y, gridView); }
                    onClearRequested: root.clearSelection()
                    onRubberBand: (idx, additive) => { root.setSelection(idx.map(i => root.shown[i].path)); root.forceActiveFocus(); }
                    onRenameCommitted: (p, t) => root.commitRename(p, t)
                    onRenameCancelled: { root.renamingPath = ""; root.forceActiveFocus(); }
                    onZoomRequested: d => root.zoom(d)
                    onDropped: (urls, folder, action) => root.handleDrop(urls, folder, action)
                    onThumbNeeded: e => root.thumbNeeded(e)
                }
                FileListView {
                    folderSizes: root.folderSizes
                    id: listView
                    anchors.fill: parent
                    visible: root.viewMode === "list"
                    model: root.shown
                    selected: root.selected
                    cursor: root.cursor
                    renamingPath: root.renamingPath
                    dragUris: root.dragUris
                    thumbs: root.thumbs
                    iconResolver: root.iconNamesFor
                    sortKey: root.sortKey
                    sortDesc: root.sortDesc
                    trashMode: root.isTrash
                    searchMode: root.searchMode || root.isVirtual
                    starredSet: root.starredSet
                    onSelectRequested: (i, mods) => root.selectAt(i, mods)
                    onOpenRequested: i => root.openEntry(root.shown[i])
                    onOpenInTabRequested: i => root.openEntryInTab(root.shown[i])
                    onContextRequested: (i, x, y) => { menu.sideItem = null; menu.mode = "files"; root.showMenu(i, x, y, listView); }
                    onClearRequested: root.clearSelection()
                    onRubberBand: (idx, additive) => { root.setSelection(idx.map(i => root.shown[i].path)); root.forceActiveFocus(); }
                    onRenameCommitted: (p, t) => root.commitRename(p, t)
                    onRenameCancelled: { root.renamingPath = ""; root.forceActiveFocus(); }
                    onZoomRequested: d => root.zoom(d)
                    onSortRequested: k => {
                        if (root.sortKey === k)
                            root.rememberView({ sortDesc: !root.sortDesc });
                        else
                            root.rememberView({ sortKey: k, sortDesc: false });
                    }
                    onDropped: (urls, folder, action) => root.handleDrop(urls, folder, action)
                    onThumbNeeded: e => root.thumbNeeded(e)
                }

                // Empty and error states
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: root.shown.length === 0 && !root.loading && !root.searchRunning
                    spacing: 10
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.loadError.length > 0 ? "folder_off" : (root.isTrash ? "delete_outline" : (root.query.length > 0 ? "search_off" : "folder_open"))
                        iconSize: 64
                        color: ClockStyle.colSubtext
                        opacity: 0.5
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.loadError.length > 0 ? root.loadError : (root.isTrash ? qsTr("The Trash is empty") : (root.query.length > 0 ? qsTr("No matches") : (root.path.startsWith("recent:") ? qsTr("Nothing opened recently") : (root.path.startsWith("starred:") ? qsTr("Star files from the right-click menu to find them here") : qsTr("This folder is empty")))))
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: ClockStyle.colSubtext
                    }
                }
                StyledText {
                    anchors.centerIn: parent
                    visible: root.searchRunning && root.shown.length === 0
                    text: qsTr("Searching…")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: ClockStyle.colSubtext
                }

                // Dropping on the empty background goes to this folder (handled by the views); a hint while dragging
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: 18
                    color: "transparent"
                    border.width: 2
                    border.color: ClockStyle.colPrimary
                    visible: viewDrop.containsDrag && root.dragUris.length === 0
                    opacity: 0.6
                }
                DropArea {
                    id: viewDrop
                    anchors.fill: parent
                    z: -1
                    keys: ["text/uri-list"]
                    onDropped: drop => {
                        root.handleDrop(drop.urls, "", drop.proposedAction);
                        drop.acceptProposedAction();
                    }
                }
            }
        }

        // Status bar
        Item {
            Layout.fillWidth: true
            implicitHeight: 24
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 14
                StyledText {
                    visible: root.typeBuffer.length > 0
                    Layout.maximumWidth: 360
                    elide: Text.ElideLeft
                    text: qsTr("Find: %1").arg(root.typeBuffer)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: root.typeMiss ? ClockStyle.colError : ClockStyle.colPrimary
                }
                StyledText {
                    visible: root.typeBuffer.length === 0
                    text: root.selCount > 0
                        ? qsTr("%1 selected").arg(root.selCount) + (root.selectionSize > 0 ? "  ·  " + root.bytes(root.selectionSize) : "")
                        : (root.searchMode ? qsTr("%1 results").arg(root.shown.length) : qsTr("%1 items").arg(root.shown.length))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: ClockStyle.colOnSurfaceVariant
                }
                StyledText {
                    visible: root.loading || root.searchRunning
                    text: qsTr("Loading…")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: ClockStyle.colSubtext
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    visible: root.freeSpace > 0 && !root.isTrash
                    text: qsTr("%1 free").arg(root.bytes(root.freeSpace))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: ClockStyle.colSubtext
                }
                StyledText {
                    visible: !root.writable && !root.isTrash && root.path.length > 0
                    text: qsTr("Read-only")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: ClockStyle.colError
                }
            }
        }
    }
    }

    // ───────────────────────── overlays ─────────────────────────

    TransferPanel {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 18
        anchors.bottomMargin: 56
        width: 340
        jobs: root.jobs
        onCancelRequested: id => backend.cancel(id)
        onDismissRequested: id => root.dismissJob(id)
    }

    Rectangle {
        visible: root.toastText.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 56
        implicitWidth: toastRow.implicitWidth + 36
        implicitHeight: 44
        radius: Appearance.rounding.full
        color: ClockStyle.colSurfaceHighest
        RowLayout {
            id: toastRow
            anchors.centerIn: parent
            spacing: 12
            StyledText {
                text: root.toastText
                font.pixelSize: Appearance.font.pixelSize.small
                color: ClockStyle.colOnSurface
            }
            StyledText {
                visible: root.toastUndo
                text: qsTr("Undo")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: ClockStyle.colPrimary
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.toastText = ""; root.undo(); }
                }
            }
        }
    }

    FmMenu {
        id: menu
        property var sideItem: null
        property string mode: "files"
        onTriggered: item => root.onMenu(item, menu.mode === "side" ? menu.sideItem : null)
        onClosed: root.forceActiveFocus()
    }

    // Which pane the keyboard is in, while the window is split
    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: 28
        color: "transparent"
        border.width: 2
        border.color: ClockStyle.colPrimary
        opacity: root.split && root.paneActive ? 0.55 : 0
        visible: opacity > 0
        z: 800
        Behavior on opacity { NumberAnimation { duration: Appearance.dur(140) } }
    }

    Item {
        id: dialogHost
        anchors.fill: parent
        z: 900
    }

    Component { id: promptDialog; PromptDialog {} }
    Component { id: conflictDialog; ConflictDialog {} }
    Component { id: propertiesDialog; PropertiesDialog {} }
    Component { id: openWithDialogComp; OpenWithDialog {} }
    Component { id: actionsDialog; ActionsEditor {} }
    Component { id: previewComp; FilePreview {} }
    Component { id: checksumComp; ChecksumDialog {} }
    Component { id: folderPickerComp; FolderPickerDialog {} }
    Component {
        id: dupesComp
        DuplicatesDialog {
            onTrashRequested: paths => { root.closeDialog(); root.trashPaths(paths); }
            onRevealRequested: p => { root.closeDialog(); root.go(root.dirname(p), p); }
        }
    }
    Component {
        id: duComp
        DiskUsageDialog { onOpenFolder: p => root.go(p) }
    }
    Component {
        id: compareComp
        CompareDialog { onTransferRequested: (srcs, dest) => root.startTransfer("copy", srcs, dest) }
    }
    Component {
        id: bulkDialog
        BulkRenameDialog {
            onAccepted: pairs => {
                backend.request("bulkRename", { pairs: pairs }, {
                    done: m => {
                        root.pushUndo({ kind: "move", pairs: m.results, label: qsTr("rename") });
                        root.reload(true);
                    },
                    error: msg => root.toast(msg)
                });
                root.closeDialog();
            }
        }
    }
    Component {
        id: helpDialog
        FmDialog {
            title: qsTr("Keyboard shortcuts")
            cardWidth: 560
            readonly property var rows: [
                ["Enter", qsTr("Open")], ["Space", qsTr("Quick look")], ["F2", qsTr("Rename")], ["Delete", qsTr("Move to Trash")],
                ["Shift+Delete", qsTr("Delete permanently")], ["Ctrl+C / X / V", qsTr("Copy / cut / paste")], ["Ctrl+Z", qsTr("Undo")],
                ["F5 / Ctrl+R", qsTr("Refresh")], ["F3", qsTr("Split view; Tab switches pane")], ["Shift+F5 / F6", qsTr("Copy / move to the other pane")], ["Ctrl+A", qsTr("Select all")], ["Ctrl+S", qsTr("Select by pattern")], ["Ctrl+I", qsTr("Invert selection")], ["Middle click", qsTr("Open a folder in a new tab")], ["Ctrl+Shift+N", qsTr("New folder")], ["Ctrl+T / W", qsTr("New tab / close tab")],
                ["Ctrl+L", qsTr("Edit the path")], ["Ctrl+F", qsTr("Search")], ["Ctrl+H", qsTr("Show hidden files")],
                ["Ctrl+1 / 2", qsTr("Icon / list view")], ["Alt+← → ↑", qsTr("Back, forward, up")], ["Alt+Enter", qsTr("Properties")],
                ["F4 / Ctrl+Alt+T", qsTr("Open a terminal here")], ["Ctrl+Alt+N", qsTr("New window")], ["Menu / Shift+F10", qsTr("Context menu")],
                ["Ctrl+D", qsTr("Bookmark")], ["Ctrl++ / −", qsTr("Zoom icons")], ["Type a name", qsTr("Jump to a file")]
            ]
            Repeater {
                model: rows
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    StyledText { Layout.preferredWidth: 180; text: modelData[0]; font.pixelSize: Appearance.font.pixelSize.smallie; font.weight: Font.DemiBold; color: ClockStyle.colPrimary }
                    StyledText { Layout.fillWidth: true; text: modelData[1]; font.pixelSize: Appearance.font.pixelSize.smallie; color: ClockStyle.colOnSurface }
                }
            }
            actions: [FmButton { text: qsTr("Close"); kind: "tonal"; onClicked: close() }]
        }
    }
}
