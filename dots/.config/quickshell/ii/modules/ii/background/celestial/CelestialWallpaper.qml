/*
    SPDX-FileCopyrightText: 2026 Hadi Alahmad <hade.alahmad1@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import qs
import qs.modules.common
import qs.services

import "code/astronomy.js" as Astronomy
import "code/prayer.js" as Prayer
import "code/simulation.js" as Simulation

Item {
    id: root

    required property var screen
    // BackgroundRoot destroys this item when it is covered by a lock, fullscreen
    // window, or Media Mode. The flag also makes the timer contract explicit for
    // callers that keep the item alive during a transition.
    property bool suspended: false
    readonly property bool active: root.visible && !root.suspended
    readonly property var settings: Config.options?.background?.celestial ?? ({})

    readonly property bool debugActive: Boolean(root.settings.debugTimeOverrideEnabled)
    readonly property real debugPhase: Number(root.settings.debugPhaseValue ?? 0.35)
    readonly property real debugDay: Number(root.settings.debugDayOfYear ?? 292.0)
    readonly property real debugHour: Number(root.settings.debugUtcHour ?? 19.0)

    // Simulation advances one shared ephemeris date. It deliberately takes
    // precedence over the fixed-date debug preview when both switches happen
    // to be enabled, so debugPhase can never pin the Moon during a run.
    readonly property bool simulationEnabled: Boolean(root.settings.simulationEnabled)
    readonly property real simulationDaysPerSecond: Simulation.clampDaysPerSecond(
        root.settings.simulationDaysPerSecond ?? 1.0)
    readonly property bool simulationPaused: Boolean(root.settings.simulationPaused)
    readonly property bool simulationActive: root.simulationEnabled && !root.simulationPaused
    readonly property int simulationTickIntervalMs: 100
    readonly property real simulationMaxElapsedMs: 1000.0
    property var simulationDate: null
    property real simulationLastWallClockMs: 0
    property bool prayerDataRequested: false

    readonly property bool followWeatherLocation: root.settings.followWeatherLocation !== false
    readonly property real configuredLat: Number(root.settings.latitude ?? 30.0)
    readonly property real configuredLon: Number(root.settings.longitude ?? 31.2)
    readonly property real observerLat: root.followWeatherLocation && PrayerTimes.hasLocation
        && isFinite(PrayerTimes.latitude) ? PrayerTimes.latitude : root.configuredLat
    readonly property real observerLon: root.followWeatherLocation && PrayerTimes.hasLocation
        && isFinite(PrayerTimes.longitude) ? PrayerTimes.longitude : root.configuredLon
    readonly property bool southernHemisphereFlip: Boolean(root.settings.flipSouthernHemisphere)
        || (root.settings.autoHemisphere !== false && root.observerLat < 0)
    readonly property bool showObserverPin: root.settings.showObserverPin !== false
    readonly property bool showOrbit: root.settings.showOrbit !== false
    readonly property bool showEarth: root.settings.showEarth !== false
    readonly property int cornerSize: Math.max(140, Math.min(400, Number(root.settings.cornerSize ?? 230)))
    readonly property int cornerMargin: Math.max(16, Math.min(96, Number(root.settings.cornerMargin ?? 36)))
    readonly property color backgroundColor: root.settings.backgroundColor ?? "#05070d"

    readonly property bool showPrayerClockWidget: root.settings.showPrayerClock !== false
    readonly property int prayerCalculationMethod: Number(root.settings.prayerMethod ?? PrayerTimes.method ?? 5)
    readonly property int prayerAsrSchool: Number(root.settings.prayerAsrSchool ?? 0)
    readonly property bool prayerUseApi: root.settings.prayerUseApi !== false

    // The debug preview freezes the simulated date, so live prayer timings
    // and the ticking clock must be suspended while it is active.
    readonly property bool useDemoDate: root.debugActive && !root.simulationEnabled

    readonly property int seasonalBackgroundMode: Number(root.settings.seasonMode ?? 0)
    readonly property int seasonalBackgroundStyle: Number(root.settings.backgroundStyle ?? 0)
    readonly property bool seasonalBackgroundAnimate: root.settings.animate === true
    readonly property real seasonalBackgroundIntensity: Number(root.settings.intensity ?? 0.65)
    readonly property int seasonalBackgroundFps: Math.max(5, Math.min(30, Number(root.settings.fps ?? 10)))
    readonly property bool showTelemetryOverlay: root.settings.showTelemetry !== false
    readonly property real earthshineIntensity: Number(root.settings.earthshineIntensity ?? 0.035)
    readonly property real craterReliefStrength: Number(root.settings.craterReliefStrength ?? 1.2)
    readonly property real moonScale: Number(root.settings.moonScale ?? 0.45)
    readonly property int updateIntervalMinutes: Math.max(1, Number(root.settings.updateIntervalMinutes ?? 1))

    // Resolved season index for BackgroundWidget:
    // -1 = Off, 0 = Spring, 1 = Summer, 2 = Autumn, 3 = Winter
    readonly property int activeSeasonIndex: {
        if (root.seasonalBackgroundMode === 5) {
            return -1;
        }
        if (root.seasonalBackgroundMode >= 1 && root.seasonalBackgroundMode <= 4) {
            return root.seasonalBackgroundMode - 1;
        }
        return (root.orbitState && root.orbitState.observerSeasonIndex !== undefined)
            ? root.orbitState.observerSeasonIndex : 3;
    }

    // Scrubbing any of these settings recomputes the scene deterministically.
    onDebugActiveChanged: root.updateAstronomy()
    onDebugPhaseChanged: {
        if (root.debugActive) {
            root.updateAstronomy();
        }
    }
    onDebugDayChanged: {
        if (root.debugActive) {
            root.updateAstronomy();
        }
    }
    onDebugHourChanged: {
        if (root.useDemoDate) {
            root.updateAstronomy();
        }
    }
    onSimulationEnabledChanged: root.handleSimulationEnabledChanged()
    onSimulationPausedChanged: root.handleSimulationPausedChanged()
    onObserverLatChanged: root.updateAstronomy()
    onObserverLonChanged: root.updateAstronomy()
    onPrayerCalculationMethodChanged: root.updateAstronomy()
    onPrayerAsrSchoolChanged: root.updateAstronomy()

    // Recompute the snapshot when the shared location service learns a place.
    Connections {
        target: PrayerTimes
        function onLocationKeyChanged() { root.updateAstronomy(); }
        function onDataVersionChanged() { root.updateAstronomy(); }
    }

    Connections {
        target: Config.options?.background?.celestial ?? null
        function onShowPrayerClockChanged() { root.updateAstronomy(); }
        function onPrayerUseApiChanged() { root.updateAstronomy(); }
        function onDebugPhaseValueChanged() { if (root.debugActive) root.updateAstronomy(); }
        function onDebugDayOfYearChanged() { if (root.debugActive) root.updateAstronomy(); }
        function onDebugUtcHourChanged() { if (root.debugActive) root.updateAstronomy(); }
    }

    // Synodic month, used only to nudge the ephemeris towards a manually
    // selected phase while the settings preview is active.
    readonly property real lunarCycleMs: 29.530588853 * 24 * 60 * 60 * 1000

    readonly property real moonSize: Math.min(root.width, root.height)
                                     * Math.max(0.15, Math.min(0.90, root.moonScale))

    // Sensible initial values so the very first frame is never blank.
    property var moonState: ({
        phase: 0.5,
        phaseAngleRad: Math.PI,
        illumination: 1.0,
        ageDays: 14.77,
        phaseName: "Full Moon",
        sunDirection: { x: 0.0, y: 0.0, z: 1.0 },
        librationLonRad: 0.0,
        librationLatRad: 0.0
    })

    property var orbitState: null

    // Prayer clock snapshot, refreshed by updateAstronomy() and by the
    // 30-second clock timer below.
    property real prayerLocalTimeHours: 12.0
    property real fajrHours: 4.8
    property real sunriseHours: 6.1
    property real dhuhrHours: 11.9
    property real asrHours: 15.3
    property real maghribHours: 17.7
    property real ishaHours: 19.0
    property real nextPrayerHours: 15.3
    property int nextPrayerIndex: 3
    property string nextPrayerName: "Asr"
    property int minutesToNextPrayer: 168
    property string prayerMethodName: "MWL"

    // Luminance of the configured background, used to keep the telemetry
    // readable on both very dark and very light wallpapers.
    readonly property real backgroundLuminance: {
        const c = root.backgroundColor;
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    }
    readonly property color telemetryColor: root.backgroundLuminance > 0.5
                                            ? Qt.rgba(0.0, 0.0, 0.0, 0.58)
                                            : Qt.rgba(0.86, 0.88, 0.92, 0.58)

    function syntheticDate(dayOfYear, utcHour) {
        const year = new Date().getUTCFullYear();
        const start = Date.UTC(year, 0, 1, 0, 0, 0);
        const day = Math.max(1.0, Math.min(365.25, dayOfYear));
        const hour = Math.max(0.0, Math.min(24.0, utcHour));
        return new Date(start + (day - 1.0) * 86400000 + hour * 3600000);
    }

    function currentAstronomyDate() {
        if (root.simulationEnabled) {
            root.ensureSimulationDate();
            return root.simulationDate;
        }
        if (root.useDemoDate) {
            return root.syntheticDate(root.debugDay, root.debugHour);
        }
        return new Date();
    }

    function startSimulation() {
        var now = Date.now();
        root.simulationDate = new Date(now);
        root.simulationLastWallClockMs = now;
    }

    function ensureSimulationDate() {
        if (!(root.simulationDate instanceof Date) || !isFinite(root.simulationDate.getTime())) {
            root.startSimulation();
        }
    }

    function handleSimulationEnabledChanged() {
        if (root.simulationEnabled) {
            root.startSimulation();
            // Drop the shared live prayer-data lease while the preview is
            // active. This keeps a simulation-only wallpaper from starting or
            // retaining the service's network path.
            root.releasePrayerData();
        } else {
            // Returning to live time discards the preview clock immediately;
            // the next astronomy pass reads the real current date.
            root.simulationDate = null;
            root.simulationLastWallClockMs = 0;
            root.ensurePrayerData();
        }
        root.updateAstronomy();
    }

    function ensurePrayerData() {
        if (!root.prayerDataRequested) {
            PrayerTimes.requestData();
            root.prayerDataRequested = true;
        }
    }

    function releasePrayerData() {
        if (root.prayerDataRequested) {
            PrayerTimes.releaseData();
            root.prayerDataRequested = false;
        }
    }

    function handleSimulationPausedChanged() {
        // Establish a fresh baseline on both pause and resume. This prevents
        // a settings-page detour from contributing a delayed wall-clock jump.
        root.simulationLastWallClockMs = Date.now();
        if (root.simulationEnabled) {
            root.updateAstronomy();
        }
    }

    function advanceSimulation(nowMs) {
        if (!root.simulationActive) {
            return;
        }
        root.ensureSimulationDate();
        var now = Number(nowMs);
        if (!isFinite(now)) {
            now = Date.now();
        }
        var elapsed = Simulation.boundedElapsedMs(now,
                                                   root.simulationLastWallClockMs,
                                                   root.simulationMaxElapsedMs);
        root.simulationLastWallClockMs = now;
        if (elapsed <= 0) {
            return;
        }
        root.simulationDate = new Date(Simulation.advanceDateMs(
            root.simulationDate.getTime(), elapsed, root.simulationDaysPerSecond));
        root.updateAstronomy();
    }

    function formatSimulationDate(date) {
        if (!(date instanceof Date) || !isFinite(date.getTime())) {
            return "";
        }
        function pad(value) { return String(value).padStart(2, "0"); }
        return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-"
            + pad(date.getDate()) + " " + pad(date.getHours()) + ":"
            + pad(date.getMinutes()) + ":" + pad(date.getSeconds());
    }

    readonly property string simulationDateLabel: root.formatSimulationDate(root.simulationDate)

    // Copy a prayer.js state object onto the root properties consumed by
    // PrayerClockWidget. Missing or malformed states leave the last snapshot.
    function applyPrayerState(pState) {
        if (!pState) {
            return;
        }

        root.prayerLocalTimeHours = pState.localTimeHours;
        root.fajrHours = pState.fajrHours;
        root.sunriseHours = pState.sunriseHours;
        root.dhuhrHours = pState.dhuhrHours;
        root.asrHours = pState.asrHours;
        root.maghribHours = pState.maghribHours;
        root.ishaHours = pState.ishaHours;
        root.nextPrayerHours = pState.nextPrayerHours;
        root.nextPrayerIndex = pState.nextPrayerIndex;
        root.nextPrayerName = pState.nextPrayerName;
        root.minutesToNextPrayer = pState.minutesToNextPrayer;
        root.prayerMethodName = pState.methodName;
    }

    function prayerStateFor(date) {
        try {
            const fallback = Prayer.getPrayerState(date, root.observerLat, root.observerLon,
                                                    root.prayerCalculationMethod,
                                                    root.prayerAsrSchool);
            // PrayerTimes is the shell's shared monthly AlAdhan cache. Reuse it
            // only when it describes this scene's weather location and method;
            // a custom coordinate must never silently inherit another place's
            // timings. The shared widget cache currently stores standard Asr
            // only, so Hanafi stays on the local calculator too.
            const serviceLat = Number(PrayerTimes.latitude);
            const serviceLon = Number(PrayerTimes.longitude);
            // A simulated date must use the local calculator. The shared
            // service cache represents live calendar days and may otherwise
            // silently replace the simulated prayer times.
            if (root.simulationEnabled || root.debugActive)
                return fallback;
            const sameLocation = root.followWeatherLocation
                && PrayerTimes.hasLocation
                && isFinite(serviceLat)
                && isFinite(serviceLon)
                && Math.abs(serviceLat - root.observerLat) < 0.01
                && Math.abs(serviceLon - root.observerLon) < 0.01;
            if (!sameLocation
                    || PrayerTimes.method !== root.prayerCalculationMethod
                    || root.prayerAsrSchool !== 0)
                return fallback;
            const records = PrayerTimes.prayersFor(date);
            if (!records || records.length < 6)
                return fallback;
            const hours = records.map(record => record.time.getHours() + record.time.getMinutes() / 60.0);
            fallback.fajrHours = hours[0];
            fallback.sunriseHours = hours[1];
            fallback.dhuhrHours = hours[2];
            fallback.asrHours = hours[3];
            fallback.maghribHours = hours[4];
            fallback.ishaHours = hours[5];
            const local = date.getHours() + date.getMinutes() / 60.0 + date.getSeconds() / 3600.0;
            fallback.localTimeHours = local;
            const order = [0, 2, 3, 4, 5];
            let next = order.find(index => hours[index] > local);
            if (next === undefined)
                next = 0;
            fallback.nextPrayerIndex = next;
            fallback.nextPrayerHours = hours[next];
            fallback.minutesToNextPrayer = next === 0 && hours[0] <= local
                ? Math.round(((24.0 - local) + hours[0]) * 60.0)
                : Math.max(0, Math.round((hours[next] - local) * 60.0));
            fallback.nextPrayerName = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"][next];
            fallback.source = "service";
            return fallback;
        } catch (e) {
            console.warn("moonphase: prayer times failed:", e);
            return null;
        }
    }

    // Offline recalculation only; the daily AlAdhan fetch happens once per
    // updateAstronomy() call and is then served from prayer.js' cache.
    function refreshPrayerState() {
        let date = root.currentAstronomyDate();
        root.applyPrayerState(root.prayerStateFor(date));
    }

    function updateAstronomy() {
        try {
            const lat = root.observerLat;
            const lon = root.observerLon;

            // Read the demo switch straight from the configuration: a derived
            // binding can still be stale while the wallpaper is being
            // constructed, and a fetch made in that window would cache live
            // timings for the simulated date.
            const demoMode = root.useDemoDate;
            const simulationMode = root.simulationEnabled;
            let date = root.currentAstronomyDate();

            if (demoMode && !simulationMode) {
                root.moonState = root.stateForPhase(root.debugPhase, date.getTime(), lat, lon);
            } else {
                root.moonState = Astronomy.getMoonState(date, lat, lon);
            }

            root.orbitState = Astronomy.getEarthAndOrbitState(date, lat, lon);

            // Synchronous offline snapshot first, so the dial is correct
            // immediately; the API result replaces it when it arrives.
            root.applyPrayerState(root.prayerStateFor(date));

            if (!demoMode && !simulationMode && root.prayerUseApi && root.showPrayerClockWidget) {
                Prayer.fetchPrayerTimesAsync(date, lat, lon,
                                             root.prayerCalculationMethod,
                                             root.prayerAsrSchool,
                                             function(apiState) {
                    // A response can land after the preview was switched on.
                    if (!root.debugActive && !root.simulationEnabled) {
                        root.applyPrayerState(apiState);
                    }
                });
            }
        } catch (e) {
            // Keep the last known-good scene rather than blanking the desktop.
            console.warn("moonphase: ephemeris failed:", e);
        }
    }

    // Walk the ephemeris to the requested phase. Two refinement passes are
    // enough to land within a few thousandths of a degree of the target.
    function stateForPhase(phase, baseMs, latitude, longitude) {
        const target = ((phase % 1.0) + 1.0) % 1.0;
        let timestamp = (baseMs === undefined) ? Date.now() : baseMs;

        let state = Astronomy.getMoonState(new Date(timestamp), latitude, longitude);
        let delta = target - state.phase;
        if (delta > 0.5) {
            delta -= 1.0;
        } else if (delta < -0.5) {
            delta += 1.0;
        }

        timestamp += delta * root.lunarCycleMs;
        state = Astronomy.getMoonState(new Date(timestamp), latitude, longitude);

        delta = target - state.phase;
        if (delta > 0.5) {
            delta -= 1.0;
        } else if (delta < -0.5) {
            delta += 1.0;
        }

        timestamp += delta * root.lunarCycleMs;
        return Astronomy.getMoonState(new Date(timestamp), latitude, longitude);
    }

    BackgroundWidget {
        id: backgroundWidget
        anchors.fill: parent
        baseColor: root.backgroundColor
        seasonIndex: root.activeSeasonIndex
        styleMode: root.seasonalBackgroundStyle
        animate: root.seasonalBackgroundAnimate
        intensity: root.seasonalBackgroundIntensity
        fps: root.seasonalBackgroundFps
        moonIllumination: root.moonState ? root.moonState.illumination : 0.5
    }

    Item {
        id: moonContainer

        anchors.centerIn: parent
        width: root.moonSize
        height: root.moonSize

    ShaderEffect {
            id: moonShader

            anchors.fill: parent

            // Rendering the shader into an offscreen layer means Qt only
            // re-runs the fragment shader when a uniform, the size or the
            // textures change -- not on every desktop repaint.
            layer.enabled: true
            layer.smooth: true

            property vector3d sunDirection: root.moonState.sunDirection
                                            ? Qt.vector3d(root.moonState.sunDirection.x,
                                                          root.moonState.sunDirection.y,
                                                          root.moonState.sunDirection.z)
                                            : Qt.vector3d(0.0, 0.0, 1.0)
            property vector2d libration: Qt.vector2d(root.moonState.librationLonRad || 0.0,
                                                     root.moonState.librationLatRad || 0.0)
            property real earthshine: root.earthshineIntensity
            property real normalStrength: root.craterReliefStrength
            property real rollAngleRad: root.southernHemisphereFlip
                                        ? Math.PI
                                        : 0.0

            // Image exposes a texture provider, so the decoded texture is
            // passed straight to the shader (mipmaps included).
            property variant albedoSource: albedoImage
            property variant normalSource: normalImage

            fragmentShader: Qt.resolvedUrl("shaders/moon.frag.qsb")
        }

        Image {
            id: albedoImage

            source: Qt.resolvedUrl("images/moon_albedo.jpg")
            visible: false
            asynchronous: false
            mipmap: true
            smooth: true
            sourceSize: Qt.size(2048, 1024)
        }

        Image {
            id: normalImage

            source: Qt.resolvedUrl("images/moon_normal.png")
            visible: false
            asynchronous: false
            mipmap: true
            smooth: true
            sourceSize: Qt.size(2048, 1024)
        }
    }

    CurvedText {
        id: telemetry

        anchors.fill: parent
        visible: root.showTelemetryOverlay
        centerX: root.width * 0.5
        centerY: root.height * 0.5
        // Sits cleanly outside the r = 0.258..0.278 ticked astrolabe circle
        // (and outside the lunar disc if MoonScale is increased).
        arcRadius: Math.max(root.moonSize * 0.465, root.height * 0.298)

        text: root.moonState.phaseName.toUpperCase()
              + "  \u2022  " + (root.moonState.illumination * 100).toFixed(1) + "%"
              + "  \u2022  DAY " + root.moonState.ageDays.toFixed(1)

        color: root.telemetryColor
        fontFamily: Appearance.font.family.main
        pixelSize: Math.max(9, Math.round(root.moonSize * 0.026))
        fontWeight: Font.Light
        letterSpacing: Math.max(1.2, root.moonSize * 0.004)
        textStyle: Text.Raised
        styleColor: root.backgroundLuminance > 0.5
                    ? Qt.rgba(1.0, 1.0, 1.0, 0.15)
                    : Qt.rgba(0.0, 0.0, 0.0, 0.25)
    }

    Text {
        id: simulationTelemetry

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.cornerMargin
        visible: root.showTelemetryOverlay && root.simulationEnabled
        text: (root.simulationPaused ? "SIMULATION PAUSED" : "SIMULATED TIME")
              + "  •  " + root.simulationDateLabel
        color: root.telemetryColor
        font.family: Appearance.font.family.main
        font.pixelSize: Math.max(9, Math.round(root.moonSize * 0.022))
        font.weight: Font.Light
        font.letterSpacing: 1.0
    }

    OrbitWidget {
        id: orbitWidget

        visible: root.showOrbit && root.orbitState !== null

        width: root.cornerSize
        height: implicitHeight

        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: root.cornerMargin

        earthHelioLonRad: root.orbitState ? root.orbitState.earthHelioLonRad : 0.0
        jan1HelioLonRad: root.orbitState ? root.orbitState.jan1HelioLonRad : 1.754
        yearProgress: root.orbitState ? root.orbitState.yearProgress : 0.0
        showGhostEarths: root.settings.showSeasonalGhostEarths !== false
        showTelemetry: root.showTelemetryOverlay

        seasonName: root.orbitState
            ? (root.orbitState.observerSeasonName || root.orbitState.seasonNameNorth)
            : "Winter"
        dayOfYear: root.orbitState ? root.orbitState.dayOfYear : 1
        daysInYear: root.orbitState ? root.orbitState.daysInYear : 365
    }

    EarthWidget {
        id: earthWidget

        visible: root.showEarth && root.orbitState !== null

        width: root.cornerSize
        height: implicitHeight

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.cornerMargin

        sunVectorWorld: root.orbitState && root.orbitState.sunVectorWorld
                        ? Qt.vector3d(root.orbitState.sunVectorWorld.x,
                                      root.orbitState.sunVectorWorld.y,
                                      root.orbitState.sunVectorWorld.z)
                        : Qt.vector3d(1.0, 0.0, 0.0)
        observerLatDeg: root.observerLat
        observerLonDeg: root.observerLon
        localSolarTimeHours: root.orbitState ? root.orbitState.localSolarTimeHours : 12.0
        // The Black Marble source is deliberately very dark; at a 230 px
        // thumbnail the city lights need a boost to read as more than noise.
        nightLightsBoost: 3.2
        showObserverPin: root.showObserverPin
        showTelemetry: root.showTelemetryOverlay
    }

    PrayerClockWidget {
        id: prayerClockWidget

        visible: root.showPrayerClockWidget
        width: root.cornerSize
        height: implicitHeight

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.cornerMargin

        localTimeHours: root.prayerLocalTimeHours
        fajrHours: root.fajrHours
        sunriseHours: root.sunriseHours
        dhuhrHours: root.dhuhrHours
        asrHours: root.asrHours
        maghribHours: root.maghribHours
        ishaHours: root.ishaHours
        nextPrayerHours: root.nextPrayerHours
        nextPrayerIndex: root.nextPrayerIndex
        nextPrayerName: root.nextPrayerName
        minutesToNextPrayer: root.minutesToNextPrayer
        methodName: root.prayerMethodName
        showTelemetry: root.showTelemetryOverlay
    }

    Timer {
        id: refreshTimer

        interval: root.updateIntervalMinutes * 60 * 1000
        running: root.active && !root.debugActive && !root.simulationEnabled
        repeat: true
        triggeredOnStart: true

        onTriggered: root.updateAstronomy()
    }

    // Fast clock tick: keeps the analogue hands and the countdown in step
    // without re-running the ephemeris or hitting the network.
    Timer {
        id: prayerClockTimer

        interval: 30000
        running: root.active && root.showPrayerClockWidget && !root.useDemoDate
            && !root.simulationEnabled
        repeat: true

        onTriggered: root.refreshPrayerState()
    }

    // The simulated date is the only high-frequency timer in the scene. It
    // runs at 10 Hz only while this visible wallpaper is actively displayed;
    // every tick advances one date and recomputes all astronomy consumers.
    Timer {
        id: simulationTimer

        interval: root.simulationTickIntervalMs
        running: root.active && root.simulationActive
        repeat: true
        triggeredOnStart: true

        onTriggered: root.advanceSimulation(Date.now())
    }

    Connections {
        target: root
        function onActiveChanged() {
            if (root.simulationEnabled) {
                root.simulationLastWallClockMs = Date.now();
            }
        }
    }

    Component.onCompleted: {
        // Simulation is deliberately self-contained: do not wake the shared
        // prayer/location API path just to render a fast local preview.
        if (!root.simulationEnabled)
            root.ensurePrayerData();
        root.updateAstronomy();
    }

    Component.onDestruction: {
        root.releasePrayerData();
    }
}
