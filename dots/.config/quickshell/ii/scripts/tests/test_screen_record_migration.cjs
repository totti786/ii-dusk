// Exercise the real Config migration without loading Quickshell or writing config.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../../modules/common/Config.qml'), 'utf8');
const start = source.indexOf('    function migrateRaw(raw) {');
const end = source.indexOf('\n    // list<var>/list<string>', start);
assert.ok(start >= 0 && end > start);
const version = Number(source.match(/currentConfigVersion:\s*(\d+)/)[1]);
assert.ok(version >= 31, 'The production schema must run the recorder migration');
const context = vm.createContext({root: {currentConfigVersion: version}, console: {log() {}}});
vm.runInContext(source.slice(start, end), context);

// The old implicit default becomes auto, so an installed GPU Screen Recorder
// takes over without the user having to revisit Settings.
const legacy = {configVersion: 30, screenRecord: {service: 'wf-recorder', quality: 'high'}};
assert.equal(context.migrateRaw(legacy), true);
assert.equal(legacy.screenRecord.service, 'auto');
assert.equal(legacy.screenRecord.quality, 'high', 'Unrelated recorder settings survive');
assert.equal(legacy.configVersion, version);
assert.equal(context.migrateRaw(legacy), false, 'Already migrated config is unchanged');

// Explicit OBS stays explicit: only the old wf-recorder default is rewritten.
const obs = {configVersion: 30, screenRecord: {service: 'obs'}};
context.migrateRaw(obs);
assert.equal(obs.screenRecord.service, 'obs');

const explicit = {configVersion: 30, screenRecord: {service: 'gsr'}};
context.migrateRaw(explicit);
assert.equal(explicit.screenRecord.service, 'gsr');

const current = {configVersion: version, screenRecord: {service: 'wf-recorder'}};
assert.equal(context.migrateRaw(current), false, 'A current config is left alone');
assert.equal(current.screenRecord.service, 'wf-recorder', 'A deliberate current choice is not rewritten');

const malformed = {configVersion: 30, screenRecord: null};
context.migrateRaw(malformed);
assert.equal(malformed.screenRecord, null, 'Malformed containers remain for the repair pass');

console.log('PASS: wf-recorder default migrates to auto, explicit choices and unrelated fields survive.');
