pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.modules.common

/**
 * Bridge to scripts/monitor/monitor.py. While the Monitor window is open (and not paused) the
 * script streams one JSON line a second: CPU, memory, disks, network, processes and the latency
 * to a few hosts. This keeps the latest line plus a couple of minutes of history for the graphs.
 */
Singleton {
    id: root

    readonly property string script: `${Directories.scriptPath}/monitor/monitor.py`
    /// The sampler keeps running for ten minutes after the window closes, so opening it again soon
    /// does not start from empty graphs
    property bool lingering: false
    readonly property bool wanted: GlobalStates.monitorOpen || root.lingering
    property bool paused: false
    /// The Overview card that fills the page (cpu, latency, net, mem, procs); empty when none does
    property string expandedCard: ""
    /// True once Tab was pressed, so cards only show a focus marker for keyboard users
    property bool keyboardNav: false
    readonly property int historyLength: 120

    // ── the latest sample ──
    property bool live: false
    property string cpuModel: ""
    property int coreCount: 1
    property string host: ""
    property string kernel: ""
    property real cpu: 0
    property var cores: []
    property var freq: []
    property var battery: null
    /// The process picked in a list, with a couple of minutes of its own history
    property int selectedPid: -1
    property var selectedCpuHistory: []
    property var selectedMemHistory: []
    /// The process list's search field is hidden until asked for
    property bool procSearchOpen: false
    /// Bumped to put the typing cursor in the open search field ("/", the search button)
    property int procSearchFocus: 0
    function openProcSearch(): void {
        root.procSearchOpen = true;
        root.procSearchFocus++;
    }
    property real freqMax: 0
    property var load: [0, 0, 0]
    property real uptime: 0
    property var mem: ({ total: 1, used: 0, cached: 0, buffers: 0, free: 0, swap_total: 0, swap_used: 0 })
    property var temps: ({ cpu: 0, sensors: [] })
    property var disks: []
    property var io: ({ read: 0, write: 0 })
    property var net: []
    property var procs: []
    property int tasks: 0
    property int threads: 0
    property var ping: []

    /// The interface the network card shows. Empty follows the busiest one (a VPN tunnel would
    /// otherwise double the count); a name pins that interface, as btop's b and n keys do.
    property string selectedNic: ""
    readonly property var busiestNet: root.net.reduce((best, n) => !best || n.rx + n.tx > best.rx + best.tx ? n : best, null)
    readonly property var mainNet: (root.selectedNic !== "" ? root.net.find(n => n.name === root.selectedNic) : null) ?? root.busiestNet
    /// What the card can cycle through: auto, then every real interface (loopback and container veths left out)
    readonly property var nicChoices: root.net.filter(n => !/^(lo$|veth)/.test(n.name)).map(n => n.name)

    function cycleNic(direction: int): void {
        const order = [""].concat(root.nicChoices);
        const at = Math.max(0, order.indexOf(root.selectedNic));
        root.selectedNic = order[(at + direction + order.length) % order.length];
    }
    readonly property real rx: root.mainNet?.rx ?? 0
    readonly property real tx: root.mainNet?.tx ?? 0

    // ── history, oldest first ──
    property var cpuHistory: []
    property var memHistory: []
    /// Each interface keeps its own history so switching shows its past, not a gap
    property var nicHistory: ({})
    readonly property var rxHistory: root.nicHistory[root.mainNet?.name ?? ""]?.rx ?? []
    readonly property var txHistory: root.nicHistory[root.mainNet?.name ?? ""]?.tx ?? []
    property var ioReadHistory: []
    property var ioWriteHistory: []
    property var pingHistory: ({})

    property string error: ""
    property var targets: []
    property string gateway: ""
    property string configPath: ""
    property var defaultTargets: []
    property bool saving: false
    property string saveError: ""

    function push(list: var, value: real): var {
        const next = list.length >= root.historyLength ? list.slice(list.length - root.historyLength + 1) : list.slice();
        next.push(value);
        return next;
    }

    function apply(d: var): void {
        if (d.event === "hello") {
            root.cpuModel = d.cpu_model;
            root.coreCount = d.cores;
            root.host = d.host;
            root.kernel = d.kernel;
            return;
        }
        if (d.event !== "tick")
            return;
        root.live = true;
        root.lastTickAt = Date.now();
        root.cpu = d.cpu;
        root.cores = d.cores;
        root.freq = d.freq ?? [];
        root.battery = d.battery ?? null;
        root.freqMax = d.freq_max ?? 0;
        root.load = d.load;
        root.uptime = d.uptime;
        root.mem = d.mem;
        root.temps = d.temps;
        root.disks = d.disks;
        root.io = d.io;
        root.net = d.net;
        root.procs = d.procs;
        if (root.selectedPid > 0) {
            const row = d.procs.find(r => r[0] === root.selectedPid);
            // A process that is not in this sample (or has ended) leaves a gap rather than a zero
            root.selectedCpuHistory = root.push(root.selectedCpuHistory, row ? row[3] : -1);
            root.selectedMemHistory = root.push(root.selectedMemHistory, row ? row[4] : -1);
        }
        root.tasks = d.tasks;
        root.threads = d.threads;
        root.ping = d.ping;
        root.cpuHistory = root.push(root.cpuHistory, d.cpu);
        root.memHistory = root.push(root.memHistory, 100 * d.mem.used / d.mem.total);
        const nics = Object.assign({}, root.nicHistory);
        for (const n of d.net)
            nics[n.name] = { rx: root.push(nics[n.name]?.rx ?? [], n.rx), tx: root.push(nics[n.name]?.tx ?? [], n.tx) };
        root.nicHistory = nics;
        root.ioReadHistory = root.push(root.ioReadHistory, d.io.read);
        root.ioWriteHistory = root.push(root.ioWriteHistory, d.io.write);
        const hist = Object.assign({}, root.pingHistory);
        for (const p of d.ping) {
            // A target that has not answered yet is not a lost packet: skip until its first reply
            if (p.ms === null && !(hist[p.name]?.length > 0))
                continue;
            hist[p.name] = root.push(hist[p.name] ?? [], p.ms === null ? -1 : p.ms);
        }
        root.pingHistory = hist;
    }

    /// Round trips of one target over the history: current, average, best, worst, jitter, loss
    function pingStats(name: string): var {
        const all = root.pingHistory[name] ?? [];
        const ok = all.filter(v => v >= 0);
        const stats = { current: all.length > 0 ? all[all.length - 1] : -1, avg: 0, min: 0, max: 0, jitter: 0,
                        loss: all.length > 0 ? 100 * (all.length - ok.length) / all.length : 0, samples: all.length };
        if (ok.length > 0) {
            stats.avg = ok.reduce((a, b) => a + b, 0) / ok.length;
            stats.min = Math.min(...ok);
            stats.max = Math.max(...ok);
            let jitter = 0;
            for (let i = 1; i < ok.length; i++)
                jitter += Math.abs(ok[i] - ok[i - 1]);
            stats.jitter = ok.length > 1 ? jitter / (ok.length - 1) : 0;
        }
        return stats;
    }

    onSelectedPidChanged: {
        root.selectedCpuHistory = [];
        root.selectedMemHistory = [];
    }

    function clearHistory(): void {
        root.cpuHistory = [];
        root.memHistory = [];
        root.nicHistory = ({});
        root.ioReadHistory = [];
        root.ioWriteHistory = [];
        root.pingHistory = ({});
    }

    /// Pids in the order the open process list shows them (the list publishes this)
    property var shownPids: []

    /// Up and down through that list; nothing selected yet starts at the first (or last) row
    function stepProcess(direction: int): void {
        const pids = root.shownPids;
        if (pids.length === 0)
            return;
        const at = pids.indexOf(root.selectedPid);
        root.selectedPid = at < 0 ? pids[direction > 0 ? 0 : pids.length - 1] : pids[Math.max(0, Math.min(pids.length - 1, at + direction))];
    }

    function signalProcess(pid: int, sig: string): void {
        root.error = "";
        signalProc.command = ["python3", "-I", root.script, "signal", String(pid), "--sig", sig];
        signalProc.running = true;
    }

    /// Pages that list every process hold this up; otherwise the sampler sends only the
    /// busiest few (the whole table is ~50 kB of JSON a second to parse)
    property int fullProcsHolders: 0
    readonly property bool fullProcs: root.fullProcsHolders > 0

    function sendProcsMode(): void {
        if (stream.running)
            stream.write(root.fullProcs ? "procs full\n" : "procs top\n");
    }

    onFullProcsChanged: root.sendProcsMode()

    Process {
        id: stream
        command: ["python3", "-I", root.script, "watch", "--interval", "1", "--procs", "top"]
        running: root.wanted && !root.paused
        stdinEnabled: true
        onStarted: root.sendProcsMode()
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.apply(JSON.parse(line));
                } catch (e) {}
            }
        }
        onRunningChanged: if (!stream.running)
            root.live = false
    }

    Process {
        id: signalProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    if (!r.ok)
                        root.error = r.error;
                } catch (e) {}
            }
        }
    }

    // ── settings: the latency targets ──
    function loadConfig(): void {
        configRun.command = ["python3", "-I", root.script, "config"];
        configRun.running = true;
    }

    function saveTargets(targets: var): void {
        if (saveRun.running)
            return;
        root.saveError = "";
        root.saving = true;
        saveRun.environment = ({ "MONITOR_CONFIG_PATCH": JSON.stringify({ targets: targets }) });
        saveRun.command = ["python3", "-I", root.script, "config", "set"];
        saveRun.running = true;
    }

    function applyConfig(d: var): void {
        root.targets = d.targets;
        root.gateway = d.gateway;
        root.configPath = d.path;
        root.defaultTargets = d.defaults;
    }

    Process {
        id: configRun
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    if (r.ok)
                        root.applyConfig(r);
                } catch (e) {}
            }
        }
    }

    Process {
        id: saveRun
        stdout: StdioCollector {
            onStreamFinished: {
                root.saving = false;
                try {
                    const r = JSON.parse(text);
                    if (r.ok) {
                        root.applyConfig(r);
                        root.pingHistory = ({});
                        // New targets are read when the sampler starts, so start it again
                        if (stream.running) {
                            root.paused = true;
                            Qt.callLater(() => root.paused = false);
                        }
                    } else {
                        root.saveError = r.error;
                    }
                } catch (e) {
                    root.saveError = "Could not save";
                }
            }
        }
    }

    property real lastTickAt: 0

    Timer {
        id: lingerTimer
        interval: 600000
        onTriggered: root.lingering = false
    }

    Connections {
        target: GlobalStates
        function onMonitorOpenChanged() {
            if (GlobalStates.monitorOpen) {
                lingerTimer.stop();
                root.lingering = false;
                // The history of a sampler that was off for a while is stale
                if (Date.now() - root.lastTickAt > 5000)
                    root.clearHistory();
            } else {
                root.lingering = true;
                lingerTimer.restart();
            }
        }
    }

    onWantedChanged: if (root.wanted) {
        root.paused = false;
        root.loadConfig();
    } else {
        root.live = false;
        root.expandedCard = "";
        root.keyboardNav = false;
    }
}
