pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    property var translations: ({})
    property var generatedTranslations: ({})
    property var availableLanguages: ["en_US"]
    property var availableGeneratedLanguages: []
    property var allAvailableLanguages: {
        const combined = new Set([...root.availableLanguages, ...root.availableGeneratedLanguages]);
        return Array.from(combined).sort();
    }
    property bool isScanning: scanLanguagesProcess.running
    property bool isLoading: false
    property string translationKeepSuffix: "/*keep*/"
    property string translationsDir: Quickshell.shellPath("translations")
    property string generatedTranslationsDir: Directories.shellConfig + "/translations"
    // Source language (en_US) is an identity map except for one key; keeping it inline
    // avoids reading and retaining the 1.26 MB en_US.json dictionary in V4/FileView.
    readonly property var sourceOverrides: ({
        "A pass from a wallet app: the device's name set huge and cropped behind a scalloped seal and the battery.": "A pass from a wallet app: the device's name set huge and cropped behind a flower badge and the battery."
    })

    property string languageCode: {
        var configLang = Config?.options.language.ui ?? "auto";

        if (configLang !== "auto")
            return configLang;

        return Qt.locale().name;
    }

    // Right-to-left languages. Windows mirror their layouts from this (contentItem.LayoutMirroring).
    readonly property var rtlLanguages: ["ar", "he", "iw", "fa", "ur", "ps", "yi", "dv", "ckb", "ug", "sd"]
    readonly property bool isRtl: {
        const forced = Config?.options.language.direction ?? "auto";
        if (forced === "rtl") return true;
        if (forced === "ltr") return false;
        return root.rtlLanguages.includes(root.languageCode.split(/[_-]/)[0].toLowerCase());
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

    TranslationScanner {
        id: scanLanguagesProcess
        translationsDir: root.translationsDir
        onLanguagesScanned: (languages) => {
            root.availableLanguages = [...languages];
            translationFileView.reread();
        }
    }

    TranslationScanner {
        id: scanGeneratedLanguagesProcess
        translationsDir: root.generatedTranslationsDir
        fallbackLanguages: []
        onLanguagesScanned: (languages) => {
            root.availableGeneratedLanguages = [...languages];
            generatedTranslationFileView.reread();
        }
    }

    onLanguageCodeChanged: {
        print("[Translation] Language changed to", root.languageCode);
        translationFileView.languageCode = root.languageCode;
        generatedTranslationFileView.languageCode = root.languageCode;
        translationFileView.reread();
        generatedTranslationFileView.reread();
    }

    TranslationReader {
        id: translationFileView
        translationsDir: root.translationsDir
        languageCode: root.languageCode
        onContentLoaded: (data) => {
            Qt.callLater(() => {
                // The English file maps every string to itself, and tr() already falls back to
                // the key. Keeping its ~15,000 entries only costs memory, so drop them.
                root.translations = root.languageCode.startsWith("en") ? ({}) : data;
                root.isLoading = false;
            });
        }
    }

    TranslationReader {
        id: generatedTranslationFileView
        translationsDir: root.generatedTranslationsDir
        languageCode: root.languageCode
        onContentLoaded: (data) => {
            Qt.callLater(() => {
                root.generatedTranslations = data;
                root.isLoading = false;
            });
        }
    }

    // A locale file generated at runtime (AiTranslation) joins the language list.
    function rescan() {
        scanLanguagesProcess.running = false;
        scanLanguagesProcess.running = true;
    }

    function tr(text) {
        // Special cases
        if (!text) return "";
        var key = text.toString();
        if (root.isLoading || (!root?.translations?.hasOwnProperty(key) && !root?.generatedTranslations?.hasOwnProperty(key)))
            return key;
        
        // Normal cases
        var translation = root.translations[key] || root.generatedTranslations[key] || key;
        // print(key, "-> [", root.translations[key], root.generatedTranslations[key], key, "] ->", translation);
        if (translation.endsWith(root.translationKeepSuffix)) {
            translation = translation.substring(0, translation.length - root.translationKeepSuffix.length).trim();
        }
        return translation;
    }

    component TranslationScanner: Process {
        id: translationScanner
        required property string translationsDir
        // Reported when the directory cannot be listed at all. The shell's own catalogue always
        // has English; a user override directory that does not exist yet has nothing.
        property var fallbackLanguages: ["en_US"]
        signal languagesScanned(var languages)

        command: ["find", translationScanner.translationsDir, "-name", "*.json", "-exec", "basename", "{}", ".json", ";"]
        running: true

        stdout: StdioCollector {
            id: languagesCollector
            onStreamFinished: {
                const output = languagesCollector.text;
                const files = output.trim().split('\n').map(f => f.trim());
                translationScanner.languagesScanned(files);
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                translationScanner.languagesScanned(translationScanner.fallbackLanguages);
            }
        }
    }

    component TranslationReader: FileView {
        id: translationReader
        required property string translationsDir
        property string languageCode: root.languageCode
        signal contentLoaded(var data)

        function reread() { // Proper reload in case the file was incorrect before
            translationReader.path = "";
            if (translationReader === translationFileView
                    && (translationReader.languageCode === "en_US" || translationReader.languageCode === "en")) {
                translationReader.contentLoaded(Object.assign({}, root.sourceOverrides));
                return;
            }
            const availableLanguages = translationReader === generatedTranslationFileView
                ? root.availableGeneratedLanguages
                : root.availableLanguages;
            // An exact match wins; otherwise another region of the same language
            // (ar_SY reads ar_SA) is better than showing English.
            const wanted = translationReader.languageCode;
            const code = (availableLanguages ?? []).includes(wanted)
                ? wanted
                : (availableLanguages ?? []).find(l => l.split("_")[0] === wanted.split("_")[0]);
            if (!code) {
                translationReader.contentLoaded({});
                return;
            }
            translationReader.path = `${translationReader.translationsDir}/${code}.json`;
            translationReader.reload();
        }
        path: ""

        onLoaded: {
            var textContent = "";
            try {
                textContent = text();
                var jsonData = JSON.parse(textContent);
                translationReader.contentLoaded(jsonData);
            } catch (e) {
                console.log("[Translation] Failed to load translations:", e);
                translationReader.contentLoaded({});
            } finally {
                textContent = "";
                // Clear path so FileView releases its QByteArray/QString file buffers immediately.
                translationReader.path = "";
            }
        }
        onLoadFailed: error => {
            translationReader.path = "";
            translationReader.contentLoaded({});
        }
    }
}
