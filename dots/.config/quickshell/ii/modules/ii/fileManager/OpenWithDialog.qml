pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// Pick any installed app to open the selection with, and optionally make it the default.
FmDialog {
    id: root

    property var backend: null
    property string mime: ""
    property string fileName: ""
    property var apps: []
    property string filter: ""
    property bool makeDefault: false

    signal chosen(string appId, bool makeDefault)

    title: qsTr("Open “%1” with").arg(root.fileName)
    cardWidth: 480

    Component.onCompleted: {
        opacity = 1;
        root.backend.request("allApps", {}, { done: m => root.apps = m.apps });
        search.input.forceActiveFocus();
    }

    readonly property var shown: {
        const q = root.filter.trim().toLowerCase();
        return q.length === 0 ? root.apps : root.apps.filter(a => a.name.toLowerCase().includes(q));
    }

    FmField {
        id: search
        Layout.fillWidth: true
        placeholder: qsTr("Search apps")
        onEdited: root.filter = text
    }
    ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: 300
        clip: true
        model: root.shown
        boundsBehavior: Flickable.StopAtBounds
        delegate: Rectangle {
            id: app
            required property var modelData
            width: ListView.view.width
            height: 46
            radius: Appearance.rounding.small
            color: ma.containsMouse ? ClockStyle.colSurfaceHover : "transparent"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                spacing: 12
                Image {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    source: app.modelData.icon ? Quickshell.iconPath(app.modelData.icon, "application-x-executable") : ""
                    sourceSize.width: 56
                    sourceSize.height: 56
                }
                StyledText {
                    Layout.fillWidth: true
                    text: app.modelData.name
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: ClockStyle.colOnSurface
                    elide: Text.ElideRight
                }
            }
            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.chosen(app.modelData.id, root.makeDefault)
            }
        }
    }
    FmChip {
        text: qsTr("Always use for this type (%1)").arg(root.mime)
        checked: root.makeDefault
        onClicked: root.makeDefault = !root.makeDefault
    }

    actions: [FmButton { text: qsTr("Cancel"); onClicked: root.close() }]
}
