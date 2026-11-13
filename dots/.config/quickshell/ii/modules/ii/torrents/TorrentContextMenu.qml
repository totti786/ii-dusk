pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "TorrentsFormat.js" as Fmt

/**
 * What a right-click on a torrent offers: the things you reach for most without opening
 * the torrent. Built on the first right-click (see TorrentRow), like the text-field menu.
 */
Menu {
    id: root

    required property var torrent
    signal detailsRequested()
    signal removeRequested()

    readonly property string hash: root.torrent.hash
    readonly property bool paused: Fmt.isPaused(root.torrent.state)
    readonly property bool missing: root.torrent.state === "missingFiles"
    readonly property bool done: (root.torrent.progress ?? 0) >= 1

    property int menuPadding: 6
    readonly property int outerRadius: Appearance.rounding.windowRounding
    readonly property int innerRadius: Math.max(0, outerRadius - menuPadding)

    implicitWidth: 240
    padding: menuPadding

    background: Item {
        implicitWidth: 240
        implicitHeight: root.contentHeight + root.menuPadding * 2

        StyledRectangularShadow {
            target: menuBackground
        }
        Rectangle {
            id: menuBackground
            anchors.fill: parent
            radius: root.outerRadius
            color: Appearance.m3colors.m3surfaceContainer
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }
    }

    function copy(text: string): void {
        Quickshell.execDetached(["wl-copy", text]);
    }

    function magnet(): string {
        if (root.torrent.magnet_uri)
            return root.torrent.magnet_uri;
        return `magnet:?xt=urn:btih:${root.hash}&dn=${encodeURIComponent(root.torrent.name ?? "")}`;
    }

    // ── What is wrong comes first ──
    TorrentMenuItem {
        visible: root.missing
        height: visible ? implicitHeight : 0
        symbol: "fact_check"
        text: Translation.tr("Force recheck")
        onTriggered: TorrentsService.act("recheck", [root.hash])
    }
    TorrentMenuRule {
        visible: root.missing
        height: visible ? implicitHeight : 0
    }

    TorrentMenuItem {
        symbol: root.paused ? "play_arrow" : "pause"
        text: root.paused ? Translation.tr("Resume") : Translation.tr("Pause")
        onTriggered: TorrentsService.act(root.paused ? "start" : "stop", [root.hash])
    }
    TorrentMenuItem {
        visible: !root.done
        height: visible ? implicitHeight : 0
        symbol: "bolt"
        text: root.torrent.force_start ? Translation.tr("Stop forcing") : Translation.tr("Force start")
        onTriggered: TorrentsService.op("force-start", [root.hash], !root.torrent.force_start)
    }
    TorrentMenuItem {
        symbol: "fact_check"
        visible: !root.missing
        height: visible ? implicitHeight : 0
        text: Translation.tr("Force recheck")
        onTriggered: TorrentsService.act("recheck", [root.hash])
    }
    TorrentMenuItem {
        symbol: "campaign"
        text: Translation.tr("Force reannounce")
        onTriggered: TorrentsService.act("reannounce", [root.hash])
    }

    TorrentMenuRule {}

    TorrentMenuItem {
        visible: !root.done
        height: visible ? implicitHeight : 0
        symbol: root.torrent.seq_dl ? "check_box" : "check_box_outline_blank"
        text: Translation.tr("Download in order")
        onTriggered: TorrentsService.op("sequential", [root.hash], "")
    }
    TorrentMenuItem {
        visible: !root.done
        height: visible ? implicitHeight : 0
        symbol: root.torrent.f_l_piece_prio ? "check_box" : "check_box_outline_blank"
        text: Translation.tr("First and last pieces first")
        onTriggered: TorrentsService.op("first-last", [root.hash], "")
    }
    TorrentMenuRule {
        visible: !root.done
        height: visible ? implicitHeight : 0
    }

    TorrentMenuItem {
        symbol: "folder_open"
        text: Translation.tr("Open folder")
        onTriggered: Quickshell.execDetached(["xdg-open", root.torrent.save_path])
    }
    TorrentMenuItem {
        symbol: "link"
        text: Translation.tr("Copy magnet link")
        onTriggered: root.copy(root.magnet())
    }
    TorrentMenuItem {
        symbol: "content_copy"
        text: Translation.tr("Copy name")
        onTriggered: root.copy(root.torrent.name ?? "")
    }

    TorrentMenuRule {}

    TorrentMenuItem {
        symbol: "info"
        text: Translation.tr("Details")
        onTriggered: root.detailsRequested()
    }
    TorrentMenuItem {
        symbol: "delete"
        text: Translation.tr("Remove…")
        destructive: true
        onTriggered: root.removeRequested()
    }
}
