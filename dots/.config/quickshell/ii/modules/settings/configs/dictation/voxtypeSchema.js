.pragma library

// Pure helpers for Voxtype's settings: no QML, so scripts/tests can run them.

/** Keys the settings page draws by hand; the generated list leaves them out. */
var handDrawn = [
    "whisper.language", "whisper.translate", "whisper.initial_prompt",
    "output.mode", "output.paste_keys", "output.paste_keys_terminal", "output.type_delay_ms",
    "output.auto_submit", "output.shift_enter_newlines", "output.append_text",
    "output.restore_clipboard", "output.fallback_to_clipboard", "output.post_process.command",
    "text.filter_filler_words", "text.spoken_punctuation", "text.format_numbers",
    "text.collapse_restarts", "text.repair_sentence_breaks", "text.smart_auto_submit",
    "audio.pause_media", "audio.duck_media", "audio.duck_media_volume_percent", "audio.duck_media_fade_ms",
    "audio.feedback.enabled", "audio.feedback.theme", "audio.feedback.volume",
    "vad.enabled", "vad.threshold",
    "history.enabled", "history.retention_days", "history.record_app", "history.record_window_title",
    "history.exclude_apps",
    "output.notification.on_transcription", "output.notification.on_no_speech", "output.notification.show_edits"
];

// Left out of the page: what the shell owns (its own hotkeys, indicator, tray,
// recording cap and daemon flags), meetings, remote services and their keys, and
// the raw ALSA device list.
var excludedKey = new RegExp([
    "^(hotkey|osd|tray|status|omarchy|meeting|soniox)\\.",
    "^(engine|state_file)$",
    "\\.(model|threads|language|on_demand_loading)$",
    "^whisper\\.(mode|secondary_model|max_loaded_models|cold_model_timeout_secs|whisper_cli_path)$",
    "api_key", "token", "remote_", "endpoint",
    "^audio\\.(device|sample_rate|max_duration_secs)$",
    "^output\\.file_(path|mode)$"
].join("|"));

/** Schema entries worth a generated row for the engine in use. */
function extras(keys, engine) {
    return (keys || []).filter(function (entry) {
        return entry.compiled !== false
            && (!entry.engine || entry.engine === engine)
            && handDrawn.indexOf(entry.key) === -1
            && !excludedKey.test(entry.key);
    });
}

/** Section names of `entries`, in the order they first appear. */
function sections(entries) {
    var seen = [];
    (entries || []).forEach(function (entry) {
        if (seen.indexOf(entry.section) === -1)
            seen.push(entry.section);
    });
    return seen;
}

/** Engines this build has, from the schema. */
function compiledEngines(keys) {
    var seen = [];
    (keys || []).forEach(function (entry) {
        if (entry.engine && entry.compiled !== false && seen.indexOf(entry.engine) === -1)
            seen.push(entry.engine);
    });
    return seen;
}

/** `voxtype info models --json` -> a flat list for the compiled engines. */
function models(info, engines) {
    var list = [];
    var all = (info && info.engines) || {};
    (engines || []).forEach(function (engine) {
        ((all[engine] && all[engine].models) || []).forEach(function (model) {
            list.push({
                engine: engine,
                name: model.name,
                installed: model.installed === true,
                downloadable: model.downloadable !== false,
                downloadArg: model.download_arg || model.name
            });
        });
    });
    return list;
}

/** The file under voxtype's models folder, or "" for a model the shell should not delete. */
function modelFile(engine, name) {
    if (!name || name.indexOf("/") !== -1 || name.charAt(0) === ".")
        return "";
    if (engine === "whisper")
        return "ggml-" + name + ".bin";
    return /\.gguf$/.test(name) ? name : "";
}

/** The multilingual twin of an English-only Whisper model, or "". */
function multilingualTwin(model) {
    return /\.en$/.test(model || "") ? model.slice(0, -3) : "";
}

/**
 * "auto", one code, or several comma-separated: normalised, or "" when it is not
 * that. Voxtype accepts any text here and only fails later, while transcribing.
 */
function languageList(text) {
    var codes = String(text || "").toLowerCase().split(",").map(function (code) {
        return code.trim();
    }).filter(function (code) {
        return code.length > 0;
    });
    var valid = codes.length > 0 && codes.every(function (code) {
        return /^[a-z]{2,3}$/.test(code) || (code === "auto" && codes.length === 1);
    });
    return valid ? codes.join(",") : "";
}

/**
 * Whisper punctuates in the style of the text it is primed with, and its
 * multilingual models are noticeably worse at commas and accents outside English
 * without that nudge. Each sample is a short, ordinary sentence carrying the
 * punctuation the language actually uses.
 */
var punctuationSamples = {
    "fr": "Bonjour, voici un exemple : des virgules, des points, et des questions ?",
    "es": "Hola, aquí va un ejemplo: comas, puntos, y preguntas. ¿Verdad?",
    "de": "Guten Tag, hier ein Beispiel: Kommas, Punkte, und Fragen?",
    "it": "Buongiorno, ecco un esempio: virgole, punti, e domande?",
    "pt": "Olá, aqui está um exemplo: vírgulas, pontos, e perguntas?",
    "nl": "Goedendag, hier een voorbeeld: komma's, punten, en vragen?",
    "pl": "Dzień dobry, oto przykład: przecinki, kropki, i pytania?",
    "ru": "Здравствуйте, вот пример: запятые, точки и вопросы?",
    "ca": "Bon dia, aquí teniu un exemple: comes, punts, i preguntes?",
    "sv": "God dag, här är ett exempel: kommatecken, punkter, och frågor?",
    "en": "Hello, here is an example: commas, periods, and questions?"
};

/** Auto-detection gets no sample: priming for the wrong language costs accuracy. */
function sampleFor(language) {
    var primary = String(language || "").split(",")[0].trim();
    return punctuationSamples.hasOwnProperty(primary) ? punctuationSamples[primary] : "";
}

/** The prompt to write after a language change, or null to keep the user's own. */
function promptAfterLanguage(prompt, language) {
    var own = Object.keys(punctuationSamples).every(function (code) {
        return punctuationSamples[code] !== prompt;
    });
    if (prompt && own)
        return null;
    return sampleFor(language);
}

/** The config key of the word replacement for `from`. */
function replacementKey(from) {
    return 'text.replacements."' + String(from).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
}

/**
 * The command that writes one setting. An empty value restores the default.
 * Voxtype's CLI stores a language list as one string, which its engine then
 * rejects as an unknown language, so lists go through the shell's own writer.
 */
function writeCommand(key, value, configScript) {
    var text = value === null || value === undefined ? "" : String(value);
    if (text.length === 0)
        return ["voxtype", "config", "unset", key];
    if (/\.language$/.test(key) && text.indexOf(",") !== -1)
        return ["python3", configScript, "set", key + "=[" + text + "]"];
    return ["voxtype", "config", "set", key, "--", text];
}

/** Whether two setting values mean the same thing; unset and empty are alike. */
function same(a, b) {
    var blankA = a === null || a === undefined || a === "";
    var blankB = b === null || b === undefined || b === "";
    if (blankA || blankB)
        return blankA && blankB;
    if (typeof a === "boolean" || typeof b === "boolean")
        return a === b;
    if (!isNaN(Number(a)) && !isNaN(Number(b)))
        return Math.abs(Number(a) - Number(b)) < 0.001;
    return String(a) === String(b);
}

/** The useful line of a failed command's stderr. */
function errorLine(text) {
    var lines = String(text || "").split("\n").map(function (line) {
        return line.trim();
    }).filter(function (line) {
        return line.length > 0;
    });
    var found = lines.find(function (line) {
        return /^error:/i.test(line);
    });
    return (found || lines[0] || "").replace(/^error:\s*/i, "");
}
