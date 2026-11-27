import QtQuick
import QtTest
import "../../../modules/settings/configs/dictation/voxtypeSchema.js" as VoxSchema

TestCase {
    name: "VoxtypeSchema"

    readonly property var keys: [
        { key: "engine", engine: null, section: "Engine" },
        { key: "whisper.model", engine: "whisper", section: "Engine" },
        { key: "whisper.threads", engine: "whisper", section: "Engine" },
        { key: "whisper.remote_api_key", engine: "whisper", section: "Engine" },
        { key: "whisper.flash_attention", engine: "whisper", section: "Advanced" },
        { key: "parakeet.streaming", engine: "parakeet", section: "Advanced" },
        { key: "moonshine.quantized", engine: "moonshine", compiled: false, section: "Advanced" },
        { key: "hotkey.key", engine: null, section: "Hotkey" },
        { key: "meeting.enabled", engine: null, section: "Meeting" },
        { key: "meeting.summary.remote_api_key", engine: null, section: "Meeting" },
        { key: "tray.enabled", engine: null, section: "Status" },
        { key: "audio.max_duration_secs", engine: null, section: "Audio" },
        { key: "output.mode", engine: null, section: "Output" },
        { key: "output.pre_type_delay_ms", engine: null, section: "Output" }
    ]

    function test_extras_keep_only_unowned_settings_of_the_engine() {
        const names = VoxSchema.extras(keys, "whisper").map(entry => entry.key);
        compare(names, ["whisper.flash_attention", "output.pre_type_delay_ms"]);
        compare(VoxSchema.sections(VoxSchema.extras(keys, "whisper")), ["Advanced", "Output"]);
        compare(VoxSchema.extras(keys, "parakeet").map(entry => entry.key),
            ["parakeet.streaming", "output.pre_type_delay_ms"]);
    }

    function test_models_of_compiled_engines() {
        compare(VoxSchema.compiledEngines(keys), ["whisper", "parakeet"]);
        const info = { engines: {
            whisper: { models: [{ name: "base", installed: true, download_arg: "base" }] },
            moonshine: { models: [{ name: "tiny", installed: false }] }
        } };
        compare(VoxSchema.models(info, ["whisper"]),
            [{ engine: "whisper", name: "base", installed: true, downloadable: true, downloadArg: "base" }]);
        compare(VoxSchema.models(null, ["whisper"]), []);
    }

    function test_only_safe_model_files_are_removable() {
        compare(VoxSchema.modelFile("whisper", "small"), "ggml-small.bin");
        compare(VoxSchema.modelFile("parakeet", "parakeet-ultra-Q8_0.gguf"), "parakeet-ultra-Q8_0.gguf");
        compare(VoxSchema.modelFile("gguf", "../x.gguf"), "");
        compare(VoxSchema.modelFile("sensevoice", "sensevoice-small"), "");
        compare(VoxSchema.modelFile("whisper", ""), "");
    }

    function test_language_lists() {
        compare(VoxSchema.languageList(" EN, fr "), "en,fr");
        compare(VoxSchema.languageList("auto"), "auto");
        compare(VoxSchema.languageList("auto,fr"), "");
        compare(VoxSchema.languageList("english"), "");
        compare(VoxSchema.languageList(""), "");
    }

    function test_a_language_list_is_written_as_an_array() {
        compare(VoxSchema.writeCommand("whisper.language", "en,fr", "/s.py"),
            ["python3", "/s.py", "set", "whisper.language=[en,fr]"]);
        compare(VoxSchema.writeCommand("whisper.language", "fr", "/s.py"),
            ["voxtype", "config", "set", "whisper.language", "--", "fr"]);
        compare(VoxSchema.writeCommand("output.append_text", " ", "/s.py"),
            ["voxtype", "config", "set", "output.append_text", "--", " "]);
        compare(VoxSchema.writeCommand("output.append_text", "", "/s.py"),
            ["voxtype", "config", "unset", "output.append_text"]);
        compare(VoxSchema.writeCommand("audio.pause_media", false, "/s.py"),
            ["voxtype", "config", "set", "audio.pause_media", "--", "false"]);
        compare(VoxSchema.writeCommand("history.retention_days", 0, "/s.py"),
            ["voxtype", "config", "set", "history.retention_days", "--", "0"]);
    }

    function test_the_punctuation_sample_follows_the_language_unless_hand_written() {
        const french = VoxSchema.sampleFor("fr");
        compare(VoxSchema.promptAfterLanguage("", "fr,en"), french);
        compare(VoxSchema.promptAfterLanguage(french, "auto"), "");
        compare(VoxSchema.promptAfterLanguage("Kubernetes, Hyprland.", "fr"), null);
    }

    function test_same_values() {
        verify(VoxSchema.same(null, ""));
        verify(!VoxSchema.same(null, 0));
        verify(!VoxSchema.same(false, ""));
        verify(VoxSchema.same(0.699999988, 0.7));
        verify(VoxSchema.same("15", 15));
        verify(!VoxSchema.same(true, "true"));
    }

    function test_small_helpers() {
        compare(VoxSchema.multilingualTwin("base.en"), "base");
        compare(VoxSchema.multilingualTwin("base"), "");
        compare(VoxSchema.replacementKey('say "x"'), 'text.replacements."say \\"x\\""');
        compare(VoxSchema.errorLine("warn\nerror: 7 is out of range.\n"), "7 is out of range.");
    }
}
