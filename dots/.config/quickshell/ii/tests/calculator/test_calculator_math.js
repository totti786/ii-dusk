// Run: node tests/calculator/test_calculator_math.js
// Loads modules/ii/calculator/CalculatorMath.js (a QML library: its first line is a pragma) by
// copying it, minus that line, next to this test as a CommonJS module.
const fs = require("fs");
const os = require("os");
const path = require("path");

const source = fs.readFileSync(path.join(__dirname, "../../modules/ii/calculator/CalculatorMath.js"), "utf8")
    .replace(/^\.pragma library\n/, "");
const tmp = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "calc-")), "math.js");
fs.writeFileSync(tmp, source + "\nmodule.exports = { evaluate, preview, format, prettyNumber, prettyExpression, sanitize, parses };\n");
const M = require(tmp);

let failed = 0;
function eq(name, got, want) {
    const ok = typeof want === "number" && typeof got === "number" ? Math.abs(got - want) < 1e-9 : got === want;
    if (!ok) { failed++; console.log("FAIL", name, "got", got, "want", want); }
}
function throws(name, fn, msg) {
    try { fn(); failed++; console.log("FAIL", name, "did not throw"); }
    catch (e) { if (msg && !e.message.includes(msg)) { failed++; console.log("FAIL", name, "threw", e.message, "want", msg); } }
}
const ev = (s, o) => M.evaluate(s, o);

// precedence and signs
eq("prec", ev("2+3*4"), 14);
eq("neg pow", ev("-2^2"), -4);
eq("pow neg", ev("2^-1"), 0.5);
eq("right assoc", ev("2^3^2"), 512);
eq("unary", ev("--3"), 3);
eq("mul neg", ev("2*-3"), -6);
eq("div", ev("10/4"), 2.5);
eq("mod word", ev("10 mod 3"), 1);

// percent
eq("pct plain", ev("10%"), 0.1);
eq("pct add", ev("50+10%"), 55);
eq("pct sub", ev("200-10%"), 180);
eq("pct mul", ev("200*10%"), 20);
eq("pct of sum", ev("(50+50)+10%"), 110);
eq("pct twice", ev("50+10%+10%"), 60.5);

// implicit multiplication
eq("2pi", ev("2pi"), 2 * Math.PI);
eq("2(3)", ev("2(3)"), 6);
eq("(1)(2)", ev("(1+1)(2+1)"), 6);
eq("3sqrt(4)", ev("3sqrt(4)"), 6);
eq("2e", ev("2e"), 2 * Math.E);
eq("1e-7 number", ev("1e-7"), 1e-7);
eq("round trip 1e-7", ev(M.format(1e-7)), 1e-7);
eq("round trip 1e21", ev(M.format(1e21)), 1e21);
eq("sci 2e3", ev("2e3"), 2000);

// functions and angle mode
eq("sin 30 deg", M.format(ev("sin(30)")), "0.5");
eq("sin 180 deg", M.format(ev("sin(180)")), "0");
eq("cos 90 deg", M.format(ev("cos(90)")), "0");
eq("sin pi rad", M.format(ev("sin(pi)", { angle: "rad" })), "0");
eq("asin 1 deg", ev("asin(1)"), 90);
eq("atan 1 deg", ev("atan(1)"), 45);
throws("tan 90", () => ev("tan(90)"), "Undefined");
eq("ln e", ev("ln(e)"), 1);
eq("log 1000", ev("log(1000)"), 3);
eq("log2", ev("log2(8)"), 3);
eq("sqrt bare", ev("sqrt 9"), 3);
eq("root sign", ev("√9"), 3);
throws("sqrt neg", () => ev("sqrt(-1)"), "Not a real");
eq("abs", ev("abs(-3)"), 3);

// factorial
eq("5!", ev("5!"), 120);
eq("0!", ev("0!"), 1);
eq("3!+1", ev("3!+1"), 7);
throws("1.5!", () => ev("1.5!"), "whole");
throws("171!", () => ev("171!"), "Too large");

// ans
eq("ans", ev("ans*2", { ans: 21 }), 42);
throws("no ans", () => ev("ans+1"), "previous");

// errors
throws("div0", () => ev("1/0"), "Division by zero");
throws("mod0", () => ev("1 mod 0"), "Division by zero");
throws("unclosed strict", () => ev("(1+2"), "Missing");
throws("trailing op", () => ev("2+"), "Unexpected end");
throws("junk", () => ev("2 # 3"), "Unknown character");
throws("empty", () => ev(""), "Empty");

// lenient preview
eq("lenient close", ev("2*(3+4", { lenient: true }), 14);
eq("preview trailing op", M.preview("2+"), 2);
eq("preview trailing op2", M.preview("2+3*"), 5);
eq("preview open bracket", M.preview("(3+4"), 7);
eq("preview op then bracket", M.preview("2+("), 2);
eq("preview empty", M.preview(""), null);
eq("preview only op", M.preview("+"), null);
eq("preview error is null", M.preview("1/0"), null);

// float formatting
eq("0.1+0.2", M.format(ev("0.1+0.2")), "0.3");
eq("int", M.format(42), "42");
eq("big", M.format(1e21), "1e+21");
eq("tiny snaps", M.format(1e-15), "0");
throws("format inf", () => M.format(Infinity), "finite");

// display forms
eq("group", M.prettyNumber("1234567", true), "1 234 567");
eq("group decimals", M.prettyNumber("1234.5678", true), "1 234.5678");
eq("no group", M.prettyNumber("1234567", false), "1234567");
eq("exp pretty", M.prettyNumber("1e+21", true), "1×10²¹");
eq("exp neg pretty", M.prettyNumber("1e-7", true), "1×10⁻⁷");
eq("neg group", M.prettyNumber("-12345", true), "-12 345");
eq("pretty expr", M.prettyExpression("12*3000/pi-sqrt(4)", true), "12×3 000÷π−√(4)".replace("√(4)", "sqrt(4)".replace("sqrt(", "√(")));

// paste sanitising
eq("paste unicode", M.sanitize("2 × 3 − 1"), "2*3-1");
eq("paste commas", M.sanitize("1,234 + 5"), "1234+5");
eq("paste pi", M.sanitize("2π"), "2pi");
eq("paste junk", M.sanitize("rm -rf /; echo"), "");
eq("paste newline", M.sanitize("1+1\n"), "1+1");

// history entries from the launcher may be qalc lines
eq("parses ok", M.parses("2+2"), true);
eq("parses qalc unit", M.parses("5 km to miles"), false);
eq("parses currency", M.parses("100 USD to EUR"), false);

console.log(failed === 0 ? "all calculator math tests passed" : failed + " FAILED");
process.exit(failed === 0 ? 0 : 1);
