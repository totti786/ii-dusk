const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const p = vm.createContext({Math});
vm.runInContext(fs.readFileSync(path.resolve(__dirname, '../../modules/ii/aiCompanion/CompanionPlacement.js'), 'utf8').replace(/^\.pragma library\s*/, ''), p);
for (const b of [{x:0,y:0,width:1920,height:1080}, {x:-1920,y:-200,width:1920,height:1080}]) {
    const edge = p.settle(b.x+65,b.y+300,b,38);
    assert.equal(edge.x,b.x+50);
    const right = p.settle(b.x+b.width-65,b.y+300,b,38);
    assert.equal(right.x,b.x+b.width-50);
    for (let i=0;i<=100;i++) {
        const point = p.fromRatios(i/100,1-i/100,b,38);
        const ratio = p.ratios(point,b,38);
        assert.ok(Math.abs(ratio.x-i/100)<1e-10);
        assert.ok(Math.abs(ratio.y-(1-i/100))<1e-10);
        const safe = p.constrain(b.x-200,b.y+3000,b,38);
        assert.equal(safe.x,b.x+50);
        assert.equal(safe.y,b.y+b.height-50);
    }
}
const target={x:862,y:4,width:196,height:40};
assert.equal(p.nearDock(960,24,target,34),true);
assert.equal(p.nearDock(960,79,target,34),false);
assert.equal(p.nearDock(820,24,target,34),false);
assert.equal(p.nearDock(960,24,null,34),false);
console.log('Companion placement: monitor bounds, saved positions, edge snapping and docking passed');
for (const x of [50,100,500,960,1820,1870]) {
    for (const y of [50,100,300,980,1030]) {
        const points=p.orbitOffsets(x,y,{width:1920,height:1080});
        assert.equal(points.length,4);
        for (let i=0;i<points.length;i++) {
            assert.ok(Math.abs(Math.hypot(points[i].x,points[i].y)-80)<1e-8);
            assert.ok(x+points[i].x-22>=0 && x+points[i].x+22<=1920);
            assert.ok(y+points[i].y-22>=0 && y+points[i].y+22<=1080);
            if(i) assert.ok(Math.hypot(points[i].x-points[i-1].x,points[i].y-points[i-1].y)>52);
        }
    }
}
console.log('Orbit controls: equal radius, equal spacing, and all screen edges passed');
for (const side of ['left','right']) {
    for (const diameter of [32,36,40,48]) {
        const innerEdge=900;
        const expected=innerEdge+(side==='left' ? -1 : 1)*diameter/2;
        for (const width of [diameter,200,320,420]) {
            const anchor=p.bubbleAnchor(side,width,diameter);
            const cardLeft=side==='left' ? innerEdge-width : innerEdge;
            assert.equal(cardLeft+anchor.x,expected,'Hover expansion keeps the orb under the original pointer');
            assert.equal(anchor.y,diameter/2);
        }
    }
}
console.log('Bubble expansion: the orb stays at the grab point on both sides');

for (const side of ['left','right']) {
    for (const diameter of [32,36,40,48]) {
        const original=p.bubbleAnchor(side,320,diameter);
        const padded=p.bubbleAnchor(side,320,diameter,6);
        assert.ok(Math.hypot(original.x-padded.x,original.y-padded.y)<diameter*.43,
            'The original cursor position stays inside the inset orb');
        assert.ok(padded.y-diameter*.43>=8,'The visible orb clears the card corner');
    }
}
console.log('Header polish: corner padding preserves the original grab target');
