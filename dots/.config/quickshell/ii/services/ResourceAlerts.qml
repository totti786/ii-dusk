pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Says when the machine is struggling: CPU or memory held high for a while, not a blip.
 *
 * It only reads what ResourceUsage already samples for the bar, so watching costs nothing;
 * the one extra piece of work, listing the busiest processes, runs only while an alert is
 * on screen. A spike has to last (`cpuSustainMs`, `memorySustainMs`) to count and has to
 * stay low for `clearMs` to end, so a load that wobbles around the line does not flicker
 * the island. Snoozing hides it for a while without hiding the cause.
 */
Singleton {
    id: root

    // ── Thresholds ───────────────────────────────────────────────────────────
    readonly property real cpuTrip: 0.90
    readonly property int cpuSustainMs: 30000
    readonly property real memoryTrip: 0.92
    readonly property int memorySustainMs: 20000
    /// How far below the line, and for how long, before an alert lets go.
    readonly property real clearMargin: 0.12
    readonly property int clearMs: 15000

    // ── State ────────────────────────────────────────────────────────────────
    property bool cpuOn: false
    property bool memoryOn: false
    property double cpuSince: 0
    property double memorySince: 0
    property bool snoozed: false

    /// "cpu", "memory", or "" when all is well. CPU first: it is the one you can act on fastest.
    readonly property string kind: root.cpuOn ? "cpu" : (root.memoryOn ? "memory" : "")
    readonly property bool active: root.kind !== "" && !root.snoozed
    /// The metric on show, 0..1.
    readonly property real value: root.kind === "memory" ? ResourceUsage.memoryUsedPercentage : ResourceUsage.cpuUsage
    /// When the alert on show began (ms since the epoch), for "for 2 minutes".
    readonly property double since: root.kind === "memory" ? root.memorySince : root.cpuSince
    property var processes: []

    property var _high: ({ cpu: 0, memory: 0 })
    property var _low: ({ cpu: 0, memory: 0 })

    /** One metric's step: on once held above `trip` for `sustainMs`, off once held below it by the margin for `clearMs`. */
    function _step(key: string, value: real, trip: real, sustainMs: int, on: bool, now: double): bool {
        if (value >= trip) {
            root._low[key] = 0;
            if (root._high[key] === 0)
                root._high[key] = now;
            return on || (now - root._high[key]) >= sustainMs;
        }
        root._high[key] = on && value >= trip - root.clearMargin ? root._high[key] : 0;
        if (!on)
            return false;
        if (value >= trip - root.clearMargin) {
            root._low[key] = 0;
            return true;
        }
        if (root._low[key] === 0)
            root._low[key] = now;
        return (now - root._low[key]) < root.clearMs;
    }

    function evaluate(): void {
        const now = Date.now();
        const cpu = root._step("cpu", ResourceUsage.cpuUsage, root.cpuTrip, root.cpuSustainMs, root.cpuOn, now);
        const memory = root._step("memory", ResourceUsage.memoryUsedPercentage, root.memoryTrip, root.memorySustainMs, root.memoryOn, now);
        if (cpu && !root.cpuOn)
            root.cpuSince = root._high.cpu;
        if (memory && !root.memoryOn)
            root.memorySince = root._high.memory;
        root.cpuOn = cpu;
        root.memoryOn = memory;
        if (!root.cpuOn && !root.memoryOn)
            root.snoozed = false;
    }

    // Only while something is near a line, or an alert is up: otherwise a loaded-but-fine
    // machine would tick this for nothing. The values it reads change on ResourceUsage's own poll.
    readonly property bool watching: ResourceUsage.cpuUsage >= root.cpuTrip - root.clearMargin
        || ResourceUsage.memoryUsedPercentage >= root.memoryTrip - root.clearMargin
        || root.cpuOn || root.memoryOn
    Timer {
        interval: 3000
        repeat: true
        running: root.watching
        triggeredOnStart: true
        onTriggered: root.evaluate()
    }

    function snooze(minutes: int): void {
        root.snoozed = true;
        snoozeTimer.interval = Math.max(1, minutes) * 60000;
        snoozeTimer.restart();
    }
    Timer {
        id: snoozeTimer
        repeat: false
        onTriggered: root.snoozed = false
    }

    // ── The culprits ─────────────────────────────────────────────────────────
    /** Programs the shell, the compositor or the session depend on: shown, never offered for ending. */
    readonly property var protectedNames: ["quickshell", "qs", "Hyprland", "hyprland", "systemd", "pipewire", "wireplumber",
        "Xwayland", "dbus-daemon", "dbus-broker", "login", "sddm", "greetd"]

    function endProcess(pid: int): void {
        if (pid > 1)
            Quickshell.execDetached(["kill", "-TERM", String(pid)]);
    }

    function _parse(text: string): void {
        const list = [];
        for (const line of String(text).split("\n")) {
            const m = line.trim().match(/^(\d+)\s+(.*?)\s+([0-9]+(?:\.[0-9]+)?)\s+([0-9]+(?:\.[0-9]+)?)$/);
            if (!m)
                continue;
            const pid = Number(m[1]);
            const name = String(m[2]).replace(/[^\p{L}\p{N} ._+:-]/gu, "").slice(0, 40);
            if (!Number.isInteger(pid) || pid <= 1 || name.length === 0)
                continue;
            list.push({
                pid: pid,
                name: name,
                cpu: Math.round(Number(m[3]) * 10) / 10,
                mem: Math.round(Number(m[4]) * 10) / 10,
                protectedProcess: root.protectedNames.includes(name)
            });
            if (list.length >= 4)
                break;
        }
        root.processes = list;
    }

    Process {
        id: psProc
        command: ["bash", "-c", "ps -u \"$(id -u)\" -o pid=,comm=,pcpu=,pmem= --sort=-" + (root.kind === "memory" ? "pmem" : "pcpu") + " | head -n 8"]
        stdout: StdioCollector {
            onStreamFinished: root._parse(text)
        }
    }
    Timer {
        interval: 4000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: {
            if (!psProc.running)
                psProc.running = true;
        }
    }
}
