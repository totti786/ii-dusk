# Celestial wallpaper provenance

This directory ports the visual and astronomy implementation from
[`hadealahmad/kde-moonphase-wallpaper`](https://github.com/hadealahmad/kde-moonphase-wallpaper),
commit `c011962658cc427942a75f32c4f77807b8c7052c` (retrieved 2026-10-21).

The upstream source and shaders are licensed under **GPL-2.0-or-later** and
retain the upstream SPDX copyright notices for Hadi Alahmad. The JavaScript
ephemeris and prayer calculations are kept as dependency-free `.pragma library`
files so the upstream unit tests remain usable.

The five bundled textures are generated from NASA LRO, Blue Marble, Black
Marble, and GEBCO products. NASA imagery is public domain under the NASA media
usage guidelines. Exact source URLs and checksums are recorded by upstream in
[`scripts/earth_assets_provenance.txt`](https://github.com/hadealahmad/kde-moonphase-wallpaper/blob/c011962658cc427942a75f32c4f77807b8c7052c/scripts/earth_assets_provenance.txt).

The Quickshell adapter replaces Plasma `WallpaperItem`/KConfigXT with the
`Config.options.background.celestial` object, uses the existing `PrayerTimes`
weather location/cache when available, and disables its scene while lock,
fullscreen, edit, or Media Mode surfaces cover the desktop.
