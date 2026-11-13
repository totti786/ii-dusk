pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * An anime's page in the Streaming tab: details from AniList, the provider show it was
 * matched to, and its episodes, with where you stopped marked on each.
 */
ColumnLayout {
    id: root

    property bool showCandidates: false

    signal localRequested(string id)

    readonly property var title: AnimeBrowseService.title
    readonly property var local: MediatorService.ownedFor([root.title?.title, root.title?.search], root.title?.year)
    readonly property var entry: AnimeBrowseService.resumeEntry()
    readonly property var target: {
        const e = root.entry;
        if (!e)
            return null;
        if (!e.watched)
            return { "id": e.episode_id, "number": e.episode_number };
        const eps = AnimeBrowseService.episodes;
        const i = eps.findIndex(x => String(x.id) === String(e.episode_id));
        return i >= 0 && i + 1 < eps.length ? eps[i + 1] : null;
    }

    readonly property bool anyDownloading: Object.values(AnimeBrowseService.downloads).some(
        d => d.state === "queued" || d.state === "downloading" || d.state === "processing")
    readonly property int watchedCount: AnimeBrowseService.episodes.filter(
        e => AnimeBrowseService.episodeState(String(e.id))?.watched === true).length

    function dlLabel(d): string {
        if (!d)
            return "";
        if (d.state === "done")
            return "Saved";
        if (d.state === "queued")
            return "Queued";
        if (d.state === "processing")
            return d.phase ? d.phase + " " + Math.round(d.percent) + "%" : "Finishing…";
        if (d.state === "error")
            return "Failed";
        return Math.round(d.percent) + "%";
    }

    function clock(sec): string {
        const t = Math.max(0, Math.floor(Number(sec) || 0));
        const h = Math.floor(t / 3600);
        const m = Math.floor((t % 3600) / 60);
        const s = String(t % 60).padStart(2, "0");
        return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${s}` : `${m}:${s}`;
    }

    spacing: 14

    property int cursor: -1
    function episodeItem(i): var {
        return epRepeater.itemAt(i);
    }
    readonly property string nextId: root.target ? String(root.target.id) : ""

    BackdropHero {
        tall: true
        name: root.title?.title ?? ""
        poster: root.title?.poster ?? ""
        background: root.title?.banner ?? ""
        description: root.title?.description ?? ""
        rating: root.title?.rating ?? ""
        facts: [root.title?.format === "MOVIE" ? "Movie" : "Anime", String(root.title?.year ?? ""),
            root.title?.episodes > 0 ? root.title.episodes + " episodes" : "", root.title?.runtime ?? ""]
            .concat((root.title?.genres ?? []).slice(0, 4))
        onBackRequested: AnimeBrowseService.back()

        ClockButton {
            visible: root.target !== null
            symbol: "play_arrow"
            label: {
                const e = root.entry;
                const n = root.target?.number ?? "";
                const at = e && !e.watched && e.position > 5 ? " · " + root.clock(e.position) : "";
                return (e?.watched ? "Next" : "Resume") + (n !== "" ? " Ep " + n : "") + at;
            }
            variant: "filled"
            onClicked: AnimeBrowseService.play(root.target)
        }
        ClockButton {
            visible: root.local !== null
            symbol: "video_library"
            label: "In your library"
            variant: "tonal"
            onClicked: root.localRequested(root.local.id)
        }
        ClockButton {
            visible: AnimeBrowseService.episodes.length > 0
            symbol: "download"
            label: root.watchedCount > 0 && root.watchedCount < AnimeBrowseService.episodes.length
                ? "Download remaining" : "Download season"
            variant: "tonal"
            onClicked: AnimeBrowseService.downloadSeason(root.watchedCount > 0)
        }
        ClockButton {
            visible: root.anyDownloading || AnimeBrowseService.batchActive
            symbol: "close"
            label: "Cancel downloads"
            variant: "text"
            onClicked: AnimeBrowseService.cancelDownloads()
        }
        ClockButton {
            visible: String(root.title?.trailer ?? "") !== ""
            symbol: "smart_display"
            label: "Trailer"
            variant: "tonal"
            onClicked: Qt.openUrlExternally("https://www.youtube.com/watch?v=" + root.title.trailer)
        }
    }

    InfoGrid {
        Layout.fillWidth: true
        Layout.topMargin: 4
        rows: [
            { "k": "Studio", "v": (root.title?.studios ?? []).join(", ") },
            { "k": "Status", "v": root.title?.status ?? "" },
            { "k": "Season", "v": [root.title?.season, root.title?.year].filter(x => x).join(" ") },
            { "k": "Source", "v": root.title?.source ?? "" },
            { "k": "Episodes", "v": root.title?.episodes > 0 ? String(root.title.episodes) : "" }
        ]
    }

    RowLayout {
        visible: AnimeBrowseService.episodes.length > 0
        Layout.fillWidth: true
        spacing: 6

        StyledText {
            text: "Download quality"
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        Repeater {
            model: [{ "v": "1080", "t": "1080p" }, { "v": "720", "t": "720p · smaller" }, { "v": "480", "t": "480p" }]
            ClockButton {
                required property var modelData
                label: modelData.t
                variant: Config.options.mediator.animeDownloadQuality === modelData.v ? "filled" : "tonal"
                onClicked: Config.options.mediator.animeDownloadQuality = modelData.v
            }
        }
    }

    StyledText {
        visible: AnimeBrowseService.downloadNotice !== ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: AnimeBrowseService.downloadNotice
        color: Appearance.colors.colTertiary
        font.pixelSize: Appearance.font.pixelSize.smaller
    }

    // Which provider show this is
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: AnimeBrowseService.chosen !== null

        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: "Source: " + (AnimeBrowseService.chosen?.title ?? "")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        ClockButton {
            visible: AnimeBrowseService.candidates.length > 1
            label: root.showCandidates ? "Hide" : "Wrong show?"
            variant: "text"
            onClicked: root.showCandidates = !root.showCandidates
        }
    }

    Flow {
        visible: root.showCandidates
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: AnimeBrowseService.candidates.slice(0, 10)
            ClockButton {
                required property var modelData
                label: modelData.title
                variant: AnimeBrowseService.chosen?.id === modelData.id ? "filled" : "tonal"
                onClicked: {
                    AnimeBrowseService.choose(modelData);
                    root.showCandidates = false;
                }
            }
        }
    }

    StyledIndeterminateProgressBar {
        visible: AnimeBrowseService.matching || (AnimeBrowseService.chosen !== null && AnimeBrowseService.episodesBusy)
        Layout.fillWidth: true
    }

    StyledText {
        visible: AnimeBrowseService.matching || (AnimeBrowseService.chosen !== null && AnimeBrowseService.episodesBusy)
        text: AnimeBrowseService.matching ? "Finding this anime on the provider…" : "Loading episodes…"
        color: Appearance.colors.colSubtext
    }

    StyledText {
        visible: !AnimeBrowseService.matching && AnimeBrowseService.chosen === null
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: "Couldn't find this anime on the provider."
        color: Appearance.colors.colSubtext
    }

    StyledText {
        visible: AnimeBrowseService.episodesError !== ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: AnimeBrowseService.episodesError
        color: Appearance.colors.colError
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Repeater {
            id: epRepeater
            model: AnimeBrowseService.episodes

            Rectangle {
                id: ep
                required property var modelData
                required property int index
                readonly property var watchState: AnimeBrowseService.episodeState(String(modelData.id))
                readonly property var dl: AnimeBrowseService.downloadState(modelData.id)
                readonly property bool selected: root.cursor === index
                readonly property bool upNext: String(modelData.id) === root.nextId
                readonly property bool partial: watchState !== null && !watchState.watched && watchState.position > 5
                readonly property real fraction: partial && Number(watchState.duration) > 0
                    ? Math.min(1, watchState.position / watchState.duration) : 0
                Layout.fillWidth: true
                implicitHeight: 58
                radius: Appearance.rounding.normal
                color: epArea.containsMouse || ep.selected ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer1
                border.width: ep.selected ? 2 : 0
                border.color: Appearance.colors.colPrimary
                Behavior on color {
                    ColorAnimation { duration: Appearance.dur(120) }
                }

                RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 14 }
                    spacing: 14
                    StyledText {
                        Layout.preferredWidth: 38
                        horizontalAlignment: Text.AlignHCenter
                        text: ep.modelData.number
                        color: ep.watchState?.watched ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.DemiBold
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            spacing: 8
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: ep.modelData.title || "Episode " + ep.modelData.number
                                color: ep.watchState?.watched ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer0
                            }
                            Rectangle {
                                visible: ep.upNext
                                implicitWidth: upText.implicitWidth + 12
                                implicitHeight: 18
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colPrimary
                                StyledText {
                                    id: upText
                                    anchors.centerIn: parent
                                    text: ep.partial ? "RESUME" : "UP NEXT"
                                    color: Appearance.colors.colOnPrimary
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Bold
                                }
                            }
                        }
                        Rectangle {
                            visible: ep.partial
                            Layout.fillWidth: true
                            Layout.preferredHeight: 3
                            radius: 1.5
                            color: Appearance.colors.colLayer2
                            Rectangle {
                                width: parent.width * (ep.fraction > 0 ? ep.fraction : 0.3)
                                height: parent.height
                                radius: 1.5
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                    StyledText {
                        visible: ep.partial
                        text: "Left at " + root.clock(ep.watchState?.position ?? 0)
                        color: Appearance.colors.colPrimary
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    StyledText {
                        visible: ep.dl !== null
                        text: root.dlLabel(ep.dl)
                        color: ep.dl?.state === "error" ? Appearance.colors.colError : Appearance.colors.colTertiary
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    ClockButton {
                        iconOnly: true
                        variant: "text"
                        symbol: !ep.dl ? "download" : ep.dl.state === "done" ? "download_done"
                            : ep.dl.state === "error" ? "refresh" : "downloading"
                        label: ep.dl?.state === "error" ? "Retry download" : ep.dl ? root.dlLabel(ep.dl) : "Download this episode"
                        enabled: !ep.dl || ep.dl.state === "error"
                        onClicked: AnimeBrowseService.downloadEpisode(ep.modelData)
                    }
                    MaterialSymbol {
                        text: ep.watchState?.watched ? "check_circle" : "play_circle"
                        fill: ep.watchState?.watched ? 1 : 0
                        iconSize: 24
                        color: ep.watchState?.watched || epArea.containsMouse || ep.selected
                            ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }
                }
                MouseArea {
                    id: epArea
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: parent.right; rightMargin: 130 }
                    hoverEnabled: true
                    cursorShape: AnimeBrowseService.starting ? Qt.BusyCursor : Qt.PointingHandCursor
                    onClicked: AnimeBrowseService.play(ep.modelData)
                    onContainsMouseChanged: if (containsMouse) root.cursor = ep.index
                }
            }
        }
    }
}
