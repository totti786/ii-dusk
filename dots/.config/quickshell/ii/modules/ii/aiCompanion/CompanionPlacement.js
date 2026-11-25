.pragma library

function clamp(value, low, high) { return Math.max(low, Math.min(high, value)); }

// Positions refer to the orb's centre, independent of its expanding controls.
function constrain(x, y, bounds, radius) {
    return {x: clamp(x, bounds.x + radius + 12, bounds.x + bounds.width - radius - 12),
            y: clamp(y, bounds.y + radius + 12, bounds.y + bounds.height - radius - 12)};
}

function settle(x, y, bounds, radius) {
    const point = constrain(x, y, bounds, radius);
    const left = bounds.x + radius + 12;
    const right = bounds.x + bounds.width - radius - 12;
    if (point.x - left < 36) point.x = left;
    if (right - point.x < 36) point.x = right;
    return point;
}

function ratios(point, bounds, radius) {
    return {x: clamp((point.x - bounds.x - radius - 12) / Math.max(1, bounds.width - 2 * radius - 24), 0, 1),
            y: clamp((point.y - bounds.y - radius - 12) / Math.max(1, bounds.height - 2 * radius - 24), 0, 1)};
}

function fromRatios(x, y, bounds, radius) {
    return {x: bounds.x + radius + 12 + clamp(x, 0, 1) * Math.max(0, bounds.width - 2 * radius - 24),
            y: bounds.y + radius + 12 + clamp(y, 0, 1) * Math.max(0, bounds.height - 2 * radius - 24)};
}

function nearDock(x, y, target, padding) {
    return !!target && x >= target.x - padding && x <= target.x + target.width + padding
        && y >= target.y - padding && y <= target.y + target.height + padding;
}

// The direction the control fan points. In the open it points down, away from the state label above
// the orb. At a side edge it turns down and inward (not straight sideways: its top button would land
// on the label), and at the bottom it has to point up.
function fanAxis(x, y, bounds) {
    const left = x < 140, right = x > bounds.width - 140;
    const top = y < 140, bottom = y > bounds.height - 140;
    if (left) return bottom ? -45 : 45;
    if (right) return bottom ? -135 : 135;
    return bottom ? -90 : 90;
}

// Keep one evenly spaced fan. Rotate the whole arrangement near edges rather
// than clamping each button separately and distorting its spacing.
function orbitOffsets(x, y, bounds, expanded = false) {
    const base = fanAxis(x, y, bounds);
    const offsets = expanded ? [76, 38, -38, -76, 0] : [66, 22, -22, -66];
    const place = axis => offsets.map(offset => {
        const angle = (axis + offset) * Math.PI / 180;
        return {x: Math.cos(angle)*96, y: Math.sin(angle)*96};
    });
    // Every button must stay on screen without being squashed against the edge (which would bunch
    // neighbours together): turn the whole fan until all of them fit, the smallest turn first. Turning
    // never goes upward past the orb's own height, so the label above it stays clear.
    const fits = spots => spots.every(p => x + p.x >= 26 && x + p.x <= bounds.width - 26
        && y + p.y >= 26 && y + p.y <= bounds.height - 26 && p.y > -48);
    for (let turn = 0; turn <= 90; turn += 6) {
        for (const sign of turn === 0 ? [1] : [1, -1]) {
            const spots = place(base + sign * turn);
            if (fits(spots)) return spots;
        }
    }
    return place(base);
}

// How far the state label ("Ready to talk") must rise so the control fan does not sit on it. The
// fan points down from an orb in the open and at a side edge, but upwards at the
// bottom, and there it would land right across the label.
function labelRaise(x, y, bounds) {
    const bottom = y > bounds.height - 140;
    if (bottom) return 52;
    return 0;
}

// A bubble card grows away from its inner edge. Its orb must not travel with
// the outer edge when the card expands, especially on the island's left side.
function bubbleAnchor(side, width, diameter, inset = 0) {
    const distance = diameter/2 + inset;
    return {x: side === "left" ? width-distance : distance, y: distance};
}

// Where the small orbs sit: on the arc facing away from the control fan, so hovering the orb
// never puts a button on top of one. Returns up to `count` offsets from the orb's centre,
// nearest-the-middle of that arc first, skipping spots that would fall off the screen.
function satelliteOffsets(count, x, y, bounds, radius) {
    const axis = fanAxis(x, y, bounds);
    const out = [];
    for (const step of [0, 36, -36, 72, -72, 108, -108]) {
        if (out.length >= count) break;
        const angle = axis + 180 + step;
        let apart = Math.abs(((angle - axis) % 360 + 540) % 360 - 180);
        if (apart < 100) continue; // the control fan lives here
        const dx = Math.cos(angle * Math.PI / 180) * radius, dy = Math.sin(angle * Math.PI / 180) * radius;
        if (x + dx < 24 || x + dx > bounds.width - 24 || y + dy < 24 || y + dy > bounds.height - 24) continue;
        out.push({x: dx, y: dy});
    }
    return out;
}
