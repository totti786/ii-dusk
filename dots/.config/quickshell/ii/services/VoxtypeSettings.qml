pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "../modules/settings/configs/dictation/voxtypeSchema.js" as VoxSchema

/**
 * Voxtype's own settings, read and written where Voxtype keeps them.
 *
 * `~/.config/voxtype/config.toml` is the only source of truth: values come from
 * `voxtype config schema --json` and are written with `voxtype config set`, which
 * validates them and keeps the file's comments. The few keys the shell needs
 * fixed are written by `DictationService.applySettings()`.
 */
Singleton {
    id: root

    readonly property string configPath: `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/voxtype/config.toml`

    /** Schema entries in Voxtype's order, and the same by key. */
    property var keys: []
    property var entries: ({})
    /** Spoken form -> replacement. */
    property var replacements: ({})
    property bool loaded: false
    /** This Voxtype is too old to describe its settings. */
    property bool unsupported: false
    property var modelInfo: null
    /** key -> value written but not yet confirmed. */
    property var pending: ({})
    property var queue: []
    property string error: ""
    readonly property bool writing: writeProc.running || root.queue.length > 0

    readonly property string engine: String(root.get("engine") ?? "whisper")
    readonly property string model: String(root.get(`${root.engine}.model`) ?? "")
    readonly property var models: VoxSchema.models(root.modelInfo, VoxSchema.compiledEngines(root.keys))

    /** Needed for the daemon: read as soon as Voxtype is the engine in use. */
    readonly property bool wanted: DictationService.installed && DictationService.enabled && !DictationService.useHex
    onWantedChanged: {
        if (root.wanted)
            root.refresh();
    }
    Component.onCompleted: {
        if (root.wanted)
            root.refresh();
    }

    function get(key: string): var {
        if (root.pending.hasOwnProperty(key))
            return root.pending[key];
        return root.entries[key]?.value;
    }

    function on(key: string): bool {
        return root.get(key) === true;
    }

    function set(key: string, value: var): void {
        if (!root.loaded || VoxSchema.same(root.get(key), value))
            return;
        const next = Object.assign({}, root.pending);
        next[key] = value;
        root.pending = next;
        root.enqueue({
            key: key,
            value: value,
            restart: root.entries[key]?.restart_required !== false,
            command: VoxSchema.writeCommand(key, value, DictationService.configScript)
        });
    }

    function selectModel(engine: string, model: string): void {
        if (!root.loaded || (engine === root.engine && model === root.model))
            return;
        root.enqueue({
            key: "",
            restart: true,
            command: ["voxtype", "config", "select-model", engine, model]
        });
    }

    /** An empty `to` removes the replacement. */
    function setReplacement(from: string, to: string): void {
        if (!root.loaded || from.length === 0)
            return;
        const key = VoxSchema.replacementKey(from);
        root.enqueue({
            key: "",
            restart: true,
            command: VoxSchema.writeCommand(key, to, DictationService.configScript)
        });
    }

    function enqueue(write: var): void {
        root.error = "";
        root.queue = root.queue.concat([write]);
        root.flush();
    }

    // One writer at a time, including the shell's own: both rewrite the whole file.
    function flush(): void {
        if (writeProc.running || DictationService.configWriting || root.queue.length === 0)
            return;
        writeProc.write = root.queue[0];
        root.queue = root.queue.slice(1);
        writeProc.command = writeProc.write.command;
        writeProc.running = true;
    }

    Process {
        id: writeProc
        property var write: ({})
        stdout: StdioCollector {}
        stderr: StdioCollector {
            id: writeErrors
        }
        onExited: code => {
            const key = writeProc.write.key;
            if (code === 0) {
                // Show the new value until the schema has been re-read.
                if (key.length > 0 && root.entries[key] !== undefined) {
                    const entries = Object.assign({}, root.entries);
                    entries[key] = Object.assign({}, entries[key], {
                        value: writeProc.write.value
                    });
                    root.entries = entries;
                }
                if (writeProc.write.restart)
                    DictationService.requestRestart();
            } else {
                root.error = VoxSchema.errorLine(writeErrors.text) || Translation.tr("Voxtype did not accept that setting.");
            }
            if (key.length > 0 && !root.queue.some(write => write.key === key)) {
                const next = Object.assign({}, root.pending);
                delete next[key];
                root.pending = next;
            }
            root.reload();
            Qt.callLater(() => root.flush());
        }
    }

    FileView {
        id: file
        path: root.configPath
        watchChanges: true
        printErrors: false
        onFileChanged: reloadTimer.restart()
    }

    Timer {
        id: reloadTimer
        interval: 300
        onTriggered: {
            if (root.wanted || root.loaded)
                root.reload();
        }
    }

    // ── Reading ───────────────────────────────────────────────────────────
    function refresh(): void {
        if (!DictationService.installed)
            return;
        // The file may not have existed when the watch was set up.
        file.path = "";
        file.path = root.configPath;
        root.reload();
        modelsProc.again = modelsProc.running;
        modelsProc.running = true;
    }

    function reload(): void {
        if (schemaProc.running)
            schemaProc.again = true;
        else
            schemaProc.running = true;
    }

    Process {
        id: schemaProc
        property bool again: false
        command: ["voxtype", "config", "schema", "--json"]
        stdout: StdioCollector {
            id: schemaOutput
        }
        stderr: StdioCollector {
            id: schemaErrors
        }
        onExited: code => {
            if (code === 0) {
                try {
                    const schema = JSON.parse(schemaOutput.text);
                    const entries = {};
                    schema.keys.forEach(entry => entries[entry.key] = entry);
                    root.entries = entries;
                    root.keys = schema.keys;
                    root.replacements = schema.replacements ?? {};
                    root.unsupported = false;
                    root.loaded = true;
                } catch (e) {
                    root.error = Translation.tr("Voxtype's settings could not be read.");
                }
            } else {
                root.unsupported = schemaErrors.text.indexOf("unrecognized subcommand") !== -1;
                root.loaded = false;
                root.error = root.unsupported ? "" : VoxSchema.errorLine(schemaErrors.text);
            }
            if (schemaProc.again) {
                schemaProc.again = false;
                Qt.callLater(() => schemaProc.running = true);
            }
        }
    }

    Process {
        id: modelsProc
        property bool again: false
        command: ["voxtype", "info", "models", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.modelInfo = JSON.parse(text);
                } catch (e) {}
            }
        }
        onExited: {
            if (modelsProc.again) {
                modelsProc.again = false;
                Qt.callLater(() => modelsProc.running = true);
            }
        }
    }
}
