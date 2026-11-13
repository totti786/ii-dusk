pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "TorrentsFormat.js" as Fmt

/** The torrents with their progress, under a banner that shows the speeds. */
Item {
    id: root

    property bool compact: false
    property real layoutWidth: root.width
    signal addRequested()
    signal torrentOpened(string hash)

    property string filter: "all"
    property string category: ""
    property string sortBy: "added"
    property bool reversed: false
    property var selected: ({})
    readonly property var selectedHashes: Object.keys(root.selected).filter(h => root.selected[h])
    readonly property bool up: TorrentsService.state === "up"

    readonly property var shown: {
        const q = search.text.trim().toLowerCase();
        const list = TorrentsService.torrents.filter(t => (root.filter === "all" || Fmt.group(t.state) === root.filter)
            && (root.category === "" || t.category === root.category)
            && (q === "" || t.name.toLowerCase().includes(q)));
        const by = {
            "added": (a, b) => b.added_on - a.added_on,
            "name": (a, b) => a.name.localeCompare(b.name),
            "progress": (a, b) => b.progress - a.progress,
            "speed": (a, b) => (b.dlspeed + b.upspeed) - (a.dlspeed + a.upspeed),
            "size": (a, b) => b.size - a.size,
            "queue": (a, b) => (a.priority <= 0 ? 1e9 : a.priority) - (b.priority <= 0 ? 1e9 : b.priority)
        };
        list.sort(by[root.sortBy]);
        return root.reversed ? list.reverse() : list;
    }
    readonly property var filters: [
        { id: "all", label: Translation.tr("All"), count: TorrentsService.torrents.length },
        { id: "downloading", label: Translation.tr("Downloading"), count: TorrentsService.downloadingCount },
        { id: "seeding", label: Translation.tr("Seeding"), count: TorrentsService.seedingCount },
        { id: "paused", label: Translation.tr("Paused"), count: TorrentsService.pausedCount },
        { id: "errored", label: Translation.tr("Errors"), count: TorrentsService.erroredCount }
    ]
    readonly property var sorts: [
        { id: "added", symbol: "schedule", label: Translation.tr("Newest") },
        { id: "name", symbol: "sort_by_alpha", label: Translation.tr("Name") },
        { id: "progress", symbol: "percent", label: Translation.tr("Progress") },
        { id: "speed", symbol: "speed", label: Translation.tr("Speed") },
        { id: "size", symbol: "hard_drive", label: Translation.tr("Size") },
        { id: "queue", symbol: "format_list_numbered", label: Translation.tr("Queue") }
    ]

    readonly property var byHash: {
        const m = {};
        TorrentsService.torrents.forEach(t => m[t.hash] = t);
        return m;
    }
    readonly property var blank: ({ "hash": "", "name": "", "state": "error", "progress": 0, "size": 0, "dlspeed": 0, "upspeed": 0, "eta": 0, "ratio": 0, "category": "" })

    // The list is fed by hashes and only rebuilt when the order or the members change, so the
    // two-second refresh moves bars and numbers without resetting the scroll position
    property string shownKey: ""
    function syncShown(): void {
        const key = root.shown.map(t => t.hash).join(",");
        if (key === root.shownKey)
            return;
        root.shownKey = key;
        const y = list.contentY;
        shownModel.clear();
        root.shown.forEach(t => shownModel.append({ "hash": t.hash }));
        list.contentY = y;
    }
    onShownChanged: root.syncShown()
    Component.onCompleted: root.syncShown()

    ListModel {
        id: shownModel
    }

    function toggleSelected(hash: string): void {
        const next = Object.assign({}, root.selected);
        next[hash] = !next[hash];
        root.selected = next;
    }

    function selectAll(on: bool): void {
        const next = {};
        if (on)
            root.shown.forEach(t => next[t.hash] = true);
        root.selected = next;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: ClockStyle.paneGap

        ClockHero {
            Layout.fillWidth: true
            compact: root.compact
            symbol: !root.up ? "cloud_off" : TorrentsService.downloadingCount > 0 ? "downloading" : "cloud_done"
            title: TorrentsService.state === "unknown" ? Translation.tr("Looking for qBittorrent…")
                : TorrentsService.state === "down" ? Translation.tr("qBittorrent is not running")
                : TorrentsService.state === "denied" ? Translation.tr("qBittorrent wants a password")
                : TorrentsService.downloadingCount > 0 ? Translation.tr("%1 downloading").arg(TorrentsService.downloadingCount)
                : TorrentsService.torrents.length === 0 ? Translation.tr("No torrents yet")
                : Translation.tr("Everything is up to date")
            text: TorrentsService.state === "down" ? Translation.tr("Nothing is listening at %1. Start it to see and add torrents.").arg(TorrentsService.address)
                : TorrentsService.state === "denied" ? Translation.tr("Turn on \"Bypass authentication for clients on localhost\" in qBittorrent's web interface settings.")
                : root.up ? Translation.tr("↓ %1   ↑ %2   ·   %3 total downloaded, %4 uploaded")
                    .arg(Fmt.speed(TorrentsService.transfer.dl_info_speed)).arg(Fmt.speed(TorrentsService.transfer.up_info_speed))
                    .arg(Fmt.bytes(TorrentsService.transfer.dl_info_data)).arg(Fmt.bytes(TorrentsService.transfer.up_info_data))
                : ""
            trailing: [
                ClockButton {
                    visible: TorrentsService.state === "down"
                    variant: "filled"
                    symbol: "play_arrow"
                    label: Translation.tr("Start qBittorrent")
                    onClicked: TorrentsService.startService()
                },
                ClockButton {
                    visible: root.up
                    variant: TorrentsService.altSpeed ? "filled" : "tonal"
                    symbol: "speed"
                    label: TorrentsService.altSpeed ? Translation.tr("Slow mode on") : Translation.tr("Slow mode")
                    onClicked: TorrentsService.toggleAltSpeed()
                },
                ClockButton {
                    visible: root.up
                    variant: "tonal"
                    symbol: "add_link"
                    label: Translation.tr("Add")
                    onClicked: root.addRequested()
                }
            ]
        }

        // ── Find, filter, sort ──
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.up && TorrentsService.torrents.length > 0
            spacing: ClockStyle.gapSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gap
                ClockFormField {
                    id: search
                    Layout.fillWidth: true
                    symbol: "search"
                    caption: Translation.tr("Search torrents")
                    placeholder: Translation.tr("Name")
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gap

                Flow {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: ClockStyle.gapSmall
                    Repeater {
                        model: root.filters
                        delegate: ClockChip {
                            required property var modelData
                            label: modelData.label
                            count: modelData.count
                            selected: root.filter === modelData.id
                            onClicked: root.filter = modelData.id
                        }
                    }
                    Item { width: ClockStyle.gap; height: 1; visible: TorrentsService.categories.length > 0 }
                    Repeater {
                        model: TorrentsService.categories
                        delegate: ClockChip {
                            required property var modelData
                            symbol: "label"
                            label: modelData.name
                            selected: root.category === modelData.name
                            onClicked: root.category = root.category === modelData.name ? "" : modelData.name
                        }
                    }
                }

                // Ordering is one control, not a second row of chips
                RowLayout {
                    Layout.alignment: Qt.AlignTop
                    spacing: 2
                    ClockChip {
                        id: sortChip
                        symbol: root.sorts.find(o => o.id === root.sortBy)?.symbol ?? "sort"
                        label: root.sorts.find(o => o.id === root.sortBy)?.label ?? ""
                        onClicked: sortMenu.popup(0, sortChip.height + 4)

                        TorrentSortMenu {
                            id: sortMenu
                            options: root.sorts
                            current: root.sortBy
                            onPicked: id => root.sortBy = id
                        }
                    }
                    ClockIconButton {
                        size: ClockStyle.chipHeight
                        iconSize: 20
                        symbol: "swap_vert"
                        toggled: root.reversed
                        tooltip: Translation.tr("Reverse the order")
                        onClicked: root.reversed = !root.reversed
                    }
                }
            }
        }

        // ── Bulk actions, while something is ticked ──
        Rectangle {
            Layout.fillWidth: true
            visible: root.selectedHashes.length > 0
            implicitHeight: bulk.implicitHeight + ClockStyle.gap * 2
            radius: ClockStyle.radiusLarge
            color: ClockStyle.colSecondaryContainer

            Flow {
                id: bulk
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: ClockStyle.gap
                }
                spacing: ClockStyle.gapSmall

                StyledText {
                    height: ClockStyle.buttonHeight
                    verticalAlignment: Text.AlignVCenter
                    text: Translation.tr("%1 selected").arg(root.selectedHashes.length)
                    color: ClockStyle.colOnSecondaryContainer
                    font.weight: Font.DemiBold
                }
                ClockButton {
                    variant: "text"
                    symbol: "pause"
                    label: Translation.tr("Pause")
                    onClicked: TorrentsService.act("stop", root.selectedHashes)
                }
                ClockButton {
                    variant: "text"
                    symbol: "play_arrow"
                    label: Translation.tr("Resume")
                    onClicked: TorrentsService.act("start", root.selectedHashes)
                }
                ClockButton {
                    variant: "text"
                    symbol: "vertical_align_top"
                    label: Translation.tr("To the top")
                    onClicked: TorrentsService.queueMove("top", root.selectedHashes)
                }
                ClockButton {
                    variant: "text"
                    symbol: "fact_check"
                    label: Translation.tr("Force recheck")
                    onClicked: TorrentsService.act("recheck", root.selectedHashes)
                }
                ClockButton {
                    variant: "text"
                    danger: true
                    symbol: "delete"
                    label: Translation.tr("Remove")
                    onClicked: { TorrentsService.act("delete", root.selectedHashes); root.selectAll(false); }
                }
                ClockButton {
                    variant: "text"
                    symbol: "select_all"
                    label: Translation.tr("Everything shown")
                    onClicked: root.selectAll(true)
                }
                ClockButton {
                    variant: "text"
                    symbol: "close"
                    label: Translation.tr("Clear")
                    onClicked: root.selectAll(false)
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: TorrentsService.lastError.length > 0
            text: TorrentsService.lastError
            color: ClockStyle.colError
            font.pixelSize: ClockStyle.textSmall
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.up && TorrentsService.torrents.length > 0
            radius: ClockStyle.radiusCard
            color: ClockStyle.colPane
            clip: true

            ListView {
                WheelScroll {}
                id: list
                anchors.fill: parent
                anchors.margins: ClockStyle.gap
                clip: true
                spacing: ClockStyle.gapSmall
                boundsBehavior: Flickable.StopAtBounds
                model: shownModel
                cacheBuffer: 400
                delegate: TorrentRow {
                    required property string hash
                    width: ListView.view.width
                    visible: root.byHash[hash] !== undefined
                    height: visible ? implicitHeight : 0
                    torrent: root.byHash[hash] ?? root.blank
                    selected: root.selected[hash] === true
                    onSelectToggled: root.toggleSelected(hash)
                    onOpened: root.torrentOpened(hash)
                }
            }

            ClockEmptyState {
                anchors.centerIn: parent
                visible: root.shown.length === 0
                symbol: "filter_alt_off"
                shapeSize: ClockStyle.emptyShapeSmall
                title: Translation.tr("Nothing here")
                subtitle: Translation.tr("No torrent matches")
            }
        }

        ClockEmptyState {
            Layout.alignment: Qt.AlignHCenter
            visible: root.up && TorrentsService.torrents.length === 0
            symbol: "downloading"
            title: Translation.tr("Add your first torrent")
            subtitle: Translation.tr("Paste a magnet link on the Add tab")
        }

        Item {
            Layout.fillHeight: true
            visible: !root.up || TorrentsService.torrents.length === 0
        }
    }
}
