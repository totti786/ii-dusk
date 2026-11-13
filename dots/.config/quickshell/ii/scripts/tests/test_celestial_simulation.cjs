#!/usr/bin/env node

/* Pure simulation-clock tests. The full wallpaper needs Quickshell services;
 * these checks exercise the shared date math and the real local ephemeris. */

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.resolve(__dirname, "../..");

function loadLibrary(relativePath, exportNames) {
    const context = vm.createContext({ console, Date, Math, Number, String, isFinite });
    let source = fs.readFileSync(path.join(root, relativePath), "utf8")
        .replace(/^\.pragma library\s*/m, "");
    source += `\nthis.exports = {${exportNames.map(name => `${name}: ${name}`).join(",")}};`;
    vm.runInContext(source, context, { filename: relativePath });
    return context.exports;
}

const Simulation = loadLibrary(
    "modules/ii/background/celestial/code/simulation.js",
    ["boundedElapsedMs", "clampDaysPerSecond", "advanceDateMs"]
);
const Astronomy = loadLibrary(
    "modules/ii/background/celestial/code/astronomy.js",
    ["getMoonState", "getEarthAndOrbitState"]
);

assert.equal(Simulation.boundedElapsedMs(1000, 0, 1000), 1000);
assert.equal(Simulation.boundedElapsedMs(5000, 0, 1000), 1000,
    "resume gaps are capped to one wall-clock second");
assert.equal(Simulation.boundedElapsedMs(900, 1000, 1000), 0,
    "backwards wall-clock changes do not reverse the simulation");
assert.equal(Simulation.clampDaysPerSecond(NaN), 1);
assert.equal(Simulation.clampDaysPerSecond(999), 365);

const startMs = Date.UTC(2026, 0, 1, 0, 0, 0);
const oneDayMs = Simulation.advanceDateMs(startMs, 1000, 1);
assert.equal(oneDayMs - startMs, 86400000,
    "one day per second advances exactly one ephemeris day");

const moonBefore = Astronomy.getMoonState(new Date(startMs), 30, 31.2);
const moonAfter = Astronomy.getMoonState(new Date(oneDayMs), 30, 31.2);
assert.notEqual(moonBefore.phase, moonAfter.phase,
    "the real Moon ephemeris changes when the shared date advances");

const orbitBefore = Astronomy.getEarthAndOrbitState(new Date(startMs), 30, 31.2);
const orbitAfter = Astronomy.getEarthAndOrbitState(new Date(oneDayMs), 30, 31.2);
assert.notEqual(orbitBefore.earthHelioLonRad, orbitAfter.earthHelioLonRad,
    "the real orbit ephemeris consumes the same advanced date");
assert.notEqual(orbitBefore.localSolarTimeHours, orbitAfter.localSolarTimeHours,
    "local solar time follows the shared date too");

console.log("celestial simulation tests: ok");

