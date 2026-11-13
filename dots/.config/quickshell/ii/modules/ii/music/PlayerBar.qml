pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import "MusicFormat.js" as Fmt

/** The strip along the bottom: what is playing, the controls, and the way into the big view. */
Rectangle {
    id: root

    property bool compact: false
    signal expandRequested()

    readonly property var track: MusicService.track
    implicitHeight: 92
    readonly property real pad: 10
    radius: ClockStyle.radiusLarge
    color: root.track ? MusicTone.surfaceHigh : ClockStyle.colSurfaceHigh
    Behavior on color { ColorAnimation { duration: Appearance.dur(300) } }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.expandRequested()
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: 14

        RowLayout {
            Layout.preferredWidth: root.compact ? 190 : 300
            Layout.maximumWidth: root.compact ? 190 : 300
            Layout.fillHeight: true
            spacing: 12
            RoundedCover {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: root.height - root.pad * 2
                Layout.preferredHeight: root.height - root.pad * 2
                radius: root.radius - root.pad
                path: root.track?.cover || root.track?.thumb || ""
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    text: root.track ? root.track.title : Translation.tr("Nothing playing")
                    color: root.track ? MusicTone.content : ClockStyle.colOnBackground
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                ArtistLink {
                    Layout.fillWidth: true
                    track: root.track
                    artistText: MusicService.playerError !== "" ? MusicService.playerError
                        : MusicService.loading ? Translation.tr("Loading…")
                        : root.track?.artist ?? Translation.tr("Search for a song to start")
                    linked: MusicService.playerError === "" && !MusicService.loading && root.track !== null
                    color: MusicService.playerError !== "" ? ClockStyle.colError : ClockStyle.colSubtext
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6
                ClockIconButton {
                    symbol: "shuffle"
                    tooltip: Translation.tr("Shuffle")
                    toggled: MusicService.shuffle
                    onClicked: MusicService.toggleShuffle()
                }
                ClockIconButton {
                    symbol: "skip_previous"
                    tooltip: Translation.tr("Previous")
                    onClicked: MusicService.prev()
                }
                // Playing is a rounded square, stopped a pill: the corners say which, and the
                // footprint stays put. The colour is the song's own tone.
                RippleButton {
                    implicitWidth: 52
                    implicitHeight: 44
                    buttonRadius: MusicService.playing ? ClockStyle.radiusFab : height / 2
                    buttonRadiusPressed: ClockStyle.radiusLarge
                    colBackground: MusicTone.primary
                    colBackgroundHover: ColorUtils.mix(MusicTone.primary, MusicTone.onPrimary, 0.9)
                    colRipple: ColorUtils.mix(MusicTone.primary, MusicTone.onPrimary, 0.8)
                    onClicked: MusicService.toggle()
                    contentItem: Item {
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: MusicService.loading ? "hourglass_top" : MusicService.playing ? "pause" : "play_arrow"
                            fill: 1
                            iconSize: 26
                            color: MusicTone.onPrimary
                        }
                    }
                    StyledToolTip {
                        text: MusicService.playing ? Translation.tr("Pause") : Translation.tr("Play")
                    }
                }
                ClockIconButton {
                    symbol: "skip_next"
                    tooltip: Translation.tr("Next")
                    onClicked: MusicService.next()
                }
                ClockIconButton {
                    symbol: MusicService.repeatMode === "one" ? "repeat_one" : "repeat"
                    tooltip: Translation.tr("Repeat")
                    toggled: MusicService.repeatMode !== "off"
                    onClicked: MusicService.cycleRepeat()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                StyledText {
                    Layout.preferredWidth: 38
                    horizontalAlignment: Text.AlignRight
                    text: Fmt.time(seek.dragging ? seek.dragValue * MusicService.duration : MusicService.position)
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                }
                MiniSlider {
                    id: seek
                    Layout.fillWidth: true
                    wavy: true
                    animate: MusicService.playing
                    colFill: MusicTone.primary
                    colTrack: MusicTone.track
                    value: MusicService.duration > 0 ? MusicService.position / MusicService.duration : 0
                    onMoved: v => MusicService.seek(v * MusicService.duration)
                }
                StyledText {
                    Layout.preferredWidth: 38
                    text: Fmt.time(MusicService.duration)
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                }
            }
        }

        RowLayout {
            visible: !root.compact
            Layout.preferredWidth: 210
            spacing: 8
            Item { Layout.fillWidth: true }
            ClockIconButton {
                visible: root.track !== null
                symbol: MusicService.hasTrack && MusicService.isDownloaded(MusicService.track.id) ? "download_done"
                    : MusicService.hasTrack && MusicService.isDownloading(MusicService.track.id) ? "downloading" : "download"
                toggled: MusicService.hasTrack && MusicService.isDownloaded(MusicService.track.id)
                tooltip: Translation.tr("Download for offline")
                onClicked: MusicService.toggleDownload(MusicService.track)
            }
            ClockIconButton {
                visible: root.track !== null
                symbol: "favorite"
                filled: MusicService.hasTrack && MusicService.isFav(MusicService.track.id)
                tooltip: Translation.tr("Favourite")
                onClicked: MusicService.toggleFav(MusicService.track)
            }
            MaterialSymbol {
                text: MusicService.volume === 0 ? "volume_off" : MusicService.volume < 50 ? "volume_down" : "volume_up"
                iconSize: 20
                color: ClockStyle.colSubtext
            }
            MiniSlider {
                Layout.preferredWidth: 96
                colFill: MusicTone.primary
                colTrack: MusicTone.track
                value: MusicService.volume / 100
                showPercent: true
                onMoved: v => MusicService.setVolume(Math.round(v * 100))
            }
        }
    }
}
