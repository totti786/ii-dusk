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

// Keep one evenly spaced fan. Rotate the whole arrangement near edges rather
// than clamping each button separately and distorting its spacing.
function orbitOffsets(x, y, bounds) {
    const left = x < 140, right = x > bounds.width - 140;
    const top = y < 140, bottom = y > bounds.height - 140;
    let axis = bottom ? -90 : 90;
    if (left) axis = top ? 45 : bottom ? -45 : 0;
    else if (right) axis = top ? 135 : bottom ? -135 : 180;
    return [60, 20, -20, -60].map(offset => {
        const angle = (axis + offset) * Math.PI / 180;
        return {x: Math.cos(angle)*80, y: Math.sin(angle)*80};
    });
}

// A bubble card grows away from its inner edge. Its orb must not travel with
// the outer edge when the card expands, especially on the island's left side.
function bubbleAnchor(side, width, diameter, inset = 0) {
    const distance = diameter/2 + inset;
    return {x: side === "left" ? width-distance : distance, y: distance};
}
