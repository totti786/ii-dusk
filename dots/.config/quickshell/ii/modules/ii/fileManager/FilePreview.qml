pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// Quick look (Space): a big picture or the start of a text file, over the folder.
FocusScope {
    id: root

    property var entry: ({})
    property string text: ""
    property string info: ""
    property var thumbs: ({})
    readonly property string thumb: root.thumbs[(root.entry.path ?? "") + "|" + (root.entry.mtime ?? 0)] ?? ""

    signal closed()
    signal stepRequested(int direction)

    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: root.closed()
    Keys.onSpacePressed: root.closed()
    Keys.onReturnPressed: root.closed()
    Keys.onLeftPressed: root.stepRequested(-1)
    Keys.onRightPressed: root.stepRequested(1)
    Keys.onUpPressed: root.stepRequested(-1)
    Keys.onDownPressed: root.stepRequested(1)

    readonly property bool isImage: root.entry.kind === "image"
    readonly property bool isText: root.entry.kind === "text" || root.entry.kind === "code"

    FileView {
        id: file
        path: root.isText && Number(root.entry.size ?? 0) < 512 * 1024 ? root.entry.path : ""
        onLoaded: root.text = file.text().slice(0, 20000)
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.6
        MouseArea { anchors.fill: parent; onClicked: root.closed() }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(root.width - 80, root.isImage ? root.width - 80 : 760)
        height: root.height - 80
        radius: 28
        color: ClockStyle.colSheet
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                FileIcon { Layout.preferredWidth: 30; Layout.preferredHeight: 30; entry: root.entry; showThumb: false }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.entry.name ?? ""
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        color: ClockStyle.colOnSurface
                        elide: Text.ElideMiddle
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: root.info.length > 0
                        text: root.info
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: ClockStyle.colSubtext
                        elide: Text.ElideRight
                    }
                }
                FmIconButton { symbol: "chevron_left"; tip: qsTr("Previous  (←)"); onClicked: root.stepRequested(-1) }
                FmIconButton { symbol: "chevron_right"; tip: qsTr("Next  (→)"); onClicked: root.stepRequested(1) }
                FmIconButton { symbol: "close"; onClicked: root.closed() }
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Image {
                    visible: root.isImage
                    anchors.fill: parent
                    source: root.isImage ? "file://" + root.entry.path : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    autoTransform: true
                    sourceSize.width: 2000
                    sourceSize.height: 2000
                }
                Flickable {
                    visible: root.isText
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: body.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    WheelScroll {}
                    StyledText {
                        id: body
                        width: parent.width
                        text: root.text.length > 0 ? root.text : qsTr("(empty or too large to preview)")
                        font.family: "monospace"
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        wrapMode: Text.WrapAnywhere
                        color: ClockStyle.colOnSurface
                    }
                }
                ColumnLayout {
                    visible: !root.isImage && !root.isText
                    anchors.centerIn: parent
                    spacing: 10
                    FileIcon {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: root.thumb.length > 0 ? Math.min(root.width - 120, 520) : 120
                        Layout.preferredHeight: root.thumb.length > 0 ? 360 : 120
                        entry: root.entry
                        thumb: root.thumb
                        thumbSize: 640
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.thumb.length === 0
                        text: qsTr("No preview for this type")
                        color: ClockStyle.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }
        }
    }
}
