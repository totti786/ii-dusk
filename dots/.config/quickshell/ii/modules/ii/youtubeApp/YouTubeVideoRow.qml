pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** A compact, keyboard-accessible result row shared by Home and Search. */
Rectangle {
    id: root

    required property var modelData
    property var service: null

    implicitHeight: 104
    radius: ClockStyle.radiusSmall
    color: pointer.containsMouse
        ? ColorUtils.transparentize(ClockStyle.colPrimary, 0.90)
        : "transparent"
    border.width: activeFocus ? 1 : 0
    border.color: ColorUtils.transparentize(ClockStyle.colPrimary, 0.38)
    activeFocusOnTab: true

    Accessible.role: Accessible.Button
    Accessible.name: String(root.modelData?.title ?? Translation.tr("YouTube video"))
    Accessible.description: Translation.tr("Play in mpv")

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.service?.play(root.modelData);
            event.accepted = true;
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.service?.play(root.modelData)
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.gapSmall
        spacing: ClockStyle.gap

        Item {
            Layout.preferredWidth: 160
            Layout.minimumWidth: 124
            Layout.preferredHeight: 90
            Layout.minimumHeight: 70
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                anchors.fill: parent
                radius: ClockStyle.radiusSmall
                color: ClockStyle.colSurface
                clip: true

                Image {
                    id: thumbnail
                    anchors.fill: parent
                    source: String(root.modelData?.thumbnail ?? "")
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 480
                    sourceSize.height: 270
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: ClockStyle.gapTiny
                    visible: thumbnail.status !== Image.Ready

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "video_library"
                        iconSize: 30
                        fill: 1
                        color: ClockStyle.colPrimary
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Video")
                        font.pixelSize: ClockStyle.textSmall
                        color: ClockStyle.colOnSurfaceVariant
                    }
                }

                Rectangle {
                    anchors {
                        right: parent.right
                        bottom: parent.bottom
                        margins: ClockStyle.gapSmall
                    }
                    implicitWidth: durationText.implicitWidth + ClockStyle.gap
                    implicitHeight: 22
                    radius: ClockStyle.radiusSmall
                    color: ColorUtils.transparentize(ClockStyle.colOnSurface, 0.22)
                    visible: durationText.text.length > 0

                    StyledText {
                        id: durationText
                        anchors.centerIn: parent
                        text: root.service ? root.service.formatDuration(root.modelData?.duration) : ""
                        color: ClockStyle.colBackground
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    implicitWidth: 40
                    implicitHeight: 40
                    radius: ClockStyle.radiusFull
                    color: ColorUtils.transparentize(ClockStyle.colPrimaryContainer, 0.12)
                    visible: pointer.containsMouse || root.activeFocus

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "play_arrow"
                        iconSize: ClockStyle.iconNormal
                        fill: 1
                        color: ClockStyle.colOnPrimaryContainer
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: ClockStyle.gapTiny

            StyledText {
                Layout.fillWidth: true
                text: String(root.modelData?.title ?? Translation.tr("Untitled video"))
                color: ClockStyle.colOnSurface
                font.pixelSize: ClockStyle.textNormal
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: String(root.modelData?.channel ?? "")
                visible: text.length > 0
                color: ClockStyle.colOnSurfaceVariant
                font.pixelSize: ClockStyle.textSmall
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: root.service
                    ? [root.service.formatViews(root.modelData?.views), root.service.formatDuration(root.modelData?.duration)]
                        .filter(part => part.length > 0).join("  ·  ")
                    : ""
                visible: text.length > 0
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
                elide: Text.ElideRight
            }
        }

        ClockIconButton {
            symbol: "play_arrow"
            tooltip: Translation.tr("Play in mpv")
            scaleBehaviorEnabled: false
            Accessible.name: Translation.tr("Play %1 in mpv").arg(root.modelData?.title ?? Translation.tr("video"))
            onClicked: root.service?.play(root.modelData)
        }

        ClockIconButton {
            symbol: "open_in_new"
            tooltip: Translation.tr("Open on YouTube")
            scaleBehaviorEnabled: false
            Accessible.name: Translation.tr("Open %1 on YouTube").arg(root.modelData?.title ?? Translation.tr("video"))
            onClicked: root.service?.openExternal(root.modelData)
        }

        ClockIconButton {
            symbol: "content_copy"
            tooltip: Translation.tr("Copy link")
            scaleBehaviorEnabled: false
            Accessible.name: Translation.tr("Copy link for %1").arg(root.modelData?.title ?? Translation.tr("video"))
            onClicked: root.service?.copyLink(root.modelData)
        }
    }
}
