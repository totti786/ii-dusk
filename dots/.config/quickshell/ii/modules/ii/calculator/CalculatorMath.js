.pragma library

// The calculator's engine: a small recursive-descent parser that never runs the text as code.
//
// Precedence, lowest first:
//   expr    := term (("+" | "-") term)*          a + b% means a + a*b/100
//   term    := unary (("*" | "/" | "mod" | <implicit>) unary)*
//   unary   := ("-" | "+") unary | power
//   power   := postfix ("^" unary)?               right associative, so 2^-1 and -2^2 work
//   postfix := primary ("!" | "%")*
//   primary := number | constant | function "(" expr ")" | "(" expr ")"
//
// Implicit multiplication ("2pi", "2(3)", "(1)(2)", "3sqrt(4)") binds like "*".
// The expression is kept as plain ASCII; everything typographic (÷ × − π √ grouping) is
// produced by `pretty*` for the screen and never stored. Throws Error with a short message.

const constants = { pi: Math.PI, "π": Math.PI, e: Math.E, tau: 2 * Math.PI };

const trig = { sin: Math.sin, cos: Math.cos, tan: Math.tan };
const inverseTrig = { asin: Math.asin, acos: Math.acos, atan: Math.atan };
const plain = {
    sinh: Math.sinh, cosh: Math.cosh, tanh: Math.tanh,
    ln: Math.log, log: Math.log10, log2: Math.log2, lg: Math.log10,
    sqrt: Math.sqrt, "√": Math.sqrt, cbrt: Math.cbrt, abs: Math.abs, exp: Math.exp,
    floor: Math.floor, ceil: Math.ceil, round: Math.round
};

function has(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key);
}

function isFunction(name) {
    return has(trig, name) || has(inverseTrig, name) || has(plain, name);
}

function tokenize(text) {
    const tokens = [];
    let i = 0;
    while (i < text.length) {
        const rest = text.slice(i);
        const space = rest.match(/^\s+/);
        if (space) {
            i += space[0].length;
            continue;
        }
        // An exponent is only part of the number when digits follow it: "2e" is 2 times e,
        // "1e-7" (what a result like 0.0000001 prints as) is one number.
        const number = rest.match(/^(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?/);
        if (number) {
            tokens.push({ type: "num", value: parseFloat(number[0]), raw: number[0] });
            i += number[0].length;
            continue;
        }
        const word = rest.match(/^[A-Za-z]+[0-9]?/);
        if (word) {
            // "log2" has a digit; "x2" and "pi2" do not mean anything, so only functions keep one
            let w = word[0].toLowerCase();
            if (/[0-9]$/.test(w) && !isFunction(w))
                w = w.slice(0, -1);
            tokens.push({ type: "name", value: w });
            i += w.length;
            continue;
        }
        const ch = text[i];
        if ("+-*/^%()!".includes(ch)) {
            tokens.push({ type: "op", value: ch });
            i += 1;
            continue;
        }
        if (ch === "π" || ch === "√") {
            tokens.push({ type: "name", value: ch });
            i += 1;
            continue;
        }
        throw new Error("Unknown character '" + ch + "'");
    }
    return tokens;
}

function factorial(n) {
    if (!Number.isInteger(n) || n < 0)
        throw new Error("Factorial needs a whole number");
    if (n > 170)
        throw new Error("Too large");
    let r = 1;
    for (let k = 2; k <= n; k++)
        r *= k;
    return r;
}

/**
 * Computes `text`. Options:
 *   angle    "deg" (default) or "rad" for sin cos tan and their inverses
 *   ans      value of the name `ans`
 *   lenient  close missing ")" at the end, for a live preview of what is being typed
 */
function evaluate(text, options) {
    const opts = options || {};
    const degrees = (opts.angle || "deg") !== "rad";
    const tokens = tokenize(String(text ?? ""));
    if (tokens.length === 0)
        throw new Error("Empty");

    let pos = 0;

    function peek() {
        return tokens[pos];
    }
    function isOp(value) {
        const t = tokens[pos];
        return t !== undefined && t.type === "op" && t.value === value;
    }
    function isName(value) {
        const t = tokens[pos];
        return t !== undefined && t.type === "name" && t.value === value;
    }
    function take() {
        return tokens[pos++];
    }
    function expectClose() {
        if (isOp(")")) {
            pos++;
            return;
        }
        if (opts.lenient && pos >= tokens.length)
            return;
        throw new Error("Missing ')'");
    }

    // A factor can begin here: what makes "2pi" and "2(3)" a product
    function startsFactor() {
        const t = peek();
        if (t === undefined)
            return false;
        if (t.type === "num")
            return true;
        if (t.type === "name")
            return t.value !== "mod";
        return t.type === "op" && t.value === "(";
    }

    function toRadians(x) {
        return degrees ? x * Math.PI / 180 : x;
    }
    function fromRadians(x) {
        return degrees ? x * 180 / Math.PI : x;
    }
    function snap(x) {
        return Math.abs(x) < 1e-14 ? 0 : x;
    }

    function callFunction(name, arg) {
        if (has(trig, name)) {
            const rad = toRadians(arg);
            if (name === "tan" && Math.abs(Math.cos(rad)) < 1e-12)
                throw new Error("Undefined");
            return snap(trig[name](rad));
        }
        if (has(inverseTrig, name)) {
            const r = inverseTrig[name](arg);
            if (Number.isNaN(r))
                throw new Error("Out of range");
            return snap(fromRadians(r));
        }
        const r = plain[name](arg);
        if (Number.isNaN(r))
            throw new Error("Not a real number");
        return r;
    }

    function parseExpr() {
        let value = parseTerm().v;
        while (isOp("+") || isOp("-")) {
            const op = take().value;
            const right = parseTerm();
            // 200 + 10% is 220: a lone percent after + or - is a share of what is on the left
            const amount = right.pct ? value * right.v : right.v;
            value = op === "+" ? value + amount : value - amount;
        }
        return value;
    }

    function parseTerm() {
        const first = parseUnary();
        let value = first.v;
        let factors = 1;
        for (;;) {
            let op = null;
            if (isOp("*") || isOp("/")) {
                op = take().value;
            } else if (isName("mod")) {
                take();
                op = "mod";
            } else if (startsFactor()) {
                op = "*";
            } else {
                break;
            }
            const right = parseUnary().v;
            factors++;
            if (op === "*") {
                value *= right;
            } else {
                if (right === 0)
                    throw new Error("Division by zero");
                value = op === "/" ? value / right : value % right;
            }
        }
        return { v: value, pct: factors === 1 && first.pct };
    }

    function parseUnary() {
        if (isOp("-")) {
            take();
            const inner = parseUnary();
            return { v: -inner.v, pct: false };
        }
        if (isOp("+")) {
            take();
            return parseUnary();
        }
        return parsePower();
    }

    function parsePower() {
        const base = parsePostfix();
        if (isOp("^")) {
            take();
            const exponent = parseUnary().v;
            const r = Math.pow(base.v, exponent);
            if (Number.isNaN(r))
                throw new Error("Not a real number");
            return { v: r, pct: false };
        }
        return base;
    }

    function parsePostfix() {
        let node = { v: parsePrimary(), pct: false };
        for (;;) {
            if (isOp("!")) {
                take();
                node = { v: factorial(node.v), pct: false };
            } else if (isOp("%")) {
                take();
                node = { v: node.v / 100, pct: true };
            } else {
                break;
            }
        }
        return node;
    }

    function parsePrimary() {
        const t = take();
        if (t === undefined)
            throw new Error("Unexpected end");
        if (t.type === "num")
            return t.value;
        if (t.type === "name") {
            if (t.value === "ans") {
                if (opts.ans === undefined || opts.ans === null)
                    throw new Error("No previous answer");
                return Number(opts.ans);
            }
            if (has(constants, t.value) && !isOp("("))
                return constants[t.value];
            if (isFunction(t.value)) {
                // "√9" and "sqrt 9" are fine without brackets for a bare number
                if (!isOp("(")) {
                    if (peek() !== undefined && peek().type === "num")
                        return callFunction(t.value, take().value);
                    throw new Error("Expected '('");
                }
                take();
                const arg = parseExpr();
                expectClose();
                return callFunction(t.value, arg);
            }
            throw new Error("Unknown name '" + t.value + "'");
        }
        if (t.value === "(") {
            const inner = parseExpr();
            expectClose();
            return inner;
        }
        throw new Error("Unexpected '" + t.value + "'");
    }

    const result = parseExpr();
    if (pos < tokens.length)
        throw new Error("Unexpected '" + (tokens[pos].raw ?? tokens[pos].value) + "'");
    if (!Number.isFinite(result))
        throw new Error("Not a finite number");
    return result;
}

/**
 * The value of what is being typed, or null when there is not one yet. Unclosed brackets are
 * closed and a trailing operator ("2+") is ignored, so the answer line follows the typing
 * instead of going blank at every operator.
 */
function preview(text, options) {
    const opts = Object.assign({}, options || {}, { lenient: true });
    let s = String(text ?? "");
    for (let i = 0; i < 4; i++) {
        try {
            return evaluate(s, opts);
        } catch (e) {
            const trimmed = s.replace(/(\s*(mod|[+\-*\/^(]))+\s*$/i, "");
            if (trimmed === s)
                return null;
            s = trimmed;
            if (s === "")
                return null;
        }
    }
    return null;
}

// Whole numbers print as they are; everything else is rounded to 12 significant digits so
// 0.1 + 0.2 shows as 0.3. Very large and very small numbers come out as "1e+21" / "1e-7",
// which the tokenizer reads back as one number.
function format(value) {
    if (!Number.isFinite(value))
        throw new Error("Not a finite number");
    if (Math.abs(value) < 1e-14)
        return "0";
    if (Number.isInteger(value) && Math.abs(value) < 1e15)
        return String(value);
    return String(parseFloat(value.toPrecision(12)));
}

const superscripts = { "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻", "+": "" };

/** A number string for the screen: groups of three, "×10ⁿ" for exponents. ASCII digits only. */
function prettyNumber(text, group) {
    const m = String(text).match(/^(-?)(\d*)(\.\d*)?(?:[eE]([+-]?\d+))?$/);
    if (!m)
        return text;
    let whole = m[2];
    if (group !== false && whole.length > 3)
        whole = whole.replace(/\B(?=(\d{3})+(?!\d))/g, " ");
    let out = m[1] + whole + (m[3] ?? "");
    if (m[4] !== undefined)
        out += "×10" + m[4].split("").map(c => superscripts[c] ?? c).join("");
    return out;
}

/** The expression as it is drawn: ÷ × − π √, grouped numbers. The stored text is not touched. */
function prettyExpression(text, group) {
    return String(text ?? "")
        .replace(/(\d+(?:\.\d*)?(?:[eE][+-]?\d+)?|\.\d+)/g, n => prettyNumber(n, group))
        .replace(/\*/g, "×")
        .replace(/\//g, "÷")
        .replace(/-/g, "−")
        .replace(/\bpi\b/g, "π")
        .replace(/\bsqrt\(/g, "√(")
        .replace(/\bmod\b/g, " mod ");
}

/** What a pasted clipboard becomes, or "" when it is not a calculation we can read. */
function sanitize(text) {
    const s = String(text ?? "")
        .replace(/[×x*]/g, "*").replace(/[÷]/g, "/").replace(/[−–—]/g, "-")
        .replace(/[\s,  ]/g, "")
        .replace(/π/g, "pi");
    return /^[0-9A-Za-z.()+\-*\/^%!]+$/.test(s) ? s : "";
}

/**
 * Whether a history entry's expression is something this engine can take back in. The
 * launcher keeps qalc-style lines too (units, currencies), which this must not be fed.
 */
function parses(text, options) {
    try {
        evaluate(text, Object.assign({}, options || {}, { lenient: true }));
        return true;
    } catch (e) {
        return false;
    }
}
