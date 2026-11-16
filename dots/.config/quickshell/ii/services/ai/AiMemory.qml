pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * What the assistant is allowed to remember between conversations.
 *
 * A persona says how to answer; this says what is already known — the distro,
 * the editor, how someone likes their code reviewed. Every fact is a line the
 * user can read, edit and delete, kept in its own file rather than buried in
 * the system prompt, and nothing is written without the user seeing it: the
 * model can only propose a fact through a tool that asks first.
 *
 * The file is a plain JSON list so it can be edited by hand, and it is
 * separate from config.json and from the sessions, both of which have their
 * own lifetimes.
 */
Singleton {
    id: root

    readonly property string path: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/memory.json`)
    property bool loaded: false
    /** Facts, newest last: {id, text, at, source}. */
    property var facts: []
    property var skills: []
    property var learning: ({state: "idle", counts: {pending: 0}})
    FileView {
        id: learningFile
        path: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/learning-status.json`)
        watchChanges: true
        printErrors: false
        onFileChanged: learningFile.reload()
        onLoaded: { try { root.learning = JSON.parse(learningFile.text()); } catch (error) {} }
    }
    readonly property string skillsPath: (Quickshell.env("XDG_DATA_HOME") || (FileUtils.trimFileProtocol(Directories.home) + "/.local/share")) + "/quickshell-ii/skills/index.json"
    function forgetSkill(id: string): void {
        root.queueWrite("memory_forget", {id: id});
    }
    FileView {
        id: skillsFile
        path: root.skillsPath
        watchChanges: true
        printErrors: false
        onFileChanged: skillsFile.reload()
        onLoaded: {
            try { root.skills = JSON.parse(skillsFile.text()).skills ?? []; }
            catch (error) { root.skills = []; }
        }
        onLoadFailed: root.skills = []
    }

    readonly property bool enabled: Config.options?.ai?.memory?.enabled ?? true
    readonly property int limit: Math.max(0, Config.options?.ai?.memory?.limit ?? 40)

    /** The block that goes into the system prompt, empty when there is nothing. */
    readonly property string promptBlock: {
        if (!root.enabled || root.facts.length === 0)
            return "";
        const lines = root.facts.map(fact => `- ${fact.text}`).join("\n");
        return `## What you already know about this user\n${lines}`;
    }

    signal factAdded(string text)

    function newId(): string {
        return `m${Date.now().toString(36)}${Math.floor(Math.random() * 1000).toString(36)}`;
    }

    property var pendingWrites: []
    property string errorText: ""
    function queueWrite(tool: string, args: var): void {
        root.pendingWrites = root.pendingWrites.concat([{tool: tool, args: args}]);
        root.startWrite();
    }
    function startWrite(): void {
        if (memoryWriter.running || root.pendingWrites.length === 0) return;
        const job = root.pendingWrites[0];
        root.pendingWrites = root.pendingWrites.slice(1);
        memoryWriter.command = ["python3", FileUtils.trimFileProtocol(Directories.scriptPath) + "/ai/agent_memory.py", job.tool, JSON.stringify(job.args)];
        memoryWriter.running = true;
    }
    Process {
        id: memoryWriter
        stdout: StdioCollector { id: writeOutput }
        onExited: (code, status) => {
            let answer = {};
            try { answer = JSON.parse(writeOutput.text); } catch (error) {}
            root.errorText = code === 0 ? "" : String(answer.error || "Memory could not be saved.");
            memoryFile.reload();
            skillsFile.reload();
            Qt.callLater(root.startWrite);
        }
    }
    function remember(text: string, source = "user"): bool {
        const value = String(text ?? "").trim();
        if (!root.enabled || root.limit === 0 || value.length === 0) return false;
        root.queueWrite("remember_fact", {fact: value, source: source});
        return true;
    }
    function forget(id: string): bool {
        if (!root.facts.some(fact => fact.id === id)) return false;
        root.queueWrite("memory_forget", {id: id});
        return true;
    }
    function edit(id: string, text: string): bool {
        const value = String(text ?? "").trim();
        if (!value.length) return root.forget(id);
        const fact = root.facts.find(item => item.id === id);
        if (!fact) return false;
        root.queueWrite("remember_fact", {id: id, fact: value, key: fact.key ?? "", projectId: fact.projectId ?? "", source: "user"});
        return true;
    }
    function forgetAll(): void {
        for (const fact of root.facts) root.queueWrite("memory_forget", {id: fact.id});
    }

    function save() {
        if (!root.loaded)
            return;
        memoryFile.setText(JSON.stringify({
            schema: 1,
            facts: root.facts
        }, null, 2));
    }

    Process {
        id: initializeMemory
        running: true
        command: ["python3", FileUtils.trimFileProtocol(Directories.scriptPath) + "/ai/agent_memory.py", "initialize", "{}"]
        onExited: {
            // The initial index creation can happen after FileView tried to
            // watch a missing parent directory. Reload once it exists.
            skillsFile.reload();
            memoryFile.reload();
            learningFile.reload();
        }
    }

    FileView {
        id: memoryFile
        path: root.path
        printErrors: false // created on the first remembered fact
        watchChanges: true
        onFileChanged: memoryFile.reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(memoryFile.text());
                root.facts = Array.isArray(parsed?.facts) ? parsed.facts : [];
            } catch (e) {
                root.facts = [];
            }
            root.loaded = true;
        }
        onLoadFailed: error => {
            // No file yet is the normal first run, not a fault.
            root.facts = [];
            root.loaded = true;
        }
    }
}
