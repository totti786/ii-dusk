pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/// Every windowed app the shell ships, straight from the action registry, so a new app shows up
/// here the day it is registered (under "More" until it is given a group). Grouped, searchable,
/// each tile says what the app does and which key opens it. A tile closes the cheatsheet and
/// opens the app.
Item {
    id: root

    readonly property var apps: ShellActionRegistry.actions.filter(a => a.app && a.enabled())

    readonly property var blurbs: ({
        notes: Translation.tr("Quick notes and sticky pads you can pin on screen"),
        clock: Translation.tr("Alarms, timers, stopwatch, pomodoro and world clocks"),
        grit: Translation.tr("Habit tracker and tasks with streaks and a focus timer"),
        weather: Translation.tr("Forecast, rain, wind, air quality and pollen"),
        calculator: Translation.tr("Standard and scientific calculator with history"),
        editor: Translation.tr("Plain text and code editor with syntax highlighting"),
        mediator: Translation.tr("Your shows, anime and movies, with resume and episode info"),
        music: Translation.tr("YouTube Music player with queue, lyrics and artist pages"),
        audioPlayer: Translation.tr("Play local audio files from your library folders"),
        youtube: Translation.tr("Search and watch YouTube videos"),
        syncplay: Translation.tr("Watch together in sync with friends"),
        imageViewer: Translation.tr("Open and browse images"),
        camera: Translation.tr("Webcam preview and photos"),
        mixer: Translation.tr("Volume per app, plus outputs and inputs"),
        easyEffects: Translation.tr("Equalizer and audio effects for speakers and mic"),
        patchbay: Translation.tr("Route audio between apps and devices on the PipeWire graph"),
        audioRecorder: Translation.tr("Record audio from a microphone or any app"),
        soundscapes: Translation.tr("Mix rain, fire, ocean and other ambient sounds, with a sleep timer"),
        qanun: Translation.tr("Qanun tuner, maqam scales, metronome and ear training"),
        books: Translation.tr("Your library of books and PDFs, with browsing of online sources"),
        quran: Translation.tr("Mushaf reader with recitation"),
        diwan: Translation.tr("Arabic poetry, from the pre-Islamic era to today"),
        anki: Translation.tr("Review your flashcards, sync with AnkiWeb and add notes"),
        wikipedia: Translation.tr("Read Wikipedia articles without a browser"),
        fileManager: Translation.tr("Browse, copy, move and preview files"),
        downloads: Translation.tr("Download videos, music and any file from a link"),
        torrents: Translation.tr("qBittorrent front end, with search across sites"),
        quickshare: Translation.tr("Send files to nearby Android phones"),
        bluetoothManager: Translation.tr("Pair and manage Bluetooth devices"),
        discordoVoice: Translation.tr("Discord voice calls with camera and screen video"),
        monitor: Translation.tr("CPU, memory, network, processes and ping latency"),
        health: Translation.tr("Disks, temperatures, failed services, crashes and the journal"),
        usage: Translation.tr("Screen time, app limits and battery usage"),
        modes: Translation.tr("Modes and routines that change several settings at once"),
        packages: Translation.tr("Installed packages, updates and the AUR")
    })

    /// What opens each app from the keyboard. Apps with none are opened from here or search.
    readonly property var chords: ({
        notes: "Super + Alt + N", clock: "Super + Alt + T", grit: "Super + Alt + G",
        calculator: "Super + Ctrl + X", mediator: "Super + Ctrl + M", music: "Super + Ctrl + A",
        mixer: "Ctrl + Alt + V", easyEffects: "Super + Alt + E", patchbay: "Ctrl + Alt + G",
        soundscapes: "Super + Ctrl + S", books: "Super + Ctrl + Shift + B", quran: "Super + Ctrl + W",
        diwan: "Super + Ctrl + Y", anki: "Super + Ctrl + Q", downloads: "Super + Ctrl + D",
        torrents: "Super + Ctrl + E", bluetoothManager: "Ctrl + Alt + B", monitor: "Ctrl + Alt + M",
        health: "Ctrl + Alt + H", usage: "Super + Alt + U", modes: "Super + Alt + Y",
        packages: "Ctrl + Alt + U", weather: "Super + Ctrl + F", youtube: "Super + Ctrl + U",
        wikipedia: "Super + Ctrl + N", camera: "Ctrl + Alt + C"
    })

    readonly property var groups: [
        { name: Translation.tr("Watch and listen"), ids: ["mediator", "music", "audioPlayer", "youtube", "syncplay", "imageViewer", "camera"] },
        { name: Translation.tr("Sound"), ids: ["mixer", "easyEffects", "patchbay", "audioRecorder", "soundscapes", "qanun"] },
        { name: Translation.tr("Read and learn"), ids: ["books", "quran", "diwan", "anki", "wikipedia"] },
        { name: Translation.tr("Day to day"), ids: ["notes", "clock", "grit", "calculator", "weather", "editor"] },
        { name: Translation.tr("Files and devices"), ids: ["fileManager", "downloads", "torrents", "quickshare", "bluetoothManager", "discordoVoice"] },
        { name: Translation.tr("System"), ids: ["monitor", "health", "usage", "modes", "packages"] }
    ]

    property string query: ""

    function matches(app): bool {
        const q = root.query.trim().toLowerCase();
        if (q.length === 0)
            return true;
        return app.name.toLowerCase().includes(q)
            || (root.blurbs[app.id] ?? "").toLowerCase().includes(q)
            || (app.keywords ?? []).some(k => String(k).toLowerCase().includes(q));
    }

    /// Groups with their apps, filtered; anything unlisted lands in a trailing "More".
    readonly property var sections: {
        const byId = {};
        for (const a of root.apps)
            byId[a.id] = a;
        const used = new Set();
        const out = [];
        for (const g of root.groups) {
            const items = g.ids.map(id => byId[id]).filter(a => a !== undefined && root.matches(a));
            g.ids.forEach(id => used.add(id));
            if (items.length > 0)
                out.push({ name: g.name, items: items });
        }
        const rest = root.apps.filter(a => !used.has(a.id) && root.matches(a));
        if (rest.length > 0)
            out.push({ name: Translation.tr("More"), items: rest });
        return out;
    }
    readonly property int shown: sections.reduce((n, s) => n + s.items.length, 0)

    readonly property real gap: 12
    readonly property real tileW: {
        const w = flick.width - 2 * root.gap;
        const n = Math.max(1, Math.floor((w + root.gap) / (280 + root.gap)));
        return (w - root.gap * (n - 1)) / n;
    }

    function open(id: string): void {
        GlobalStates.cheatsheetOpen = false;
        Qt.callLater(() => ShellActionRegistry.trigger(id, ""));
    }

    RowLayout {
        id: header
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            leftMargin: root.gap
            rightMargin: root.gap
            topMargin: root.gap
        }
        spacing: 12

        ToolbarTextField {
            id: filter
            Layout.fillWidth: true
            Layout.maximumWidth: 420
            placeholderText: Translation.tr("Find an app")
            text: root.query
            onTextChanged: root.query = text
        }
        StyledText {
            Layout.fillWidth: true
            text: root.query.trim().length > 0
                ? Translation.tr("%1 of %2").arg(root.shown).arg(root.apps.length)
                : Translation.tr("%1 apps. Click one to open it.").arg(root.apps.length)
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            elide: Text.ElideRight
        }
    }

    Flickable {
        id: flick
        WheelScroll {}
        anchors {
            top: header.bottom
            topMargin: root.gap
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        clip: true
        contentWidth: width
        contentHeight: sectionsColumn.implicitHeight + 2 * root.gap
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: sectionsColumn
            x: root.gap
            y: 0
            width: flick.width - 2 * root.gap
            spacing: 20

            Repeater {
                model: root.sections
                delegate: ColumnLayout {
                    id: section
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        text: section.modelData.name
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                    }

                    Flow {
                        width: sectionsColumn.width
                        Layout.preferredWidth: sectionsColumn.width
                        Layout.preferredHeight: childrenRect.height
                        spacing: root.gap

                        Repeater {
                            model: section.modelData.items
                            delegate: Rectangle {
                                id: tile
                                required property var modelData
                                readonly property string chord: root.chords[modelData.id] ?? ""
                                width: root.tileW
                                height: 118
                                radius: Appearance.rounding.normal
                                color: area.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer1
                                Behavior on color { ColorAnimation { duration: Appearance.dur(120) } }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        MaterialSymbol {
                                            text: tile.modelData.icon
                                            iconSize: 22
                                            color: Appearance.colors.colPrimary
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: tile.modelData.name
                                            font.pixelSize: Appearance.font.pixelSize.larger
                                            font.weight: Font.Medium
                                            elide: Text.ElideRight
                                        }
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.blurbs[tile.modelData.id] ?? ""
                                        visible: text.length > 0
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                    Item { Layout.fillHeight: true }
                                    KeybindShortcutSequence {
                                        visible: tile.chord.length > 0
                                        compact: true
                                        maximumWidth: tile.width - 28
                                        shortcutText: tile.chord
                                    }
                                }
                                MouseArea {
                                    id: area
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.open(tile.modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: root.shown === 0
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 40
                text: Translation.tr("No app matches that")
                color: Appearance.colors.colSubtext
            }
        }
    }
}
