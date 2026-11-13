import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** A cover with a title under it: a recommendation, an album, a playlist. */
Item {
    id: root

    property string path: ""
    property string title: ""
    property string subtitle: ""
    property real coverSize: 150
    /// An artist: a round picture, no play button, the name centred under it
    property bool round: false
    /// A song or album whose artist names should open their pages; otherwise `subtitle` is plain text
    property var track: null
    property string symbol: "music_note"

    signal activated()

    implicitWidth: root.coverSize
    implicitHeight: root.coverSize + 52

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RoundedCover {
            Layout.preferredWidth: root.coverSize
            Layout.preferredHeight: root.coverSize
            radius: root.round ? root.coverSize / 2 : ClockStyle.radiusLarge
            symbol: root.round ? "person" : root.symbol
            path: root.path
            scale: area.containsMouse ? 1.02 : 1
            Behavior on scale { NumberAnimation { duration: Appearance.dur(140); easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: ClockStyle.colScrim
                opacity: area.containsMouse ? 0.32 : 0
                Behavior on opacity { NumberAnimation { duration: Appearance.dur(140) } }
            }
            Rectangle {
                visible: !root.round
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 10
                width: 44
                height: 44
                radius: area.containsMouse ? ClockStyle.radiusFab : 22
                color: ClockStyle.colPrimaryContainer
                Behavior on radius { NumberAnimation { duration: Appearance.dur(160); easing.type: Easing.OutCubic } }
                opacity: area.containsMouse ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Appearance.dur(140) } }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "play_arrow"
                    fill: 1
                    iconSize: 26
                    color: ClockStyle.colOnPrimaryContainer
                }
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: root.title
            color: ClockStyle.colOnBackground
            font.weight: Font.DemiBold
            horizontalAlignment: root.round ? Text.AlignHCenter : Text.AlignLeft
            elide: Text.ElideRight
        }
        ArtistLink {
            visible: root.track !== null
            Layout.fillWidth: true
            Layout.topMargin: -6
            track: root.track
            color: ClockStyle.colOnSurfaceVariant
        }
        StyledText {
            visible: root.track === null
            Layout.fillWidth: true
            Layout.topMargin: -6
            text: root.subtitle
            color: ClockStyle.colOnSurfaceVariant
            font.pixelSize: ClockStyle.textSmall
            horizontalAlignment: root.round ? Text.AlignHCenter : Text.AlignLeft
            elide: Text.ElideRight
        }
    }
}
