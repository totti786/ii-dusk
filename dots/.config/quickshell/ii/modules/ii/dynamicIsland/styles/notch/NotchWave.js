.pragma library

// A traveling scallop, joined to the corners with a zero-slope taper.
// Hermite tangents give adjacent cubic segments exactly the same velocity.
function segments(left, right, baseline, amplitude, phase, focus) {
    const length = Math.max(0, right-left);
    const a = Math.max(0, amplitude);
    const count = 12;
    const sample = u => {
        const envelope = Math.pow(Math.sin(Math.PI*u), 2);
        const envelopeSlope = Math.PI*Math.sin(2*Math.PI*u);
        const angle = 6*Math.PI*u-phase;
        const carrier = .5+.5*Math.sin(angle);
        const carrierSlope = 3*Math.PI*Math.cos(angle);
        const attention = .8+.2*Math.cos((u-focus)*Math.PI);
        const attentionSlope = -.2*Math.PI*Math.sin((u-focus)*Math.PI);
        return {x: right-length*u,
            y: baseline+a*envelope*carrier*attention,
            slope: a*(envelopeSlope*carrier*attention
                + envelope*carrierSlope*attention + envelope*carrier*attentionSlope)};
    };
    const result = [];
    for (let i=0;i<count;i++) {
        const p = sample(i/count), q = sample((i+1)/count), step = 1/(3*count);
        result.push({x: q.x, y: q.y,
            c1x: p.x-length*step, c1y: p.y+p.slope*step,
            c2x: q.x+length*step, c2y: q.y-q.slope*step});
    }
    return result;
}

function svg(parts) {
    return parts.map(p => " C " + p.c1x + " " + p.c1y + " " + p.c2x + " " + p.c2y + " " + p.x + " " + p.y).join("");
}
