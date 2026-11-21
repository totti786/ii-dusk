pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions

/**
 * Grit & Tomato, in one place.
 *
 * Habits, tasks, focus tags and focus sessions live in one JSON document, so the
 * statistics page can answer questions that cross the two apps: "which tag did I
 * actually spend the week on", "did the days I focused also keep the habits".
 *
 * The timer is kept here rather than in the Focus page because it has to outlive
 * the window: closing Grit must not stop a session. Its state is an absolute
 * start stamp plus accumulated running seconds, so a shell restart, a suspend or
 * a pause resumes into the same place instead of losing time.
 *
 * Every record carries `updatedAt`, `device` and a `deleted` tombstone flag. That
 * is enough for the optional sync server to merge two devices record by record
 * without ever deleting something a newer edit still needs.
 */
Singleton {
    id: root

    // ── Persistence ─────────────────────────────────────────────────────
    readonly property int dataVersion: 1
    property bool loaded: false
    property bool _blockWrites: false
    property double _initTimestamp: Date.now()
    property string deviceId: ""
    property int _serial: 0
    property int revision: 0

    property var habits: []
    property var entries: []
    property var tasks: []
    property var categories: []
    property var tags: []
    property var focusSessions: []
    property var timer: null

    readonly property var activeHabits: root.habits.filter(item => !item.deleted)
    readonly property var activeTasks: root.tasks.filter(item => !item.deleted)
    readonly property var activeCategories: root.categories.filter(item => !item.deleted)
    readonly property var activeTags: root.tags.filter(item => !item.deleted)
    readonly property var activeSessions: root.focusSessions.filter(item => !item.deleted)
    readonly property var activeEntries: root.entries.filter(item => !item.deleted)

    // ── Signals ─────────────────────────────────────────────────────────
    signal focusCompleted(var session)
    signal phaseChanged(string phase)
    signal allHabitsCompleted(var habit)
    signal dataReset()

    // ── Date helpers ────────────────────────────────────────────────────
    property string todayKey: Qt.formatDate(new Date(), "yyyy-MM-dd")
    property int minuteTick: 0

    function dateKey(date) {
        return Qt.formatDate(date, "yyyy-MM-dd");
    }

    function dateFromKey(key) {
        const parts = String(key ?? "").split("-").map(Number);
        if (parts.length !== 3 || !parts[0] || !parts[1] || !parts[2])
            return new Date();
        return new Date(parts[0], parts[1] - 1, parts[2], 12, 0, 0, 0);
    }

    function addDays(key, amount) {
        const date = root.dateFromKey(key);
        date.setDate(date.getDate() + Number(amount || 0));
        return root.dateKey(date);
    }

    function lastNDays(count) {
        const out = [];
        for (let i = Math.max(1, Number(count || 1)) - 1; i >= 0; i--)
            out.push(root.addDays(root.todayKey, -i));
        return out;
    }

    function weekdayOf(key) {
        return root.dateFromKey(key).getDay();
    }

    function weekdayName(key, short) {
        const date = root.dateFromKey(key);
        return Qt.locale().dayName(date.getDay(), short ? Locale.ShortFormat : Locale.LongFormat);
    }

    function relativeDay(key) {
        if (key === root.todayKey)
            return Translation.tr("Today");
        if (key === root.addDays(root.todayKey, 1))
            return Translation.tr("Tomorrow");
        if (key === root.addDays(root.todayKey, -1))
            return Translation.tr("Yesterday");
        return Qt.locale().toString(root.dateFromKey(key), "ddd, d MMM");
    }

    function weekStartOffset() {
        const day = new Date().getDay();
        return (Persistent.states.grit?.weekStartMonday ?? true) ? (day + 6) % 7 : day;
    }

    function thisWeekDays() {
        const start = root.addDays(root.todayKey, -root.weekStartOffset());
        const out = [];
        for (let i = 0; i < 7; i++)
            out.push(root.addDays(start, i));
        return out;
    }

    // ── Identity / plumbing ─────────────────────────────────────────────
    function ensureDeviceId() {
        let id = String(Persistent.states.grit?.deviceId ?? "");
        if (id.length === 0) {
            id = "dev-" + Qt.md5(String(Date.now()) + ":" + String(Math.random())).slice(0, 12);
            Persistent.states.grit.deviceId = id;
        }
        return id;
    }

    function newId(prefix) {
        root._serial = (root._serial + 1) % 1000000;
        return String(prefix ?? "grit") + "-" + root.deviceId.slice(0, 8) + "-"
            + Date.now().toString(36) + "-" + root._serial.toString(36);
    }

    function stamp(record) {
        return Object.assign({}, record ?? {}, {
            updatedAt: Date.now(),
            device: root.deviceId
        });
    }

    function clone(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function live(array) {
        return Array.from(array ?? []).filter(item => item && !item.deleted);
    }

    function sortSessions(list) {
        return Array.from(list ?? []).sort((a, b) => Number(b.endedAt ?? 0) - Number(a.endedAt ?? 0));
    }

    // ── Defaults ────────────────────────────────────────────────────────
    function defaultCategories() {
        return [
            { id: "cat-personal", name: "Personal", accent: "primary", icon: "person", updatedAt: 0, device: "seed", deleted: false },
            { id: "cat-work", name: "Work", accent: "tertiary", icon: "work", updatedAt: 0, device: "seed", deleted: false },
            { id: "cat-study", name: "Study", accent: "secondary", icon: "school", updatedAt: 0, device: "seed", deleted: false },
            { id: "cat-health", name: "Health", accent: "success", icon: "favorite", updatedAt: 0, device: "seed", deleted: false }
        ];
    }

    function defaultTags() {
        return [
            {
                id: "tag-deep-work", name: "Deep work", accent: "primary", color: "",
                shape: "Cookie7Sided", icon: "neurology",
                focusMinutes: 25, breakMinutes: 5, longBreakMinutes: 15, cycles: 4,
                dailyGoalMinutes: 120, autoStartBreak: true, autoStartFocus: false,
                updatedAt: 0, device: "seed", deleted: false
            },
            {
                id: "tag-study", name: "Study", accent: "tertiary", color: "",
                shape: "Cookie9Sided", icon: "school",
                focusMinutes: 45, breakMinutes: 10, longBreakMinutes: 20, cycles: 3,
                dailyGoalMinutes: 90, autoStartBreak: true, autoStartFocus: false,
                updatedAt: 0, device: "seed", deleted: false
            },
            {
                id: "tag-creative", name: "Creative", accent: "secondary", color: "",
                shape: "Flower", icon: "palette",
                focusMinutes: 30, breakMinutes: 8, longBreakMinutes: 15, cycles: 4,
                dailyGoalMinutes: 60, autoStartBreak: true, autoStartFocus: false,
                updatedAt: 0, device: "seed", deleted: false
            },
            {
                id: "tag-admin", name: "Admin", accent: "success", color: "",
                shape: "Cookie4Sided", icon: "inbox",
                focusMinutes: 20, breakMinutes: 5, longBreakMinutes: 10, cycles: 3,
                dailyGoalMinutes: 45, autoStartBreak: true, autoStartFocus: false,
                updatedAt: 0, device: "seed", deleted: false
            }
        ];
    }

    function emptyStore() {
        return {
            version: root.dataVersion,
            habits: [],
            entries: [],
            tasks: [],
            categories: root.defaultCategories(),
            tags: root.defaultTags(),
            focusSessions: [],
            timer: null,
            updatedAt: Date.now(),
            device: root.deviceId
        };
    }

    // ── Normalisation / loading ─────────────────────────────────────────
    function normalizeList(array) {
        if (!Array.isArray(array))
            return [];
        return array
            .filter(item => item && typeof item === "object" && String(item.id ?? "").length > 0)
            .map(item => Object.assign({}, item, {
                updatedAt: Number(item.updatedAt ?? 0) || 0,
                deleted: item.deleted === true
            }));
    }

    /** Older resets could leave a live record and a tombstone sharing one id. */
    function dedupeList(list) {
        const byId = {};
        for (const item of root.normalizeList(list)) {
            const previous = byId[item.id];
            if (!previous
                || (previous.deleted && !item.deleted)
                || (previous.deleted === item.deleted && item.updatedAt > previous.updatedAt))
                byId[item.id] = item;
        }
        return Object.keys(byId).map(id => byId[id]);
    }

    function defaultGoalForTagId(id) {
        switch (String(id ?? "")) {
        case "tag-deep-work": return 120;
        case "tag-study": return 90;
        case "tag-creative": return 60;
        case "tag-admin": return 45;
        default: return 0;
        }
    }

    function normalizeTag(item) {
        const tag = Object.assign({}, item);
        if (!Object.prototype.hasOwnProperty.call(tag, "dailyGoalMinutes"))
            tag.dailyGoalMinutes = root.defaultGoalForTagId(tag.id);
        tag.dailyGoalMinutes = Math.max(0, Math.min(720, Number(tag.dailyGoalMinutes ?? 0)));
        return tag;
    }

    function leaderboardPrefs() {
        const nameAt = Number(Persistent.states.grit?.displayNameUpdatedAt ?? 0);
        const tagsAt = Number(Persistent.states.grit?.publicTagsUpdatedAt ?? 0);
        return {
            displayName: root.displayName,
            nameUpdatedAt: nameAt,
            publicTagIds: root.publicTagIds,
            tagsUpdatedAt: tagsAt,
            updatedAt: Math.max(nameAt, tagsAt)
        };
    }

    function mergeLeaderboardPrefs(local, remote) {
        const a = local && typeof local === "object" ? local : root.leaderboardPrefs();
        const b = remote && typeof remote === "object" ? remote : null;
        if (!b)
            return a;
        const nameWinsRemote = Number(b.nameUpdatedAt ?? 0) > Number(a.nameUpdatedAt ?? 0);
        const tagsWinRemote = Number(b.tagsUpdatedAt ?? 0) > Number(a.tagsUpdatedAt ?? 0);
        const nameAt = Math.max(Number(a.nameUpdatedAt ?? 0), Number(b.nameUpdatedAt ?? 0));
        const tagsAt = Math.max(Number(a.tagsUpdatedAt ?? 0), Number(b.tagsUpdatedAt ?? 0));
        return {
            displayName: nameWinsRemote ? String(b.displayName ?? "") : String(a.displayName ?? ""),
            nameUpdatedAt: nameAt,
            publicTagIds: tagsWinRemote ? Array.from(b.publicTagIds ?? []).map(String)
                : Array.from(a.publicTagIds ?? []).map(String),
            tagsUpdatedAt: tagsAt,
            updatedAt: Math.max(Number(a.updatedAt ?? 0), Number(b.updatedAt ?? 0), nameAt, tagsAt)
        };
    }

    function applyLeaderboardPrefs(prefs) {
        if (!prefs || typeof prefs !== "object")
            return;
        const nameAt = Number(prefs.nameUpdatedAt ?? 0);
        const tagsAt = Number(prefs.tagsUpdatedAt ?? 0);
        if (nameAt > Number(Persistent.states.grit.displayNameUpdatedAt ?? 0)) {
            Persistent.states.grit.displayName = String(prefs.displayName ?? "").trim().slice(0, 40);
            Persistent.states.grit.displayNameUpdatedAt = nameAt;
        }
        if (tagsAt > Number(Persistent.states.grit.publicTagsUpdatedAt ?? 0)) {
            const activeIds = root.activeTags.map(tag => String(tag.id));
            Persistent.states.grit.publicTagIds = Array.from(prefs.publicTagIds ?? [])
                .map(String)
                .filter(id => activeIds.indexOf(id) >= 0);
            Persistent.states.grit.publicTagsUpdatedAt = tagsAt;
        }
    }

    function normalizeStore(raw) {
        const data = raw && typeof raw === "object" ? raw : {};
        return {
            version: Number(data.version ?? root.dataVersion) || root.dataVersion,
            habits: root.dedupeList(data.habits),
            entries: root.dedupeList(data.entries),
            tasks: root.dedupeList(data.tasks),
            categories: Array.isArray(data.categories)
                ? root.dedupeList(data.categories) : root.defaultCategories(),
            tags: Array.isArray(data.tags)
                ? root.dedupeList(data.tags).map(root.normalizeTag) : root.defaultTags(),
            focusSessions: root.sortSessions(root.dedupeList(data.focusSessions)),
            timer: data.timer && typeof data.timer === "object" ? data.timer : null,
            leaderboard: data.leaderboard && typeof data.leaderboard === "object"
                ? root.mergeLeaderboardPrefs(root.leaderboardPrefs(), data.leaderboard) : null,
            updatedAt: Number(data.updatedAt ?? 0) || 0,
            device: String(data.device ?? "")
        };
    }

    function adoptStore(raw) {
        const store = root.normalizeStore(raw);
        root.habits = store.habits;
        root.entries = store.entries;
        root.tasks = store.tasks;
        root.categories = store.categories;
        root.tags = store.tags;
        root.focusSessions = store.focusSessions;
        root.timer = store.timer;
        if (store.leaderboard)
            root.applyLeaderboardPrefs(store.leaderboard);
        root.loaded = true;
        root.ensureTimer();
        root.revision++;
        Qt.callLater(root.reconcileTimerAfterLoad);
    }

    function snapshot() {
        return {
            version: root.dataVersion,
            habits: root.habits,
            entries: root.entries,
            tasks: root.tasks,
            categories: root.categories,
            tags: root.tags,
            focusSessions: root.focusSessions,
            timer: root.timer,
            leaderboard: root.leaderboardPrefs(),
            updatedAt: Date.now(),
            device: root.deviceId
        };
    }

    function saveSoon() {
        if (root.loaded && !root._blockWrites && !root.syncApplying)
            saveTimer.restart();
    }

    function saveNow() {
        if (!root.loaded || root._blockWrites)
            return;
        try {
            storeFile.setText(JSON.stringify(root.snapshot(), null, 1));
        } catch (error) {
            console.warn("[Grit] Could not serialize data:", error);
        }
    }

    Timer {
        id: saveTimer
        interval: 350
        onTriggered: root.saveNow()
    }

    FileView {
        id: storeFile
        path: Qt.resolvedUrl(Directories.gritDataPath)
        atomicWrites: true
        onLoaded: {
            try {
                root.adoptStore(JSON.parse(storeFile.text()));
            } catch (error) {
                console.warn("[Grit] Unreadable data file, keeping a backup and starting fresh:", error);
                Quickshell.execDetached(["cp", Directories.gritDataPath, Directories.gritDataPath + ".corrupt-" + Date.now()]);
                root.adoptStore(root.emptyStore());
                root.saveNow();
            }
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) {
                console.warn("[Grit] Could not read the data file:", error);
                return;
            }
            if (Date.now() - root._initTimestamp < 3000) {
                retryTimer.restart();
                return;
            }
            root.adoptStore(root.emptyStore());
            root.saveNow();
        }
    }

    Timer {
        id: retryTimer
        interval: 1000
        onTriggered: storeFile.reload()
    }

    FileView {
        id: backupFile
        path: ""
        atomicWrites: true
    }

    FileView {
        id: importFile
        path: ""
        onLoaded: {
            try {
                root.restoreFromBackup(JSON.parse(importFile.text()));
            } catch (error) {
                console.warn("[Grit] Could not restore backup:", error);
            }
        }
        onLoadFailed: error => console.warn("[Grit] Could not read backup:", error)
    }

    Timer {
        id: minuteTimer
        interval: 30000
        repeat: true
        running: true
        onTriggered: {
            root.minuteTick++;
            const key = Qt.formatDate(new Date(), "yyyy-MM-dd");
            if (key !== root.todayKey)
                root.todayKey = key;
        }
    }

    Component.onCompleted: {
        root.deviceId = root.ensureDeviceId();
        root.timerTick++;
        if (Persistent.states.grit?.autoSync === undefined)
            Persistent.states.grit.autoSync = true;
        Qt.callLater(() => {
            if (root.autoSync && root.signedIn)
                root.syncNow();
            if (root.signedIn && root.publicTagIds.length > 0)
                root.publishLeaderboard();
        });
    }

    Component.onDestruction: {
        root._blockWrites = true;
        if (saveTimer.running)
            root.saveNow();
    }

    // ── Habit / category access ─────────────────────────────────────────
    function habitById(id) {
        return root.habits.find(item => String(item.id) === String(id)) ?? null;
    }

    function entryFor(habitId, date) {
        const key = String(date ?? root.todayKey);
        return root.activeEntries.find(item =>
            String(item.habitId) === String(habitId) && String(item.date) === key) ?? null;
    }

    function habitValue(habitId, date) {
        return Number(root.entryFor(habitId, date)?.value ?? 0);
    }

    function habitDone(habit, date) {
        if (!habit)
            return false;
        const target = Math.max(1, Number(habit.target ?? 1));
        return root.habitValue(habit.id, date ?? root.todayKey) >= target;
    }

    function habitProgress(habit, date) {
        if (!habit)
            return 0;
        const target = Math.max(1, Number(habit.target ?? 1));
        return Math.max(0, Math.min(1, root.habitValue(habit.id, date ?? root.todayKey) / target));
    }

    function scheduledOn(habit, date) {
        if (!habit)
            return false;
        const days = Array.isArray(habit.days) ? habit.days : [0, 1, 2, 3, 4, 5, 6];
        return days.includes(root.weekdayOf(date ?? root.todayKey));
    }

    function setHabitEntry(habitId, date, value) {
        const key = String(date ?? root.todayKey);
        const habit = root.habitById(habitId);
        if (!habit)
            return false;
        const max = Math.max(1, Number(habit.target ?? 1));
        const nextValue = Math.max(0, Math.min(max, Number(value ?? 0)));
        const existing = root.entryFor(habitId, key);
        let next;
        if (existing) {
            next = root.entries.map(item => String(item.id) === String(existing.id)
                ? root.stamp(Object.assign({}, item, { value: nextValue }))
                : item);
        } else {
            next = root.entries.concat([root.stamp({
                id: root.newId("entry"),
                habitId: String(habitId),
                date: key,
                value: nextValue,
                note: "",
                deleted: false
            })]);
        }
        root.entries = next;
        root.afterHabitChange(habitId);
        return true;
    }

    function incrementHabit(habitId, delta) {
        const habit = root.habitById(habitId);
        if (!habit)
            return;
        root.setHabitEntry(habitId, root.todayKey,
            root.habitValue(habitId, root.todayKey) + Number(delta ?? 1));
    }

    function toggleHabitDone(habitId) {
        const habit = root.habitById(habitId);
        if (!habit)
            return;
        const target = Math.max(1, Number(habit.target ?? 1));
        root.setHabitEntry(habitId, root.todayKey, root.habitDone(habit) ? 0 : target);
    }

    function afterHabitChange(habitId) {
        root.revision++;
        root.saveSoon();
        root.maybeCelebrateHabits(habitId);
        root.syncSoon();
    }

    property string _celebratedDate: ""

    function maybeCelebrateHabits(habitId) {
        const due = root.todayHabits;
        if (due.length === 0)
            return;
        const done = due.filter(habit => root.habitDone(habit)).length;
        if (done >= due.length && root._celebratedDate !== root.todayKey) {
            root._celebratedDate = root.todayKey;
            root.allHabitsCompleted(root.habitById(habitId));
        }
    }

    function createHabit(draft) {
        const data = draft ?? {};
        const habit = root.stamp({
            id: root.newId("habit"),
            name: String(data.name ?? "").trim() || Translation.tr("New habit"),
            icon: String(data.icon ?? "check_circle"),
            categoryId: String(data.categoryId ?? root.activeCategories[0]?.id ?? ""),
            days: Array.isArray(data.days) ? data.days : [0, 1, 2, 3, 4, 5, 6],
            time: String(data.time ?? ""),
            target: Math.max(1, Number(data.target ?? 1)),
            unit: String(data.unit ?? Translation.tr("times")),
            note: String(data.note ?? ""),
            createdAt: Date.now(),
            deleted: false
        });
        root.habits = root.habits.concat([habit]);
        root.revision++;
        root.saveSoon();
        root.syncSoon();
        return habit.id;
    }

    function updateHabit(id, changes) {
        let found = false;
        root.habits = root.habits.map(item => {
            if (String(item.id) !== String(id))
                return item;
            found = true;
            return root.stamp(Object.assign({}, item, changes ?? {}));
        });
        if (found) {
            root.revision++;
            root.saveSoon();
            root.syncSoon();
        }
        return found;
    }

    function deleteHabit(id) {
        root.habits = root.habits.map(item => String(item.id) === String(id)
            ? root.stamp(Object.assign({}, item, { deleted: true }))
            : item);
        root.revision++;
        root.saveSoon();
        root.syncSoon();
    }

    // ── Habits: streak / consistency ────────────────────────────────────
    function currentStreak(habit) {
        if (!habit)
            return 0;
        let cursor = root.todayKey;
        if (!root.scheduledOn(habit, cursor))
            cursor = root.previousScheduled(habit, cursor);
        let streak = 0;
        let guard = 0;
        while (guard++ < 400) {
            if (!root.scheduledOn(habit, cursor)) {
                cursor = root.addDays(cursor, -1);
                continue;
            }
            if (root.habitDone(habit, cursor)) {
                streak++;
                cursor = root.previousScheduled(habit, cursor);
            } else {
                // A day still in progress is not a broken streak yet.
                if (cursor !== root.todayKey)
                    break;
                cursor = root.previousScheduled(habit, cursor);
            }
        }
        return streak;
    }

    function previousScheduled(habit, fromKey) {
        let cursor = root.addDays(fromKey, -1);
        for (let i = 0; i < 14; i++) {
            if (root.scheduledOn(habit, cursor))
                return cursor;
            cursor = root.addDays(cursor, -1);
        }
        return cursor;
    }

    function bestStreak(habit) {
        if (!habit)
            return 0;
        const start = root.dateKey(new Date(Math.max(Number(habit.createdAt ?? Date.now()) - 86400000 * 365, Date.now() - 86400000 * 365)));
        let cursor = start;
        let best = 0;
        let run = 0;
        let guard = 0;
        while (cursor <= root.todayKey && guard++ < 400) {
            if (root.scheduledOn(habit, cursor)) {
                if (root.habitDone(habit, cursor)) {
                    run++;
                    best = Math.max(best, run);
                } else if (cursor !== root.todayKey) {
                    run = 0;
                }
            }
            cursor = root.addDays(cursor, 1);
        }
        return Math.max(best, root.currentStreak(habit));
    }

    function habitConsistency(habit, days) {
        if (!habit)
            return 0;
        const keys = root.lastNDays(Math.max(1, Number(days ?? 30)));
        let due = 0;
        let done = 0;
        for (const key of keys) {
            if (!root.scheduledOn(habit, key))
                continue;
            due++;
            if (root.habitDone(habit, key))
                done++;
        }
        return due > 0 ? done / due : 0;
    }

    function habitWeek(habit) {
        return root.thisWeekDays().map(key => ({
            date: key,
            label: root.weekdayName(key, true).slice(0, 2),
            done: root.habitDone(habit, key),
            scheduled: root.scheduledOn(habit, key),
            today: key === root.todayKey
        }));
    }

    function habitHeatmap(habit, weeks) {
        return root.lastNDays(Math.max(7, Number(weeks ?? 16) * 7)).map(key => ({
            date: key,
            value: root.habitDone(habit, key) ? 1 : 0,
            scheduled: root.scheduledOn(habit, key)
        }));
    }

    readonly property var todayHabits: root.activeHabits
        .filter(habit => root.scheduledOn(habit, root.todayKey))
        .sort((a, b) => String(a.time ?? "99:99").localeCompare(String(b.time ?? "99:99")))
    readonly property int todayHabitsTotal: root.todayHabits.length
    readonly property int todayHabitsDone: root.todayHabits.filter(habit => root.habitDone(habit)).length
    readonly property real todayHabitsProgress: root.todayHabitsTotal > 0 ? root.todayHabitsDone / root.todayHabitsTotal : 0

    function categoryById(id) {
        return root.categories.find(item => String(item.id) === String(id))
            ?? { id: "", name: Translation.tr("Uncategorised"), accent: "outline", icon: "circle", deleted: true };
    }

    function createCategory(draft) {
        const data = draft ?? {};
        const category = root.stamp({
            id: root.newId("cat"),
            name: String(data.name ?? "").trim() || Translation.tr("New category"),
            accent: String(data.accent ?? "primary"),
            icon: String(data.icon ?? "label"),
            deleted: false
        });
        root.categories = root.categories.concat([category]);
        root.revision++;
        root.saveSoon();
        root.syncSoon();
        return category.id;
    }

    function updateCategory(id, changes) {
        root.categories = root.categories.map(item => String(item.id) === String(id)
            ? root.stamp(Object.assign({}, item, changes ?? {}))
            : item);
        root.revision++;
        root.saveSoon();
        root.syncSoon();
    }

    function deleteCategory(id) {
        const fallback = root.activeCategories.find(item => String(item.id) !== String(id))?.id ?? "";
        root.categories = root.categories.map(item => String(item.id) === String(id)
            ? root.stamp(Object.assign({}, item, { deleted: true }))
            : item);
        // Habits and tasks in the old category move to the first surviving one so
        // nothing is left pointing at a group that no longer exists. If every
        // category is gone they become uncategorised instead.
        root.habits = root.habits.map(item => String(item.categoryId ?? "") === String(id)
            ? root.stamp(Object.assign({}, item, { categoryId: fallback }))
            : item);
        root.tasks = root.tasks.map(item => String(item.categoryId ?? "") === String(id)
            ? root.stamp(Object.assign({}, item, { categoryId: fallback }))
            : item);
        root.revision++;
        root.saveNow();
        root.syncSoon();
        return true;
    }

    // ── Tags ────────────────────────────────────────────────────────────
    function tagById(id) {
        return root.tags.find(item => String(item.id) === String(id)) ?? null;
    }

    function activeTagById(id) {
        return root.activeTags.find(item => String(item.id) === String(id)) ?? null;
    }

    function createTag(draft) {
        const data = draft ?? {};
        const tag = root.stamp({
            id: root.newId("tag"),
            name: String(data.name ?? "").trim() || Translation.tr("New tag"),
            accent: String(data.accent ?? "primary"),
            color: String(data.color ?? ""),
            shape: String(data.shape ?? "Cookie7Sided"),
            icon: String(data.icon ?? "local_fire_department"),
            focusMinutes: Math.max(1, Number(data.focusMinutes ?? 25)),
            breakMinutes: Math.max(1, Number(data.breakMinutes ?? 5)),
            longBreakMinutes: Math.max(1, Number(data.longBreakMinutes ?? 15)),
            cycles: Math.max(1, Number(data.cycles ?? 4)),
            dailyGoalMinutes: Math.max(0, Math.min(720, Number(data.dailyGoalMinutes ?? 0))),
            autoStartBreak: data.autoStartBreak !== false,
            autoStartFocus: data.autoStartFocus === true,
            deleted: false
        });
        root.tags = root.tags.concat([tag]);
        root.revision++;
        root.saveSoon();
        root.syncSoon();
        return tag.id;
    }

    function updateTag(id, changes) {
        let found = false;
        root.tags = root.tags.map(item => {
            if (String(item.id) !== String(id))
                return item;
            found = true;
            const merged = Object.assign({}, item, changes ?? {});
            merged.focusMinutes = Math.max(1, Number(merged.focusMinutes ?? 25));
            merged.breakMinutes = Math.max(1, Number(merged.breakMinutes ?? 5));
            merged.longBreakMinutes = Math.max(1, Number(merged.longBreakMinutes ?? 15));
            merged.cycles = Math.max(1, Number(merged.cycles ?? 4));
            merged.dailyGoalMinutes = Math.max(0, Math.min(720, Number(merged.dailyGoalMinutes ?? 0)));
            return root.stamp(merged);
        });
        if (found) {
            if (root.timer && String(root.timer.tagId) === String(id) && !root.timer.running) {
                const tag = root.tagById(id);
                const minutes = root.minutesForPhase(tag, root.timer.phase);
                root.timer = Object.assign({}, root.timer, {
                    durationSec: minutes * 60,
                    accumulatedSec: Math.min(Number(root.timer.accumulatedSec ?? 0), minutes * 60),
                    updatedAt: Date.now()
                });
            }
            root.revision++;
            root.saveSoon();
            root.syncSoon();
        }
        return found;
    }

    function deleteTag(id) {
        if (root.activeTags.length <= 1)
            return false;
        root.tags = root.tags.map(item => String(item.id) === String(id)
            ? root.stamp(Object.assign({}, item, { deleted: true }))
            : item);
        if (root.timer && String(root.timer.tagId) === String(id)) {
            const fallback = root.activeTags[0];
            root.timer = Object.assign({}, root.timer, { tagId: fallback?.id ?? "", updatedAt: Date.now() });
        }
        root.revision++;
        root.saveSoon();
        root.syncSoon();
        return true;
    }

    function minutesForPhase(tag, phase) {
        if (!tag)
            return 25;
        if (phase === "shortBreak")
            return Math.max(1, Number(tag.breakMinutes ?? 5));
        if (phase === "longBreak")
            return Math.max(1, Number(tag.longBreakMinutes ?? 15));
        return Math.max(1, Number(tag.focusMinutes ?? 25));
    }

    // ── Tasks ───────────────────────────────────────────────────────────
    function taskById(id) {
        return root.tasks.find(item => String(item.id) === String(id)) ?? null;
    }

    function normalizeSubtasks(list) {
        return Array.from(list ?? []).map(task => ({
            id: String(task.id ?? root.newId("sub")),
            title: String(task.title ?? "").trim(),
            done: task.done === true,
            updatedAt: Number(task.updatedAt ?? Date.now())
        })).filter(task => task.title.length > 0);
    }

    function createTask(draft) {
        const data = draft ?? {};
        const task = root.stamp({
            id: root.newId("task"),
            title: String(data.title ?? "").trim() || Translation.tr("New task"),
            notes: String(data.notes ?? ""),
            categoryId: String(data.categoryId ?? root.activeCategories[0]?.id ?? ""),
            due: String(data.due ?? ""),
            done: data.done === true,
            priority: Math.max(0, Math.min(2, Number(data.priority ?? 0))),
            subtasks: root.normalizeSubtasks(data.subtasks),
            taskTag: String(data.taskTag ?? ""),
            deleted: false,
            createdAt: Date.now()
        });
        root.tasks = root.tasks.concat([task]);
        root.revision++;
        root.saveSoon();
        root.syncSoon();
        return task.id;
    }

    function updateTask(id, changes) {
        let found = false;
        root.tasks = root.tasks.map(item => {
            if (String(item.id) !== String(id))
                return item;
            found = true;
            const merged = Object.assign({}, item, changes ?? {});
            if (changes && Object.prototype.hasOwnProperty.call(changes, "subtasks"))
                merged.subtasks = root.normalizeSubtasks(changes.subtasks);
            merged.priority = Math.max(0, Math.min(2, Number(merged.priority ?? 0)));
            return root.stamp(merged);
        });
        if (found) {
            root.revision++;
            root.saveSoon();
            root.syncSoon();
        }
        return found;
    }

    function deleteTask(id) {
        root.tasks = root.tasks.map(item => String(item.id) === String(id)
            ? root.stamp(Object.assign({}, item, { deleted: true }))
            : item);
        root.revision++;
        root.saveSoon();
        root.syncSoon();
    }

    function toggleTask(id) {
        const task = root.taskById(id);
        if (!task)
            return;
        root.updateTask(id, { done: !task.done });
    }

    function addSubtask(taskId, title) {
        const task = root.taskById(taskId);
        const text = String(title ?? "").trim();
        if (!task || text.length === 0)
            return;
        root.updateTask(taskId, {
            subtasks: Array.from(task.subtasks ?? []).concat([{
                id: root.newId("sub"), title: text, done: false, updatedAt: Date.now()
            }])
        });
    }

    function toggleSubtask(taskId, subtaskId) {
        const task = root.taskById(taskId);
        if (!task)
            return;
        root.updateTask(taskId, {
            subtasks: Array.from(task.subtasks ?? []).map(sub =>
                String(sub.id) === String(subtaskId)
                    ? Object.assign({}, sub, { done: !sub.done, updatedAt: Date.now() })
                    : sub)
        });
    }

    function removeSubtask(taskId, subtaskId) {
        const task = root.taskById(taskId);
        if (!task)
            return;
        root.updateTask(taskId, {
            subtasks: Array.from(task.subtasks ?? []).filter(sub => String(sub.id) !== String(subtaskId))
        });
    }

    function taskFiltered(filter) {
        const now = root.todayKey;
        let list = root.activeTasks.slice();
        if (filter === "today")
            list = list.filter(task => !task.done && (task.due === now || (task.due.length > 0 && task.due < now)));
        else if (filter === "upcoming")
            list = list.filter(task => !task.done && task.due > now);
        else if (filter === "done")
            list = list.filter(task => task.done);
        else if (filter === "open")
            list = list.filter(task => !task.done);
        return list.sort((a, b) => {
            if (a.done !== b.done)
                return a.done ? 1 : -1;
            if (a.due !== b.due)
                return String(a.due ?? "9999").localeCompare(String(b.due ?? "9999"));
            if (a.priority !== b.priority)
                return Number(b.priority ?? 0) - Number(a.priority ?? 0);
            return Number(b.createdAt ?? 0) - Number(a.createdAt ?? 0);
        });
    }

    /** The to-do list that belongs to one focus tag. */
    function tasksForTag(tagId) {
        return root.activeTasks
            .filter(task => String(task.taskTag ?? "") === String(tagId ?? ""))
            .sort((a, b) => {
                if (a.done !== b.done)
                    return a.done ? 1 : -1;
                if (a.due !== b.due)
                    return String(a.due ?? "9999").localeCompare(String(b.due ?? "9999"));
                return Number(b.createdAt ?? 0) - Number(a.createdAt ?? 0);
            });
    }

    function createTagTask(tagId, title) {
        return root.createTask({
            title: title,
            taskTag: String(tagId ?? ""),
            due: root.todayKey,
            categoryId: root.activeCategories[0]?.id ?? ""
        });
    }

    readonly property int openTaskCount: root.activeTasks.filter(task => !task.done).length
    readonly property int doneTaskCount: root.activeTasks.filter(task => task.done).length
    readonly property int dueTodayTaskCount: root.activeTasks.filter(task =>
        !task.done && task.due.length > 0 && task.due <= root.todayKey).length
    readonly property int overdueTaskCount: root.activeTasks.filter(task =>
        !task.done && task.due.length > 0 && task.due < root.todayKey).length

    function taskSubtaskProgress(task) {
        const subtasks = Array.from(task?.subtasks ?? []);
        if (subtasks.length === 0)
            return -1;
        return subtasks.filter(sub => sub.done).length / subtasks.length;
    }

    // ── Timer ───────────────────────────────────────────────────────────
    property int timerTick: 0

    readonly property string timerPhase: String(root.timer?.phase ?? "focus")
    readonly property bool timerRunning: root.timer?.running === true
    readonly property bool timerPaused: root.timer !== null && root.timer?.running !== true
        && Number(root.timer?.accumulatedSec ?? 0) > 0
    readonly property string activeTagId: String(root.timer?.tagId ?? root.activeTags[0]?.id ?? "")
    readonly property var activeTag: root.tagById(root.activeTagId) ?? root.activeTags[0] ?? null
    readonly property int timerCycles: Math.max(1, Number(root.activeTag?.cycles ?? 4))
    readonly property int timerCycle: Math.max(0, Number(root.timer?.cycle ?? 0))
    readonly property int timerDurationSec: Math.max(1, Number(root.timer?.durationSec ?? (root.minutesForPhase(root.activeTag, root.timerPhase) * 60)))
    readonly property int timerSecondsLeft: {
        root.timerTick;
        return root.computeSecondsLeft(root.timer);
    }
    readonly property real timerProgress: {
        root.timerTick;
        return Math.max(0, Math.min(1, 1 - root.timerSecondsLeft / root.timerDurationSec));
    }
    readonly property string timerPhaseLabel: root.timerPhase === "shortBreak"
        ? Translation.tr("Short break")
        : root.timerPhase === "longBreak" ? Translation.tr("Long break") : Translation.tr("Focus")

    function computeSecondsLeft(value) {
        if (!value)
            return 0;
        const duration = Math.max(1, Number(value.durationSec ?? 0));
        const accumulated = Math.max(0, Number(value.accumulatedSec ?? 0));
        const runningPart = value.running ? (Date.now() - Number(value.runStartedAt ?? Date.now())) / 1000 : 0;
        return Math.max(0, Math.ceil(duration - accumulated - runningPart));
    }

    function elapsedSeconds(value) {
        if (!value)
            return 0;
        const accumulated = Math.max(0, Number(value.accumulatedSec ?? 0));
        const runningPart = value.running ? (Date.now() - Number(value.runStartedAt ?? Date.now())) / 1000 : 0;
        return Math.max(0, Math.min(Number(value.durationSec ?? 0), accumulated + runningPart));
    }

    function makeTimer(tagId, phase, cycle, running) {
        const tag = root.activeTagById(tagId) ?? root.activeTagById(root.activeTagId)
            ?? root.activeTags[0] ?? null;
        const minutes = root.minutesForPhase(tag, phase);
        const now = Date.now();
        return {
            phase: String(phase ?? "focus"),
            tagId: String(tag?.id ?? ""),
            taskId: "",
            note: "",
            running: running === true,
            startedAt: now,
            runStartedAt: running === true ? now : 0,
            accumulatedSec: 0,
            durationSec: Math.round(minutes * 60),
            sessionId: root.newId("session"),
            cycle: Math.max(0, Number(cycle ?? 0)),
            updatedAt: now,
            device: root.deviceId
        };
    }

    function ensureTimer() {
        if (!root.timer || typeof root.timer !== "object" || !String(root.timer.phase ?? "").length) {
            root.timer = root.makeTimer(root.activeTagId, "focus", 0, false);
            return;
        }
        const tag = root.tagById(root.timer.tagId);
        if (!tag) {
            root.timer = Object.assign({}, root.timer, {
                tagId: root.activeTags[0]?.id ?? "",
                updatedAt: Date.now()
            });
        }
    }

    function selectTag(tagId) {
        if (root.timerRunning)
            return false;
        const tag = root.activeTagById(tagId);
        if (!tag)
            return false;
        root.timer = root.makeTimer(tag.id, root.timerPhase, root.timerCycle, false);
        root.revision++;
        root.saveSoon();
        root.syncSoon();
        return true;
    }

    function setTimerNote(text) {
        if (!root.timer)
            root.ensureTimer();
        root.timer = Object.assign({}, root.timer, {
            note: String(text ?? ""),
            updatedAt: Date.now()
        });
        root.saveSoon();
    }

    function startPhase(tagId, phase, cycle, running) {
        root.timer = root.makeTimer(tagId, phase, cycle, running);
        root.timerTick++;
        root.revision++;
        root.saveSoon();
        root.syncSoon();
        root.phaseChanged(root.timer.phase);
    }

    function toggleTimer() {
        if (!root.timer) {
            root.startFocusNow(root.activeTagId);
            return;
        }
        if (root.timerRunning)
            root.pauseTimer();
        else if (root.timerSecondsLeft <= 0)
            root.startFocusNow(root.activeTagId);
        else
            root.resumeTimer();
    }

    function startFocusNow(tagId) {
        const id = String(tagId ?? root.activeTagId);
        const tag = root.activeTagById(id) ?? root.activeTags[0] ?? null;
        root.startPhase(tag?.id ?? "", "focus", root.timer?.phase === "focus" ? root.timerCycle : 0, true);
    }

    function pauseTimer() {
        if (!root.timer || !root.timer.running)
            return;
        const elapsed = root.elapsedSeconds(root.timer);
        root.timer = Object.assign({}, root.timer, {
            running: false,
            runStartedAt: 0,
            accumulatedSec: elapsed,
            updatedAt: Date.now()
        });
        root.timerTick++;
        root.saveSoon();
        root.syncSoon();
    }

    function resumeTimer() {
        if (!root.timer || root.timer.running)
            return;
        if (root.computeSecondsLeft(root.timer) <= 0) {
            root.startFocusNow(root.activeTagId);
            return;
        }
        root.timer = Object.assign({}, root.timer, {
            running: true,
            runStartedAt: Date.now(),
            updatedAt: Date.now()
        });
        root.timerTick++;
        root.saveNow();
        root.syncSoon();
    }

    function resetTimer() {
        if (!root.timer)
            return;
        const current = root.timer;
        root.finalizeSession(current, false);
        root.timer = root.makeTimer(current.tagId, current.phase, current.cycle, false);
        root.timerTick++;
        root.revision++;
        root.saveNow();
        root.syncSoon();
    }

    function skipTimer() {
        if (!root.timer)
            return;
        const current = root.timer;
        root.finalizeSession(current, false);
        root.advanceAfter(current, false);
    }

    function finalizeSession(value, completed) {
        if (!value)
            return null;
        const elapsed = Math.round(root.elapsedSeconds(value));
        if (elapsed < 15)
            return null;
        const session = root.stamp({
            id: String(value.sessionId ?? root.newId("session")),
            tagId: String(value.tagId ?? ""),
            taskId: String(value.taskId ?? ""),
            phase: String(value.phase ?? "focus"),
            startedAt: Number(value.startedAt ?? (Date.now() - elapsed * 1000)),
            endedAt: Date.now(),
            durationSec: elapsed,
            plannedSec: Math.max(1, Number(value.durationSec ?? elapsed)),
            completed: completed === true,
            note: String(value.note ?? ""),
            deleted: false
        });
        if (!root.focusSessions.some(item => String(item.id) === String(session.id))) {
            root.focusSessions = root.sortSessions(root.focusSessions.concat([session]));
            root.revision++;
        }
        return session;
    }

    function completeCurrentPhase() {
        if (!root.timer)
            return;
        const current = root.timer;
        const wouldAdvance = true;
        root.timer = Object.assign({}, current, {
            running: false,
            runStartedAt: 0,
            accumulatedSec: Math.max(Number(current.durationSec ?? 0), root.elapsedSeconds(current)),
            updatedAt: Date.now()
        });
        const session = root.finalizeSession(root.timer, true);
        root.afterPhaseDone(root.timer, session);
    }

    function advanceAfter(current, completed) {
        const tag = root.tagById(current.tagId) ?? root.activeTag ?? {};
        const phase = String(current.phase ?? "focus");
        const cycles = Math.max(1, Number(tag.cycles ?? 4));
        if (phase === "focus") {
            const count = Math.max(0, Number(current.cycle ?? 0)) + 1;
            const long = count >= cycles;
            root.startPhase(tag.id, long ? "longBreak" : "shortBreak", count, tag.autoStartBreak === true);
        } else {
            const cycle = phase === "longBreak" ? 0 : Math.max(0, Number(current.cycle ?? 0));
            root.startPhase(tag.id, "focus", cycle, tag.autoStartFocus === true);
        }
    }

    function afterPhaseDone(value, session) {
        const tag = root.tagById(value.tagId) ?? root.activeTag;
        const phase = String(value.phase ?? "focus");
        if (phase === "focus") {
            root.focusCompleted(session);
            root.notifyPhase(tag, true);
        } else {
            root.notifyPhase(tag, false);
        }
        root.advanceAfter(value, true);
        root.timerTick++;
        root.revision++;
        root.saveNow();
        root.syncSoon();
    }

    function notifyPhase(tag, focusDone) {
        const title = focusDone
            ? Translation.tr("Focus complete")
            : Translation.tr("Break over");
        const body = focusDone
            ? Translation.tr("%1 · %2").arg(String(tag?.name ?? Translation.tr("Focus"))).arg(Translation.tr("Time for a break"))
            : Translation.tr("Ready for another focus session?");
        if (Config.options?.time?.timer?.notify ?? true) {
            Quickshell.execDetached(["notify-send", title, body, "-a", "Panadoro",
                "-i", "local_fire_department", "--hint=boolean:suppress-sound:true"]);
        }
        SoundService.playEvent("timer", "alarm-clock-elapsed");
    }

    function reconcileTimerAfterLoad() {
        root.ensureTimer();
        if (root.timer?.running && root.computeSecondsLeft(root.timer) <= 0)
            root.completeCurrentPhase();
        root.revision++;
    }

    Timer {
        id: phaseTimer
        interval: 500
        repeat: true
        running: root.timerRunning
        onTriggered: {
            root.timerTick++;
            if (root.timerSecondsLeft <= 0)
                root.completeCurrentPhase();
        }
    }

    // ── Focus statistics ────────────────────────────────────────────────
    function sessionsInRange(days, phase) {
        const start = root.dateFromKey(root.addDays(root.todayKey, -(Math.max(1, Number(days ?? 7)) - 1)));
        const startMs = new Date(start.getFullYear(), start.getMonth(), start.getDate()).getTime();
        return root.activeSessions.filter(session => {
            if (phase && String(session.phase) !== String(phase))
                return false;
            return Number(session.endedAt ?? 0) >= startMs;
        });
    }

    function secondsInRange(days, phase) {
        return root.sessionsInRange(days, phase)
            .reduce((total, session) => total + Math.max(0, Number(session.durationSec ?? 0)), 0);
    }

    function focusMinutesInRange(days) {
        return Math.round(root.secondsInRange(days, "focus") / 60);
    }

    readonly property int todayFocusSeconds: {
        root.revision;
        return root.activeSessions
            .filter(session => String(session.phase) === "focus" && root.dateKey(new Date(Number(session.endedAt ?? 0))) === root.todayKey)
            .reduce((total, session) => total + Math.max(0, Number(session.durationSec ?? 0)), 0);
    }
    readonly property int todayFocusMinutes: Math.round(root.todayFocusSeconds / 60)
    readonly property int todayFocusSessions: {
        root.revision;
        return root.activeSessions.filter(session => String(session.phase) === "focus"
            && root.dateKey(new Date(Number(session.endedAt ?? 0))) === root.todayKey).length;
    }
    readonly property int weekFocusMinutes: {
        root.revision;
        const days = root.thisWeekDays();
        return Math.round(root.activeSessions
            .filter(session => String(session.phase) === "focus"
                && days.includes(root.dateKey(new Date(Number(session.endedAt ?? 0)))))
            .reduce((total, session) => total + Number(session.durationSec ?? 0), 0) / 60);
    }
    readonly property int totalFocusMinutes: {
        root.revision;
        return Math.round(root.activeSessions
            .filter(session => String(session.phase) === "focus")
            .reduce((total, session) => total + Number(session.durationSec ?? 0), 0) / 60);
    }

    function focusStreak() {
        const days = {};
        for (const session of root.activeSessions) {
            if (String(session.phase) !== "focus" || Number(session.durationSec ?? 0) < 30)
                continue;
            days[root.dateKey(new Date(Number(session.endedAt ?? 0)))] = true;
        }
        let cursor = root.todayKey;
        if (!days[cursor])
            cursor = root.addDays(cursor, -1);
        let streak = 0;
        while (days[cursor] && streak < 3650) {
            streak++;
            cursor = root.addDays(cursor, -1);
        }
        return streak;
    }

    function tagSecondsInRange(tagId, days) {
        return root.sessionsInRange(days, "focus")
            .filter(session => String(session.tagId ?? "") === String(tagId ?? ""))
            .reduce((total, session) => total + Math.max(0, Number(session.durationSec ?? 0)), 0);
    }

    function tagTodayMinutes(tagId) {
        return Math.round(root.tagSecondsInRange(tagId, 1) / 60);
    }

    function tagPercent(tagId, days) {
        const total = root.secondsInRange(days, "focus");
        return total > 0 ? root.tagSecondsInRange(tagId, days) / total : 0;
    }

    function tagStreak(tagId) {
        const dates = {};
        for (const session of root.activeSessions) {
            if (String(session.phase) !== "focus" || String(session.tagId ?? "") !== String(tagId ?? ""))
                continue;
            dates[root.dateKey(new Date(Number(session.endedAt ?? 0)))] = true;
        }
        let key = root.todayKey;
        if (!dates[key])
            key = root.addDays(key, -1);
        let streak = 0;
        while (dates[key]) {
            streak++;
            key = root.addDays(key, -1);
        }
        return streak;
    }

    function tagGoalProgress(tag) {
        const goal = Math.max(0, Number(tag?.dailyGoalMinutes ?? 0));
        if (goal <= 0)
            return -1;
        return Math.max(0, Math.min(1, root.tagTodayMinutes(tag?.id ?? "") / goal));
    }

    function tagStats(days) {
        const totals = {};
        for (const session of root.sessionsInRange(days, "focus")) {
            const id = String(session.tagId ?? "");
            if (!totals[id])
                totals[id] = { tagId: id, seconds: 0, sessions: 0 };
            totals[id].seconds += Math.max(0, Number(session.durationSec ?? 0));
            totals[id].sessions++;
        }
        const allSeconds = Math.max(1, root.secondsInRange(days, "focus"));
        return Object.keys(totals)
            .map(id => {
                const tag = root.tagById(id);
                return Object.assign({}, totals[id], {
                    tag: tag,
                    name: tag?.name ?? Translation.tr("Untagged"),
                    accent: tag?.accent ?? "outline",
                    color: tag?.color ?? "",
                    shape: tag?.shape ?? "Circle",
                    percent: totals[id].seconds / allSeconds,
                    streak: root.tagStreak(id),
                    goalMinutes: Math.max(0, Number(tag?.dailyGoalMinutes ?? 0)),
                    todayMinutes: root.tagTodayMinutes(id)
                });
            })
            .sort((a, b) => b.seconds - a.seconds);
    }

    function dailyFocusSeries(days, phase) {
        const keys = root.lastNDays(Math.max(1, Number(days ?? 7)));
        const index = {};
        for (const key of keys)
            index[key] = { date: key, label: root.weekdayName(key, true).slice(0, 2), focus: 0, breaks: 0 };
        for (const session of root.activeSessions) {
            const key = root.dateKey(new Date(Number(session.endedAt ?? 0)));
            if (!index[key])
                continue;
            if (String(session.phase) === "focus")
                index[key].focus += Math.max(0, Number(session.durationSec ?? 0));
            else
                index[key].breaks += Math.max(0, Number(session.durationSec ?? 0));
        }
        return keys.map(key => index[key]);
    }

    /**
     * One entry per day, with each day's focus split into tag-coloured segments.
     * This is what the "focus by tag" chart draws.
     */
    function dailyTagFocusSeries(days) {
        const keys = root.lastNDays(Math.max(1, Number(days ?? 7)));
        const index = {};
        for (const key of keys)
            index[key] = {
                date: key,
                label: root.weekdayName(key, true).slice(0, 2),
                total: 0,
                segments: []
            };
        for (const session of root.activeSessions) {
            if (String(session.phase) !== "focus")
                continue;
            const key = root.dateKey(new Date(Number(session.endedAt ?? 0)));
            const day = index[key];
            if (!day)
                continue;
            const tagId = String(session.tagId ?? "");
            let segment = day.segments.find(item => item.tagId === tagId);
            if (!segment) {
                segment = { tagId: tagId, tag: root.tagById(tagId), seconds: 0 };
                day.segments.push(segment);
            }
            segment.seconds += Math.max(0, Number(session.durationSec ?? 0));
            day.total += Math.max(0, Number(session.durationSec ?? 0));
        }
        for (const key of keys)
            index[key].segments.sort((a, b) => b.seconds - a.seconds);
        return keys.map(key => index[key]);
    }

    /** One tag's daily focus graph, in that tag's colour. */
    function tagFocusSeries(tagId, days) {
        return root.dailyTagFocusSeries(days).map(day => {
            const segment = day.segments.find(item => String(item.tagId) === String(tagId ?? ""));
            const seconds = Math.max(0, Number(segment?.seconds ?? 0));
            return {
                date: day.date,
                label: day.label,
                total: seconds,
                segments: seconds > 0 ? [{
                    tagId: String(tagId ?? ""),
                    tag: root.tagById(tagId),
                    seconds: seconds
                }] : []
            };
        });
    }

    function focusHeatmap(days) {
        return root.lastNDays(Math.max(7, Number(days ?? 84))).map(key => {
            let value = 0;
            for (const session of root.activeSessions) {
                if (String(session.phase) !== "focus")
                    continue;
                if (root.dateKey(new Date(Number(session.endedAt ?? 0))) === key)
                    value += Math.max(0, Number(session.durationSec ?? 0));
            }
            return { date: key, value: value };
        });
    }

    /**
     * A week-aligned heatmap. Every column is a real week (starting on the user's
     * first day of the week), so the grid never starts halfway through a column.
     * `tagId` narrows it to one focus tag.
     */
    function focusHeatmapWeeks(weeks, tagId) {
        const count = Math.max(1, Number(weeks ?? 12));
        const offset = root.weekStartOffset();
        const start = root.addDays(root.todayKey, -offset - (count - 1) * 7);
        const wantedTag = String(tagId ?? "");
        const out = [];
        for (let i = 0; i < count * 7; i++) {
            const key = root.addDays(start, i);
            let value = 0;
            for (const session of root.activeSessions) {
                if (String(session.phase) !== "focus")
                    continue;
                if (wantedTag.length > 0 && String(session.tagId ?? "") !== wantedTag)
                    continue;
                if (root.dateKey(new Date(Number(session.endedAt ?? 0))) === key)
                    value += Math.max(0, Number(session.durationSec ?? 0));
            }
            out.push({ date: key, value: value, future: key > root.todayKey });
        }
        return out;
    }

    function timeOfDayStats(days) {
        const buckets = [
            { id: "night", label: Translation.tr("Night"), range: "00–06", seconds: 0 },
            { id: "morning", label: Translation.tr("Morning"), range: "06–12", seconds: 0 },
            { id: "afternoon", label: Translation.tr("Afternoon"), range: "12–18", seconds: 0 },
            { id: "evening", label: Translation.tr("Evening"), range: "18–24", seconds: 0 }
        ];
        for (const session of root.sessionsInRange(days, "focus")) {
            const hour = new Date(Number(session.startedAt ?? session.endedAt ?? 0)).getHours();
            const index = Math.max(0, Math.min(3, Math.floor(hour / 6)));
            buckets[index].seconds += Math.max(0, Number(session.durationSec ?? 0));
        }
        return buckets;
    }

    function breakRatio(days) {
        const focus = root.secondsInRange(days, "focus");
        const breaks = root.secondsInRange(days, "shortBreak") + root.secondsInRange(days, "longBreak");
        return { focus: focus, breaks: breaks, ratio: breaks > 0 ? focus / breaks : 0 };
    }

    function bestFocusDay(days) {
        const series = root.dailyFocusSeries(days);
        let best = { date: "", focus: 0 };
        for (const day of series)
            if (day.focus > best.focus)
                best = day;
        return best;
    }

    function recentSessions(limit) {
        return root.activeSessions.slice(0, Math.max(1, Number(limit ?? 8)));
    }

    function deleteSession(id) {
        root.focusSessions = root.focusSessions.map(session => String(session.id) === String(id)
            ? root.stamp(Object.assign({}, session, { deleted: true }))
            : session);
        root.revision++;
        root.saveSoon();
        root.syncSoon();
    }

    // ── Task / habit summary for stats ──────────────────────────────────
    function habitStats(days) {
        const list = root.lastNDays(Math.max(1, Number(days ?? 30)));
        return root.activeHabits.map(habit => {
            let due = 0;
            let done = 0;
            for (const key of list) {
                if (!root.scheduledOn(habit, key))
                    continue;
                due++;
                if (root.habitDone(habit, key))
                    done++;
            }
            return {
                habit: habit,
                name: habit.name,
                due: due,
                done: done,
                rate: due > 0 ? done / due : 0,
                streak: root.currentStreak(habit),
                best: root.bestStreak(habit)
            };
        }).sort((a, b) => b.rate - a.rate);
    }

    function habitHeatmapAll(days) {
        const keys = root.lastNDays(Math.max(7, Number(days ?? 84)));
        return keys.map(key => {
            const due = root.activeHabits.filter(habit => root.scheduledOn(habit, key));
            const done = due.filter(habit => root.habitDone(habit, key)).length;
            return {
                date: key,
                value: due.length > 0 ? done / due.length : 0,
                done: done,
                due: due.length
            };
        });
    }

    // ── Firebase account settings ───────────────────────────────────────
    readonly property string firebaseProjectId: "habit-tracker-bd354"
    readonly property string firebaseApiKey: "AIzaSyAc97ILytNHNXRbS_EapcllNLd1CcaoLPo"
    readonly property string firebaseDatabase: "default"
    readonly property string firebaseCollection: "panadora"
    readonly property string authEmail: String(Persistent.states.grit?.authEmail ?? "")
    readonly property string authUid: String(Persistent.states.grit?.authUid ?? "")
    readonly property string authIdToken: String(Persistent.states.grit?.authIdToken ?? "")
    readonly property string authRefreshToken: String(Persistent.states.grit?.authRefreshToken ?? "")
    readonly property double authExpiresAt: Number(Persistent.states.grit?.authExpiresAt ?? 0)
    readonly property bool signedIn: root.authUid.length > 0 && root.authRefreshToken.length > 0
    readonly property bool autoSync: Persistent.states.grit?.autoSync === true
    property bool syncApplying: false
    property bool syncInProgress: false
    property int _postAttempt: 0
    property bool authBusy: false
    property string authError: ""
    property string syncStatus: root.signedIn ? "idle" : "off"
    property string syncMessage: root.signedIn ? "" : Translation.tr("Sign in to sync")

    // ── Public leaderboard ──────────────────────────────────────────────
    // Only the focus tags the user marks public are mirrored here; habits,
    // tasks, notes and private tags never leave the private sync document.
    readonly property string leaderboardCollection: "panadora_leaderboard"
    readonly property string displayName: String(Persistent.states.grit?.displayName ?? "")
    readonly property var publicTagIds: {
        const value = Persistent.states.grit?.publicTagIds;
        return Array.isArray(value) ? value.map(String) : [];
    }
    readonly property string effectiveDisplayName: {
        const custom = root.displayName.trim();
        if (custom.length > 0)
            return custom;
        const local = root.authEmail.split("@")[0].trim();
        if (local.length === 0)
            return Translation.tr("Panadoro user");
        return local.replace(/[._-]+/g, " ")
            .split(" ")
            .filter(word => word.length > 0)
            .map(word => word.charAt(0).toUpperCase() + word.slice(1))
            .join(" ")
            .slice(0, 40);
    }
    property var leaderboardEntries: []
    property bool leaderboardLoading: false
    property string leaderboardError: ""
    property double leaderboardUpdatedAt: 0

    function setDisplayName(value) {
        const clean = String(value ?? "").trim().slice(0, 40);
        if (clean === root.displayName)
            return;
        Persistent.states.grit.displayName = clean;
        Persistent.states.grit.displayNameUpdatedAt = Date.now();
        root.leaderboardSoon();
    }

    function setTagPublic(tagId, isPublic) {
        const id = String(tagId ?? "");
        if (id.length === 0)
            return;
        if ((root.publicTagIds.indexOf(id) >= 0) === (isPublic === true))
            return;
        const next = root.publicTagIds.filter(item => item !== id);
        if (isPublic === true)
            next.push(id);
        Persistent.states.grit.publicTagIds = next;
        Persistent.states.grit.publicTagsUpdatedAt = Date.now();
        root.leaderboardSoon();
    }

    /**
     * A newer device owns the name or public-tag list. Adopt only the fields
     * whose timestamp is newer, never both blindly.
     */
    function adoptLeaderboardSettings(displayName, nameUpdatedAt, publicTagIds, tagsUpdatedAt) {
        const nameAt = Number(nameUpdatedAt ?? 0);
        const tagsAt = Number(tagsUpdatedAt ?? 0);
        if (nameAt > Number(Persistent.states.grit.displayNameUpdatedAt ?? 0)) {
            Persistent.states.grit.displayName = String(displayName ?? "").trim().slice(0, 40);
            Persistent.states.grit.displayNameUpdatedAt = nameAt;
        }
        if (tagsAt > Number(Persistent.states.grit.publicTagsUpdatedAt ?? 0)) {
            const activeIds = root.activeTags.map(tag => String(tag.id));
            const next = Array.from(publicTagIds ?? [])
                .map(String)
                .filter(id => activeIds.indexOf(id) >= 0);
            Persistent.states.grit.publicTagIds = next;
            Persistent.states.grit.publicTagsUpdatedAt = tagsAt;
        }
    }

    function leaderboardUrl() {
        return "https://firestore.googleapis.com/v1/projects/"
            + encodeURIComponent(root.firebaseProjectId)
            + "/databases/" + encodeURIComponent(root.firebaseDatabase)
            + "/documents/" + encodeURIComponent(root.leaderboardCollection);
    }

    function leaderboardEntryUrl(uid) {
        return root.leaderboardUrl() + "/" + encodeURIComponent(String(uid ?? ""));
    }

    function firestoreString(fields, name) {
        return String(fields?.[name]?.stringValue ?? "");
    }

    function firestoreInt(fields, name) {
        return Number(fields?.[name]?.integerValue ?? 0) || 0;
    }

    function leaderboardPublicTags() {
        const weekDays = root.thisWeekDays();
        const monthStart = root.todayKey.slice(0, 7) + "-01";
        const wanted = root.publicTagIds;
        return root.activeTags
            .filter(tag => wanted.indexOf(String(tag.id)) >= 0)
            .map(tag => {
                let day = 0;
                let week = 0;
                let month = 0;
                for (const session of root.activeSessions) {
                    if (String(session.phase) !== "focus" || String(session.tagId ?? "") !== String(tag.id))
                        continue;
                    const key = root.dateKey(new Date(Number(session.endedAt ?? 0)));
                    const seconds = Math.max(0, Number(session.durationSec ?? 0));
                    if (key === root.todayKey)
                        day += seconds;
                    if (weekDays.indexOf(key) >= 0)
                        week += seconds;
                    if (key >= monthStart && key <= root.todayKey)
                        month += seconds;
                }
                return {
                    id: String(tag.id),
                    name: String(tag.name ?? ""),
                    accent: String(tag.accent ?? "primary"),
                    color: String(tag.color ?? ""),
                    shape: String(tag.shape ?? "Cookie7Sided"),
                    icon: String(tag.icon ?? "local_fire_department"),
                    updatedAt: Number(tag.updatedAt ?? 0),
                    day: day,
                    week: week,
                    month: month
                };
            });
    }

    function ensureLeaderboardToken(callback) {
        if (!root.signedIn) {
            callback(false);
            return;
        }
        if (Date.now() <= root.authExpiresAt - 90000) {
            callback(true);
            return;
        }
        root.refreshAuthToken(callback);
    }

    function leaderboardTagValue(tag) {
        return {
            mapValue: {
                fields: {
                    name: { stringValue: String(tag.name ?? "") },
                    accent: { stringValue: String(tag.accent ?? "primary") },
                    color: { stringValue: String(tag.color ?? "") },
                    shape: { stringValue: String(tag.shape ?? "Cookie7Sided") },
                    icon: { stringValue: String(tag.icon ?? "local_fire_department") },
                    updatedAt: { integerValue: String(Number(tag.updatedAt ?? 0)) },
                    day: { integerValue: String(Number(tag.day ?? 0)) },
                    week: { integerValue: String(Number(tag.week ?? 0)) },
                    month: { integerValue: String(Number(tag.month ?? 0)) }
                }
            }
        };
    }

    function parseBoardTag(id, fields) {
        return {
            id: String(id),
            name: root.firestoreString(fields, "name") || Translation.tr("Focus"),
            accent: root.firestoreString(fields, "accent") || "primary",
            color: root.firestoreString(fields, "color"),
            shape: root.firestoreString(fields, "shape") || "Cookie7Sided",
            icon: root.firestoreString(fields, "icon") || "local_fire_department",
            updatedAt: root.firestoreInt(fields, "updatedAt"),
            day: root.firestoreInt(fields, "day"),
            week: root.firestoreInt(fields, "week"),
            month: root.firestoreInt(fields, "month")
        };
    }

    function parseBoardDocument(document) {
        if (!document || typeof document !== "object")
            return null;
        const uid = String(document.name ?? "").split("/").pop();
        if (uid.length === 0)
            return null;
        const fields = document.fields ?? {};
        const tagMap = fields.tags?.mapValue?.fields ?? {};
        const tags = Object.keys(tagMap).map(id =>
            root.parseBoardTag(id, tagMap[id]?.mapValue?.fields ?? {}));
        if (tags.length === 0)
            return null;
        return {
            uid: uid,
            updateTime: String(document.updateTime ?? ""),
            displayName: root.firestoreString(fields, "displayName") || Translation.tr("Panadoro user"),
            nameUpdatedAt: root.firestoreInt(fields, "nameUpdatedAt"),
            tags: tags,
            tagsUpdatedAt: root.firestoreInt(fields, "tagsUpdatedAt"),
            dayKey: root.firestoreString(fields, "dayKey"),
            weekKey: root.firestoreString(fields, "weekKey"),
            monthKey: root.firestoreString(fields, "monthKey"),
            updatedAt: root.firestoreInt(fields, "updatedAt")
        };
    }

    function mergeBoardTags(localTags, remote) {
        if (!remote)
            return localTags;
        const localById = {};
        for (const tag of localTags)
            localById[String(tag.id)] = tag;
        const remoteById = {};
        for (const tag of remote.tags)
            remoteById[String(tag.id)] = tag;
        const localAt = Number(Persistent.states.grit.publicTagsUpdatedAt ?? 0);
        let ids;
        if (localAt > remote.tagsUpdatedAt)
            ids = Object.keys(localById);
        else if (localAt < remote.tagsUpdatedAt)
            ids = Object.keys(remoteById);
        else
            ids = Array.from(new Set(Object.keys(localById).concat(Object.keys(remoteById))));
        const sameDay = remote.dayKey === root.todayKey;
        const weekKey = root.thisWeekDays()[0] ?? root.todayKey;
        const sameWeek = remote.weekKey === weekKey;
        const monthKey = root.todayKey.slice(0, 7);
        const sameMonth = remote.monthKey === monthKey;
        const out = [];
        for (const id of ids) {
            const local = localById[id];
            const remoteTag = remoteById[id];
            if (!local && !remoteTag)
                continue;
            const meta = (!local
                || (remoteTag && Number(remoteTag.updatedAt ?? 0) > Number(local.updatedAt ?? 0)))
                ? remoteTag : local;
            out.push(Object.assign({}, meta, {
                id: id,
                day: local
                    ? (sameDay ? Math.max(Number(local.day ?? 0), Number(remoteTag?.day ?? 0))
                        : Number(local.day ?? 0))
                    : (sameDay ? Number(remoteTag?.day ?? 0) : 0),
                week: local
                    ? (sameWeek ? Math.max(Number(local.week ?? 0), Number(remoteTag?.week ?? 0))
                        : Number(local.week ?? 0))
                    : (sameWeek ? Number(remoteTag?.week ?? 0) : 0),
                month: local
                    ? (sameMonth ? Math.max(Number(local.month ?? 0), Number(remoteTag?.month ?? 0))
                        : Number(local.month ?? 0))
                    : (sameMonth ? Number(remoteTag?.month ?? 0) : 0)
            }));
        }
        return out;
    }

    function isBoardConflict(xhr) {
        if (xhr.status === 409 || xhr.status === 412)
            return true;
        if (xhr.status !== 400)
            return false;
        try {
            return String(JSON.parse(xhr.responseText)?.error?.status ?? "") === "FAILED_PRECONDITION";
        } catch (error) {
            return false;
        }
    }

    function leaderboardSoon() {
        if (root.signedIn)
            leaderboardDebounce.restart();
    }

    function publishLeaderboard() {
        if (!root.signedIn)
            return;
        root.ensureLeaderboardToken(ok => {
            if (ok)
                root.tryPublishLeaderboard(0);
        });
    }

    function tryPublishLeaderboard(attempt) {
        if (attempt >= 4) {
            root.leaderboardError = Translation.tr("The leaderboard kept changing on another device. Try again.");
            return;
        }
        const read = new XMLHttpRequest();
        read.open("GET", root.leaderboardEntryUrl(root.authUid)
            + "?key=" + encodeURIComponent(root.firebaseApiKey));
        read.setRequestHeader("Accept", "application/json");
        read.setRequestHeader("Authorization", "Bearer " + root.authIdToken);
        read.timeout = 25000;
        read.onreadystatechange = function () {
            if (read.readyState !== XMLHttpRequest.DONE)
                return;
            let remote = null;
            if (read.status !== 404) {
                if (read.status < 200 || read.status >= 300) {
                    root.leaderboardError = root.firebaseError(read);
                    return;
                }
                try {
                    remote = root.parseBoardDocument(JSON.parse(read.responseText || "{}"));
                } catch (error) {
                    root.leaderboardError = String(error);
                    return;
                }
            }
            if (remote) {
                root.adoptLeaderboardSettings(remote.displayName, remote.nameUpdatedAt,
                    remote.tags.map(tag => String(tag.id)), remote.tagsUpdatedAt);
            }

            const tags = root.leaderboardPublicTags();
            const weekKey = root.thisWeekDays()[0] ?? root.todayKey;
            const monthKey = root.todayKey.slice(0, 7);

            if (tags.length === 0) {
                if (!remote) {
                    root.leaderboardError = "";
                    root.leaderboardUpdatedAt = Date.now();
                    return;
                }
                root.deleteLeaderboardEntry(root.authUid, root.authIdToken, remote.updateTime, result => {
                    if (result === "conflict")
                        root.tryPublishLeaderboard(attempt + 1);
                    else if (result === true) {
                        root.leaderboardError = "";
                        root.leaderboardUpdatedAt = Date.now();
                    }
                });
                return;
            }

            const mergedTags = root.mergeBoardTags(tags, remote);
            const fields = {};
            for (const tag of mergedTags)
                fields[String(tag.id)] = root.leaderboardTagValue(tag);
            const body = {
                fields: {
                    displayName: { stringValue: root.effectiveDisplayName },
                    nameUpdatedAt: { integerValue: String(Math.max(
                        Number(Persistent.states.grit.displayNameUpdatedAt ?? 0),
                        Number(remote?.nameUpdatedAt ?? 0))) },
                    tagsUpdatedAt: { integerValue: String(Math.max(
                        Number(Persistent.states.grit.publicTagsUpdatedAt ?? 0),
                        Number(remote?.tagsUpdatedAt ?? 0))) },
                    dayKey: { stringValue: root.todayKey },
                    weekKey: { stringValue: weekKey },
                    monthKey: { stringValue: monthKey },
                    updatedAt: { integerValue: String(Date.now()) },
                    device: { stringValue: root.deviceId },
                    tags: { mapValue: { fields: fields } }
                }
            };
            let url = root.leaderboardEntryUrl(root.authUid)
                + "?key=" + encodeURIComponent(root.firebaseApiKey)
                + "&updateMask.fieldPaths=displayName"
                + "&updateMask.fieldPaths=nameUpdatedAt"
                + "&updateMask.fieldPaths=tagsUpdatedAt"
                + "&updateMask.fieldPaths=dayKey"
                + "&updateMask.fieldPaths=weekKey"
                + "&updateMask.fieldPaths=monthKey"
                + "&updateMask.fieldPaths=updatedAt"
                + "&updateMask.fieldPaths=device"
                + "&updateMask.fieldPaths=tags";
            url += remote && remote.updateTime.length > 0
                ? "&currentDocument.updateTime=" + encodeURIComponent(remote.updateTime)
                : "&currentDocument.exists=false";

            const write = new XMLHttpRequest();
            write.open("PATCH", url);
            write.setRequestHeader("Content-Type", "application/json");
            write.setRequestHeader("Accept", "application/json");
            write.setRequestHeader("Authorization", "Bearer " + root.authIdToken);
            write.timeout = 30000;
            write.onreadystatechange = function () {
                if (write.readyState !== XMLHttpRequest.DONE)
                    return;
                if (write.status >= 200 && write.status < 300) {
                    root.leaderboardError = "";
                    root.leaderboardUpdatedAt = Date.now();
                    return;
                }
                if (root.isBoardConflict(write))
                    root.tryPublishLeaderboard(attempt + 1);
                else
                    root.leaderboardError = root.firebaseError(write);
            };
            write.ontimeout = function () {
                root.leaderboardError = Translation.tr("Firebase did not answer in time");
            };
            write.onerror = function () {
                root.leaderboardError = Translation.tr("Could not reach Firebase");
            };
            try {
                write.send(JSON.stringify(body));
            } catch (error) {
                root.leaderboardError = String(error);
            }
        };
        read.ontimeout = function () {
            root.leaderboardError = Translation.tr("Firebase did not answer in time");
        };
        read.onerror = function () {
            root.leaderboardError = Translation.tr("Could not reach Firebase");
        };
        try {
            read.send();
        } catch (error) {
            root.leaderboardError = String(error);
        }
    }

    function deleteLeaderboardEntry(uid, token, updateTime, callback) {
        if (String(uid ?? "").length === 0 || String(token ?? "").length === 0) {
            if (callback)
                callback(false);
            return;
        }
        let url = root.leaderboardEntryUrl(uid)
            + "?key=" + encodeURIComponent(root.firebaseApiKey);
        if (String(updateTime ?? "").length > 0)
            url += "&currentDocument.updateTime=" + encodeURIComponent(String(updateTime));
        const xhr = new XMLHttpRequest();
        xhr.open("DELETE", url);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.setRequestHeader("Authorization", "Bearer " + token);
        xhr.timeout = 20000;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status >= 200 && xhr.status < 300 || xhr.status === 404) {
                root.leaderboardEntries = root.leaderboardEntries.filter(
                    item => String(item.uid) !== String(uid));
                if (callback)
                    callback(true);
                return;
            }
            if (root.isBoardConflict(xhr)) {
                if (callback)
                    callback("conflict");
                return;
            }
            root.leaderboardError = root.firebaseError(xhr);
            if (callback)
                callback(false);
        };
        xhr.ontimeout = function () {
            root.leaderboardError = Translation.tr("Firebase did not answer in time");
            if (callback)
                callback(false);
        };
        xhr.onerror = function () {
            root.leaderboardError = Translation.tr("Could not reach Firebase");
            if (callback)
                callback(false);
        };
        try {
            xhr.send();
        } catch (error) {
            if (callback)
                callback(false);
        }
    }

    function parseLeaderboardEntry(document) {
        if (!document || typeof document !== "object")
            return null;
        const uid = String(document.name ?? "").split("/").pop();
        const fields = document.fields ?? {};
        const tagMap = fields.tags?.mapValue?.fields ?? {};
        const tags = Object.keys(tagMap).map(id =>
            root.parseBoardTag(id, tagMap[id]?.mapValue?.fields ?? {}));
        if (tags.length === 0 || uid.length === 0)
            return null;
        return {
            uid: uid,
            displayName: root.firestoreString(fields, "displayName") || Translation.tr("Panadoro user"),
            nameUpdatedAt: root.firestoreInt(fields, "nameUpdatedAt"),
            tagsUpdatedAt: root.firestoreInt(fields, "tagsUpdatedAt"),
            dayKey: root.firestoreString(fields, "dayKey"),
            weekKey: root.firestoreString(fields, "weekKey"),
            monthKey: root.firestoreString(fields, "monthKey"),
            updatedAt: root.firestoreInt(fields, "updatedAt"),
            tags: tags
        };
    }

    function refreshLeaderboard() {
        if (!root.signedIn) {
            root.leaderboardEntries = [];
            root.leaderboardError = Translation.tr("Sign in to join the leaderboard");
            return;
        }
        root.ensureLeaderboardToken(ok => {
            if (!ok) {
                root.leaderboardError = Translation.tr("Could not refresh the leaderboard");
                return;
            }
            root.leaderboardLoading = true;
            const xhr = new XMLHttpRequest();
            xhr.open("GET", root.leaderboardUrl()
                + "?pageSize=300&key=" + encodeURIComponent(root.firebaseApiKey));
            xhr.setRequestHeader("Accept", "application/json");
            xhr.setRequestHeader("Authorization", "Bearer " + root.authIdToken);
            xhr.timeout = 30000;
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return;
                root.leaderboardLoading = false;
                let data = null;
                try {
                    data = JSON.parse(xhr.responseText || "{}");
                } catch (error) {}
                if (xhr.status < 200 || xhr.status >= 300) {
                    root.leaderboardError = root.firebaseError(xhr);
                    return;
                }
                const entries = [];
                for (const document of Array.from(data?.documents ?? [])) {
                    const entry = root.parseLeaderboardEntry(document);
                    if (entry)
                        entries.push(entry);
                }
                const own = entries.find(entry => String(entry.uid) === String(root.authUid));
                if (own) {
                    root.adoptLeaderboardSettings(own.displayName, own.nameUpdatedAt,
                        own.tags.map(tag => String(tag.id)), own.tagsUpdatedAt);
                }
                root.leaderboardEntries = entries;
                root.leaderboardError = "";
                root.leaderboardUpdatedAt = Date.now();
            };
            xhr.ontimeout = function () {
                root.leaderboardLoading = false;
                root.leaderboardError = Translation.tr("Firebase did not answer in time");
            };
            xhr.onerror = function () {
                root.leaderboardLoading = false;
                root.leaderboardError = Translation.tr("Could not reach Firebase");
            };
            try {
                xhr.send();
            } catch (error) {
                root.leaderboardLoading = false;
                root.leaderboardError = String(error);
            }
        });
    }

    Timer {
        id: leaderboardDebounce
        interval: 8000
        onTriggered: root.publishLeaderboard()
    }

    Timer {
        id: leaderboardAutoTimer
        interval: 600000
        repeat: true
        running: root.signedIn
        onTriggered: root.publishLeaderboard()
    }

    function setAutoSync(value) {
        Persistent.states.grit.autoSync = value === true;
        root.afterSyncSetting();
        if (value === true && root.signedIn)
            Qt.callLater(root.syncNow);
    }

    function afterSyncSetting() {
        if (root.autoSync && root.signedIn) {
            syncDebounce.restart();
            syncAutoTimer.restart();
        } else {
            syncAutoTimer.stop();
        }
        if (root.signedIn) {
            root.syncStatus = "idle";
            root.syncMessage = "";
        } else if (!root.syncInProgress) {
            root.syncStatus = "off";
            root.syncMessage = Translation.tr("Sign in to sync");
        }
    }

    Timer {
        id: syncAutoTimer
        interval: 5000
        repeat: true
        running: root.autoSync && root.signedIn
        onTriggered: root.syncNow()
    }

    // Push shortly after an edit, so a change reaches the other device on the
    // next pull instead of waiting for the background check.
    Timer {
        id: syncDebounce
        interval: 500
        onTriggered: {
            if (root.autoSync && root.signedIn && !root.syncInProgress)
                root.syncNow();
        }
    }

    function syncSoon() {
        if (root.autoSync && root.signedIn && !root.syncInProgress)
            syncDebounce.restart();
        if (root.signedIn && root.publicTagIds.length > 0)
            root.leaderboardSoon();
    }

    // Stable content view of a store: key order and the volatile top-level
    // fields must not make two identical stores look different, or every poll
    // would write the document again.
    function syncSignature(store) {
        if (!store || typeof store !== "object")
            return "";
        const copy = Object.assign({}, store);
        delete copy.updatedAt;
        delete copy.device;
        return root.stableStringify(copy);
    }

    function stableStringify(value) {
        if (Array.isArray(value))
            return "[" + value.map(item => root.stableStringify(item)).join(",") + "]";
        if (value && typeof value === "object") {
            const keys = Object.keys(value).sort();
            return "{" + keys.map(key =>
                JSON.stringify(key) + ":" + root.stableStringify(value[key])).join(",") + "}";
        }
        return JSON.stringify(value);
    }

    // ── Firebase Authentication ─────────────────────────────────────────

    function authEndpoint(path) {
        return "https://identitytoolkit.googleapis.com/v1/" + path
            + "?key=" + encodeURIComponent(root.firebaseApiKey);
    }

    function authErrorText(code) {
        switch (String(code)) {
        case "EMAIL_EXISTS": return Translation.tr("An account with this email already exists");
        case "EMAIL_NOT_FOUND":
        case "INVALID_LOGIN_CREDENTIALS":
        case "INVALID_PASSWORD": return Translation.tr("Wrong email or password");
        case "INVALID_EMAIL": return Translation.tr("That email address is not valid");
        case "WEAK_PASSWORD": return Translation.tr("Use at least 6 characters");
        case "MISSING_PASSWORD": return Translation.tr("Enter a password");
        case "TOO_MANY_ATTEMPTS_TRY_LATER": return Translation.tr("Too many attempts. Try again later");
        case "USER_DISABLED": return Translation.tr("This account is disabled");
        case "OPERATION_NOT_ALLOWED": return Translation.tr("Email sign-in is not enabled in Firebase");
        default: return String(code);
        }
    }

    function authRequest(path, body, callback) {
        root.authBusy = true;
        root.authError = "";
        const xhr = new XMLHttpRequest();
        xhr.open("POST", root.authEndpoint(path));
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.timeout = 25000;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            root.authBusy = false;
            let data = null;
            try {
                data = JSON.parse(xhr.responseText || "{}");
            } catch (error) {}
            if (xhr.status < 200 || xhr.status >= 300) {
                root.authError = root.authErrorText(data?.error?.message ?? ("HTTP " + String(xhr.status)));
                callback(null);
                return;
            }
            callback(data ?? {});
        };
        xhr.ontimeout = function () {
            root.authBusy = false;
            root.authError = Translation.tr("Firebase did not answer in time");
            callback(null);
        };
        xhr.onerror = function () {
            root.authBusy = false;
            root.authError = Translation.tr("Could not reach Firebase");
            callback(null);
        };
        try {
            xhr.send(JSON.stringify(body));
        } catch (error) {
            root.authBusy = false;
            root.authError = String(error);
            callback(null);
        }
    }

    function adoptAuth(data, fallbackEmail) {
        Persistent.states.grit.authIdToken = String(data.idToken ?? "");
        Persistent.states.grit.authRefreshToken = String(data.refreshToken ?? "");
        Persistent.states.grit.authUid = String(data.localId ?? "");
        Persistent.states.grit.authExpiresAt = Date.now() + Number(data.expiresIn ?? 3600) * 1000;
        Persistent.states.grit.authEmail = String(data.email ?? fallbackEmail ?? "");
        root.authError = "";
        root.syncStatus = "syncing";
        root.syncMessage = Translation.tr("Signed in");
        Qt.callLater(root.syncNow);
        Qt.callLater(root.publishLeaderboard);
        Qt.callLater(root.refreshLeaderboard);
    }

    function signIn(email, password) {
        const clean = String(email ?? "").trim();
        const pass = String(password ?? "");
        if (clean.length === 0 || pass.length === 0) {
            root.authError = Translation.tr("Enter an email and password");
            return;
        }
        root.authRequest("accounts:signInWithPassword", {
            email: clean,
            password: pass,
            returnSecureToken: true
        }, data => {
            if (data)
                root.adoptAuth(data, clean);
        });
    }

    function createAccount(email, password) {
        const clean = String(email ?? "").trim();
        const pass = String(password ?? "");
        if (clean.length === 0 || pass.length === 0) {
            root.authError = Translation.tr("Enter an email and password");
            return;
        }
        root.authRequest("accounts:signUp", {
            email: clean,
            password: pass,
            returnSecureToken: true
        }, data => {
            if (data)
                root.adoptAuth(data, clean);
        });
    }

    function signOut() {
        // Take the public row down while the old token is still valid.
        root.deleteLeaderboardEntry(root.authUid, root.authIdToken);
        Persistent.states.grit.authIdToken = "";
        Persistent.states.grit.authRefreshToken = "";
        Persistent.states.grit.authUid = "";
        Persistent.states.grit.authExpiresAt = 0;
        Persistent.states.grit.authEmail = "";
        root.authError = "";
        root.authBusy = false;
        root.syncInProgress = false;
        syncWatchdog.stop();
        root.syncStatus = "off";
        root.syncMessage = Translation.tr("Sign in to sync");
        root.leaderboardEntries = [];
        root.leaderboardError = "";
        root.leaderboardLoading = false;
    }

    function refreshAuthToken(callback) {
        const refresh = root.authRefreshToken;
        if (refresh.length === 0) {
            callback(false);
            return;
        }
        const xhr = new XMLHttpRequest();
        xhr.open("POST", "https://securetoken.googleapis.com/v1/token?key="
            + encodeURIComponent(root.firebaseApiKey));
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        xhr.timeout = 25000;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            let data = null;
            try {
                data = JSON.parse(xhr.responseText || "{}");
            } catch (error) {}
            if (xhr.status < 200 || xhr.status >= 300) {
                const reason = String(data?.error?.message ?? "");
                const ended = reason.indexOf("INVALID_REFRESH_TOKEN") >= 0
                    || reason.indexOf("TOKEN_EXPIRED") >= 0
                    || reason.indexOf("INVALID_GRANT") >= 0
                    || reason.indexOf("USER_DISABLED") >= 0
                    || reason.indexOf("USER_NOT_FOUND") >= 0;
                if (ended) {
                    root.signOut();
                    root.authError = Translation.tr("Session expired. Sign in again.");
                }
                callback(false);
                return;
            }
            Persistent.states.grit.authIdToken = String(data.id_token ?? "");
            Persistent.states.grit.authRefreshToken = String(data.refresh_token ?? refresh);
            Persistent.states.grit.authExpiresAt = Date.now() + Number(data.expires_in ?? 3600) * 1000;
            if (String(data.user_id ?? "").length > 0)
                Persistent.states.grit.authUid = String(data.user_id);
            callback(true);
        };
        xhr.ontimeout = function () {
            callback(false);
        };
        xhr.onerror = function () {
            callback(false);
        };
        try {
            xhr.send("grant_type=refresh_token&refresh_token=" + encodeURIComponent(refresh));
        } catch (error) {
            callback(false);
        }
    }

    function firestoreDocumentUrl() {
        return "https://firestore.googleapis.com/v1/projects/" + encodeURIComponent(root.firebaseProjectId)
            + "/databases/" + encodeURIComponent(root.firebaseDatabase)
            + "/documents/" + encodeURIComponent(root.firebaseCollection)
            + "/" + encodeURIComponent(root.authUid);
    }

    function syncNow() {
        if (!root.signedIn) {
            root.syncStatus = "off";
            root.syncMessage = Translation.tr("Sign in to sync");
            return;
        }
        if (root.syncInProgress)
            return;
        root.syncInProgress = true;
        root.syncStatus = "syncing";
        root.syncMessage = Translation.tr("Contacting Firebase…");
        root._postAttempt = 0;
        syncWatchdog.restart();
        if (Date.now() > root.authExpiresAt - 90000) {
            root.refreshAuthToken(ok => {
                if (!ok) {
                    // A dropped network must not end a saved session; the
                    // refresh token is still good when the connection returns.
                    root.syncFailed(Translation.tr("Offline — your session is still signed in"));
                    return;
                }
                root.firestorePull();
            });
            return;
        }
        root.firestorePull();
    }

    // A request that hangs without ever reaching DONE (a dropped connection,
    // for example) would otherwise leave syncInProgress stuck and block every
    // later sync until the shell restarts.
    Timer {
        id: syncWatchdog
        interval: 75000
        onTriggered: {
            if (root.syncInProgress)
                root.syncFailed(Translation.tr("Sync did not finish in time"));
        }
    }

    function firestorePull() {
        try {
            const xhr = new XMLHttpRequest();
            xhr.open("GET", root.firestoreDocumentUrl() + "?key=" + encodeURIComponent(root.firebaseApiKey));
            xhr.setRequestHeader("Accept", "application/json");
            xhr.setRequestHeader("Authorization", "Bearer " + root.authIdToken);
            xhr.timeout = 20000;
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return;
                if (xhr.status === 404) {
                    root.firestorePush("", 0);
                    return;
                }
                if (xhr.status < 200 || xhr.status >= 300) {
                    root.syncFailed(root.firebaseError(xhr));
                    return;
                }
                let document = null;
                try {
                    document = JSON.parse(xhr.responseText || "{}");
                } catch (error) {
                    root.syncFailed(Translation.tr("Firebase returned something that is not JSON"));
                    return;
                }
                const remoteRevision = Number(document?.fields?.revision?.integerValue ?? 0);
                const updateTime = String(document?.updateTime ?? "");
                let remotePayload = null;
                try {
                    const raw = document?.fields?.payload?.stringValue;
                    if (raw)
                        remotePayload = JSON.parse(raw);
                } catch (error) {}
                try {
                    const hasRemote = remotePayload && typeof remotePayload === "object";
                    const remoteSignature = hasRemote ? root.syncSignature(remotePayload) : "";
                    if (hasRemote)
                        root.applyRemoteStore(remotePayload);
                    if (hasRemote && remoteSignature === root.syncSignature(root.snapshot())) {
                        root.syncFinished(remoteRevision);
                        return;
                    }
                    root.firestorePush(updateTime, remoteRevision);
                } catch (error) {
                    root.syncFailed(String(error));
                }
            };
            xhr.ontimeout = function () {
                root.syncFailed(Translation.tr("Firebase did not answer in time"));
            };
            xhr.onerror = function () {
                root.syncFailed(Translation.tr("Could not reach Firebase"));
            };
            xhr.send();
        } catch (error) {
            root.syncFailed(String(error));
        }
    }

    function firestorePush(updateTime, baseRevision) {
        try {
            const payload = root.snapshot();
            const revision = Number(baseRevision ?? 0) + 1;
            const body = {
                fields: {
                    payload: { stringValue: JSON.stringify(payload) },
                    revision: { integerValue: String(revision) },
                    updatedAt: { integerValue: String(Date.now()) }
                }
            };
            let url = root.firestoreDocumentUrl()
                + "?key=" + encodeURIComponent(root.firebaseApiKey)
                + "&updateMask.fieldPaths=payload"
                + "&updateMask.fieldPaths=revision"
                + "&updateMask.fieldPaths=updatedAt";
            url += updateTime.length > 0
                ? "&currentDocument.updateTime=" + encodeURIComponent(updateTime)
                : "&currentDocument.exists=false";
            const xhr = new XMLHttpRequest();
            xhr.open("PATCH", url);
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.setRequestHeader("Accept", "application/json");
            xhr.setRequestHeader("Authorization", "Bearer " + root.authIdToken);
            xhr.timeout = 30000;
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return;
                if (root.firestoreConflict(xhr) && root._postAttempt < 2) {
                    root._postAttempt++;
                    Qt.callLater(() => {
                        try {
                            root.firestorePull();
                        } catch (error) {
                            root.syncFailed(String(error));
                        }
                    });
                    return;
                }
                if (xhr.status < 200 || xhr.status >= 300) {
                    root.syncFailed(root.firebaseError(xhr));
                    return;
                }
                let result = null;
                try {
                    result = JSON.parse(xhr.responseText || "{}");
                } catch (error) {}
                root.syncFinished(Number(result?.fields?.revision?.integerValue ?? revision));
            };
            xhr.ontimeout = function () {
                root.syncFailed(Translation.tr("Firebase did not answer in time"));
            };
            xhr.onerror = function () {
                root.syncFailed(Translation.tr("Could not reach Firebase"));
            };
            xhr.send(JSON.stringify(body));
        } catch (error) {
            root.syncFailed(String(error));
        }
    }

    function firestoreConflict(xhr) {
        if (xhr.status === 409 || xhr.status === 412)
            return true;
        if (xhr.status !== 400)
            return false;
        try {
            return String(JSON.parse(xhr.responseText)?.error?.status ?? "") === "FAILED_PRECONDITION";
        } catch (error) {
            return false;
        }
    }

    function firebaseError(xhr) {
        let message = "";
        try {
            message = String(JSON.parse(xhr.responseText)?.error?.message ?? "");
        } catch (error) {}
        if (xhr.status === 401 || xhr.status === 403)
            return Translation.tr("Firebase rejected the request%1").arg(message.length > 0 ? ": " + message : "");
        return Translation.tr("Firebase sync failed (HTTP %1)%2")
            .arg(String(xhr.status))
            .arg(message.length > 0 ? ": " + message : "");
    }

    function syncFinished(revision) {
        syncWatchdog.stop();
        root.syncInProgress = false;
        root.syncStatus = "synced";
        root.syncMessage = Translation.tr("Synced %1").arg(Qt.formatTime(new Date(), "HH:mm"));
        root.revision = Number(revision ?? root.revision);
        Persistent.states.grit.lastSyncAt = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm:ss");
    }

    function syncFailed(message) {
        syncWatchdog.stop();
        root.syncInProgress = false;
        root.syncStatus = "error";
        root.syncMessage = String(message ?? Translation.tr("Sync failed"));
    }

    function mergeRecordLists(local, remote) {
        const map = {};
        for (const item of Array.from(local ?? [])) {
            if (item && item.id)
                map[String(item.id)] = item;
        }
        for (const item of Array.from(remote ?? [])) {
            if (!item || !item.id)
                continue;
            const id = String(item.id);
            const current = map[id];
            if (!current) {
                map[id] = item;
                continue;
            }
            const currentTime = Number(current.updatedAt ?? 0);
            const remoteTime = Number(item.updatedAt ?? 0);
            if (remoteTime > currentTime
                || (remoteTime === currentTime && item.deleted === true && current.deleted !== true))
                map[id] = item;
        }
        return Object.keys(map).map(id => map[id]);
    }

    function mergeStores(local, remote) {
        const a = local ?? {};
        const b = remote ?? {};
        const merged = {
            version: root.dataVersion,
            habits: root.mergeRecordLists(a.habits, b.habits),
            entries: root.mergeRecordLists(a.entries, b.entries),
            tasks: root.mergeRecordLists(a.tasks, b.tasks),
            categories: root.mergeRecordLists(a.categories, b.categories),
            tags: root.mergeRecordLists(a.tags, b.tags),
            focusSessions: root.sortSessions(root.mergeRecordLists(a.focusSessions, b.focusSessions)),
            timer: a.timer,
            leaderboard: root.mergeLeaderboardPrefs(a.leaderboard, b.leaderboard),
            updatedAt: Date.now(),
            device: root.deviceId
        };
        if (b.timer && typeof b.timer === "object") {
            if (!a.timer || Number(b.timer.updatedAt ?? 0) > Number(a.timer.updatedAt ?? 0))
                merged.timer = b.timer;
        }
        return merged;
    }

    function applyRemoteStore(payload) {
        if (!payload || typeof payload !== "object")
            return;
        root.syncApplying = true;
        const merged = root.mergeStores(root.snapshot(), payload);
        root.habits = root.normalizeList(merged.habits);
        root.entries = root.normalizeList(merged.entries);
        root.tasks = root.normalizeList(merged.tasks);
        root.categories = root.normalizeList(merged.categories);
        root.tags = root.normalizeList(merged.tags);
        root.focusSessions = root.sortSessions(root.normalizeList(merged.focusSessions));
        if (merged.timer && typeof merged.timer === "object")
            root.timer = merged.timer;
        if (merged.leaderboard)
            root.applyLeaderboardPrefs(merged.leaderboard);
        root.ensureTimer();
        root.revision++;
        root.syncApplying = false;
        root.saveSoon();
    }

    // ── Backup / restore ────────────────────────────────────────────────

    function exportBackup(fileUrl) {
        const payload = JSON.stringify(root.snapshot(), null, 2);
        backupFile.path = fileUrl;
        Qt.callLater(() => {
            try {
                backupFile.setText(payload);
            } catch (error) {
                console.warn("[Grit] Could not save backup:", error);
            }
        });
    }

    function importBackup(fileUrl) {
        importFile.path = fileUrl;
        importFile.reload();
    }

    function restoreFromBackup(raw) {
        if (!raw || typeof raw !== "object")
            return;
        const parsed = root.normalizeStore(raw);
        const now = Date.now();
        const dev = root.deviceId;
        const restore = (imported, current) => {
            const ids = {};
            const stamped = Array.from(imported ?? []).map(item => {
                const copy = Object.assign({}, item, { updatedAt: now, device: dev });
                ids[String(copy.id ?? "")] = true;
                return copy;
            });
            const tombstones = Array.from(current ?? [])
                .filter(item => !ids[String(item.id ?? "")])
                .map(item => Object.assign({}, item, { deleted: true, updatedAt: now, device: dev }));
            return stamped.concat(tombstones);
        };
        root.habits = restore(parsed.habits, root.habits);
        root.entries = restore(parsed.entries, root.entries);
        root.tasks = restore(parsed.tasks, root.tasks);
        root.categories = restore(parsed.categories, root.categories);
        root.tags = restore(parsed.tags, root.tags);
        root.focusSessions = root.sortSessions(restore(parsed.focusSessions, root.focusSessions));
        root.timer = parsed.timer && typeof parsed.timer === "object"
            ? parsed.timer : root.makeTimer(parsed.tags.find(tag => !tag.deleted)?.id ?? "", "focus", 0, false);
        if (raw.leaderboard && typeof raw.leaderboard === "object") {
            Persistent.states.grit.displayName = String(raw.leaderboard.displayName ?? "").trim().slice(0, 40);
            Persistent.states.grit.displayNameUpdatedAt = now;
            Persistent.states.grit.publicTagIds = Array.from(raw.leaderboard.publicTagIds ?? []).map(String);
            Persistent.states.grit.publicTagsUpdatedAt = now;
        }
        root.revision++;
        root.ensureTimer();
        root.saveNow();
        root.syncSoon();
        root.syncNow();
    }

    // ── Reset ───────────────────────────────────────────────────────────
    function resetAllData() {
        const tombstone = item => root.stamp(Object.assign({}, item, { deleted: true }));
        root.habits = root.habits.map(tombstone);
        root.entries = root.entries.map(tombstone);
        root.tasks = root.tasks.map(tombstone);
        root.focusSessions = root.focusSessions.map(tombstone);
        root.tags = root.tags.map(tombstone).concat(root.defaultTags().map(tag => root.stamp(tag)));
        root.categories = root.categories.map(tombstone).concat(root.defaultCategories().map(cat => root.stamp(cat)));
        root.timer = root.makeTimer(root.activeTags[0]?.id ?? "", "focus", 0, false);
        root.revision++;
        root.saveNow();
        root.syncSoon();
        root.dataReset();
        root.syncNow();
    }

    // ── IPC ─────────────────────────────────────────────────────────────
    IpcHandler {
        target: "grit"

        function open(tab: string): void {
            GlobalStates.openGritApp(tab);
        }

        function startFocus(tag: string): void {
            GlobalStates.openGritApp("focus");
            root.startFocusNow(String(tag ?? ""));
        }

        function stopTimer(): void {
            if (root.timerRunning)
                root.pauseTimer();
        }

        function toggleTimer(): void {
            root.toggleTimer();
        }

        function addHabit(name: string): string {
            return root.createHabit({ name: name });
        }

        function addTask(title: string): string {
            return root.createTask({ title: title, due: root.todayKey });
        }

        function sync(): string {
            root.syncNow();
            return "started";
        }

        function status(): string {
            return [
                "habits=" + root.activeHabits.length,
                "tasks=" + root.openTaskCount,
                "focusToday=" + root.todayFocusMinutes,
                "streak=" + root.focusStreak(),
                "timer=" + root.timerPhase + ":" + root.timerSecondsLeft,
                "sync=" + root.syncStatus
            ].join(" ");
        }
    }
}
