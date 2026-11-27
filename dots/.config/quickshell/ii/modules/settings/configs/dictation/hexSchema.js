.pragma library

// Pure helpers for Hex's settings: no QML, so scripts/tests can run them in node.

/** Keys the settings page draws by hand; the generated list leaves them out. */
var handDrawn = [
    "labs.unload_idle", "labs.unload_idle_minutes",
    "transcription_device",
    "release_microphone_while_idle", "labs.keep_microphone_open", "labs.keep_microphone_open_seconds",
    "avoid_bluetooth_microphone",
    "sound_effects", "sound_theme", "sound_effect_volume",
    "recording_audio_behavior", "recording_duck_volume", "labs.speakers_only",
    "labs.live_typing", "paste_with_shift", "labs.keep_on_clipboard", "labs.yolo_mode",
    "labs.filler_words", "labs.spoken_formatting", "labs.spoken_symbols", "labs.skip_pauses",
    "labs.dictation_style", "labs.dictation_style_choice", "labs.stop_phrase", "labs.stop_phrase_text",
    "indicator_position", "labs.live_text", "labs.failure_notices",
    "history_retention", "labs.keep_recordings",
    "vocabulary_boost"
];

// Features that are not dictation, that Hex's own hotkeys drive (the shell sends
// `hex dictation ...` from its own shortcuts instead), or that could stop dictation
// working: `enable_on_launch` off leaves Hex refusing the shell's commands, and a
// mistyped `microphone` name records nothing.
var excludedKey = new RegExp([
    "^(meetings|capture|screenshots|updates|keyboard_model_switching|experimental|dictation_processing|transcription)\\.",
    "meeting", "calendar", "annotate", "capture", "screenshot", "call_recording", "transcript_edits", "live_chapters",
    "appearance", "gnome", "wsl", "playground", "notch", "ui_language",
    "hotkey", "shortcut", "_key$", "_keys$", "double_tap", "tap_or_hold", "hold_through", "caps_lock",
    "section_key", "middle_mouse", "typed_text", "confirm_long_cancels", "model_switch",
    "^enable_on_launch$", "^microphone$"
].join("|"));

/** True when Hex's description marks the setting as not working on Linux. */
function otherPlatform(about) {
    var groups = about.match(/\([^()]*\)/g) || [];
    var elsewhere = groups.some(function (group) {
        return /macOS|Windows/.test(group) && !/Linux/.test(group);
    });
    return elsewhere || /Apple|this Mac|Retina|\bDock\b|menu bar(?! or tray)/.test(about);
}

/** Catalogue entries worth a generated row: Linux dictation settings not drawn by hand. */
function extras(catalogue) {
    return (catalogue || []).filter(function (entry) {
        return entry.available !== false && entry.writable !== false
            && ["bool", "choice", "text", "integer", "number"].indexOf(entry.kind) !== -1
            && handDrawn.indexOf(entry.key) === -1
            && !excludedKey.test(entry.key)
            && !otherPlatform(String(entry.about || ""));
    });
}

/** Which group of the generated list a key belongs to. */
function group(key) {
    if (/\.api_/.test(key))
        return "api";
    if (/picker|benchmark|history_stats|output_fixes|modes_editor|vocabulary_files|model_in_place|parakeet|copy_dictation_audio|drop_transcribe|typing_wpm/.test(key))
        return "window";
    return "dictation";
}

function title(key) {
    var words = key.replace(/^labs\./, "").replace(/[._]/g, " ").replace(/\bapi\b/, "API").replace(/\bwpm\b/, "(words a minute)");
    return words.charAt(0).toUpperCase() + words.slice(1);
}

/** `hex labs list` output -> { settings key: description }. */
function parseLabs(text) {
    var found = {};
    String(text || "").split("\n").forEach(function (line) {
        var match = line.match(/^\S+\s+(?:on|off)\s+\S+\s+(.*?)\s*\(hex settings ([\w.]+)\)\s*$/);
        if (match)
            found[match[2]] = match[1];
    });
    return found;
}

function lookup(object, key) {
    var parts = key.split(".");
    var value = object;
    for (var i = 0; i < parts.length; i++) {
        if (value === null || typeof value !== "object")
            return undefined;
        value = value[parts[i]];
    }
    return value;
}

/** A copy of `object` with `key` set; the original is left alone. */
function assign(object, key, value) {
    var copy = Object.assign({}, object);
    var dot = key.indexOf(".");
    if (dot === -1)
        copy[key] = value;
    else
        copy[key.slice(0, dot)] = assign(copy[key.slice(0, dot)] || {}, key.slice(dot + 1), value);
    return copy;
}

/**
 * Whether two setting values mean the same thing. Hex lists some choices as text
 * ("15") and stores them as numbers, and stores volumes as 32-bit floats.
 */
function same(a, b) {
    if (a === b)
        return true;
    if (a === undefined || b === undefined || a === null || b === null
            || typeof a === "boolean" || typeof b === "boolean")
        return false;
    if (a !== "" && b !== "" && !isNaN(Number(a)) && !isNaN(Number(b)))
        return Math.abs(Number(a) - Number(b)) < 0.001;
    return JSON.stringify(a) === JSON.stringify(b);
}
