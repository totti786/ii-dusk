pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One source in a stream list: the direct stream or a torrent. Shared by the Streaming tab's
 * title page and the library's stream dialog, so both read the same: quality badge, the
 * release name with its tags (HDR, codec, source), then seeders and size.
 */
Rectangle {
    id: root

    /// A stream object from StremioService.streamRows
    property var stream: ({})
    /// The row the keyboard cursor is on
    property bool selected: false
    /// The recommended pick (best quality with healthy seeders)
    property bool recommended: false

    signal activated()
    signal downloadRequested()

    readonly property bool direct: root.stream?.direct === true
    readonly property string quality: String(root.stream?.quality ?? "")
    readonly property string release: String(root.stream?.filename || root.stream?.title || "")
    readonly property int seeds: Number(root.stream?.seeds ?? 0)

    // Release tags worth showing, read from the file name
    readonly property var tags: {
        const n = root.release.toLowerCase();
        const out = [];
        if (/\b(hdr10\+?|hdr|dolby.?vision|dv)\b/.test(n))
            out.push(/dolby|\bdv\b/.test(n) ? "Dolby Vision" : "HDR");
        if (/\b(x265|h\.?265|hevc)\b/.test(n))
            out.push("HEVC");
        else if (/\b(x264|h\.?264|avc)\b/.test(n))
            out.push("H.264");
        if (/\b(remux)\b/.test(n))
            out.push("Remux");
        else if (/\b(blu-?ray|bdrip|brrip)\b/.test(n))
            out.push("BluRay");
        else if (/\b(web-?dl|webrip|web)\b/.test(n))
            out.push("WEB");
        else if (/\b(hdtv)\b/.test(n))
            out.push("HDTV");
        if (/\b(atmos|truehd|dts|ddp?5\.1|dd\+|eac3)\b/.test(n))
            out.push("Surround");
        return out.slice(0, 4);
    }

    function qualityColor(q): color {
        return q === "2160p" || q === "4k" ? Appearance.colors.colTertiaryContainer
            : q === "1080p" ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer;
    }
    function qualityOn(q): color {
        return q === "2160p" || q === "4k" ? Appearance.colors.colOnTertiaryContainer
            : q === "1080p" ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer;
    }

    // A thin health bar: seeders against a healthy swarm of 200
    readonly property real health: Math.min(1, root.seeds / 200)

    implicitHeight: root.direct ? 60 : 66
    radius: Appearance.rounding.normal
    color: area.containsMouse || root.selected ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer1
    opacity: StremioService.starting ? 0.6 : 1
    border.width: root.selected ? 2 : root.recommended ? 1 : 0
    border.color: root.selected ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

    Behavior on color {
        ColorAnimation { duration: Appearance.dur(120) }
    }

    RowLayout {
        anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
        spacing: 12

        Rectangle {
            Layout.preferredWidth: 62
            Layout.preferredHeight: 28
            radius: Appearance.rounding.full
            color: root.direct ? Appearance.colors.colPrimary : root.qualityColor(root.quality)
            StyledText {
                anchors.centerIn: parent
                text: root.direct ? "DIRECT" : root.quality ? root.quality.toUpperCase() : "?"
                color: root.direct ? Appearance.colors.colOnPrimary : root.qualityOn(root.quality)
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                text: root.direct ? Translation.tr("Direct stream: starts right away") : root.release
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
            }

            Row {
                spacing: 6
                visible: root.direct || root.tags.length > 0 || root.recommended

                Repeater {
                    model: {
                        const t = root.tags.slice();
                        if (root.recommended)
                            t.unshift("Recommended");
                        if (root.direct)
                            t.push("No torrent needed");
                        return t;
                    }
                    delegate: Rectangle {
                        id: tag
                        required property string modelData
                        readonly property bool strong: modelData === "Recommended"
                        implicitWidth: tagText.implicitWidth + 12
                        implicitHeight: 18
                        radius: Appearance.rounding.full
                        color: tag.strong ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                        StyledText {
                            id: tagText
                            anchors.centerIn: parent
                            text: tag.modelData
                            color: tag.strong ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smallest
                        }
                    }
                }
            }
        }

        ColumnLayout {
            visible: !root.direct
            Layout.preferredWidth: 78
            spacing: 4
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 4
                MaterialSymbol {
                    text: "group"
                    iconSize: 15
                    color: root.seeds >= 20 ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }
                StyledText {
                    text: root.seeds
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 3
                radius: 1.5
                color: Appearance.colors.colLayer2
                Rectangle {
                    width: parent.width * root.health
                    height: parent.height
                    radius: 1.5
                    color: root.seeds >= 20 ? Appearance.colors.colPrimary : Appearance.colors.colTertiary
                }
            }
            StyledText {
                Layout.alignment: Qt.AlignRight
                text: root.stream?.size ?? ""
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallest
            }
        }

        ClockButton {
            iconOnly: true
            variant: "text"
            symbol: "download"
            label: "Download this stream"
            enabled: root.direct || String(root.stream?.infoHash ?? "") !== ""
            onClicked: root.downloadRequested()
        }
    }

    MouseArea {
        id: area
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: parent.right; rightMargin: 56 }
        hoverEnabled: true
        cursorShape: StremioService.starting ? Qt.BusyCursor : Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
