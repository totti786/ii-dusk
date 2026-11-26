pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * A nice wrapper for date and time strings.
 */
Singleton {
    property var clock: SystemClock {
        id: clock
        precision: {
            if (Config.options.time.secondPrecision || GlobalStates.screenLocked)
                return SystemClock.Seconds;
            return SystemClock.Minutes;
        }
    }
    property string time: Translation.formatDate(clock.date, Config.options?.time.format ?? "hh:mm")
    property string seconds: Translation.formatDate(clock.date, Config.options?.time.secondsFormat ?? "ss")
    property string shortDate: Translation.formatDate(clock.date, Config.options?.time.shortDateFormat ?? "dd/MM")
    property string dayNameShort: Translation.formatDate(clock.date, "ddd")
    property string date: Translation.formatDate(clock.date, Config.options?.time.dateWithYearFormat ?? "dd/MM/yyyy")
    property string longDate: Translation.formatDate(clock.date, Config.options?.time.dateFormat ?? "dddd, dd/MM")
    /// The same date without the weekday: the day-name tokens go, and so do the
    /// separators they leave dangling ("MM/dd, ddd" -> "MM/dd", "dddd, dd/MM" -> "dd/MM").
    property string longDateNoDayName: {
        const format = (Config.options?.time.dateFormat ?? "dddd, dd/MM")
            .replace(/d{3,4}/g, "")
            .replace(/^[\s,.\-\/]+|[\s,.\-\/]+$/g, "")
            .replace(/([,.])\s*[,.]/g, "$1");
        return Translation.formatDate(clock.date, format.length > 0 ? format : "dd/MM");
    }
    property string collapsedCalendarFormat: Translation.formatDate(clock.date, "dddd, MMMM dd")

    // ── Date parts ────────────────────────────────────────────────────────────
    // The bar's date widget renders each part of the date with its own
    // typography, so it needs the parts separately rather than one formatted
    // string. Everything here derives from `clock.date`, so it re-evaluates on
    // the same tick as the rest of the service.
    property string dayOfMonth: Qt.locale().toString(clock.date, "d")
    property string dayOfMonthPadded: Qt.locale().toString(clock.date, "dd")
    property string monthNumberPadded: Qt.locale().toString(clock.date, "MM")
    property string monthNameShort: Translation.formatDate(clock.date, "MMM")
    property string monthNameLong: Translation.formatDate(clock.date, "MMMM")
    property string dayNameLong: Translation.formatDate(clock.date, "dddd")
    property string yearShort: Qt.locale().toString(clock.date, "yy")
    property string yearLong: Qt.locale().toString(clock.date, "yyyy")

    // Neighbouring weekdays for strip-style widgets. Built from the calendar
    // fields instead of ±86400000ms so a DST transition cannot land the result
    // back on today.
    property string dayNameShortPrev: Translation.formatDate(new Date(clock.date.getFullYear(), clock.date.getMonth(), clock.date.getDate() - 1), "ddd")
    property string dayNameShortNext: Translation.formatDate(new Date(clock.date.getFullYear(), clock.date.getMonth(), clock.date.getDate() + 1), "ddd")

    // ── Clock parts ───────────────────────────────────────────────────────────
    // Same reasoning as the date parts: the bar's clock draws hours and minutes
    // with different type, so it needs them apart rather than pre-joined.
    readonly property bool use12HourClock: /a/i.test(Config.options?.time.format ?? "hh:mm")
    property string hours: use12HourClock
        ? ("0" + (clock.date.getHours() % 12 || 12)).slice(-2)
        : Qt.locale().toString(clock.date, "HH")
    property string minutes: Qt.locale().toString(clock.date, "mm")
    property string meridiem: use12HourClock
        ? Translation.formatDate(clock.date, (Config.options?.time.format ?? "").includes("AP") ? "AP" : "ap").trim()
        : ""

    // Fractions for dials and arcs. `clock.precision` is Minutes unless the
    // user asked for seconds, so these step once a minute rather than sweeping
    // — which is what a bar widget wants anyway.
    readonly property real minuteProgress: (clock.date.getMinutes() + clock.date.getSeconds() / 60) / 60
    readonly property real hourProgress: ((clock.date.getHours() % 12) + clock.date.getMinutes() / 60) / 12

    readonly property int dayNumber: clock.date.getDate()
    readonly property int daysInMonth: new Date(clock.date.getFullYear(), clock.date.getMonth() + 1, 0).getDate()
    readonly property real monthProgress: daysInMonth > 0 ? dayNumber / daysInMonth : 0
    property string uptime: "0h, 0m"

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: {
            fileUptime.reload();
            const textUptime = fileUptime.text();
            const uptimeSeconds = Number(textUptime.split(" ")[0] ?? 0);

            // Convert seconds to days, hours, and minutes
            const days = Math.floor(uptimeSeconds / 86400);
            const hours = Math.floor((uptimeSeconds % 86400) / 3600);
            const minutes = Math.floor((uptimeSeconds % 3600) / 60);

            // Build the formatted uptime string
            let formatted = "";
            if (days > 0)
                formatted += Translation.tr("%1d").arg(days);
            if (hours > 0)
                formatted += (formatted ? ", " : "") + Translation.tr("%1h").arg(hours);
            if (minutes > 0 || !formatted)
                formatted += (formatted ? ", " : "") + Translation.tr("%1m").arg(minutes);
            uptime = formatted;
            interval = Config.options?.resources?.updateInterval ?? 3000;
        }
    }

    FileView {
        id: fileUptime

        path: "/proc/uptime"
    }
}
