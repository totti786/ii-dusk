pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// The tab strip; hidden by its owner while there is a single tab.
Item {
    id: root

    property var tabs: []
    property int current: 0

    signal activated(int index)
    signal closed(int index)
    signal added()

    implicitHeight: 42

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 6

        Repeater {
            model: root.tabs
            delegate: Rectangle {
                id: tab
                required property var modelData
                required property int index
                readonly property bool active: tab.index === root.current
                Layout.preferredWidth: Math.min(220, Math.max(110, (root.width - 80) / Math.max(1, root.tabs.length)))
                Layout.preferredHeight: 34
                radius: Appearance.rounding.full
                color: tab.active ? ClockStyle.colSecondaryContainer : (tabArea.containsMouse ? ClockStyle.colSurfaceHover : "transparent")

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 6
                    spacing: 6
                    MaterialSymbol {
                        text: tab.modelData.path.startsWith("trash:") ? "delete" : "folder"
                        iconSize: 18
                        fill: tab.active ? 1 : 0
                        color: tab.active ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: tab.modelData.title
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: tab.active ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                        elide: Text.ElideRight
                    }
                    FmIconButton {
                        visible: root.tabs.length > 1
                        size: 24
                        iconSize: 16
                        symbol: "close"
                        onClicked: root.closed(tab.index)
                    }
                }
                MouseArea {
                    id: tabArea
                    anchors.fill: parent
                    z: -1
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onClicked: m => m.button === Qt.MiddleButton ? root.closed(tab.index) : root.activated(tab.index)
                }
            }
        }
        FmIconButton {
            size: 32
            iconSize: 20
            symbol: "add"
            tip: qsTr("New tab")
            onClicked: root.added()
        }
        Item { Layout.fillWidth: true }
    }
}
