pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A scrolling list of songs. `asQueue` decides what a click means: false plays that song
 * alone and lets radio carry on from it (search results), true plays the whole list from
 * there (an album, favourites).
 */
ListView {
    WheelScroll {}
    id: root

    property var tracks: []
    property bool asQueue: false
    property bool showIndex: false
    property real padding: 0

    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: root.tracks
    spacing: 2
    topMargin: root.padding
    bottomMargin: root.padding
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    delegate: TrackRow {
        required property var modelData
        required property int index
        width: ListView.view.width
        track: modelData
        rowIndex: index
        showIndex: root.showIndex
        onActivated: {
            if (root.asQueue)
                MusicService.play(root.tracks, index);
            else
                MusicService.playOne(modelData);
        }
    }
}
