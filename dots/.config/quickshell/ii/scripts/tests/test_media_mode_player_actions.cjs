const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const actions = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../../modules/ii/background/MediaModePlayerActions.js'), 'utf8'), actions);
// Skip backwards cannot become negative; near-end skips must stay in the track.
assert.equal(actions.seekTarget(3, 120, -10), 0);
assert.equal(actions.seekTarget(115, 120, 10), 120);
// Streams without a published duration can still seek relatively.
assert.equal(actions.seekTarget(40, 0, 10), 50);
// Honor the player's bounds, including non-quarter-step boundaries.
assert.equal(actions.rateTarget(0.6, 1.8, 2), 1.8);
assert.equal(actions.rateTarget(0.6, 1.8, 0.5), 0.6);
assert.equal(actions.rateTarget(0.25, 2, 1.249999), 1.25);
assert.equal(actions.rateTarget(1, 1, 1), null);
assert.equal(actions.rateTarget(0.25, 2, NaN), null);
// URI opening needs a complete, advertised scheme, not just matching text.
assert.equal(actions.uriAllowed('HTTPS://example.com/media', ['http', 'https']), true);
assert.equal(actions.uriAllowed(' file:///home/user/music.ogg ', ['file']), true);
assert.equal(actions.uriAllowed('https', ['https']), false);
assert.equal(actions.uriAllowed('javascript:alert(1)', ['http', 'https']), false);
assert.equal(actions.uriAllowed('/tmp/a.mp3', ['file']), false);
assert.equal(actions.uriAllowed('https://example.com', []), false);
console.log('Media mode seek, rate and URI boundaries passed (14 checks).');
