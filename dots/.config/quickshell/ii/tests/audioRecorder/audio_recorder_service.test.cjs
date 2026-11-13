// Run with: node --test tests/audioRecorder/audio_recorder_service.test.cjs
//
// The pure helpers are extracted from the production QML service. No microphone,
// user's recordings, MediaPlayer backend, or external player is touched here.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');

const rootDir = path.resolve(__dirname, '../..');
const servicePath = path.join(rootDir, 'services/AudioRecorderService.qml');
const contentPath = path.join(rootDir, 'modules/ii/audioRecorder/AudioRecorderContent.qml');
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
        const char = source[index];
        if (inString) {
            if (escaped)
                escaped = false;
            else if (char === '\\')
                escaped = true;
            else if (char === quote)
                inString = false;
            continue;
        }
        if (char === '"' || char === "'") {
            inString = true;
            quote = char;
        } else if (char === '{') {
            depth++;
        } else if (char === '}' && --depth === 0) {
            const signature = source.slice(start, open)
                .replace(/:\s*(?:var|bool|int|real|string|void)\s*$/, '');
            return `${signature}{${source.slice(open + 1, index)}}`;
        }
    }
    throw new Error(`unterminated ${name}()`);
}

function qmlFunction(name) {
    return vm.runInNewContext(`(${functionSource(service, name)})`, {
        Array,
        Math,
        Number,
        String,
        encodeURIComponent,
    });
}

test('local file URLs preserve separators and encode path syntax', () => {
    const localFileUrl = qmlFunction('localFileUrl');
    assert.equal(
        localFileUrl('/tmp/voice note #1 – café.wav'),
        'file:///tmp/voice%20note%20%231%20%E2%80%93%20caf%C3%A9.wav',
    );
    assert.equal(localFileUrl('/tmp/take?.wav'), 'file:///tmp/take%3F.wav');
    assert.equal(localFileUrl('relative.wav'), 'file:///relative.wav');
    assert.equal(localFileUrl(''), '');
});

test('seek targets clamp to the native duration', () => {
    const clampSeek = qmlFunction('clampSeek');
    assert.equal(clampSeek(-2, 90), 0);
    assert.equal(clampSeek(42.5, 90), 42.5);
    assert.equal(clampSeek(120, 90), 90);
    assert.equal(clampSeek(12, 0), 0);
});

test('paused recording resumes before its final interrupt', () => {
    const stopSignalSequence = qmlFunction('stopSignalSequence');
    assert.deepEqual(Array.from(stopSignalSequence(true)), [18, 2]);
    assert.deepEqual(Array.from(stopSignalSequence(false)), [2]);
    assert.match(service, /for \(const signal of root\.stopSignalSequence\(root\.paused\)\)/);
    assert.match(service, /recordProc\.signal\(signal\)/);

    const signals = [];
    const root = {
        recording: true,
        paused: true,
        stopping: false,
        stopSignalSequence,
    };
    const context = {
        root,
        recordProc: {signal: signal => signals.push(signal)},
        elapsedTimer: {stop: () => { context.elapsedStopped = true; }},
        refreshTimer: {restart: () => { context.refreshScheduled = true; }},
    };
    const stopRecording = vm.runInNewContext(
        `(${functionSource(service, 'stopRecording')})`, context,
    );
    stopRecording();
    assert.deepEqual(signals, [18, 2]);
    assert.equal(root.recording, false);
    assert.equal(root.paused, false);
    assert.equal(root.stopping, true);
    assert.equal(context.elapsedStopped, true);
    assert.equal(context.refreshScheduled, true);
});

test('native in-process transport owns playback state', () => {
    assert.match(service, /import QtMultimedia/);
    assert.match(service, /MediaPlayer \{/);
    assert.match(service, /AudioOutput \{/);
    assert.match(service, /readonly property real playbackPosition/);
    assert.match(service, /readonly property real playbackDuration/);
    assert.match(service, /readonly property bool seekable/);
    assert.match(service, /function togglePlayback\(entry\)/);
    assert.match(service, /function pausePlayback\(\)/);
    assert.match(service, /function resumePlayback\(\)/);
    assert.match(service, /function stopPlayback\(\)/);
    assert.match(service, /function skip\(deltaSeconds\)/);
    assert.match(service, /_playWhenReady/);
    assert.match(service, /onErrorOccurred/);
    assert.doesNotMatch(functionSource(service, 'play'), /mpv|execDetached/);
});

test('transport keeps pending loads, pause/resume position, and replay bounded', () => {
    const media = {
        PlayingState: 1,
        PausedState: 2,
        StoppedState: 0,
        NoError: 0,
    };
    const calls = [];
    const player = {
        source: '',
        position: 0,
        duration: 12,
        playbackState: media.StoppedState,
        play() {
            calls.push('play');
            this.playbackState = media.PlayingState;
        },
        pause() {
            calls.push('pause');
            this.playbackState = media.PausedState;
        },
        stop() {
            calls.push('stop');
            this.playbackState = media.StoppedState;
        },
    };
    const root = {
        currentFile: '',
        recording: false,
        starting: false,
        stopping: false,
        selectedEntry: null,
        playbackEnded: false,
        _loadedPath: '',
        _playWhenReady: false,
        _playbackError: '',
        get selectedPath() { return String(this.selectedEntry?.path ?? ''); },
        get playbackDuration() { return player.duration; },
        get playbackPosition() { return player.position / 1000; },
        get playing() { return player.playbackState === media.PlayingState; },
        get seekable() { return true; },
        localFileUrl: qmlFunction('localFileUrl'),
        stopPlayback() {
            this._playWhenReady = false;
            player.stop();
            this.playbackEnded = false;
        },
    };
    const context = {
        root,
        String,
        Number,
        Math,
        MediaPlayer: media,
        playbackPlayer: player,
        playbackStartTimer: {
            restart() { calls.push('schedule-play'); },
            stop() { calls.push('cancel-play'); },
        },
        Translation: {tr: value => value},
    };
    root.selectRecording = vm.runInNewContext(
        `(${functionSource(service, 'selectRecording')})`, context,
    );
    const play = vm.runInNewContext(`(${functionSource(service, 'play')})`, context);
    root.play = play;
    root.pausePlayback = vm.runInNewContext(
        `(${functionSource(service, 'pausePlayback')})`, context,
    );
    const togglePlayback = vm.runInNewContext(
        `(${functionSource(service, 'togglePlayback')})`, context,
    );
    const first = {name: 'voice note #1 – café.wav', path: '/tmp/voice note #1 – café.wav'};
    play(first);
    assert.equal(player.source, 'file:///tmp/voice%20note%20%231%20%E2%80%93%20caf%C3%A9.wav');
    assert.equal(root._loadedPath, first.path);
    assert.equal(root._playWhenReady, true);
    assert.equal(calls.at(-1), 'schedule-play');

    player.position = 5000;
    player.playbackState = media.PlayingState;
    togglePlayback(first);
    assert.equal(player.playbackState, media.PausedState);
    assert.equal(player.position, 5000);
    assert.equal(root._playWhenReady, false, 'explicit pause cancels pending auto-play');
    togglePlayback(first);
    assert.equal(player.playbackState, media.PlayingState);
    assert.equal(player.position, 5000);

    root.playbackEnded = true;
    player.playbackState = media.StoppedState;
    player.position = 12000;
    play(first);
    assert.equal(player.position, 0, 'end-of-media play starts from the beginning');
    assert.equal(root._playbackError, '', 'retry clears a stale decoder error');

    root._playbackError = 'stale decoder error';
    player.source = 'stale-source';
    play(first);
    assert.equal(player.source, 'file:///tmp/voice%20note%20%231%20%E2%80%93%20caf%C3%A9.wav');
    assert.equal(root._playbackError, '', 'retry reloads the source after an error');
});

test('seek after end clamps and selected deletion clears transport state', () => {
    const player = {position: 4000, stopCalls: 0, stop() { this.stopCalls++; }};
    const root = {
        seekable: true,
        playbackDuration: 4,
        playbackEnded: true,
        selectedPath: '/tmp/take.wav',
        selectedEntry: {path: '/tmp/take.wav'},
        recording: false,
        starting: false,
        stopping: false,
        currentFile: '',
        playbackError: '',
        stopPlayback() { player.stop(); this.playbackEnded = false; },
    };
    const context = {
        root,
        Number,
        Math,
        String,
        playbackPlayer: player,
        Quickshell: {execDetached: args => { context.deleted = args; }},
        refreshTimer: {restart: () => { context.refreshed = true; }},
        Translation: {tr: value => value},
    };
    root.clampSeek = qmlFunction('clampSeek');
    const seek = vm.runInNewContext(`(${functionSource(service, 'seek')})`, context);
    seek(99);
    assert.equal(player.position, 4000);
    assert.equal(root.playbackEnded, false);

    const removeSource = functionSource(service, 'remove').replace('remove(path: string)', 'remove(path)');
    const remove = vm.runInNewContext(`(${removeSource})`, context);
    remove('/tmp/take.wav');
    assert.equal(root.selectedEntry, null);
    assert.equal(player.stopCalls, 1);
    assert.deepEqual(Array.from(context.deleted), ['rm', '-f', '/tmp/take.wav']);
    assert.equal(context.refreshed, true);
});

test('same-track replay and deleted-selection cleanup remain explicit', () => {
    assert.match(service, /root\.playbackEnded \|\|/);
    assert.match(service, /playbackPlayer\.position = 0/);
    assert.match(service, /playbackEnded = false/);
    assert.match(service, /if \(rawPath === root\.selectedPath\)/);
    assert.match(service, /root\.selectedEntry = null/);
    assert.match(service, /root\.stopPlayback\(\);/);
});

test('selecting a different row stops the old source before highlighting it', () => {
    const calls = [];
    const root = {
        currentFile: '',
        recording: false,
        starting: false,
        stopping: false,
        selectedPath: '/tmp/a.wav',
        selectedEntry: {path: '/tmp/a.wav'},
        playbackEnded: true,
        _playbackError: 'old error',
        stopPlayback() { calls.push('stop'); },
    };
    const player = {source: 'file:///tmp/a.wav'};
    const fn = vm.runInNewContext(`(${functionSource(service, 'selectRecording')})`, {
        root,
        String,
        Translation: {tr: text => text},
        playbackPlayer: player,
    });
    assert.equal(fn({path: '/tmp/b.wav', name: 'b'}), true);
    assert.deepEqual(calls, ['stop']);
    assert.equal(player.source, '');
    assert.equal(root.selectedEntry.path, '/tmp/b.wav');
    assert.equal(root.playbackEnded, false);
    assert.equal(root._playbackError, '');
});

test('recorder page exposes focused shared controls and protects child shortcuts', () => {
    assert.match(content, /ClockTopBar \{/);
    assert.match(content, /ClockPane \{/);
    assert.match(content, /StyledFlickable \{/);
    assert.match(content, /Layout\.minimumHeight: Math\.max\(listHeader\.implicitHeight/);
    assert.match(content, /ScrollBar\.vertical: StyledScrollBar/);
    assert.match(content, /implicitHeight: 60/);
    assert.match(content, /ClockButton \{/);
    assert.match(content, /StyledSlider \{/);
    assert.match(content, /Accessible\.name: Translation\.tr\("Playback position"\)/);
    assert.match(content, /focusPolicy: Qt\.StrongFocus/);
    assert.match(content, /interactiveChildHasFocus\(\)/);
    assert.match(content, /Qt\.Key_R/);
    assert.match(content, /Qt\.Key_W/);
    assert.match(content, /Qt\.Key_Q/);
    assert.match(content, /Translation\.tr\("Retry"\)/);
    assert.match(content, /enabled: root\.hasSelection && !root\.svc\.loading/);
    assert.doesNotMatch(content, /SIGSTOP/);
    assert.doesNotMatch(content, /PipeWire/);
});
