pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "DownloadsFormat.js" as Fmt

/**
 * Where a link goes in: the field, a preview of what it points to, the format, and the
 * button that queues it.
 */
Rectangle {
    id: root

    property bool compact: false
    property real layoutWidth: root.width
    signal queued()

    readonly property var info: DownloadsService.info
    readonly property bool hasInfo: (info.title ?? "") !== ""
    readonly property var presets: DownloadsService.settings.presets ?? []
    property string preset: DownloadsService.settings.preset ?? "best"
    property bool playlist: false
    property bool subs: DownloadsService.settings.subs ?? false
    readonly property bool audioOnly: presets.find(p => p.id === preset)?.audio ?? false
    readonly property real padding: 0
    readonly property real contentWidth: root.width

    color: "transparent"

    function submit(): void {
        if (link.text.trim().length > 0)
            DownloadsService.probe(link.text);
    }

    function pasteFromClipboard(): void {
        if (!clipProc.running)
            clipProc.running = true;
    }

    Component.onCompleted: {
        if (!root.hasInfo)
            link.focusInput();
    }

    // A fresh playlist link asks about the whole list; a single video never does
    onInfoChanged: root.playlist = Boolean(root.info.playlist)

    Process {
        id: clipProc
        command: ["wl-paste", "--no-newline"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (/^https?:\/\//.test(t)) {
                    link.text = t;
                    root.submit();
                } else {
                    link.focusInput();
                }
            }
        }
    }

    Flickable {
        WheelScroll {}
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + root.padding * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: column
            x: Math.max(root.padding, (flick.width - root.contentWidth) / 2)
            // Before a link is looked up the page is one centred block; after it, the
            // form reads from the top.
            y: 0
            width: root.contentWidth
            spacing: ClockStyle.gapLarge

            ClockHero {
                Layout.fillWidth: true
                compact: root.compact
                symbol: "download"
                title: Translation.tr("Save anything you can link to")
                text: Translation.tr("Videos, playlists, music and plain files from any link. Paste one to begin.")
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: ClockStyle.gap

                ClockFormField {
                    id: link
                    symbol: "link"
                    caption: Translation.tr("Link")
                    placeholder: Translation.tr("https://…")
                    onAccepted: root.submit()
                }
                ClockIconButton {
                    symbol: "content_paste"
                    tooltip: Translation.tr("Paste from clipboard")
                    onClicked: root.pasteFromClipboard()
                }
                ClockButton {
                    variant: "filled"
                    symbol: "search"
                    label: DownloadsService.probing ? Translation.tr("Looking…") : Translation.tr("Look up")
                    enabled: !DownloadsService.probing && link.text.trim().length > 0
                    onClicked: root.submit()
                }
            }

            StyledText {
                visible: DownloadsService.probeError !== ""
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: DownloadsService.probeError
                color: ClockStyle.colError
            }

            // ── Before a link: pick how to save, what works, what finished lately ──
            Item {
                id: heroHolder
                visible: !root.hasInfo && !DownloadsService.probing && DownloadsService.probeError === ""
                Layout.fillWidth: true
                implicitHeight: hero.implicitHeight

            ColumnLayout {
                id: hero
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, Math.max(implicitWidth, 1))
                spacing: ClockStyle.gapLarge

                // Where links come from: a hint, not a control
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Works with")
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                    }
                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: ClockStyle.gap
                        Repeater {
                            model: [
                                { icon: "smart_display", label: "YouTube" },
                                { icon: "graphic_eq", label: "SoundCloud" },
                                { icon: "movie", label: "Vimeo" },
                                { icon: "live_tv", label: "Twitch" },
                                { icon: "public", label: Translation.tr("1,000+ more") }
                            ]
                            delegate: Rectangle {
                                id: site
                                required property var modelData
                                width: 124
                                height: 76
                                radius: ClockStyle.radiusNormal
                                color: ClockStyle.colSurfaceHigh
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    MaterialSymbol {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: site.modelData.icon
                                        iconSize: 26
                                        color: ClockStyle.colPrimary
                                    }
                                    StyledText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: site.modelData.label
                                        color: ClockStyle.colSubtext
                                        font.pixelSize: ClockStyle.textSmall
                                    }
                                }
                            }
                        }
                    }
                }

                // The last few finished downloads, one click to open
                ColumnLayout {
                    visible: DownloadsService.finishedJobs.length > 0
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall
                    StyledText {
                        text: Translation.tr("Recently finished")
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                    }
                    Repeater {
                        model: DownloadsService.finishedJobs.filter(j => j.status === "done").slice(0, 3)
                        delegate: Rectangle {
                            id: recent
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 48
                            radius: ClockStyle.radiusNormal
                            color: recentArea.containsMouse ? ClockStyle.colSurfaceHigh : ClockStyle.colPane
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 12
                                MaterialSymbol {
                                    text: ["mp3", "opus"].includes(recent.modelData.preset) ? "music_note" : "movie"
                                    iconSize: 20
                                    color: ClockStyle.colPrimary
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: recent.modelData.title ?? ""
                                    color: ClockStyle.colOnBackground
                                    elide: Text.ElideRight
                                }
                                MaterialSymbol {
                                    text: "open_in_new"
                                    iconSize: 18
                                    color: ClockStyle.colSubtext
                                }
                            }
                            MouseArea {
                                id: recentArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: DownloadsService.openFile(recent.modelData)
                            }
                        }
                    }
                }
            }
            }

            // ── The preview ─────────────────────────────────────────────
            Rectangle {
                visible: root.hasInfo
                Layout.fillWidth: true
                implicitHeight: previewRow.implicitHeight + ClockStyle.gapLarge * 2
                radius: ClockStyle.radiusCard
                color: ClockStyle.colPane

                RowLayout {
                    id: previewRow
                    anchors.fill: parent
                    anchors.margins: ClockStyle.gapLarge
                    spacing: ClockStyle.gapLarge

                    Rectangle {
                        Layout.preferredWidth: root.compact ? 140 : 240
                        Layout.preferredHeight: Layout.preferredWidth * 9 / 16
                        radius: ClockStyle.radiusLarge
                        color: ClockStyle.colSurfaceHigh
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: root.info.thumbnail ?? ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                        }
                        Rectangle {
                            visible: Fmt.duration(root.info.duration) !== ""
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 6
                            radius: 6
                            color: "#cc000000"
                            implicitWidth: durText.implicitWidth + 12
                            implicitHeight: durText.implicitHeight + 4
                            StyledText {
                                id: durText
                                anchors.centerIn: parent
                                text: Fmt.duration(root.info.duration)
                                color: "white"
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: ClockStyle.gapTiny

                        StyledText {
                            Layout.fillWidth: true
                            text: root.info.title ?? ""
                            color: ClockStyle.colOnBackground
                            font.pixelSize: ClockStyle.textLarge
                            font.weight: Font.Medium
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: [root.info.uploader, root.info.site].filter(s => s).join(" · ")
                            color: ClockStyle.colSubtext
                            elide: Text.ElideRight
                        }
                        StyledText {
                            visible: Boolean(root.info.playlist)
                            text: Translation.tr("Playlist · %1 videos").arg(root.info.count ?? 0)
                            color: ClockStyle.colPrimary
                        }
                    }
                }
            }

            // ── Format ──────────────────────────────────────────────────
            ColumnLayout {
                visible: root.hasInfo && root.info.kind !== "file"
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                StyledText {
                    text: Translation.tr("Format")
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall
                    Repeater {
                        model: root.presets
                        delegate: ClockChip {
                            required property var modelData
                            symbol: modelData.audio ? "music_note" : "videocam"
                            label: modelData.label
                            selected: root.preset === modelData.id
                            onClicked: root.preset = modelData.id
                        }
                    }
                }
            }

            ClockFormToggle {
                visible: root.hasInfo && Boolean(root.info.playlist)
                Layout.fillWidth: true
                symbol: "playlist_play"
                label: Translation.tr("Download the whole playlist")
                description: Translation.tr("Off downloads only the video the link points to")
                checked: root.playlist
                onToggled: checked => root.playlist = checked
            }

            ClockFormToggle {
                visible: root.hasInfo && !root.audioOnly && root.info.kind !== "file"
                Layout.fillWidth: true
                symbol: "subtitles"
                label: Translation.tr("Embed English subtitles")
                description: Translation.tr("Adds them to the file when the video has any")
                checked: root.subs
                onToggled: checked => root.subs = checked
            }

            StyledText {
                visible: DownloadsService.startError !== ""
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: DownloadsService.startError
                color: ClockStyle.colError
            }

            RowLayout {
                visible: root.hasInfo
                Layout.fillWidth: true
                spacing: ClockStyle.gap

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Saves to %1").arg(DownloadsService.settings.dir ?? "")
                    color: ClockStyle.colSubtext
                    elide: Text.ElideMiddle
                }
                ClockButton {
                    variant: "text"
                    label: Translation.tr("Clear")
                    onClicked: {
                        DownloadsService.clearProbe();
                        link.text = "";
                        link.focusInput();
                    }
                }
                ClockButton {
                    variant: "filled"
                    symbol: "download"
                    label: Translation.tr("Download")
                    onClicked: {
                        DownloadsService.start({ preset: root.preset, playlist: root.playlist, subs: root.subs && !root.audioOnly });
                        link.text = "";
                        root.queued();
                    }
                }
            }
        }
    }
}
