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
        for (const countdown of Array.from(TimerService.countdowns ?? [])) {
            if (!countdown) continue;
            const left = TimerService.countdownSecondsLeft(countdown);
            const done = countdown.notified === true || (!countdown.paused && left <= 0);
            // A finished timer lingers for ten minutes as a nudge, then lets go.
            if (done && now - Number(countdown.endsAt ?? 0) > 600000) continue;
            out.push({id: "t:" + countdown.id, kind: "timer", icon: done ? "timer_off" : countdown.paused ? "timer_pause" : "timer",
                label: String(countdown.label ?? "") || Translation.tr("Timer"),
                detail: done ? Translation.tr("Finished") : root.clock(left) + (countdown.paused ? " · " + Translation.tr("paused") : ""),
                progress: done ? 1 : TimerService.countdownProgress(countdown), left: left,
                state: done ? "done" : countdown.paused ? "paused" : "running", order: done ? 0 : 1 + left / 1e6});
        }
        const minutesNow = new Date().getHours() * 60 + new Date().getMinutes();
        for (const alarm of Array.from(AlarmService.alarms ?? [])) {
            if (!alarm || alarm.enabled === false || !String(alarm.time).match(/^\d{1,2}:\d{2}$/)) continue;
            const parts = String(alarm.time).split(":");
            const wait = Number(parts[0]) * 60 + Number(parts[1]) - minutesNow;
            if (wait < 0 || wait > 60) continue;
            out.push({id: "a:" + alarm.time + ":" + (alarm.label ?? ""), kind: "alarm", icon: "alarm",
                label: String(alarm.label ?? "") || Translation.tr("Alarm"),
                detail: alarm.time + " · " + Translation.tr("in %1 min").arg(wait), progress: 1 - wait / 60, state: "soon", order: 2 + wait / 100});
        }
        const reminder = RemindersService.upcoming;
        if (reminder?.reminder) {
            const wait = Math.max(0, Math.round((reminder.at - now) / 60000));
            out.push({id: "r:" + reminder.reminder.id, kind: "reminder", icon: "notifications_active",
                label: String(reminder.reminder.title ?? "") || Translation.tr("Reminder"),
                detail: Translation.tr("in %1 min").arg(wait), progress: 1 - wait / 60, state: "soon", order: 2 + wait / 100});
        }
        if (root.settings.satelliteTasks !== false) {
            const run = Ai.runCoordinator.runFor(Ai.runCoordinator.activeRunId);
            if (run && Ai.runCoordinator.activeStates.includes(run.state) && !root.voiceBusy) {
                const waiting = run.state === "needsAction";
                const lastTool = Array.from(run.activityEvents ?? []).reverse().find(event => event.tool)?.tool ?? "";
                const verb = waiting ? Translation.tr("Waiting for you") : run.state === "toolRunning" && lastTool.length > 0
                    ? Translation.tr("Running %1").arg(lastTool) : run.state === "searching" ? Translation.tr("Searching")
                    : run.state === "streaming" ? Translation.tr("Writing the answer") : Translation.tr("Thinking");
                out.push({id: "k:" + run.runId, kind: "task", icon: waiting ? "front_hand" : run.state === "toolRunning" ? "build"
                    : run.state === "searching" ? "search" : run.state === "streaming" ? "edit_note" : "neurology",
                    label: Translation.tr("AI task"), detail: verb + " · " + root.clock((now - run.startedAt) / 1000),
                    progress: -1, state: waiting ? "waiting" : "working", order: -1});
            }
        }
        for (const task of root.finishedTasks) {
            if (now - task.at > 600000) continue;
            out.push({id: task.id, kind: "task", icon: task.state === "failed" ? "error" : "check",
                label: Translation.tr("AI task"), detail: task.state === "failed" ? Translation.tr("Failed · click to open") : Translation.tr("Done · click to read"),
                progress: -1, state: task.state, order: 0.5});
        }
        const player = MprisController.activePlayer;
        if (root.settings.satelliteMedia !== false && player && MprisController.isPlaying && player.trackTitle)
            out.push({id: "m", kind: "media", icon: "music_note", label: String(player.trackTitle),
                detail: String(player.trackArtist ?? ""), progress: -1, state: "playing", order: 9});
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
