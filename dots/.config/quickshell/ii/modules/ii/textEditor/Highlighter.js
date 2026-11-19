.pragma library

/*
 * Syntax highlighting for the editor: one pass of a language's rule list over the whole text,
 * giving HTML for the Text layer that sits under the (transparent) TextEdit.
 * Rules are tried in order at every position through a single alternation, so the first rule
 * that matches at the leftmost position wins: put comments and strings before everything else.
 */

function words(list) { return "\\b(?:" + list.split(" ").join("|") + ")\\b"; }

var NUM = "\\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|\\d[\\d_]*\\.?\\d*(?:[eE][+-]?\\d+)?)[fFlLuU]*\\b";

var C_KEYWORDS = "if else for while do switch case default break continue return goto sizeof typedef struct union enum static const extern volatile register inline new delete class public private protected virtual override final namespace using template typename try catch throw this nullptr operator friend explicit auto constexpr noexcept";
var C_TYPES = "int long short char float double void unsigned signed bool size_t uint8_t uint16_t uint32_t uint64_t int8_t int16_t int32_t int64_t string vector map set";

var LANGS = {
    python: {
        comment: "#", rules: [
            ["comment", "#[^\\n]*"],
            ["string", "(?:[rRbBfFuU]{0,2})(?:\"\"\"[\\s\\S]*?\"\"\"|'''[\\s\\S]*?'''|\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*')"],
            ["decorator", "@[A-Za-z_][\\w.]*"],
            ["keyword", words("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case")],
            ["constant", words("True False None self cls")],
            ["type", words("int str float bool list dict set tuple bytes object type")],
            ["function", "\\b[A-Za-z_]\\w*(?=\\s*\\()"],
            ["number", NUM]
        ]
    },
    javascript: {
        comment: "//", rules: [
            ["comment", "//[^\\n]*|/\\*[\\s\\S]*?\\*/"],
            ["string", "`(?:[^`\\\\]|\\\\[\\s\\S])*`|\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'"],
            ["keyword", words("break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new of return static super switch this throw try typeof var void while with yield async await from as interface type enum implements readonly declare namespace abstract public private protected")],
            ["constant", words("true false null undefined NaN Infinity")],
            ["type", words("string number boolean any unknown never void object Array Promise Map Set Record")],
            ["function", "\\b[A-Za-z_$][\\w$]*(?=\\s*\\()"],
            ["number", NUM]
        ]
    },
    qml: {
        comment: "//", rules: [
            ["comment", "//[^\\n]*|/\\*[\\s\\S]*?\\*/"],
            ["string", "`(?:[^`\\\\]|\\\\[\\s\\S])*`|\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'"],
            ["keyword", words("import pragma property signal function readonly required component default on as var let const if else for while return new true false null undefined switch case break continue try catch this")],
            ["type", words("int real bool string url color var list double point size rect date font alias")],
            ["tag", "\\b[A-Z]\\w*(?=\\s*\\{)"],
            ["attr", "\\b[a-z]\\w*(?:\\.[a-z]\\w*)*(?=\\s*:)"],
            ["function", "\\b[A-Za-z_]\\w*(?=\\s*\\()"],
            ["number", NUM]
        ]
    },
    c: {
        comment: "//", rules: [
            ["comment", "//[^\\n]*|/\\*[\\s\\S]*?\\*/"],
            ["string", "\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'"],
            ["decorator", "^[ \\t]*#[ \\t]*\\w+"],
            ["keyword", words(C_KEYWORDS)],
            ["type", words(C_TYPES)],
            ["constant", words("true false NULL")],
            ["function", "\\b[A-Za-z_]\\w*(?=\\s*\\()"],
            ["number", NUM]
        ]
    },
    rust: {
        comment: "//", rules: [
            ["comment", "//[^\\n]*|/\\*[\\s\\S]*?\\*/"],
            ["string", "r#*\"[\\s\\S]*?\"#*|b?\"(?:[^\"\\\\]|\\\\[\\s\\S])*\"|b?'(?:[^'\\\\\\n]|\\\\.)'"],
            ["decorator", "#!?\\[[^\\]]*\\]"],
            ["keyword", words("as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait type unsafe use where while")],
            ["constant", words("true false None Some Ok Err")],
            ["type", words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Box")],
            ["function", "\\b[A-Za-z_]\\w*!?(?=\\s*[(<])"],
            ["number", NUM]
        ]
    },
    go: {
        comment: "//", rules: [
            ["comment", "//[^\\n]*|/\\*[\\s\\S]*?\\*/"],
            ["string", "`[^`]*`|\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'"],
            ["keyword", words("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var")],
            ["constant", words("true false nil iota")],
            ["type", words("int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 float32 float64 string bool byte rune error any")],
            ["function", "\\b[A-Za-z_]\\w*(?=\\s*\\()"],
            ["number", NUM]
        ]
    },
    lua: {
        comment: "--", rules: [
            ["comment", "--\\[\\[[\\s\\S]*?\\]\\]|--[^\\n]*"],
            ["string", "\\[\\[[\\s\\S]*?\\]\\]|\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'"],
            ["keyword", words("and break do else elseif end for function goto if in local not or repeat return then until while")],
            ["constant", words("true false nil self")],
            ["function", "\\b[A-Za-z_][\\w.:]*(?=\\s*[({\"'])"],
            ["number", NUM]
        ]
    },
    shell: {
        comment: "#", rules: [
            ["comment", "(?:^|\\s)#[^\\n]*"],
            ["string", "\"(?:[^\"\\\\]|\\\\[\\s\\S])*\"|'[^']*'"],
            ["constant", "\\$(?:\\{[^}]*\\}|[A-Za-z_]\\w*|[0-9@#?$!*-])"],
            ["keyword", words("if then else elif fi for while until do done case esac in function select return exit break continue local export readonly declare source alias unset set shift trap eval exec")],
            ["function", "\\b(?:echo|cd|ls|cat|grep|sed|awk|find|mkdir|rm|cp|mv|chmod|chown|sudo|git|curl|wget|tar|pacman|systemctl|printf|read|test|command)\\b"],
            ["number", NUM]
        ]
    },
    json: {
        comment: "", rules: [
            ["attr", "\"(?:[^\"\\\\\\n]|\\\\.)*\"(?=\\s*:)"],
            ["string", "\"(?:[^\"\\\\\\n]|\\\\.)*\""],
            ["constant", words("true false null")],
            ["number", "-?\\b\\d+\\.?\\d*(?:[eE][+-]?\\d+)?\\b"]
        ]
    },
    yaml: {
        comment: "#", rules: [
            ["comment", "#[^\\n]*"],
            ["attr", "^[ \\t-]*[\\w.\\-\"']+(?=\\s*:(?:\\s|$))"],
            ["string", "\"(?:[^\"\\\\\\n]|\\\\.)*\"|'[^'\\n]*'"],
            ["constant", words("true false null yes no on off ~")],
            ["number", NUM]
        ]
    },
    toml: {
        comment: "#", rules: [
            ["comment", "#[^\\n]*"],
            ["tag", "^[ \\t]*\\[+[^\\]\\n]*\\]+"],
            ["attr", "^[ \\t]*[\\w.\\-\"']+(?=\\s*=)"],
            ["string", "\"\"\"[\\s\\S]*?\"\"\"|\"(?:[^\"\\\\\\n]|\\\\.)*\"|'[^'\\n]*'"],
            ["constant", words("true false")],
            ["number", NUM]
        ]
    },
    css: {
        comment: "", rules: [
            ["comment", "/\\*[\\s\\S]*?\\*/"],
            ["string", "\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'"],
            ["decorator", "@[\\w-]+"],
            ["tag", "[.#]?[A-Za-z_][\\w-]*(?=[^{};]*\\{)"],
            ["attr", "[A-Za-z-]+(?=\\s*:)"],
            ["number", "#[0-9a-fA-F]{3,8}\\b|-?\\b\\d+\\.?\\d*(?:px|em|rem|%|vh|vw|s|ms|deg)?"]
        ]
    },
    html: {
        comment: "", rules: [
            ["comment", "<!--[\\s\\S]*?-->"],
            ["string", "\"[^\"]*\"|'[^']*'"],
            ["tag", "</?[A-Za-z][\\w:-]*|/?>"],
            ["attr", "\\b[A-Za-z_:][\\w:.-]*(?=\\s*=)"],
            ["constant", "&\\w+;"]
        ]
    },
    markdown: {
        comment: "", rules: [
            ["string", "```[\\s\\S]*?```|`[^`\\n]+`"],
            ["keyword", "^#{1,6}[ \\t].*$"],
            ["comment", "^>.*$"],
            ["decorator", "^[ \\t]*(?:[-*+]|\\d+\\.)[ \\t]"],
            ["function", "\\[[^\\]\\n]*\\]\\([^)\\n]*\\)"],
            ["constant", "\\*\\*[^*\\n]+\\*\\*|__[^_\\n]+__"]
        ]
    },
    diff: {
        comment: "", rules: [
            ["decorator", "^@@.*$"],
            ["string", "^\\+.*$"],
            ["keyword", "^-.*$"],
            ["comment", "^(?:diff|index|---|\\+\\+\\+).*$"]
        ]
    },
    ini: {
        comment: ";", rules: [
            ["comment", "^[ \\t]*[;#][^\\n]*"],
            ["tag", "^[ \\t]*\\[[^\\]\\n]*\\]"],
            ["attr", "^[ \\t]*[\\w.\\-]+(?=\\s*=)"],
            ["string", "\"[^\"\\n]*\""],
            ["number", NUM]
        ]
    },
    plain: { comment: "", rules: [] }
};

LANGS.typescript = LANGS.javascript;
LANGS.cpp = LANGS.c;
LANGS.java = LANGS.c;

var EXT = {
    py: "python", pyw: "python", js: "javascript", mjs: "javascript", cjs: "javascript", jsx: "javascript", ts: "typescript", tsx: "typescript",
    qml: "qml", c: "c", h: "c", cc: "cpp", cpp: "cpp", hpp: "cpp", cxx: "cpp", java: "java", kt: "java", rs: "rust", go: "go", lua: "lua",
    sh: "shell", bash: "shell", zsh: "shell", fish: "shell", json: "json", jsonc: "json", yaml: "yaml", yml: "yaml", toml: "toml",
    css: "css", scss: "css", html: "html", htm: "html", xml: "html", svg: "html", md: "markdown", markdown: "markdown",
    diff: "diff", patch: "diff", ini: "ini", conf: "ini", cfg: "ini", desktop: "ini", service: "ini", rasi: "css"
};

var NAMES = {
    python: "Python", javascript: "JavaScript", typescript: "TypeScript", qml: "QML", c: "C", cpp: "C++", java: "Java", rust: "Rust", go: "Go", lua: "Lua",
    shell: "Shell", json: "JSON", yaml: "YAML", toml: "TOML", css: "CSS", html: "HTML/XML", markdown: "Markdown", diff: "Diff", ini: "Config", plain: "Plain text"
};

function languageFor(fileName) {
    var name = String(fileName || "").toLowerCase();
    var base = name.split("/").pop();
    if (base === "makefile" || base === "dockerfile" || base === "pkgbuild" || base === ".bashrc" || base === ".zshrc" || base === ".profile") return "shell";
    var dot = base.lastIndexOf(".");
    if (dot < 0) return "plain";
    return EXT[base.slice(dot + 1)] || "plain";
}

function languageName(lang) { return NAMES[lang] || "Plain text"; }
function commentPrefix(lang) { return (LANGS[lang] || LANGS.plain).comment; }

var compiled = {};

function compile(lang) {
    if (compiled[lang]) return compiled[lang];
    var def = LANGS[lang] || LANGS.plain;
    var classes = [];
    var parts = [];
    for (var i = 0; i < def.rules.length; ++i) {
        classes.push(def.rules[i][0]);
        // Every rule is exactly one capturing group (inner groups must be non-capturing)
        var src = def.rules[i][1];
        parts.push("(" + src + ")");
    }
    var re = parts.length > 0 ? new RegExp(parts.join("|"), "gm") : null;
    compiled[lang] = { re: re, classes: classes };
    return compiled[lang];
}

function esc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// Tabs are widened to the next tab stop so the Text layer lines up with the TextEdit above it
function expandTabs(s, startCol, tabSize) {
    if (s.indexOf("\t") < 0) return s;
    var out = "", col = startCol;
    for (var i = 0; i < s.length; ++i) {
        var ch = s[i];
        if (ch === "\t") { var n = tabSize - (col % tabSize); out += new Array(n + 1).join(" "); col += n; }
        else if (ch === "\n") { out += ch; col = 0; }
        else { out += ch; col++; }
    }
    return out;
}

/// HTML for `text`; `colors` maps a class name to a colour, "" is plain text
function highlight(text, lang, colors, tabSize) {
    var c = compile(lang);
    var out = [];
    var col = 0;
    function emit(chunk, cls) {
        if (chunk.length === 0) return;
        var x = expandTabs(chunk, col, tabSize);
        var nl = x.lastIndexOf("\n");
        col = nl >= 0 ? x.length - nl - 1 : col + x.length;
        var colour = cls ? colors[cls] : "";
        var e = esc(x);
        out.push(colour ? "<span style=\"color:" + colour + "\">" + e + "</span>" : e);
    }
    if (!c.re) { emit(text, ""); return out.join(""); }
    var re = c.re, last = 0, m;
    re.lastIndex = 0;
    while ((m = re.exec(text)) !== null) {
        if (m[0].length === 0) { re.lastIndex++; continue; }
        if (m.index > last) emit(text.slice(last, m.index), "");
        var cls = "";
        for (var g = 1; g <= c.classes.length; ++g) if (m[g] !== undefined) { cls = c.classes[g - 1]; break; }
        emit(m[0], cls);
        last = m.index + m[0].length;
    }
    if (last < text.length) emit(text.slice(last), "");
    return out.join("");
}
