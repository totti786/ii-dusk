pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "../modules/settings/configs/dictation/hexSchema.js" as HexSchema

/**
 * Hex's own settings, read and written where Hex keeps them.
 *
 * `~/.local/share/hex/settings.json` is the only source of truth: nothing here is
 * mirrored into the shell's Config, so a change made in Hex's window shows up on
 * the settings page and the other way round. Writes go through
 * `hex settings apply`, which edits the file while Hex is stopped and asks the
 * running Hex otherwise, so flipping a switch never starts it.
 *
 * The setting catalogue, the model list and vocabulary edits need a running Hex.
 * The first two are cached for when it is down, and Hex is only started by an
 * explicit action (`runStarted`).
 */
Singleton {
    id: root

    readonly property string dataDir: `${Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share"}/hex`
    readonly property string bin: DictationService.hexBin

    /** settings.json as parsed. */
    property var stored: ({})
    property bool loaded: false
    /** key -> value written but not yet confirmed. */
    property var pending: ({})
    property var queue: []
    /** `hex settings list` entries, possibly from the cache. */
    property var catalogue: []
    /** key -> Hex's plain description of a Labs feature. */
    property var labDescriptions: ({})
    property var models: []
    property string error: ""
    /** A command that needed Hex running is in flight. */
    readonly property bool busy: actionProc.running
    /** Id of the model being downloaded, empty otherwise. */
    property string installingModel: ""

    readonly property var vocabulary: {
        const list = root.stored.vocabulary;
        if (!Array.isArray(list))
            return [];
        return list.map(entry => typeof entry === "string" ? entry : (entry?.term ?? "")).filter(term => term.length > 0);
    }

    function get(key: string): var {
        if (root.pending.hasOwnProperty(key))
            return root.pending[key];
        return HexSchema.lookup(root.stored, key);
    }

    function on(key: string): bool {
        return root.get(key) === true;
    }

    function set(key: string, value: var): void {
        const change = {};
        change[key] = value;
        root.setMany(change);
    }

    /** Applies several keys at once; Hex takes all of them or none. */
    function setMany(changes: var): void {
        if (!root.loaded || root.bin.length === 0)
            return;
        const next = Object.assign({}, root.pending);
        const body = {};
        for (const key in changes) {
            if (HexSchema.same(root.get(key), changes[key]))
                continue;
            body[key] = changes[key];
            next[key] = changes[key];
        }
        if (Object.keys(body).length === 0)
            return;
        root.error = "";
        root.pending = next;
        root.queue = root.queue.concat([body]);
        root.flush();
    }

    function flush(): void {
        if (applyProc.running || root.queue.length === 0)
            return;
        applyProc.body = root.queue[0];
        root.queue = root.queue.slice(1);
        applyProc.command = ["bash", "-c", "printf '%s' \"$2\" | \"$1\" settings apply - --json",
            "--", root.bin, JSON.stringify(applyProc.body)];
        applyProc.running = true;
    }

    function replyError(text: string): string {
        try {
            const reply = JSON.parse(text);
            return reply.status === "error" ? String(reply.message ?? reply.code ?? "") : "";
        } catch (e) {
            return "";
        }
    }

    Process {
        id: applyProc
        property var body: ({})
        stdout: StdioCollector {
            id: applyOutput
        }
        onExited: code => {
            if (code === 0) {
                // Show the new value until the file watcher has re-read the file.
                let merged = root.stored;
                for (const key in applyProc.body)
                    merged = HexSchema.assign(merged, key, applyProc.body[key]);
                root.stored = merged;
            } else {
                root.error = root.replyError(applyOutput.text) || Translation.tr("Hex did not accept that setting.");
            }
            const next = Object.assign({}, root.pending);
            for (const key in applyProc.body) {
                if (!root.queue.some(change => change.hasOwnProperty(key)))
                    delete next[key];
            }
            root.pending = next;
            file.reload();
            Qt.callLater(() => root.flush());
        }
    }

    FileView {
        id: file
        path: `${root.dataDir}/settings.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.stored = JSON.parse(file.text());
                root.loaded = true;
            } catch (e) {}
        }
        onLoadFailed: root.loaded = false
    }

    // ── Catalogue and models ──────────────────────────────────────────────
    /**
     * Re-reads what Hex can tell us, without starting it: a running Hex refreshes
     * the cache files, a stopped one leaves the last answers in place.
     */
    function refresh(): void {
        if (root.bin.length === 0)
            return;
        file.reload();
        if (!catalogueProc.running)
            catalogueProc.running = true;
        if (!modelsProc.running)
            modelsProc.running = true;
        if (!labsProc.running)
            labsProc.running = true;
    }

    function cachedCommand(name: string, args: var): var {
        return ["bash", "-c",
            'h="$1"; dir="$2"; file="$dir/$3"; shift 3; mkdir -p "$dir"; '
            + 'if out=$(timeout 10 "$h" "$@" 2>/dev/null); then printf "%s" "$out" > "$file"; fi; '
            + 'cat "$file" 2>/dev/null',
            "--", root.bin, DictationService.stateDir, name].concat(args);
    }

    Process {
        id: catalogueProc
        command: root.cachedCommand("hex-settings.json", ["settings", "list", "--json"])
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.catalogue = JSON.parse(text).settings ?? [];
                } catch (e) {}
            }
        }
    }

    Process {
        id: modelsProc
        command: root.cachedCommand("hex-models.json", ["model", "list", "--json"])
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.models = JSON.parse(text).models ?? [];
                } catch (e) {}
            }
        }
    }

    Process {
        id: labsProc
        command: [root.bin, "labs", "list"]
        stdout: StdioCollector {
            onStreamFinished: root.labDescriptions = HexSchema.parseLabs(text)
        }
    }

    // ── Commands that need Hex running ────────────────────────────────────
    /** Starts Hex when it is down, then runs `hex <args>`. For explicit user actions only. */
    function runStarted(args: var): void {
        if (root.bin.length === 0 || actionProc.running)
            return;
        root.error = "";
        actionProc.command = ["bash", "-c",
            'h="$1"; shift; if ! "$h" status >/dev/null 2>&1; then setsid -f "$h" start >/dev/null 2>&1 </dev/null; '
            + 'for i in $(seq 60); do "$h" status >/dev/null 2>&1 && break; sleep 0.5; done; fi; exec "$h" "$@"',
            "--", root.bin].concat(args);
        actionProc.running = true;
    }

    function loadModels(): void {
        root.runStarted(["model", "list", "--json"]);
    }

    function addTerm(term: string, soundsLike: string): void {
        const options = soundsLike.length > 0 ? [`--sounds-like=${soundsLike}`] : [];
        root.runStarted(["vocabulary", "add", "--json"].concat(options, ["--", term]));
    }

    function removeTerm(term: string): void {
        root.runStarted(["vocabulary", "remove", "--json", "--", term]);
    }

    Process {
        id: actionProc
        stdout: StdioCollector {
            id: actionOutput
        }
        onExited: code => {
            if (code !== 0)
                root.error = root.replyError(actionOutput.text) || Translation.tr("Hex could not do that. Open Hex to see why.");
            root.refresh();
        }
    }

    // ── Model downloads ───────────────────────────────────────────────────
    /** Downloads a model and switches to it. The shell keeps Hex running until it ends. */
    function installModel(id: string): void {
        if (root.bin.length === 0 || installProc.running)
            return;
        root.error = "";
        root.installingModel = id;
        installProc.cancelled = false;
        installProc.command = [root.bin, "model", "install", id, "--json"];
        installProc.running = true;
    }

    function cancelInstall(): void {
        if (!installProc.running)
            return;
        installProc.cancelled = true;
        // Tells a running Hex to stop; with Hex stopped the download lives in our own process.
        Quickshell.execDetached([root.bin, "model", "cancel"]);
        installProc.running = false;
    }

    Process {
        id: installProc
        property bool cancelled: false
        stdout: StdioCollector {
            id: installOutput
        }
        onExited: code => {
            if (code !== 0 && !installProc.cancelled)
                root.error = root.replyError(installOutput.text) || Translation.tr("The model download failed.");
            root.installingModel = "";
            root.refresh();
        }
    }
}
