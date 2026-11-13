pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** What the player has learned: the artists you finish and like score up, ones you skip score down. */
Item {
    id: root

    readonly property var t: MusicService.taste
    readonly property real best: Math.max(1, ...root.t.artists.map(a => a.score))

    ClockEmptyState {
        visible: root.t.artists.length === 0
        anchors.centerIn: parent
        symbol: "insights"
        title: Translation.tr("Still learning")
        subtitle: Translation.tr("Play, finish, skip and like songs and this page fills in")
    }

    ColumnLayout {
        visible: root.t.artists.length > 0
        anchors.fill: parent
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
                text: Translation.tr("%1 songs and %2 hours so far, %3 skips. This shapes Made for you and what plays after your queue.")
                    .arg(root.t.tracks).arg(root.t.hours).arg(root.t.skipped)
            }
            ClockButton {
                variant: "text"
                symbol: "restart_alt"
                label: Translation.tr("Forget it")
                onClicked: MusicService.resetTaste()
            }
        }

        ListView {
            WheelScroll {}
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: root.t.artists
            boundsBehavior: Flickable.StopAtBounds

            delegate: RowLayout {
                id: row
                required property var modelData
                width: ListView.view.width
                spacing: 12

                StyledText {
                    Layout.preferredWidth: 180
                    text: row.modelData.name
                    color: ClockStyle.colOnBackground
                    elide: Text.ElideRight
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 8
                    radius: height / 2
                    color: ClockStyle.colSurfaceHighest
                    Rectangle {
                        width: parent.width * Math.max(0.04, row.modelData.score / root.best)
                        height: parent.height
                        radius: height / 2
                        color: ClockStyle.colPrimary
                    }
                }
                StyledText {
                    Layout.preferredWidth: 110
                    horizontalAlignment: Text.AlignRight
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                    text: Translation.tr("%1 plays").arg(row.modelData.plays) + (row.modelData.likes > 0 ? " · ♥ " + row.modelData.likes : "")
                }
            }
        }
    }
}
