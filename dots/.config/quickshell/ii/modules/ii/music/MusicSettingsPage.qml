pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "MusicFormat.js" as Fmt

/** How much the player keeps on disk, and whether it carries on by itself. */
Rectangle {
    id: root

    property bool compact: false
    readonly property var s: MusicService.settings
    readonly property var sizes: MusicService.cacheSizes
    readonly property var capChoices: [
        { mb: 0, label: Translation.tr("Off") }, { mb: 256, label: "256 MB" }, { mb: 512, label: "512 MB" },
        { mb: 1024, label: "1 GB" }, { mb: 2048, label: "2 GB" }, { mb: 5120, label: "5 GB" }
    ]

    color: "transparent"

    component Cache: RowLayout {
        id: row
        property string what: ""
        property string label: ""
        property string hint: ""
        Layout.fillWidth: true
        spacing: 12
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText { text: row.label; color: ClockStyle.colOnBackground; font.weight: Font.Medium }
            StyledText { text: row.hint; color: ClockStyle.colSubtext; font.pixelSize: ClockStyle.textSmall }
        }
        StyledText { text: Fmt.bytes(root.sizes[row.what]); color: ClockStyle.colSubtext }
        ClockButton {
            variant: "text"
            label: Translation.tr("Clear")
            onClicked: MusicService.clearCache(row.what)
        }
    }

    Flickable {
        WheelScroll {}
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: Math.min(flick.width, 720)
            x: Math.max(0, (flick.width - width) / 2)
            spacing: 18

            StyledText {
                visible: !(root.s.ytmusicapi ?? true)
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: ClockStyle.colError
                text: Translation.tr("python-ytmusicapi is not installed, so search will not work. Install it with: sudo pacman -S python-ytmusicapi")
            }
            StyledText {
                visible: !(root.s.mpv ?? true) || !(root.s.yt_dlp ?? true)
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: ClockStyle.colError
                text: Translation.tr("mpv and yt-dlp are both needed to play music.")
            }

            ClockFormToggle {
                Layout.fillWidth: true
                symbol: "radio"
                label: Translation.tr("Keep playing similar songs")
                description: Translation.tr("When the queue runs out, continue with YouTube Music's radio")
                checked: root.s.autoplay_radio ?? true
                onToggled: checked => MusicService.saveSettings({ "autoplay_radio": checked })
            }

            ClockFormToggle {
                Layout.fillWidth: true
                symbol: "download"
                label: Translation.tr("Download songs I like")
                description: Translation.tr("Liking a song also saves it for offline. Downloads use %1 now and are never removed by the limit below.").arg(Fmt.bytes(MusicService.dlBytes))
                checked: root.s.auto_download_likes ?? false
                onToggled: checked => MusicService.saveSettings({ "auto_download_likes": checked })
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                StyledText { text: Translation.tr("Keep played songs on disk"); color: ClockStyle.colOnBackground; font.weight: Font.Medium }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: Translation.tr("Saved songs start instantly and play offline. The oldest are removed when the limit is reached.")
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: root.capChoices
                        delegate: ClockChip {
                            required property var modelData
                            label: modelData.label
                            selected: (root.s.audio_cache_mb ?? 1024) === modelData.mb
                            onClicked: MusicService.saveSettings({ "audio_cache_mb": modelData.mb })
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                StyledText { text: Translation.tr("Stored on this computer"); color: ClockStyle.colPrimary; font.weight: Font.Medium }
                Cache { what: "audio"; label: Translation.tr("Songs"); hint: Translation.tr("Audio kept for instant and offline playback") }
                Cache { what: "art"; label: Translation.tr("Covers"); hint: Translation.tr("Album art, capped at %1 MB").arg(root.s.art_cache_mb ?? 200) }
                Cache { what: "lyrics"; label: Translation.tr("Lyrics"); hint: Translation.tr("Synced and plain lyrics") }
                Cache { what: "search"; label: Translation.tr("Searches"); hint: Translation.tr("Results are reused for an hour") }
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Translation.tr("Settings are saved to %1").arg(root.s.path ?? "")
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
            }
            StyledText {
                visible: MusicService.saveError !== ""
                text: MusicService.saveError
                color: ClockStyle.colError
            }
        }
    }
}
