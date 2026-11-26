pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Translation for standalone apps: the shell's tr() over the same locale files,
 * without the language scanner processes. en_US is the source language, so it
 * reads nothing (the shell avoids retaining the 1.26 MB en_US.json the same way).
 *
 * This is the only service apps/ provides; shared widgets that import qs.services
 * resolve here, and any other service name stays undefined instead of booting.
 */
Singleton {
    id: root

    readonly property string translationKeepSuffix: "/*keep*/"
    readonly property string languageCode: {
        const configLang = Config.options?.language?.ui ?? "auto";
        return configLang !== "auto" ? configLang : Qt.locale().name;
    }
    readonly property bool isSource: root.languageCode === "en_US"
    property var translations: ({})

    FileView {
        path: root.isSource ? "" : Quickshell.shellPath(`translations/${root.languageCode}.json`)
        onLoaded: {
            try {
                root.translations = JSON.parse(text());
            } catch (e) {
                console.warn("[apps Translation] unreadable", root.languageCode, e);
            }
        }
    }

    // Dates follow the interface language. English keeps the system's own date locale.
    readonly property bool isEnglish: root.languageCode.startsWith("en")
    readonly property bool isArabic: root.languageCode.startsWith("ar")
    readonly property var locale: root.isEnglish ? Qt.locale() : Qt.locale(root.languageCode)

    // `format` is a pattern ("ddd d MMM") or a Locale format type, which gives the date alone.
    function formatDate(date, format): string {
        if (date === undefined || date === null)
            return "";
        const value = date instanceof Date ? date : new Date(date);
        if (isNaN(value.getTime()))
            return "";
        if (typeof format !== "string")
            return root.westernDigits(value.toLocaleDateString(root.locale, format ?? Locale.LongFormat));
        if (!root.isArabic)
            return root.westernDigits(root.locale.toString(value, format));
        // Arabic writes the day before the month, and has its own comma.
        const ordered = format.replace(/(M{3,4}) (d{1,2})(?!d)/, "$2 $1");
        return root.westernDigits(root.locale.toString(value, ordered)).replace(/,/g, "\u060c");
    }

    // The shell assembles clocks and ranges from plain numbers, so formatted text
    // uses the same digits rather than the locale's.
    function westernDigits(text): string {
        return String(text).replace(/[\u0660-\u0669\u06f0-\u06f9]/g, c => String(c.charCodeAt(0) & 0xf));
    }

    // For clock times built where the locale is out of reach.
    function dayMarks(text): string {
        if (root.isEnglish)
            return text;
        return String(text).replace(/\b(AM|PM)\b/gi, mark => mark.toUpperCase() === "AM" ? root.locale.amText : root.locale.pmText);
    }

    function dayName(day, format): string {
        return root.locale.dayName(day, format ?? Locale.LongFormat);
    }

    // Shortens a day or month name. Arabic names cannot be cut: the first letters
    // are the article, the same for every weekday.
    function clip(name, length): string {
        return root.isArabic ? name : name.slice(0, length);
    }

    // The calendar's own locale setting only applies while the interface is in English.
    function calendarLocale(configured): string {
        return root.isEnglish ? configured : root.languageCode;
    }

    function tr(text) {
        if (!text)
            return "";
        const key = text.toString();
        let translation = root.translations[key];
        if (!translation)
            return key;
        if (translation.endsWith(root.translationKeepSuffix))
            translation = translation.substring(0, translation.length - root.translationKeepSuffix.length).trim();
        return translation;
    }
}
