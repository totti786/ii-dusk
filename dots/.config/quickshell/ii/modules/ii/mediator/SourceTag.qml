import QtQuick

import qs.modules.common
import qs.modules.common.widgets

/** Says where a title lives when it is not a local file ("jellyfin"); nothing for local ones. */
Rectangle {
    id: root

    property string source: "local"
    /// Compact: a bare icon, for the corner of a poster
    property bool compact: false

    readonly property bool shown: root.source !== "" && root.source !== "local"
    readonly property string name: root.source === "jellyfin" ? "Jellyfin"
        : root.source.charAt(0).toUpperCase() + root.source.slice(1)

    visible: root.shown
    implicitWidth: row.implicitWidth + (root.compact ? 12 : 16)
    implicitHeight: 24
    radius: Appearance.rounding.full
    color: Appearance.colors.colTertiaryContainer

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: "cloud"
            fill: 1
            iconSize: 14
            color: Appearance.colors.colOnTertiaryContainer
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.compact
            text: root.name
            color: Appearance.colors.colOnTertiaryContainer
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
        }
    }
}
