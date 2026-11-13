pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** Recently played, and what YouTube Music suggests. */
Rectangle {
    id: root

    property bool compact: false
    /// The play history without repeats, newest first
    readonly property var uniqueHistory: {
        const seen = {};
        const out = [];
        for (const t of MusicService.history) {
            if (!t?.id || seen[t.id])
                continue;
            seen[t.id] = true;
            out.push(t);
        }
        return out;
    }
    /// The last few songs, one tile each, for the quick-pick grid
    readonly property var quickPicks: root.uniqueHistory.slice(0, 6)
    readonly property var shelves: {
        const list = [];
        const shown = {};
        for (const t of root.uniqueHistory.slice(0, 18))
            shown[t.id] = true;
        // The quick picks are the newest six; this shelf carries on from there
        const earlier = root.uniqueHistory.slice(6, 18);
        if (earlier.length >= 3)
            list.push({ title: Translation.tr("Earlier"), tracks: earlier });
        // A suggestion shelf made only of songs already shown is the same row twice
        for (const s of MusicService.homeShelves) {
            const fresh = (s.tracks ?? []).filter(t => !shown[t.id]);
            if (fresh.length >= 3 || (s.tracks ?? []).length === 0)
                list.push(s);
        }
        return list;
    }
    readonly property string greeting: {
        const h = new Date().getHours();
        return h < 5 ? Translation.tr("Still up?") : h < 12 ? Translation.tr("Good morning")
            : h < 18 ? Translation.tr("Good afternoon") : Translation.tr("Good evening");
    }

    color: "transparent"

    Component.onCompleted: {
        MusicService.loadHome();
        MusicService.loadLibrary();
    }

    ClockEmptyState {
        visible: root.shelves.length === 0 && !MusicService.homeLoading
        anchors.centerIn: parent
        symbol: MusicService.homeError !== "" ? "cloud_off" : "library_music"
        title: MusicService.homeError !== "" ? Translation.tr("Could not reach YouTube Music") : Translation.tr("Nothing here yet")
        subtitle: MusicService.homeError !== "" ? MusicService.homeError : Translation.tr("Search for a song and it will show up here")
    }

    StyledText {
        visible: MusicService.homeLoading && root.shelves.length === 0
        anchors.centerIn: parent
        text: Translation.tr("Loading…")
        color: ClockStyle.colSubtext
    }

    Flickable {
        WheelScroll {}
        id: flick
        anchors.fill: parent
        topMargin: 4
        contentWidth: width
        contentHeight: column.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: column
            width: flick.width
            spacing: 22

            // ── Greeting and quick picks ──
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 14

                ColumnLayout {
                    spacing: 0
                    StyledText {
                        text: root.greeting
                        color: ClockStyle.colOnBackground
                        font.family: ClockStyle.fontTitle
                        font.variableAxes: ClockStyle.axesTitle
                        font.pixelSize: 34
                    }
                    StyledText {
                        visible: root.quickPicks.length > 0
                        text: Translation.tr("Pick up where you left off")
                        color: ClockStyle.colSubtext
                    }
                }

                GridLayout {
                    visible: root.quickPicks.length > 0
                    Layout.fillWidth: true
                    columns: root.compact ? 2 : 3
                    columnSpacing: 10
                    rowSpacing: 10

                    Repeater {
                        model: root.quickPicks
                        delegate: Rectangle {
                            id: pick
                            required property var modelData
                            readonly property bool current: MusicService.track?.id === modelData.id
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 64
                            radius: ClockStyle.radiusNormal
                            color: pick.current ? ClockStyle.colSecondaryContainer
                                : pickArea.containsMouse ? ClockStyle.colSurfaceHighest : ClockStyle.colSurfaceHigh
                            Behavior on color { ColorAnimation { duration: Appearance.dur(120) } }

                            RowLayout {
                                anchors.fill: parent
                                spacing: 12
                                RoundedCover {
                                    Layout.preferredWidth: 64
                                    Layout.preferredHeight: 64
                                    radius: ClockStyle.radiusNormal
                                    path: pick.modelData.thumb ?? ""
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.rightMargin: 12
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: pick.modelData.title
                                        color: pick.current ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnBackground
                                        font.weight: Font.Medium
                                        horizontalAlignment: Text.AlignLeft
                                        elide: Text.ElideRight
                                    }
                                    ArtistLink {
                                        Layout.fillWidth: true
                                        track: pick.modelData
                                        color: ClockStyle.colOnSurfaceVariant
                                    }
                                }
                                MaterialSymbol {
                                    Layout.rightMargin: 14
                                    visible: pick.current && MusicService.playing
                                    text: "equalizer"
                                    iconSize: 20
                                    color: ClockStyle.colPrimary
                                }
                            }
                            MouseArea {
                                id: pickArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: MusicService.playOne(pick.modelData)
                            }
                        }
                    }
                }
            }

            Repeater {
                model: root.shelves
                delegate: ColumnLayout {
                    id: shelf
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10

                    StyledText {
                        text: shelf.modelData.title
                        color: ClockStyle.colOnBackground
                        font.pixelSize: ClockStyle.textLarge
                        font.weight: Font.DemiBold
                    }
                    ListView {
                        WheelScroll {}
                        Layout.fillWidth: true
                        Layout.preferredHeight: 214
                        orientation: ListView.Horizontal
                        spacing: 16
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: shelf.modelData.tracks
                        delegate: Card {
                            required property var modelData
                            path: modelData.thumb ?? ""
                            title: modelData.title
                            subtitle: modelData.artist
                            track: modelData
                            onActivated: MusicService.playOne(modelData)
                        }
                    }
                }
            }
        }
    }
}
