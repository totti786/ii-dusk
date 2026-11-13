pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One "Continue watching" row for everything streamed: anime from the provider and movies or
 * shows from Stremio, newest first, one card per title. The card for the player that is
 * open right now toggles pause; the others resume where they stopped (or start the next
 * episode once one was finished).
 */
ColumnLayout {
    id: root

    readonly property var current: MediatorService.nativeState
    readonly property bool hasCurrent: MediatorService.nativeHasState
    readonly property var entries: {
        const out = MediatorService.streamShows(MediatorService.streamHistory);
        const seen = ({});
        for (const item of out)
            seen[String(item.show_id)] = true;
        // History entries carry the full episode list; the "current" state may not
        if (root.hasCurrent && !seen[String(root.current.show_id)])
            out.unshift(root.current);
        // What is on, then what is half watched, then shows with a next episode, finished ones last
        const rank = e => root.isLive(e) ? 0 : !e.watched ? 1 : root.nextOf(e) ? 2 : 3;
        out.sort((a, b) => rank(a) - rank(b));
        return out.slice(0, 12);
    }

    function clock(sec): string {
        const t = Math.max(0, Math.floor(Number(sec) || 0));
        const h = Math.floor(t / 3600);
        const m = Math.floor((t % 3600) / 60);
        const s = String(t % 60).padStart(2, "0");
        return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${s}` : `${m}:${s}`;
    }

    function nextOf(state): var {
        const episodes = Array.isArray(state?.episodes) ? state.episodes : [];
        const i = episodes.findIndex(e => String(e?.id ?? "") === String(state?.episode_id ?? ""));
        return i >= 0 && i + 1 < episodes.length ? episodes[i + 1] : null;
    }

    function tag(state): string {
        const n = String(state?.episode_number ?? "");
        return n === "" ? "" : (/^S\d+E\d+$/.test(n) ? n : "Ep " + n);
    }

    function subtitle(state): string {
        if (state.watched) {
            const next = root.nextOf(state);
            return next ? "Next " + root.tag({ "episode_number": next.number }) : "Finished";
        }
        const at = Number(state.position) > 5 ? " · " + root.clock(state.position) : "";
        return (root.tag(state) !== "" ? "Resume " + root.tag(state) : "Resume") + at;
    }

    function isLive(state): bool {
        return root.hasCurrent && MediatorService.nativeActive
            && String(state.show_id) === String(root.current.show_id);
    }

    function activate(state): void {
        if (root.isLive(state)) {
            MediatorService.nativeControl("toggle");
            return;
        }
        MediatorService.resumeStream(state);
    }

    visible: root.entries.length > 0
    spacing: 12

    function chipText(e): string {
        if (root.isLive(e))
            return MediatorService.nativeLoading ? "Opening" : MediatorService.nativePaused ? "Paused" : "Playing";
        if (e.watched)
            return root.nextOf(e) ? "Up next" : "Finished";
        return root.tag(e) || (String(e.show_id).includes(":movie:") ? "Movie" : "Episode");
    }

    function lineOf(e): string {
        if (e.watched) {
            const next = root.nextOf(e);
            return next ? root.tag({ "episode_number": next.number }) + (next.title ? " · " + next.title : "") : "You're all caught up";
        }
        const t = String(e.episode_title ?? "");
        return root.tag(e) !== "" ? root.tag(e) + (t !== "" ? " · " + t : "") : t;
    }

    function actionLabel(e): string {
        if (root.isLive(e))
            return MediatorService.nativePaused ? "Resume" : "Pause";
        if (root.isFinished(e))
            return "Clear";
        if (e.watched)
            return "Play " + root.tag({ "episode_number": root.nextOf(e).number });
        return Number(e.position) > 5 ? "Resume " + root.clock(e.position) : "Play";
    }

    onEntriesChanged: MediatorService.warmImages(root.entries.map(e => e.poster))

    // Keyboard: the card under the cursor, -1 for none
    property int cursor: -1
    /// The poster under the mouse, -1 for none; with no keyboard cursor it picks what the caption shows
    property int hovered: -1
    readonly property int focusIndex: root.cursor >= 0 ? root.cursor : root.hovered >= 0 ? root.hovered : 0

    function moveCursor(to): void {
        root.cursor = Math.max(0, Math.min(root.entries.length - 1, to));
        list.positionViewAtIndex(root.cursor, ListView.Contain);
    }

    /// The library title behind the card under the cursor, if it has one
    function localForCursor(): var {
        const entry = root.entries[root.cursor];
        return entry ? MediatorService.ownedFor([entry.title], null) : null;
    }

    function activateCursor(): bool {
        const entry = root.entries[root.cursor];
        if (!entry)
            return false;
        root.activate(entry);
        return true;
    }

    function isFinished(e): bool {
        return Boolean(e?.watched) && !root.nextOf(e);
    }

    readonly property var finishedIds: root.entries.filter(e => root.isFinished(e)).map(e => String(e.show_id))

    function remove(entry): void {
        MediatorService.forgetStreams([String(entry?.show_id ?? "")]);
        root.cursor = Math.min(root.cursor, root.entries.length - 2);
    }

    /// Delete key: remove the card under the keyboard cursor
    function removeCursor(): bool {
        const entry = root.entries[root.cursor];
        if (!entry || root.isLive(entry))
            return false;
        root.remove(entry);
        return true;
    }

    function fractionOf(e): real {
        return Number(e?.duration) > 0 && !e?.watched ? Math.min(1, Number(e.position) / Number(e.duration)) : 0
    }

    function leftLabel(e): string {
        if (e?.watched || !(Number(e?.duration) > 0))
            return "";
        const m = Math.max(1, Math.round((Number(e.duration) - Number(e.position)) / 60));
        return m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m left` : `${m} min left`;
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        StyledText {
            text: "Continue watching"
            color: Appearance.colors.colOnLayer0
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.DemiBold
        }
        Rectangle {
            implicitWidth: countText.implicitWidth + 14
            implicitHeight: 20
            radius: Appearance.rounding.full
            color: Appearance.colors.colSecondaryContainer
            StyledText {
                id: countText
                anchors.centerIn: parent
                text: root.entries.length
                color: Appearance.colors.colOnSecondaryContainer
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
            }
        }
        Item { Layout.fillWidth: true }
        Rectangle {
            visible: root.finishedIds.length > 0
            implicitWidth: clearRow.implicitWidth + 22
            implicitHeight: 28
            radius: Appearance.rounding.full
            color: clearArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer1
            Row {
                id: clearRow
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "done_all"
                    iconSize: 16
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: `Clear ${root.finishedIds.length} finished`
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
            MouseArea {
                id: clearArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: MediatorService.forgetStreams(root.finishedIds)
            }
        }
    }

    // The posters, nothing laid over them: how far along is a line beneath each
    ListView {
        id: list
        WheelScroll {}
        Layout.fillWidth: true
        Layout.preferredHeight: 226
        orientation: ListView.Horizontal
        spacing: 14
        clip: true
        topMargin: 6
        bottomMargin: 4
        leftMargin: 4
        rightMargin: 4
        boundsBehavior: Flickable.StopAtBounds
        model: root.entries

        delegate: Item {
            id: card
            required property var modelData
            required property int index
            readonly property bool live: root.isLive(modelData)
            readonly property real fraction: root.fractionOf(modelData)
            readonly property bool selected: root.cursor === card.index
            readonly property bool finished: root.isFinished(modelData)
            width: 132
            height: ListView.view.height - 10

            RoundedBox {
                id: poster
                width: parent.width
                height: 198
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2

                Image {
                    anchors.fill: parent
                    source: MediatorService.cachedImage(String(card.modelData.poster ?? ""))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 300
                    opacity: card.finished ? 0.45 : 1
                }
                MaterialSymbol {
                    visible: card.finished
                    anchors.centerIn: parent
                    text: "check_circle"
                    fill: 1
                    iconSize: 34
                    color: "white"
                }
                // Only the one that is playing says anything on its poster
                Rectangle {
                    visible: card.live
                    anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
                    width: 26
                    height: 26
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimary
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: MediatorService.nativePaused ? "pause" : "graphic_eq"
                        fill: 1
                        iconSize: 16
                        color: Appearance.colors.colOnPrimary
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    color: "black"
                    opacity: area.containsMouse && !card.selected ? 0.12 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: Appearance.dur(120) }
                    }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: StremioService.starting ? Qt.BusyCursor : Qt.PointingHandCursor
                    onContainsMouseChanged: root.hovered = area.containsMouse ? card.index : (root.hovered === card.index ? -1 : root.hovered)
                    onClicked: card.finished ? root.remove(card.modelData) : root.activate(card.modelData)
                }

                Rectangle {
                    visible: !card.live && !card.finished && (area.containsMouse || xArea.containsMouse || card.selected)
                    anchors { top: parent.top; right: parent.right; margins: 6 }
                    width: 24
                    height: 24
                    radius: Appearance.rounding.full
                    color: xArea.containsMouse ? Appearance.colors.colErrorContainer : Qt.rgba(0, 0, 0, 0.55)
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 15
                        color: xArea.containsMouse ? Appearance.m3colors.m3onErrorContainer : "white"
                    }
                    MouseArea {
                        id: xArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.remove(card.modelData)
                    }
                    StyledToolTip {
                        extraVisibleCondition: xArea.containsMouse
                        text: "Remove from Continue watching"
                    }
                }
            }

            // How far along, under the poster
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: poster.bottom; topMargin: 8 }
                height: 3
                radius: 1.5
                visible: card.fraction > 0
                color: Appearance.colors.colSecondaryContainer
                Rectangle {
                    width: parent.width * card.fraction
                    height: parent.height
                    radius: 1.5
                    color: Appearance.colors.colPrimary
                }
            }

            Rectangle {
                anchors { fill: poster; margins: -3 }
                radius: Appearance.rounding.normal + 3
                color: "transparent"
                visible: card.selected
                border.width: 3
                border.color: Appearance.colors.colPrimary
            }
        }
    }

    // One line for the title the cursor (or the mouse) is on, with the single action that matters
    RowLayout {
        id: caption
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        spacing: 14
        readonly property var entry: root.entries[root.focusIndex] ?? ({})
        readonly property bool finished: root.isFinished(caption.entry)

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: String(caption.entry.title ?? "")
                color: Appearance.colors.colOnLayer0
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: [root.lineOf(caption.entry), root.leftLabel(caption.entry)].filter(x => x).join("  ·  ")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }

        Rectangle {
            implicitHeight: 40
            implicitWidth: actionRow.implicitWidth + 32
            radius: actionArea.pressed ? 12 : height / 2
            color: caption.finished ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
            Behavior on radius {
                NumberAnimation { duration: Appearance.dur(120) }
            }
            Row {
                id: actionRow
                anchors.centerIn: parent
                spacing: 8
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: caption.finished ? "check_circle" : root.isLive(caption.entry) && !MediatorService.nativePaused ? "pause" : "play_arrow"
                    fill: 1
                    iconSize: 22
                    color: caption.finished ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.actionLabel(caption.entry)
                    color: caption.finished ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                    font.weight: Font.Medium
                }
            }
            MouseArea {
                id: actionArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: caption.finished ? root.remove(caption.entry) : root.activate(caption.entry)
            }
        }
    }
}
