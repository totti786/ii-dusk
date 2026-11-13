import QtQuick
import QtTest
import "../../modules/ii/wikipedia/WikipediaLogic.js" as Logic

TestCase {
    name: "WikipediaLogic"

    function test_language_and_url_policy() {
        compare(Logic.normalizeLanguage(" EN "), "en");
        verify(Logic.isValidLanguage("zh-min-nan"));
        verify(!Logic.isValidLanguage("en.wikipedia.org"));
        verify(!Logic.isValidLanguage("en/../../bad"));
        compare(Logic.siteUrl("tr"), "https://tr.wikipedia.org");
        compare(Logic.siteUrl("bad host"), "");
        compare(Logic.pageUrl("en", "Ada Lovelace"), "https://en.wikipedia.org/wiki/Ada_Lovelace");
        verify(Logic.safePageUrl("https://en.wikipedia.org/wiki/Ada_Lovelace", "en").length > 0);
        compare(Logic.safePageUrl("https://evil.example/wiki/Ada_Lovelace", "en"), "");
    }

    function test_stale_request_and_retry_policy() {
        verify(Logic.isCurrentRequest(4, 4, 9, 9));
        verify(!Logic.isCurrentRequest(3, 4, 9, 9));
        verify(!Logic.isCurrentRequest(4, 4, 8, 9));
        // clear() and language changes advance the epoch, while a replacement in the
        // same lane advances its token; either response must be ignored.
        compare(Logic.articleRetryAction("random", ""), "random");
        compare(Logic.articleRetryAction("article", "Earth"), "article");
        compare(Logic.articleRetryAction("article", ""), "none");
    }

    function test_language_catalog_search_and_code_entry() {
        const catalog = Logic.languageCatalog();
        verify(catalog.length >= 25);
        const arabic = catalog.find(option => option.code === "ar");
        compare(arabic.nativeName, "العربية");
        compare(arabic.englishName, "Arabic");
        const turkish = catalog.find(option => option.code === "tr");
        compare(turkish.nativeName, "Türkçe");
        compare(turkish.englishName, "Turkish");

        const byEnglishPrefix = Logic.languageSearchResults(catalog, "spa");
        compare(byEnglishPrefix.length, 2);
        compare(byEnglishPrefix[0].code, "es");
        compare(byEnglishPrefix[1].code, "spa");
        verify(byEnglishPrefix[1].custom);
        compare(Logic.languageSelection(catalog, "spa", -1), "es");
        compare(Logic.languageSelection(catalog, "spa", 1), "spa");
        compare(Logic.languageSelection(catalog, "ga", -1), "ga");
        compare(Logic.languageSelection(catalog, "tr", -1), "tr");

        const byNative = Logic.languageSearchResults(catalog, "العربية");
        compare(byNative[0].code, "ar");
        const custom = Logic.languageSearchResults(catalog, "xx-test");
        compare(custom.length, 1);
        compare(custom[0].code, "xx-test");
        verify(custom[0].custom);
    }

    function test_reader_font_size_clamps_and_steps() {
        compare(Logic.clampReaderFontSize(10, 18, 14, 28), 14);
        compare(Logic.clampReaderFontSize(31, 18, 14, 28), 28);
        compare(Logic.clampReaderFontSize("not-a-number", 18, 14, 28), 18);
        compare(Logic.adjustReaderFontSize(27, 1, 18, 14, 28), 28);
        compare(Logic.adjustReaderFontSize(15, -1, 18, 14, 28), 14);
        compare(Logic.adjustReaderFontSize(18, "bad", 18, 14, 28), 18);
    }

    function test_featured_feed_requires_real_content() {
        const feed = {
            "tfa": {
                "title": "Featured title",
                "description": "A short description",
                "extract": "A real extract.",
                "thumbnail": { "source": "https://upload.wikimedia.org/a.jpg" },
                "content_urls": { "desktop": { "page": "https://en.wikipedia.org/wiki/Featured_title" } }
            },
            "mostread": {
                "articles": [
                    { "title": "Featured title", "views": 10 },
                    { "title": "Second title", "views": 9 }
                ]
            }
        };
        const parsed = Logic.parseFeatured(feed, "en");
        verify(parsed.valid);
        compare(parsed.article.title, "Featured title");
        compare(parsed.article.thumbnail, "https://upload.wikimedia.org/a.jpg");
        compare(parsed.mostRead.length, 2);
        compare(parsed.mostRead[0].title, "Featured title");
        compare(Logic.parseFeatured({ "tfa": null, "mostread": { "articles": [] } }, "en").valid, false);
    }

    function test_search_and_article_parsing_is_plain_and_safe() {
        const search = Logic.parseSearch({
            "query": { "search": [
                { "title": "A & B", "pageid": 4, "snippet": "A <span class=\"searchmatch\">useful</span> result", "wordcount": 20 }
            ] }
        }, "en");
        compare(search.length, 1);
        compare(search[0].snippet, "A useful result");
        compare(search[0].url, "https://en.wikipedia.org/wiki/A_%26_B");

        const article = Logic.parseArticle({
            "query": { "pages": [{
                "title": "An article",
                "extract": "Readable text",
                "fullurl": "https://evil.example/article"
            }] }
        }, "en", "An article");
        compare(article.title, "An article");
        compare(article.url, "https://en.wikipedia.org/wiki/An_article");
        compare(Logic.parseArticle({ "query": { "pages": [{ "missing": true }] } }, "en", "Missing"), null);
    }
}
