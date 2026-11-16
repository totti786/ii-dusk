pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "../../common/functions/LyricsKaraoke.js" as Karaoke

/**
 * Lyrics that follow the song, in the same way as the media view and the overlay: the lines,
 * their provider order and the sync offset come from LyricsService, and the line being sung
 * fills in word by word (real word timing where a provider has it, spread over the line where
 * it does not). Type stays one size and the sung line is scaled up, so nothing reflows; lines
 * fade with distance and the top and bottom dissolve. Clicking a line seeks to it; scrolling
 * by hand pauses following for a few seconds. Unsynced text is a plain, readable page.
 */
Item {
    id: root

    property color accent: ClockStyle.colPrimary

    // Lyrics come from the same place as the media overlay's (LyricsService: BetterLyrics,
    // LRCLIB, lrcmux, NetEase, then YouTube Music and Genius text) whenever the Music player is
    // the one the shell is following. The Music app's own lookup is the fallback when that chain
    // finds nothing, or when another player has the shell's attention.
    readonly property bool followed: (MprisController.activePlayer?.dbusName ?? "") === "org.mpris.MediaPlayer2.music"
        && LyricsService.lyricsEnabled
    readonly property bool shared: root.followed && (LyricsService.hasAnyLyrics || LyricsService.searching)
    readonly property bool sharedSynced: LyricsService.hasSyncedLines
    readonly property var lines: {
        if (!root.shared)
            return MusicService.lyrics.lines ?? [];
        if (root.sharedSynced)
            return LyricsService.syncedLines.map(l => ({ t: l.time, end: l.endTime, text: l.text ?? "", words: l.words ?? [] }));
        return LyricsService.plainLyrics.split("\n").map(t => ({ t: 0, text: t.trim(), words: [] }));
    }
    readonly property bool synced: root.shared ? root.sharedSynced : (MusicService.lyrics.synced ?? false)
    readonly property int current: root.shared ? LyricsService.currentIndex : MusicService.lyricIndex
    readonly property bool loading: root.shared ? LyricsService.searching : MusicService.lyricsLoading
    property bool userScrolling: false

    // Where the song is, with the user's sync offset from the media view's settings
    readonly property real position: root.shared ? LyricsService.syncPosition
        : MusicService.position + (Config.options.background.mediaMode.lyricsOffsetMs ?? 0) / 1000

    // Word-by-word state of the line being sung
    readonly property var currentLine: root.synced && root.current >= 0 ? (root.lines[root.current] ?? null) : null
    readonly property var nextLine: root.synced && root.current >= 0 ? (root.lines[root.current + 1] ?? null) : null
    readonly property var currentRanges: root.currentLine
        ? Karaoke.computeWordRanges(root.currentLine.text, root.currentLine.words, root.currentLine.t,
            root.currentLine.end, root.nextLine?.t)
        : []
    readonly property string currentHtml: root.currentRanges.length > 0
        ? Karaoke.karaokeHtml(root.currentLine.text, root.currentRanges, root.position, MusicTone.content, 0.38)
        : ""

    // The player only reports its position now and then; the fill needs it often
    Timer {
        interval: 50
        repeat: true
        running: root.shared && MusicService.playing && root.currentRanges.length > 0
        onTriggered: MprisController.activePlayer?.positionChanged()
    }

    function followTarget(): void {
        if (!root.synced || root.userScrolling || root.current < 0)
            return;
        const item = list.itemAtIndex(root.current);
        if (!item) {
            // Not built yet (a long jump, or the list is still filling): bring it in, then glide
            list.positionViewAtIndex(root.current, ListView.Center);
            Qt.callLater(root.followTarget);
            return;
        }
        const target = Math.max(-list.topMargin, Math.min(list.contentHeight - list.height + list.bottomMargin,
            item.y + item.height / 2 - list.height / 2));
        follow.stop();
        follow.from = list.contentY;
        follow.to = target;
        follow.start();
    }

    Connections {
        target: MusicService
        function onLyricIndexChanged() { root.followTarget(); }
    }
    Connections {
        target: LyricsService
        function onCurrentIndexChanged() { root.followTarget(); }
    }
    // Providers only start once a lyrics view asks for them
    Component.onCompleted: if (root.followed) LyricsService.initiliazeLyrics()
    onFollowedChanged: if (root.followed) LyricsService.initiliazeLyrics()
    onLinesChanged: Qt.callLater(root.followTarget)
    onSyncedChanged: Qt.callLater(root.followTarget)

    NumberAnimation {
        id: follow
        target: list
        property: "contentY"
        duration: 560
        easing.type: Easing.OutCubic
    }

    Timer {
        id: resume
        interval: 1500
        onTriggered: { root.userScrolling = false; root.followTarget(); }
    }

    ClockEmptyState {
        anchors.centerIn: parent
        visible: root.lines.length === 0
        symbol: root.loading ? "hourglass_top" : "lyrics"
        title: root.loading ? Translation.tr("Finding lyrics…")
            : MusicService.hasTrack ? Translation.tr("No lyrics for this song") : Translation.tr("Nothing playing")
    }

    Item {
        id: viewport
        anchors.fill: parent
        visible: root.lines.length > 0
        layer.enabled: root.synced
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: fade
        }

        ListView {
            id: list
            WheelScroll {}
            anchors.fill: parent
            clip: true
            model: root.lines
            cacheBuffer: 200000
            boundsBehavior: Flickable.StopAtBounds
            topMargin: root.synced ? height * 0.34 : 24
            bottomMargin: root.synced ? height * 0.5 : 24
            spacing: root.synced ? 14 : 2
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            // Rows are built as they come into view and the height of the list grows with them,
            // so the target moves; keep aiming at the sung line
            onContentHeightChanged: Qt.callLater(root.followTarget)
            onHeightChanged: Qt.callLater(root.followTarget)

            onMovementStarted: { root.userScrolling = true; follow.stop(); resume.restart(); }
            onMovementEnded: resume.restart()

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool active: root.synced && index === root.current
                readonly property int distance: root.synced && root.current >= 0 ? Math.abs(index - root.current) : 0
                property real emphasis: row.active ? 1 : 0
                Behavior on emphasis { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                width: ListView.view.width
                height: lineText.implicitHeight * (root.synced ? 0.9 : 1) + (root.synced ? 8 : 4)

                // Layout is always at the sung line's size; the other lines are the same text
                // scaled down, so the list never reflows as the song moves.
                StyledText {
                    id: lineText
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.synced ? 20 : 8
                    width: root.synced ? (parent.width - 40) : (parent.width - 16)
                    textFormat: row.active && root.currentHtml.length > 0 ? Text.StyledText : Text.PlainText
                    text: row.active && root.currentHtml.length > 0 ? root.currentHtml
                        : (row.modelData.text.length > 0 ? row.modelData.text : "♪")
                    wrapMode: Text.Wrap
                    font.pixelSize: root.synced ? 30 : 18
                    font.variableAxes: ({ "wght": root.synced ? 700 : 480 })
                    color: row.active ? MusicTone.content : MusicTone.contentVariant
                    opacity: !root.synced ? 0.9
                        : row.active ? 1 : Math.max(0.16, 0.5 - row.distance * 0.1)
                    transformOrigin: Item.Left
                    scale: root.synced ? 0.86 + 0.14 * row.emphasis : 1
                    Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                    Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.synced
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        MusicService.seek(row.modelData.t);
                        root.userScrolling = false;
                    }
                }
            }
        }
    }

    Rectangle {
        id: fade
        anchors.fill: parent
        visible: false
        layer.enabled: true
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 0.16; color: Qt.rgba(0, 0, 0, 1) }
            GradientStop { position: 0.84; color: Qt.rgba(0, 0, 0, 1) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
        }
    }
}
