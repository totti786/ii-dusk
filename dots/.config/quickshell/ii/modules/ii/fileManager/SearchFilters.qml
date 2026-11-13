pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

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

    readonly property var kindNames: ({ image: qsTr("Images"), video: qsTr("Videos"), audio: qsTr("Audio"), document: qsTr("Documents"),
        archive: qsTr("Archives"), code: qsTr("Code"), folder: qsTr("Folders") })
    readonly property bool any: root.kind.length > 0 || root.days > 0 || root.minMb > 0

    RowLayout {
        anchors.fill: parent
        spacing: 8

        FmChip {
            id: kindChip
            text: root.kind.length > 0 ? root.kindNames[root.kind] : qsTr("Type")
            icon: "category"
            checked: root.kind.length > 0
            onClicked: { const p = kindChip.mapToItem(null, 0, kindChip.height + 4); root.menuRequested("kind", p.x, p.y); }
        }
        FmChip {
            id: dayChip
            text: root.days === 1 ? qsTr("Last 24 hours") : root.days === 7 ? qsTr("Last 7 days") : root.days === 30 ? qsTr("Last 30 days") : root.days === 365 ? qsTr("Last year") : qsTr("Date")
            icon: "event"
            checked: root.days > 0
            onClicked: { const p = dayChip.mapToItem(null, 0, dayChip.height + 4); root.menuRequested("days", p.x, p.y); }
        }
        FmChip {
            id: sizeChip
            text: root.minMb >= 1000 ? qsTr("Over 1 GB") : root.minMb > 0 ? qsTr("Over %1 MB").arg(root.minMb) : qsTr("Size")
            icon: "straighten"
            checked: root.minMb > 0
            onClicked: { const p = sizeChip.mapToItem(null, 0, sizeChip.height + 4); root.menuRequested("size", p.x, p.y); }
        }
        FmChip {
            text: qsTr("File contents")
            icon: "manage_search"
            checked: root.content
            onClicked: root.contentToggled()
        }
        FmChip {
            visible: root.any
            text: qsTr("Clear")
            icon: "filter_alt_off"
            onClicked: root.cleared()
        }
        Item { Layout.fillWidth: true }
    }
}
