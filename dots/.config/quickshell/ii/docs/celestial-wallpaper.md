# Celestial Moonphase wallpaper

The optional celestial wallpaper ports the KDE Moonphase scene into the Quickshell
background. It draws a planisphere, moon, orbit, Earth, seasonal markers, and an
optional prayer clock. It is disabled and static by default.

## Enable it

Use **Settings → Background → Celestial Moonphase**. The same settings are stored
under `background.celestial` in:

```text
~/.config/illogical-impulse/config.json
```

The smallest direct configuration is:

```json
"celestial": {
  "enable": true,
  "animate": false,
  "fps": 10,
  "backgroundStyle": 0,
  "simulationEnabled": false,
  "simulationDaysPerSecond": 1.0,
  "simulationPaused": false
}
```

`animate: false` keeps the scene still. When animation is enabled, `fps` is
clamped to 5–30; 10 FPS is the default. `updateIntervalMinutes` controls the
astronomy/prayer refresh and defaults to one minute, independently of the shader
refresh rate.

## Simulate the sky

Turn on **Simulate time** in the Celestial Moonphase settings to start at the
current date and run the ephemeris forward quickly. The simulation advances one
shared date, so the Moon phase, Earth/orbit positions, local solar time, and
prayer clock all move together. The available presets are:

| Preset | Setting |
| --- | ---: |
| 1 hour / second | `0.0416667` days per second |
| 1 day / second | `1.0` day per second |
| 7 days / second | `7.0` days per second |

The default preview speed is one day per second, which makes a lunar month
visible in about 30 seconds. **Pause simulation** holds the current simulated
date, and **Return to live time** immediately discards it and resumes the real
clock. Simulation is separate from the older fixed-date debug preview; when
both are enabled, simulation takes precedence and the debug phase value cannot
pin the Moon.

While simulation is active, prayer timings are calculated locally for the
simulated date. The shared live prayer cache and prayer API are bypassed, and
the 10 Hz simulation timer only runs while the wallpaper is visible and
unsuspended. Each wall-clock tick is bounded to one second so a lock-screen or
desktop resume cannot create a large time jump. No configuration writes occur
per tick.

The main display modes are:

| Key | Values |
| --- | --- |
| `backgroundStyle` | `0` Planisphere, `1` Seasonal etchings, `2` Combined |
| `seasonMode` | `0` automatic, `1` Spring, `2` Summer, `3` Autumn, `4` Winter, `5` off |
| `intensity` | Scene brightness from `0.1` to `1.0` (default `0.65`) |
| `showTelemetry` | Show or hide captions and instrument labels |
| `showEarth`, `showOrbit`, `showPrayerClock` | Toggle the corresponding scene elements |

Location follows the existing Weather service when `followWeatherLocation` is
`true`. Set it to `false` to use `latitude` and `longitude` from this group;
`autoHemisphere` and `flipSouthernHemisphere` control the southern-hemisphere
orientation. `prayerMethod`, `prayerAsrSchool`, and `prayerUseApi` select the
prayer-clock calculation path.

## Lifecycle and fallback

The scene is loaded lazily once per monitor. While it is loading, disabled, or if a
the scene component fails to load, the existing wallpaper remains visible. The scene is
suspended when the background is covered by the lock screen, a fullscreen/game
surface, edit mode, or media mode; its animation and astronomy timers therefore do
not continue in those states. The original depth/parallax image effects are gated
while the celestial scene is active so the still image is not composited over it.
When a suspended scene is destroyed and later loaded again, a simulation starts
from the then-current real date; its preview date is intentionally runtime-only.

## Measured impact

These are short observations on one 1920×1080 60 Hz Intel i915 display with the full
live shell and an active desktop. CPU is shell process usage as a percentage of one
core; GPU is render-engine busy time from i915 DRM fdinfo; RSS is the whole shell
resident set. Disabled/static runs were 40–45 seconds and animation ran at 10 FPS.

| State | Window | CPU / one core | GPU render busy | RSS |
| --- | ---: | ---: | ---: | ---: |
| Integrated, celestial disabled | 40 s | 8.3608% | 0.6645% | 652.225 MiB |
| Celestial static | 45 s | 8.2122% | 0.6575% | 719.591 MiB |
| Celestial animated, 10 FPS | 45 s | 8.8242% | 2.5932% | 816.080 MiB |
| Disabled after celestial run | 40 s | 3.4165% | 1.0820% | 833.912 MiB |

The last row shows that allocations and caches can remain resident after disabling;
it also includes workspace/user activity, so it is not a controlled before/after
benchmark. RSS is a whole-shell measurement rather than an isolated scene
allocation. The samples indicate that static mode adds little measured CPU/GPU
work, while 10 FPS animation raises render-engine activity; repeat measurements are
needed for battery or multi-monitor conclusions. Lock, edit, and media-mode runtime
costs were not measured, and no multi-monitor run has been completed.

## Verification and provenance

- Upstream astronomy, Earth/orbit, and prayer tests: **40 passed**.
- Local celestial contract tests: **6 passed**.
- Five GLSL shaders compiled to Qt `.qsb` artifacts with the local Qt 6 `qsb`.
- `qmllint` reported **0 errors** on the changed QML; standalone linting still
  reports existing unresolved-module and unqualified-property warnings.
- An existing background-grid contract check still has four unrelated failures.

Porting attribution, source commit, and licenses are recorded in
[`modules/ii/background/celestial/PROVENANCE.md`](../modules/ii/background/celestial/PROVENANCE.md).
