pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.shared
import qs.services

// Plain native anime controls shared by the bar popup and the island bubble card.
// The service remains the single owner of saved episode ids, worker state and errors.
Item {
    id: root
    clip: true

    signal openAppRequested()

    // The popup's StyledPopup adds its own outer margin. AuxiliaryBubble hosts
    // this plain item directly, so it opts into the room that host normally gives.
    property real contentPadding: 6
    property real cardWidth: 340

    readonly property var saved: MediatorService.displayState
    readonly property var episodes: Array.isArray(root.saved?.episodes) ? root.saved.episodes : []
    readonly property int currentIndex: {
        const id = String(root.saved?.episode_id ?? "");
        return root.episodes.findIndex(item => String(item?.id ?? "") === id);
    }
    readonly property bool hasCurrent: MediatorService.displayHasState
    readonly property bool active: MediatorService.nativeActive
    readonly property bool playing: root.active && !MediatorService.nativePaused
    readonly property bool switching: MediatorService.streamResolving
    readonly property bool busy: root.switching
        || (MediatorService.streamBusy && !root.active)
    readonly property bool hasError: String(
        MediatorService.streamError || MediatorService.nativeStateError || "").trim() !== ""
    readonly property bool askTorrent: MediatorService.directFailed !== null
    readonly property bool showStatus: !root.askTorrent && (root.hasError || root.switching
        || (MediatorService.streamBusy && !root.active)
        || MediatorService.nativeStateBusy)
    readonly property real progress: Math.max(0, Math.min(1,
        Number(MediatorService.nativeDuration) > 0
            ? Number(MediatorService.nativePosition) / Number(MediatorService.nativeDuration)
            : 0))
    property bool episodeListOpen: false
    property real episodeReveal: 0
    readonly property real episodeListHeight: Math.min(268, root.episodes.length * 38 + 28)
    readonly property real clampedEpisodeReveal: Math.max(0, Math.min(1, root.episodeReveal))
    readonly property real baseCardHeight: 200
    // The poster fades into the surface the card sits on, so the lower half (controls, the
    // episode list) is drawn in the shell's own colours rather than fixed white.
    readonly property color shelfColor: Appearance.colors.colLayer0Base
    readonly property color shelfText: Appearance.colors.colOnLayer0
    readonly property color chip: Qt.alpha(Appearance.colors.colSurfaceContainerHigh, 0.78)
    readonly property color chipHover: Appearance.colors.colSurfaceContainerHighest
    function seasonOf(episode): int {
        const m = String(episode?.number ?? "").match(/^S(\d+)E/i);
        return m ? Number(m[1]) : 0;
    }

    implicitWidth: root.cardWidth
    implicitHeight: body.implicitHeight + root.contentPadding * 2

    // Passive: attaches to a Syncplay session that exists, never starts one.
    Component.onCompleted: if (Config.options.syncplay?.enable ?? true) SyncplayService.watch()
    Component.onDestruction: if (Config.options.syncplay?.enable ?? true) SyncplayService.unwatch()

    Behavior on episodeReveal {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
    }

    onEpisodeListOpenChanged: root.episodeReveal = root.episodeListOpen ? 1 : 0

    function posterSourceFor(path): string {
        const value = String(path ?? "").trim();
        if (value === "")
            return "";
        if (/^https?:\/\//i.test(value))
            return MediatorService.cachedImage(value);
        if (/^file:\/\//i.test(value))
            return value;
        return MediatorService.posterUrl(value);
    }

    readonly property string posterSource: root.posterSourceFor(root.saved?.poster)

    // A movie has no episodes: no "Episode ?" line, no previous/next, no episode list
    readonly property bool isMovie: String(root.saved?.show_id ?? "").startsWith("stremio:movie:")
        || root.saved?.movie === true
    // A local episode has no episode list to move through, only the file playing
    readonly property bool isLocal: root.saved?.local === true
    // A Jellyfin session carries its series, so it can step and list episodes like a stream
    readonly property bool localSwitch: root.isLocal && root.episodes.length > 0

    function episodeSubtitle(): string {
        if (!root.hasCurrent)
            return MediatorService.streamMessage || "Native player";
        if (root.isMovie)
            return "Movie";
        if (root.isLocal) {
            const label = String(root.saved?.episode_number ?? "").trim();
            const name = String(root.saved?.episode_title ?? "").trim();
            return [label, label.includes(name) ? "" : name].filter(part => part !== "").join(" · ") || "Library";
        }
        const number = String(root.saved?.episode_number ?? "").trim();
        const title = String(root.saved?.episode_title ?? "").trim();
        // Stremio episodes already read "S01E02"; provider episodes are plain numbers
        const label = /^S\d+E\d+$/i.test(number) ? number : `Episode ${number || "?"}`;
        return `${label}${title !== "" ? ` · ${title}` : ""}`;
    }

    function statusText(): string {
        const error = String(
            MediatorService.streamError || MediatorService.nativeStateError || "").trim();
        if (error !== "")
            return error;
        if (MediatorService.streamResolving)
            return String(MediatorService.streamMessage || "Opening episode…");
        if (MediatorService.streamBusy && !root.active)
            return "Loading episode…";
        if (MediatorService.nativeStateBusy)
            return "Loading saved playback…";
        return "";
    }

    function launch(index: int): void {
        if (root.switching)
            return;
        MediatorService.launchEpisode(index);
    }

    function playOrPause(): void {
        if (root.busy)
            return;
        if (root.active)
            MediatorService.nativeControl("toggle");
        else if (root.isLocal)
            MediatorService.continueTitle(String(root.saved?.show_id ?? ""));
        else
            MediatorService.playRememberedNative();
    }

    // The poster is the face of the native card. Keep it in a separate hero item
    // so AuxiliaryBubble can grow the same artwork into the expanded background.
    Item {
        id: heroBackground
        objectName: "mediatorHeroBackground"
        readonly property bool heroBackdrop: true
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.baseCardHeight
        clip: true

        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colSurfaceContainerHighest
        }

        Image {
            id: backgroundImage
            anchors.fill: parent
            source: root.posterSource
            visible: root.posterSource !== "" && status === Image.Ready
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            sourceSize.width: root.cardWidth * 2
            sourceSize.height: root.baseCardHeight * 2
        }

        // A dark wash keeps white text readable over both bright skies and
        // the poster's pale logo. The lower stop gives controls a quiet shelf.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#59000000" }
                GradientStop { position: 0.38; color: "#1F000000" }
                GradientStop { position: 0.6; color: Qt.alpha(root.shelfColor, 0.55) }
                GradientStop { position: 0.84; color: Qt.alpha(root.shelfColor, 0.9) }
                GradientStop { position: 1.0; color: root.shelfColor }
            }
        }

        // A localized upper scrim keeps the title readable over bright artwork
        // without burying the poster across the whole card.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 92
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#A6000000" }
                GradientStop { position: 0.72; color: "#78000000" }
                GradientStop { position: 1.0; color: "#00000000" }
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            visible: !backgroundImage.visible
            text: "movie"
            fill: 1
            iconSize: 30
            color: "#D9FFFFFF"
        }
    }

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: root.contentPadding
        implicitWidth: root.cardWidth - root.contentPadding * 2
        spacing: 8 * root.clampedEpisodeReveal

        Item {
            id: heroFrame
            Layout.fillWidth: true
            Layout.preferredHeight: root.baseCardHeight - root.contentPadding * 2

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 6
                anchors.rightMargin: SyncplayService.connected ? 100 : 42
                spacing: 3

                StyledText {
                    Layout.fillWidth: true
                    text: root.hasCurrent
                        ? String(root.saved?.title ?? root.saved?.show_id ?? "Anime")
                        : "Anime streaming"
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                    color: "#FFFFFFFF"
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.episodeSubtitle()
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: "#E6FFFFFF"
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.showStatus
                    text: root.statusText()
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: root.hasError ? "#FFFFB4AB" : "#D9FFFFFF"
                }
            }

            // A Syncplay room you are in: who is watching, and who the room is waiting for.
            RippleButton {
                id: roomButton
                animationsEnabled: !Appearance.reducedMotion
                visible: SyncplayService.connected
                anchors.right: parent.right
                anchors.rightMargin: 36
                anchors.top: parent.top
                height: 30
                width: roomRow.implicitWidth + 20
                buttonRadius: Appearance.rounding.full
                colBackground: "#66000000"
                colBackgroundHover: "#88000000"
                onClicked: GlobalStates.openSyncplayApp()

                readonly property int total: SyncplayService.roomUsers.length
                readonly property var notReady: SyncplayService.roomUsers.filter(u => !u.ready).map(u => u.name)

                contentItem: Row {
                    id: roomRow
                    anchors.centerIn: parent
                    spacing: 5
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "group"
                        fill: 1
                        iconSize: 15
                        color: "#F2FFFFFF"
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: roomButton.notReady.length > 0
                            ? Translation.tr("%1 · %2 waiting").arg(roomButton.total).arg(roomButton.notReady.length)
                            : String(roomButton.total)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: "#F2FFFFFF"
                    }
                }
                StyledToolTip {
                    text: roomButton.notReady.length > 0
                        ? Translation.tr("%1 · waiting for %2").arg(SyncplayService.room).arg(roomButton.notReady.join(", "))
                        : Translation.tr("%1 · everyone is ready").arg(SyncplayService.room)
                }
            }

            RippleButton {
                animationsEnabled: !Appearance.reducedMotion
                anchors.right: parent.right
                anchors.top: parent.top
                width: 30
                height: 30
                buttonRadius: Appearance.rounding.full
                colBackground: "#66000000"
                colBackgroundHover: "#88000000"
                onClicked: root.openAppRequested()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "open_in_new"
                    iconSize: 15
                    color: "#F2FFFFFF"
                }
            }

            // The direct stream failed: nothing switches on its own. Takes the place of the seek bar
            // and transport buttons, which belong to an episode that never started.
            Item {
                id: askPanel
                visible: root.askTorrent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 96

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: "cloud_off"
                            iconSize: 22
                            color: root.shelfText
                            opacity: 0.85
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Couldn't play this directly")
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: root.shelfText
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("A torrent starts slower but usually works.")
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: root.shelfText
                                opacity: 0.7
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RippleButton {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            colRipple: Appearance.colors.colPrimaryActive
                            onClicked: MediatorService.useTorrentInstead()
                            contentItem: StyledText {
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: Translation.tr("Play torrent")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                        RippleButton {
                            Layout.preferredWidth: 96
                            Layout.preferredHeight: 38
                            buttonRadius: Appearance.rounding.full
                            colBackground: root.chip
                            colBackgroundHover: root.chipHover
                            onClicked: MediatorService.dismissDirectFailed()
                            contentItem: StyledText {
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: Translation.tr("Cancel")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: root.shelfText
                            }
                        }
                    }
                }
            }

            Item {
                id: heroControls
                visible: root.hasCurrent && !root.askTorrent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 78

                RowLayout {
                    id: progressRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: controlRow.top
                    anchors.bottomMargin: 6
                    spacing: 6

                    StyledText {
                        text: MediatorService.clock(MediatorService.nativePosition)
                        color: root.shelfText
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.features: ({ "tnum": 1 })
                    }

                    // Material 3 Expressive progress: the fill ripples while it plays, goes
                    // straight when paused, and the bar can be dragged to seek
                    StyledSlider {
                        id: seekBar
                        Layout.fillWidth: true
                        Layout.preferredHeight: 20
                        configuration: StyledSlider.Configuration.Wavy
                        animateWave: root.playing && root.visible && !Appearance.reducedMotion
                        highlightColor: Appearance.colors.colPrimary
                        handleColor: Appearance.colors.colPrimary
                        trackColor: Qt.alpha(root.shelfText, 0.2)
                        usePercentTooltip: false
                        tooltipContent: MediatorService.clock(value * Math.max(0, Number(MediatorService.nativeDuration)))
                        enabled: root.active && Number(MediatorService.nativeDuration) > 0
                        value: root.progress
                        onMoved: MediatorService.nativeControl("seek_to", value * Number(MediatorService.nativeDuration))
                        // A drag overwrites `value` and drops the binding: restore it on release
                        onPressedChanged: if (!pressed)
                            value = Qt.binding(() => root.progress)
                    }

                    StyledText {
                        text: MediatorService.nativeDuration > 0
                            ? MediatorService.clock(MediatorService.nativeDuration) : "--:--"
                        color: root.shelfText
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.features: ({ "tnum": 1 })
                    }
                }

                RowLayout {
                    id: controlRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    spacing: 8

                    // A movie has only play/pause: centred, no previous/next
                    Item { Layout.fillWidth: true; visible: root.isMovie || (root.isLocal && !root.localSwitch) }

                    RippleButton {
                        animationsEnabled: !Appearance.reducedMotion
                        visible: !root.isMovie && (!root.isLocal || root.localSwitch)
                        enabled: root.currentIndex > 0 && !root.busy
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.chip
                        colBackgroundHover: root.chipHover
                        opacity: enabled ? 1 : 0.45
                        onClicked: root.launch(root.currentIndex - 1)

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "skip_previous"
                            iconSize: 20
                            color: root.shelfText
                        }
                    }

                    RippleButton {
                        animationsEnabled: !Appearance.reducedMotion
                        enabled: !root.busy
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 48
                        buttonRadius: root.playing ? Appearance.rounding.full : Appearance.rounding.small
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: root.playOrPause()

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.busy ? "hourglass_top"
                                : (root.playing ? "pause" : "play_arrow")
                            iconSize: 28
                            fill: 1
                            color: Appearance.colors.colOnPrimary
                        }
                    }

                    RippleButton {
                        animationsEnabled: !Appearance.reducedMotion
                        visible: !root.isMovie && (!root.isLocal || root.localSwitch)
                        enabled: root.currentIndex >= 0
                            && root.currentIndex < root.episodes.length - 1 && !root.busy
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.chip
                        colBackgroundHover: root.chipHover
                        opacity: enabled ? 1 : 0.45
                        onClicked: root.launch(root.currentIndex + 1)

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "skip_next"
                            iconSize: 20
                            color: root.shelfText
                        }
                    }

                    Item { Layout.fillWidth: true }

                    RippleButton {
                        id: episodesButton
                        animationsEnabled: !Appearance.reducedMotion
                        visible: root.episodes.length > 0 && !root.isMovie
                        enabled: !root.busy
                        // Wide enough for "12 / 187" however long the show runs
                        Layout.preferredWidth: Math.max(68, chipRow.implicitWidth + 24)
                        Layout.preferredHeight: 30
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.episodeListOpen
                            ? Appearance.colors.colPrimaryContainer : root.chip
                        colBackgroundHover: root.episodeListOpen
                            ? Appearance.colors.colPrimaryContainerHover : root.chipHover
                        onClicked: root.episodeListOpen = !root.episodeListOpen

                        // Hovering opens the list; it stays open until the button is clicked
                        HoverHandler {
                            onHoveredChanged: if (hovered && !root.episodeListOpen)
                                root.episodeListOpen = true
                        }

                        contentItem: RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                text: "list"
                                iconSize: 15
                                color: root.episodeListOpen ? Appearance.colors.colOnPrimaryContainer : root.shelfText
                            }

                            StyledText {
                                // Where you are in the show, not just how long it is
                                text: root.currentIndex >= 0
                                    ? `${root.currentIndex + 1} / ${root.episodes.length}`
                                    : String(root.episodes.length)
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: root.episodeListOpen ? Appearance.colors.colOnPrimaryContainer : root.shelfText
                            }

                            MaterialSymbol {
                                text: root.episodeListOpen ? "expand_less" : "expand_more"
                                iconSize: 15
                                color: root.episodeListOpen ? Appearance.colors.colOnPrimaryContainer : root.shelfText
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: episodeListFrame
            visible: root.hasCurrent && root.episodes.length > 0 && !root.isMovie
            Layout.fillWidth: true
            Layout.preferredHeight: root.episodeListHeight * root.clampedEpisodeReveal
            clip: true
            opacity: root.clampedEpisodeReveal
            scale: 0.98 + (0.02 * root.clampedEpisodeReveal)

            Behavior on opacity {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on scale {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            ListView {
                WheelScroll {}
                id: episodeList
                anchors.fill: parent
                anchors.topMargin: 14
                anchors.leftMargin: -2
                anchors.rightMargin: -2
                clip: true
                model: root.episodes
                reuseItems: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                Component.onCompleted: positionViewAtIndex(Math.max(0, root.currentIndex), ListView.Contain)

                delegate: Column {
                    id: episodeRow
                    required property var modelData
                    required property int index
                    width: episodeList.width
                    readonly property int season: root.seasonOf(modelData)
                    readonly property bool firstOfSeason: season > 0
                        && (index === 0 || root.seasonOf(root.episodes[index - 1]) !== season)

                    StyledText {
                        visible: episodeRow.firstOfSeason
                        height: visible ? 30 : 0
                        leftPadding: 14
                        topPadding: episodeRow.index === 0 ? 0 : 8
                        verticalAlignment: Text.AlignVCenter
                        text: `SEASON ${episodeRow.season}`
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.8
                        color: Appearance.colors.colSubtext
                    }

                RippleButton {
                    id: episodeButton
                    animationsEnabled: !Appearance.reducedMotion
                    readonly property var modelData: episodeRow.modelData
                    readonly property int index: episodeRow.index
                    width: episodeList.width
                    implicitHeight: 36
                    buttonRadius: 10
                    readonly property bool selected: String(modelData?.id ?? "")
                        === String(root.saved?.episode_id ?? "")
                    readonly property string code: {
                        const n = String(modelData?.number ?? "").trim() || String(index + 1);
                        const m = n.match(/^S\d+E(\d+)$/i);
                        return m ? `E${m[1]}` : n;
                    }
                    colBackground: selected ? Qt.alpha(Appearance.colors.colPrimary, 0.20) : "transparent"
                    colBackgroundHover: selected
                        ? Qt.alpha(Appearance.colors.colPrimary, 0.28) : Qt.alpha(root.shelfText, 0.08)
                    colRipple: selected ? Appearance.colors.colPrimary : Qt.alpha(root.shelfText, 0.14)
                    enabled: !root.busy
                    onClicked: root.launch(index)

                    Rectangle {
                        visible: episodeButton.selected
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: 16
                        radius: 2
                        color: Appearance.colors.colPrimary
                    }

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 10
                        spacing: 10

                        StyledText {
                            Layout.preferredWidth: 34
                            text: episodeButton.code
                            horizontalAlignment: Text.AlignLeft
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.4
                            color: episodeButton.selected
                                ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: String(episodeButton.modelData?.title ?? "") !== ""
                                ? String(episodeButton.modelData.title) : `Episode ${episodeButton.code}`
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: episodeButton.selected ? Font.DemiBold : Font.Normal
                            color: root.shelfText
                            elide: Text.ElideRight
                        }
                        MaterialSymbol {
                            visible: episodeButton.selected
                            text: "graphic_eq"
                            iconSize: 16
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
                }
            }
        }

    }

    // The full background is the hero shared with the native glance. The ring's
    // poster grows into this item while the card's text and controls stay readable.
    readonly property Item heroItem: heroBackground
}
