pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import qs
import qs.modules.common

// Prayer times for the Prayer Times desktop widget, from the same source as the
// `prayertime` script (api.aladhan.com, method 5 by default) but for the place the
// weather service resolved, so there is no separate city setting.
// A month is fetched at a time and kept in Persistent, so a restart or a dropped
// connection still has times to show. Today's day is read off the shell clock,
// so the schedule rolls over at midnight and after Isha the next prayer is
// tomorrow's Fajr (the next month is fetched ahead of the month end for that).
Singleton {
    id: root

    readonly property var options: Config.options?.background?.widgets?.prayer_times ?? ({})
    readonly property int method: root.options.method ?? 5

    // Where: whatever the weather service resolved (GPS, IP, or the bar's weather
    // city geocoded). Its location is a plain object that mutates without
    // notifying, so the coordinates are copied out whenever weather refreshes.
    // One value, so a change of place is never seen half-assigned.
    property var coords: ({ lat: 0, lon: 0 })
    readonly property real latitude: root.coords.lat
    readonly property real longitude: root.coords.lon
    property string city: ""
    readonly property bool hasLocation: root.city.length > 0 || root.latitude !== 0 || root.longitude !== 0
    readonly property string locationKey: `${root.latitude.toFixed(2)},${root.longitude.toFixed(2)}|${root.method}`

    function _syncLocation() {
        const loc = Weather.location;
        if (!loc?.valid) return;
        const city = loc.city || Weather.data?.city || "";
        if (root.latitude !== Number(loc.lat) || root.longitude !== Number(loc.lon))
            root.coords = { lat: Number(loc.lat), lon: Number(loc.lon) };
        if (root.city !== city) root.city = city;
    }

    Connections {
        target: Weather
        function onDataRefreshed() { root._syncLocation(); }
    }

    // The five prayers and sunrise, in the order the day runs.
    readonly property var prayerIds: ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
    function prayerName(id) {
        switch (id) {
        case "Fajr": return Translation.tr("Fajr");
        case "Sunrise": return Translation.tr("Sunrise");
        case "Dhuhr": return Translation.tr("Dhuhr");
        case "Asr": return Translation.tr("Asr");
        case "Maghrib": return Translation.tr("Maghrib");
        case "Isha": return Translation.tr("Isha");
        }
        return id;
    }

    // Widgets that want data (including a Settings preview of a widget that is
    // not on the desktop yet) hold a request; nothing is fetched without one.
    property int requests: 0
    readonly property bool wanted: Config.ready && (root.requests > 0 || Config.isWidgetActive("prayer_times"))

    // "<location>|<year>-<month>" -> [{ d: "DD-MM-YYYY", t: { Fajr: "05:12", ... }, h: "9 Rabi' al-thani 1448" }]
    property var months: ({})
    property int dataVersion: 0
    property string error: ""
    property var _inflight: ({})

    readonly property var now: DateTime.clock.date

    function requestData() { root.requests++; }
    function releaseData() { root.requests = Math.max(0, root.requests - 1); }

    function _monthKey(date) {
        return `${root.locationKey}|${date.getFullYear()}-${date.getMonth() + 1}`;
    }

    function _pad(n) { return n < 10 ? "0" + n : "" + n; }

    function _dayStamp(date) {
        return `${root._pad(date.getDate())}-${root._pad(date.getMonth() + 1)}-${date.getFullYear()}`;
    }

    function _dayRecord(date) {
        const list = root.months[root._monthKey(date)];
        if (!list) return null;
        const stamp = root._dayStamp(date);
        const guess = list[date.getDate() - 1];
        if (guess && guess.d === stamp) return guess;
        return list.find(day => day.d === stamp) ?? null;
    }

    // [{ id, name, time: Date }] for a day; empty while its month is not loaded.
    function prayersFor(date) {
        const day = root._dayRecord(date);
        if (!day) return [];
        return root.prayerIds.map(id => {
            const parts = String(day.t[id] ?? "").split(":");
            const time = new Date(date.getFullYear(), date.getMonth(), date.getDate(), Number(parts[0]), Number(parts[1]), 0);
            return { id: id, name: root.prayerName(id), time: time };
        });
    }

    function _tomorrow(date) {
        return new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1);
    }

    readonly property var today: {
        root.dataVersion;
        return root.prayersFor(root.now);
    }

    function _yesterday(date) {
        return new Date(date.getFullYear(), date.getMonth(), date.getDate() - 1);
    }

    // Yesterday through tomorrow, sunrise left out: it is a marker, not a prayer.
    readonly property var timeline: {
        root.dataVersion;
        return root.prayersFor(root._yesterday(root.now))
            .concat(root.today, root.prayersFor(root._tomorrow(root.now)))
            .filter(p => p.id !== "Sunrise");
    }

    // The next prayer; past Isha this is tomorrow's Fajr.
    readonly property var next: root.timeline.find(p => p.time > root.now) ?? null
    // The last one that began, so before Fajr it is yesterday's Isha.
    readonly property var previous: {
        const done = root.timeline.filter(p => p.time <= root.now);
        return done.length > 0 ? done[done.length - 1] : null;
    }
    // How far through the gap between the two, 0..1.
    readonly property real progress: {
        if (!root.next || !root.previous) return 0;
        const span = root.next.time.getTime() - root.previous.time.getTime();
        return span > 0 ? Math.max(0, Math.min(1, (root.now.getTime() - root.previous.time.getTime()) / span)) : 0;
    }
    readonly property var sunrise: root.today.find(p => p.id === "Sunrise") ?? null

    readonly property bool nextIsTomorrow: root.next !== null && root.next.time.getDate() !== root.now.getDate()

    readonly property string hijriDate: {
        root.dataVersion;
        return root._dayRecord(root.now)?.h ?? "";
    }

    // The prayer worth a glance on the island: the next one for the last 20 minutes before
    // it, or the one that began within the last 10 ("Asr" on its own, once the time has come).
    readonly property int glanceSoonMinutes: 20
    readonly property int glanceNowMinutes: 10
    readonly property var glancePrayer: {
        const prev = root.previous;
        if (prev) {
            const elapsed = (root.now.getTime() - prev.time.getTime()) / 60000;
            if (elapsed >= 0 && elapsed < root.glanceNowMinutes)
                return prev;
        }
        return root.next !== null && root.minutesToNext <= root.glanceSoonMinutes ? root.next : null;
    }
    readonly property bool glanceBegan: root.glancePrayer !== null && root.glancePrayer.time.getTime() <= root.now.getTime()

    readonly property int minutesToNext: root.next ? Math.max(0, Math.ceil((root.next.time.getTime() - root.now.getTime()) / 60000)) : 0

    function formatTime(date) {
        return Qt.locale().toString(date, Config.options?.time?.format ?? "hh:mm");
    }

    // The clock and the AM/PM mark apart, for a place too narrow to hold "12:19 PM" on one line:
    // the mark is the trailing a/A/ap/AP of the configured format, empty in a 24-hour one.
    readonly property string _suffixCode: {
        const m = String(Config.options?.time?.format ?? "hh:mm").match(/(ap|AP|a|A)$/);
        return m ? m[1] : "";
    }
    // Formatted WITH the mark (without it Qt switches to a 24-hour clock), then the mark is cut off.
    function formatClock(date) {
        const full = formatTime(date);
        const mark = formatSuffix(date);
        const at = mark === "" ? -1 : full.lastIndexOf(mark);
        return at < 0 ? full : full.slice(0, at).trim();
    }
    function formatSuffix(date) {
        return root._suffixCode === "" ? "" : Qt.locale().toString(date, root._suffixCode);
    }

    // "2h 14m" / "14m"
    function formatRemaining(minutes) {
        const h = Math.floor(minutes / 60);
        const m = minutes % 60;
        return h > 0 ? `${h}h ${m}m` : `${m}m`;
    }

    // ── Fetching ──
    function _ensure(date) {
        const key = root._monthKey(date);
        if (root.months[key] || root._inflight[key]) return;
        root._fetch(date, key);
    }

    function refresh() {
        // After a failed fetch the retry timer owns the next attempt; the minute
        // tick would otherwise hit the API every minute.
        if (!root.wanted || retry.running) return;
        if (!root.hasLocation) return;
        root._ensure(root.now);
        root._ensure(root._tomorrow(root.now));
    }

    function _fetch(date, key) {
        const inflight = root._inflight;
        inflight[key] = true;
        const url = `https://api.aladhan.com/v1/calendar/${date.getFullYear()}/${date.getMonth() + 1}`
            + `?latitude=${root.latitude}&longitude=${root.longitude}&method=${root.method}`;
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            delete root._inflight[key];
            let days = null;
            try {
                // An error body is valid JSON too; only a 200 with a month of days is kept.
                const body = JSON.parse(xhr.responseText);
                if (body.code === 200 && Array.isArray(body.data) && body.data.length >= 28) {
                    days = body.data.map(day => {
                        const t = {};
                        for (const id of root.prayerIds)
                            t[id] = String(day.timings[id]).split(" ")[0];
                        const hijri = day.date.hijri;
                        return { d: day.date.gregorian.date, t: t, h: `${hijri.day} ${hijri.month.en} ${hijri.year}` };
                    });
                }
            } catch (e) {
                days = null;
            }
            if (days === null) {
                root.error = Translation.tr("Couldn't load prayer times");
                retry.restart();
                return;
            }
            root.error = "";
            const next = Object.assign({}, root.months);
            next[key] = days;
            root.months = next;
            root.dataVersion++;
            root._save();
        };
        xhr.open("GET", url);
        xhr.send();
    }

    Timer {
        id: retry
        interval: 5 * 60 * 1000
        repeat: false
        onTriggered: root.refresh()
    }

    // ── Persistence ──
    function _save() {
        if (!Persistent.ready) return;
        // Only this location's current and next month are worth keeping.
        const keep = [root._monthKey(root.now), root._monthKey(root._tomorrow(root.now))];
        const kept = {};
        for (const key of keep) {
            if (root.months[key]) kept[key] = root.months[key];
        }
        Persistent.states.prayer.cacheJson = JSON.stringify(kept);
    }

    function _load() {
        try {
            const cached = JSON.parse(Persistent.states.prayer.cacheJson || "{}");
            const next = Object.assign({}, cached, root.months);
            root.months = next;
            root.dataVersion++;
        } catch (e) {
            console.warn("[PrayerTimes] Ignoring unreadable cache: " + e);
        }
        root.refresh();
    }

    Connections {
        target: Persistent
        function onReadyChanged() { if (Persistent.ready) root._load(); }
    }

    Connections {
        target: Config
        function onReadyChanged() { root.refresh(); }
    }

    // The minute tick also covers midnight: the day and the month are read off it.
    onNowChanged: root.refresh()
    onWantedChanged: root.refresh()
    onHasLocationChanged: root.refresh()
    onLocationKeyChanged: {
        root.error = "";
        retry.stop();
        root.dataVersion++;
        root.refresh();
    }

    Component.onCompleted: {
        root._syncLocation();
        if (Persistent.ready) root._load();
    }
}
