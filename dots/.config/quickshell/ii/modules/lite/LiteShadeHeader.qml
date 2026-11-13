pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * What sits above the notifications in the Lite shade: a mini player for whatever MPRIS player is
 * active, the focus timer, and the month. Plain Items on the shell's own services. The player's
 * progress tick runs only while the shade is open and a track is playing, and the month grid is
 * built only while it is unfolded.
 */
ColumnLayout {
    id: root

    spacing: 10

    readonly property var player: MprisController.activePlayer
    readonly property bool hasTrack: root.player !== null && root.player !== undefined && (root.player.trackTitle ?? "").length > 0

    // ── mini player ──
    Rectangle {
        Layout.fillWidth: true
        visible: root.hasTrack
        implicitHeight: 64
        radius: 18
        color: Appearance.colors.colLayer1

        property real progress: 0
        function refresh(): void {
            progress = root.hasTrack && MprisController.hasTrackLength(root.player) ? MprisController.trackProgressOf(root.player) : 0;
        }
        Timer {
            interval: 1000
            repeat: true
            running: root.hasTrack && root.player.isPlaying
            triggeredOnStart: true
            onTriggered: parent.refresh()
        }
        Connections {
            target: root.player
            function onTrackTitleChanged() { parent.refresh(); }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                radius: 10
                color: Appearance.colors.colLayer2
                clip: true
                Image {
                    anchors.fill: parent
                    source: root.hasTrack ? (root.player.trackArtUrl ?? "") : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(88, 88)
                    visible: status === Image.Ready
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !(root.hasTrack && (root.player.trackArtUrl ?? "") !== "")
                    text: "music_note"
                    iconSize: 22
                    color: Appearance.colors.colSubtext
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.hasTrack ? (StringUtils.cleanMusicTitle(root.player.trackTitle) || root.player.trackTitle) : ""
                    color: Appearance.colors.colOnLayer0
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.hasTrack ? (root.player.trackArtist ?? "") : ""
                    visible: text !== ""
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    elide: Text.ElideRight
                }
            }
            Repeater {
                model: [
                    { icon: "skip_previous", act: "previous" },
                    { icon: "play", act: "toggle" },
                    { icon: "skip_next", act: "next" }
                ]
                delegate: Rectangle {
                    id: control
                    required property var modelData
                    readonly property bool main: modelData.act === "toggle"
                    implicitWidth: main ? 38 : 32
                    implicitHeight: implicitWidth
                    radius: implicitWidth / 2
                    color: main ? Appearance.colors.colPrimary : controlArea.containsMouse ? Appearance.colors.colLayer2 : "transparent"
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: control.main ? (root.hasTrack && root.player.isPlaying ? "pause" : "play_arrow") : control.modelData.icon
                        iconSize: control.main ? 24 : 22
                        fill: 1
                        color: control.main ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                    }
                    MouseArea {
                        id: controlArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.hasTrack)
                                return;
                            if (control.modelData.act === "toggle")
                                root.player.togglePlaying();
                            else if (control.modelData.act === "next")
                                root.player.next();
                            else
                                root.player.previous();
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            anchors.bottomMargin: 3
            height: 3
            radius: 1.5
            color: Appearance.colors.colLayer2
            visible: parent.progress > 0
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, parent.parent.progress))
                height: parent.height
                radius: parent.radius
                color: Appearance.colors.colPrimary
            }
        }
    }

    // ── focus timer ──
    Rectangle {
        id: timerCard
        Layout.fillWidth: true
        implicitHeight: 52
        radius: 18
        color: Appearance.colors.colLayer1

        function mmss(total: int): string {
            const t = Math.max(0, Math.floor(total));
            return String(Math.floor(t / 60)).padStart(2, "0") + ":" + String(t % 60).padStart(2, "0");
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 8
            spacing: 10
            MaterialSymbol {
                text: TimerService.pomodoroBreak ? "coffee" : "timer"
                iconSize: 22
                color: TimerService.pomodoroRunning ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: timerCard.mmss(TimerService.pomodoroSecondsLeft)
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                }
                StyledText {
                    text: TimerService.pomodoroBreak ? Translation.tr("Break") : Translation.tr("Focus")
                        + (TimerService.pomodoroFocusToday > 0 ? " · " + Translation.tr("%1 today").arg(TimerService.pomodoroFocusToday) : "")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
            Repeater {
                model: [
                    { icon: "restart_alt", act: "reset" },
                    { icon: "skip_next", act: "skip" },
                    { icon: "play", act: "toggle" }
                ]
                delegate: Rectangle {
                    id: tctl
                    required property var modelData
                    readonly property bool main: modelData.act === "toggle"
                    implicitWidth: 36
                    implicitHeight: 36
                    radius: 18
                    color: main ? Appearance.colors.colPrimary : tctlArea.containsMouse ? Appearance.colors.colLayer2 : "transparent"
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: tctl.main ? (TimerService.pomodoroRunning ? "pause" : "play_arrow") : tctl.modelData.icon
                        iconSize: 22
                        fill: tctl.main ? 1 : 0
                        color: tctl.main ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                    }
                    MouseArea {
                        id: tctlArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (tctl.modelData.act === "toggle")
                                TimerService.togglePomodoro();
                            else if (tctl.modelData.act === "skip")
                                TimerService.skipPomodoroPhase();
                            else
                                TimerService.resetPomodoro();
                        }
                    }
                }
            }
        }
    }

    // ── month ──
    Rectangle {
        id: month
        Layout.fillWidth: true
        implicitHeight: monthColumn.implicitHeight + 20
        radius: 18
        color: Appearance.colors.colLayer1

        property bool unfolded: false
        /// The month shown: the first of it. Resets to this month whenever the grid is folded.
        property date shown: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
        readonly property int firstDay: Qt.locale().firstDayOfWeek % 7
        readonly property int offset: (shown.getDay() - firstDay + 7) % 7
        readonly property int length: new Date(shown.getFullYear(), shown.getMonth() + 1, 0).getDate()
        readonly property date today: new Date()

        function step(delta: int): void {
            shown = new Date(shown.getFullYear(), shown.getMonth() + delta, 1);
        }

        ColumnLayout {
            id: monthColumn
            anchors.fill: parent
            anchors.margins: 10
            anchors.leftMargin: 14
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                StyledText {
                    Layout.fillWidth: true
                    text: month.unfolded ? Qt.formatDate(month.shown, "MMMM yyyy") : Qt.formatDate(month.today, "dddd, d MMMM")
                    color: Appearance.colors.colOnLayer0
                    font.weight: Font.Medium
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            month.unfolded = !month.unfolded;
                            if (!month.unfolded)
                                month.shown = new Date(month.today.getFullYear(), month.today.getMonth(), 1);
                        }
                    }
                }
                Repeater {
                    model: month.unfolded ? [{ icon: "chevron_left", d: -1 }, { icon: "chevron_right", d: 1 }] : []
                    delegate: Rectangle {
                        id: nav
                        required property var modelData
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: 14
                        color: navArea.containsMouse ? Appearance.colors.colLayer2 : "transparent"
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: nav.modelData.icon
                            iconSize: 20
                            color: Appearance.colors.colOnLayer0
                        }
                        MouseArea {
                            id: navArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: month.step(nav.modelData.d)
                        }
                    }
                }
                MaterialSymbol {
                    text: month.unfolded ? "expand_less" : "expand_more"
                    iconSize: 20
                    color: Appearance.colors.colSubtext
                }
            }

            Loader {
                Layout.fillWidth: true
                active: month.unfolded
                visible: active
                sourceComponent: GridLayout {
                    columns: 7
                    columnSpacing: 0
                    rowSpacing: 2

                    Repeater {
                        model: 7
                        delegate: StyledText {
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            horizontalAlignment: Text.AlignHCenter
                            text: Qt.locale().dayName((month.firstDay + index) % 7, Locale.NarrowFormat)
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                    Repeater {
                        model: Math.ceil((month.offset + month.length) / 7) * 7
                        delegate: Item {
                            id: cell
                            required property int index
                            readonly property int day: cell.index - month.offset + 1
                            readonly property bool inMonth: cell.day >= 1 && cell.day <= month.length
                            readonly property bool isToday: cell.inMonth
                                && month.shown.getFullYear() === month.today.getFullYear()
                                && month.shown.getMonth() === month.today.getMonth()
                                && cell.day === month.today.getDate()
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 28
                            Rectangle {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                radius: 13
                                visible: cell.isToday
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                anchors.centerIn: parent
                                visible: cell.inMonth
                                text: cell.day
                                color: cell.isToday ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                    }
                }
            }
        }
    }
}
