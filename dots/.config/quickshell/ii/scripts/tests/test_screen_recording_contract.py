"""Contracts for the recorder backends and region-selector integration.

These tests intentionally inspect the command boundary rather than starting a
Wayland capture.  They keep the regression coverage safe for headless CI and
avoid touching the user's active Quickshell session.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
RECORD = (ROOT / "scripts/videos/record.sh").read_text()
CONFIG = (ROOT / "modules/common/Config.qml").read_text()
SCREENSHOT_ACTION = (ROOT / "modules/common/utils/ScreenshotAction.qml").read_text()
REGION_SELECTION = (ROOT / "modules/ii/regionSelector/RegionSelection.qml").read_text()
QUALITY_JS = (ROOT / "modules/common/functions/recordingQuality.js").read_text()
KEYPRESS_MONITOR = (ROOT / "scripts/videos/keypress_monitor.py").read_text()


class ScreenRecordingContractTests(unittest.TestCase):
    def test_audio_prefers_the_default_sink_monitor(self):
        body = RECORD.split("getaudiooutput() {", 1)[1].split("\n}\ngetactivemonitor", 1)[0]
        self.assertIn("pactl get-default-sink", body)
        self.assertIn('default_monitor="${default_sink}.monitor"', body)
        self.assertIn("pactl list short sources", body)
        self.assertLess(body.index("default_monitor"), body.index("$2 ~ /\\.monitor$/"))

    def test_record_audio_setting_enables_sound_for_every_entry_point(self):
        self.assertIn('jq -r ".screenRecord.recordAudio"', RECORD)
        parse = RECORD.split('MANUAL_REGION=""', 1)[1].split("AUDIO_ARGS=()", 1)[0]
        self.assertIn('if [[ "$REC_RECORD_AUDIO" == "true" ]]; then\n    SOUND_FLAG=1', parse)
        self.assertIn('"${ARGS[i]}" == "--sound"', parse)

    def test_audio_requests_high_bitrate_aac(self):
        block = RECORD.split("AUDIO_ARGS=()", 1)[1].split("\nfi\n", 2)
        self.assertIn('AUDIO_ARGS+=("-C" "aac" "-P" "b=320k")', block[0] + block[1])

    def test_auto_prefers_gpu_screen_recorder_then_wf_recorder_then_obs(self):
        body = RECORD.split("resolve_service() {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("for candidate in gsr wf-recorder obs; do", body)
        order = body.split("for candidate in ", 1)[1].split(";", 1)[0].split()
        self.assertEqual(order, ["gsr", "wf-recorder", "obs"])
        # An explicit choice is honoured only while that program exists, so a
        # stale config entry cannot break recording.
        self.assertIn('case "$requested" in', body)
        self.assertIn("if service_available \"$requested\"", body)

    def test_default_service_is_auto(self):
        self.assertIn('property string service: "auto"', CONFIG)
        self.assertIn("GPU Screen Recorder is now the preferred backend", CONFIG)
        self.assertIn('raw.screenRecord?.service === "wf-recorder"', CONFIG)
        self.assertIn('raw.screenRecord.service = "auto";', CONFIG)

    def test_gpu_screen_recorder_is_a_first_class_backend(self):
        self.assertIn('elif [[ "$REC_SERVICE" == "gsr" ]]; then', RECORD)
        self.assertIn("gpu-screen-recorder \"${GSR_ARGS[@]}\"", RECORD)
        self.assertIn("gsr_pid()", RECORD)
        # The 15-character comm limit makes `pgrep -x` silently match nothing.
        self.assertIn("pgrep -f '(^|/)gpu-screen-recorder( |$)'", RECORD)

    def test_gsr_records_region_in_slurp_coordinates(self):
        body = RECORD.split('elif [[ "$REC_SERVICE" == "gsr" ]]; then', 1)[1].split('\nelse\n    FILENAME="recording_', 1)[0]
        self.assertIn('GSR_ARGS+=(-w "${size}+${x}+${y}")', body)
        # GSR and slurp share the logical coordinate space; only the encoded
        # size uses the monitor scale.
        self.assertNotIn("-region", body)
        self.assertIn('GSR_ARGS+=(-s "${GSR_W}x${GSR_H}")', body)

    def test_gsr_maps_settings_to_its_own_vocabulary(self):
        body = RECORD.split("gsr_codec() {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("hevc*|libx265", body)
        self.assertIn("h264*|libx264", body)
        quality = RECORD.split("gsr_quality() {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("low) echo \"medium\"", quality)
        self.assertIn('high) echo "very_high"', quality)
        start = RECORD.split('elif [[ "$REC_SERVICE" == "gsr" ]]; then', 1)[1].split('\nelse\n    FILENAME="recording_', 1)[0]
        self.assertIn("-fm \"$GSR_FRAME_SYNC\"", start)
        self.assertIn('GSR_ENCODER_ARGS=("-encoder" "cpu")', start)

    def test_gsr_audio_follows_the_default_output(self):
        body = RECORD.split('elif [[ "$REC_SERVICE" == "gsr" ]]; then', 1)[1].split('\nelse\n    FILENAME="recording_', 1)[0]
        self.assertIn('GSR_AUDIO="default_output"', body)
        self.assertIn('GSR_ARGS+=(-a "$GSR_AUDIO" -ab 320)', body)
        self.assertIn('GSR_ARGS+=(-ac aac)', body)
        self.assertIn('GSR_ARGS+=(-ac opus)', body)

    def test_terminated_session_stops_the_recorder_and_clears_state(self):
        body = RECORD.split("cleanup() {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn('[[ "${RECORDING_SESSION:-0}" == "1" ]]', body)
        self.assertIn('kill -CONT "$RECORDER_PID"', body)
        self.assertIn('kill -INT "$RECORDER_PID"', body)
        self.assertIn("updatestate false", body)
        # The recorder runs as a child so the trap can reach it by PID, while
        # the script still waits for the file to be finalised.
        self.assertIn('gpu-screen-recorder "${GSR_ARGS[@]}" &', RECORD)
        self.assertIn('wait "$RECORDER_PID"', RECORD)

    def test_stale_active_state_stops_instead_of_starting_a_recording(self):
        """A killed script leaves active=true behind. The stop button must clear
        that state, not fall through to the toolbar/region picker."""
        stale = RECORD.split("# The state file can outlive its recorder", 1)[1]
        stale = stale.split("# If toolbar is enabled", 1)[0]
        self.assertIn('if [[ "$(jq -r "$STATE_JSON_PATH" "$STATE_FILE" 2>/dev/null)" == "true" ]]; then', stale)
        self.assertIn('notify-send "Recording Stopped"', stale)
        self.assertIn("updatestate false", stale)
        self.assertIn("exit 0", stale)

    def test_stopping_resets_the_elapsed_counter_even_without_a_timer(self):
        body = RECORD.split("updatestate() {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn(".screenRecord.seconds = 0", body)
        # The timer must be dead before the flag is cleared, or its in-flight
        # jq write can restore active=true after a successful stop.
        false_branch = body.split("else", 1)[1]
        self.assertLess(false_branch.index("stop_timer"), false_branch.index(".screenRecord.seconds = 0"))

    def test_gsr_stop_finalises_through_sigint(self):
        body = RECORD.split("GSR_ACTIVE_PID=$(gsr_pid)", 1)[1].split("if pgrep wf-recorder", 1)[0]
        self.assertIn('kill -INT "$GSR_ACTIVE_PID"', body)
        self.assertIn('kill -0 "$GSR_ACTIVE_PID"', body)
        self.assertIn('kill -TERM "$GSR_ACTIVE_PID"', body)

    def test_gsr_pause_uses_its_own_signal(self):
        body = RECORD.split("elif GSR_ACTIVE_PID=$(gsr_pid)", 1)[1].split("elif pgrep -x wf-recorder", 1)[0]
        self.assertIn('kill -USR2 "$GSR_ACTIVE_PID"', body)

    def test_video_is_labelled_limited_range(self):
        # Untagged output is flagged full range and plays back washed out.
        self.assertIn('"-p" "color_range=tv"', RECORD)
        self.assertIn('"-p" "colorspace=$COLOR_MATRIX"', RECORD)

    def test_region_command_has_a_logical_global_geometry_channel(self):
        self.assertIn("recordGeometry = null", SCREENSHOT_ACTION)
        self.assertIn("recordGeometry ? recordGeometry.x : x", SCREENSHOT_ACTION)
        self.assertIn("recordGeometry ? recordGeometry.y : y", SCREENSHOT_ACTION)
        self.assertIn("recordGeometry ? recordGeometry.width : width", SCREENSHOT_ACTION)
        self.assertIn("recordGeometry ? recordGeometry.height : height", SCREENSHOT_ACTION)
        self.assertIn("x: rx + root.monitorOffsetX", REGION_SELECTION)
        self.assertIn("y: ry + root.monitorOffsetY", REGION_SELECTION)

    def test_region_recording_does_not_force_the_focused_output(self):
        region_body = RECORD.split("# If a manual region was provided", 1)[1]
        region_body = region_body.split("# Post recording action", 1)[0]
        self.assertNotIn('wf-recorder -o "$(getactivemonitor)"', region_body)

    def test_constant_frame_rate_is_the_only_thing_that_passes_r(self):
        """`-r` *is* wf-recorder's CFR switch, so the variable mode must omit it
        entirely rather than pass a rate nobody honours."""
        body = RECORD.split("CODEC_OPTS=(\"-c\" \"$CODEC\")", 1)[1].split("apply_quality", 1)[0]
        self.assertIn('if [[ "$REC_FRAME_SYNC" != "vfr" ]]; then', body)
        self.assertIn('CODEC_OPTS+=("-r" "$REC_FRAMERATE")', body)
        self.assertNotIn('CODEC_OPTS=("-c" "$CODEC" "-r"', RECORD)

    def test_vaapi_scales_with_the_vaapi_scaler(self):
        """VAAPI frames are on the GPU by the time the filter runs; the CPU
        `scale` filter would never see them."""
        body = RECORD.split("apply_quality() {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn('if [[ "$codec" == *_vaapi ]]', body)
        self.assertIn("scale_vaapi=w=${box_w}:h=${box_h}", body)
        self.assertIn("scale=${box_w}:${box_h}", body)
        self.assertIn("force_original_aspect_ratio=decrease", body)
        self.assertIn("force_divisible_by=2", body)
        # A smaller source must be left alone rather than blown up to the box.
        self.assertIn("(( src_w > box_w || src_h > box_h ))", body)

    def test_bitrate_is_derived_and_never_asked_for(self):
        self.assertNotIn("screenRecord.bitrate", RECORD)
        self.assertIn('jq -r ".screenRecord.quality"', RECORD)
        self.assertIn('jq -r ".screenRecord.resolution"', RECORD)
        self.assertIn('jq -r ".screenRecord.frameSync"', RECORD)

    def test_quality_constants_match_between_the_script_and_the_settings_page(self):
        """The settings page shows the bitrate the script will pick, so the two
        copies of the formula have to agree."""
        for name, value in (
            ("QUALITY_BPP_LOW", "0.05"),
            ("QUALITY_BPP_BALANCED", "0.09"),
            ("QUALITY_BPP_HIGH", "0.15"),
            ("BITRATE_FLOOR_MBPS", "1.5"),
            ("BITRATE_CEILING_MBPS", "80"),
        ):
            self.assertIn(f'{name}="{value}"', RECORD, f"{name} missing from record.sh")
            self.assertIn(f"var {name} = {value};", QUALITY_JS, f"{name} missing from recordingQuality.js")

        for preset, box in (
            ("2160p", "3840 2160"),
            ("1440p", "2560 1440"),
            ("1080p", "1920 1080"),
            ("720p", "1280 720"),
            ("480p", "854 480"),
        ):
            self.assertIn(f'{preset}) echo "{box}" ;;', RECORD)
            self.assertIn(f'"{preset}": [{box.replace(" ", ", ")}]', QUALITY_JS)

    def test_keypress_monitor_never_persists_what_it_reads(self):
        """The reader is a keylogger by construction; it may only ever write to
        the pipe the shell holds open."""
        self.assertNotIn("open(", KEYPRESS_MONITOR.replace("os.open(", ""))
        self.assertIn("def emit(", KEYPRESS_MONITOR)
        self.assertIn("print(json.dumps(payload", KEYPRESS_MONITOR)

    def test_keypress_monitor_translates_through_the_active_layout(self):
        """evdev reports physical keys, so a US table would mislabel every
        letter on an AZERTY keyboard."""
        self.assertIn("keymap_new_from_names", KEYPRESS_MONITOR)
        self.assertIn("--layout", KEYPRESS_MONITOR)
        # +8 is the offset between an evdev keycode and an xkb one.
        self.assertIn("code + 8", KEYPRESS_MONITOR)

    def test_recording_does_not_open_the_screenshot_overlay(self):
        snip_body = REGION_SELECTION.split("function snip()", 1)[1]
        overlay_body = snip_body.split("// Trigger screenshot overlay", 1)[1]
        overlay_body = overlay_body.split("root.dismiss();", 1)[0]
        self.assertIn("const isRecording", REGION_SELECTION)
        self.assertIn("if (!isRecording &&", overlay_body)


if __name__ == "__main__":
    unittest.main()
