#!/usr/bin/env node
// Builds assets/quran/search-ar.json: the normalised Arabic of all 6236 verses, in surah order,
// so the first Arabic search does not have to build it (that took ~0.7 s inside the shell).
// Run from the shell directory after the Arabic text or normaliser changes:
//   node scripts/quran/build_search_index.js
const vm = require("vm"), fs = require("fs");
const ctx = vm.createContext({ console, JSON, Math, RegExp });
const strip = s => s.replace(/^\.pragma.*$/m, "").replace(/^\.import.*$/m, "");
const load = f => vm.runInContext(strip(fs.readFileSync("modules/ii/quran/" + f, "utf8")), ctx);
load("QuranCore.js");
vm.runInContext("var Core = this;", ctx);
load("QuranText.js");
const read = p => fs.readFileSync("assets/quran/" + p, "utf8");
ctx.setData(read("manifest-16.json"), read("manifest-24.json"), read("mushaf-unified.json"));
ctx.setChapters(read("chapters.json"));
ctx.ensureArabicIndex();
const out = vm.runInContext("arabicIndex", ctx);
if (out.length !== 6236 || out.some(x => typeof x !== "string")) throw new Error("bad index");
fs.writeFileSync("assets/quran/search-ar.json", JSON.stringify(out));
console.log("wrote", out.length, "verses");
