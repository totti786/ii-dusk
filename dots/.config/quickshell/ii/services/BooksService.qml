pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.modules.common
import qs.modules.common.functions

/**
 * The book library behind the Books app: what is on disk, what the viewers remember
 * about it, and the covers.
 *
 * scripts/books/books.py does the work. `scan` is quick and runs every time the window
 * opens; `covers` streams finished covers and page counts while the window is open and
 * leaves nothing to do once they are cached.
 */
Singleton {
    id: root

    signal browseRequested()

    readonly property string script: `${Directories.scriptPath}/books/books.py`
    readonly property string opdsScript: `${Directories.scriptPath}/books/opds.py`
    readonly property string homeDir: FileUtils.trimFileProtocol(Directories.home)

    /// The folder scanned for books.
    readonly property string libraryDir: {
        const configured = Config.options.books?.directory ?? "";
        return configured.length > 0 ? configured : `${root.homeDir}/Documents/Books`;
    }
    readonly property string viewer: Config.options.books?.viewer ?? "zathura"
    readonly property var viewers: ["zathura", "sioyek"]

    property var books: []
    property bool loading: false
    property bool folderExists: true
    property string errorText: ""
    property bool coversRunning: false

    /// Covers and page counts that arrived after the scan, by book id. Applied in batches.
    property var covers: ({})
    property var pages: ({})
    property var _pendingCovers: ({})
    property var _pendingPages: ({})

    function refresh(): void {
        if (scanProcess.running)
            return;
        root.loading = true;
        root.errorText = "";
        scanProcess.command = ["python3", "-I", root.script, "scan", "--dir", root.libraryDir];
        scanProcess.running = true;
    }

    function startCovers(): void {
        if (coverProcess.running)
            return;
        root.coversRunning = true;
        coverProcess.command = ["python3", "-I", root.script, "covers", "--dir", root.libraryDir];
        coverProcess.running = true;
    }

    function stopCovers(): void {
        coverProcess.running = false;
    }

    function coverFor(book): string {
        const path = root.covers[book.id] ?? book.cover;
        return path && path.length > 0 ? `file://${path}` : "";
    }

    function pagesFor(book): int {
        return Number(root.pages[book.id] ?? book.pages ?? 0);
    }

    /// 0..1 when the book has been started and its length is known.
    function progressFor(book): real {
        const total = root.pagesFor(book);
        if (book.page === null || book.page === undefined || total <= 0)
            return -1;
        return Math.max(0, Math.min(1, (Number(book.page) + 1) / total));
    }

    /// "3 days ago" for a unix timestamp (seconds).
    function ago(timestamp): string {
        if (timestamp === null || timestamp === undefined)
            return "";
        const seconds = Math.max(0, Date.now() / 1000 - Number(timestamp));
        const minutes = Math.floor(seconds / 60);
        const hours = Math.floor(minutes / 60);
        const days = Math.floor(hours / 24);
        if (minutes < 2)
            return Translation.tr("just now");
        if (hours < 1)
            return Translation.tr("%1 min ago").arg(minutes);
        if (hours < 24)
            return Translation.tr("%1 h ago").arg(hours);
        if (days === 1)
            return Translation.tr("yesterday");
        if (days < 14)
            return Translation.tr("%1 days ago").arg(days);
        if (days < 60)
            return Translation.tr("%1 weeks ago").arg(Math.floor(days / 7));
        if (days < 700)
            return Translation.tr("%1 months ago").arg(Math.floor(days / 30));
        return Translation.tr("%1 years ago").arg(Math.floor(days / 365));
    }

    function open(book, viewerName = ""): void {
        const chosen = viewerName.length > 0 ? viewerName : root.viewer;
        Quickshell.execDetached(["python3", FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/books/fullscreen_new.py")), chosen, book.path]);
    }

    function showInFolder(book): void {
        const slash = book.path.lastIndexOf("/");
        Quickshell.execDetached(["xdg-open", slash > 0 ? book.path.slice(0, slash) : book.path]);
    }

    function setViewer(name: string): void {
        Config.options.books.viewer = name;
    }

    /// Drops the book's saved page and, for one outside the library, its place in the list.
    function forget(book): void {
        root.books = root.books.map(b => b.id === book.id
            ? Object.assign({}, b, { page: null, lastRead: null, known: false }) : b);
        forgetProcess.command = ["python3", "-I", root.script, "forget", "--path", book.path];
        forgetProcess.running = true;
    }

    function restoreForgotten(): void {
        restoreProcess.command = ["python3", "-I", root.script, "restore"];
        restoreProcess.running = true;
    }

    function setLibraryDir(path: string): void {
        const trimmed = path.trim().replace(/\/+$/, "");
        const resolved = trimmed.startsWith("~") ? root.homeDir + trimmed.slice(1) : trimmed;
        if (resolved === root.libraryDir)
            return;
        Config.options.books.directory = resolved === `${root.homeDir}/Documents/Books` ? "" : resolved;
        root.stopCovers();
        root.covers = {};
        root.pages = {};
        root.refresh();
    }

    /// Asks the desktop for a folder; the answer goes through setLibraryDir.
    function browseLibraryDir(): void {
        if (pickProcess.running)
            return;
        pickProcess.command = ["zenity", "--file-selection", "--directory",
            "--title=" + Translation.tr("Choose the library folder"), "--filename=" + root.libraryDir + "/"];
        pickProcess.running = true;
    }


    // ------------------------------------------------------------------ sources & browsing

    property var sources: []
    property string sourceId: ""
    property string sourceError: ""
    /// A source the next refreshSources() should land on (used by the Manga launcher).
    property string pendingSource: ""
    /// Whether the next BooksContent should open on the Browse page.
    property bool browseWanted: false

    /// Pages visited in the current source, newest last. A frame is { url, query, page }.
    property var browseStack: []
    property bool browseLoading: false
    property string browseError: ""
    property int _browseToken: 0

    readonly property var source: root.sources.find(s => s.id === root.sourceId) ?? null
    readonly property var browsePage: root.browseStack.length > 0 ? root.browseStack[root.browseStack.length - 1].page : null
    readonly property bool canGoBack: root.browseStack.length > 1

    /// downloads[url] = { state: "running" | "done" | "error", received, total, path, error }
    property var downloads: ({})

    function _run(command, handler, stdinText = ""): void {
        const process = runnerComponent.createObject(root, { "command": command, "stdinText": stdinText, "handler": handler });
        process.running = true;
    }

    function _parse(text): var {
        try {
            return JSON.parse(text.split("\n").filter(l => l.trim().length > 0).pop());
        } catch (e) {
            return null;
        }
    }

    function refreshSources(): void {
        root._run(["python3", "-I", root.opdsScript, "sources"], text => {
            const data = root._parse(text);
            if (!data || !data.sources)
                return;
            root.sources = data.sources;
            if (root.pendingSource.length > 0) {
                const wanted = root.pendingSource;
                root.pendingSource = "";
                if (data.sources.some(source => source.id === wanted)) {
                    root.selectSource(wanted);
                    return;
                }
            }
            if (!root.source && data.sources.length > 0)
                root.selectSource(data.sources[0].id);
        });
    }

    /// Opens a source by id, loading the source list first when this session has none.
    function openSource(id: string): void {
        root.browseWanted = true;
        root.browseRequested();
        if (root.sources.some(source => source.id === id)) {
            root.selectSource(id);
            return;
        }
        root.pendingSource = id;
        root.refreshSources();
    }

    function selectSource(id: string): void {
        root.sourceId = id;
        root.browseStack = [];
        root.browseError = "";
        root._fetch({ "url": "", "query": "" }, true);
    }

    /// Loads a catalogue page. `replaceTop` swaps the newest frame instead of adding one.
    function _fetch(frame, fresh, append = false): void {
        const token = ++root._browseToken;
        root.browseLoading = true;
        root.browseError = "";
        const command = ["python3", "-I", root.opdsScript, "browse", `--id=${root.sourceId}`];
        if (frame.url.length > 0)
            command.push(`--url=${frame.url}`);
        if (frame.query.length > 0)
            command.push(`--query=${frame.query}`);
        root._run(command, text => {
            if (token !== root._browseToken)
                return;
            root.browseLoading = false;
            const page = root._parse(text);
            if (!page || page.ok === false) {
                root.browseError = page?.message ?? Translation.tr("The source did not answer.");
                return;
            }
            const stack = root.browseStack.slice();
            if (append && stack.length > 0) {
                const top = Object.assign({}, stack[stack.length - 1]);
                top.page = Object.assign({}, page, { "entries": top.page.entries.concat(page.entries) });
                stack[stack.length - 1] = top;
            } else {
                stack.push({ "url": frame.url, "query": frame.query, "page": page });
            }
            root.browseStack = stack;
        });
    }

    function browseOpen(url: string): void {
        root._fetch({ "url": url, "query": "" }, false);
    }

    function browseSearch(query: string): void {
        if (query.trim().length === 0)
            return;
        root._fetch({ "url": "", "query": query.trim() }, false);
    }

    /// Opens a book that the current page already describes in full.
    function browseShow(book): void {
        const stack = root.browseStack.slice();
        stack.push({ "url": "", "query": "", "page": { "title": book.title, "entries": [], "detail": book, "next": "", "search": false } });
        root.browseStack = stack;
    }

    function browseBack(): void {
        if (root.browseStack.length > 1) {
            root._browseToken++;
            root.browseLoading = false;
            root.browseError = "";
            root.browseStack = root.browseStack.slice(0, -1);
        }
    }

    function browseHome(): void {
        root.selectSource(root.sourceId);
    }

    function browseMore(): void {
        const page = root.browsePage;
        if (!page || !page.next || root.browseLoading)
            return;
        root._fetch({ "url": page.next, "query": "" }, false, true);
    }

    function addSource(name: string, url: string, user: string, password: string, done): void {
        const command = ["python3", "-I", root.opdsScript, "source-add", `--name=${name}`, `--url=${url}`];
        if (user.length > 0)
            command.push(`--user=${user}`);
        root._run(command, text => {
            const data = root._parse(text);
            if (!data || data.ok !== true) {
                done(false, data?.message ?? Translation.tr("Could not add the source."));
                return;
            }
            root.refreshSources();
            root.selectSource(data.id);
            done(true, "");
        }, user.length > 0 ? password : "");
    }

    function removeSource(id: string): void {
        root._run(["python3", "-I", root.opdsScript, "source-remove", "--id", id], text => {
            root.sourceId = "";
            root.refreshSources();
        });
    }

    function downloadDir(): string {
        if (root.source?.id === "zlib") {
            const configured = root._expandPath(String(Config.options.books?.zlibDownloadDir ?? ""));
            return configured.length > 0 ? configured : `${root.libraryDir}/Downloaded/Z-Library`;
        }
        if (root.source?.id === "manga")
            return `${root.libraryDir}/Manga`;
        const name = (root.source?.name ?? "Downloads").replace(/[\/\\:*?"<>|]/g, "-");
        return `${root.libraryDir}/Downloaded/${name}`;
    }

    function _expandPath(path: string): string {
        const trimmed = path.trim();
        if (trimmed.startsWith("~"))
            return root.homeDir + trimmed.slice(1);
        if (trimmed.length > 0 && !trimmed.startsWith("/"))
            return `${root.homeDir}/${trimmed}`;
        return trimmed;
    }

    function download(book, format): void {
        const key = format.href;
        if (root.downloads[key]?.state === "running")
            return;
        const update = patch => {
            const next = Object.assign({}, root.downloads);
            next[key] = Object.assign({}, next[key] ?? {}, patch);
            root.downloads = next;
        };
        update({ "state": "running", "received": 0, "total": format.size ?? 0, "path": "", "error": "" });
        const process = downloadComponent.createObject(root, {
            // --opt=value, so a title that starts with "-" is not read as an option.
            "command": ["python3", "-I", root.opdsScript, "download", `--id=${root.sourceId}`, `--url=${format.href}`,
                `--dest=${root.downloadDir()}`, `--title=${book.title}`, `--author=${book.author ?? ""}`, `--ext=${format.ext}`],
            "eventHandler": event => {
                if (event.done) {
                    update({ "state": "done", "path": event.path, "received": event.size, "total": event.size });
                    root.refresh();
                } else if (event.ok === false) {
                    update({ "state": "error", "error": event.message ?? Translation.tr("The download failed.") });
                } else if (event.progress !== undefined) {
                    update({ "received": event.progress, "total": event.total || (format.size ?? 0) });
                }
            },
            "failHandler": () => {
                if (root.downloads[key]?.state === "running")
                    update({ "state": "error", "error": Translation.tr("The download failed.") });
            }
        });
        process.running = true;
    }

    // ------------------------------------------------------------------ Z-Library

    /// Credentials travel over stdin (never argv); the CLI stores the tokens.
    function zlibLogin(email: string, password: string, domain: string, done): void {
        const payload = JSON.stringify({ "email": email, "password": password, "domain": domain });
        root._run(["python3", "-I", root.opdsScript, "login", "--id=zlib"], text => {
            const data = root._parse(text);
            if (!data) {
                done(false, Translation.tr("No answer from books-cli."));
                return;
            }
            done(data.ok === true, data.message ?? Translation.tr("Login failed."));
        }, payload);
    }

    function zlibSettings(done): void {
        root._run(["python3", "-I", root.opdsScript, "settings", "--id=zlib"], text => {
            done(root._parse(text) ?? null);
        });
    }

    function zlibSaveSettings(domain: string, done): void {
        root._run(["python3", "-I", root.opdsScript, "settings", "--id=zlib", `--domain=${domain}`], text => {
            const data = root._parse(text);
            if (!data) {
                done(false, Translation.tr("No answer from books-cli."));
                return;
            }
            done(data.ok === true, data.message ?? Translation.tr("Could not save the settings."));
        });
    }

    /// Opens the desktop folder picker; `done(path)` receives the absolute path.
    property var _zlibFolderCallback: null

    function zlibPickFolder(start: string, done): void {
        if (zlibPickProcess.running)
            return;
        root._zlibFolderCallback = done;
        zlibPickProcess.command = ["zenity", "--file-selection", "--directory",
            "--title=" + Translation.tr("Choose the Z-Library download folder"),
            "--filename=" + (start.length > 0 ? start : root.downloadDir()) + "/"];
        zlibPickProcess.running = true;
    }

    Component {
        id: runnerComponent

        Process {
            id: runner
            property string stdinText: ""
            property var handler: null
            stdinEnabled: runner.stdinText.length > 0
            onStarted: {
                if (runner.stdinText.length > 0)
                    runner.write(runner.stdinText + "\n");
            }
            stdout: StdioCollector {
                onStreamFinished: {
                    if (runner.handler)
                        runner.handler(text);
                    Qt.callLater(() => runner.destroy());
                }
            }
        }
    }

    Component {
        id: downloadComponent

        Process {
            id: transfer
            property var eventHandler: null
            property var failHandler: null
            stdout: SplitParser {
                onRead: line => {
                    try {
                        transfer.eventHandler(JSON.parse(line));
                    } catch (e) {
                    }
                }
            }
            onExited: (code, status) => {
                if (code !== 0 && transfer.failHandler)
                    transfer.failHandler();
                Qt.callLater(() => transfer.destroy());
            }
        }
    }

    function _flushCovers(): void {
        const addedCovers = root._pendingCovers;
        const addedPages = root._pendingPages;
        root._pendingCovers = {};
        root._pendingPages = {};
        if (Object.keys(addedCovers).length > 0)
            root.covers = Object.assign({}, root.covers, addedCovers);
        if (Object.keys(addedPages).length > 0)
            root.pages = Object.assign({}, root.pages, addedPages);
    }

    Timer {
        id: flushTimer
        interval: 300
        repeat: true
        running: root.coversRunning
        onTriggered: root._flushCovers()
    }

    Process {
        id: scanProcess
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    const data = JSON.parse(text);
                    root.folderExists = data.exists !== false;
                    root.books = data.books ?? [];
                } catch (e) {
                    root.errorText = Translation.tr("Could not read the library.");
                }
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.loading = false;
                root.errorText = Translation.tr("The library helper failed.");
            }
        }
    }

    Process {
        id: coverProcess
        stdout: SplitParser {
            onRead: line => {
                try {
                    const item = JSON.parse(line);
                    if (item.cover)
                        root._pendingCovers[item.id] = item.cover;
                    if (item.pages)
                        root._pendingPages[item.id] = item.pages;
                } catch (e) {
                }
            }
        }
        onExited: {
            root.coversRunning = false;
            root._flushCovers();
        }
    }

    Process {
        id: forgetProcess
        onExited: root.refresh()
    }

    Process {
        id: restoreProcess
        onExited: root.refresh()
    }

    Process {
        id: pickProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const chosen = text.trim();
                if (chosen.length > 0)
                    root.setLibraryDir(chosen);
            }
        }
    }

    Process {
        id: zlibPickProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const chosen = text.trim();
                const callback = root._zlibFolderCallback;
                root._zlibFolderCallback = null;
                if (chosen.length > 0 && callback)
                    callback(chosen);
            }
        }
    }
}
