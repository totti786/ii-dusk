pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common

/// The verse of the day for the Diwan desktop widget: today's poem from the same
/// daily pick the reader's home page shows (scripts/diwan/diwan.py daily, cached per
/// date there, so asking again is free). It is read when the first widget asks and
/// again when the date changes, so the verse rolls over at midnight.
Singleton {
    id: root

    /// { slug, title, poet, era, meter, verse: [sadr, ajuz], count } or null until read
    property var daily: null
    property string error: ""
    property int users: 0
    readonly property string today: Qt.formatDate(DateTime.clock.date, "yyyy-MM-dd")
    property string loadedFor: ""

    readonly property string script: `${Directories.scriptPath}/diwan/diwan.py`

    function requestData(): void {
        root.users += 1;
        root.refresh();
    }

    function releaseData(): void {
        root.users = Math.max(0, root.users - 1);
    }

    function refresh(): void {
        if (root.users === 0 || proc.running || root.loadedFor === root.today)
            return;
        proc.running = true;
    }

    onTodayChanged: root.refresh()

    // A failed read is tried again in a while
    Timer {
        interval: 5 * 60 * 1000
        running: root.users > 0 && root.error !== ""
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: proc
        command: ["python3", "-I", root.script, "daily"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try {
                    d = JSON.parse(text);
                } catch (e) {
                    d = null;
                }
                if (d?.ok && d.daily?.verse?.length >= 1) {
                    root.daily = d.daily;
                    root.error = "";
                    root.loadedFor = root.today;
                } else {
                    root.error = d?.error ?? "تعذّر تحميل بيت اليوم";
                }
            }
        }
    }
}
