pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * Music theory and public-domain score data for Qanun.
 *
 * Everything here is lookup data and pure formatting: the window, the tabs and
 * the store stay free of note tables. Maqam intervals use 24-TET semitones, so a
 * quarter tone is 0.5. Scale spelling follows the degree letters instead of the
 * chromatic names, which is what keeps Hijaz's F♯ on an F and Rast's neutral
 * third on an E.
 */
Singleton {
    id: root

    readonly property var letterNames: ["C", "D", "E", "F", "G", "A", "B"]
    readonly property var letterSemitones: [0, 2, 4, 5, 7, 9, 11]
    readonly property var solfegeNames: ["Do", "Ré", "Mi", "Fa", "Sol", "La", "Si"]
    readonly property var rootSpellings: [
        { letter: "C", alter: 0 }, { letter: "D", alter: -1 }, { letter: "D", alter: 0 },
        { letter: "E", alter: -1 }, { letter: "E", alter: 0 }, { letter: "F", alter: 0 },
        { letter: "F", alter: 1 }, { letter: "G", alter: 0 }, { letter: "A", alter: -1 },
        { letter: "A", alter: 0 }, { letter: "B", alter: -1 }, { letter: "B", alter: 0 }
    ]

    readonly property var tunerInstruments: [
        { id: "concert", name: "Concert pitch", symbol: "music_note", transpose: 0 },
        { id: "bb", name: "B♭ clarinet / trumpet", symbol: "music_note", transpose: -2 },
        { id: "eb", name: "E♭ alto sax", symbol: "music_note", transpose: -9 },
        { id: "f", name: "F horn", symbol: "music_note", transpose: -7 },
        { id: "guitar", name: "Guitar (sounds 8va)", symbol: "music_note", transpose: 12 },
        { id: "oud", name: "Oud", symbol: "music_note", transpose: 0 },
        { id: "qanun", name: "Qanun", symbol: "music_note", transpose: 0 },
        { id: "violin", name: "Violin", symbol: "music_note", transpose: 0 }
    ]

    readonly property var notationOptions: [
        { id: "letters", label: "C D E" },
        { id: "solfege", label: "Do Ré Mi" },
        { id: "both", label: "Both" }
    ]

    // ── Maqams ──────────────────────────────────────────────────────────
    // Roots are the common Arabic starting pitches, not necessarily C. The
    // intervals include the 24-TET quarter tones (0.5 semitone).
    readonly property var maqams: [
        {
            id: "rast", name: "Rast", arabic: "راست", rootPc: 0,
            intervals: [0, 2, 3.5, 5, 7, 9, 10.5, 12],
            family: "Rast", mood: "Pride, calm, soundness",
            character: [2, 6],
            jins: ["Rast on C (C–F)", "Rast on G (G–C)"],
            description: "The parent of the Rast family and one of the central maqams. Its half-flat third and seventh give the scale its open, dignified colour; the fourth and fifth are perfect anchors."
        },
        {
            id: "bayati", name: "Bayati", arabic: "بياتي", rootPc: 2,
            intervals: [0, 1.5, 3, 5, 7, 8, 10, 12],
            family: "Bayati", mood: "Vitality, intimacy, joy",
            character: [1, 5],
            jins: ["Bayati on D (D–G)", "Nahawand on G (G–C)"],
            description: "A very common maqam in the Levant and in religious chant. The half-flat second is the signature; the upper jins is usually Nahawand or Rast."
        },
        {
            id: "hijaz", name: "Hijaz", arabic: "حجاز", rootPc: 2,
            intervals: [0, 1, 4, 5, 7, 8, 10, 12],
            family: "Hijaz", mood: "Distant desert, longing, drama",
            character: [1, 5],
            jins: ["Hijaz on D (D–G)", "Nahawand on G (G–C)"],
            description: "The augmented second between the second and third degrees is the unmistakable Hijaz colour. It is close to the Western Phrygian dominant scale."
        },
        {
            id: "nahawand", name: "Nahawand", arabic: "نهاوند", rootPc: 2,
            intervals: [0, 2, 3, 5, 7, 8, 10, 12],
            family: "Nahawand", mood: "Tender, reflective, familiar",
            character: [2, 5],
            jins: ["Nahawand on D (D–G)", "Hijaz on G (G–C)"],
            description: "The Arabic natural minor, and the easiest bridge between maqam and Western tonal music. Many songs use Nahawand for a warm, lyrical character."
        },
        {
            id: "kurd", name: "Kurd", arabic: "كرد", rootPc: 2,
            intervals: [0, 1, 3, 5, 7, 8, 10, 12],
            family: "Kurd", mood: "Direct, austere, folk-like",
            character: [1],
            jins: ["Kurd on D (D–G)", "Nahawand on G (G–C)"],
            description: "Kurd is the Arabic Phrygian: a lowered second over a minor third. It is common in folk songs and in pieces that want an unadorned modal colour."
        },
        {
            id: "saba", name: "Saba", arabic: "صبا", rootPc: 2,
            intervals: [0, 1.5, 3, 4, 7, 8, 10, 12],
            family: "Saba", mood: "Sadness, lament, sensitivity",
            character: [1, 3],
            jins: ["Saba on D (D–G♭)", "Hijaz on G (G–C)"],
            description: "Saba's lowered fourth is the heart of its lamenting quality. The neutral second and diminished fourth are meant to be played with expressive intonation."
        },
        {
            id: "huzam", name: "Huzam", arabic: "هزام", rootPc: 3.5,
            intervals: [0, 1.5, 3.5, 5.5, 7, 8.5, 10.5, 12],
            family: "Sikah", mood: "Love, lyricism, yearning",
            character: [0, 4],
            jins: ["Sikah on E½♭ (E–A)", "Hijaz on A (A–D)"],
            description: "Huzam starts on the half-flat Sikah degree. It is one of the most lyrical members of the Sikah family and is often used for love songs and taqasim."
        },
        {
            id: "sikah", name: "Sikah", arabic: "سيكاه", rootPc: 3.5,
            intervals: [0, 1.5, 3.5, 5.5, 7, 8.5, 10.5, 12],
            family: "Sikah", mood: "Love, tenderness, intimacy",
            character: [0, 3],
            jins: ["Sikah on E½♭ (E–A)", "Rast on A (A–D)"],
            description: "Sikah is built on the neutral third of the Rast scale, treated as a tonic. Its colour is soft and vocal, and it is often heard in the adhan and in muwashshah."
        },
        {
            id: "ajam", name: "Ajam", arabic: "عجم", rootPc: 10,
            intervals: [0, 2, 4, 5, 7, 9, 11, 12],
            family: "Ajam", mood: "Bright, open, celebratory",
            character: [2, 6],
            jins: ["Ajam on B♭ (B♭–E♭)", "Ajam on F (F–B♭)"],
            description: "Ajam is the Arabic major scale and a close relative of the Western Ionian mode. It is used for bright instrumental pieces and festive songs."
        },
        {
            id: "jiharkah", name: "Jiharkah", arabic: "جهاركاه", rootPc: 5,
            intervals: [0, 2, 4, 5, 7, 9, 10, 12],
            family: "Ajam", mood: "Noble, warm, song-like",
            character: [6],
            jins: ["Jiharkah on F (F–B♭)", "Ajam on B♭ (B♭–E♭)"],
            description: "Jiharkah is a major-type maqam with a lowered seventh, giving it a Mixolydian warmth. Its name refers to the fourth degree and it is a favourite for songs."
        },
        {
            id: "nikriz", name: "Nikriz", arabic: "نكريز", rootPc: 0,
            intervals: [0, 2, 3, 6, 7, 9, 10, 12],
            family: "Nawa Athar", mood: "Cunning, bittersweet, ornamental",
            character: [2, 3, 6],
            jins: ["Nikriz on C (C–F♯)", "Hijaz on G (G–C)"],
            description: "Nikriz combines a minor third with a raised fourth. It is a favourite for instrumental taqasim and for modulations with a bittersweet edge."
        },
        {
            id: "nawaAthar", name: "Nawa Athar", arabic: "نوى أثر", rootPc: 0,
            intervals: [0, 2, 3, 6, 7, 9, 11, 12],
            family: "Nawa Athar", mood: "Mysterious, arching, dramatic",
            character: [2, 3, 6],
            jins: ["Nawa Athar on C (C–F♯)", "Hijaz on G (G–C)"],
            description: "Nawa Athar is the best-known maqam in its family. The raised fourth and major seventh create a wide, arching scale with a strong pull to the tonic."
        }
    ]

    // ── Western scales ──────────────────────────────────────────────────
    readonly property var westernScales: [
        { id: "major", name: "Major (Ionian)", family: "Diatonic", intervals: [0, 2, 4, 5, 7, 9, 11, 12], mood: "Bright, stable, resolved", description: "The reference seven-note scale. Its pattern of whole and half steps is W–W–H–W–W–W–H.", jins: ["Ionian", "Major"] },
        { id: "naturalMinor", name: "Natural minor (Aeolian)", family: "Diatonic", intervals: [0, 2, 3, 5, 7, 8, 10, 12], mood: "Wistful, serious, open", description: "The relative minor of the major scale: lowered third, sixth and seventh. It is also the parent shape of maqam Nahawand.", jins: ["Aeolian", "Minor"] },
        { id: "harmonicMinor", name: "Harmonic minor", family: "Minor", intervals: [0, 2, 3, 5, 7, 8, 11, 12], mood: "Dramatic, tense, classical", description: "A raised seventh gives the harmonic minor its leading tone and augmented second. Common in Baroque, metal and Middle Eastern-flavoured music.", jins: ["Minor", "Leading tone"] },
        { id: "melodicMinor", name: "Melodic minor (ascending)", family: "Minor", intervals: [0, 2, 3, 5, 7, 9, 11, 12], mood: "Restless, lyrical, jazz", description: "Ascending, the sixth and seventh are raised; descending it usually becomes natural minor. It is the basis of many jazz colours.", jins: ["Jazz minor"] },
        { id: "dorian", name: "Dorian", family: "Modes", intervals: [0, 2, 3, 5, 7, 9, 10, 12], mood: "Hopeful, cool, Dorian", description: "A minor mode with a raised sixth. It sits between natural minor and minor pentatonic in feel and is common in modal jazz and folk music.", jins: ["Minor", "Raised 6"] },
        { id: "phrygian", name: "Phrygian", family: "Modes", intervals: [0, 1, 3, 5, 7, 8, 10, 12], mood: "Dark, Spanish, austere", description: "The lowered second is the Phrygian fingerprint. Maqam Kurd has the same pitch set in its common lower jins.", jins: ["Minor", "♭2"] },
        { id: "lydian", name: "Lydian", family: "Modes", intervals: [0, 2, 4, 6, 7, 9, 11, 12], mood: "Airy, floating, bright", description: "A major mode with a raised fourth. Film composers use its wide, unresolved brightness for wonder and flight.", jins: ["Major", "♯4"] },
        { id: "mixolydian", name: "Mixolydian", family: "Modes", intervals: [0, 2, 4, 5, 7, 9, 10, 12], mood: "Warm, bluesy, resolved", description: "A major mode with a lowered seventh. It is the sound of folk, rock and many maqam Ajam-adjacent melodies.", jins: ["Major", "♭7"] },
        { id: "locrian", name: "Locrian", family: "Modes", intervals: [0, 1, 3, 5, 6, 8, 10, 12], mood: "Unstable, diminished, tense", description: "The darkest diatonic mode, with a lowered fifth. Its tonic triad is diminished, so it rarely settles.", jins: ["Diminished"] },
        { id: "doubleHarmonic", name: "Double harmonic", family: "Synthetic", intervals: [0, 1, 4, 5, 7, 8, 11, 12], mood: "Exotic, ceremonial, tense", description: "Two augmented seconds create the 'gypsy major' or Byzantine sound. Maqam Hijaz Kar is its close relative.", jins: ["Hijaz", "Raised 7"] },
        { id: "phrygianDominant", name: "Phrygian dominant", family: "Synthetic", intervals: [0, 1, 4, 5, 7, 8, 10, 12], mood: "Flamenco, desert, dramatic", description: "The fifth mode of harmonic minor and the Western name for maqam Hijaz. The augmented second sits between ♭2 and 3.", jins: ["Hijaz"] },
        { id: "majorPentatonic", name: "Major pentatonic", family: "Pentatonic", intervals: [0, 2, 4, 7, 9, 12], mood: "Open, folk, hopeful", description: "Five notes with no semitones. It is forgiving over major harmony and common in folk melodies worldwide.", jins: ["Pentatonic"] },
        { id: "minorPentatonic", name: "Minor pentatonic", family: "Pentatonic", intervals: [0, 3, 5, 7, 10, 12], mood: "Earthy, direct, bluesy", description: "The five-note minor scale behind countless riffs and folk tunes. Adding a ♭5 produces the blues scale.", jins: ["Pentatonic"] },
        { id: "blues", name: "Blues", family: "Pentatonic", intervals: [0, 3, 5, 6, 7, 10, 12], mood: "Gritty, vocal, expressive", description: "The minor pentatonic plus a blue note between the fourth and fifth. The blue note is often bent rather than fixed.", jins: ["Blues"] },
        { id: "wholeTone", name: "Whole tone", family: "Synthetic", intervals: [0, 2, 4, 6, 8, 10, 12], mood: "Dreamlike, weightless, ambiguous", description: "Only whole steps, so every note is the same distance apart and no tonic triad is stable. A favourite of Debussy and film fantasy.", jins: ["Symmetric"] }
    ]

    // ── Qanun ───────────────────────────────────────────────────────────
    readonly property var qanunMandalCounts: [0, 2, 3, 3,
        4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
        3, 1, 1]

    /// 26 courses, G2 at the bottom to D6 at the top, diatonically tuned.
    readonly property var qanunStrings: {
        const result = [];
        const steps = [2, 2, 1, 2, 2, 1, 2];
        let midi = 43; // G2
        for (let i = 0; i < 26; ++i) {
            const pc = midi % 12;
            const octave = Math.floor(midi / 12) - 1;
            const letterIndex = [0, 2, 4, 5, 7, 9, 11].indexOf(pc);
            result.push({
                index: i,
                midi: midi,
                letter: root.letterNames[Math.max(0, letterIndex)],
                octave: octave,
                name: root.letterNames[Math.max(0, letterIndex)] + octave,
                mandals: root.qanunMandalCounts[i]
            });
            midi += steps[i % 7];
        }
        return result;
    }

    // ── Built-in library ────────────────────────────────────────────────
    // Original, public-domain melodies encoded as "pitch:beats" tokens. A
    // trailing h means half-flat (for the Arabic exercises), # and b are the
    // ordinary accidentals. The app never claims these are critical editions.
    readonly property var builtInScores: [
        {
            id: "ode-to-joy", title: "Ode to Joy", composer: "Ludwig van Beethoven",
            category: "Western", region: "Europe", era: "Classical", difficulty: "Beginner",
            license: "Public domain", clef: "treble", key: 0, time: [4, 4], tempo: 100,
            description: "The main theme from the final movement of Beethoven's Ninth Symphony, reduced to its first phrase.",
            melody: "E4:1 E4:1 F4:1 G4:1 G4:1 F4:1 E4:1 D4:1 C4:1 C4:1 D4:1 E4:1 E4:1 D4:1 D4:2 E4:1 E4:1 F4:1 G4:1 G4:1 F4:1 E4:1 D4:1 C4:1 C4:1 D4:1 E4:1 D4:1 C4:1 C4:2"
        },
        {
            id: "twinkle", title: "Twinkle, Twinkle, Little Star", composer: "Traditional",
            category: "Western", region: "Europe", era: "Traditional", difficulty: "Beginner",
            license: "Public domain", clef: "treble", key: 0, time: [4, 4], tempo: 96,
            description: "The French melody 'Ah! vous dirai-je, maman', heard in countless children's songs.",
            melody: "C4:1 C4:1 G4:1 G4:1 A4:1 A4:1 G4:2 F4:1 F4:1 E4:1 E4:1 D4:1 D4:1 C4:2 G4:1 G4:1 F4:1 F4:1 E4:1 E4:1 D4:2 G4:1 G4:1 F4:1 F4:1 E4:1 E4:1 D4:2"
        },
        {
            id: "happy-birthday", title: "Happy Birthday to You", composer: "Patty & Mildred Hill",
            category: "Western", region: "North America", era: "Traditional", difficulty: "Beginner",
            license: "Public domain", clef: "treble", key: 0, time: [3, 4], tempo: 120,
            description: "The four-phrase birthday song, in C major. A good first sight-reading exercise for dotted rhythms.",
            melody: "G4:0.75 G4:0.25 A4:1 G4:1 C5:1 B4:2 G4:0.75 G4:0.25 A4:1 G4:1 D5:1 C5:2 G4:0.75 G4:0.25 G5:1 E5:1 C5:1 B4:1 A4:2 F5:0.75 F5:0.25 E5:1 C5:1 D5:1 C5:2"
        },
        {
            id: "frere-jacques", title: "Frère Jacques", composer: "Traditional",
            category: "Western", region: "Europe", era: "Traditional", difficulty: "Beginner",
            license: "Public domain", clef: "treble", key: 0, time: [4, 4], tempo: 104,
            description: "A round in C major. The melody rises stepwise and returns, ideal for reading intervals.",
            melody: "C4:1 D4:1 E4:1 C4:1 C4:1 D4:1 E4:1 C4:1 E4:1 F4:1 G4:2 E4:1 F4:1 G4:2 G4:0.5 A4:0.5 G4:0.5 F4:0.5 E4:1 C4:1 G4:0.5 A4:0.5 G4:0.5 F4:0.5 E4:1 C4:1 C4:1 G4:1 C4:2 C4:1 G4:1 C4:2"
        },
        {
            id: "au-clair", title: "Au clair de la lune", composer: "Traditional",
            category: "Western", region: "France", era: "Traditional", difficulty: "Beginner",
            license: "Public domain", clef: "treble", key: 0, time: [4, 4], tempo: 92,
            description: "An old French folk song in C major, with a simple call-and-answer shape.",
            melody: "C4:1 C4:1 C4:1 D4:1 E4:2 D4:2 C4:1 E4:1 D4:1 D4:1 C4:2 C4:1 C4:1 C4:1 D4:1 E4:2 D4:2 C4:1 E4:1 D4:1 D4:1 C4:2"
        },
        {
            id: "amazing-grace", title: "Amazing Grace", composer: "John Newton",
            category: "Western", region: "Atlantic", era: "Traditional", difficulty: "Beginner",
            license: "Public domain", clef: "treble", key: 0, time: [3, 4], tempo: 76,
            description: "The pentatonic hymn tune 'New Britain'. The melody outlines a G major pentatonic scale.",
            melody: "G4:2 C5:1 E5:3 C5:1 E5:2 D5:1 C5:3 A4:1 G4:2 A4:1 C5:1 G4:3 E4:1 G4:2 C5:1 E5:3 C5:1 E5:2 D5:1 C5:3 A4:1 G4:2 A4:1 C5:1 G4:3"
        },
        {
            id: "scarborough", title: "Scarborough Fair", composer: "Traditional",
            category: "Western", region: "England", era: "Traditional", difficulty: "Intermediate",
            license: "Public domain", clef: "treble", key: 0, time: [3, 4], tempo: 80,
            description: "An English ballad in Dorian colour, with the raised sixth that defines the mode.",
            melody: "A4:2 A4:1 E5:2 E5:1 B4:2 C5:1 B4:2 A4:1 G4:2 A4:1 B4:2 C5:1 A4:2 A4:1 G4:2 A4:1 B4:2 E5:1 D5:2 B4:1 A4:2 A4:1 G4:2 A4:1 B4:2 C5:1 A4:3"
        },
        {
            id: "sakura", title: "Sakura Sakura", composer: "Traditional",
            category: "Western", region: "Japan", era: "Traditional", difficulty: "Beginner",
            license: "Public domain", clef: "treble", key: 0, time: [4, 4], tempo: 72,
            description: "A Japanese folk melody in the miyako-bushi (hirajoshi) scale. In this simple setting the flat second and raised fourth carry the colour.",
            melody: "A4:1 A4:1 B4:2 A4:1 A4:1 B4:2 A4:1 B4:1 C5:1 B4:1 A4:2 F4:1 E4:1 F4:1 A4:1 B4:1 A4:1 F4:1 E4:2"
        },
        {
            id: "rast-study", title: "Rast — Qanun study", composer: "Qanun",
            category: "Arabic", region: "Levant", era: "Contemporary", difficulty: "Beginner",
            license: "Original exercise", clef: "treble", key: 0, time: [4, 4], tempo: 84,
            description: "An ascending and descending Rast exercise in C, written with the half-flat third and seventh. Listen for the neutral intervals rather than treating them as E♭ and B♭.",
            melody: "C4:1 D4:1 E4h:1 F4:1 G4:1 A4:1 B4h:1 C5:1 C5:1 B4h:1 A4:1 G4:1 F4:1 E4h:1 D4:1 C4:1"
        },
        {
            id: "hijaz-study", title: "Hijaz — Qanun study", composer: "Qanun",
            category: "Arabic", region: "Levant", era: "Contemporary", difficulty: "Beginner",
            license: "Original exercise", clef: "treble", key: 0, time: [4, 4], tempo: 84,
            description: "A Hijaz exercise on D. The E♭ to F♯ augmented second is the scale's defining gesture; keep the fourth and fifth open underneath it.",
            melody: "D4:1 E4b:1 F4#:1 G4:1 A4:1 B4b:1 C5:1 D5:1 D5:1 C5:1 B4b:1 A4:1 G4:1 F4#:1 E4b:1 D4:1"
        },
        {
            id: "bayati-study", title: "Bayati — Qanun study", composer: "Qanun",
            category: "Arabic", region: "Levant", era: "Contemporary", difficulty: "Intermediate",
            license: "Original exercise", clef: "treble", key: 0, time: [4, 4], tempo: 80,
            description: "A Bayati phrase on D with the characteristic half-flat E. The second phrase answers the first a fourth above.",
            melody: "D4:1 E4h:1 F4:1 G4:2 A4:1 G4:1 F4:1 E4h:1 D4:2 G4:1 A4:1 B4b:1 C5:1 D5:2 C5:1 B4b:1 A4:1 G4:1 F4:1 E4h:1 D4:2"
        },
        {
            id: "nahawand-song", title: "Nahawand — lyric phrase", composer: "Qanun",
            category: "Arabic", region: "Levant", era: "Contemporary", difficulty: "Beginner",
            license: "Original exercise", clef: "treble", key: 0, time: [4, 4], tempo: 76,
            description: "A short Nahawand melody that leans on the minor sixth. It can be played with the Nahawand scale on D or transposed.",
            melody: "D4:1 F4:1 A4:1 G4:1 F4:2 E4:1 D4:1 E4:1 F4:2 G4:1 F4:1 E4:1 D4:1 C4:1 D4:3"
        }
    ]

    // ── Note math ───────────────────────────────────────────────────────
    function frequencyForMidi(midi: real, a4 = 440): real {
        return Number(a4) * Math.pow(2, (Number(midi) - 69) / 12);
    }

    function midiForFrequency(freq: real, a4 = 440): real {
        if (!(freq > 0))
            return -1;
        return 69 + 12 * Math.log(freq / Number(a4)) / Math.LN2;
    }

    function centsOff(freq: real, target: real): real {
        if (!(freq > 0) || !(target > 0))
            return 0;
        return 1200 * Math.log(freq / target) / Math.LN2;
    }

    function accidentalText(alter: real): string {
        const value = Number(alter) || 0;
        if (Math.abs(value) < 0.01)
            return "";
        if (Math.abs(value - 0.5) < 0.01)
            return "½♯";
        if (Math.abs(value + 0.5) < 0.01)
            return "½♭";
        if (Math.abs(value - 1) < 0.01)
            return "♯";
        if (Math.abs(value + 1) < 0.01)
            return "♭";
        if (Math.abs(value - 2) < 0.01)
            return "𝄪";
        if (Math.abs(value + 2) < 0.01)
            return "𝄫";
        return (value > 0 ? "+" : "") + String(value);
    }

    function noteLabel(letter: string, alter: real, notation = "letters"): string {
        const letterIndex = root.letterNames.indexOf(String(letter).toUpperCase());
        if (letterIndex < 0)
            return String(letter);
        const accidental = root.accidentalText(alter);
        if (notation === "solfege")
            return root.solfegeNames[letterIndex] + accidental;
        if (notation === "both")
            return root.letterNames[letterIndex] + accidental + " · " + root.solfegeNames[letterIndex] + accidental;
        return root.letterNames[letterIndex] + accidental;
    }

    function spellMidi(midi: int, preferFlats = false, notation = "letters"): var {
        const safe = Math.max(0, Math.min(127, Math.round(midi)));
        const pc = safe % 12;
        const octave = Math.floor(safe / 12) - 1;
        const naturalIndex = root.letterSemitones.indexOf(pc);
        if (naturalIndex >= 0) {
            return {
                midi: safe, letter: root.letterNames[naturalIndex], alter: 0, octave: octave,
                label: root.noteLabel(root.letterNames[naturalIndex], 0, notation)
            };
        }
        // Black keys: choose the spelling the user asked for.
        const sharpLetter = pc === 1 ? "C" : pc === 3 ? "D" : pc === 6 ? "F" : pc === 8 ? "G" : "A";
        const flatLetter = pc === 1 ? "D" : pc === 3 ? "E" : pc === 6 ? "G" : pc === 8 ? "A" : "B";
        const letter = preferFlats ? flatLetter : sharpLetter;
        const alter = preferFlats ? -1 : 1;
        return {
            midi: safe, letter: letter, alter: alter, octave: octave,
            label: root.noteLabel(letter, alter, notation)
        };
    }

    function midiLabel(midi: int, notation = "letters", preferFlats = false): string {
        return root.spellMidi(midi, preferFlats, notation).label;
    }

    function tunerReading(freq: real, a4 = 440, preferFlats = false, notation = "letters"): var {
        if (!(freq > 0) || !isFinite(freq))
            return { valid: false, freq: 0, cents: 0, label: "—", octave: 0, target: 0, midi: -1 };
        const exact = root.midiForFrequency(freq, a4);
        const nearest = Math.round(exact);
        const target = root.frequencyForMidi(nearest, a4);
        const info = root.spellMidi(nearest, preferFlats, notation);
        return {
            valid: true,
            freq: Number(freq),
            cents: root.centsOff(freq, target),
            target: target,
            midi: nearest,
            label: info.label,
            letter: info.letter,
            alter: info.alter,
            octave: info.octave,
            exactMidi: exact
        };
    }

    function noteText(note, notation = "letters"): string {
        if (!note)
            return "—";
        if (note.rest)
            return "Rest";
        return root.noteLabel(note.letter, note.alter ?? 0, notation) + (note.octave !== undefined ? String(note.octave) : "");
    }

    function midiForNote(note): int {
        if (!note || note.rest)
            return -1;
        const index = root.letterNames.indexOf(String(note.letter ?? "C").toUpperCase());
        if (index < 0)
            return 60;
        return (Number(note.octave ?? 4) + 1) * 12 + root.letterSemitones[index] + Number(note.alter ?? 0);
    }

    function noteForMidi(midi: real, preferFlats = false): var {
        const info = root.spellMidi(Math.round(midi), preferFlats);
        return { letter: info.letter, alter: info.alter, octave: info.octave, midi: info.midi };
    }

    // ── Scales ──────────────────────────────────────────────────────────
    function rootSpelling(pc: real): var {
        const value = ((Number(pc) % 12) + 12) % 12;
        const whole = Math.floor(value);
        const half = Math.abs(value - whole) > 0.01;
        if (half) {
            // Half-flat is the Arabic convention: E half-flat sits between E♭ and
            // E, so spell it as the natural note above with a -½ alteration.
            const naturals = [0, 2, 4, 5, 7, 9, 11];
            for (let i = 0; i < naturals.length; ++i) {
                if (naturals[i] > value) {
                    return {
                        letter: root.letterNames[i],
                        alter: value - naturals[i],
                        pc: value
                    };
                }
            }
            return { letter: "C", alter: value - 12, pc: value };
        }
        const spelling = root.rootSpellings[whole % 12];
        return { letter: spelling.letter, alter: spelling.alter, pc: value };
    }

    function scaleNotes(scale, rootPc, notation = "letters"): var {
        if (!scale)
            return [];
        const baseRoot = rootPc !== undefined && rootPc !== null ? Number(rootPc) : Number(scale.rootPc ?? 0);
        const rootInfo = root.rootSpelling(baseRoot);
        const rootLetterIndex = root.letterNames.indexOf(rootInfo.letter);
        const degrees = [];
        for (let i = 0; i < scale.intervals.length; ++i) {
            const interval = Number(scale.intervals[i]);
            const targetMidi = 60 + baseRoot + interval;
            const octave = Math.floor(targetMidi / 12) - 1;
            const letter = root.letterNames[(rootLetterIndex + i) % 7];
            const naturalMidi = (octave + 1) * 12 + root.letterSemitones[root.letterNames.indexOf(letter)];
            let alter = targetMidi - naturalMidi;
            if (alter > 6) alter -= 12;
            if (alter < -6) alter += 12;
            if (alter > 2) alter -= 12;
            if (alter < -2) alter += 12;
            degrees.push({
                degree: i + 1,
                midi: targetMidi,
                letter: letter,
                alter: alter,
                octave: octave,
                name: root.noteLabel(letter, alter, notation),
                fullName: root.noteLabel(letter, alter, notation) + String(octave),
                solfege: root.noteLabel(letter, alter, "solfege"),
                frequency: root.frequencyForMidi(targetMidi)
            });
        }
        return degrees;
    }

    function scaleIntervalLabels(scale): var {
        if (!scale)
            return [];
        const result = [];
        for (let i = 1; i < scale.intervals.length; ++i) {
            const step = scale.intervals[i] - scale.intervals[i - 1];
            if (Math.abs(step - 2) < 0.01)
                result.push("W");
            else if (Math.abs(step - 1) < 0.01)
                result.push("H");
            else if (Math.abs(step - 1.5) < 0.01)
                result.push("¾");
            else if (Math.abs(step - 0.5) < 0.01)
                result.push("¼");
            else if (Math.abs(step - 3) < 0.01)
                result.push("A2");
            else
                result.push(String(step));
        }
        return result;
    }

    function scaleFormula(scale): string {
        return root.scaleIntervalLabels(scale).join(" · ");
    }

    function scaleDegreeText(scale, degreeIndex): string {
        const names = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"];
        return names[degreeIndex] ?? String(degreeIndex + 1);
    }

    function allScales(category = "all"): var {
        const result = [];
        if (category === "all" || category === "maqam") {
            for (let i = 0; i < root.maqams.length; ++i) {
                const item = Object.assign({}, root.maqams[i]);
                item.category = "maqam";
                item.kind = "Arabic maqam";
                item.searchText = (item.name + " " + item.arabic + " " + item.family + " " + item.mood).toLowerCase();
                result.push(item);
            }
        }
        if (category === "all" || category === "western") {
            for (let i = 0; i < root.westernScales.length; ++i) {
                const item = Object.assign({}, root.westernScales[i]);
                item.category = "western";
                item.kind = "Western scale";
                item.searchText = (item.name + " " + item.family + " " + item.mood).toLowerCase();
                result.push(item);
            }
        }
        return result;
    }

    function findScale(id): var {
        return root.allScales("all").find(item => item.id === id) ?? null;
    }

    // ── Score melody parsing ────────────────────────────────────────────
    function parseMelody(spec: string): var {
        const tokens = String(spec ?? "").trim().split(/\s+/);
        const notes = [];
        for (const token of tokens) {
            if (!token)
                continue;
            const parts = token.split(":");
            const pitch = parts[0];
            const beats = Math.max(0.05, Number(parts[1] ?? 1) || 1);
            if (pitch === "R" || pitch === "r") {
                notes.push({ rest: true, duration: beats, letter: "B", alter: 0, octave: 4, midi: -1 });
                continue;
            }
            const match = /^([A-Ga-g])([#b]?)(\d)(h?)$/.exec(pitch);
            if (!match)
                continue;
            const letter = match[1].toUpperCase();
            let alter = match[2] === "#" ? 1 : match[2] === "b" ? -1 : 0;
            if (match[4] === "h")
                alter -= 0.5;
            const octave = Number(match[3]);
            const letterIndex = root.letterNames.indexOf(letter);
            notes.push({
                rest: false,
                letter: letter,
                alter: alter,
                octave: octave,
                duration: beats,
                dotted: false,
                tie: false,
                midi: (octave + 1) * 12 + root.letterSemitones[letterIndex] + alter
            });
        }
        return notes;
    }

    function scoreNotes(score): var {
        if (!score)
            return [];
        if (score.melody)
            return root.parseMelody(score.melody);
        if (score.notes)
            return Array.from(score.notes);
        if (score.preview && score.preview.notes)
            return Array.from(score.preview.notes);
        return [];
    }

    function scoreSearchText(score): string {
        if (!score)
            return "";
        return [score.title, score.composer, score.category, score.region, score.era,
            score.difficulty, score.description, score.source].join(" ").toLowerCase();
    }

    function tempoMarking(bpm: real): string {
        const value = Number(bpm) || 0;
        if (value < 40) return "Grave";
        if (value < 60) return "Largo";
        if (value < 66) return "Larghetto";
        if (value < 76) return "Adagio";
        if (value < 108) return "Andante";
        if (value < 120) return "Moderato";
        if (value < 156) return "Allegro";
        if (value < 176) return "Vivace";
        if (value < 200) return "Presto";
        return "Prestissimo";
    }

    function metronomeSoundPacks(): var {
        return [
            { id: "click", name: "Click", accent: "assets/audio/click-accent.wav", beat: "assets/audio/click-beat.wav", sub: "assets/audio/click-sub.wav" },
            { id: "wood", name: "Wood", accent: "assets/audio/wood-accent.wav", beat: "assets/audio/wood-beat.wav", sub: "assets/audio/wood-sub.wav" },
            { id: "beep", name: "Beep", accent: "assets/audio/beep-accent.wav", beat: "assets/audio/beep-beat.wav", sub: "assets/audio/beep-sub.wav" }
        ];
    }

    function notePoolForClef(clef: string, accidentals = false): var {
        const result = [];
        const ranges = clef === "treble" ? [[60, 81]] : clef === "bass" ? [[36, 57]] : [[60, 81], [36, 57]];
        for (const range of ranges) {
            for (let midi = range[0]; midi <= range[1]; ++midi) {
                if (!accidentals && ![0, 2, 4, 5, 7, 9, 11].includes(midi % 12))
                    continue;
                result.push(midi);
            }
        }
        return result;
    }
}
