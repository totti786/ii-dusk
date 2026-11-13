import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** A book offered by a source: cover, title, author. Clicking opens its page. */
Item {
    id: root

    required property var book

    signal activated()

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: 8
        }
        spacing: 8
        scale: pointer.containsMouse ? 1.025 : 1
        transformOrigin: Item.Center

        Behavior on scale {
            enabled: !ClockStyle.reducedMotion
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }

        BookCover {
            Layout.fillWidth: true
            Layout.preferredHeight: width * 1.5
            source: root.book.thumb
            title: root.book.title
            format: (root.book.formats?.[0]?.ext ?? "")

            Rectangle {
                anchors {
                    right: parent.right
                    bottom: parent.bottom
                    margins: 8
                }
                width: 30
                height: 30
                radius: 15
                color: "#aa000000"
                visible: pointer.containsMouse

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "download"
                    iconSize: 18
                    color: "white"
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.book.title
            maximumLineCount: 2
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            color: ClockStyle.colOnSurface
            font.pixelSize: ClockStyle.textNormal
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignLeft
        }

        StyledText {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.book.author ?? ""
            elide: Text.ElideRight
            color: ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textSmall
        }

        Item { Layout.fillHeight: true }
    }
}
