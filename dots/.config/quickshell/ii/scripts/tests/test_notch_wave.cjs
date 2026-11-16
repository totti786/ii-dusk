const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const wave=vm.createContext({Math});
vm.runInContext(fs.readFileSync(path.resolve(__dirname,'../../modules/ii/dynamicIsland/styles/notch/NotchWave.js'),'utf8').replace(/^\.pragma library\s*/,''),wave);
for(let phase=0;phase<Math.PI*2;phase+=.17) {
    const parts=wave.segments(20,220,40,7,phase,.5);
    const next=wave.segments(20,220,40,7,phase+2.8/60,.5);
    assert.equal(parts.at(-1).x,20);
    assert.equal(parts.at(-1).y,40);
    assert.equal(parts[0].c1y,40);
    assert.equal(parts.at(-1).c2y,40);
    for(let i=0;i<parts.length;i++) {
        const p=parts[i];
        assert.ok(p.y>=40 && p.y<=47);
        assert.ok(Math.abs(p.y-next[i].y)<.2,'Frame-to-frame movement stays subpixel');
        if(i) {
            const before=parts[i-1];
            assert.ok(Math.abs((before.x-before.c2x)-(p.c1x-before.x))<1e-8);
            assert.ok(Math.abs((before.y-before.c2y)-(p.c1y-before.y))<1e-8,'Adjacent curves share a tangent');
        }
    }
}
for(const p of wave.segments(20,220,40,0,0,.5)) assert.equal(p.y,40);
console.log('Notch wave: smooth joins, corner tangency, frame continuity, bounds and flat rest passed');
