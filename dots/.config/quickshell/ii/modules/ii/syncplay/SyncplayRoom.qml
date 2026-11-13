pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "SyncplayFormat.js" as Fmt

/**
 * The room: what is playing and where, who is here and what they have, the shared playlist,
 * and chat. Everything shown is the session's state; everything done is a command to it.
 */
Item {
    id: root

    readonly property bool hasFile: SyncplayService.file !== null
    readonly property var mediaDirs: SyncplayService.defaults.mediaDirs ?? []

    // Which action the file picker is serving
    property string pickPurpose: "open"

    function pickFile(purpose: string): void {
        if (picker.running)
            return;
        root.pickPurpose = purpose;
        const start = root.mediaDirs.length > 0 ? root.mediaDirs[0] : Quickshell.env("HOME");
        picker.command = ["zenity", "--file-selection", "--title",
            purpose === "open" ? Translation.tr("Choose a video") : Translation.tr("Add to the playlist"),
            "--filename", start + "/"];
        picker.running = true;
    }

    Process {
        id: picker
        stdout: StdioCollector { id: pickerOut }
        onExited: code => {
            const path = pickerOut.text.trim();
            if (code !== 0 || path.length === 0)
                return;
            if (root.pickPurpose === "open")
                SyncplayService.openFile(path);
            else
                SyncplayService.playlistAdd(Fmt.baseName(path));
        }
    }

    RowLayout {
        anchors {
            fill: parent
            leftMargin: ClockStyle.pagePadding
            rightMargin: ClockStyle.pagePadding
            bottomMargin: ClockStyle.pagePadding
        }
        spacing: ClockStyle.paneGap

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: ClockStyle.paneGap

            // ── Now playing ────────────────────────────────────────────────
            SyncplayPane {
                Layout.fillWidth: true
                title: Translation.tr("Now playing")

                headerExtras: [
                    ClockButton {
                        visible: !SyncplayService.mediatorOwned
                        focusPolicy: Qt.NoFocus
                        variant: "tonal"
                        symbol: "folder_open"
                        label: Translation.tr("Open file")
                        onClicked: root.pickFile("open")
                    }
                ]

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: root.hasFile ? SyncplayService.currentName : Translation.tr("Nothing loaded yet")
                    font.pixelSize: ClockStyle.textLarge
                    color: root.hasFile ? ClockStyle.colOnSurface : ClockStyle.colSubtext
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gap
                    opacity: root.hasFile ? 1 : 0.4

                    ClockIconButton {
                        focusPolicy: Qt.NoFocus
                        enabled: root.hasFile
                        symbol: SyncplayService.paused ? "play_arrow" : "pause"
                        filled: true
                        toggled: !SyncplayService.paused
                        tooltip: SyncplayService.paused ? Translation.tr("Play for everyone") : Translation.tr("Pause for everyone")
                        onClicked: SyncplayService.togglePause()
                    }

                    StyledText {
                        text: Fmt.time(SyncplayService.position)
                        font.pixelSize: ClockStyle.textNormal
                        font.family: ClockStyle.fontNumbers
                        color: ClockStyle.colOnSurfaceVariant
                    }

                    StyledSlider {
                        id: seek
                        Layout.fillWidth: true
                        enabled: root.hasFile
                        from: 0
                        to: Math.max(1, SyncplayService.duration)
                        value: SyncplayService.position
                        usePercentTooltip: false
                        tooltipContent: Fmt.time(seek.value)
                        onMoved: SyncplayService.seek(seek.value)
                    }

                    StyledText {
                        text: Fmt.time(SyncplayService.duration)
                        font.pixelSize: ClockStyle.textNormal
                        font.family: ClockStyle.fontNumbers
                        color: ClockStyle.colOnSurfaceVariant
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                    ClockChip {
                        focusPolicy: Qt.NoFocus
                        symbol: SyncplayService.ready ? "check_circle" : "radio_button_unchecked"
                        label: SyncplayService.ready ? Translation.tr("You are ready") : Translation.tr("Mark yourself ready")
                        selected: SyncplayService.ready
                        onClicked: SyncplayService.setReady(!SyncplayService.ready)
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        visible: SyncplayService.globalPaused !== SyncplayService.paused
                        text: Translation.tr("Catching up with the room…")
                        font.pixelSize: ClockStyle.textSmall
                        color: ClockStyle.colSubtext
                    }
                }
            }

            // ── Who is here ────────────────────────────────────────────────
            SyncplayPane {
                Layout.fillWidth: true
                title: Translation.tr("In this room")
                count: SyncplayService.roomUsers.length

                headerExtras: [
                    ClockIconButton {
                        focusPolicy: Qt.NoFocus
                        symbol: "edit"
                        tooltip: Translation.tr("Switch room")
                        onClicked: roomSwitch.visible = !roomSwitch.visible
                    }
                ]

                RowLayout {
                    id: roomSwitch
                    visible: false
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                    ClockFormField {
                        id: roomInput
                        symbol: "meeting_room"
                        shapeKind: MaterialShape.Shape.Clover4Leaf
                        caption: Translation.tr("Room")
                        onAccepted: {
                            SyncplayService.changeRoom(roomInput.text);
                            roomInput.text = "";
                            roomSwitch.visible = false;
                        }
                        onVisibleChanged: if (visible) roomInput.focusInput()
                    }
                }

                Repeater {
                    model: SyncplayService.roomUsers

                    delegate: RowLayout {
                        id: userRow
                        required property var modelData
                        readonly property bool differentFile: !modelData.me && modelData.file !== null
                            && SyncplayService.file !== null && !modelData.sameFile
                        Layout.fillWidth: true
                        spacing: ClockStyle.gap

                        MaterialSymbol {
                            text: userRow.modelData.ready === true ? "check_circle"
                                : userRow.modelData.ready === false ? "radio_button_unchecked" : "remove"
                            fill: userRow.modelData.ready === true ? 1 : 0
                            iconSize: ClockStyle.iconNormal
                            color: userRow.modelData.ready === true ? ClockStyle.colPrimary : ClockStyle.colSubtext
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            RowLayout {
                                spacing: ClockStyle.gapTiny

                                StyledText {
                                    text: userRow.modelData.me
                                        ? Translation.tr("%1 (you)").arg(userRow.modelData.name)
                                        : userRow.modelData.name
                                    font.pixelSize: ClockStyle.textNormal
                                    font.weight: Font.DemiBold
                                    color: ClockStyle.colOnSurface
                                }

                                MaterialSymbol {
                                    visible: userRow.modelData.controller
                                    text: "shield_person"
                                    iconSize: ClockStyle.iconSmall
                                    color: ClockStyle.colTertiary
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                                text: userRow.modelData.file
                                    ? `${userRow.modelData.file.name} · ${Fmt.time(userRow.modelData.file.duration)}`
                                    : Translation.tr("No file loaded")
                                font.pixelSize: ClockStyle.textSmall
                                color: userRow.differentFile ? ClockStyle.colError : ClockStyle.colSubtext
                            }
                        }

                        MaterialSymbol {
                            visible: userRow.differentFile
                            text: "warning"
                            iconSize: ClockStyle.iconNormal
                            color: ClockStyle.colError

                            StyledToolTip {
                                text: Translation.tr("A different file from yours: name, size or length does not match")
                            }
                        }
                    }
                }
            }

            // ── Playlist ───────────────────────────────────────────────────
            SyncplayPane {
                id: playlistPane
                // Watch Together through Mediator: Mediator's episode list is the list. The room's
                // own list only holds the links Mediator has resolved so far (a few ahead), which
                // would read as raw URLs, so the window shows Mediator's episodes instead.
                readonly property var mediatorEpisodes: MediatorService.displayState?.episodes ?? []
                readonly property bool useMediator: SyncplayService.mediatorOwned
                    && playlistPane.mediatorEpisodes.length > 0
                // Only what is left: the episode playing and those after it
                readonly property int firstShown: playlistPane.useMediator
                    ? Math.max(0, playlistPane.mediatorEpisodes.findIndex(e => String(e?.id ?? "") === String(MediatorService.displayState?.episode_id ?? "")))
                    : 0
                readonly property int currentIndex: playlistPane.useMediator ? 0 : SyncplayService.playlistIndex
                readonly property var rows: playlistPane.useMediator
                    ? playlistPane.mediatorEpisodes.slice(playlistPane.firstShown).map((e, i) => {
                        const n = String(e?.number ?? "").trim() || String(i + playlistPane.firstShown + 1);
                        const m = n.match(/^S\d+E(\d+)$/i);
                        const code = m ? `E${m[1]}` : n;
                        const t = String(e?.title ?? "").trim();
                        return t !== "" && !code.includes(t) ? `${code} · ${t}` : code;
                    })
                    : SyncplayService.playlistItems
                function playRow(i: int): void {
                    if (playlistPane.useMediator) {
                        // One the room already holds is a move inside the room; further ahead
                        // is Mediator's to resolve and start
                        const inRoom = Math.max(0, SyncplayService.playlistIndex) + i;
                        if (SyncplayService.connected && inRoom < SyncplayService.playlistItems.length)
                            SyncplayService.playlistPlay(inRoom);
                        else
                            MediatorService.launchEpisode(i + playlistPane.firstShown);
                    }
                    else if (!SyncplayService.mediatorOwned)
                        SyncplayService.playlistPlay(i);
                }
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 160
                title: playlistPane.useMediator ? Translation.tr("Up next") : Translation.tr("Playlist")
                count: playlistPane.rows.length

                headerExtras: [
                    ClockIconButton {
                        visible: !SyncplayService.mediatorOwned
                        focusPolicy: Qt.NoFocus
                        enabled: SyncplayService.canUndo
                        symbol: "undo"
                        tooltip: Translation.tr("Undo the last change")
                        onClicked: SyncplayService.undoPlaylist()
                    },
                    ClockIconButton {
                        visible: !SyncplayService.mediatorOwned
                        focusPolicy: Qt.NoFocus
                        enabled: SyncplayService.playlistItems.length > 1
                        symbol: "shuffle"
                        tooltip: Translation.tr("Shuffle what is left")
                        onClicked: SyncplayService.shufflePlaylist()
                    }
                ]

                StyledText {
                    visible: SyncplayService.mediatorOwned
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: playlistPane.useMediator
                        ? Translation.tr("Mediator's episode list. The room moves on to the next one by itself; picking another switches everyone to it.")
                        : Translation.tr("Mediator controls this list: it follows what you are watching there, and next and previous are done in Mediator.")
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                }

                StyledText {
                    visible: !SyncplayService.sharedPlaylist && !playlistPane.useMediator
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Translation.tr("Shared playlists are off in your Syncplay settings, so this room's list is not synced.")
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                }

                StyledText {
                    visible: playlistPane.rows.length === 0 && SyncplayService.sharedPlaylist
                    Layout.fillWidth: true
                    text: Translation.tr("Nothing queued. Add a file name or a link: everyone loads it from their own folders.")
                    wrapMode: Text.WordWrap
                    font.pixelSize: ClockStyle.textNormal
                    color: ClockStyle.colSubtext
                }

                ListView {
                    id: playlistView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: playlistPane.rows
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: item
                        required property int index
                        required property string modelData
                        readonly property bool current: item.index === playlistPane.currentIndex
                        width: playlistView.width
                        height: ClockStyle.rowHeight - 8
                        radius: ClockStyle.radiusNormal
                        color: item.current ? ClockStyle.colSecondaryContainer
                            : (itemHover.hovered ? ClockStyle.colRailRowHover : "transparent")

                        HoverHandler { id: itemHover }
                        TapHandler {
                            enabled: playlistPane.useMediator || !SyncplayService.mediatorOwned
                            onTapped: playlistPane.playRow(item.index)
                        }

                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: ClockStyle.gap
                                rightMargin: ClockStyle.gapSmall
                            }
                            spacing: ClockStyle.gap

                            MaterialSymbol {
                                text: item.current ? "play_arrow" : "movie"
                                fill: item.current ? 1 : 0
                                iconSize: ClockStyle.iconSmall + 2
                                color: item.current ? ClockStyle.colOnSecondaryContainer : ClockStyle.colSubtext
                            }

                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                                text: item.modelData
                                font.pixelSize: ClockStyle.textNormal
                                font.weight: item.current ? Font.DemiBold : Font.Normal
                                color: item.current ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                            }

                            MaterialSymbol {
                                visible: !playlistPane.useMediator && SyncplayService.playlistMissing.indexOf(item.index) >= 0
                                text: "warning"
                                fill: 1
                                iconSize: ClockStyle.iconSmall + 2
                                color: ClockStyle.colError
                                StyledToolTip { text: Translation.tr("Not in your Syncplay media folders: it cannot load here") }
                            }

                            ClockIconButton {
                                focusPolicy: Qt.NoFocus
                                visible: itemHover.hovered && !SyncplayService.mediatorOwned
                                size: 32
                                iconSize: ClockStyle.iconSmall + 2
                                symbol: "close"
                                tooltip: Translation.tr("Remove")
                                onClicked: SyncplayService.playlistRemove(item.index)
                            }
                        }
                    }
                }

                RowLayout {
                    visible: !SyncplayService.mediatorOwned
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                    ClockFormField {
                        id: addInput
                        symbol: "playlist_add"
                        shapeKind: MaterialShape.Shape.Cookie9Sided
                        caption: Translation.tr("Add a file name or link")
                        onAccepted: {
                            const t = addInput.text.trim();
                            if (t.length > 0)
                                SyncplayService.playlistAdd(t);
                            addInput.text = "";
                        }
                    }

                    ClockIconButton {
                        focusPolicy: Qt.NoFocus
                        symbol: "folder_open"
                        tooltip: Translation.tr("Browse")
                        onClicked: root.pickFile("add")
                    }
                }
            }
        }

        SyncplayChat {
            Layout.preferredWidth: 340
            Layout.fillHeight: true
        }
    }
}
