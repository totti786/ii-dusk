pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** What mpv is playing right now (from the mediator daemon) with the controls to drive it. */
RoundedBox {
    id: root

    readonly property var s: MediatorService.now
    property color surface: Appearance.colors.colLayer2
    readonly property real frac: root.s && root.s.duration > 0 ? Math.min(1, root.s.position / root.s.duration) : 0

    visible: root.s !== null
    implicitHeight: 76
    radius: Appearance.rounding.large
    color: root.surface

    component Ctl: Rectangle {
        id: ctl
        property string icon
        property bool primary: false
        property string tip
        signal clicked()
        implicitWidth: primary ? 44 : 36
        implicitHeight: implicitWidth
        radius: implicitWidth / 2
        color: primary ? Appearance.colors.colPrimary : (area.containsMouse ? Appearance.colors.colLayer3 : "transparent")
        MaterialSymbol {
            anchors.centerIn: parent
            text: ctl.icon
            fill: ctl.primary ? 1 : 0
            iconSize: ctl.primary ? 26 : 22
            color: ctl.primary ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ctl.clicked()
        }
    }

    RowLayout {
        anchors { fill: parent; leftMargin: 12; rightMargin: 14; topMargin: 8; bottomMargin: 8 }
        spacing: 14

        RoundedBox {
            Layout.preferredHeight: 56
            Layout.preferredWidth: root.s?.still ? 100 : 38
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer3
            Image {
                anchors.fill: parent
                source: root.s?.still ? root.s.still : MediatorService.posterUrl(root.s?.poster)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 240
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: 2
            StyledText {
                Layout.fillWidth: true
                text: root.s ? (root.s.title ?? root.s.media_title) : ""
                elide: Text.ElideRight
                color: Appearance.colors.colOnLayer0
                font.weight: Font.DemiBold
            }
            StyledText {
                Layout.fillWidth: true
                text: {
                    if (!root.s)
                        return "";
                    const bits = [];
                    if (root.s.code)
                        bits.push(root.s.code);
                    if (root.s.episode_title)
                        bits.push(root.s.episode_title);
                    return bits.length ? bits.join(" · ") : (root.s.label ?? "");
                }
                elide: Text.ElideRight
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }

        ColumnLayout {
            Layout.preferredWidth: 360
            spacing: 4
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 2
                Ctl { icon: "skip_previous"; onClicked: MediatorService.control("prev", null) }
                Ctl { icon: "replay_10"; onClicked: MediatorService.control("seek", -10) }
                Ctl {
                    primary: true
                    icon: root.s?.paused ? "play_arrow" : "pause"
                    onClicked: MediatorService.control("toggle", null)
                }
                Ctl { icon: "forward_10"; onClicked: MediatorService.control("seek", 10) }
                Ctl { icon: "skip_next"; onClicked: MediatorService.control("next", null) }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                StyledText {
                    text: MediatorService.clock(root.s?.position ?? 0)
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 5
                    radius: 3
                    color: Appearance.colors.colOutlineVariant
                    Rectangle {
                        width: parent.width * root.frac
                        height: parent.height
                        radius: 3
                        color: Appearance.colors.colPrimary
                    }
                    MouseArea {
                        anchors { fill: parent; topMargin: -8; bottomMargin: -8 }
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => MediatorService.control("seek_to", (mouse.x / width) * (root.s?.duration ?? 0))
                    }
                }
                StyledText {
                    text: MediatorService.clock(root.s?.duration ?? 0)
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }
            }
        }

        Ctl { icon: "stop"; onClicked: MediatorService.control("stop", null) }
    }
}
