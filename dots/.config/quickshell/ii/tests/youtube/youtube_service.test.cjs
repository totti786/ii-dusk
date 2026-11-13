// Run with: node --test tests/youtube/youtube_service.test.cjs
//
// The pure helpers are extracted from the QML service. These tests never invoke yt-dlp,
// mpv, xdg-open, a browser, or the desktop clipboard.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');

const rootDir = path.resolve(__dirname, '../..');
const servicePath = path.join(rootDir, 'services/YouTubeService.qml');
const contentPath = path.join(rootDir, 'modules/ii/youtubeApp/YouTubeContent.qml');
const service = fs.readFileSync(servicePath, 'utf8');
const content = fs.readFileSync(contentPath, 'utf8');

function functionSource(source, name) {
    const start = source.indexOf(`function ${name}(`);
    assert.notEqual(start, -1, `expected ${name}() in source`);
    const open = source.indexOf('{', start);
    let depth = 0;
    let inString = false;
    let quote = '';
    let escaped = false;
    for (let index = open; index < source.length; index++) {
        const ch = source[index];
        if (inString) {
            if (escaped)
                escaped = false;
            else if (ch === '\\')
                escaped = true;
            else if (ch === quote)
                inString = false;
            continue;
        }
        if (ch === '"' || ch === "'") {
            inString = true;
            quote = ch;
        } else if (ch === '{') {
            depth++;
        } else if (ch === '}' && --depth === 0) {
            const signature = source.slice(start, open)
                .replace(/:\s*(?:var|bool|int|real|string|void)\s*$/, '')
                .replace(/:\s*(?:var|bool|int|real|string|void)(?=\s*[,\)])/g, '');
            return `${signature}{${source.slice(open + 1, index)}}`;
        }
    }
    throw new Error(`unterminated ${name}()`);
}

function qmlFunction(name, context = {}) {
    return vm.runInNewContext(`(${functionSource(service, name)})`, {
        Array,
        JSON,
        Math,
        Number,
        Object,
        String,
        Translation: {tr: value => value},
        ...context,
    });
}

function qmlContentFunction(name, context = {}) {
    return vm.runInNewContext(`(${functionSource(content, name)})`, {
        Array,
        JSON,
        Math,
        Number,
        Object,
        String,
        Qt: {callLater: callback => callback()},
        ...context,
    });
}

test('video id validation accepts supported YouTube URLs and rejects lookalikes', () => {
    const root = {};
    root._validVideoId = qmlFunction('_validVideoId', {root});
    root.videoIdFromText = qmlFunction('videoIdFromText', {root});

    assert.equal(root.videoIdFromText('dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    assert.equal(root.videoIdFromText('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42'), 'dQw4w9WgXcQ');
    assert.equal(root.videoIdFromText('https://youtu.be/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    assert.equal(root.videoIdFromText('https://youtube.com/shorts/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    assert.equal(root.videoIdFromText('https://example.test/watch?v=dQw4w9WgXcQ'), '');
    assert.equal(root.videoIdFromText('https://youtube.com/watch?v=too-short'), '');
    assert.equal(root.videoIdFromText('dQw4w9WgXcQ trailing text'), '');
});

test('playlist mapping keeps only unique video entries and selects useful metadata', () => {
    const root = {};
    root._validVideoId = qmlFunction('_validVideoId', {root});
    root.videoIdFromText = qmlFunction('videoIdFromText', {root});
    root._parsePlaylist = qmlFunction('_parsePlaylist', {root});
    root._bestThumbnail = qmlFunction('_bestThumbnail', {root});
    root._mapEntries = qmlFunction('_mapEntries', {root});

    const payload = JSON.stringify({entries: [
        {id: 'dQw4w9WgXcQ', title: 'First', uploader: 'Channel', duration: 61, view_count: 1200},
        {id: 'dQw4w9WgXcQ', title: 'Duplicate'},
        {id: 'too-short', title: 'Invalid'},
        {id: '9bZkp7q19f0', title: 'Second', thumbnails: [{width: 120, url: 'small'}, {width: 640, url: 'large'}]},
    ]});
    // The helper is evaluated in a vm realm, so normalize its array/object prototypes
    // before comparing the data contract in the host realm.
    assert.deepEqual(JSON.parse(JSON.stringify(root._mapEntries(payload))), [
        {id: 'dQw4w9WgXcQ', title: 'First', channel: 'Channel', duration: 61, views: 1200,
            thumbnail: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg'},
        {id: '9bZkp7q19f0', title: 'Second', channel: '', duration: 0, views: 0, thumbnail: 'large'},
    ]);
});

test('formatters are stable for empty and human-sized metadata', () => {
    const formatDuration = qmlFunction('formatDuration');
    const formatViews = qmlFunction('formatViews');
    assert.equal(formatDuration(0), '');
    assert.equal(formatDuration(61), '1:01');
    assert.equal(formatDuration(3661), '1:01:01');
    assert.equal(formatViews(0), '');
    assert.equal(formatViews(1200), '1.2K views');
    assert.equal(formatViews(1200000), '1.2M views');
});

test('returning to Search resumes a query canceled by Home, while stale callbacks stay inert', () => {
    const events = [];
    const svc = {
        query: 'science documentaries',
        results: [],
        searching: true,
        error: '',
        homeResults: [],
        homeLoading: false,
        homeError: '',
        homeTopic: 'Documentaries',
        loadHome(topic) {
            events.push(['home', topic]);
            this.searching = false;
            this.homeLoading = true;
        },
        search(query) {
            events.push(['search', query]);
            this.searching = true;
        },
    };
    const root = {
        svc,
        tabIds: ['home', 'search'],
        currentTab: 'search',
        focusSearch() {},
    };
    root.resumeSearchIfNeeded = qmlContentFunction('resumeSearchIfNeeded', {root});
    root.selectTab = qmlContentFunction('selectTab', {root});

    // A Home navigation cancels the shared Search runner and leaves the query recoverable.
    root.selectTab('home');
    assert.deepEqual(events, [['home', 'Documentaries']]);
    assert.equal(svc.searching, false);

    // Returning to Search starts exactly one replacement request.
    root.selectTab('search');
    assert.deepEqual(events, [['home', 'Documentaries'], ['search', 'science documentaries']]);
    root.selectTab('search');
    assert.deepEqual(events, [['home', 'Documentaries'], ['search', 'science documentaries']]);

    // A callback from either canceled generation cannot mutate the newer request.
    const lifecycle = {
        _generation: 2,
        searching: true,
        results: [],
        error: '',
    };
    lifecycle._isCurrentRequest = qmlFunction('_isCurrentRequest', {root: lifecycle});
    lifecycle._searchFinished = qmlFunction('_searchFinished', {root: lifecycle});
    lifecycle._searchFinished(1, '{"entries":[{"id":"dQw4w9WgXcQ"}]}', '', 0, false);
    assert.equal(lifecycle.searching, true);
    assert.deepEqual(lifecycle.results, []);
    lifecycle._generation = 3; // cancel/newer request supersedes token 2
    lifecycle._searchFinished(2, '{"entries":[{"id":"9bZkp7q19f0"}]}', '', 0, false);
    assert.equal(lifecycle.searching, true);
    assert.deepEqual(lifecycle.results, []);
});

test('request lifecycle is owned by generations and bounded runners', () => {
    assert.match(service, /import qs\.services/);
    assert.match(service, /property int _generation/);
    assert.match(service, /function _isCurrentRequest\(token\)/);
    assert.match(service, /if \(!root\._isCurrentRequest\(token\)\)/);
    assert.match(service, /runnerComponent\.createObject/);
    assert.match(service, /function _cancelActiveRequests\(\)/);
    assert.match(service, /property bool retired/);
    assert.match(service, /property int timeoutMs/);
    assert.match(service, /requestTimeoutMs: 25000/);
    assert.match(service, /--ignore-config/);
    assert.match(service, /--no-cache-dir/);
    assert.match(service, /:ytrec/);
    assert.doesNotMatch(service, /cookies-from-browser|--cookies\b/i);
});

test('content has compact shell navigation, themed generic icons, and honest last-opened copy', () => {
    assert.match(content, /ClockTopBar\s*\{/);
    assert.match(content, /video_library/);
    assert.match(content, /play_circle/);
    assert.match(content, /property string currentTab: "home"/);
    assert.match(content, /["']id["']:\s*["']search["']/);
    assert.match(content, /Key_F/);
    assert.match(content, /Key_W/);
    assert.match(content, /Key_Q/);
    assert.match(content, /Last opened/);
    assert.doesNotMatch(content, /#d32f2f|#ff0000|#ffebee/);
    assert.doesNotMatch(content, /Playing in mpv/);
});
