import QtQuick
import QtQuick.Layouts
import QtMultimedia

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Plays the question/answer audio clips returned by the bridge, in order.
 *
 * Missing and video-only clips are filtered out. A single replay button stays available
 * after the automatic pass so learners can hear the word again.
 */
Item {
    id: root

    property var clips: []
    property bool active: true
    property bool autoPlay: true
    property bool playing: false

    readonly property var playable: (root.clips ?? []).filter(clip => !clip.missing && !clip.video)
    readonly property bool hasMissing: (root.clips ?? []).some(clip => clip.missing)
    readonly property int count: root.playable.length

    property int _index: 0

    implicitWidth: controls.implicitWidth
    implicitHeight: root.clips.length > 0 ? 40 : 0
    visible: root.clips.length > 0

    function playAll(): void {
        if (root.playable.length === 0)
            return;
        root._index = 0;
        root.playing = true;
        root._playCurrent();
    }

    function toggle(): void {
        if (root.playing) {
            player.stop();
            root.playing = false;
        } else {
            root.playAll();
        }
    }

    function _playCurrent(): void {
        if (!root.playing)
            return;
        if (root._index >= root.playable.length) {
            root.playing = false;
            return;
        }
        const clip = root.playable[root._index++];
        if (!clip || !clip.url) {
            root._playCurrent();
            return;
        }
        player.source = clip.url;
        player.play();
    }

    onPlayableChanged: {
        if (root.playable.length === 0 && root.playing) {
            player.stop();
            root.playing = false;
        } else if (root.active && root.autoPlay && root.playable.length > 0) {
            Qt.callLater(root.playAll);
        }
    }

    onActiveChanged: {
        if (root.active && root.autoPlay && root.playable.length > 0)
            Qt.callLater(root.playAll);
        else if (!root.active && root.playing) {
            player.stop();
            root.playing = false;
        }
    }

    RowLayout {
        id: controls
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: ClockStyle.gapSmall

        ClockIconButton {
            symbol: root.playing ? "stop_circle" : (root.count > 0 ? "volume_up" : "volume_off")
            tooltip: root.count > 0
                ? (root.playing ? Translation.tr("Stop audio") : Translation.tr("Replay audio"))
                : Translation.tr("Audio files are missing")
            enabled: root.count > 0
            onClicked: root.toggle()
        }

        StyledText {
            text: root.count > 0
                ? (root.count === 1 ? Translation.tr("Replay audio") : Translation.tr("%1 audio clips").arg(root.count))
                : Translation.tr("Audio unavailable")
            font.pixelSize: ClockStyle.textSmall
            color: ClockStyle.colSubtext
        }
    }

    MediaPlayer {
        id: player
        autoPlay: false
        audioOutput: AudioOutput {
            volume: 0.9
        }
        onPlaybackStateChanged: {
            if (player.playbackState === MediaPlayer.StoppedState && root.playing)
                root._playCurrent();
        }
        onErrorChanged: {
            if (player.error !== MediaPlayer.NoError && root.playing) {
                console.warn("[AnkiMedia] " + player.errorString);
                Qt.callLater(root._playCurrent);
            }
        }
    }
}
