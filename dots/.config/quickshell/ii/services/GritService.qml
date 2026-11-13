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
        if (root.hostLocal)
            Qt.callLater(root.startLocalHost);
        if (root.autoSync && root.syncConfigured)
            Qt.callLater(root.syncNow);
    }

    Component.onDestruction: {
        root._blockWrites = true;
        if (saveTimer.running)
            root.saveNow();
        if (hostProcess.running)
            hostProcess.running = false;
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
            Quickshell.execDetached(["notify-send", title, body, "-a", "Grit",
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

    // ── Sync settings ───────────────────────────────────────────────────
    readonly property string syncUrl: String(Persistent.states.grit?.syncUrl ?? "")
    readonly property string syncToken: String(Persistent.states.grit?.syncToken ?? "")
    readonly property bool autoSync: Persistent.states.grit?.autoSync === true
    readonly property int syncIntervalSec: Math.max(15, Number(Persistent.states.grit?.syncIntervalSec ?? 120))
    readonly property int syncPort: Math.max(1024, Math.min(65535, Number(Persistent.states.grit?.syncPort ?? 8765)))
    readonly property bool hostLocal: Persistent.states.grit?.hostLocal === true
    readonly property bool syncConfigured: root.syncUrl.length > 0 && root.syncToken.length > 0
    property bool syncApplying: false
    property bool syncInProgress: false
    property int _postAttempt: 0
    property string syncStatus: root.syncConfigured ? "idle" : "off"
    property string syncMessage: root.syncConfigured ? "" : Translation.tr("Add a sync URL and key to sync between devices")
    property string hostStatus: ""
    property bool hostRunning: false

    function setSyncUrl(value) {
        Persistent.states.grit.syncUrl = String(value ?? "").trim();
        root.afterSyncSetting();
    }

    function setSyncToken(value) {
        Persistent.states.grit.syncToken = String(value ?? "").trim();
        root.afterSyncSetting();
    }

    function setAutoSync(value) {
        Persistent.states.grit.autoSync = value === true;
        root.afterSyncSetting();
        if (value === true && root.syncConfigured)
            Qt.callLater(root.syncNow);
    }

    function setSyncInterval(value) {
        Persistent.states.grit.syncIntervalSec = Math.max(15, Number(value ?? 120));
    }

    function setSyncPort(value) {
        Persistent.states.grit.syncPort = Math.max(1024, Math.min(65535, Number(value ?? 8765)));
        if (root.hostRunning) {
            root.stopLocalHost();
            Qt.callLater(root.startLocalHost);
        }
    }

    function generateToken() {
        return Qt.md5(String(Date.now()) + ":" + String(Math.random()) + ":grit").slice(0, 32);
    }

    function ensureToken() {
        if (String(Persistent.states.grit.syncToken ?? "").length === 0)
            Persistent.states.grit.syncToken = root.generateToken();
        return String(Persistent.states.grit.syncToken);
    }

    function afterSyncSetting() {
        if (root.autoSync && root.syncConfigured) {
            syncDebounce.restart();
            syncAutoTimer.restart();
        } else {
            syncAutoTimer.stop();
        }
        root.syncStatus = root.syncConfigured ? "idle" : "off";
        root.syncMessage = root.syncConfigured ? "" : Translation.tr("Add a sync URL and key to sync between devices");
    }

    Timer {
        id: syncAutoTimer
        interval: root.syncIntervalSec * 1000
        repeat: true
        running: root.autoSync && root.syncConfigured
        onTriggered: root.syncNow()
    }

    Timer {
        id: syncDebounce
        interval: 5000
        onTriggered: {
            if (root.autoSync && root.syncConfigured && !root.syncInProgress)
                root.syncNow();
        }
    }

    function syncSoon() {
        if (root.autoSync && root.syncConfigured && !root.syncInProgress)
            syncDebounce.restart();
    }

    function syncNow() {
        if (!root.syncConfigured) {
            root.syncStatus = "off";
            root.syncMessage = Translation.tr("Add a sync URL and key first");
            return;
        }
        if (root.syncInProgress)
            return;
        root.syncInProgress = true;
        root.syncStatus = "syncing";
        root.syncMessage = Translation.tr("Contacting the server…");
        root._postAttempt = 0;
        const xhr = new XMLHttpRequest();
        xhr.open("GET", root.syncUrl);
        xhr.setRequestHeader("Authorization", "Bearer " + root.syncToken);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.timeout = 20000;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status < 200 || xhr.status >= 300) {
                root.syncFailed(root.httpError(xhr));
                return;
            }
            let remote = null;
            try {
                remote = JSON.parse(xhr.responseText || "{}");
            } catch (error) {
                root.syncFailed(Translation.tr("The server returned something that is not JSON"));
                return;
            }
            const baseRevision = Number(remote?.revision ?? 0);
            if (remote?.payload && typeof remote.payload === "object")
                root.applyRemoteStore(remote.payload);
            root.pushSync(baseRevision);
        };
        xhr.ontimeout = function () {
            root.syncFailed(Translation.tr("The server did not answer in time"));
        };
        xhr.onerror = function () {
            root.syncFailed(Translation.tr("Could not reach the sync server"));
        };
        try {
            xhr.send();
        } catch (error) {
            root.syncFailed(String(error));
        }
    }

    function httpError(xhr) {
        if (xhr.status === 401 || xhr.status === 403)
            return Translation.tr("The sync key was rejected");
        if (xhr.status === 404)
            return Translation.tr("The sync endpoint was not found");
        return Translation.tr("Sync failed (HTTP %1)").arg(String(xhr.status));
    }

    function pushSync(baseRevision) {
        const payload = root.snapshot();
        const xhr = new XMLHttpRequest();
        xhr.open("POST", root.syncUrl);
        xhr.setRequestHeader("Authorization", "Bearer " + root.syncToken);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.setRequestHeader("Accept", "application/json");
        xhr.timeout = 20000;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status === 409 && root._postAttempt < 2) {
                root._postAttempt++;
                let current = null;
                try {
                    current = JSON.parse(xhr.responseText || "{}");
                } catch (error) {}
                if (current?.payload)
                    root.applyRemoteStore(current.payload);
                Qt.callLater(() => root.pushSync(Number(current?.revision ?? baseRevision + 1)));
                return;
            }
            if (xhr.status < 200 || xhr.status >= 300) {
                root.syncFailed(root.httpError(xhr));
                return;
            }
            let result = null;
            try {
                result = JSON.parse(xhr.responseText || "{}");
            } catch (error) {}
            root.syncInProgress = false;
            root.syncStatus = "synced";
            root.syncMessage = Translation.tr("Synced %1").arg(Qt.formatTime(new Date(), "HH:mm"));
            root.revision = Number(result?.revision ?? baseRevision + 1);
            Persistent.states.grit.lastSyncAt = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm:ss");
            root.saveSoon();
        };
        xhr.ontimeout = function () {
            root.syncFailed(Translation.tr("The server did not answer in time"));
        };
        xhr.onerror = function () {
            root.syncFailed(Translation.tr("Could not reach the sync server"));
        };
        try {
            xhr.send(JSON.stringify({
                baseRevision: Number(baseRevision ?? 0),
                payload: payload
            }));
        } catch (error) {
            root.syncFailed(String(error));
        }
    }

    function syncFailed(message) {
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
        root.ensureTimer();
        root.revision++;
        root.syncApplying = false;
        root.saveSoon();
    }

    // ── Local sync host ─────────────────────────────────────────────────
    Process {
        id: hostProcess
        running: false
        command: ["python3", Directories.gritSyncServerPath,
            "--port", String(root.syncPort),
            "--token", root.syncToken,
            "--data", Directories.gritSyncDataPath]
        onStarted: {
            root.hostRunning = true;
            root.hostStatus = Translation.tr("Serving on port %1").arg(String(root.syncPort));
        }
        onExited: (code, status) => {
            root.hostRunning = false;
            if (root.hostLocal) {
                root.hostStatus = Translation.tr("The local server stopped (code %1)").arg(String(code));
                Persistent.states.grit.hostLocal = false;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const text = String(this.text ?? "").trim();
                if (text.length > 0)
                    root.hostStatus = text.split("\n").slice(-2).join(" · ");
            }
        }
    }

    function startLocalHost() {
        if (hostProcess.running)
            return;
        const token = root.ensureToken();
        Persistent.states.grit.hostLocal = true;
        root.hostStatus = Translation.tr("Starting the local server…");
        hostProcess.command = ["python3", Directories.gritSyncServerPath,
            "--port", String(root.syncPort), "--token", token, "--data", Directories.gritSyncDataPath];
        hostProcess.running = true;
        if (root.syncUrl.length === 0)
            root.setSyncUrl("http://127.0.0.1:" + String(root.syncPort) + "/grit");
    }

    function stopLocalHost() {
        Persistent.states.grit.hostLocal = false;
        root.hostStatus = Translation.tr("Local server stopped");
        hostProcess.running = false;
    }

    function toggleLocalHost() {
        if (root.hostRunning)
            root.stopLocalHost();
        else
            root.startLocalHost();
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
