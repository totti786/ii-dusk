pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.services.ai
import qs.modules.common

/**
 * What the shell itself has running right now: media, timers, recordings, downloads, VPN, the voice orb
 * and its helpers, AI work in progress. Read-only, bounded and free of identifiers: names and counts, no
 * addresses, no paths, no message text.
 *
 * Each source is read on its own, so a service that is missing or not ready shows up as "unavailable" in
 * the answer instead of hiding everything else.
 */
QtObject {
    id: root

    function clip(text: var, limit: int): string {
        const value = String(text ?? "").replace(/[\r\n\t]+/g, " ").replace(/\s+/g, " ").trim();
        return value.length > limit ? value.slice(0, limit - 1) + "…" : value;
    }

    // Runs one reader; a failure becomes a note, never an exception.
    function read(reader: var): var {
        try {
            const value = reader();
            return value === undefined ? null : value;
        } catch (error) {
            return { unavailable: root.clip(error, 80) };
        }
    }

    function media(): var {
        const player = MprisController.activePlayer;
        const playing = MprisController.isPlaying === true;
        return {
            playing: playing,
            player: player ? root.clip(player.identity ?? player.desktopEntry ?? "", 40) : "",
            track: player ? root.clip(player.trackTitle, 70) : "",
            artist: player ? root.clip(player.trackArtist, 50) : ""
        };
    }

    function timers(): var {
        const countdowns = Array.from(TimerService.countdowns ?? []).filter(item => item).slice(0, 5).map(item => ({
                    label: root.clip(item.label, 30),
                    paused: item.paused === true,
                    secondsLeft: Math.max(0, Math.round(TimerService.countdownSecondsLeft(item)))
                }));
        const alarms = Array.from(AlarmService.alarms ?? []).filter(alarm => alarm && alarm.enabled !== false);
        return { countdowns: countdowns, enabledAlarms: alarms.length };
    }

    function soundscapes(): var {
        return { playing: SoundscapesService.playing === true, sounds: Array.from(SoundscapesService.active ?? []).slice(0, 8).map(id => root.clip(id, 30)) };
    }

    function downloads(): var {
        const jobs = Array.from(DownloadsService.jobs ?? []);
        return {
            files: jobs.length,
            mediaDownloader: MediaDownloaderService.active === true || MediaDownloaderService.queueProcessing === true
        };
    }

    function ai(): var {
        return {
            generating: Ai.isGenerating === true,
            model: root.clip(Ai.currentModelId, 60),
            tools: String(Ai.functionExposure ?? "")
        };
    }

    function orb(): var {
        const voice = Config.options.ai.voice;
        const ui = AiCompanionUi.voice;
        return {
            phase: String(ui?.phase ?? ""),
            active: ui?.active === true,
            speaking: Ai.speechService.speaking === true,
            triggerWordOn: voice.wakeWord === true,
            triggerWord: String(voice.wakeWordModel ?? ""),
            triggerThreshold: Number(voice.wakeWordThreshold ?? 0),
            voice: String(voice.fastModel ?? "")
        };
    }


    function two(n: int): string { return (n < 10 ? "0" : "") + n; }
    function clock(date: var): string { return root.two(date.getHours()) + ":" + root.two(date.getMinutes()); }

    // The cached conditions only: reading them never starts a network request.
    function weather(): var {
        const w = Weather.data ?? ({});
        // Until a fetch has finished the data is only placeholders ("City", "0°C").
        if (!(Weather.lastFetchTimestamp > 0) || !w.wDesc) return { available: false, note: "not loaded yet" };
        return {
            available: true,
            city: root.clip(w.city, 60),
            condition: root.clip(w.wDesc, 60),
            temperature: String(w.temp ?? ""),
            feelsLike: String(w.tempFeelsLike ?? ""),
            humidity: String(w.humidity ?? ""),
            wind: String(w.wind ?? ""),
            sunrise: String(w.sunrise ?? ""),
            sunset: String(w.sunset ?? "")
        };
    }

    function prayer(): var {
        if (!PrayerTimes.hasLocation) return { available: false };
        const next = PrayerTimes.next;
        return {
            available: PrayerTimes.today.length > 0,
            hijriDate: root.clip(PrayerTimes.hijriDate, 40),
            next: next ? { name: next.name, time: root.clock(next.time), tomorrow: PrayerTimes.nextIsTomorrow, minutesAway: PrayerTimes.minutesToNext } : null,
            previous: PrayerTimes.previous ? PrayerTimes.previous.name : "",
            today: Array.from(PrayerTimes.today ?? []).map(item => ({ name: item.name, time: root.clock(item.time) }))
        };
    }

    function personal(): var {
        return {
            water: { enabled: WaterReminderService.enabled === true, glasses: Number(WaterReminderService.glassesDrunk ?? 0), goal: Number(WaterReminderService.dailyGoal ?? 0) },
            bedtime: { enabled: BedtimeService.enabled === true, target: String(BedtimeService.targetTime ?? ""), phase: String(BedtimeService.phase ?? "") },
            screenTimeLimits: { active: ScreenTimeLimits.active === true, rules: Array.from(ScreenTimeLimits.limits ?? []).length }
        };
    }

    function connectivity(): var {
        return {
            bluetooth: { enabled: BluetoothStatus.enabled === true, connectedDevices: Number(BluetoothStatus.activeDeviceCount ?? 0) },
            tailscale: { active: TailscaleService.active === true, state: String(TailscaleService.backendState ?? "") },
            docker: { running: DockerService.dockerRunning === true, containers: Number(DockerService.runningCount ?? 0) }
        };
    }

    function attention(): var {
        return {
            // Which sensors are in use right now: camera, microphone, screen, location.
            sensorsInUse: Array.from(Privacy.activeKinds ?? []).map(kind => String(kind)),
            updatesAvailable: Updates.available === true ? Number(Updates.count ?? 0) : null,
            resourceAlert: String(ResourceAlerts.active ? ResourceAlerts.kind : "")
        };
    }

    // The next prayer and the weather, as short lines for the orb's quick-answer context.
    function glance(): string {
        const lines = [];
        const w = root.read(() => root.weather());
        if (w && w.available === true)
            lines.push("weather: " + [w.condition, w.temperature, w.feelsLike ? "feels " + w.feelsLike : ""].filter(x => x).join(", ") + (w.city ? " in " + w.city : ""));
        const p = root.read(() => root.prayer());
        if (p && p.available === true && p.next)
            lines.push("next prayer: " + p.next.name + " at " + p.next.time + (p.next.tomorrow ? " tomorrow" : "") + " (in " + p.next.minutesAway + " min)");
        return lines.join("\n");
    }

    // Everything above, by name.
    function snapshot(): var {
        // The tool (not the orb's per-turn glance) may start the very first weather fetch.
        root.read(() => { if (!(Weather.lastFetchTimestamp > 0)) Weather.getData(); });
        return {
            media: root.read(() => root.media()),
            audio: root.read(() => ({ volumePercent: Math.round((Audio.sink?.audio?.volume ?? 0) * 100), muted: Audio.sink?.audio?.muted === true })),
            timers: root.read(() => root.timers()),
            soundscapes: root.read(() => root.soundscapes()),
            recording: root.read(() => ({ audioRecorder: AudioRecorderService.recording === true })),
            downloads: root.read(() => root.downloads()),
            vpn: root.read(() => ({ active: VpnService.active === true })),
            quickShare: root.read(() => ({ transfersActive: QuickShareService.busy === true })),
            gameMode: root.read(() => ({ running: FullGameMode.running === true })),
            sleepInhibited: root.read(() => ({ inhibited: Idle.inhibit === true })),
            notifications: root.read(() => ({ unread: Number(Notifications.unread ?? 0) })),
            ai: root.read(() => root.ai()),
            orb: root.read(() => root.orb()),
            weather: root.read(() => root.weather()),
            prayerTimes: root.read(() => root.prayer()),
            personal: root.read(() => root.personal()),
            connectivity: root.read(() => root.connectivity()),
            attention: root.read(() => root.attention())
        };
    }

    // One short line for the orb's quick-answer context: only what is actively going on.
    function brief(): string {
        const parts = [];
        const add = (name, reader, text) => {
            const value = root.read(reader);
            if (value && value.unavailable === undefined) {
                const said = text(value);
                if (said.length > 0) parts.push(said);
            }
        };
        add("soundscapes", () => root.soundscapes(), v => v.playing ? "soundscape playing" : "");
        add("recording", () => ({ on: AudioRecorderService.recording === true }), v => v.on ? "recording audio" : "");
        add("downloads", () => root.downloads(), v => (v.files > 0 ? v.files + " download" + (v.files === 1 ? "" : "s") : "") || (v.mediaDownloader ? "media download running" : ""));
        add("vpn", () => ({ on: VpnService.active === true }), v => v.on ? "VPN on" : "");
        add("game", () => ({ on: FullGameMode.running === true }), v => v.on ? "game mode" : "");
        add("inhibit", () => ({ on: Idle.inhibit === true }), v => v.on ? "sleep blocked" : "");
        add("ai", () => ({ on: Ai.isGenerating === true }), v => v.on ? "the chat assistant is working" : "");
        return parts.length > 0 ? "running: " + parts.join(", ") : "";
    }
}
