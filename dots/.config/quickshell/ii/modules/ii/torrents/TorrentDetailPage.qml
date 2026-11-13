pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "TorrentsFormat.js" as Fmt

/**
 * One torrent in full: where it stands, the options that change how it downloads, which of
 * its files are wanted and how urgently, and who it is talking to.
 */
Item {
    id: root

    required property string hash
    property bool compact: false
    property real layoutWidth: root.width
    signal gone()

    readonly property var torrent: TorrentsService.torrents.find(t => t.hash === root.hash) ?? null
    readonly property var detail: TorrentsService.detail.hash === root.hash ? TorrentsService.detail : null
    readonly property var props: root.detail?.props ?? ({})
    readonly property bool paused: root.torrent ? Fmt.isPaused(root.torrent.state) : false
    readonly property bool done: (root.torrent?.progress ?? 0) >= 1
    property bool removing: false
    readonly property bool wide: root.layoutWidth >= 880

    property bool filled: false
    onTorrentChanged: {
        if (root.torrent === null && TorrentsService.state === "up")
            root.gone();
        else if (root.torrent !== null && !root.filled) {
            root.filled = true;
            root.fillOptions();
        }
    }

    // ── The files, filtered by the box above them ──
    property var fileList: root.detail?.files ?? []
    readonly property var shownFiles: {
        const q = fileSearch.text.trim().toLowerCase();
        return root.fileList.filter(f => q === "" || f.name.toLowerCase().includes(q));
    }
    readonly property var fileByIndex: {
        const m = {};
        root.fileList.forEach(f => m[f.index] = f);
        return m;
    }
    property string filesKey: ""
    function syncFiles(): void {
        const key = root.hash + ":" + root.shownFiles.map(f => f.index).join(",");
        if (key === root.filesKey)
            return;
        root.filesKey = key;
        const y = fileView.contentY;
        fileModel.clear();
        root.shownFiles.forEach(f => fileModel.append({ "fileIndex": f.index }));
        fileView.contentY = y;
    }
    onShownFilesChanged: root.syncFiles()

    function setShown(prio: int): void {
        TorrentsService.setFilePriority(root.hash, prio, root.shownFiles.filter(f => f.priority !== prio).map(f => f.index));
    }

    function limitText(bytes: real): string {
        return bytes > 0 ? String(Math.round(bytes / 1024)) : "";
    }

    function fillOptions(): void {
        if (!root.torrent)
            return;
        downLimit.text = root.limitText(root.torrent.dl_limit);
        upLimit.text = root.limitText(root.torrent.up_limit);
        locationField.text = root.torrent.save_path;
        nameField.text = root.torrent.name;
    }

    Component.onCompleted: {
        TorrentsService.loadDetail(root.hash);
        if (root.torrent !== null) {
            root.filled = true;
            root.fillOptions();
        }
        root.syncFiles();
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: TorrentsService.loadDetail(root.hash)
    }

    ListModel {
        id: fileModel
    }

    component Stat: Rectangle {
        id: stat
        property string label: ""
        property string value: ""
        implicitWidth: 168
        implicitHeight: statCol.implicitHeight + ClockStyle.gap * 2
        radius: ClockStyle.radiusNormal
        color: ClockStyle.colSurfaceHigh
        Column {
            id: statCol
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: ClockStyle.gap
            }
            spacing: 2
            StyledText {
                width: parent.width
                text: stat.label
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
                elide: Text.ElideRight
            }
            StyledText {
                width: parent.width
                text: stat.value
                color: ClockStyle.colOnBackground
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
        }
    }

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
                symbol: root.paused ? "pause" : root.done ? "check" : "downloading"
                title: root.torrent?.name ?? ""
                text: root.torrent ? [Fmt.label(root.torrent.state), Fmt.bytes(root.torrent.size), Fmt.percent(root.torrent.progress)].join("  ·  ") : ""
                trailing: [
                    ClockButton {
                        visible: !root.removing
                        variant: "filled"
                        symbol: root.paused ? "play_arrow" : "pause"
                        label: root.paused ? Translation.tr("Resume") : Translation.tr("Pause")
                        onClicked: TorrentsService.act(root.paused ? "start" : "stop", [root.hash])
                    },
                    ClockButton {
                        visible: !root.removing
                        variant: "tonal"
                        symbol: "delete"
                        label: Translation.tr("Remove")
                        onClicked: root.removing = true
                    },
                    ClockButton {
                        visible: root.removing
                        variant: "filled"
                        danger: true
                        label: Translation.tr("Remove")
                        onClicked: TorrentsService.act("delete", [root.hash])
                    },
                    ClockButton {
                        visible: root.removing
                        variant: "filled"
                        danger: true
                        label: Translation.tr("And delete files")
                        onClicked: TorrentsService.act("delete-files", [root.hash])
                    },
                    ClockButton {
                        visible: root.removing
                        variant: "tonal"
                        label: Translation.tr("Cancel")
                        onClicked: root.removing = false
                    }
                ]
            }

            StyledText {
                Layout.fillWidth: true
                visible: TorrentsService.lastError.length > 0
                text: TorrentsService.lastError
                color: ClockStyle.colError
                wrapMode: Text.WordWrap
            }

            // ── Where it stands ──
            ClockPane {
                Layout.fillWidth: true
                title: Translation.tr("Progress")
                symbol: "donut_large"

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 10
                    radius: 5
                    color: ClockStyle.colSurfaceHigh
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, root.torrent?.progress ?? 0))
                        height: parent.height
                        radius: 5
                        color: root.done ? ClockStyle.colTertiary : ClockStyle.colPrimary
                        Behavior on width { NumberAnimation { duration: Appearance.dur(400) } }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall
                    Stat { label: Translation.tr("Download speed"); value: Fmt.speed(root.torrent?.dlspeed) }
                    Stat { label: Translation.tr("Upload speed"); value: Fmt.speed(root.torrent?.upspeed) }
                    Stat { label: Translation.tr("Time left"); value: root.done ? "—" : (Fmt.eta(root.torrent?.eta) || "—") }
                    Stat { label: Translation.tr("Share ratio"); value: (root.torrent?.ratio ?? 0).toFixed(2) }
                    Stat { label: Translation.tr("Downloaded"); value: Fmt.bytes(root.props.total_downloaded) }
                    Stat { label: Translation.tr("Uploaded"); value: Fmt.bytes(root.props.total_uploaded) }
                    Stat { label: Translation.tr("Seeds"); value: `${root.torrent?.num_seeds ?? 0} of ${root.torrent?.num_complete ?? 0}` }
                    Stat { label: Translation.tr("Peers"); value: `${root.torrent?.num_leechs ?? 0} of ${root.torrent?.num_incomplete ?? 0}` }
                    Stat { label: Translation.tr("Availability"); value: (root.torrent?.availability ?? 0) >= 0 ? (root.torrent?.availability ?? 0).toFixed(2) : "—" }
                    Stat { label: Translation.tr("Active for"); value: Fmt.duration(root.props.time_elapsed) }
                }
            }

            // ── How it downloads ──
            ClockPane {
                Layout.fillWidth: true
                title: Translation.tr("Options")
                symbol: "tune"
                shape: MaterialShape.Shape.SoftBurst

                ClockFormToggle {
                    symbol: "format_list_numbered"
                    label: Translation.tr("Download in order")
                    description: Translation.tr("Fetch pieces from the start of the files, so a video can be watched while it downloads")
                    checked: root.torrent?.seq_dl ?? false
                    onToggled: TorrentsService.op("sequential", [root.hash], "")
                }
                ClockFormToggle {
                    symbol: "swap_horiz"
                    label: Translation.tr("First and last pieces first")
                    description: Translation.tr("Helps media players read the headers of a file early")
                    checked: root.torrent?.f_l_piece_prio ?? false
                    onToggled: TorrentsService.op("first-last", [root.hash], "")
                }
                ClockFormToggle {
                    symbol: "bolt"
                    label: Translation.tr("Force start")
                    description: Translation.tr("Ignore the queue limits for this torrent")
                    checked: root.torrent?.force_start ?? false
                    onToggled: checked => TorrentsService.op("force-start", [root.hash], checked ? "true" : "false")
                }

                StyledText {
                    Layout.topMargin: ClockStyle.gapSmall
                    text: (root.torrent?.priority ?? 0) > 0 ? Translation.tr("Queue position %1").arg(root.torrent.priority) : Translation.tr("Queue")
                    color: ClockStyle.colOnBackground
                    font.weight: Font.DemiBold
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall
                    ClockButton { variant: "tonal"; symbol: "vertical_align_top"; label: Translation.tr("To the top"); onClicked: TorrentsService.queueMove("top", [root.hash]) }
                    ClockButton { variant: "tonal"; symbol: "arrow_upward"; label: Translation.tr("Up"); onClicked: TorrentsService.queueMove("up", [root.hash]) }
                    ClockButton { variant: "tonal"; symbol: "arrow_downward"; label: Translation.tr("Down"); onClicked: TorrentsService.queueMove("down", [root.hash]) }
                    ClockButton { variant: "tonal"; symbol: "vertical_align_bottom"; label: Translation.tr("To the bottom"); onClicked: TorrentsService.queueMove("bottom", [root.hash]) }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: (root.torrent?.priority ?? 0) <= 0
                    text: Translation.tr("Queueing is off in qBittorrent, so the order has no effect. Turn it on in Settings.")
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.topMargin: ClockStyle.gapSmall
                    text: Translation.tr("Speed limits for this torrent")
                    color: ClockStyle.colOnBackground
                    font.weight: Font.DemiBold
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gap
                    ClockFormField {
                        id: downLimit
                        Layout.fillWidth: true
                        symbol: "arrow_downward"
                        caption: Translation.tr("Download, KiB/s")
                        placeholder: Translation.tr("No limit")
                    }
                    ClockFormField {
                        id: upLimit
                        Layout.fillWidth: true
                        symbol: "arrow_upward"
                        caption: Translation.tr("Upload, KiB/s")
                        placeholder: Translation.tr("No limit")
                    }
                    ClockButton {
                        variant: "tonal"
                        symbol: "check"
                        label: Translation.tr("Apply")
                        onClicked: {
                            TorrentsService.op("dl-limit", [root.hash], (parseInt(downLimit.text) || 0) * 1024);
                            TorrentsService.op("up-limit", [root.hash], (parseInt(upLimit.text) || 0) * 1024);
                        }
                    }
                }

                StyledText {
                    Layout.topMargin: ClockStyle.gapSmall
                    text: Translation.tr("Category")
                    color: ClockStyle.colOnBackground
                    font.weight: Font.DemiBold
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall
                    ClockChip {
                        label: Translation.tr("None")
                        selected: (root.torrent?.category ?? "") === ""
                        onClicked: TorrentsService.op("category", [root.hash], "")
                    }
                    Repeater {
                        model: TorrentsService.categories
                        delegate: ClockChip {
                            required property var modelData
                            symbol: "label"
                            label: modelData.name
                            selected: root.torrent?.category === modelData.name
                            onClicked: TorrentsService.op("category", [root.hash], modelData.name)
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gap
                    ClockFormField {
                        id: newCategory
                        Layout.fillWidth: true
                        symbol: "new_label"
                        caption: Translation.tr("New category")
                        placeholder: Translation.tr("Name")
                    }
                    ClockButton {
                        variant: "tonal"
                        symbol: "add"
                        label: Translation.tr("Create and use")
                        enabled: newCategory.text.trim().length > 0
                        onClicked: {
                            const name = newCategory.text.trim();
                            TorrentsService.categoryAdd(name, "");
                            TorrentsService.op("category", [root.hash], name);
                            newCategory.text = "";
                        }
                    }
                }

                StyledText {
                    Layout.topMargin: ClockStyle.gapSmall
                    text: Translation.tr("Location and name")
                    color: ClockStyle.colOnBackground
                    font.weight: Font.DemiBold
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gap
                    ClockFormField {
                        id: locationField
                        Layout.fillWidth: true
                        symbol: "folder"
                        caption: Translation.tr("Save folder")
                    }
                    ClockButton {
                        variant: "tonal"
                        symbol: "drive_file_move"
                        label: Translation.tr("Move")
                        enabled: locationField.text.trim().length > 0 && locationField.text.trim() !== root.torrent?.save_path
                        onClicked: TorrentsService.op("location", [root.hash], locationField.text.trim())
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gap
                    ClockFormField {
                        id: nameField
                        Layout.fillWidth: true
                        symbol: "edit"
                        caption: Translation.tr("Name")
                    }
                    ClockButton {
                        variant: "tonal"
                        symbol: "check"
                        label: Translation.tr("Rename")
                        enabled: nameField.text.trim().length > 0 && nameField.text.trim() !== root.torrent?.name
                        onClicked: TorrentsService.op("rename", [root.hash], nameField.text.trim())
                    }
                }
            }

            // ── Which files, and how soon ──
            ClockPane {
                Layout.fillWidth: true
                title: Translation.tr("Files")
                symbol: "folder_open"
                shape: MaterialShape.Shape.Clover4Leaf
                count: root.fileList.length

                ClockFormField {
                    id: fileSearch
                    Layout.fillWidth: true
                    symbol: "search"
                    caption: Translation.tr("Filter files")
                    placeholder: Translation.tr("Part of a name")
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall
                    StyledText {
                        height: ClockStyle.buttonHeight
                        verticalAlignment: Text.AlignVCenter
                        text: fileSearch.text.trim().length > 0 ? Translation.tr("%1 shown:").arg(root.shownFiles.length) : Translation.tr("All files:")
                        color: ClockStyle.colSubtext
                    }
                    ClockButton { variant: "tonal"; symbol: "block"; label: Translation.tr("Skip"); onClicked: root.setShown(0) }
                    ClockButton { variant: "tonal"; symbol: "download"; label: Translation.tr("Normal"); onClicked: root.setShown(1) }
                    ClockButton { variant: "tonal"; symbol: "keyboard_arrow_up"; label: Translation.tr("High"); onClicked: root.setShown(6) }
                    ClockButton { variant: "tonal"; symbol: "keyboard_double_arrow_up"; label: Translation.tr("Maximum"); onClicked: root.setShown(7) }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Math.min(440, Math.max(60, fileModel.count * 48 + ClockStyle.gap * 2))
                    radius: ClockStyle.radiusNormal
                    color: ClockStyle.colSurface
                    clip: true

                    ListView {
                        WheelScroll {}
                        id: fileView
                        anchors.fill: parent
                        anchors.margins: ClockStyle.gapSmall
                        clip: true
                        spacing: 2
                        boundsBehavior: Flickable.StopAtBounds
                        model: fileModel
                        delegate: Rectangle {
                            id: fileRow
                            required property int fileIndex
                            readonly property var file: root.fileByIndex[fileIndex]
                            width: ListView.view.width
                            height: file ? 44 : 0
                            visible: file !== undefined
                            radius: ClockStyle.radiusSmall
                            color: fileHover.hovered ? ClockStyle.colSurfaceHigh : "transparent"
                            HoverHandler { id: fileHover }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: ClockStyle.gap
                                spacing: ClockStyle.gap

                                ClockIconButton {
                                    size: 32
                                    iconSize: 22
                                    symbol: (fileRow.file?.priority ?? 0) > 0 ? "check_box" : "check_box_outline_blank"
                                    colIcon: (fileRow.file?.priority ?? 0) > 0 ? ClockStyle.colPrimary : ClockStyle.colSubtext
                                    tooltip: (fileRow.file?.priority ?? 0) > 0 ? Translation.tr("Do not download") : Translation.tr("Download")
                                    onClicked: TorrentsService.setFilePriority(root.hash, (fileRow.file?.priority ?? 0) > 0 ? 0 : 1, [fileRow.file.index])
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 2
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: fileRow.file?.name ?? ""
                                        elide: Text.ElideMiddle
                                        color: (fileRow.file?.priority ?? 0) > 0 ? ClockStyle.colOnBackground : ClockStyle.colSubtext
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 3
                                        radius: 1.5
                                        color: ClockStyle.colSurfaceHighest
                                        Rectangle {
                                            width: parent.width * (fileRow.file?.progress ?? 0)
                                            height: parent.height
                                            radius: 1.5
                                            color: ClockStyle.colPrimary
                                        }
                                    }
                                }
                                StyledText {
                                    text: Fmt.bytes(fileRow.file?.size)
                                    color: ClockStyle.colSubtext
                                    font.pixelSize: ClockStyle.textSmall
                                }
                                StyledText {
                                    Layout.preferredWidth: 40
                                    horizontalAlignment: Text.AlignRight
                                    text: Fmt.percent(fileRow.file?.progress)
                                    color: ClockStyle.colSubtext
                                    font.pixelSize: ClockStyle.textSmall
                                }
                                ClockChip {
                                    enabled: (fileRow.file?.priority ?? 0) > 0
                                    label: Fmt.priorityLabel(fileRow.file?.priority ?? 1)
                                    selected: (fileRow.file?.priority ?? 1) > 1
                                    onClicked: TorrentsService.setFilePriority(root.hash, Fmt.nextPriority(fileRow.file.priority), [fileRow.file.index])
                                }
                            }
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.detail === null
                    text: Translation.tr("Loading…")
                    color: ClockStyle.colSubtext
                }
            }

            // ── Who it talks to ──
            ClockPane {
                Layout.fillWidth: true
                visible: (root.detail?.trackers.length ?? 0) > 0
                title: Translation.tr("Trackers")
                symbol: "dns"
                count: root.detail?.trackers.length ?? 0
                Repeater {
                    model: root.detail?.trackers ?? []
                    delegate: RowLayout {
                        id: trackerRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: ClockStyle.gap
                        StyledText {
                            Layout.fillWidth: true
                            text: trackerRow.modelData.url
                            elide: Text.ElideMiddle
                            color: ClockStyle.colOnBackground
                        }
                        StyledText {
                            text: trackerRow.modelData.msg || (trackerRow.modelData.status === 2 ? Translation.tr("Working") : trackerRow.modelData.status === 4 ? Translation.tr("Not working") : trackerRow.modelData.status === 3 ? Translation.tr("Updating") : Translation.tr("Not contacted"))
                            color: trackerRow.modelData.status === 4 ? ClockStyle.colError : ClockStyle.colSubtext
                            font.pixelSize: ClockStyle.textSmall
                        }
                    }
                }
                RowLayout {
                    spacing: ClockStyle.gapSmall
                    ClockButton { variant: "text"; symbol: "campaign"; label: Translation.tr("Ask trackers for peers"); onClicked: TorrentsService.act("reannounce", [root.hash]) }
                    ClockButton { variant: "text"; symbol: "fact_check"; label: Translation.tr("Force recheck"); onClicked: TorrentsService.act("recheck", [root.hash]) }
                }
            }

            ClockPane {
                Layout.fillWidth: true
                visible: (root.detail?.peers.length ?? 0) > 0
                title: Translation.tr("Peers")
                symbol: "group"
                shape: MaterialShape.Shape.SoftBurst
                count: root.detail?.peers.length ?? 0
                Repeater {
                    model: root.detail?.peers ?? []
                    delegate: RowLayout {
                        id: peerRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: ClockStyle.gap
                        StyledText {
                            Layout.preferredWidth: 150
                            text: peerRow.modelData.ip
                            color: ClockStyle.colOnBackground
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: peerRow.modelData.client
                            color: ClockStyle.colSubtext
                            font.pixelSize: ClockStyle.textSmall
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.preferredWidth: 44
                            horizontalAlignment: Text.AlignRight
                            text: Fmt.percent(peerRow.modelData.progress)
                            color: ClockStyle.colSubtext
                            font.pixelSize: ClockStyle.textSmall
                        }
                        StyledText {
                            Layout.preferredWidth: 90
                            horizontalAlignment: Text.AlignRight
                            text: peerRow.modelData.dl > 0 ? "↓ " + Fmt.speed(peerRow.modelData.dl) : ""
                            color: ClockStyle.colPrimary
                            font.pixelSize: ClockStyle.textSmall
                        }
                        StyledText {
                            Layout.preferredWidth: 90
                            horizontalAlignment: Text.AlignRight
                            text: peerRow.modelData.up > 0 ? "↑ " + Fmt.speed(peerRow.modelData.up) : ""
                            color: ClockStyle.colTertiary
                            font.pixelSize: ClockStyle.textSmall
                        }
                    }
                }
            }

            ClockPane {
                Layout.fillWidth: true
                title: Translation.tr("About")
                symbol: "info"
                Flow {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall
                    Stat { implicitWidth: 260; label: Translation.tr("Hash"); value: root.hash }
                    Stat { label: Translation.tr("Added"); value: Fmt.date(root.props.addition_date) }
                    Stat { label: Translation.tr("Finished"); value: Fmt.date(root.props.completion_date) || "—" }
                    Stat { label: Translation.tr("Created"); value: Fmt.date(root.props.creation_date) || "—" }
                    Stat { label: Translation.tr("Created by"); value: root.props.created_by || "—" }
                    Stat { label: Translation.tr("Piece size"); value: Fmt.bytes(root.props.piece_size) }
                    Stat { label: Translation.tr("Pieces"); value: `${root.props.pieces_have ?? 0} of ${root.props.pieces_num ?? 0}` }
                    Stat { label: Translation.tr("Private"); value: root.props.is_private ? Translation.tr("Yes") : Translation.tr("No") }
                    Stat { implicitWidth: 400; label: Translation.tr("Comment"); value: root.props.comment || "—" }
                }
            }
        }
    }
}
