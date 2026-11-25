pragma ComponentBehavior: Bound
import QtQuick
import qs
import qs.services
import qs.modules.common

/**
 * The small orbs that bud off the voice orb: one per live thing on the desktop.
 *
 * Running and just-finished timers, an alarm or reminder due within the hour, and the
 * track that is playing. This only describes them; the overlay draws and places them.
 *
 * `ids` is stable on purpose: it changes only when the set changes, so a satellite that
 * keeps living is not rebuilt (and does not replay its spawn animation) every second.
 * `info(id)` is the per-second detail and is meant to be read from a binding on `tick`.
 */
QtObject {
    id: root

    readonly property var settings: Config.options.ai.voice
    readonly property bool enabled: root.settings.satellites !== false
    readonly property int maxCount: 5
    property int tick: 0
    property var ids: []
    /** Background runs that finished while nobody was watching: {id, state, at}. Cleared when read. */
    property var finishedTasks: []
    readonly property bool voiceBusy: AiCompanionUi.voice.active

    property Connections runWatch: Connections {
        target: Ai.runCoordinator
        function onRunFinished(run) {
            if (!root.enabled || root.settings.satelliteTasks === false) return;
            // Someone watching the chat, or the orb itself answering, already knows.
            if (root.voiceBusy || GlobalStates.sidebarLeftOpen) return;
            if (run.state !== "completed" && run.state !== "failed") return;
            root.finishedTasks = root.finishedTasks.filter(item => item.id !== "k:" + run.runId)
                .concat([{id: "k:" + run.runId, state: run.state === "failed" ? "failed" : "done", at: Date.now()}]).slice(-3);
        }
    }
    property Connections sidebarWatch: Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() { if (GlobalStates.sidebarLeftOpen) root.finishedTasks = []; }
    }

    function two(n) { return (n < 10 ? "0" : "") + n; }
    function clock(seconds) {
        const total = Math.max(0, Math.round(seconds));
        const hours = Math.floor(total / 3600), minutes = Math.floor(total % 3600 / 60);
        return hours > 0 ? hours + ":" + root.two(minutes) + ":" + root.two(total % 60) : minutes + ":" + root.two(total % 60);
    }

    /** Everything live right now, most urgent first. Reads `tick`, so it follows the clock. */
    function collect() {
        root.tick;
        const out = [];
        if (!root.enabled) return out;
        const now = Date.now();
        // Timers, alarms, reminders, music and running agents each have a bubble in the island, so they get
        // no orb here. Only a finished AI task does: nothing else says "done, click to read".
        for (const task of root.finishedTasks) {
            if (now - task.at > 600000) continue;
            out.push({id: task.id, kind: "task", icon: task.state === "failed" ? "error" : "check",
                label: Translation.tr("AI task"), detail: task.state === "failed" ? Translation.tr("Failed · click to open") : Translation.tr("Done · click to read"),
                progress: -1, state: task.state, order: 0.5});
        }
        out.sort((a, b) => a.order - b.order);
        return out.slice(0, root.maxCount);
    }

    readonly property var live: root.collect()
    readonly property var byId: {
        const map = ({});
        for (const item of root.live) map[item.id] = item;
        return map;
    }
    onLiveChanged: {
        const next = root.live.map(item => item.id);
        if (next.join("|") !== root.ids.join("|")) root.ids = next;
    }
    function info(id) { return root.byId[id] ?? null; }

    property Timer clockTimer: Timer {
        interval: 1000
        repeat: true
        running: root.enabled && (root.ids.length > 0 || (Array.from(TimerService.countdowns ?? []).length > 0))
        onTriggered: root.tick++
    }

    /** What a click does: pause or resume a timer, dismiss a finished one, play/pause the track. */
    function activate(id) {
        const item = root.info(id);
        if (!item) return;
        if (item.kind === "timer") {
            const key = id.slice(2);
            if (item.state === "done") TimerService.removeCountdown(key);
            else TimerService.toggleCountdown(key);
        } else if (item.kind === "media") MprisController.togglePlaying();
        else if (item.kind === "task") {
            // Finished: read the answer, and let the orb go. Running: just take me to the chat.
            if (item.state === "done" || item.state === "failed") root.finishedTasks = root.finishedTasks.filter(task => task.id !== id);
            AiCompanionUi.transcript();
        }
    }
    /** Right-click: let go of it (a timer is deleted; the others have nothing to dismiss). */
    function dismiss(id) {
        const item = root.info(id);
        if (item?.kind === "timer") TimerService.removeCountdown(id.slice(2));
        else if (item?.kind === "task") root.finishedTasks = root.finishedTasks.filter(task => task.id !== id);
    }
}
