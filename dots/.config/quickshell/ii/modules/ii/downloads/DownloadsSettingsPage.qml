pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** Where files go, the default format, and the yt-dlp options worth exposing. */
Rectangle {
    id: root

    property bool compact: false
    property real layoutWidth: root.width

    readonly property var s: DownloadsService.settings
    readonly property real padding: 0
    readonly property real contentWidth: root.width
    readonly property var browsers: ["", "firefox", "chrome", "chromium", "brave", "zen"]
    readonly property bool hasChanges: folder.text !== (s.dir ?? "") || limit.text !== (s.rate_limit ?? "")
        || preset !== (s.preset ?? "best") || browser !== (s.cookies_browser ?? "")
        || parallel !== (s.max_parallel ?? 2) || subs !== (s.subs ?? false) || notify !== (s.notify ?? true)

    property string preset: "best"
    property string browser: ""
    property int parallel: 2
    property bool subs: false
    property bool notify: true

    function load(): void {
        folder.text = s.dir ?? "";
        limit.text = s.rate_limit ?? "";
        preset = s.preset ?? "best";
        browser = s.cookies_browser ?? "";
        parallel = s.max_parallel ?? 2;
        subs = s.subs ?? false;
        notify = s.notify ?? true;
    }

    function save(): void {
        DownloadsService.saveSettings({
            "dir": folder.text, "rate_limit": limit.text, "preset": preset,
            "cookies_browser": browser, "max_parallel": parallel, "subs": subs, "notify": notify
        });
    }

    color: "transparent"
    Component.onCompleted: root.load()
    onSChanged: Qt.callLater(root.load)

    Flickable {
        WheelScroll {}
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + root.padding * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            x: Math.max(root.padding, (flick.width - root.contentWidth) / 2)
            y: root.padding
            width: root.contentWidth
            spacing: ClockStyle.gapLarge

            StyledText {
                visible: !(root.s.yt_dlp ?? true)
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Translation.tr("yt-dlp is not installed. Install it with your package manager to download anything.")
                color: ClockStyle.colError
            }
            StyledText {
                visible: !(root.s.aria2c ?? true)
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Translation.tr("aria2 is not installed, so plain files (ISOs, archives, PDFs) cannot be downloaded. Videos and music still work.")
                color: ClockStyle.colError
            }
            StyledText {
                visible: (root.s.yt_dlp ?? true) && !(root.s.ffmpeg ?? true)
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Translation.tr("ffmpeg is missing, so separate video and audio cannot be merged and audio cannot be converted.")
                color: ClockStyle.colError
            }

            ClockFormField {
                id: folder
                symbol: "folder"
                caption: Translation.tr("Download folder")
                placeholder: "~/Videos/Downloads"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall
                StyledText {
                    text: Translation.tr("Default format")
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall
                    Repeater {
                        model: root.s.presets ?? []
                        delegate: ClockChip {
                            required property var modelData
                            label: modelData.label
                            selected: root.preset === modelData.id
                            onClicked: root.preset = modelData.id
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall
                StyledText {
                    text: Translation.tr("Downloads at the same time")
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall
                    Repeater {
                        model: [1, 2, 3, 4]
                        delegate: ClockChip {
                            required property int modelData
                            label: String(modelData)
                            selected: root.parallel === modelData
                            onClicked: root.parallel = modelData
                        }
                    }
                }
            }

            ClockFormField {
                id: limit
                symbol: "speed"
                caption: Translation.tr("Speed limit")
                placeholder: Translation.tr("None. Write 500K or 2M to cap it")
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall
                StyledText {
                    text: Translation.tr("Use login cookies from")
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall
                    Repeater {
                        model: root.browsers
                        delegate: ClockChip {
                            required property string modelData
                            label: modelData === "" ? Translation.tr("No browser") : modelData.charAt(0).toUpperCase() + modelData.slice(1)
                            selected: root.browser === modelData
                            onClicked: root.browser = modelData
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: Translation.tr("For age-restricted or members-only videos. yt-dlp reads the browser's cookies each time.")
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                }
            }

            ClockFormToggle {
                Layout.fillWidth: true
                symbol: "subtitles"
                label: Translation.tr("Embed English subtitles by default")
                checked: root.subs
                onToggled: checked => root.subs = checked
            }
            ClockFormToggle {
                Layout.fillWidth: true
                symbol: "notifications"
                label: Translation.tr("Notify when a download finishes")
                checked: root.notify
                onToggled: checked => root.notify = checked
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gap
                ClockButton {
                    variant: "filled"
                    label: DownloadsService.saving ? Translation.tr("Saving…") : Translation.tr("Save")
                    enabled: root.hasChanges && !DownloadsService.saving
                    onClicked: root.save()
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: DownloadsService.saveError !== "" ? DownloadsService.saveError
                        : root.hasChanges ? Translation.tr("Unsaved changes") : Translation.tr("Saved to %1").arg(root.s.path ?? "")
                    color: DownloadsService.saveError !== "" ? ClockStyle.colError : ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                }
            }
        }
    }
}
