pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "TorrentsFormat.js" as Fmt

/**
 * One torrent: what it is called, how far along, how fast, and the buttons for it. Clicking
 * the row opens its files and trackers underneath.
 */
Rectangle {
    id: root

    required property var torrent
    /// Ticked for a bulk action
    property bool selected: false
    /// Asking before a removal: the row shows its own choices instead of the buttons
    property bool removing: false

    signal opened()
    signal selectToggled()

    readonly property string group: Fmt.group(root.torrent.state)
    readonly property bool paused: Fmt.isPaused(root.torrent.state)
    readonly property bool done: root.torrent.progress >= 1

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + ClockStyle.gap * 2
    radius: ClockStyle.radiusLarge
    color: root.selected ? ClockStyle.colSecondaryContainer : hover.hovered ? ClockStyle.colSurfaceHighest : ClockStyle.colSurfaceHigh
    Behavior on color { ColorAnimation { duration: Appearance.dur(120) } }

    HoverHandler {
        id: hover
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: ClockStyle.gap
        }
        spacing: ClockStyle.gapSmall

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gap

            ClockIconButton {
                size: 32
                iconSize: 20
                symbol: root.selected ? "check_box" : "check_box_outline_blank"
                toggled: false
                colIcon: root.selected ? ClockStyle.colOnSecondaryContainer : ClockStyle.colSubtext
                tooltip: Translation.tr("Select")
                onClicked: root.selectToggled()
            }

            ClockBadge {
                size: 44
                text: root.group === "downloading" ? "download" : root.group === "seeding" ? "upload"
                    : root.group === "errored" ? "error" : root.done ? "check" : "pause"
                shape: root.group === "downloading" ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                color: root.group === "errored" ? ClockStyle.colError
                    : root.group === "downloading" ? ClockStyle.colPrimary : ClockStyle.colSecondaryContainer
                colSymbol: root.group === "errored" ? ClockStyle.colOnError
                    : root.group === "downloading" ? ClockStyle.colOnPrimary : ClockStyle.colOnSecondaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 3

                StyledText {
                    Layout.fillWidth: true
                    text: root.torrent.name
                    color: ClockStyle.colOnBackground
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 6
                    radius: 3
                    color: ClockStyle.colSurfaceHighest
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, root.torrent.progress))
                        height: parent.height
                        radius: 3
                        color: root.group === "errored" ? ClockStyle.colError : root.done ? ClockStyle.colTertiary : ClockStyle.colPrimary
                        Behavior on width { NumberAnimation { duration: Appearance.dur(400) } }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                    elide: Text.ElideRight
                    text: {
                        const parts = [Fmt.label(root.torrent.state)];
                        parts.push(root.done ? Fmt.bytes(root.torrent.size) : `${Fmt.bytes(root.torrent.size * root.torrent.progress)} of ${Fmt.bytes(root.torrent.size)}  (${Fmt.percent(root.torrent.progress)})`);
                        if (root.torrent.dlspeed > 0)
                            parts.push("↓ " + Fmt.speed(root.torrent.dlspeed));
                        if (root.torrent.upspeed > 0)
                            parts.push("↑ " + Fmt.speed(root.torrent.upspeed));
                        if (!root.done && Fmt.eta(root.torrent.eta) !== "" && root.torrent.dlspeed > 0)
                            parts.push(Fmt.eta(root.torrent.eta) + " left");
                        if (root.torrent.category)
                            parts.push(root.torrent.category);
                        if (root.torrent.ratio > 0)
                            parts.push(Translation.tr("ratio %1").arg(root.torrent.ratio.toFixed(2)));
                        return parts.join("  ·  ");
                    }
                }
            }

            RowLayout {
                visible: !root.removing
                spacing: 0
                ClockIconButton {
                    size: 36
                    iconSize: 20
                    symbol: root.paused ? "play_arrow" : "pause"
                    tooltip: root.paused ? Translation.tr("Resume") : Translation.tr("Pause")
                    onClicked: TorrentsService.act(root.paused ? "start" : "stop", [root.torrent.hash])
                }
                ClockIconButton {
                    size: 36
                    iconSize: 20
                    symbol: "delete"
                    tooltip: Translation.tr("Remove")
                    onClicked: root.removing = true
                }
                ClockIconButton {
                    size: 36
                    iconSize: 20
                    symbol: "chevron_right"
                    tooltip: Translation.tr("Open")
                    onClicked: root.opened()
                }
            }

            RowLayout {
                visible: root.removing
                spacing: ClockStyle.gapSmall
                ClockButton {
                    variant: "tonal"
                    label: Translation.tr("Remove")
                    onClicked: { TorrentsService.act("delete", [root.torrent.hash]); root.removing = false; }
                }
                ClockButton {
                    variant: "tonal"
                    danger: true
                    label: Translation.tr("Remove and delete files")
                    onClicked: { TorrentsService.act("delete-files", [root.torrent.hash]); root.removing = false; }
                }
                ClockButton {
                    variant: "text"
                    label: Translation.tr("Cancel")
                    onClicked: root.removing = false
                }
            }
        }
    }

    // Right-click: the common things without opening the torrent. Built on first use; a list
    // of a few dozen rows should not each carry a menu nobody opened.
    Loader {
        id: contextMenu
        active: false
        function popup(x, y) {
            contextMenu.active = true;
            contextMenu.item.popup(x, y);
        }
        sourceComponent: TorrentContextMenu {
            parent: root
            torrent: root.torrent
            onDetailsRequested: root.opened()
            onRemoveRequested: root.removing = true
        }
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: point => contextMenu.popup(point.position.x, point.position.y)
    }

    MouseArea {
        // The row's own click, under the buttons and the details
        anchors.fill: parent
        z: -1
        cursorShape: Qt.PointingHandCursor
        onClicked: root.opened()
    }
}
