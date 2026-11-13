pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions

/**
 * Qanun's small persistent store and the native jobs around it.
 *
 * The JSON document holds preferences, compositions, saved provider scores and
 * flashcard statistics. Waveforms and the OpenScore catalogue are cached in
 * memory; the catalogue is mirrored into the document so the library still has
 * something to search when the network is away.
 */
Singleton {
    id: root

    readonly property string stateDir: Directories.state + "/user/qanun"
    readonly property string dataPath: stateDir + "/data.json"
    readonly property string scoresDir: FileUtils.trimFileProtocol(Directories.documents) + "/Qanun Scores"
    readonly property string tunerScript: Quickshell.shellPath("scripts/qanun/tuner.py")
    readonly property string audioScript: Quickshell.shellPath("scripts/qanun/audio.py")
    readonly property string waveformScript: Quickshell.shellPath("scripts/qanun/waveform.py")
    readonly property string scoreScript: Quickshell.shellPath("scripts/qanun/score.py")
    readonly property string catalogUrl: "https://raw.githubusercontent.com/OpenScore/StringQuartets/main/data/scores.tsv"

    readonly property var defaults: ({
        version: 1,
        settings: {
            general: {
                notation: "letters",
                accidentalStyle: "sharps",
                a4: 440,
                instrument: "concert",
                reduceMotion: false
            },
            tuner: {
                autoStart: true,
                showGraph: true,
                inTuneCents: 5,
                historySeconds: 14,
                showFrequency: true,
                referenceTone: false
            },
            metronome: {
                bpm: 96,
                numerator: 4,
                denominator: 4,
                volume: 0.8,
                countIn: false,
                countInBars: 1,
                flash: true,
                accentFirst: true,
                sound: "wood",
                tapResetMs: 2600,
                tracks: [
                    { id: "pulse", name: "Pulse", enabled: true, division: 1, sound: "wood", volume: 0.85 },
                    { id: "subdivision", name: "Subdivision", enabled: false, division: 2, sound: "click", volume: 0.55 }
                ],
                accents: [1, 0, 0, 0]
            },
            flashcards: {
                clef: "both",
                answerMode: "name",
                notation: "letters",
                accidentals: false,
                sound: true,
                autoAdvance: true,
                matchOctave: false,
                micTolerance: 35,
                target: 10,
                showOctave: false
            },
            earTraining: {
                mode: "intervals",
                intervalDirection: "ascending",
                scaleSource: "maqams",
                scaleDirection: "ascending",
                chordSet: "triads",
                singleNoteAccidentals: false,
                autoPlay: true,
                autoAdvance: true
            },
            library: {
                provider: "openscoreStringQuartets"
            }
        },
        compositions: [],
        savedScores: [],
        savedBuiltIns: [],
        stats: {
            answered: 0,
            correct: 0,
            streak: 0,
            bestStreak: 0,
            byNote: {}
        },
        earTrainingStats: {
            answered: 0,
            correct: 0,
            streak: 0,
            bestStreak: 0,
            byMode: {}
        },
        onlineCatalog: [],
        catalogUpdated: 0,
        ui: {
            tab: "tuner",
            railExpanded: true
        }
    })

    property var data: root.defaults
    property bool ready: false
    property bool blockWrites: false
    property real initTimestamp: Date.now()
    property int missingFileGracePeriod: 2200

    readonly property var settings: root.data.settings ?? root.defaults.settings
    readonly property var compositions: root.data.compositions ?? []
    readonly property var savedScores: root.data.savedScores ?? []
    readonly property var savedBuiltIns: root.data.savedBuiltIns ?? []
    readonly property var stats: root.data.stats ?? root.defaults.stats
    readonly property var earStats: root.data.earTrainingStats ?? root.defaults.earTrainingStats
    readonly property var onlineCatalog: root.data.onlineCatalog ?? []

    // Waveforms are extracted on demand and kept for the session.
    property var waveforms: ({})
    property var waveformDurations: ({})
    property var waveformQueue: []
    property string waveformCurrent: ""
    property bool catalogLoading: false
    property string catalogError: ""
    property string downloadingId: ""
    property string downloadError: ""
    property string downloadingTitle: ""
    property var lastDownloaded: null
    property string playingSequenceLabel: ""

    signal toneRequested(real midi, real seconds)
    signal downloadFinished(var result)
    signal audioStopRequested()

    // ── Persistence ─────────────────────────────────────────────────────
    function deepMerge(base, incoming) {
        if (!incoming || typeof incoming !== "object" || Array.isArray(incoming))
            return incoming === undefined ? base : incoming;
        const out = Array.isArray(base) ? [] : Object.assign({}, base ?? {});
        for (const key of Object.keys(incoming)) {
            const value = incoming[key];
            if (value && typeof value === "object" && !Array.isArray(value)
                    && base?.[key] && typeof base[key] === "object" && !Array.isArray(base[key]))
                out[key] = root.deepMerge(base[key], value);
            else
                out[key] = value;
        }
        return out;
    }

    readonly property var normalized: root.deepMerge(root.defaults, root.data)

    function mutate(mutator) {
        const next = JSON.parse(JSON.stringify(root.normalized));
        mutator(next);
        root.data = next;
    }

    function setGeneral(key, value) {
        root.mutate(doc => { doc.settings.general[key] = value; });
    }

    function setTuner(key, value) {
        root.mutate(doc => { doc.settings.tuner[key] = value; });
    }

    function setMetronome(patch) {
        root.mutate(doc => { Object.assign(doc.settings.metronome, patch); });
    }

    function setMetronomeTrack(index, patch) {
        root.mutate(doc => {
            const tracks = doc.settings.metronome.tracks ?? [];
            if (index < 0 || index >= tracks.length)
                return;
            tracks[index] = Object.assign({}, tracks[index], patch);
        });
    }

    function addMetronomeTrack() {
        root.mutate(doc => {
            const tracks = doc.settings.metronome.tracks ?? [];
            if (tracks.length >= 2)
                return;
            tracks.push({
                id: "track" + (tracks.length + 1),
                name: "Track " + (tracks.length + 1),
                enabled: true,
                division: 1,
                sound: "click",
                volume: 0.6
            });
        });
    }

    function removeMetronomeTrack(index) {
        root.mutate(doc => {
            const tracks = doc.settings.metronome.tracks ?? [];
            if (tracks.length <= 1)
                return;
            tracks.splice(index, 1);
        });
    }

    function setAccents(accents) {
        root.mutate(doc => { doc.settings.metronome.accents = Array.from(accents); });
    }

    function setFlashcards(patch) {
        root.mutate(doc => { Object.assign(doc.settings.flashcards, patch); });
    }

    function setEarTraining(patch) {
        root.mutate(doc => { Object.assign(doc.settings.earTraining, patch); });
    }

    function recordEarTraining(correct: bool, mode: string, answerLabel: string) {
        root.mutate(doc => {
            const stats = doc.earTrainingStats ?? JSON.parse(JSON.stringify(root.defaults.earTrainingStats));
            stats.answered = Number(stats.answered ?? 0) + 1;
            if (correct) {
                stats.correct = Number(stats.correct ?? 0) + 1;
                stats.streak = Number(stats.streak ?? 0) + 1;
                stats.bestStreak = Math.max(Number(stats.bestStreak ?? 0), stats.streak);
            } else {
                stats.streak = 0;
            }
            const byMode = Object.assign({}, stats.byMode ?? {});
            const entry = Object.assign({ correct: 0, wrong: 0 }, byMode[mode] ?? {});
            if (correct) entry.correct = Number(entry.correct ?? 0) + 1;
            else entry.wrong = Number(entry.wrong ?? 0) + 1;
            byMode[mode] = entry;
            stats.byMode = byMode;
            doc.earTrainingStats = stats;
        });
    }

    function resetEarTrainingStats() {
        root.mutate(doc => {
            doc.earTrainingStats = JSON.parse(JSON.stringify(root.defaults.earTrainingStats));
        });
    }

    function earAccuracyPercent(): int {
        const answered = Number(root.earStats.answered ?? 0);
        if (answered <= 0)
            return 0;
        return Math.round(100 * Number(root.earStats.correct ?? 0) / answered);
    }

    function setLibrary(key, value) {
        root.mutate(doc => { doc.settings.library[key] = value; });
    }

    function setUi(key, value) {
        root.mutate(doc => { doc.ui[key] = value; });
    }

    function saveComposition(composition) {
        root.mutate(doc => {
            const list = Array.from(doc.compositions ?? []);
            const index = list.findIndex(item => item.id === composition.id);
            if (index >= 0)
                list[index] = composition;
            else
                list.unshift(composition);
            doc.compositions = list;
        });
    }

    function deleteComposition(id) {
        root.mutate(doc => {
            doc.compositions = Array.from(doc.compositions ?? []).filter(item => item.id !== id);
        });
    }

    function toggleBuiltInSave(id) {
        root.mutate(doc => {
            const list = Array.from(doc.savedBuiltIns ?? []);
            const index = list.indexOf(id);
            if (index >= 0)
                list.splice(index, 1);
            else
                list.push(id);
            doc.savedBuiltIns = list;
        });
    }

    function isBuiltInSaved(id): bool {
        return root.savedBuiltIns.includes(id);
    }

    function saveProviderScore(entry) {
        root.mutate(doc => {
            const list = Array.from(doc.savedScores ?? []).filter(item => String(item.id) !== String(entry.id));
            list.unshift(entry);
            doc.savedScores = list;
        });
    }

    function removeSavedScore(id) {
        root.mutate(doc => {
            doc.savedScores = Array.from(doc.savedScores ?? []).filter(item => String(item.id) !== String(id));
        });
    }

    function isProviderSaved(id): bool {
        return root.savedScores.some(item => String(item.id) === String(id));
    }

    function recordAnswer(correct: bool, midi: int, answerLabel: string) {
        root.mutate(doc => {
            const stats = doc.stats ?? root.defaults.stats;
            stats.answered = Number(stats.answered ?? 0) + 1;
            if (correct) {
                stats.correct = Number(stats.correct ?? 0) + 1;
                stats.streak = Number(stats.streak ?? 0) + 1;
                stats.bestStreak = Math.max(Number(stats.bestStreak ?? 0), stats.streak);
            } else {
                stats.streak = 0;
            }
            const key = String(midi);
            const byNote = Object.assign({}, stats.byNote ?? {});
            const entry = Object.assign({ correct: 0, wrong: 0, label: answerLabel }, byNote[key] ?? {});
            if (correct) entry.correct = Number(entry.correct ?? 0) + 1;
            else entry.wrong = Number(entry.wrong ?? 0) + 1;
            entry.label = answerLabel;
            byNote[key] = entry;
            stats.byNote = byNote;
            doc.stats = stats;
        });
    }

    function resetStats() {
        root.mutate(doc => { doc.stats = JSON.parse(JSON.stringify(root.defaults.stats)); });
    }

    function accuracyPercent(): int {
        const answered = Number(root.stats.answered ?? 0);
        if (answered <= 0)
            return 0;
        return Math.round(100 * Number(root.stats.correct ?? 0) / answered);
    }

    // ── Tone playback ───────────────────────────────────────────────────
    property var sequence: []
    property int sequenceIndex: 0
    property int sequenceSerial: 0
    property real sequenceBpm: 90

    function playTone(midi: real, seconds = 1.2) {
        if (!(midi >= 0))
            return;
        const freq = QanunData.frequencyForMidi(midi, root.settings.general.a4 ?? 440);
        toneProcess.command = ["python3", root.audioScript, "tone", String(freq), String(seconds), "0.62"];
        toneProcess.running = true;
        root.toneRequested(midi, seconds);
    }

    function playMidiSequence(notes, bpm = 90, label = "") {
        root.stopSequence();
        root.stopChordPlayback();
        const list = Array.from(notes ?? []).filter(note => note && !note.rest).map(note => {
            const midi = note.midi !== undefined ? note.midi : QanunData.midiForNote(note);
            return {
                midi: midi,
                beats: Math.max(0.1, Number(note.beats ?? note.duration ?? 1)),
                rest: note.rest === true
            };
        });
        if (list.length === 0)
            return;
        root.sequence = list;
        root.sequenceIndex = 0;
        root.sequenceBpm = Math.max(20, Math.min(320, Number(bpm) || 90));
        root.playingSequenceLabel = label;
        root.sequenceSerial++;
        const serial = root.sequenceSerial;
        root._playSequenceStep(serial);
    }

    function _playSequenceStep(serial) {
        if (serial !== root.sequenceSerial || root.sequenceIndex >= root.sequence.length) {
            if (serial === root.sequenceSerial)
                root.playingSequenceLabel = "";
            return;
        }
        const note = root.sequence[root.sequenceIndex];
        const seconds = Math.max(0.08, note.beats * 60 / root.sequenceBpm);
        if (!note.rest)
            root.playTone(note.midi, Math.max(0.25, Math.min(seconds * 1.05, 4.0)));
        root.sequenceIndex++;
        sequenceTimer.interval = Math.max(40, Math.round(seconds * 1000));
        sequenceTimer.restart();
    }

    function stopSequence() {
        sequenceTimer.stop();
        root.sequence = [];
        root.sequenceIndex = 0;
        root.sequenceSerial++;
        root.playingSequenceLabel = "";
    }

    function playChord(midis, seconds = 1.8) {
        root.stopSequence();
        if (chordProcess.running)
            chordProcess.running = false;
        const freqs = Array.from(midis ?? []).filter(midi => Number(midi) >= 0)
            .map(midi => QanunData.frequencyForMidi(Number(midi), root.settings.general.a4 ?? 440))
            .map(freq => String(freq));
        if (freqs.length === 0)
            return;
        chordProcess.command = ["python3", root.audioScript, "chord", freqs.join(","),
            String(seconds), "0.58"];
        chordProcess.running = true;
    }

    function stopChordPlayback() {
        if (chordProcess.running)
            chordProcess.running = false;
    }

    function stopTonePlayback() {
        if (toneProcess.running)
            toneProcess.running = false;
    }

    function stopAllAudio(): void {
        root.stopSequence();
        root.stopChordPlayback();
        root.stopTonePlayback();
        root.audioStopRequested();
    }

    Timer {
        id: sequenceTimer
        repeat: false
        onTriggered: root._playSequenceStep(root.sequenceSerial)
    }

    Process {
        id: toneProcess
        running: false
        stderr: StdioCollector {}
    }

    Process {
        id: chordProcess
        running: false
        stderr: StdioCollector {}
    }

    // ── Waveforms ───────────────────────────────────────────────────────
    function requestWaveform(path: string) {
        const key = String(path ?? "");
        if (key.length === 0 || root.waveforms[key] !== undefined)
            return;
        if (root.waveformCurrent === key || root.waveformQueue.includes(key))
            return;
        root.waveformQueue.push(key);
        root._runNextWaveform();
    }

    function _runNextWaveform() {
        if (waveformProcess.running || root.waveformQueue.length === 0)
            return;
        const path = root.waveformQueue.shift();
        root.waveformCurrent = path;
        waveformProcess.command = ["python3", root.waveformScript, path, "100"];
        waveformProcess.running = true;
    }

    Process {
        id: waveformProcess
        stdout: StdioCollector {
            id: waveformOut
            waitForEnd: true
            onStreamFinished: {
                let parsed = null;
                try {
                    parsed = JSON.parse(String(waveformOut.text ?? ""));
                } catch (error) {
                    parsed = null;
                }
                if (parsed && parsed.ok) {
                    const next = Object.assign({}, root.waveforms);
                    next[root.waveformCurrent] = parsed.peaks ?? [];
                    root.waveforms = next;
                    const durations = Object.assign({}, root.waveformDurations);
                    durations[root.waveformCurrent] = Number(parsed.duration ?? 0);
                    root.waveformDurations = durations;
                } else {
                    const next = Object.assign({}, root.waveforms);
                    next[root.waveformCurrent] = [];
                    root.waveforms = next;
                }
            }
        }
        onExited: (code, status) => {
            root.waveformCurrent = "";
            root._runNextWaveform();
        }
    }

    // ── OpenScore catalogue and downloads ───────────────────────────────
    function fetchCatalog(force = false) {
        if (root.catalogLoading)
            return;
        if (!force && (root.onlineCatalog.length > 0 || root.data.catalogUpdated > 0)) {
            if (Date.now() - Number(root.data.catalogUpdated ?? 0) < 86400000)
                return;
        }
        root.catalogLoading = true;
        root.catalogError = "";
        catalogProcess.command = ["curl", "-fsSL", "--max-time", "30", root.catalogUrl];
        catalogProcess.running = true;
    }

    function parseCatalog(text): var {
        const rows = [];
        const lines = String(text ?? "").split("\n");
        for (let i = 1; i < lines.length; ++i) {
            const line = lines[i].trim();
            if (!line)
                continue;
            const fields = line.split("\t");
            if (fields.length < 3)
                continue;
            const path = fields[1] ?? "";
            const composer = path.split("/")[0].replace(/_/g, " ") || "OpenScore";
            rows.push({
                id: String(fields[0]),
                path: path,
                name: fields[2] ?? ("Score " + fields[0]),
                link: fields[3] ?? "",
                version: fields[4] ?? "",
                imslp: fields[5] ?? "",
                kind: "provider",
                source: "OpenScore String Quartets",
                license: "CC0 1.0",
                composer: composer,
                category: "String quartet",
                difficulty: "Intermediate",
                description: "A public-domain string quartet from the OpenScore corpus, released under CC0."
            });
            if (rows.length >= 240)
                break;
        }
        return rows;
    }

    Process {
        id: catalogProcess
        stdout: StdioCollector {
            id: catalogOut
            waitForEnd: true
            onStreamFinished: {
                if (catalogOut.text && String(catalogOut.text).trim().length > 0) {
                    const rows = root.parseCatalog(String(catalogOut.text));
                    if (rows.length > 0) {
                        root.mutate(doc => {
                            doc.onlineCatalog = rows;
                            doc.catalogUpdated = Date.now();
                        });
                        root.catalogError = "";
                    } else {
                        root.catalogError = "The provider returned an empty catalogue.";
                    }
                }
            }
        }
        onExited: (code, status) => {
            root.catalogLoading = false;
            if (code !== 0 && root.catalogError.length === 0)
                root.catalogError = Translation.tr("Could not reach OpenScore. Showing the cached catalogue.");
        }
    }

    function downloadScore(entry) {
        if (!entry || root.downloadingId.length > 0)
            return;
        root.downloadingId = String(entry.id ?? "");
        root.downloadingTitle = String(entry.name ?? entry.title ?? "");
        root.downloadError = "";
        downloadProcess.command = ["python3", root.scoreScript, "download", String(entry.id), String(entry.path)];
        downloadProcess.running = true;
    }

    Process {
        id: downloadProcess
        stdout: StdioCollector {
            id: downloadOut
            waitForEnd: true
            onStreamFinished: {
                let parsed = null;
                try {
                    parsed = JSON.parse(String(downloadOut.text ?? ""));
                } catch (error) {
                    parsed = null;
                }
                if (parsed && parsed.ok) {
                    const catalogEntry = root.onlineCatalog.find(item => String(item.id) === String(parsed.id));
                    const saved = Object.assign({}, catalogEntry ?? {}, parsed, {
                        kind: "provider",
                        savedAt: Date.now(),
                        title: catalogEntry?.name ?? parsed.title,
                        composer: catalogEntry?.composer ?? parsed.composer,
                        source: "OpenScore String Quartets (CC0)",
                        license: "CC0 1.0"
                    });
                    root.saveProviderScore(saved);
                    root.lastDownloaded = saved;
                    root.downloadFinished(saved);
                } else {
                    root.downloadError = parsed?.error ?? Translation.tr("The score could not be downloaded.");
                }
            }
        }
        onExited: (code, status) => {
            root.downloadingId = "";
            root.downloadingTitle = "";
        }
    }

    function requestPreview(entry) {
        if (!entry || !entry.file)
            return;
        previewProcess.command = ["python3", root.scoreScript, "preview", String(entry.file), "8"];
        previewProcess.pendingId = String(entry.id ?? "");
        previewProcess.running = true;
        root.downloadingId = String(entry.id ?? "");
        root.downloadingTitle = String(entry.title ?? entry.name ?? "");
    }

    Process {
        id: previewProcess
        property string pendingId: ""
        stdout: StdioCollector {
            id: previewOut
            waitForEnd: true
            onStreamFinished: {
                let parsed = null;
                try {
                    parsed = JSON.parse(String(previewOut.text ?? ""));
                } catch (error) {
                    parsed = null;
                }
                if (parsed && parsed.ok) {
                    root.mutate(doc => {
                        doc.savedScores = Array.from(doc.savedScores ?? []).map(item => {
                            if (String(item.id) !== previewProcess.pendingId)
                                return item;
                            return Object.assign({}, item, parsed, { preview: parsed });
                        });
                    });
                    root.lastDownloaded = parsed;
                    root.downloadFinished(parsed);
                } else {
                    root.downloadError = parsed?.error ?? Translation.tr("Could not render this score.");
                }
            }
        }
        onExited: (code, status) => {
            root.downloadingId = "";
            root.downloadingTitle = "";
        }
    }

    function openExternal(url: string) {
        if (String(url ?? "").length > 0)
            Quickshell.execDetached(["xdg-open", String(url)]);
    }

    function openScoresFolder() {
        Quickshell.execDetached(["mkdir", "-p", root.scoresDir]);
        Quickshell.execDetached(["xdg-open", root.scoresDir]);
    }

    // ── File plumbing ───────────────────────────────────────────────────
    property bool _writeQueued: false

    onDataChanged: {
        if (!root.ready || root.blockWrites)
            return;
        writeTimer.restart();
    }

    Timer {
        id: writeTimer
        interval: 120
        repeat: false
        onTriggered: {
            if (!root.ready || root.blockWrites)
                return;
            dataFile.writeAdapter();
        }
    }

    Timer {
        id: reloadTimer
        interval: 500
        repeat: false
        onTriggered: dataFile.reload()
    }

    Process {
        id: mkdirProcess
        command: ["mkdir", "-p", root.stateDir]
        running: true
        onExited: (code, status) => {
            if (code === 0)
                reloadTimer.restart();
            else
                console.log("Qanun: could not create", root.stateDir);
        }
    }

    FileView {
        id: dataFile
        path: root.dataPath
        watchChanges: true
        atomicWrites: true
        blockWrites: root.blockWrites
        onFileChanged: reloadTimer.restart()
        onLoaded: {
            const loaded = dataAdapter.data;
            if (loaded && typeof loaded === "object")
                root.data = root.deepMerge(root.defaults, loaded);
            root.ready = true;
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) {
                root.ready = true;
                return;
            }
            if (Date.now() - root.initTimestamp > root.missingFileGracePeriod) {
                root.ready = true;
                dataFile.writeAdapter();
            } else {
                retryTimer.restart();
            }
        }

        adapter: JsonAdapter {
            id: dataAdapter
            property var data: root.data
        }
    }

    Timer {
        id: retryTimer
        interval: 700
        repeat: false
        onTriggered: dataFile.reload()
    }

    Component.onDestruction: {
        root.blockWrites = true;
        root.stopSequence();
        if (dataFile)
            dataFile.blockWrites = true;
    }
}
