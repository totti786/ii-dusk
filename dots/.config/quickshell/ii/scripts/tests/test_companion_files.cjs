const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const c=vm.createContext({decodeURIComponent});
vm.runInContext(fs.readFileSync(path.resolve(__dirname,'../../modules/ii/aiCompanion/CompanionFiles.js'),'utf8').replace(/^\.pragma library\s*/,''),c);
const values = input => Array.from(c.localPaths(input));
assert.deepEqual(values(['file:///tmp/hello%20world.txt','file://localhost/tmp/hello%20world.txt','/tmp/a.txt']),['/tmp/hello world.txt','/tmp/a.txt']);
assert.deepEqual(values(['https://example.com/a','file://server/tmp/a','file:///tmp/%00a','file:///tmp/%ZZ','relative.txt']),[]);
assert.deepEqual(values(['file:///tmp/%D9%85%D9%84%D9%81.txt']),['/tmp/ملف.txt']);
assert.deepEqual(values([]),[]);
console.log('Companion files: local URLs, escaped names, Arabic, duplicates and unsupported drops passed');
