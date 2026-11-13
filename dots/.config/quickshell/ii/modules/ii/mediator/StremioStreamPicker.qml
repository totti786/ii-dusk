pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// The streams Stremio found for one episode: pick one to play, or download it
FocusScope {
    id: root
    focus: true

    signal closeRequested()

    readonly property var streamingSettings: StremioService.streamSettings
    readonly property var rows: StremioService.streamRows
    property int cursor: -1
    onRowsChanged: root.cursor = -1

    function _step(d): void {
        const n = root.rows.length;
        if (n === 0)
            return;
        root.cursor = root.cursor < 0 ? (d > 0 ? Math.max(0, StremioService.recommendedIndex) : n - 1)
            : Math.max(0, Math.min(n - 1, root.cursor + d));
        list.positionViewAtIndex(root.cursor, ListView.Contain);
    }

    Keys.onEscapePressed: root.closeRequested()
    Keys.onDownPressed: root._step(1)
    Keys.onUpPressed: root._step(-1)
    Keys.onReturnPressed: if (root.cursor >= 0 && root.cursor < root.rows.length) StremioService.play(root.rows[root.cursor])
    Keys.onEnterPressed: if (root.cursor >= 0 && root.cursor < root.rows.length) StremioService.play(root.rows[root.cursor])

    Rectangle {
        anchors.fill: parent
        color: "#b3000000"
        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 680)
        height: Math.min(parent.height - 48, 560)
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer1
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors { fill: parent; margins: 20 }
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        text: `Streams for ${StremioService.pickedLabel}`
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Medium
                    }
                    StyledText {
                        text: StremioService.busy ? "Looking for streams…" : root.streamingSettings.hls === false ? "Most seeders first. ↑↓ to choose, Enter to play" : root.streamingSettings.prefer_stremio ? "Torrents first for quality, direct as the fallback" : "Direct stream first. Pick a torrent for higher quality"
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
                ClockButton {
                    iconOnly: true
                    variant: "text"
                    symbol: "close"
                    label: "Close"
                    onClicked: root.closeRequested()
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                wrapMode: Text.Wrap
                text: StremioService.starting ? "Starting…" : StremioService.notice
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            // Quality filter: only the sharpness the release list actually has
            Row {
                visible: StremioService.qualityOptions.length > 1 && root.streamingSettings.stremio !== false
                spacing: 6
                FilterChip {
                    label: "All"
                    selected: StremioService.streamFilter === "all"
                    onClicked: StremioService.streamFilter = "all"
                }
                Repeater {
                    model: StremioService.qualityOptions
                    FilterChip {
                        required property string modelData
                        label: modelData
                        selected: StremioService.streamFilter === modelData
                        onClicked: StremioService.streamFilter = modelData
                    }
                }
            }

            ListView {
                id: list
                WheelScroll {}
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                model: root.rows
                boundsBehavior: Flickable.StopAtBounds

                delegate: StremioStreamRow {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    stream: modelData
                    selected: root.cursor === index
                    recommended: index === StremioService.recommendedIndex && ListView.view.count > 1
                    onActivated: StremioService.play(modelData)
                    onDownloadRequested: StremioService.download(modelData)
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: !StremioService.busy && list.count === 0
                    text: "No streams found. Try another quality or check Settings."
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
