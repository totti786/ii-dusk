const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const {execFileSync} = require('node:child_process');
const {test} = require('node:test');

const root = path.resolve(__dirname, '..');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(root, 'services/HyprlandProfiles.js'), 'utf8').replace(/^\.pragma library\s*/, ''), context);

function native(value) {
    return JSON.parse(JSON.stringify(value));
}

function plan(state, resetScope, releaseGameMode) {
    return native(context.plan(state, resetScope, releaseGameMode));
}

test('desktop transition resets Lite keys without removing the game marker', () => {
    const result = plan({lite: false, reduceMotion: false, gameMode: false}, context.LITE_KEYS, false);
    assert.deepStrictEqual(result.set, {});
    assert.deepStrictEqual(result.reset, native(context.LITE_KEYS));
    assert.deepStrictEqual(result.addLines, []);
    assert.deepStrictEqual(result.removeMatching, []);
});

test('Lite owns all six Lite values without adding a marker or resetting its scope', () => {
    const result = plan({lite: true, reduceMotion: false, gameMode: false}, context.LITE_KEYS, false);
    assert.deepStrictEqual(result.set, native(context.LITE));
    assert.deepStrictEqual(result.reset, []);
    assert.deepStrictEqual(result.addLines, []);
    assert.deepStrictEqual(result.removeMatching, []);
});

test('Game Mode wins shared keys while Lite-only values remain set', () => {
    const result = plan({lite: true, reduceMotion: false, gameMode: true}, context.GAME_MODE_KEYS, false);
    assert.equal(result.set['decoration:rounding_power'], 2);
    assert.equal(result.set['decoration:dim_inactive'], 0);
    assert.equal(result.set['render:direct_scanout'], 1);
    assert.deepStrictEqual(result.reset, []);
    assert.deepStrictEqual(result.addLines, [context.GAME_MODE_RULE]);
    assert.deepStrictEqual(result.removeMatching, []);
});

test('Desktop Game Mode sets all nine options and adds its marker', () => {
    const result = plan({lite: false, reduceMotion: false, gameMode: true}, null, false);
    assert.deepStrictEqual(result.set, native(context.GAME_MODE));
    assert.deepStrictEqual(result.reset, []);
    assert.deepStrictEqual(result.addLines, [context.GAME_MODE_RULE]);
    assert.deepStrictEqual(result.removeMatching, []);
});

test('Reduce motion alone sets only animations', () => {
    const result = plan({lite: false, reduceMotion: true, gameMode: false}, ['animations:enabled'], false);
    assert.deepStrictEqual(result.set, {'animations:enabled': 0});
    assert.deepStrictEqual(result.reset, []);
    assert.deepStrictEqual(result.addLines, []);
    assert.deepStrictEqual(result.removeMatching, []);
});

test('turning Game Mode off in Lite restores Lite values and resets game-only keys', () => {
    const result = plan({lite: true, reduceMotion: false, gameMode: false}, context.GAME_MODE_KEYS, true);
    assert.equal(result.set['animations:enabled'], 0);
    assert.equal(result.set['decoration:blur:enabled'], 0);
    assert.equal(result.set['decoration:shadow:enabled'], 0);
    assert.equal(result.set['decoration:rounding_power'], 2);
    assert.deepStrictEqual(result.reset, [
        'general:gaps_in',
        'general:gaps_out',
        'general:border_size',
        'decoration:rounding',
        'general:allow_tearing'
    ]);
    assert.deepStrictEqual(result.removeMatching, [context.GAME_MODE_RULE_MARKER]);
});

test('boot sync with no game marker does not remove anything', () => {
    const result = plan({lite: false, reduceMotion: false, gameMode: false}, null, false);
    assert.deepStrictEqual(result.set, {});
    assert.deepStrictEqual(result.reset, []);
    assert.deepStrictEqual(result.addLines, []);
    assert.deepStrictEqual(result.removeMatching, []);
});

test('a game-mode release does not remove the marker while Game Mode remains active', () => {
    const result = plan({lite: false, reduceMotion: false, gameMode: true}, context.GAME_MODE_KEYS, true);
    assert.deepStrictEqual(result.addLines, [context.GAME_MODE_RULE]);
    assert.deepStrictEqual(result.removeMatching, []);
});

test('the marker is removed only for an explicit game-mode release', () => {
    const result = plan({lite: false, reduceMotion: false, gameMode: false}, [], true);
    assert.deepStrictEqual(result.removeMatching, [context.GAME_MODE_RULE_MARKER]);
    assert.deepStrictEqual(plan({lite: false, reduceMotion: false, gameMode: false}, [], false).removeMatching, []);
});

test('set and reset keys are always disjoint', () => {
    const states = [
        {lite: false, reduceMotion: false, gameMode: false},
        {lite: true, reduceMotion: false, gameMode: false},
        {lite: false, reduceMotion: true, gameMode: false},
        {lite: true, reduceMotion: true, gameMode: true},
        {lite: false, reduceMotion: false, gameMode: true}
    ];
    const scopes = [null, [], context.LITE_KEYS, context.GAME_MODE_KEYS, ['animations:enabled', 'animations:enabled']];
    for (const state of states) {
        for (const scope of scopes) {
            const result = plan(state, scope, false);
            for (const key of result.reset)
                assert.equal(Object.prototype.hasOwnProperty.call(result.set, key), false, `${key} overlaps`);
        }
    }
});

test('configurator combines set and reset and skips an identical rewrite', () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hyprland-profiles-'));
    const file = path.join(directory, 'main.lua');
    const configurator = path.join(root, 'scripts/hyprland/hyprconfigurator.py');
    try {
        execFileSync('python3', [configurator, '--file', file,
            '--set', 'animations:enabled', '0', '--reset', 'general:gaps_in']);
        const first = fs.readFileSync(file);
        assert.equal(first.toString(), 'hl.config({animations={enabled=0}})\n');
        execFileSync('python3', [configurator, '--file', file,
            '--set', 'animations:enabled', '0', '--reset', 'general:gaps_in']);
        assert.deepStrictEqual(fs.readFileSync(file), first);
    } finally {
        fs.rmSync(directory, {recursive: true, force: true});
    }
});
