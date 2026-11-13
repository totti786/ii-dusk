pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "QuranCore.js" as Core

/// Recitation controls for the top bar: the reciter (which opens the reciter list) and what is
/// being recited, previous, play and next, a slim progress line, then follow and volume.
RowLayout {
    id: root

    required property var player
    property bool reciterOpen: false
    /// How much of the bar fits: 0 everything, 1 no progress line, 2 no volume slider or follow
    /// toggle, a narrower reciter, 3 no speed or stop, the reciter as an icon
    property int level: 0

    signal playRequested()
    signal reciterToggled()

    spacing: 6

    readonly property bool idle: root.player.currentKey === ""
    readonly property real frac: root.player.durationMs > 0 ? Math.min(1, root.player.positionMs / root.player.durationMs) : 0
    readonly property var recitation: Core.RECITATIONS.find(r => r.code === Config.options.quran.recitation) ?? Core.RECITATIONS[0]
    readonly property string nowText: {
        if (root.player.error !== "")
            return root.player.error;
        if (root.idle)
            return root.recitation.nameAr;
        const p = root.player.currentKey.split(":");
        return Core.SURAH_NAMES_AR[+p[0]] + " · " + p[1];
    }

    function clock(ms: real): string {
        const t = Math.max(0, Math.floor(ms / 1000));
        const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
        const two = n => (n < 10 ? "0" : "") + n;
        return h > 0 ? h + ":" + two(m) + ":" + two(s) : m + ":" + two(s);
    }

    // Reciter, and what is being recited
    Rectangle {
        Layout.preferredHeight: 40
        Layout.preferredWidth: root.level >= 3 ? 44 : root.level >= 2 ? 190 : 250
        radius: Appearance.rounding.full
        color: reciterArea.containsMouse || root.reciterOpen ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 12
            spacing: 8
            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: Appearance.rounding.full
                color: root.player.playing ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "record_voice_over"
                    iconSize: 18
                    fill: 1
                    color: root.player.playing ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                visible: root.level < 3
                Layout.fillWidth: true
                text: root.nowText
                elide: Text.ElideRight
                font.weight: Font.Medium
                color: root.player.error !== "" ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer0
            }
            MaterialSymbol {
                visible: root.level < 3
                text: root.reciterOpen ? "expand_less" : "expand_more"
                iconSize: 20
                color: Appearance.colors.colSubtext
            }
        }
        MouseArea {
            id: reciterArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.reciterToggled()
        }
    }

    // Transport
    QuranButton { icon: "skip_previous"; enabled: !root.idle; onClicked: root.player.step(-1) }
    QuranButton {
        primary: true
        icon: root.player.loading ? "hourglass_top" : root.player.playing ? "pause" : "play_arrow"
        onClicked: root.playRequested()
    }
    QuranButton { icon: "skip_next"; enabled: !root.idle; onClicked: root.player.step(1) }
    QuranButton { visible: root.level < 3; icon: "stop"; enabled: !root.idle; onClicked: root.player.stop() }

    // Progress
    StyledText {
        visible: root.level < 1
        text: root.clock(root.player.positionMs)
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
    }
    Rectangle {
        visible: root.level < 1
        Layout.preferredWidth: 150
        Layout.preferredHeight: 5
        Layout.alignment: Qt.AlignVCenter
        radius: 3
        color: Appearance.colors.colOutlineVariant
        Rectangle {
            width: parent.width * root.frac
            height: parent.height
            radius: 3
            color: Appearance.colors.colPrimary
        }
        MouseArea {
            anchors { fill: parent; topMargin: -10; bottomMargin: -10 }
            enabled: !root.idle
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => root.player.seekFraction(mouse.x / width)
        }
    }
    StyledText {
        visible: root.level < 1
        text: root.clock(root.player.durationMs)
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
    }

    // Speed: click for the next step, wheel to move either way; lit while it is not 1x
    QuranButton {
        id: speedButton
        visible: root.level < 3
        readonly property var steps: [0.75, 1, 1.25, 1.5, 2]
        function step(dir: int): void {
            let i = steps.findIndex(v => Math.abs(v - Config.options.quran.speed) < 0.01);
            if (i < 0)
                i = 1;
            Config.options.quran.speed = steps[((i + dir) % steps.length + steps.length) % steps.length];
        }
        icon: "speed"
        iconSize: active ? 19 : 22
        iconOffset: active ? -5 : 0
        active: Math.abs(Config.options.quran.speed - 1) > 0.01
        onClicked: speedButton.step(1)
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: wheel => {
                speedButton.step(wheel.angleDelta.y > 0 ? 1 : -1);
                wheel.accepted = true;
            }
        }
        // The value, small under the icon, while it is not 1x
        StyledText {
            visible: speedButton.active
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            text: Config.options.quran.speed + "×"
            font.pixelSize: 10
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnSecondaryContainer
        }
        StyledToolTip {
            text: Translation.tr("Speed %1×").arg(Config.options.quran.speed)
        }
    }

    // Follow and volume
    QuranButton {
        visible: root.level < 2
        icon: "auto_stories"
        active: Config.options.quran.followAudio
        onClicked: Config.options.quran.followAudio = !Config.options.quran.followAudio
        StyledToolTip {
            text: Config.options.quran.followAudio ? Translation.tr("Pages turn with the recitation (on)")
                : Translation.tr("Pages turn with the recitation (off)")
        }
    }
    QuranButton {
        icon: Config.options.quran.volume < 0.01 ? "volume_off" : Config.options.quran.volume < 0.5 ? "volume_down" : "volume_up"
        onClicked: Config.options.quran.volume = Config.options.quran.volume < 0.01 ? 0.9 : 0
    }
    StyledSlider {
        visible: root.level < 2
        Layout.preferredWidth: 90
        Layout.minimumWidth: 90
        Layout.maximumWidth: 90
        Layout.alignment: Qt.AlignVCenter
        value: Config.options.quran.volume
        onMoved: Config.options.quran.volume = value
    }
}
