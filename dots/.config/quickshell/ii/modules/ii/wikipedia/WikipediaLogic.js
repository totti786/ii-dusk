.pragma library

// Pure parsing and URL policy for WikipediaService. Keeping the response contract
// here makes the service small enough to reason about and lets the native feed/search
// behaviour be tested without constructing a Quickshell process.

var _languageCatalog = [
    { "code": "en", "nativeName": "English", "englishName": "English" },
    { "code": "tr", "nativeName": "Türkçe", "englishName": "Turkish" },
    { "code": "ar", "nativeName": "العربية", "englishName": "Arabic" },
    { "code": "de", "nativeName": "Deutsch", "englishName": "German" },
    { "code": "es", "nativeName": "Español", "englishName": "Spanish" },
    { "code": "fr", "nativeName": "Français", "englishName": "French" },
    { "code": "it", "nativeName": "Italiano", "englishName": "Italian" },
    { "code": "pt", "nativeName": "Português", "englishName": "Portuguese" },
    { "code": "zh", "nativeName": "中文", "englishName": "Chinese" },
    { "code": "ja", "nativeName": "日本語", "englishName": "Japanese" },
    { "code": "ko", "nativeName": "한국어", "englishName": "Korean" },
    { "code": "ru", "nativeName": "Русский", "englishName": "Russian" },
    { "code": "uk", "nativeName": "Українська", "englishName": "Ukrainian" },
    { "code": "pl", "nativeName": "Polski", "englishName": "Polish" },
    { "code": "nl", "nativeName": "Nederlands", "englishName": "Dutch" },
    { "code": "sv", "nativeName": "Svenska", "englishName": "Swedish" },
    { "code": "da", "nativeName": "Dansk", "englishName": "Danish" },
    { "code": "no", "nativeName": "Norsk bokmål", "englishName": "Norwegian" },
    { "code": "fi", "nativeName": "Suomi", "englishName": "Finnish" },
    { "code": "he", "nativeName": "עברית", "englishName": "Hebrew" },
    { "code": "fa", "nativeName": "فارسی", "englishName": "Persian" },
    { "code": "hi", "nativeName": "हिन्दी", "englishName": "Hindi" },
    { "code": "id", "nativeName": "Bahasa Indonesia", "englishName": "Indonesian" },
    { "code": "vi", "nativeName": "Tiếng Việt", "englishName": "Vietnamese" },
    { "code": "el", "nativeName": "Ελληνικά", "englishName": "Greek" },
    { "code": "cs", "nativeName": "Čeština", "englishName": "Czech" },
    { "code": "ro", "nativeName": "Română", "englishName": "Romanian" },
    { "code": "ca", "nativeName": "Català", "englishName": "Catalan" },
    { "code": "hu", "nativeName": "Magyar", "englishName": "Hungarian" }
];

function languageCatalog() {
    return _languageCatalog.slice();
}

function languageForCode(options, code) {
    var normalized = normalizeLanguage(code);
    var source = Array.isArray(options) ? options : _languageCatalog;
    for (var i = 0; i < source.length; i++) {
        if (_text(source[i]?.code).toLowerCase() === normalized)
            return source[i];
    }
    return {
        "code": normalized,
        "nativeName": normalized,
        "englishName": "Wikipedia language",
        "custom": true
    };
}

function languageSearchResults(options, query) {
    var source = Array.isArray(options) ? options : _languageCatalog;
    var needle = _text(query).trim().toLowerCase();
    if (needle.length === 0)
        return source.slice();

    var matches = source.filter(function (item) {
        return [_text(item?.code), _text(item?.nativeName), _text(item?.englishName)]
            .some(function (value) { return value.toLowerCase().indexOf(needle) >= 0; });
    });
    var normalized = normalizeLanguage(needle);
    var known = source.some(function (item) {
        return _text(item?.code).toLowerCase() === normalized;
    });
    if (normalized.length > 0 && !known) {
        matches.push({
            "code": normalized,
            "nativeName": normalized,
            "englishName": "Use this Wikipedia language code",
            "custom": true
        });
    }
    return matches;
}

// Enter from the search field should choose a curated locale when a three-letter
// code prefix also produces a custom-code row. A highlighted row is an explicit
// choice, so it wins after an exact curated code match. Two-letter custom codes
// are treated as exact codes before name-prefix matches, which keeps "ga" from
// silently becoming Hungarian while still keeping "spa" predictable.
function languageSelection(options, query, highlightedIndex) {
    var matches = languageSearchResults(options, query);
    var normalized = _text(query).trim().toLowerCase();
    var exactCurated = matches.find(function (option) {
        return !option.custom && _text(option.code).toLowerCase() === normalized;
    });
    if (exactCurated)
        return exactCurated.code;

    var index = Number(highlightedIndex);
    if (isFinite(index) && index >= 0 && index < matches.length)
        return matches[index].code;

    var exactCustom = matches.find(function (option) {
        return option.custom && _text(option.code).toLowerCase() === normalized;
    });
    if (exactCustom && normalized.length === 2)
        return exactCustom.code;

    var firstCurated = matches.find(function (option) { return !option.custom; });
    if (firstCurated)
        return firstCurated.code;

    return exactCustom ? exactCustom.code : "";
}

function clampReaderFontSize(value, fallback, minimum, maximum) {
    var safeFallback = Number(fallback);
    if (!isFinite(safeFallback))
        safeFallback = 18;
    var low = Number(minimum);
    var high = Number(maximum);
    if (!isFinite(low))
        low = 14;
    if (!isFinite(high))
        high = 28;
    if (high < low) {
        var swap = low;
        low = high;
        high = swap;
    }
    safeFallback = Math.max(low, Math.min(high, Math.round(safeFallback)));
    var number = Number(value);
    if (!isFinite(number))
        return safeFallback;
    return Math.max(low, Math.min(high, Math.round(number)));
}

function adjustReaderFontSize(value, delta, fallback, minimum, maximum) {
    var current = clampReaderFontSize(value, fallback, minimum, maximum);
    var change = Number(delta);
    return clampReaderFontSize(current + (isFinite(change) ? change : 0), fallback, minimum, maximum);
}

function _text(value) {
    return value === undefined || value === null ? "" : String(value);
}

function normalizeLanguage(value) {
    var language = _text(value).trim().toLowerCase();
    return isValidLanguage(language) ? language : "";
}

// Wikimedia language subdomains contain a language code and, in some cases, a
// hyphenated script/variant (for example zh-min-nan or sr-ec). Never let arbitrary
// text become part of a request host.
function isValidLanguage(value) {
    return /^[a-z]{2,3}(?:-[a-z0-9]{2,8})*$/.test(_text(value).trim().toLowerCase());
}

function siteUrl(language) {
    var normalized = normalizeLanguage(language);
    return normalized.length > 0 ? "https://" + normalized + ".wikipedia.org" : "";
}

function featuredPath(dateText) {
    var value = _text(dateText).trim();
    return /^\d{4}\/\d{2}\/\d{2}$/.test(value)
        ? "/api/rest_v1/feed/featured/" + value
        : "";
}

function stripHtml(value) {
    return _text(value)
        .replace(/<[^>]*>/g, "")
        .replace(/&quot;/g, '"')
        .replace(/&#039;/g, "'")
        .replace(/&#39;/g, "'")
        .replace(/&amp;/g, "&")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .replace(/&nbsp;/g, " ")
        .replace(/\s+/g, " ")
        .trim();
}

function pageUrl(language, title) {
    var base = siteUrl(language);
    var value = _text(title).trim();
    if (base.length === 0 || value.length === 0)
        return "";
    return base + "/wiki/" + encodeURIComponent(value).replace(/%20/g, "_");
}

function safePageUrl(url, language) {
    var value = _text(url).trim();
    var base = siteUrl(language);
    if (base.length === 0 || value.length === 0)
        return "";
    if (value.indexOf(base + "/wiki/") !== 0)
        return "";
    // A full URL from Wikimedia may contain a query/hash, but its host and path must
    // stay on the selected wiki before it is handed to xdg-open.
    return /^https:\/\/[a-z]{2,3}(?:-[a-z0-9]{2,8})*\.wikipedia\.org\/wiki\/[^\s]+(?:[?#][^\s]*)?$/i.test(value)
        ? value
        : "";
}

function isCurrentRequest(requestEpoch, currentEpoch, requestToken, currentToken) {
    return Number(requestEpoch) === Number(currentEpoch) && Number(requestToken) === Number(currentToken);
}

// A failed random request has no article title to retry. Preserve that intent so a
// retry cannot silently reload an older article from the previous reader state.
function articleRetryAction(requestKind, articleTitle) {
    if (_text(requestKind) === "random")
        return "random";
    return _text(articleTitle).trim().length > 0 ? "article" : "none";
}

function _json(payload) {
    if (payload && typeof payload === "object")
        return payload;
    try {
        return JSON.parse(_text(payload));
    } catch (error) {
        return null;
    }
}

function _thumbnail(raw) {
    return _text(raw?.thumbnail?.source ?? raw?.thumbnail?.url
        ?? raw?.originalimage?.source ?? raw?.originalimage?.url);
}

function articleFromRaw(raw, language, fallbackTitle) {
    if (!raw || typeof raw !== "object")
        return null;
    var title = _text(raw.normalizedtitle ?? raw.title ?? fallbackTitle).trim().replace(/_/g, " ");
    if (title.length === 0)
        return null;
    var officialUrl = safePageUrl(raw.content_urls?.desktop?.page ?? raw.fullurl, language);
    return {
        "title": title,
        "description": _text(raw.description).trim(),
        "extract": _text(raw.extract ?? raw.tfa_extract).trim(),
        "thumbnail": _thumbnail(raw),
        "url": officialUrl.length > 0 ? officialUrl : pageUrl(language, title),
        "pageid": Number(raw.pageid ?? 0),
        "language": normalizeLanguage(language),
        "views": Number(raw.views ?? 0),
        "rank": Number(raw.rank ?? 0)
    };
}

function parseFeatured(payload, language) {
    var data = _json(payload);
    if (!data)
        return { "article": null, "mostRead": [], "valid": false };

    var article = articleFromRaw(data.tfa, language, "");
    var source = Array.isArray(data.mostread?.articles) ? data.mostread.articles : [];
    var mostRead = [];
    var seen = {};
    for (var i = 0; i < source.length && mostRead.length < 12; i++) {
        var item = articleFromRaw(source[i], language, "");
        if (!item || seen[item.title])
            continue;
        seen[item.title] = true;
        mostRead.push(item);
    }
    return {
        "article": article,
        "mostRead": mostRead,
        "valid": article !== null || mostRead.length > 0
    };
}

function parseSearch(payload, language) {
    var data = _json(payload);
    var source = Array.isArray(data?.query?.search) ? data.query.search : [];
    return source.map(function (item) {
        var title = _text(item?.title).trim();
        return {
            "title": title,
            "pageid": Number(item?.pageid ?? 0),
            "snippet": stripHtml(item?.snippet),
            "words": Number(item?.wordcount ?? 0),
            "url": pageUrl(language, title)
        };
    }).filter(function (item) { return item.title.length > 0; });
}

function parseArticle(payload, language, fallbackTitle) {
    var data = _json(payload);
    var pages = Array.isArray(data?.query?.pages) ? data.query.pages : [];
    if (pages.length === 0 || pages[0]?.missing === true)
        return null;
    return articleFromRaw(pages[0], language, fallbackTitle);
}

function parseRandom(payload) {
    var data = _json(payload);
    var item = Array.isArray(data?.query?.random) ? data.query.random[0] : null;
    return _text(item?.title).trim();
}
