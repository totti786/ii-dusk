pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import Quickshell

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** A magnet link, a web link to a .torrent, or the path of one on disk. */
Item {
    id: root

    property bool compact: false
    property real layoutWidth: root.width
    signal added()

    property string category: ""
    property bool paused: false
    property bool sequential: false
    property bool skipCheck: false

    readonly property string value: link.text.trim()
    readonly property bool isPath: root.value.startsWith("/") || root.value.startsWith("~") || root.value.startsWith("file://")
    readonly property bool valid: /^(magnet:\?|https?:\/\/)/.test(root.value) || (root.isPath && /\.torrent$/i.test(root.value))

    function expandPath(p: string): string {
        if (p.startsWith("file://"))
            return decodeURIComponent(p.substring(7));
        return p.startsWith("~") ? Quickshell.env("HOME") + p.substring(1) : p;
    }

    function submit(): void {
        if (!root.valid || TorrentsService.state !== "up")
            return;
        const opts = { "dir": folder.text.trim(), "category": root.category, "paused": root.paused,
            "sequential": root.sequential, "skipCheck": root.skipCheck };
        if (root.isPath)
            TorrentsService.addFile(root.expandPath(root.value), opts);
        else
            TorrentsService.addUrl(root.value, opts);
        link.text = "";
        root.added();
    }

    // The page can be taller than the window (the options and the Add button sit below the
    // fold on a small one), so it scrolls like Settings does.
    Flickable {
        WheelScroll {}
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: col
        width: flick.width
        spacing: ClockStyle.paneGap

        ClockHero {
            Layout.fillWidth: true
            compact: root.compact
            symbol: "add_link"
            title: Translation.tr("Add a torrent")
            text: Translation.tr("Paste a magnet link, a web link to a .torrent file, or the path of a .torrent file on this computer.")
        }

        ClockPane {
            Layout.fillWidth: true
            title: Translation.tr("Source")
            symbol: "link"

            ClockFormField {
                id: link
                Layout.fillWidth: true
                symbol: "link"
                caption: Translation.tr("Magnet link, web link or file")
                placeholder: Translation.tr("magnet:?xt=urn:btih:…  or  ~/Downloads/file.torrent")
                onAccepted: root.submit()
            }
            ClockFormField {
                id: folder
                Layout.fillWidth: true
                symbol: "folder"
                caption: Translation.tr("Save in (optional)")
                placeholder: Translation.tr("Leave empty for qBittorrent's default folder")
                onAccepted: root.submit()
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.value.length > 0 && !root.valid
                text: Translation.tr("That is not a magnet link, a web link or a path ending in .torrent")
                color: ClockStyle.colError
                font.pixelSize: ClockStyle.textSmall
                wrapMode: Text.WordWrap
            }
            StyledText {
                Layout.fillWidth: true
                visible: TorrentsService.state !== "up"
                text: Translation.tr("qBittorrent is not running. Start it on the Torrents tab first.")
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
                wrapMode: Text.WordWrap
            }
        }

        ClockPane {
            Layout.fillWidth: true
            title: Translation.tr("Options")
            symbol: "tune"
            shape: MaterialShape.Shape.SoftBurst

            ClockFormToggle {
                symbol: "pause_circle"
                label: Translation.tr("Add it paused")
                description: Translation.tr("Choose which files to download first, then start it from its page")
                checked: root.paused
                onToggled: checked => root.paused = checked
            }
            ClockFormToggle {
                symbol: "format_list_numbered"
                label: Translation.tr("Download in order")
                description: Translation.tr("For media you want to start watching early")
                checked: root.sequential
                onToggled: checked => root.sequential = checked
            }
            ClockFormToggle {
                symbol: "fast_forward"
                label: Translation.tr("Skip the file check")
                description: Translation.tr("Only for files you already have in the save folder")
                checked: root.skipCheck
                onToggled: checked => root.skipCheck = checked
            }
            StyledText {
                visible: TorrentsService.categories.length > 0
                Layout.topMargin: ClockStyle.gapSmall
                text: Translation.tr("Category")
                color: ClockStyle.colOnBackground
                font.weight: Font.DemiBold
            }
            Flow {
                Layout.fillWidth: true
                visible: TorrentsService.categories.length > 0
                spacing: ClockStyle.gapSmall
                ClockChip {
                    label: Translation.tr("None")
                    selected: root.category === ""
                    onClicked: root.category = ""
                }
                Repeater {
                    model: TorrentsService.categories
                    delegate: ClockChip {
                        required property var modelData
                        symbol: "label"
                        label: modelData.name
                        selected: root.category === modelData.name
                        onClicked: root.category = modelData.name
                    }
                }
            }
            RowLayout {
                Layout.topMargin: ClockStyle.gapSmall
                spacing: ClockStyle.gapSmall
                ClockButton {
                    variant: "filled"
                    symbol: "add"
                    label: Translation.tr("Add torrent")
                    enabled: root.valid && TorrentsService.state === "up"
                    onClicked: root.submit()
                }
            }
        }

    }
    }
}
