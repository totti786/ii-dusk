# Attribution and licensing

This kit is extracted from `syrianzone/syrianzone` (MIT, Copyright (c) 2025
SYCompass). The source code retains that MIT license — see `LICENSE`.

The **data and media assets are not covered by the MIT license** and carry
their own terms. Verify before redistributing.

## Quran text and Madina page layout

- Source: King Fahd Glorious Quran Printing Complex (KFGQPC), Madina 15-line
  layout, vendored by the upstream project under `public/quran-data/`.
- Files: `mushaf-unified.json`, `hafs-16/manifest.json`,
  `hafs-24/manifest.json`.
- The upstream project treats these as vendored data. No explicit license file
  is shipped with them; confirm KFGQPC's terms for your distribution.

## Hafs Uthmanic font

- File: `public/fonts/quran-hafs.woff2`
- KFGQPC HAFS Uthmanic Script. Same caveat as the text data: verify the font's
  redistribution terms. The upstream project vendors it for offline use.

## Ayah mark rosette

From `src/react/AYAH-MARK-ATTRIBUTION.md` (kept verbatim):

> Ayah-mark rosette artwork vendored from
> https://github.com/quranpedia/ayah-marks
> (file `markers/015-regular.svg`, collection entry `015-regular`,
> codepoint U+E029, number box cx=586.2 cy=291.2 w=522.7 h=290.4).
>
> Source artwork: "DigitalKhattV1" family via fonts.quran.ws
> (https://fonts.quran.ws/assets/fonts/digital-khatt-v1.otf).
>
> **LICENSE WARNING:** the upstream repository marks this source family as
> "unverified — pending confirmation" (see collection.json entry
> `015-regular` → sources[0].license, and the repo's Licensing section:
> "do not redistribute those markers until their terms are confirmed").
> Unlike entry 001-regular (OFL-1.1, SIL Alkalami), no licence is asserted
> for this artwork upstream. It is vendored here at the explicit request of
> the project owner; replace it with an OFL-verified design (e.g. 001) if
> the terms cannot be confirmed.

If you need a clean license chain, replace `marker-015-regular.svg` with an
OFL-verified marker (e.g. `001-regular`) and update the geometry constants in
`src/react/AyahMark.tsx`.

## Recitation audio

- MP3Quran v4 API and CDN (`api-staging.mp3quran.net`, `cdn.mp3quran.net`).
- EveryAyah per-ayah fallback (`everyayah.com`).
- Audio is streamed, not bundled. Review each provider's terms of use for
  commercial or high-volume use. The v4 base is configurable in
  `src/core/config.ts`.

## Calligraphic display fonts (desktop widget)

- `fonts/ArefRuqaa-Regular.ttf` (Aref Ruqaa), `fonts/Katibeh-Regular.ttf` (Katibeh),
  `fonts/Mirza-Regular.ttf` (Mirza): SIL Open Font License 1.1, from the Google Fonts
  repository; the licence texts are alongside (`OFL-*.txt`).
- Used only by the Quran Calligraphy desktop widgets. They lack some of the small Quranic
  recitation signs, which the widgets leave out when these fonts are chosen.
