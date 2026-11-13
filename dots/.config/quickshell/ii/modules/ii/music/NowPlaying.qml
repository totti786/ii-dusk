pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import "MusicFormat.js" as Fmt

/**
 * The big view: the cover large, the controls, and the lyrics beside it. The page takes a
 * tint from the cover, so each song gets its own colour.
 */
Rectangle {
    id: root

    property bool compact: false
    signal closeRequested()

    readonly property var track: MusicService.track
    // The song's own colour, as a Material 3 tonal set (see MusicTone)
    readonly property color tint: MusicTone.primary
    readonly property bool narrow: width < 860
    /// The lyrics column, which the user can switch off; the player then centres itself
    readonly property bool lyricsWanted: MusicService.settings.show_lyrics ?? true
    readonly property bool lyricsShown: !root.narrow && root.lyricsWanted

    radius: ClockStyle.radiusExtraLarge
    color: MusicTone.surface
    Behavior on color { ColorAnimation { duration: Appearance.dur(400) } }
    clip: true

    // A flat tonal surface, like every other pane in the shell, with the cover's colour
    // settling in from the top. No image behind it: colour from the song is enough.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.alpha(MusicTone.container, 0.9) }
            GradientStop { position: 0.65; color: Qt.alpha(MusicTone.container, 0.25) }
            GradientStop { position: 1.0; color: "transparent" }
        }
        Behavior on opacity { NumberAnimation { duration: Appearance.dur(400) } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 36

        Item { Layout.fillWidth: true; visible: !root.narrow && !root.lyricsWanted }

        ColumnLayout {
            id: leftCol
            Layout.fillWidth: root.narrow
            Layout.preferredWidth: root.narrow ? root.width - 56 : Math.min(440, (root.width - 92) * 0.45)
            Layout.maximumWidth: root.narrow ? root.width : 440
            Layout.fillHeight: true
            spacing: 14

            Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }

            RoundedCover {
                id: cover
                Layout.alignment: Qt.AlignHCenter
                readonly property real side: Math.max(120, Math.min(root.narrow ? 220 : 400,
                    root.height - 330, root.narrow ? root.width - 80 : root.width * 0.42))
                Layout.preferredWidth: side
                Layout.preferredHeight: side
                radius: ClockStyle.radiusExtraLarge
                path: root.track?.cover || root.track?.thumb || ""
                symbol: "album"

                // A soft halo in the cover's colour, drawn as two widening layers
                Rectangle {
                    z: -1
                    anchors.fill: parent
                    anchors.margins: -8
                    radius: cover.radius + 8
                    color: MusicTone.container
                    opacity: 0.6
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 12
                // Lines up with the cover's edges, which the cover centres inside the column
                Layout.leftMargin: Math.max(0, (leftCol.width - cover.side) / 2)
                Layout.rightMargin: Layout.leftMargin
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: root.track?.title ?? Translation.tr("Nothing playing")
                    color: MusicTone.content
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: 26
                    elide: Text.ElideRight
                }
                ArtistLink {
                    Layout.fillWidth: true
                    track: root.track
                    suffix: root.track?.album ? " · " + root.track.album : ""
                    pixelSize: Appearance.font.pixelSize.small
                    color: MusicTone.contentVariant
                    hoverColor: MusicTone.content
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Math.max(0, (leftCol.width - cover.side) / 2)
                Layout.rightMargin: Layout.leftMargin
                spacing: 0
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
                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        text: Fmt.time(seek.dragging ? seek.dragValue * MusicService.duration : MusicService.position)
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        text: Fmt.time(MusicService.duration)
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 10
                ClockIconButton {
                    colBackgroundToggled: MusicTone.primary
                    colBackgroundToggledHover: MusicTone.primary
                    colIcon: toggled ? MusicTone.onPrimary : ClockStyle.colOnSurfaceVariant
                    symbol: "shuffle"
                    toggled: MusicService.shuffle
                    tooltip: Translation.tr("Shuffle")
                    onClicked: MusicService.toggleShuffle()
                }
                ClockIconButton {
                    symbol: "skip_previous"
                    size: 48
                    iconSize: 28
                    tooltip: Translation.tr("Previous")
                    onClicked: MusicService.prev()
                }
                RippleButton {
                    implicitWidth: 88
                    implicitHeight: 64
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
                            iconSize: 36
                            color: MusicTone.onPrimary
                        }
                    }
                    StyledToolTip {
                        text: MusicService.playing ? Translation.tr("Pause") : Translation.tr("Play")
                    }
                }
                ClockIconButton {
                    symbol: "skip_next"
                    size: 48
                    iconSize: 28
                    tooltip: Translation.tr("Next")
                    onClicked: MusicService.next()
                }
                ClockIconButton {
                    colBackgroundToggled: MusicTone.primary
                    colBackgroundToggledHover: MusicTone.primary
                    colIcon: toggled ? MusicTone.onPrimary : ClockStyle.colOnSurfaceVariant
                    symbol: MusicService.repeatMode === "one" ? "repeat_one" : "repeat"
                    toggled: MusicService.repeatMode !== "off"
                    tooltip: Translation.tr("Repeat")
                    onClicked: MusicService.cycleRepeat()
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                ClockIconButton {
                    colBackgroundToggled: MusicTone.primary
                    colBackgroundToggledHover: MusicTone.primary
                    colIcon: toggled ? MusicTone.onPrimary : ClockStyle.colOnSurfaceVariant
                    symbol: MusicService.hasTrack && MusicService.isDownloaded(MusicService.track.id) ? "download_done"
                        : MusicService.hasTrack && MusicService.isDownloading(MusicService.track.id) ? "downloading" : "download"
                    toggled: MusicService.hasTrack && MusicService.isDownloaded(MusicService.track.id)
                    tooltip: Translation.tr("Download for offline")
                    onClicked: if (MusicService.hasTrack) MusicService.toggleDownload(MusicService.track)
                }
                ClockIconButton {
                    symbol: "favorite"
                    filled: MusicService.hasTrack && MusicService.isFav(MusicService.track.id)
                    tooltip: Translation.tr("Favourite")
                    onClicked: if (MusicService.hasTrack) MusicService.toggleFav(MusicService.track)
                }
                ClockIconButton {
                    colBackgroundToggled: MusicTone.primary
                    colBackgroundToggledHover: MusicTone.primary
                    colIcon: toggled ? MusicTone.onPrimary : ClockStyle.colOnSurfaceVariant
                    visible: !root.narrow
                    symbol: "lyrics"
                    toggled: root.lyricsWanted
                    tooltip: root.lyricsWanted ? Translation.tr("Hide lyrics") : Translation.tr("Show lyrics")
                    onClicked: MusicService.saveSettings({ "show_lyrics": !root.lyricsWanted })
                }
                MaterialSymbol {
                    text: MusicService.volume === 0 ? "volume_off" : "volume_up"
                    iconSize: 20
                    color: ClockStyle.colSubtext
                }
                MiniSlider {
                    Layout.preferredWidth: 140
                    colFill: MusicTone.primary
                    colTrack: MusicTone.track
                    value: MusicService.volume / 100
                    showPercent: true
                onMoved: v => MusicService.setVolume(Math.round(v * 100))
                }
            }

            Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }
        }

        Item { Layout.fillWidth: true; visible: !root.narrow && !root.lyricsWanted }

        // The lyrics sit on a tonal card, the same surface the shell's other cards use
        Item {
            visible: root.lyricsShown
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                anchors.fill: parent
                radius: ClockStyle.radiusLarge
                color: Qt.alpha(MusicTone.surfaceHigh, 0.7)
            }
            LyricsView {
                anchors.fill: parent
                anchors.margins: 18
                accent: root.tint
            }
        }
    }

}
