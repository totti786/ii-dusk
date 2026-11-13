.pragma library

// Discord's markdown as Qt rich text. The helper has already turned <@id>, <#id> and <@&id> into marked text
// (U+E000..E003) and left custom emoji as <:name:id>; everything else in a message is raw.

const MENTION_OPEN = "", MENTION_CLOSE = "", CHANNEL_OPEN = "", CHANNEL_CLOSE = "";

function escapeHtml(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function pad(n) { return n < 10 ? "0" + n : "" + n; }

function relative(seconds) {
    const diff = seconds - Date.now() / 1000;
    const abs = Math.abs(diff);
    const units = [[31536000, "year"], [2592000, "month"], [86400, "day"], [3600, "hour"], [60, "minute"]];
    for (const [size, name] of units) {
        if (abs >= size) {
            const n = Math.floor(abs / size);
            const text = n + " " + name + (n === 1 ? "" : "s");
            return diff < 0 ? text + " ago" : "in " + text;
        }
    }
    return diff < 0 ? "just now" : "in a moment";
}

/** <t:1700000000:R> and friends */
function timestamp(seconds, style) {
    const d = new Date(seconds * 1000);
    const time = pad(d.getHours()) + ":" + pad(d.getMinutes());
    switch (style) {
    case "t": return time;
    case "T": return time + ":" + pad(d.getSeconds());
    case "d": return pad(d.getDate()) + "/" + pad(d.getMonth() + 1) + "/" + d.getFullYear();
    case "D": return d.toDateString();
    case "F": return d.toDateString() + " " + time;
    case "R": return relative(seconds);
    default: return d.toDateString() + " " + time;
    }
}

function emojiUrl(id, animated, size) {
    return "https://cdn.discordapp.com/emojis/" + id + "." + (animated ? "gif" : "png") + "?size=" + size;
}

const EMOJI_ONLY = /^(?:\s|<a?:\w+:\d+>|\p{Extended_Pictographic}|‍|️|\p{Regional_Indicator})+$/u;

/** A message of nothing but emoji is shown large. */
function isJumbo(content) {
    const s = String(content || "").trim();
    if (s.length === 0 || s.length > 200 || !EMOJI_ONLY.test(s))
        return false;
    const count = (s.match(/<a?:\w+:\d+>|\p{Extended_Pictographic}|\p{Regional_Indicator}/gu) || []).length;
    return count > 0 && count <= 27;
}

/**
 * opts: { link, mention, channel, codeBg, codeFg, quote, spoilerBg, reveal, emojiSize }
 * Colours are CSS strings.
 */
function render(content, opts) {
    const o = Object.assign({ link: "#8ab4f8", mention: "#8ab4f8", channel: "#8ab4f8", codeBg: "#00000040", codeFg: "inherit",
        quote: "#808080", spoilerBg: "#404040", reveal: false, emojiSize: 22 }, opts || {});
    let text = String(content || "");
    const stash = [];
    const keep = html => { stash.push(html); return "" + (stash.length - 1) + ""; };

    // code first, so nothing inside it is touched
    text = text.replace(/```(?:[\w+#-]*\n)?([\s\S]*?)```/g, (m, code) =>
        keep('<pre style="background-color:' + o.codeBg + '; color:' + o.codeFg + ';">' + escapeHtml(code.replace(/^\n|\n$/g, "")) + "</pre>"));
    text = text.replace(/``([^`]+)``|`([^`\n]+)`/g, (m, a, b) =>
        keep('<code style="background-color:' + o.codeBg + '; color:' + o.codeFg + ';">&nbsp;' + escapeHtml(a || b) + "&nbsp;</code>"));

    text = escapeHtml(text);

    // links: [label](url), <url>, bare url
    text = text.replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, (m, label, url) =>
        keep('<a href="' + url + '" style="color:' + o.link + '">' + label + "</a>"));
    text = text.replace(/&lt;(https?:\/\/[^\s&]+)&gt;/g, (m, url) => keep('<a href="' + url + '" style="color:' + o.link + '">' + url + "</a>"));
    text = text.replace(/(^|[\s(])(https?:\/\/[^\s<]+[^\s<.,;:!?)\]])/g, (m, lead, url) =>
        lead + keep('<a href="' + url + '" style="color:' + o.link + '">' + url + "</a>"));

    // custom emoji and timestamps
    const jumbo = isJumbo(content);
    const size = jumbo ? 48 : o.emojiSize;
    text = text.replace(/&lt;(a?):(\w+):(\d+)&gt;/g, (m, anim, name, id) =>
        keep('<img src="' + emojiUrl(id, anim === "a", size * 2) + '" width="' + size + '" height="' + size + '" alt=":' + name + ':">'));
    text = text.replace(/&lt;t:(\d+)(?::([tTdDfFR]))?&gt;/g, (m, ts, style) => keep(timestamp(Number(ts), style || "f")));

    // inline styles, longest markers first
    const wrap = (re, open, close) => { text = text.replace(re, (m, inner) => open + inner + close); };
    text = text.replace(/\|\|([\s\S]+?)\|\|/g, (m, inner) => o.reveal
        ? '<span style="background-color:' + o.spoilerBg + ';">' + inner + "</span>"
        : '<span style="background-color:' + o.spoilerBg + '; color:' + o.spoilerBg + ';">' + inner + "</span>");
    wrap(/\*\*\*([\s\S]+?)\*\*\*/g, "<b><i>", "</i></b>");
    wrap(/\*\*([\s\S]+?)\*\*/g, "<b>", "</b>");
    wrap(/__([\s\S]+?)__/g, "<u>", "</u>");
    wrap(/\*(?!\s)([^*\n]+?)\*/g, "<i>", "</i>");
    text = text.replace(/(^|[^\w])_(?!\s)([^_\n]+?)_(?!\w)/g, "$1<i>$2</i>");
    wrap(/~~([\s\S]+?)~~/g, "<s>", "</s>");

    // mentions marked by the helper
    text = text.split(MENTION_OPEN).join('<span style="color:' + o.mention + '; background-color:' + o.mention + '22;"><b>&nbsp;')
        .split(MENTION_CLOSE).join("&nbsp;</b></span>")
        .split(CHANNEL_OPEN).join('<span style="color:' + o.channel + ';"><b>')
        .split(CHANNEL_CLOSE).join("</b></span>");

    // block lines: quotes, headings, bullets
    const lines = text.split("\n");
    const out = [];
    let multiQuote = false;
    for (let line of lines) {
        if (/^&gt;&gt;&gt; ?/.test(line)) { multiQuote = true; line = line.replace(/^&gt;&gt;&gt; ?/, ""); }
        if (multiQuote || /^&gt; ?/.test(line)) {
            line = line.replace(/^&gt; ?/, "");
            out.push('<span style="color:' + o.quote + ';">&#9475; ' + line + "</span>");
            continue;
        }
        let h = line.match(/^(#{1,3}) (.+)$/);
        if (h) { out.push("<b style=\"font-size:" + (h[1].length === 1 ? "large" : "medium") + ";\">" + h[2] + "</b>"); continue; }
        line = line.replace(/^(\s*)[-*] /, "$1&bull; ");
        out.push(line);
    }
    text = out.join("<br>");

    // put the stashed pieces back (they can nest inside each other: link text, never code)
    for (let pass = 0; pass < 3; ++pass)
        text = text.replace(/(\d+)/g, (m, i) => stash[Number(i)]);
    return text;
}

/** One-line plain text of a message for reply previews and the like. */
function plain(content) {
    return String(content || "").split(MENTION_OPEN).join("").split(MENTION_CLOSE).join("")
        .split(CHANNEL_OPEN).join("").split(CHANNEL_CLOSE).join("").replace(/<a?:(\w+):\d+>/g, ":$1:");
}

function formatTime(iso) {
    const d = new Date(iso);
    if (isNaN(d.getTime()))
        return "";
    const now = new Date();
    const time = pad(d.getHours()) + ":" + pad(d.getMinutes());
    if (d.toDateString() === now.toDateString())
        return time;
    const y = new Date(now.getTime() - 86400000);
    if (d.toDateString() === y.toDateString())
        return "Yesterday " + time;
    return pad(d.getDate()) + "/" + pad(d.getMonth() + 1) + "/" + d.getFullYear() + " " + time;
}

function dayLabel(iso) {
    const d = new Date(iso);
    return isNaN(d.getTime()) ? "" : d.toDateString();
}

function humanSize(bytes) {
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1048576) return (bytes / 1024).toFixed(1) + " KB";
    return (bytes / 1048576).toFixed(1) + " MB";
}
