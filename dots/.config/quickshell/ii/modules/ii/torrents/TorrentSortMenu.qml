import QtQuick
import QtQuick.Controls

import qs.modules.common
import qs.modules.common.widgets

/** The ways to order the torrent list; the current one is ticked. */
Menu {
    id: root

    property var options: []
    property string current: ""
    signal picked(string id)

    readonly property int menuPadding: 6
    padding: menuPadding
    implicitWidth: 200

    background: Item {
        implicitWidth: 200
        implicitHeight: root.contentHeight + root.menuPadding * 2
        StyledRectangularShadow {
            target: sortBackground
        }
        Rectangle {
            id: sortBackground
            anchors.fill: parent
            radius: Appearance.rounding.windowRounding
            color: Appearance.m3colors.m3surfaceContainer
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }
    }

    Repeater {
        model: root.options
        delegate: TorrentMenuItem {
            required property var modelData
            implicitWidth: 188
            symbol: modelData.symbol ?? ""
            text: modelData.label
            current: root.current === modelData.id
            onTriggered: root.picked(modelData.id)
        }
    }
}
