pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common

/**
 * What the voice orb knows about the desktop, and the few things it may do without
 * asking Codex.
 *
 *   snapshot()      a short text block describing the computer right now; it goes in
 *                   front of every spoken turn so "what's playing" or "how much battery"
 *                   needs no tool call.
 *   run(verb, args) one action from a closed table. Arguments are validated and clamped
 *                   here; nothing is ever passed to a shell. Returns {ok, note}.
 *
 * Deliberately absent: closing windows, typing, files, lock/logout, shell commands. A
 * window title or track name is attacker-controlled text and the model reads it, so
 * everything in this table is something the user can undo with one more sentence.
 */
QtObject {
    id: root

    readonly property var settings: Config.options.ai.voice

    // ── Context ──────────────────────────────────────────────────────────────────
    function two(n) { return (n < 10 ? "0" : "") + n; }
    function clip(text, limit) {
        const value = String(text ?? "").replace(/[\r\n\t]+/g, " ").replace(/\s+/g, " ").trim();
        return value.length > limit ? value.slice(0, limit - 1) + "…" : value;
    }
    function nextAlarmText() {
        const now = new Date();
        const nowMinutes = now.getHours() * 60 + now.getMinutes();
        let best = null, bestWait = 1e9;
        for (const alarm of Array.from(AlarmService.alarms ?? [])) {
            if (!alarm || alarm.enabled === false || !String(alarm.time).match(/^\d{1,2}:\d{2}$/)) continue;
            const parts = String(alarm.time).split(":");
            let wait = Number(parts[0]) * 60 + Number(parts[1]) - nowMinutes;
            if (wait <= 0) wait += 1440;
            if (wait < bestWait) { bestWait = wait; best = alarm; }
        }
        return best ? root.clip(best.time + (best.label ? " " + best.label : ""), 50) : "";
    }
    function snapshot() {
        const now = new Date();
        const lines = [];
        lines.push("time: " + now.toLocaleDateString(Qt.locale("en_US"), "ddd d MMM yyyy") + ", " + root.two(now.getHours()) + ":" + root.two(now.getMinutes()));
        const win = ToplevelManager.activeToplevel;
        const workspace = Hyprland.focusedWorkspace?.id;
        if (win && (win.appId || win.title))
            lines.push("focused: " + root.clip(win.appId, 40) + " — \"" + root.clip(win.title, 90) + "\"" + (workspace ? " (workspace " + workspace + ")" : ""));
        else if (workspace) lines.push("workspace: " + workspace);
        const player = MprisController.activePlayer;
        if (player && (player.trackTitle || player.trackArtist))
            lines.push("playing: " + root.clip(player.trackTitle, 70) + (player.trackArtist ? " — " + root.clip(player.trackArtist, 50) : "")
                + " (" + (MprisController.isPlaying ? "playing" : "paused") + ")");
        else lines.push("playing: nothing");
        const sink = Audio.sink?.audio;
        if (sink) lines.push("volume: " + Math.round(sink.volume * 100) + "%" + (sink.muted ? " (muted)" : ""));
        if (Battery.available)
            lines.push("battery: " + Math.round(Battery.percentage * 100) + "% " + (Battery.isCharging ? "charging" : "discharging"));
        if (Notifications.unread > 0) lines.push("unread notifications: " + Notifications.unread);
        const alarm = root.nextAlarmText();
        if (alarm.length > 0) lines.push("next alarm: " + alarm);
        const reminder = RemindersService.upcoming?.reminder;
        if (reminder?.title) lines.push("reminder soon: " + root.clip(reminder.title, 60));
        const timers = Array.from(TimerService.countdowns ?? []).filter(item => item && !item.paused).slice(0, 2);
        if (timers.length > 0)
            lines.push("timers: " + timers.map(item => {
                const left = Math.max(0, TimerService.countdownSecondsLeft(item));
                return root.clip(item.label, 30) + " " + Math.floor(left / 60) + "m" + root.two(Math.floor(left % 60)) + "s left";
            }).join(", "));
        const open = Array.from(Todo.list ?? []).filter(task => task && task.done !== true);
        if (open.length > 0)
            lines.push("open tasks (" + open.length + "): " + open.slice(0, 3).map(task => root.clip(task.content ?? task.title, 40)).join("; "));
        lines.push(root.pipelineLine());
        return lines.join("\n");
    }

    // What the orb is made of, so it can answer questions about itself instead of guessing.
    function pipelineLine() {
        const voice = Config.options.ai.voice;
        const stt = String(voice.sttModel ?? "auto") + ((voice.language ?? "en") === "en" ? ".en, English only" : "");
        const ears = (voice.vad ?? true) ? "a Silero voice-activity model hears when the user stops talking" : "a loudness threshold hears when the user stops talking";
        const task = String(voice.escalationModel ?? "").length > 0 ? String(voice.escalationModel) : "the sidebar chat model";
        return "your pipeline: ears = " + ears + ", then whisper.cpp (" + (stt === "auto" ? "best installed model" : stt + " model")
            + ") transcribes it on this computer; you = Claude " + String(voice.fastModel ?? "haiku") + " for quick answers and instant commands, "
            + task + " for desktop tasks; voice = local Kokoro at " + Number(voice.speechSpeed ?? 1.25).toFixed(2) + "x speed (a cloud voice for non-Latin scripts)";
    }

    // ── Actions ──────────────────────────────────────────────────────────────────
    function ok(note) { return {ok: true, note: note}; }
    function no(note) { return {ok: false, note: note}; }
    function number(text, low, high) {
        const value = Number(String(text ?? "").replace("%", ""));
        return Number.isFinite(value) ? Math.max(low, Math.min(high, value)) : NaN;
    }
    function findApp(query) {
        const wanted = String(query).toLowerCase().trim();
        if (wanted.length < 2) return null;
        const apps = Array.from(DesktopEntries.applications.values).filter(entry => entry && !entry.noDisplay);
        const rank = entry => {
            const name = String(entry.name ?? "").toLowerCase();
            const id = String(entry.id ?? "").toLowerCase().replace(/\.desktop$/, "");
            if (name === wanted || id === wanted) return 0;
            if (name.startsWith(wanted) || id.startsWith(wanted)) return 1;
            if (name.includes(wanted)) return 2;
            return 9;
        };
        const hit = apps.map(entry => ({entry: entry, rank: rank(entry)})).filter(item => item.rank < 9)
            .sort((a, b) => a.rank - b.rank || String(a.entry.name).length - String(b.entry.name).length)[0];
        return hit ? hit.entry : null;
    }

    /** The verbs the model may use; anything else is refused, and the turn goes to the full agent. */
    readonly property var table: ({
        media: args => {
            const player = MprisController.activePlayer;
            const what = String(args[0] ?? "");
            if (!player) return root.no("nothing is playing");
            if (what === "next") { MprisController.next(); return root.ok("Skipped to the next track"); }
            if (what === "previous") { MprisController.previous(); return root.ok("Went back a track"); }
            if (what === "toggle") { MprisController.togglePlaying(); return root.ok(MprisController.isPlaying ? "Paused" : "Playing"); }
            if (what === "play") { if (!MprisController.isPlaying) MprisController.togglePlaying(); return root.ok("Playing"); }
            if (what === "pause") { if (MprisController.isPlaying) MprisController.togglePlaying(); return root.ok("Paused"); }
            return root.no("unknown media action");
        },
        volume: args => {
            const sink = Audio.sink?.audio;
            if (!sink) return root.no("no audio output");
            const what = String(args[0] ?? "");
            if (what === "mute") { sink.muted = true; return root.ok("Muted"); }
            if (what === "unmute") { sink.muted = false; return root.ok("Unmuted"); }
            let target = NaN;
            if (what === "set") target = root.number(args[1], 0, 100);
            else if (what === "up") target = Math.min(100, Math.round(sink.volume * 100) + 10);
            else if (what === "down") target = Math.max(0, Math.round(sink.volume * 100) - 10);
            if (!Number.isFinite(target)) return root.no("bad volume");
            sink.muted = false;
            sink.volume = target / 100;
            return root.ok("Set volume to " + Math.round(target) + "%");
        },
        brightness: args => {
            const monitor = Brightness.getTargetMonitor();
            if (!monitor) return root.no("no adjustable screen");
            const what = String(args[0] ?? "");
            let target = NaN;
            if (what === "set") target = root.number(args[1], 5, 100);
            else if (what === "up") target = Math.min(100, Math.round(monitor.brightness * 100) + 15);
            else if (what === "down") target = Math.max(5, Math.round(monitor.brightness * 100) - 15);
            if (!Number.isFinite(target)) return root.no("bad brightness");
            monitor.setBrightness(target / 100);
            return root.ok("Set brightness to " + Math.round(target) + "%");
        },
        theme: args => {
            const want = String(args[0] ?? "");
            if (want !== "dark" && want !== "light") return root.no("unknown theme");
            if ((want === "dark") !== Appearance.m3colors.darkmode) MaterialThemeLoader.toggleLightDark();
            return root.ok("Switched to " + want + " mode");
        },
        open: args => {
            const entry = root.findApp(args.join(" "));
            if (!entry) return root.no("no app called " + root.clip(args.join(" "), 30));
            entry.execute();
            return root.ok("Opened " + entry.name);
        },
        timer: args => {
            const minutes = root.number(args[0], 1, 600);
            if (!Number.isFinite(minutes)) return root.no("bad timer length");
            TimerService.addCountdown(minutes, root.clip(args.slice(1).join(" "), 40));
            return root.ok("Timer set for " + minutes + (minutes === 1 ? " minute" : " minutes"));
        },
        alarm: args => {
            const match = String(args[0] ?? "").match(/^(\d{1,2}):(\d{2})$/);
            if (!match || Number(match[1]) > 23 || Number(match[2]) > 59) return root.no("bad alarm time");
            const time = root.two(Number(match[1])) + ":" + match[2];
            // A spoken alarm rings once, at the next occurrence of that time.
            const now = new Date();
            const target = new Date(now.getFullYear(), now.getMonth(), now.getDate(), Number(match[1]), Number(match[2]));
            const day = target.getTime() <= now.getTime() ? new Date(target.getTime() + 86400000) : target;
            const date = day.getFullYear() + "-" + root.two(day.getMonth() + 1) + "-" + root.two(day.getDate());
            const added = AlarmService.addAlarm(time, root.clip(args.slice(1).join(" "), 40), [false, false, false, false, false, false, false], date);
            return added ? root.ok("Alarm set for " + time) : root.no("could not add the alarm");
        },
        remind: args => {
            const title = root.clip(args.join(" "), 120);
            if (title.length === 0) return root.no("nothing to remind");
            RemindersService.create({title: title});
            return root.ok("Reminder added: " + title);
        },
        task: args => {
            const title = root.clip(args.join(" "), 120);
            if (title.length === 0) return root.no("nothing to add");
            const result = Todo.aiCreateTask({title: title});
            return result?.ok ? root.ok("Added task: " + title) : root.no(result?.error ?? "could not add the task");
        },
        workspace: args => {
            const id = Math.round(root.number(args[0], 1, 20));
            if (!Number.isFinite(id)) return root.no("bad workspace");
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + id + " })");
            return root.ok("Went to workspace " + id);
        }
    })

    function run(verb, args) {
        const name = String(verb);
        if (root.settings.actions === false) return root.no("actions are off");
        if (!Object.prototype.hasOwnProperty.call(root.table, name)) return root.no("unknown action " + root.clip(name, 20));
        try {
            return root.table[name](Array.from(args ?? []).map(item => String(item)));
        } catch (error) {
            return root.no(String(error));
        }
    }
}
