pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.common

/**
 * Lets the shell's lyrics (the media view, the bar) use the lyrics the Music app already
 * has instead of looking the song up a second time. While the Music player is the active
 * one, this turns its lyrics into LRC text for LyricsService, which treats it like a local
 * lyrics file: it takes priority and the online providers stay quiet. The lookups go
 * through the same on-disk cache the Music window uses, so a song is fetched once.
 */
Singleton {
    id: root

    readonly property var player: MprisController.activePlayer
    readonly property bool isMusic: (root.player?.dbusName ?? "") === "org.mpris.MediaPlayer2.music"
    readonly property string videoId: {
        const m = String(root.player?.metadata?.["xesam:url"] ?? "").match(/[?&]v=([\w-]{6,})/);
        return root.isMusic && m ? m[1] : "";
    }
    readonly property string title: root.isMusic ? (root.player?.trackTitle ?? "") : ""
    readonly property string artist: root.isMusic ? (root.player?.trackArtist ?? "") : ""
    readonly property real duration: root.isMusic ? (root.player?.length ?? 0) : 0

    property string loadedId: ""
    property string loadedText: ""

    /// LRC (or plain) text for the song that is playing now; empty until it is ready
    readonly property string lrcText: root.videoId.length > 0 && root.loadedId === root.videoId ? root.loadedText : ""

    /// True from the moment a song starts until its lyrics arrive (or the lookup gives up),
    /// so the online providers do not start their own search in the meantime
    readonly property bool loading: root.videoId.length > 0 && root.loadedId !== root.videoId

    function loadingFor(player: var): bool {
        return player?.dbusName === "org.mpris.MediaPlayer2.music" && root.loading;
    }

    function textFor(player: var): string {
        return player?.dbusName === "org.mpris.MediaPlayer2.music" ? root.lrcText : "";
    }

    function toLrc(lines: var, synced: bool): string {
        if (!synced)
            return lines.map(l => l.text).join("\n");
        const pad = (n, w) => String(n).padStart(w, "0");
        return lines.map(l => {
            const m = Math.floor(l.t / 60);
            const s = l.t - m * 60;
            return `[${pad(m, 2)}:${pad(s.toFixed(2), 5)}]${l.text}`;
        }).join("\n");
    }

    onVideoIdChanged: {
        root.loadedId = "";
        root.loadedText = "";
        if (root.videoId.length === 0)
            return;
        // The title and artist may arrive a moment after the id; wait for them to settle
        settle.restart();
    }

    Timer {
        id: settle
        interval: 400
        onTriggered: {
            if (root.videoId.length === 0)
                return;
            // The previous song's lookup ends first; changing `wanted` under it would make its
            // exit look like this song's failure
            if (run.running) {
                run.again = true;
                return;
            }
            run.wanted = root.videoId;
            run.command = ["python3", "-I", `${Directories.scriptPath}/music/music.py`, "lyrics", root.videoId,
                           "--title", root.title, "--artist", root.artist, "--duration", String(root.duration)];
            run.running = true;
        }
    }

    Process {
        id: run
        property string wanted: ""
        property bool again: false
        onExited: {
            if (run.again) {
                run.again = false;
                settle.restart();
                return;
            }
            // Failed or empty: stop waiting, and let the online providers have a go
            if (run.wanted === root.videoId && root.loadedId !== run.wanted) {
                root.loadedText = "";
                root.loadedId = run.wanted;
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try {
                    d = JSON.parse(text);
                } catch (e) {}
                if (!d?.ok || d.id !== run.wanted || d.id !== root.videoId)
                    return;
                root.loadedText = (d.lines ?? []).length > 0 ? root.toLrc(d.lines, d.synced) : "";
                root.loadedId = d.id;
            }
        }
    }
}
