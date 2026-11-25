pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.UPower
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
 * Deliberately absent: typing, files and shell commands. A window title or track name is
 * attacker-controlled text and the model reads it, so almost everything here is something the
 * user can undo with one more sentence. The exceptions (lock, suspend, reboot, shutdown, close)
 * are refused unless `run()` is told the user confirmed out loud; only the voice agent, after a
 * fresh plain "yes", ever says so, and the model's own markers never do.
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
    /** The last few actions that ran, newest last: {text, at}. Kept in memory only. */
    property var recent: []

    function focusedWindowId(): string {
        return String(ToplevelManager.activeToplevel?.HyprlandToplevel?.address ?? "");
    }

    // This is the only automatically attached context the cloud quick model receives.
    // Local rules can still answer from the richer desktop snapshot below.
    function contextForModel(text): string {
        const facts = [];
        const question = String(text);
        const sink = Audio.sink?.audio;
        if (/\b(volume|mute|unmute|louder|quieter|softer)\b/i.test(question) && sink)
            facts.push("volume: " + Math.round(sink.volume * 100) + "%" + (sink.muted ? " (muted)" : ""));
        if (/\b(battery|charging|charge)\b/i.test(question) && Battery.available)
            facts.push("battery: " + Math.round(Battery.percentage * 100) + "%" + (Battery.isCharging ? " (charging)" : ""));
        return facts.join("\n");
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
        const glance = Ai.runningIntegration.glance();
        if (glance.length > 0) lines.push(glance);
        const running = Ai.runningIntegration.brief();
        if (running.length > 0) lines.push(running);
        // What the shell just did on request, so "turn it back up" has something to refer to even when an
        // instant command handled the turn and no model saw it.
        const lately = root.recent.filter(item => Date.now() - item.at < 10 * 60 * 1000);
        if (lately.length > 0)
            lines.push("recent actions: " + lately.map(item => item.text + " (" + Math.max(1, Math.round((Date.now() - item.at) / 60000)) + " min ago)").join("; "));
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
            // Up to 150%, unless the volume protection is on: then its own ceiling holds.
            const protectedMax = Config.options.audio.protection.enable ? Config.options.audio.protection.maxAllowed : 150;
            const limit = Math.min(150, protectedMax);
            const now = Math.round(sink.volume * 100);
            if (what === "set") target = root.number(args[1], 0, limit);
            // "Louder" stays within 100% unless it is already past it.
            else if (what === "up") target = Math.min(now > 100 ? limit : Math.min(100, limit), now + 10);
            else if (what === "down") target = Math.max(0, now - 10);
            if (!Number.isFinite(target)) return root.no("bad volume");
            sink.muted = false;
            sink.volume = target / 100;
            const asked = what === "set" ? Number(String(args[1] ?? "").replace("%", "")) : target;
            return root.ok("Set volume to " + Math.round(target) + "%" + (asked > target ? " (the most allowed)" : ""));
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
        ,
        toggle: args => {
            const what = String(args[0] ?? ""), state = String(args[1] ?? "toggle");
            if (!["on", "off", "toggle"].includes(state)) return root.no("bad state");
            // The wanted state, given what is on now (idempotent: "turn it on" twice is not a toggle).
            const want = current => state === "toggle" ? !current : state === "on";
            switch (what) {
            case "wifi": {
                const now = Network.wifiEnabled;
                if (!NetworkState.hasWifiDevice) return root.no("no Wi-Fi adapter");
                Network.enableWifi(want(now));
                return root.ok("Wi-Fi " + (want(now) ? "on" : "off"));
            }
            case "bluetooth": {
                if (!BluetoothStatus.available) return root.no("no Bluetooth adapter");
                const on = want(BluetoothStatus.enabled);
                BluetoothStatus.setEnabled(on);
                return root.ok("Bluetooth " + (on ? "on" : "off"));
            }
            case "nightlight": {
                const on = want(Hyprsunset.temperatureActive);
                if (on !== Hyprsunset.temperatureActive) Hyprsunset.toggleTemperature(on);
                return root.ok("Night light " + (on ? "on" : "off"));
            }
            case "dnd": {
                const on = want(Notifications.effectiveSilent);
                Notifications.silent = on;
                return root.ok("Do not disturb " + (on ? "on" : "off"));
            }
            case "awake": {
                const on = want(Idle.inhibit);
                if (on !== Idle.inhibit) Idle.toggleInhibit(on);
                return root.ok(on ? "Keeping the screen awake" : "Normal sleep");
            }
            case "gamemode": {
                const model = QuickToggleRegistry.getModel("gameMode");
                if (!model) return root.no("no game mode");
                const on = want(model.toggled);
                if (on !== model.toggled) model.mainAction();
                return root.ok("Game mode " + (on ? "on" : "off"));
            }
            case "mic": {
                const audio = Audio.source?.audio;
                if (!audio) return root.no("no microphone");
                const on = want(!audio.muted);
                audio.muted = !on;
                return root.ok(on ? "Mic on" : "Mic muted");
            }
            }
            return root.no("unknown toggle");
        },
        power: args => {
            const names = {saver: PowerProfile.PowerSaver, balanced: PowerProfile.Balanced, performance: PowerProfile.Performance};
            const name = String(args[0] ?? "");
            if (!Object.prototype.hasOwnProperty.call(names, name)) return root.no("unknown power profile");
            if (name === "performance" && !PowerProfiles.hasPerformanceProfile) return root.no("no performance profile on this computer");
            PowerProfiles.profile = names[name];
            return root.ok("Power profile: " + name);
        },
        capture: args => {
            const what = String(args[0] ?? "");
            if (what === "color") { root.later(null, () => GlobalStates.launchColorPicker()); return root.ok("Color picker"); }
            if (what === "shot") { root.later(["region", "fullscreen"]); return root.ok("Taking a screenshot"); }
            if (what === "area") { root.later(["region", "screenshot"]); return root.ok("Select an area"); }
            const recording = Persistent.states.screenRecord.active;
            if (what === "stop") {
                if (!recording) return root.no("not recording");
                Quickshell.execDetached([Directories.recordScriptPath]);
                return root.ok("Stopped recording");
            }
            if (what === "record" || what === "region") {
                if (recording) return root.no("already recording");
                root.later(null, () => Quickshell.execDetached([Directories.recordScriptPath, what === "record" ? "--fullscreen" : "--region"]));
                return root.ok(what === "record" ? "Recording the screen" : "Select an area to record");
            }
            return root.no("unknown capture");
        },
        session: args => {
            const op = String(args[0] ?? "");
            const tool = String(args[1] ?? "");
            const id = String(args[2] ?? "");
            if (!["send", "stop", "focus"].includes(op)) return root.no("unknown session action");
            if (!["claude", "codex", "opencode"].includes(tool)) return root.no("unknown coding tool");
            const script = Quickshell.shellPath("scripts/ai/agent_sessions.py");
            if (op === "send") {
                const text = args.slice(3).join(" ").trim();
                if (text.length === 0) return root.no("nothing to send");
                Quickshell.execDetached(["python3", script, "send", tool, id, text]);
                return root.ok("Sent to " + tool);
            }
            Quickshell.execDetached(["python3", script, op === "stop" ? "interrupt" : "focus", tool, id]);
            return root.ok((op === "stop" ? "Stopped " : "Showing ") + tool);
        },
        kitten: args => {
            const name = String(args[0] ?? "");
            const known = ["play", "pet", "come", "hop", "trick", "sleep", "wake", "yawn", "groom", "hide", "knock", "yarn", "gift", "laser", "stop"];
            if (!known.includes(name)) return root.no("unknown kitten trick");
            if (!AiCompanionUi.kittenPlay(name)) return root.no("the kitten is not out (the orb is docked or hidden)");
            return root.ok("Kitten: " + name);
        },
        panel: args => {
            const panels = {settings: ["settings", "open", "toggle"], sidebar: ["sidebarRight", "open", "toggle", "close"],
                            cheatsheet: ["cheatsheet", "open", "toggle", "close"], apps: ["appDrawer", "open", "toggle", "close"],
                            power: ["session", "open", "toggle", "close"], clipboard: ["search", "clipboardToggle"],
                            mixer: ["mixer", "toggle", "close"]};
            const name = String(args[0] ?? ""), how = String(args[1] ?? "open");
            if (!Object.prototype.hasOwnProperty.call(panels, name)) return root.no("unknown panel");
            const entry = panels[name];
            const fn = entry[1] === "clipboardToggle" ? "clipboardToggle" : (entry.includes(how) ? how : (how === "open" ? "toggle" : ""));
            if (fn.length === 0) return root.no("cannot " + how + " the " + name);
            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", entry[0], fn]);
            return root.ok((how === "close" ? "Closed the " : "Opened the ") + name);
        },
        window: args => {
            const what = String(args[0] ?? "");
            if (what === "fullscreen") { Hyprland.dispatch("hl.dsp.window.fullscreen({ mode = 0 })"); return root.ok("Toggled fullscreen"); }
            if (what === "float") { Hyprland.dispatch("hl.dsp.window.float({ action = \"toggle\" })"); return root.ok("Toggled floating"); }
            if (what === "pin") { Hyprland.dispatch("hl.dsp.window.pin({ action = \"toggle\" })"); return root.ok("Toggled pin"); }
            if (what === "move") {
                const id = Math.round(root.number(args[1], 1, 20));
                if (!Number.isFinite(id)) return root.no("bad workspace");
                Hyprland.dispatch("hl.dsp.window.move({ workspace = " + id + " })");
                return root.ok("Moved the window to workspace " + id);
            }
            if (what === "focus") {
                // Resolved here against the real window list: nothing spoken goes into a dispatch string.
                const wanted = args.slice(1).join(" ").toLowerCase().trim();
                if (wanted.length < 2) return root.no("which window?");
                const windows = Array.from(ToplevelManager.toplevels?.values ?? []);
                const rank = w => {
                    const id = String(w.appId ?? "").toLowerCase(), title = String(w.title ?? "").toLowerCase();
                    return id === wanted ? 0 : id.startsWith(wanted) ? 1 : id.includes(wanted) ? 2 : title.includes(wanted) ? 3 : 9;
                };
                const best = windows.map(w => ({w: w, r: rank(w)})).filter(x => x.r < 9).sort((a, b) => a.r - b.r)[0];
                if (!best) return root.no("no window called " + root.clip(wanted, 30));
                best.w.activate();
                return root.ok("Switched to " + root.clip(best.w.appId || best.w.title, 30));
            }
            return root.no("unknown window action");
        },
        // These four-plus-one are the only verbs that need the user's spoken yes (see run()).
        lock: args => { Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "lock", "activate"]); return root.ok("Locking"); },
        suspend: args => { Quickshell.execDetached(["systemctl", "suspend"]); return root.ok("Going to sleep"); },
        reboot: args => { Quickshell.execDetached(["systemctl", "reboot"]); return root.ok("Restarting"); },
        shutdown: args => { Quickshell.execDetached(["systemctl", "poweroff"]); return root.ok("Shutting down"); },
        close: args => { Quickshell.execDetached([Quickshell.shellPath("scripts/hyprland/close_window.sh")]); return root.ok("Closed the window"); }
    })

    /** Verbs that may only run after the user confirmed out loud. */
    readonly property var needsConfirm: ["lock", "suspend", "reboot", "shutdown", "close"]

    // A short pause before anything that takes a picture, so the orb and its label are not in it.
    property var laterTask: null
    property Timer laterTimer: Timer {
        interval: 450
        onTriggered: { const task = root.laterTask; root.laterTask = null; if (task) task(); }
    }
    function later(ipcCall, task) {
        root.laterTask = task ?? (() => Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", ipcCall[0], ipcCall[1]]));
        root.laterTimer.restart();
    }

    function run(verb, args, confirmed) {
        const name = String(verb);
        if (root.settings.actions === false) return root.no("actions are off");
        if (!Object.prototype.hasOwnProperty.call(root.table, name)) return root.no("unknown action " + root.clip(name, 20));
        const mustConfirm = root.needsConfirm.includes(name) || (name === "session" && ["send", "stop"].includes(String(args?.[0])));
        if (mustConfirm && confirmed !== true) return root.no(name + " needs the user's confirmation");
        try {
            const result = root.table[name](Array.from(args ?? []).map(item => String(item)));
            console.log("[voice] action", name, result.ok ? "completed" : "refused");
            if (result.ok)
                root.recent = root.recent.concat([{text: root.clip(result.note, 60), at: Date.now()}]).slice(-3);
            return result;
        } catch (error) {
            console.log("[voice] action", name, "failed:", String(error));
            return root.no(String(error));
        }
    }
}
