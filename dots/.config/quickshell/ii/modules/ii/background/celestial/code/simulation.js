.pragma library

/*
 * Small, dependency-free helpers for the Celestial wallpaper's time preview.
 * Keeping the clock math here makes the important state rules easy to test
 * without constructing the full Quickshell scene.
 */

var MILLIS_PER_DAY = 86400000;
var DEFAULT_MAX_ELAPSED_MS = 1000;

function boundedElapsedMs(nowMs, previousMs, maxElapsedMs) {
    var now = Number(nowMs);
    var previous = Number(previousMs);
    var maximum = Number(maxElapsedMs);

    if (!isFinite(now) || !isFinite(previous) || now < previous) {
        return 0;
    }
    if (!isFinite(maximum) || maximum <= 0) {
        maximum = DEFAULT_MAX_ELAPSED_MS;
    }
    return Math.min(maximum, Math.max(0, now - previous));
}

function clampDaysPerSecond(value) {
    var speed = Number(value);
    if (!isFinite(speed)) {
        return 1.0;
    }
    return Math.max(1.0 / 86400.0, Math.min(365.0, speed));
}

function advanceDateMs(dateMs, elapsedMs, daysPerSecond) {
    var start = Number(dateMs);
    var elapsed = Number(elapsedMs);
    if (!isFinite(start) || !isFinite(elapsed) || elapsed <= 0) {
        return start;
    }
    return start + elapsed / 1000.0 * clampDaysPerSecond(daysPerSecond) * MILLIS_PER_DAY;
}

