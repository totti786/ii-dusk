import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// A surface card with an icon, a title and a value in its header; the content fills the rest.
Rectangle {
    id: root

    property string title: ""
    property string value: ""
    property string symbol: ""
    property color accent: ClockStyle.colPrimary
    property real padding: 12
    /// Shows an expand button in the header; the page decides what expanding does
    property bool expandable: false
    property bool expanded: false
    signal expandToggled()
    default property alias content: normalBody.data
    /// What fills the card instead of its normal content while it is expanded
    property Component expandedContent: null
    /// Controls that sit in the header line, between the title and the value
    property alias headerExtras: extras.data

    radius: ClockStyle.radiusLarge
    color: root.activeFocus && MonitorService.keyboardNav ? ClockStyle.colSurfaceHighest : ClockStyle.colSurface
    border.width: root.activeFocus && MonitorService.keyboardNav ? 2 : 0
    border.color: ClockStyle.colPrimary

    // Tab reaches the card, Enter expands it, Esc folds it back
    activeFocusOnTab: root.expandable
    Keys.onReturnPressed: event => { if (root.expandable) { root.expandToggled(); event.accepted = true; } }
    Keys.onEnterPressed: event => { if (root.expandable) { root.expandToggled(); event.accepted = true; } }
    Keys.onEscapePressed: event => {
        if (root.expandable && root.expanded) {
            root.expandToggled();
            event.accepted = true;
        } else {
            event.accepted = false;
        }
    }

    RowLayout {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.padding
        spacing: 8

        MaterialSymbol {
            visible: root.symbol !== ""
            text: root.symbol
            iconSize: 18
            color: root.accent
        }
        StyledText {
            Layout.fillWidth: root.title !== "" && extras.children.length === 0
            text: root.title
            color: ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textSmall
            font.letterSpacing: 0.8
            elide: Text.ElideRight
        }
        RowLayout {
            id: extras
            Layout.fillWidth: extras.children.length > 0
            Layout.alignment: Qt.AlignVCenter
            spacing: 8
        }
        StyledText {
            text: root.value
            color: ClockStyle.colOnBackground
            font.weight: Font.Medium
            font.pixelSize: ClockStyle.textSmall + 1
        }
        Rectangle {
            visible: root.expandable
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26
            radius: 13
            color: expandArea.containsMouse ? ClockStyle.colSurfaceHover : "transparent"
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.expanded ? "close_fullscreen" : "open_in_full"
                iconSize: 16
                color: ClockStyle.colSubtext
            }
            MouseArea {
                id: expandArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expandToggled()
            }
        }
    }

    Item {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.margins: root.padding
        anchors.topMargin: 8

        Item {
            id: normalBody
            anchors.fill: parent
            visible: !(root.expanded && root.expandedContent !== null)
        }
        Loader {
            anchors.fill: parent
            active: root.expanded && root.expandedContent !== null
            sourceComponent: root.expandedContent
        }
    }
}
