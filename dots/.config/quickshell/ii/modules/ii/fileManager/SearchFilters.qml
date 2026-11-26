pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.services

/// The filter chips under the toolbar while searching: type, date, size and file contents.
Item {
    id: root

    property string kind: ""
    property int days: 0
    property int minMb: 0
    property bool content: false

    signal menuRequested(string which, real x, real y)
    signal contentToggled()
    signal cleared()

    implicitHeight: 40

    readonly property var kindNames: ({ image: Translation.tr("Images"), video: Translation.tr("Videos"), audio: Translation.tr("Audio"), document: Translation.tr("Documents"),
        archive: Translation.tr("Archives"), code: Translation.tr("Code"), folder: Translation.tr("Folders") })
    readonly property bool any: root.kind.length > 0 || root.days > 0 || root.minMb > 0

    RowLayout {
        anchors.fill: parent
        spacing: 8

        FmChip {
            id: kindChip
            text: root.kind.length > 0 ? root.kindNames[root.kind] : Translation.tr("Type")
            icon: "category"
            checked: root.kind.length > 0
            onClicked: { const p = kindChip.mapToItem(null, 0, kindChip.height + 4); root.menuRequested("kind", p.x, p.y); }
        }
        FmChip {
            id: dayChip
            text: root.days === 1 ? Translation.tr("Last 24 hours") : root.days === 7 ? Translation.tr("Last 7 days") : root.days === 30 ? Translation.tr("Last 30 days") : root.days === 365 ? Translation.tr("Last year") : Translation.tr("Date")
            icon: "event"
            checked: root.days > 0
            onClicked: { const p = dayChip.mapToItem(null, 0, dayChip.height + 4); root.menuRequested("days", p.x, p.y); }
        }
        FmChip {
            id: sizeChip
            text: root.minMb >= 1000 ? Translation.tr("Over 1 GB") : root.minMb > 0 ? Translation.tr("Over %1 MB").arg(root.minMb) : Translation.tr("Size")
            icon: "straighten"
            checked: root.minMb > 0
            onClicked: { const p = sizeChip.mapToItem(null, 0, sizeChip.height + 4); root.menuRequested("size", p.x, p.y); }
        }
        FmChip {
            text: Translation.tr("File contents")
            icon: "manage_search"
            checked: root.content
            onClicked: root.contentToggled()
        }
        FmChip {
            visible: root.any
            text: Translation.tr("Clear")
            icon: "filter_alt_off"
            onClicked: root.cleared()
        }
        Item { Layout.fillWidth: true }
    }
}
