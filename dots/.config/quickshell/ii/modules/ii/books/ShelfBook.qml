import QtQuick

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A book in a collection: the cover with a soft shadow, the title under it. Hovering lifts it
 * and rounds its corners further; a badge shows how far you are once a book is started.
 */
Item {
    id: item

    required property var book
    required property var host
    property int order: 0
    property string rowKey: ""

    readonly property real progress: BooksService.progressFor(item.book)
    readonly property bool started: item.book.page !== null && item.book.page !== undefined && Number(item.book.page) > 0
    readonly property bool chosen: item.host.selectedId === item.book.id
    readonly property bool lifted: pointer.containsMouse || item.chosen
    readonly property bool still: ClockStyle.reducedMotion
    readonly property real coverHeight: item.width * 1.46

    signal activated(var cover)
    signal contextRequested(var point)

    Item {
        id: body
        width: parent.width
        height: item.coverHeight
        transform: Translate { id: slide }

        // Shadow: two soft layers that deepen while the book is lifted.
        Rectangle {
            anchors.fill: cover
            anchors.topMargin: item.lifted ? 14 : 6
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            anchors.bottomMargin: -(item.lifted ? 14 : 6)
            radius: cover.radius
            color: "#000000"
            opacity: item.lifted ? 0.34 : 0.2
            Behavior on anchors.topMargin { enabled: !item.still; NumberAnimation { duration: Appearance.dur(200) } }
            Behavior on anchors.bottomMargin { enabled: !item.still; NumberAnimation { duration: Appearance.dur(200) } }
            Behavior on opacity { enabled: !item.still; NumberAnimation { duration: Appearance.dur(200) } }
        }

        Binding {
            when: item.chosen
            target: item.host
            property: "selectedCover"
            value: cover
        }

        BookCover {
            id: cover
            width: parent.width
            height: parent.height
            y: item.lifted ? -8 : 0
            scale: item.lifted ? 1.04 : 1
            transformOrigin: Item.Bottom
            source: BooksService.coverFor(item.book)
            title: item.book.title
            format: ""
            radius: item.lifted ? 26 : 14

            Behavior on y { enabled: !item.still; NumberAnimation { duration: Appearance.dur(220); easing.type: Easing.OutCubic } }
            Behavior on scale { enabled: !item.still; NumberAnimation { duration: Appearance.dur(220); easing.type: Easing.OutCubic } }
            Behavior on radius { enabled: !item.still; NumberAnimation { duration: Appearance.dur(220); easing.type: Easing.OutCubic } }

            // Progress badge.
            Rectangle {
                visible: item.started && item.progress >= 0
                anchors {
                    right: parent.right
                    top: parent.top
                    margins: 8
                }
                width: badge.implicitWidth + 16
                height: 24
                radius: 12
                color: ClockStyle.colPrimaryContainer

                StyledText {
                    id: badge
                    anchors.centerIn: parent
                    text: Math.round(Math.max(0, item.progress) * 100) + "%"
                    color: ClockStyle.colOnPrimaryContainer
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }

            // Reading without a known length: a dot instead.
            Rectangle {
                visible: item.started && item.progress < 0
                anchors {
                    right: parent.right
                    top: parent.top
                    margins: 10
                }
                width: 12
                height: 12
                radius: 6
                color: ClockStyle.colPrimary
            }
        }
    }

    Column {
        anchors {
            top: body.bottom
            topMargin: 14
            left: parent.left
            right: parent.right
        }
        spacing: 2

        StyledText {
            width: parent.width
            text: item.book.title
            maximumLineCount: 2
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            color: ClockStyle.colOnSurface
            font.pixelSize: ClockStyle.textNormal
            font.weight: Font.Medium
        }
        StyledText {
            width: parent.width
            visible: text.length > 0
            text: item.started && item.book.lastRead ? BooksService.ago(item.book.lastRead) : item.book.format.toUpperCase()
            elide: Text.ElideRight
            color: ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textSmall
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                item.contextRequested(pointer.mapToItem(null, mouse.x, mouse.y));
            else
                item.activated(cover);
        }
    }

    // First sight of a collection: covers rise in one after another, once.
    SequentialAnimation {
        id: intro
        PauseAnimation { duration: Math.min(item.order, 12) * 40 }
        ParallelAnimation {
            NumberAnimation { target: item; property: "opacity"; from: 0; to: 1; duration: Appearance.dur(260) }
            NumberAnimation { target: slide; property: "y"; from: 28; to: 0; duration: Appearance.dur(420); easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        }
    }

    Component.onCompleted: {
        const key = item.rowKey + "/" + item.book.id;
        if (item.still || item.host.seen[key])
            return;
        item.host.seen[key] = true;
        item.opacity = 0;
        slide.y = 28;
        intro.start();
    }
}
