"""Static contracts for the optional celestial wallpaper integration.

The scene is intentionally off by default and is loaded only while a desktop
is visible.  These checks protect the wiring that keeps the existing wallpaper
path intact and make sure the checked-in shader/texture bundle remains
complete when the QML is edited later.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
CELESTIAL = ROOT / "modules/ii/background/celestial"
CONFIG = (ROOT / "modules/common/Config.qml").read_text()
BACKGROUND_ROOT = (ROOT / "modules/ii/background/BackgroundRoot.qml").read_text()
BACKGROUND_WIDGETS_WINDOW = (ROOT / "modules/ii/background/BackgroundWidgetsWindow.qml").read_text()
CELESTIAL_WALLPAPER = (CELESTIAL / "CelestialWallpaper.qml").read_text()
BACKGROUND_CONFIG = (ROOT / "modules/settings/configs/BackgroundConfig.qml").read_text()
WALLPAPER_IMAGE = (ROOT / "modules/ii/background/wallpaper/WallpaperImage.qml").read_text()
DEPTH_LAYER = (ROOT / "modules/ii/background/depth/DepthCutoutLayer.qml").read_text()


class CelestialWallpaperContractTests(unittest.TestCase):
    def test_schema_is_off_static_and_throttled_by_default(self):
        self.assertIn("property JsonObject celestial: JsonObject {", CONFIG)
        self.assertIn("property bool enable: false", CONFIG)
        self.assertIn("property bool animate: false", CONFIG)
        self.assertIn("property int fps: 10", CONFIG)
        self.assertIn("property int updateIntervalMinutes: 1", CONFIG)
        self.assertIn("property bool simulationEnabled: false", CONFIG)
        self.assertIn("property real simulationDaysPerSecond: 1.0", CONFIG)
        self.assertIn("property bool simulationPaused: false", CONFIG)

    def test_loader_preserves_desktop_fallback_and_visibility_gates(self):
        self.assertIn("Loader {", BACKGROUND_ROOT)
        self.assertIn("id: celestialLoader", BACKGROUND_ROOT)
        self.assertIn("active: bgRoot.celestialWallpaperEnabled", BACKGROUND_ROOT)
        self.assertIn("celestialLoader.status === Loader.Ready", BACKGROUND_ROOT)
        for gate in (
            "!GlobalStates.screenLocked",
            "!bgRoot.deferredFullscreen",
            "!bgRoot.isFullscreen",
            "!bgRoot.mediaModeOpen",
            "!FullGameMode.running",
            "!FullGameMode.switching",
            "bgRoot.editProgress <= 0.001",
        ):
            self.assertIn(gate, BACKGROUND_ROOT)
        self.assertIn("visible: !bgRoot.celestialWallpaperActive", BACKGROUND_ROOT)
        self.assertIn("import qs.modules.ii.background.celestial", BACKGROUND_ROOT)

    def test_still_image_effects_and_depth_are_gated(self):
        self.assertIn("celestialWallpaperActive", WALLPAPER_IMAGE)
        self.assertIn("|| wallpaperImageRoot.celestialWallpaperActive", WALLPAPER_IMAGE)
        self.assertIn("|| p.celestialWallpaperActive", DEPTH_LAYER)
        self.assertIn("|| bgRoot.celestialWallpaperActive", BACKGROUND_ROOT)
        self.assertIn("readonly property bool celestialWallpaperActive:", BACKGROUND_WIDGETS_WINDOW)
        self.assertIn("readonly property bool videoEffectsDisabled: bgWidgetsWindow.celestialWallpaperActive", BACKGROUND_WIDGETS_WINDOW)

    def test_debug_preview_toggle_recomputes_the_scene(self):
        self.assertIn("onDebugActiveChanged: root.updateAstronomy()", CELESTIAL_WALLPAPER)

    def test_shared_prayer_cache_is_location_and_school_safe(self):
        self.assertIn("const sameLocation = root.followWeatherLocation", CELESTIAL_WALLPAPER)
        self.assertIn("Math.abs(serviceLat - root.observerLat) < 0.01", CELESTIAL_WALLPAPER)
        self.assertIn("Math.abs(serviceLon - root.observerLon) < 0.01", CELESTIAL_WALLPAPER)
        self.assertIn("|| root.prayerAsrSchool !== 0", CELESTIAL_WALLPAPER)

    def test_simulation_uses_one_date_and_stays_off_the_live_prayer_paths(self):
        self.assertIn('import "code/simulation.js" as Simulation', CELESTIAL_WALLPAPER)
        self.assertIn("root.simulationDate = new Date(Simulation.advanceDateMs(", CELESTIAL_WALLPAPER)
        self.assertIn("root.orbitState = Astronomy.getEarthAndOrbitState(date, lat, lon);", CELESTIAL_WALLPAPER)
        self.assertIn("if (root.simulationEnabled || root.debugActive)\n                return fallback;", CELESTIAL_WALLPAPER)
        self.assertIn("if (!demoMode && !simulationMode && root.prayerUseApi", CELESTIAL_WALLPAPER)
        self.assertIn("interval: root.simulationTickIntervalMs", CELESTIAL_WALLPAPER)
        self.assertIn("running: root.active && root.simulationActive", CELESTIAL_WALLPAPER)
        self.assertIn("root.simulationLastWallClockMs,", CELESTIAL_WALLPAPER)
        self.assertIn("root.releasePrayerData();", CELESTIAL_WALLPAPER)
        self.assertIn("root.ensurePrayerData();", CELESTIAL_WALLPAPER)

    def test_settings_expose_simulation_speed_pause_and_live_reset(self):
        for label in ("Simulate time", "Pause simulation", "Return to live time"):
            self.assertIn(label, BACKGROUND_CONFIG)
        self.assertIn("simulationDaysPerSecond", BACKGROUND_CONFIG)
        self.assertIn("1.0 / 24.0", BACKGROUND_CONFIG)
        self.assertIn("7.0", BACKGROUND_CONFIG)
        self.assertIn("simulationEnabled = false", BACKGROUND_CONFIG)
        self.assertIn("debugTimeOverrideEnabled = false", BACKGROUND_CONFIG)

    def test_source_bundle_and_provenance_are_complete(self):
        shaders = ("background", "earth", "moon", "orbit", "prayer_clock")
        for shader in shaders:
            self.assertTrue((CELESTIAL / "shaders" / f"{shader}.frag").is_file())
            qsb = CELESTIAL / "shaders" / f"{shader}.frag.qsb"
            self.assertGreater(qsb.stat().st_size, 0)

        for image in (
            "earth_day.png",
            "earth_night.jpg",
            "earth_normal.png",
            "moon_albedo.jpg",
            "moon_normal.png",
        ):
            self.assertTrue((CELESTIAL / "images" / image).is_file())

        provenance = (CELESTIAL / "PROVENANCE.md").read_text()
        self.assertIn("c011962658cc427942a75f32c4f77807b8c7052c", provenance)
        self.assertIn("GPL-2.0-or-later", provenance)
        self.assertIn("NASA", provenance)


if __name__ == "__main__":
    unittest.main()
