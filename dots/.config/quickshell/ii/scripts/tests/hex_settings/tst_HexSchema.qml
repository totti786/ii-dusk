import QtQuick
import QtTest
import "../../../modules/settings/configs/dictation/hexSchema.js" as HexSchema

// The pure helpers behind the Hex part of Settings > Dictation.
// Run with: /usr/lib/qt6/bin/qmltestrunner -input scripts/tests/hex_settings
TestCase {
    name: "HexSchema"

    function entry(key, about, extra) {
        return Object.assign({
            key: key,
            about: about,
            kind: "bool",
            writable: true,
            available: true
        }, extra || {});
    }

    function test_generatedRowsAreLinuxDictationSettings() {
        const kept = HexSchema.extras([
            entry("labs.signature", "Labs: every normal dictation is signed"),
            entry("labs.clipboard_phrase", "Labs: spoken in a normal dictation (Windows, Linux)"),
            entry("labs.smart_spacing", "Labs: add a space before a dictation (macOS)"),
            entry("labs.copy_only", "Labs: put it on the clipboard (macOS and Windows)"),
            entry("meetings.enabled", "Labs: Meetings"),
            entry("labs.meeting_import", "Labs: Import audio"),
            entry("dictation_hotkey", "The dictation shortcut", { kind: "shortcut" }),
            entry("labs.second_dictation_shortcut", "Labs: another shortcut"),
            entry("labs.standalone_special_keys", "Labs: shortcuts may use Menu (Linux)"),
            entry("labs.section_key_alone", "Labs: the key left of 1 (Linux, macOS)"),
            entry("enable_on_launch", "Start listening when Hex opens (Windows and Linux)"),
            entry("microphone", "Microphone by name", { kind: "text" }),
            entry("sound_effects", "Play recording and error tones"),
            entry("labs.yolo_mode_apps", "Labs: the apps", { kind: "json" }),
            entry("labs.drop_transcribe", "Labs: dropped files", { writable: false }),
            entry("labs.api_timestamps", "Labs: times", { available: false })
        ]).map(found => found.key);
        compare(kept.join(" "), "labs.signature labs.clipboard_phrase");
    }

    function test_groups() {
        compare(HexSchema.group("labs.api_processing"), "api");
        compare(HexSchema.group("labs.history_stats"), "window");
        compare(HexSchema.group("labs.signature"), "dictation");
        compare(HexSchema.title("labs.signature_text"), "Signature text");
    }

    function test_labsList() {
        const found = HexSchema.parseLabs("signature   off   everyone  Sign each dictation (hex settings labs.signature)\n"
            + "special-keys   on   everyone  Use Menu (or Pause) alone (hex settings labs.standalone_special_keys)\n"
            + "not a labs line\n");
        compare(Object.keys(found).length, 2);
        compare(found["labs.signature"], "Sign each dictation");
        compare(found["labs.standalone_special_keys"], "Use Menu (or Pause) alone");
    }

    // Hex lists some choices as text and stores them as numbers; volumes are 32-bit floats.
    function test_same() {
        verify(HexSchema.same("15", 15));
        verify(HexSchema.same(0.2, 0.20000000298023224));
        verify(HexSchema.same(null, null));
        verify(!HexSchema.same(null, 0));
        verify(!HexSchema.same("", 0));
        verify(!HexSchema.same(undefined, false));
        verify(!HexSchema.same(true, 1));
        verify(!HexSchema.same("day", "week"));
    }

    function test_assignLeavesTheOriginalAlone() {
        const stored = { labs: { unload_idle: false, signature: true }, sound_effects: true };
        const next = HexSchema.assign(stored, "labs.unload_idle", true);
        compare(HexSchema.lookup(next, "labs.unload_idle"), true);
        compare(HexSchema.lookup(next, "labs.signature"), true);
        compare(stored.labs.unload_idle, false);
        compare(HexSchema.lookup(stored, "transcription.model"), undefined);
    }
}
