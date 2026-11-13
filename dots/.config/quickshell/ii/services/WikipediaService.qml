pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import QtCore

import qs
import qs.modules.common
import "../modules/ii/wikipedia/WikipediaLogic.js" as WikiLogic

/**
 * Wikipedia's public MediaWiki and REST feed APIs.
 *
 * Home, search and article requests deliberately have separate state and tokens. A
 * slow feed cannot blank a search result, and a response from a canceled request can
 * never overwrite the language or article that replaced it.
 */
Singleton {
    id: root

    property string language: "en"
    property string query: ""
    property var results: []
    property var article: null
    property var history: []

    property var homeArticle: null
    property var mostRead: []
    property string homeDate: ""
    property bool homeLoading: false
    property bool homeLoaded: false
    property string homeError: ""

    property bool searching: false
    property string searchError: ""

    property bool articleLoading: false
    property string articleError: ""
    property string articleTitle: ""

    readonly property int readerFontSizeMin: 14
    readonly property int readerFontSizeMax: 28
    readonly property int readerFontSizeDefault: 18
    property int readerFontSize: root.readerFontSizeDefault

    // Compatibility names retained for callers that used the first two-pane version.
    readonly property bool loading: root.articleLoading
    readonly property string error: root.articleError
    /// IPC and the content frame consume this after they have initialised their state.
    property string requestedTab: ""

    readonly property int requestTimeoutMs: 18000
    readonly property string siteUrl: WikiLogic.siteUrl(root.language)

    property string _lastValidLanguage: "en"
    property int _epoch: 0
    property int _homeToken: 0
    property int _searchToken: 0
    property int _articleToken: 0
    property bool _homeTriedPreviousDate: false
    property string _articleRequestKind: "article"
    property var _activeRunners: []
    property bool _initialized: false

    onLanguageChanged: {
        if (root._initialized)
            root._handleLanguageChanged();
        else
            root._acceptStoredLanguage();
    }

    onReaderFontSizeChanged: root._clampReaderFontSize()

    Component.onCompleted: {
        root._acceptStoredLanguage();
        root._clampReaderFontSize();
        root._initialized = true;
    }

    function _acceptStoredLanguage(): void {
        const candidate = WikiLogic.normalizeLanguage(root.language);
        if (candidate.length === 0) {
            if (root.language !== root._lastValidLanguage)
                root.language = root._lastValidLanguage;
            return;
        }
        if (candidate !== root.language) {
            root.language = candidate;
            return;
        }
        root._lastValidLanguage = candidate;
    }

    function _clampReaderFontSize(): void {
        const clamped = WikiLogic.clampReaderFontSize(root.readerFontSize,
            root.readerFontSizeDefault, root.readerFontSizeMin, root.readerFontSizeMax);
        if (clamped !== root.readerFontSize)
            root.readerFontSize = clamped;
    }

    function _handleLanguageChanged(): void {
        const candidate = WikiLogic.normalizeLanguage(root.language);
        if (candidate.length === 0) {
            if (root.language !== root._lastValidLanguage)
                root.language = root._lastValidLanguage;
            return;
        }
        if (candidate !== root.language) {
            root.language = candidate;
            return;
        }
        if (candidate === root._lastValidLanguage)
            return;

        root._lastValidLanguage = candidate;
        root._epoch++;
        root._homeToken++;
        root._searchToken++;
        root._articleToken++;
        root._cancelActiveRequests();
        root.query = "";
        root.results = [];
        root.article = null;
        root.articleTitle = "";
        root._articleRequestKind = "article";
        root.history = [];
        root.homeArticle = null;
        root.mostRead = [];
        root.homeDate = "";
        root.homeLoaded = false;
        root.homeLoading = false;
        root.searching = false;
        root.articleLoading = false;
        root.homeError = "";
        root.searchError = "";
        root.articleError = "";
        root.requestedTab = "home";
        root.loadHome();
    }

    function setLanguage(value): bool {
        const candidate = WikiLogic.normalizeLanguage(value);
        if (candidate.length === 0)
            return false;
        if (candidate === root.language)
            return true;
        root.language = candidate;
        return true;
    }

    function setReaderFontSize(value): int {
        const clamped = WikiLogic.clampReaderFontSize(value, root.readerFontSizeDefault,
            root.readerFontSizeMin, root.readerFontSizeMax);
        root.readerFontSize = clamped;
        return clamped;
    }

    function adjustReaderFontSize(delta): int {
        return root.setReaderFontSize(WikiLogic.adjustReaderFontSize(root.readerFontSize,
            delta, root.readerFontSizeDefault, root.readerFontSizeMin, root.readerFontSizeMax));
    }

    function resetReaderFontSize(): int {
        return root.setReaderFontSize(root.readerFontSizeDefault);
    }

    function isValidLanguage(value): bool {
        return WikiLogic.isValidLanguage(value);
    }

    function plainText(html): string {
        return WikiLogic.stripHtml(html);
    }

    function _datePath(offsetDays = 0): string {
        const date = new Date();
        date.setDate(date.getDate() + Number(offsetDays || 0));
        return Qt.formatDateTime(date, "yyyy/MM/dd");
    }

    function _wikiUrl(path): string {
        if (root.siteUrl.length === 0 || String(path ?? "").length === 0)
            return "";
        return root.siteUrl + String(path);
    }

    function _begin(kind): var {
        root._cancelActiveRequests(kind);
        if (kind === "home")
            root._homeToken++;
        else if (kind === "search")
            root._searchToken++;
        else if (kind === "article")
            root._articleToken++;
        return {
            "epoch": root._epoch,
            "token": kind === "home" ? root._homeToken
                : kind === "search" ? root._searchToken : root._articleToken
        };
    }

    function _isCurrent(kind, epoch, token): bool {
        if (Number(epoch) !== root._epoch)
            return false;
        if (kind === "home")
            return WikiLogic.isCurrentRequest(epoch, root._epoch, token, root._homeToken);
        if (kind === "search")
            return WikiLogic.isCurrentRequest(epoch, root._epoch, token, root._searchToken);
        return WikiLogic.isCurrentRequest(epoch, root._epoch, token, root._articleToken);
    }

    function _rememberRunner(runner): void {
        root._activeRunners = root._activeRunners.concat([runner]);
    }

    function _forgetRunner(runner): void {
        root._activeRunners = root._activeRunners.filter(item => item !== runner);
    }

    function _cancelActiveRequests(kind = ""): void {
        const runners = root._activeRunners.slice();
        for (const runner of runners) {
            if (kind.length > 0 && runner.kind !== kind)
                continue;
            runner.retired = true;
            runner.handler = null;
            root._forgetRunner(runner);
            if (runner.running)
                runner.running = false;
            Qt.callLater(() => runner.destroy());
        }
    }

    function _decodeResponse(stdout): var {
        const text = String(stdout ?? "");
        const marker = "\n__II_HTTP_STATUS__:";
        const index = text.lastIndexOf(marker);
        if (index < 0)
            return { "body": text, "status": 0 };
        return {
            "body": text.slice(0, index),
            "status": Number(text.slice(index + marker.length).trim()) || 0
        };
    }

    function _jsonBody(text): var {
        try {
            return JSON.parse(String(text ?? ""));
        } catch (error) {
            return null;
        }
    }

    function _apiFailure(data): bool {
        return !!(data && typeof data === "object" && data.error);
    }

    function _networkError(stderr, fallback): string {
        const detail = String(stderr ?? "").trim().split("\n")
            .filter(line => line.trim().length > 0).pop() ?? "";
        // Curl's diagnostics are useful for logs but tend to be noisy and unstable in
        // the UI. Keep a short truthful fallback for a timeout or missing network.
        return detail.length > 0 ? detail : Translation.tr(fallback);
    }

    function _run(url, kind, epoch, token, handler): void {
        const runner = runnerComponent.createObject(root, {
            "command": ["curl", "-sS", "--compressed", "--max-time", String(root.requestTimeoutMs / 1000),
                "--connect-timeout", "6", "--retry", "0", "-A", "ii-wikipedia/1.0 (Quickshell)",
                "-w", "\n__II_HTTP_STATUS__:%{http_code}", url],
            "kind": kind,
            "epoch": epoch,
            "requestToken": token,
            "handler": handler,
            "timeoutMs": root.requestTimeoutMs + 1000
        });
        root._rememberRunner(runner);
        runner.running = true;
    }

    function loadHome(): void {
        const request = root._begin("home");
        root.homeArticle = null;
        root.mostRead = [];
        root.homeLoaded = false;
        root.homeLoading = true;
        root.homeError = "";
        root._homeTriedPreviousDate = false;
        root._runHomeDate(request.epoch, request.token, root._datePath(0));
    }

    function _runHomeDate(epoch, token, date): void {
        const path = WikiLogic.featuredPath(date);
        if (path.length === 0) {
            root._homeFailed(epoch, token, true, "");
            return;
        }
        root.homeDate = date;
        root._run(root._wikiUrl(path), "home", epoch, token,
            (stdout, stderr, code, timedOut) => root._homeFinished(epoch, token, date,
                stdout, stderr, code, timedOut));
    }

    function _homeFinished(epoch, token, date, stdout, stderr, code, timedOut): void {
        if (!root._isCurrent("home", epoch, token))
            return;

        const response = root._decodeResponse(stdout);
        const data = root._jsonBody(response.body);
        if (!timedOut && code === 0 && response.status >= 200 && response.status < 300
                && data && !root._apiFailure(data)) {
            const parsed = WikiLogic.parseFeatured(data, root.language);
            if (parsed.valid) {
                root.homeArticle = parsed.article;
                root.mostRead = parsed.mostRead;
                root.homeLoaded = true;
                root.homeLoading = false;
                root.homeError = "";
                return;
            }
        }

        if (!root._homeTriedPreviousDate) {
            root._homeTriedPreviousDate = true;
            const previous = root._datePath(-1);
            if (previous !== date) {
                root._runHomeDate(epoch, token, previous);
                return;
            }
        }
        root._homeFailed(epoch, token, timedOut, stderr);
    }

    function _homeFailed(epoch, token, timedOut, stderr): void {
        if (!root._isCurrent("home", epoch, token))
            return;
        root.homeLoading = false;
        root.homeLoaded = false;
        root.homeError = timedOut
            ? Translation.tr("Today's Wikipedia feed timed out. Try again.")
            : root._networkError(stderr, "Today's Wikipedia feed is unavailable for this language.");
    }

    function retryHome(): void {
        root.loadHome();
    }

    function search(text): void {
        const needle = String(text ?? "").trim();
        const request = root._begin("search");
        root.query = needle;
        root.results = [];
        root.searchError = "";
        root.requestedTab = "search";
        if (needle.length === 0) {
            root.searching = false;
            return;
        }

        root.searching = true;
        const url = root._wikiUrl("/w/api.php?action=query&list=search"
            + "&srsearch=" + encodeURIComponent(needle)
            + "&srlimit=24&srprop=snippet%7Cwordcount%7Ctimestamp"
            + "&format=json&formatversion=2&origin=*");
        root._run(url, "search", request.epoch, request.token,
            (stdout, stderr, code, timedOut) => root._searchFinished(request.epoch,
                request.token, stdout, stderr, code, timedOut));
    }

    function _searchFinished(epoch, token, stdout, stderr, code, timedOut): void {
        if (!root._isCurrent("search", epoch, token))
            return;
        root.searching = false;
        const response = root._decodeResponse(stdout);
        const data = root._jsonBody(response.body);
        if (timedOut) {
            root.searchError = Translation.tr("Search timed out. Try again.");
            return;
        }
        if (code !== 0 || response.status < 200 || response.status >= 300 || !data || root._apiFailure(data)) {
            root.searchError = root._networkError(stderr, "Wikipedia search failed. Try again.");
            return;
        }
        root.results = WikiLogic.parseSearch(data, root.language);
        if (root.results.length === 0)
            root.searchError = Translation.tr("No articles matched that search.");
    }

    function retrySearch(): void {
        if (root.query.length > 0)
            root.search(root.query);
    }

    function clearSearch(): void {
        root._searchToken++;
        root._cancelActiveRequests("search");
        root.query = "";
        root.results = [];
        root.searching = false;
        root.searchError = "";
    }

    function open(title): void {
        const page = String(title ?? "").trim();
        if (page.length === 0)
            return;
        if (root.article && String(root.article.title ?? "") !== page)
            root.history = root.history.concat([root.article.title]);
        root.requestedTab = "article";
        root._loadArticle(page);
    }

    function _loadArticle(title): void {
        const page = String(title ?? "").trim();
        if (page.length === 0)
            return;
        const request = root._begin("article");
        root.article = null;
        root.articleTitle = page;
        root._articleRequestKind = "article";
        root.articleLoading = true;
        root.articleError = "";
        const url = root._wikiUrl("/w/api.php?action=query"
            + "&prop=extracts%7Cpageimages%7Cinfo%7Cdescription"
            + "&exchars=24000&explaintext=1&exsectionformat=plain"
            + "&piprop=thumbnail&pithumbsize=960&inprop=url"
            + "&redirects=1&titles=" + encodeURIComponent(page)
            + "&format=json&formatversion=2&origin=*");
        root._run(url, "article", request.epoch, request.token,
            (stdout, stderr, code, timedOut) => root._articleFinished(request.epoch,
                request.token, page, stdout, stderr, code, timedOut));
    }

    function _articleFinished(epoch, token, title, stdout, stderr, code, timedOut): void {
        if (!root._isCurrent("article", epoch, token))
            return;
        root.articleLoading = false;
        const response = root._decodeResponse(stdout);
        const data = root._jsonBody(response.body);
        if (timedOut) {
            root.articleError = Translation.tr("That article timed out. Try again.");
            return;
        }
        if (code !== 0 || response.status < 200 || response.status >= 300 || !data || root._apiFailure(data)) {
            root.articleError = root._networkError(stderr, "Wikipedia could not load that article.");
            return;
        }
        const parsed = WikiLogic.parseArticle(data, root.language, title);
        if (!parsed) {
            root.articleError = Translation.tr("There is no article called %1.").arg(title);
            return;
        }
        root.article = parsed;
        root.articleError = "";
    }

    function back(): void {
        if (root.history.length === 0)
            return;
        const stack = root.history.slice();
        const title = stack.pop();
        root.history = stack;
        root.requestedTab = "article";
        root._loadArticle(title);
    }

    function random(): void {
        const request = root._begin("article");
        if (root.article)
            root.history = root.history.concat([root.article.title]);
        root.article = null;
        root.articleTitle = "";
        root._articleRequestKind = "random";
        root.articleLoading = true;
        root.articleError = "";
        root.requestedTab = "article";
        const url = root._wikiUrl("/w/api.php?action=query&list=random&rnnamespace=0"
            + "&rnlimit=1&format=json&formatversion=2&origin=*");
        root._run(url, "article", request.epoch, request.token,
            (stdout, stderr, code, timedOut) => root._randomFinished(request.epoch,
                request.token, stdout, stderr, code, timedOut));
    }

    function _randomFinished(epoch, token, stdout, stderr, code, timedOut): void {
        if (!root._isCurrent("article", epoch, token))
            return;
        const response = root._decodeResponse(stdout);
        const data = root._jsonBody(response.body);
        if (timedOut) {
            root.articleLoading = false;
            root.articleError = Translation.tr("Random article timed out. Try again.");
            return;
        }
        if (code !== 0 || response.status < 200 || response.status >= 300 || !data || root._apiFailure(data)) {
            root.articleLoading = false;
            root.articleError = root._networkError(stderr, "Could not choose a random article.");
            return;
        }
        const title = WikiLogic.parseRandom(data);
        if (title.length === 0) {
            root.articleLoading = false;
            root.articleError = Translation.tr("Wikipedia did not return a random article.");
            return;
        }
        root._loadArticle(title);
    }

    function retryArticle(): void {
        const title = root.article?.title ?? root.articleTitle;
        const action = WikiLogic.articleRetryAction(root._articleRequestKind, title);
        if (action === "random") {
            root.random();
            return;
        }
        if (action === "article")
            root._loadArticle(title);
    }

    function openInBrowser(): void {
        const url = WikiLogic.safePageUrl(root.article?.url, root.language);
        if (url.length > 0)
            Quickshell.execDetached(["xdg-open", url]);
    }

    function copyLink(): void {
        const article = root.article;
        const url = WikiLogic.safePageUrl(article?.url, root.language);
        if (url.length > 0)
            Quickshell.clipboardText = url;
    }

    function cancel(): void {
        root._epoch++;
        root._homeToken++;
        root._searchToken++;
        root._articleToken++;
        root._cancelActiveRequests();
        root.homeLoading = false;
        root.searching = false;
        root.articleLoading = false;
    }

    function clear(): void {
        root.cancel();
        root.query = "";
        root.results = [];
        root.article = null;
        root.articleTitle = "";
        root.history = [];
        root.homeArticle = null;
        root.mostRead = [];
        root.homeDate = "";
        root.homeLoaded = false;
        root.homeError = "";
        root.searchError = "";
        root.articleError = "";
        root.requestedTab = "";
    }

    Settings {
        id: wikipediaSettings
        // Keep Wikipedia preferences independent from the global config schema. This
        // follows the explicit-file pattern used by EmailService and survives shell reloads.
        location: `${Directories.state}/user/wikipedia-settings.ini`
        category: "WikipediaService"
        property alias language: root.language
        property alias readerFontSize: root.readerFontSize
    }

    Component {
        id: runnerComponent

        Scope {
            id: runner

            property alias command: process.command
            property alias running: process.running
            property var handler: null
            property string kind: ""
            property int epoch: 0
            property int requestToken: 0
            property int timeoutMs: 0
            property bool retired: false
            property bool timedOut: false

            Process {
                id: process

                stdout: StdioCollector {
                    id: output
                    waitForEnd: true
                }

                stderr: StdioCollector {
                    id: errors
                    waitForEnd: true
                }

                onExited: (code, status) => runner.finish(code, false)
            }

            Timer {
                interval: Math.max(1, runner.timeoutMs)
                running: !runner.retired && runner.timeoutMs > 0
                onTriggered: runner.finish(-1, true)
            }

            function finish(code, timedOut = false): void {
                if (runner.retired)
                    return;
                runner.retired = true;
                runner.timedOut = timedOut;
                const callback = runner.handler;
                runner.handler = null;
                const stdout = String(output.text ?? "");
                const stderr = String(errors.text ?? "");
                root._forgetRunner(runner);
                if (timedOut && runner.running)
                    runner.running = false;
                if (callback)
                    callback(stdout, stderr, code, timedOut);
                Qt.callLater(() => runner.destroy());
            }
        }
    }
}
