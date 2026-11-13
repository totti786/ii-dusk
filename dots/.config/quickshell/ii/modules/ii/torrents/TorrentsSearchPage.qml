pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import Quickshell

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "TorrentsFormat.js" as Fmt

/**
 * Search through qBittorrent's own search plugins (The Pirate Bay, Jackett and so on). Results
 * stream in while the sites answer; a row adds the torrent, opens its page or copies its link.
 */
Item {
    id: root

    property bool compact: false
    property real layoutWidth: root.width
    property bool active: true
    signal added()

    property string sortBy: "seeds"
    /// Links already sent to qBittorrent from here, so a row can say so
    property var sent: ({})
    readonly property bool up: TorrentsService.state === "up"
    readonly property bool running: TorrentsService.searchState === "running"
    readonly property var enabledPlugins: TorrentsService.searchPlugins.filter(p => p.enabled)

    readonly property var sorts: [
        { id: "seeds", label: Translation.tr("Seeders") },
        { id: "size", label: Translation.tr("Size") },
        { id: "name", label: Translation.tr("Name") },
        { id: "date", label: Translation.tr("Newest") }
    ]

    readonly property var shown: {
        const by = {
            "seeds": (a, b) => b.seeds - a.seeds,
            "size": (a, b) => b.size - a.size,
            "name": (a, b) => a.name.localeCompare(b.name),
            "date": (a, b) => (b.date ?? 0) - (a.date ?? 0)
        };
        // The same torrent often comes from several sites: keep the best-seeded copy
        const seen = {};
        const rows = [];
        TorrentsService.searchResults.forEach(r => {
            const key = r.url.startsWith("magnet:") ? (r.url.match(/btih:([0-9a-zA-Z]+)/)?.[1] ?? r.url).toLowerCase() : r.url;
            const at = seen[key];
            if (at === undefined) {
                seen[key] = rows.length;
                rows.push(r);
            } else if (r.seeds > rows[at].seeds) {
                rows[at] = r;
            }
        });
        return rows.sort(by[root.sortBy]);
    }

    function go(): void {
        if (!root.up || query.text.trim().length === 0)
            return;
        TorrentsService.search(query.text, "");
    }

    function send(row: var): void {
        TorrentsService.addUrl(row.url, ({}));
        const next = Object.assign({}, root.sent);
        next[row.url] = true;
        root.sent = next;
    }

    onActiveChanged: if (root.active) TorrentsService.loadSearchPlugins()
    Component.onCompleted: TorrentsService.loadSearchPlugins()

    ColumnLayout {
        anchors.fill: parent
        spacing: ClockStyle.paneGap

        ClockHero {
            Layout.fillWidth: true
            compact: root.compact
            symbol: "travel_explore"
            title: !root.up ? Translation.tr("qBittorrent is not running")
                : root.running ? Translation.tr("Searching…")
                : TorrentsService.searchState === "idle" ? Translation.tr("Search for torrents")
                : Translation.tr("%1 results for “%2”").arg(root.shown.length).arg(TorrentsService.searchQuery)
            text: !root.up ? Translation.tr("Start it on the Torrents tab, then come back to search.")
                : root.enabledPlugins.length === 0 ? Translation.tr("Every search site is turned off. Turn one on below.")
                : Translation.tr("Searching %1.").arg(root.enabledPlugins.map(p => p.title).join(", "))
            trailing: [
                ClockButton {
                    visible: root.running
                    variant: "tonal"
                    symbol: "stop"
                    label: Translation.tr("Stop")
                    onClicked: TorrentsService.stopSearch()
                }
            ]
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gap
            ClockFormField {
                id: query
                Layout.fillWidth: true
                symbol: "search"
                caption: Translation.tr("Search")
                placeholder: Translation.tr("A title, a release name…")
                onAccepted: root.go()
            }
            ClockButton {
                Layout.alignment: Qt.AlignBottom
                variant: "filled"
                symbol: "search"
                label: Translation.tr("Search")
                enabled: root.up && query.text.trim().length > 0 && root.enabledPlugins.length > 0
                onClicked: root.go()
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall

            StyledText {
                height: ClockStyle.chipHeight
                verticalAlignment: Text.AlignVCenter
                text: Translation.tr("Sites")
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
            }
            Repeater {
                model: TorrentsService.searchPlugins
                delegate: ClockChip {
                    required property var modelData
                    symbol: modelData.enabled ? "check" : ""
                    label: modelData.title
                    selected: modelData.enabled
                    onClicked: TorrentsService.setSearchPlugin(modelData.name, !modelData.enabled)
                }
            }
            ClockChip {
                symbol: "sync"
                label: Translation.tr("Update sites")
                onClicked: TorrentsService.updateSearchPlugins()
            }
        }

        Flow {
            Layout.fillWidth: true
            visible: TorrentsService.searchResults.length > 0
            spacing: ClockStyle.gapSmall
            StyledText {
                height: ClockStyle.chipHeight
                verticalAlignment: Text.AlignVCenter
                text: Translation.tr("Sort by")
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
            }
            Repeater {
                model: root.sorts
                delegate: ClockChip {
                    required property var modelData
                    label: modelData.label
                    selected: root.sortBy === modelData.id
                    onClicked: root.sortBy = modelData.id
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: TorrentsService.searchState === "error" || TorrentsService.lastError.length > 0
            text: TorrentsService.searchState === "error" ? TorrentsService.searchError : TorrentsService.lastError
            color: ClockStyle.colError
            font.pixelSize: ClockStyle.textSmall
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.shown.length > 0
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
                model: root.shown
                cacheBuffer: 400
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool sentAlready: root.sent[row.modelData.url] === true
                    width: ListView.view.width
                    implicitHeight: rowLayout.implicitHeight + ClockStyle.gap * 2
                    height: implicitHeight
                    radius: ClockStyle.radiusLarge
                    color: hover.hovered ? ClockStyle.colSurfaceHighest : ClockStyle.colSurfaceHigh
                    Behavior on color { ColorAnimation { duration: Appearance.dur(120) } }

                    HoverHandler {
                        id: hover
                    }

                    RowLayout {
                        id: rowLayout
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: ClockStyle.gap
                        }
                        spacing: ClockStyle.gap

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 3
                            StyledText {
                                Layout.fillWidth: true
                                text: row.modelData.name
                                color: ClockStyle.colOnBackground
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: ClockStyle.textSmall
                                color: ClockStyle.colSubtext
                                elide: Text.ElideRight
                                text: {
                                    const parts = [];
                                    if (row.modelData.size >= 0)
                                        parts.push(Fmt.bytes(row.modelData.size));
                                    parts.push("↑ " + Math.max(0, row.modelData.seeds) + "   ↓ " + Math.max(0, row.modelData.peers));
                                    parts.push(row.modelData.engine ?? "");
                                    return parts.filter(p => p.length > 0).join("  ·  ");
                                }
                            }
                        }

                        ClockIconButton {
                            size: 36
                            iconSize: 20
                            symbol: "content_copy"
                            tooltip: Translation.tr("Copy the link")
                            onClicked: Quickshell.clipboardText = row.modelData.url
                        }
                        ClockIconButton {
                            visible: (row.modelData.page ?? "").startsWith("http")
                            size: 36
                            iconSize: 20
                            symbol: "open_in_new"
                            tooltip: Translation.tr("Open its page")
                            onClicked: Qt.openUrlExternally(row.modelData.page)
                        }
                        ClockButton {
                            variant: row.sentAlready ? "tonal" : "filled"
                            symbol: row.sentAlready ? "check" : "download"
                            label: row.sentAlready ? Translation.tr("Added") : Translation.tr("Download")
                            enabled: root.up && !row.sentAlready
                            onClicked: root.send(row.modelData)
                        }
                    }
                }
            }
        }

        ClockEmptyState {
            Layout.alignment: Qt.AlignHCenter
            visible: root.shown.length === 0 && !root.running
            symbol: TorrentsService.searchState === "idle" ? "travel_explore" : "search_off"
            title: TorrentsService.searchState === "idle" ? Translation.tr("Find something to download")
                : Translation.tr("Nothing found")
            subtitle: TorrentsService.searchState === "idle" ? Translation.tr("Type a name and press Enter")
                : Translation.tr("Try fewer words, or turn on another site")
        }

        Item {
            Layout.fillHeight: true
            visible: root.shown.length === 0
        }
    }
}
