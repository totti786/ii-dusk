pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.bar.widgets.media
import qs.modules.ii.bar.widgets.indicators
import qs.modules.ii.bar.widgets.timer
import qs.modules.ii.modes
import qs.modules.ii.soundscapes.components

/**
 * What an auxiliary bubble shows: a glance at an activity, never the activity itself.
 *
 * Each glance says how wide it wants to be (`preferredWidth`): a circle is the bubble's
 * own diameter, a pill asks for more. The bubble animates to that width and the shape
 * grows away from the island, so a glance only has to lay itself out at the width it
 * is given - it is clipped while the pill is still catching up.
 *
 *   media       the bar's vertical ring (cover in a scalloped rim sweeping with the
 *               track); on a track change it opens into a pill with part of the title,
 *               and while paused into a pill with a play button
 *   workspaces  the active-workspace indicator
 *   ai          the working agent's icon
 *   dictation   the microphone, breathing while it listens
 *   recording   a pill: a still error-coloured dot and the elapsed time, its digits
 *               rolling like the bar's record indicator
 *   timer       a pill: the expressive timer marker and the time left (pomodoro,
 *               countdown, or the stopwatch); paused, it folds to the marker alone
 *   update      the update glyph, with how many commits behind in the corner
 *   privacy     one glyph per sensor held, in the phones' colours
 *   discordVoice  the headset or microphone state in a compact pill, with the
 *               headcount and a speaking or muted outline
 *   phoneLink   the phone's camera and/or microphone glyph while they stream here
 *   systemTray  the tray's own chevron, the count of programs in a badge
 *   easyEffects the loaded preset's glyph, dimmed while bypassed; a scroll switches preset
 *   soundscapes the lead sound of the ambient mix in its group's tone, rippling while it plays,
 *               a pause badge when it does not; a sleep timer widens it into a pill with the
 *               time left. A scroll sets the volume
 *   earbuds     the connected headset's glyph inside a ring that is its battery,
 *               error-coloured at 15 % and below
 *   btPhone     the same for a phone connected over Bluetooth
 *
 * Resting on the bubble opens it into its own expanded card; the only thing a glance
 * does itself is media's play button while paused.
 */
Item {
    id: root

    /** The activity on show; "" while the bubble is empty. */
    required property string activityId
    /** The bubble's settled height; circles are this wide. */
    required property real diameter
    /** Buttons on a glance (media's play) answer only while it is the glance on show. */
    property bool interactive: true
    /**
     * How much of the glance the pill currently uncovers, from its inner end. Parts
     * beyond it are masked away by the bubble; this lets them also fade in as they
     * are reached rather than pop in at the edge.
     */
    property real revealedWidth: root.width
    /**
     * Hosted inside the island itself (its resting face): no pill growth for media -
     * no title, no play button - and no pill padding at the ends of the others.
     */
    property bool glanceOnly: false
    /** How far this glance is being handed to its card, 0 to 1 (the bubble's expansion). */
    property real handOff: 0

    /** How wide this glance wants the bubble to be. */
    readonly property real preferredWidth: glance.item ? glance.item.preferredWidth : root.diameter
    /**
     * What this glance weighs when the island shares its bubbles between its two sides:
     * the width it asks for, unless it says otherwise (`balanceWidth`). A glance whose
     * width comes and goes says otherwise, so that the row is not re-dealt each time.
     */
    readonly property real balanceWidth: glance.item
        ? (glance.item.balanceWidth ?? glance.item.preferredWidth) : root.diameter
    /**
     * The elements this glance hands to its expanded card's own `heroItems`, paired by
     * index (the icon, the avatar, the recording's dot and time); empty where it has none.
     */
    readonly property var heroItems: glance.item && glance.item.heroItems ? glance.item.heroItems : []

    height: root.diameter

    /** Padding at a pill's ends: enough to clear the rounded caps. */
    // Inside the island a glance sits between its neighbours, which give it air.
    readonly property real endPadding: root.glanceOnly ? 0 : Math.round(root.diameter * 0.32)
    readonly property color colText: Appearance.colors.colOnLayer0

    /**
     * A lone glyph's size, as a share of the bubble and always even. An odd glyph has no
     * centre in an even circle: it sat half a pixel across, and on a fractional scale a
     * pixel and a half high.
     */
    function glyphSize(share: real): int {
        return 2 * Math.round(root.diameter * share / 2);
    }

    /**
     * A count in the bubble's lower right.
     *
     * The glance is a square and the bubble a circle cut out of it, so a badge anchored
     * to the square's corner sat in the part the circle removes and lost half its
     * number. This one is placed on the circle instead: its outer end cap rests just
     * inside the rim on the diagonal, and a wider count grows inwards from there.
     */
    component CountBadge: Rectangle {
        id: badge
        required property real diameter
        property string label: ""
        property string glyph: ""

        readonly property real reach: Math.max(0, badge.diameter / 2 - badge.height / 2 - 1) / Math.SQRT2

        x: badge.diameter / 2 + badge.reach + badge.height / 2 - badge.width
        y: badge.diameter / 2 + badge.reach - badge.height / 2
        width: Math.max(badge.height, badgeText.implicitWidth + 6)
        height: 14
        radius: badge.height / 2
        color: Appearance.colors.colPrimary

        MaterialSymbol {
            anchors.centerIn: parent
            visible: badge.glyph !== ""
            text: badge.glyph
            iconSize: 11
            fill: 1
            color: Appearance.colors.colOnPrimary
        }

        StyledText {
            id: badgeText
            anchors.centerIn: parent
            visible: badge.glyph === ""
            text: badge.label
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Bold
            color: Appearance.colors.colOnPrimary
        }
    }

    Loader {
        id: glance
        anchors.fill: parent
        sourceComponent: {
            switch (root.activityId) {
            case "media": return mediaGlance;
            case "mediator": return mediatorGlance;
            case "workspaces": return workspaceGlance;
            case "ai": return aiGlance;
            case "dictation": return dictationGlance;
            case "recording": return recordingGlance;
            case "audioRecording": return audioRecordingGlance;
            case "timer": return timerGlance;
            case "mode": return modeGlance;
            case "update": return updateGlance;
            case "privacy": return privacyGlance;
            case "discordVoice": return discordGlance;
            case "phoneMirror": return phoneMirrorGlance;
            case "phoneLink": return phoneLinkGlance;
            case "shelf": return shelfGlance;
            case "systemTray": return systemTrayGlance;
            case "easyEffects": return easyEffectsGlance;
            case "soundscapes": return soundscapesGlance;
            case "quickShare": return quickShareGlance;
            case "progress": return progressGlance;
            case "monitorAlert": return monitorAlertGlance;
            case "focus": return focusGlance;
            case "prayer": return prayerGlance;
            case "earbuds": return earbudsGlance;
            case "btPhone": return phoneGlance;
            }
            return null;
        }
    }

    // ── Media ────────────────────────────────────────────────────────────────
    Component {
        id: mediaGlance

        Item {
            id: media

            /**
             * A track change is worth a word: for a few seconds the ring opens into a pill
             * with the start of the new title, then closes again. Kept short so the bar
             * beside it is pushed only a little and only briefly.
             */
            property bool showTitle: false
            readonly property real maxWidth: Math.round(root.diameter * 4.6)
            readonly property string title: StringUtils.cleanMusicTitle(MprisController.activePlayer?.trackTitle ?? "")
            /**
             * Pinned open (Settings > Dynamic Island > Media): the pill never folds back to
             * the ring. It stays at one fixed width - a width that followed each lyric line
             * would shove the bar beside it on every verse - and says the current lyric, or
             * the track name where there are none (and for a few seconds after a track change).
             */
            readonly property bool pinned: (Config.options.bar.floatingNotch.pinMediaBubble ?? false) && !root.glanceOnly
            readonly property real pinnedWidth: Math.round(root.diameter * 5.4)
            readonly property bool lyricsOn: media.pinned && !media.showTitle && !media.paused
                && (Config.options.lyricsService.enable ?? false) && LyricsService.hasSyncedLines
            readonly property string lyricLine: media.lyricsOn
                ? (LyricsService.syncedLines[LyricsService.currentIndex]?.text ?? "") : ""
            readonly property string shownText: media.lyricLine.trim() !== "" ? media.lyricLine.trim() : media.title
            /**
             * Paused, the ring opens into a pill with a play button beside it, so
             * resuming is one click away without opening anything.
             */
            readonly property bool paused: MprisController.activePlayer ? !MprisController.activePlayer.isPlaying : false
            readonly property real buttonWidth: Math.round(root.diameter * 1.3)
            /** The ring, rim and cover together, becomes the card's album-art backdrop. */
            readonly property var heroItems: [ring.ringItem]
            readonly property real preferredWidth: {
                if (root.glanceOnly)
                    return root.diameter;
                if (media.pinned)
                    return media.pinnedWidth;
                if (media.paused)
                    return root.diameter + media.buttonWidth + 4;
                if (media.showTitle && media.title !== "")
                    return Math.min(media.maxWidth, root.diameter + titleMetrics.advanceWidth + root.endPadding);
                return root.diameter;
            }
            /**
             * Two circles, whatever it is doing: between the ring it is while playing and
             * the pills it opens into while paused or on a new track. Weighed live, every
             * pause and every track change moved some other bubble across the island.
             */
            readonly property real balanceWidth: media.pinned ? media.pinnedWidth : 2 * root.diameter

            // Only a pinned pill shows lyrics, so only then does the service need to fetch them.
            onPinnedChanged: if (media.pinned) LyricsService.initiliazeLyrics()

            // A Syncplay room you are in rides on this bubble: the count of people watching.
            // Watching only attaches to a session that exists; it never starts one.
            readonly property bool inRoom: SyncplayService.connected
            Component.onCompleted: {
                if (media.pinned)
                    LyricsService.initiliazeLyrics();
                if (Config.options.syncplay?.enable ?? true)
                    SyncplayService.watch();
            }
            Component.onDestruction: if (Config.options.syncplay?.enable ?? true) SyncplayService.unwatch()

            // Measured apart from the label: the label is laid out at the width this
            // decides, and measuring the label itself would loop.
            TextMetrics {
                id: titleMetrics
                text: media.title
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                font.family: Appearance.font.family.main
            }

            Timer {
                id: titleTimer
                interval: 4000
                onTriggered: media.showTitle = false
            }

            Connections {
                target: MprisController
                function onTrackChanged() {
                    media.showTitle = true;
                    titleTimer.restart();
                }
            }

            // The ring always sits in the circle at the pill's inner end.
            Item {
                id: ringSlot
                width: root.diameter
                height: root.diameter

                RingMedia {
                    id: ring
                    anchors.centerIn: parent
                    vertical: true
                    // Outside the bar: must not move the media popup's anchor or open it.
                    previewMode: true
                    // The vertical ring is drawn for a bar column; scale it to the bubble.
                    scale: ring.ringSize > 0 ? (root.diameter - 6) / ring.ringSize : 1
                    // Only the cover grows into the card: the rim zoomed with it, a pale
                    // crescent at its edge.
                    chromeOpacity: 1 - Math.min(1, root.handOff / 0.2)
                }
            }

            StyledText {
                id: titleText
                anchors.left: ringSlot.right
                anchors.right: parent.right
                // A pinned, paused pill keeps the play button at its end.
                anchors.rightMargin: root.endPadding + (media.pinned && media.paused ? media.buttonWidth + 4 : 0)
                anchors.verticalCenter: parent.verticalCenter
                text: media.pinned ? media.shownText : media.title
                animateChange: media.pinned
                elide: Text.ElideRight
                maximumLineCount: 1
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: root.colText
                opacity: media.pinned ? 1 : (media.showTitle && !media.paused && !root.glanceOnly ? 1 : 0)
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(titleText)
                }
            }

            // Resume: a full-radius button in the island's accent, beside the ring.
            RippleButton {
                id: playButton
                x: media.pinned ? media.pinnedWidth - media.buttonWidth - 4 : root.diameter
                anchors.verticalCenter: parent.verticalCenter
                width: media.buttonWidth
                height: root.diameter - 8
                enabled: root.interactive && media.paused && !root.glanceOnly
                // Uncovered by the growing pill, and fading in as it is: no pop at the
                // pill's edge on the way out, none on the way back in.
                readonly property real revealed: Math.max(0, Math.min(1,
                    (root.revealedWidth - playButton.x - playButton.width * 0.3) / (playButton.width * 0.7)))
                opacity: media.paused && !root.glanceOnly ? playButton.revealed : 0
                scale: 0.85 + 0.15 * playButton.revealed
                visible: opacity > 0
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: MprisController.activePlayer?.togglePlaying()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "play_arrow"
                    fill: 1
                    iconSize: Math.round(root.diameter * 0.5)
                    color: Appearance.colors.colOnPrimary
                }
            }

            CountBadge {
                diameter: root.diameter
                visible: media.inRoom && !root.glanceOnly
                glyph: "group"
                label: ""
            }
        }
    }

    // ── Native anime playback ───────────────────────────────────────────────
    // Keep the anime player visually in the media family without reading MPRIS:
    // its own worker state drives the ring, pause pill and expanded card.
    Component {
        id: mediatorGlance

        Item {
            id: mediator

            readonly property bool active: MediatorService.nativeActive
                && !MediatorService.nativePaused
            readonly property bool paused: MediatorService.displayHasState
                && (!MediatorService.nativeActive || MediatorService.nativePaused)
            readonly property real buttonWidth: Math.round(root.diameter * 1.3)
            readonly property real progress: Math.max(0, Math.min(1,
                Number(MediatorService.nativeDuration) > 0
                    ? Number(MediatorService.nativePosition) / Number(MediatorService.nativeDuration)
                    : 0))
            readonly property real preferredWidth: root.glanceOnly || !mediator.paused
                ? root.diameter : root.diameter + mediator.buttonWidth + 4

            // A Syncplay room you are in rides on this bubble too (Watch Together plays
            // through the native player): the count of people watching.
            Component.onCompleted: if (Config.options.syncplay?.enable ?? true) SyncplayService.watch()
            Component.onDestruction: if (Config.options.syncplay?.enable ?? true) SyncplayService.unwatch()
            readonly property real balanceWidth: 2 * root.diameter
            readonly property string posterSource: MediatorService.posterUrl(MediatorService.displayState?.poster)
            // Hand off the same poster item that the expanded card uses. The
            // rim is chrome around this item and must not become the hero.
            readonly property var heroItems: [animeRing.artItem]

            Item {
                id: animeDisc
                width: root.diameter
                height: root.diameter
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter

                MediaRingVisual {
                    id: animeRing
                    anchors.centerIn: parent
                    diameter: root.diameter - 4
                    progress: mediator.progress
                    chromeOpacity: 1 - Math.min(1, root.handOff / 0.2)
                    artSource: mediator.posterSource
                    icon: MediatorService.streamResolving ? "hourglass_top"
                        : (mediator.active ? "play_circle" : "movie")
                    primaryColor: Appearance.colors.colPrimary
                    iconColor: mediator.active
                        ? Appearance.colors.colOnPrimaryContainer : root.colText
                }
            }

            RippleButton {
                id: playButton
                x: root.diameter
                anchors.verticalCenter: parent.verticalCenter
                width: mediator.buttonWidth
                height: root.diameter - 8
                enabled: root.interactive && mediator.paused && !root.glanceOnly
                    && !MediatorService.streamResolving
                    && !(MediatorService.streamBusy && !MediatorService.nativeActive)
                readonly property real revealed: Math.max(0, Math.min(1,
                    (root.revealedWidth - playButton.x - playButton.width * 0.3)
                        / (playButton.width * 0.7)))
                opacity: mediator.paused && !root.glanceOnly ? playButton.revealed : 0
                scale: 0.85 + 0.15 * playButton.revealed
                visible: opacity > 0
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: MediatorService.nativeActive
                    ? MediatorService.nativeControl("toggle")
                    : MediatorService.playRememberedNative()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "play_arrow"
                    fill: 1
                    iconSize: Math.round(root.diameter * 0.5)
                    color: Appearance.colors.colOnPrimary
                }
            }

            CountBadge {
                diameter: root.diameter
                visible: SyncplayService.connected && !root.glanceOnly
                glyph: "group"
                label: ""
            }
        }
    }

    // ── Workspaces ───────────────────────────────────────────────────────────
    Component {
        id: workspaceGlance

        Item {
            readonly property real preferredWidth: root.diameter
            readonly property int workspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
            readonly property var numberMap: Config.options.bar.workspaces.numberMap ?? []

            Rectangle {
                anchors.centerIn: parent
                width: root.diameter - 8
                height: width
                radius: width / 2
                color: Appearance.colors.colPrimary

                StyledText {
                    anchors.centerIn: parent
                    text: String(parent.parent.numberMap[parent.parent.workspaceId - 1] || parent.parent.workspaceId)
                    font.pixelSize: Math.max(10, Math.round(parent.height * 0.5))
                    font.weight: Font.Bold
                    font.family: Appearance.font.family.numbers
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }

    // ── AI ───────────────────────────────────────────────────────────────────
    Component {
        id: aiGlance

        Item {
            id: ai
            readonly property real preferredWidth: root.diameter
            readonly property var agent: AiStatusService.primaryAgent
            readonly property int agentCount: AiStatusService.agentCount
            // Resting sessions sort last, so the first one resting means they all are.
            readonly property bool resting: (ai.agent?.startedAtEpoch ?? 0) <= 0
                && ai.agent?.requiresAttention !== true
            readonly property var heroItems: [aiIcon]

            CustomIcon {
                id: aiIcon
                anchors.centerIn: parent
                // Up and left a touch while the count is there, so it covers less of it.
                anchors.horizontalCenterOffset: ai.agentCount > 1 ? -2 : 0
                anchors.verticalCenterOffset: ai.agentCount > 1 ? -2 : 0
                width: Math.round(root.diameter * 0.5)
                height: width
                source: {
                    let name = ai.agent?.icon || "google-gemini-symbolic.svg";
                    return name.endsWith(".svg") ? name : name + ".svg";
                }
                colorize: true
                color: ai.resting ? Appearance.colors.colOnSurfaceVariant : Appearance.colors.colPrimary
            }

            // More than one agent at work: how many, in the corner.
            CountBadge {
                visible: ai.agentCount > 1
                diameter: root.diameter
                label: String(ai.agentCount)
            }
        }
    }

    // ── Dictation ────────────────────────────────────────────────────────────
    Component {
        id: dictationGlance

        Item {
            readonly property real preferredWidth: root.diameter
            readonly property bool transcribing: DictationService.transcribing
            readonly property var heroItems: [dictationDisc]

            Rectangle {
                id: dictationDisc
                anchors.centerIn: parent
                width: root.diameter - 8
                height: width
                radius: width / 2
                color: parent.transcribing ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: parent.parent.transcribing ? "graphic_eq" : "mic"
                    iconSize: Math.round(root.diameter * 0.45)
                    fill: 1
                    color: parent.parent.transcribing ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimaryContainer

                    // The microphone is open: the same breathing the bar's indicator has,
                    // and only while it is.
                    SequentialAnimation on opacity {
                        running: (DictationService.recording) && !Appearance.motionOff
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.45; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.45; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                    }
                    onTextChanged: if (!DictationService.recording) opacity = 1.0
                }
            }
        }
    }

    // ── Recording ────────────────────────────────────────────────────────────
    Component {
        id: recordingGlance

        Item {
            id: recording
            readonly property int seconds: (Persistent.states.screenRecord && Persistent.states.screenRecord.seconds) || 0
            readonly property string timeText: {
                const s = recording.seconds;
                const hours = Math.floor(s / 3600);
                const clock = String(Math.floor((s % 3600) / 60)).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0");
                return hours > 0 ? String(hours) + ":" + clock : clock;
            }
            readonly property real preferredWidth: row.implicitWidth + 2 * root.endPadding
            readonly property var heroItems: [recordingDot, recordingTime]

            Row {
                id: row
                anchors.centerIn: parent
                spacing: 7

                // Still on purpose: the digits are what move.
                Rectangle {
                    id: recordingDot
                    anchors.verticalCenter: parent.verticalCenter
                    width: 9
                    height: 9
                    radius: 4.5
                    // The saturated red; plain `colError` is the pale tone meant for text.
                    color: Appearance.colors.colErrorContainer
                }

                RecordTimerText {
                    id: recordingTime
                    anchors.verticalCenter: parent.verticalCenter
                    value: recording.timeText
                    pixelSize: Appearance.font.pixelSize.small
                    colText: root.colText
                    animate: !Appearance.reducedMotion
                }
            }
        }
    }

    // ── Audio recording ──────────────────────────────────────────────────────
    Component {
        id: audioRecordingGlance

        Item {
            id: audioRec
            readonly property int seconds: AudioRecorderService.elapsed
            readonly property string timeText: {
                const s = audioRec.seconds;
                const hours = Math.floor(s / 3600);
                const clock = String(Math.floor((s % 3600) / 60)).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0");
                return hours > 0 ? String(hours) + ":" + clock : clock;
            }
            readonly property real preferredWidth: row.implicitWidth + 2 * root.endPadding
            readonly property var heroItems: [audioRecDot, audioRecTime]

            Row {
                id: row
                anchors.centerIn: parent
                spacing: 7

                // A held take goes amber and dim; a running one is the saturated red.
                Rectangle {
                    id: audioRecDot
                    anchors.verticalCenter: parent.verticalCenter
                    width: 9
                    height: 9
                    radius: 4.5
                    color: AudioRecorderService.paused ? Appearance.colors.colWarning : Appearance.colors.colErrorContainer
                    opacity: AudioRecorderService.paused ? 0.65 : 1
                }

                RecordTimerText {
                    id: audioRecTime
                    anchors.verticalCenter: parent.verticalCenter
                    value: audioRec.timeText
                    pixelSize: Appearance.font.pixelSize.small
                    colText: root.colText
                    animate: !Appearance.reducedMotion && !AudioRecorderService.paused
                }
            }
        }
    }

    // ── Timers ───────────────────────────────────────────────────────────────
    Component {
        id: timerGlance

        Item {
            id: timer

            // Pomodoro first, then the countdown that ends soonest, then the stopwatch:
            // the order the bar's timer widget lays its capsules out in, cut to one.
            // A paused countdown or stopwatch steps aside for an alarm that is about to ring.
            readonly property string kind: timerState.hasPomodoro ? "pomodoro"
                : (timerState.hasCountdown && !timerState.countdownPaused) ? "countdown"
                : timerState.stopwatchRunning ? "stopwatch"
                : timerState.hasUpcomingAlarm ? "alarm"
                : (timerState.hasCountdown ? "countdown" : "stopwatch")
            readonly property string value: timer.kind === "alarm" ? timerState.upcomingAlarmText
                : timer.kind === "pomodoro" ? timerState.pomodoroText
                : (timer.kind === "countdown" ? timerState.countdownText
                    // Whole seconds: centiseconds in a glance are only flicker.
                    : timerState.formatClock(Math.floor(TimerService.stopwatchTime / 100)))
            readonly property bool running: timer.kind === "alarm" ? true
                : timer.kind === "pomodoro" ? timerState.pomodoroRunning
                : (timer.kind === "countdown" ? !timerState.countdownPaused : timerState.stopwatchRunning)
            readonly property real markerSize: root.diameter - 10
            // Paused, the pill folds to the marker alone: nothing is counting.
            readonly property real preferredWidth: timer.running
                ? (root.diameter - timer.markerSize) / 2 + row.implicitWidth + root.endPadding
                : root.diameter
            readonly property var heroItems: [timerMarker, timerText]

            TimerBarState {
                id: timerState
            }

            Row {
                id: row
                x: (root.diameter - timer.markerSize) / 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                MaterialShapeWrappedMaterialSymbol {
                    id: timerMarker
                    anchors.verticalCenter: parent.verticalCenter
                    shape: timer.kind === "alarm" ? MaterialShape.Shape.Cookie7Sided
                        : timer.kind === "pomodoro" ? MaterialShape.Shape.Cookie9Sided
                        : (timer.kind === "countdown" ? MaterialShape.Shape.Arch : MaterialShape.Shape.Circle)
                    implicitSize: timer.markerSize
                    iconSize: Appearance.font.pixelSize.normal
                    padding: 3
                    text: {
                        if (timer.kind === "alarm")
                            return timerState.upcomingAlarm?.phone ? "phone_android" : "alarm";
                        if (!timer.running)
                            return "pause_circle";
                        if (timer.kind === "pomodoro")
                            return "search_activity";
                        return timer.kind === "countdown" ? "hourglass_top" : "timer";
                    }
                    color: Appearance.colors.colPrimary
                    colSymbol: Appearance.colors.colOnPrimary
                }

                StyledText {
                    id: timerText
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: timer.running ? 1 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(timerText)
                    }
                    text: timer.value
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    font.features: ({ "tnum": 1 })
                    color: root.colText
                }
            }
        }
    }

    // ── Modes ────────────────────────────────────────────────────────────────
    Component {
        id: modeGlance

        Item {
            id: modeItem
            readonly property real preferredWidth: root.diameter
            readonly property var mode: Modes.activeMode
            readonly property string colorKey: modeItem.mode?.color ?? ""
            readonly property real shapeSize: Math.max(16, root.diameter - 8)
            readonly property var heroItems: [shape]

            MaterialShape {
                id: shape
                anchors.centerIn: parent
                implicitWidth: modeItem.shapeSize
                implicitHeight: modeItem.shapeSize
                shapeString: (modeItem.mode && modeItem.mode.shape) ? modeItem.mode.shape : "Cookie12Sided"
                color: ModeUi.container(modeItem.colorKey)

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: modeItem.mode?.icon ?? "tune"
                    iconSize: Math.round(shape.implicitHeight * 0.52)
                    fill: 1
                    color: ModeUi.onContainer(modeItem.colorKey)
                }
            }
        }
    }

    // ── Shell update ─────────────────────────────────────────────────────────
    Component {
        id: updateGlance

        Item {
            id: update
            readonly property real preferredWidth: root.diameter
            // 0 is "unknown" (offline, rate-limited, not a GitHub remote), not "level".
            readonly property int behind: ShellUpdates.commitsBehind
            readonly property var heroItems: [updateIcon]

            MaterialSymbol {
                id: updateIcon
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: update.behind > 0 ? -2 : 0
                anchors.verticalCenterOffset: update.behind > 0 ? -2 : 0
                text: "deployed_code_update"
                iconSize: root.glyphSize(0.56)
                color: Appearance.colors.colPrimary
            }

            CountBadge {
                visible: update.behind > 0
                diameter: root.diameter
                label: update.behind > 99 ? "99+" : String(update.behind)
            }
        }
    }

    // ── Privacy ──────────────────────────────────────────────────────────────
    // One glyph per held sensor, in the bar indicator's own colour. A single sensor is
    // a circle like every other bubble; a video call (camera and microphone) widens it.
    Component {
        id: privacyGlance

        Item {
            id: privacy
            readonly property var kinds: Privacy.activeKinds
            readonly property int iconSize: Math.round(root.diameter * 0.5)
            readonly property real preferredWidth: privacy.kinds.length <= 1 ? root.diameter
                : privacyRow.implicitWidth + 2 * Math.max(root.endPadding, Math.round(root.diameter * 0.26))
            // One glyph per sensor, in `Privacy.activeKinds` order: the card lists its
            // badges the same way, so each glyph lands on its sensor's first row.
            readonly property var heroItems: {
                const glyphs = [];
                for (let i = 0; i < privacyGlyphs.count; i++)
                    glyphs.push(privacyGlyphs.itemAt(i));
                return glyphs;
            }

            Row {
                id: privacyRow
                anchors.centerIn: parent
                spacing: 3

                Repeater {
                    id: privacyGlyphs
                    model: privacy.kinds

                    MaterialSymbol {
                        required property var modelData
                        text: Privacy.iconFor(String(modelData))
                        fill: 1
                        iconSize: privacy.iconSize
                        color: Appearance.colors.colTertiary
                    }
                }
            }
        }
    }

    // ── Discord voice ────────────────────────────────────────────────────────
    // Only loaded while a call is on, which is also the only time DiscordVoice runs.
    Component {
        id: discordGlance

        Item {
            id: discord
            readonly property string stateGlyph: discord.muted
                ? (DiscordVoiceActivity.deafened ? "headset_off" : "mic_off") : "headset_mic"
            readonly property color stateColor: discord.muted ? Appearance.colors.colError
                : Appearance.colors.colOnLayer2
            readonly property real preferredWidth: root.diameter

            readonly property var participants: DiscordVoiceActivity.participants ?? []
            readonly property bool anyoneSpeaking: discord.participants.some(user => user?.speaking === true)
            readonly property bool muted: DiscordVoiceActivity.muted || DiscordVoiceActivity.deafened
            readonly property var speaker: {
                const talking = discord.participants.find(user => user?.speaking === true);
                const selfId = String(DiscordVoiceActivity.currentUser?.id ?? "");
                return talking ?? discord.participants.find(user => String(user?.id ?? "") === selfId)
                    ?? discord.participants[0] ?? null;
            }

            Rectangle {
                anchors.centerIn: parent
                width: root.diameter
                height: width
                radius: width / 2
                color: "transparent"
                // A ring only while there is something to say with it (speaking, muted). At
                // rest the 1px outline was nearly the colour of what is behind the bubble, so
                // it showed as a faint arc on whichever side the backdrop differed.
                readonly property bool ringed: discord.anyoneSpeaking || discord.muted
                border.width: ringed ? 3 : 0
                border.color: discord.anyoneSpeaking ? Appearance.colors.colPrimary : Appearance.colors.colError

                ClippingRectangle {
                    anchors.centerIn: parent
                    width: root.diameter - (parent.ringed ? 10 : 4)
                    height: width
                    Behavior on width {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    radius: width / 2
                    color: Appearance.colors.colLayer2

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: speakerImage.status !== Image.Ready
                        text: discord.stateGlyph
                        fill: 1
                        iconSize: Math.max(16, Math.round(root.diameter * 0.46))
                        color: discord.stateColor
                    }

                    Image {
                        id: speakerImage
                        anchors.fill: parent
                        source: DiscordVoiceActivity.avatarUrl(discord.speaker, 64)
                        sourceSize: Qt.size(64, 64)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: status === Image.Ready
                    }
                }
            }
        }
    }

    // ── Phone camera & microphone ────────────────────────────────────────────
    // Read from the flags the phone services publish, so the glance never constructs
    // them. One stream is a circle; both widen it, like privacy.
    Component {
        id: phoneLinkGlance

        Item {
            id: phoneLink
            readonly property var streams: [GlobalStates.phoneCameraRunning ? "videocam" : "",
                GlobalStates.phoneMicRunning ? "mic" : ""].filter(glyph => glyph !== "")
            readonly property int iconSize: Math.round(root.diameter * 0.5)
            readonly property real preferredWidth: phoneLink.streams.length <= 1 ? root.diameter
                : phoneLinkRow.implicitWidth + 2 * Math.max(root.endPadding, Math.round(root.diameter * 0.26))
            // One glyph per stream, camera first: the card's rows, in the same order.
            readonly property var heroItems: {
                const glyphs = [];
                for (let i = 0; i < phoneLinkGlyphs.count; i++)
                    glyphs.push(phoneLinkGlyphs.itemAt(i));
                return glyphs;
            }

            Row {
                id: phoneLinkRow
                anchors.centerIn: parent
                spacing: 3

                Repeater {
                    id: phoneLinkGlyphs
                    model: phoneLink.streams

                    MaterialSymbol {
                        required property var modelData
                        text: String(modelData)
                        fill: 1
                        iconSize: phoneLink.iconSize
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }
    }

    // ── Phone screen mirror ──────────────────────────────────────────────────
    Component {
        id: phoneMirrorGlance

        Item {
            id: phoneMirror
            readonly property real preferredWidth: root.diameter

            readonly property string deviceImageSource: BluetoothDeviceImages.sourceForPhone(KdeConnectService.activeDeviceDisplayName)
            readonly property var heroItems: [phoneMirrorAvatar]

            Rectangle {
                id: phoneMirrorAvatar
                anchors.centerIn: parent
                width: Math.round(root.diameter * 0.82)
                height: width
                radius: width / 2
                color: Appearance.colors.colPrimaryContainer
                clip: true

                Image {
                    id: glanceDeviceImg
                    anchors.fill: parent
                    anchors.margins: 2
                    source: phoneMirror.deviceImageSource
                    fillMode: Image.PreserveAspectFit
                    visible: phoneMirror.deviceImageSource !== "" && status === Image.Ready
                    smooth: true
                    mipmap: true
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !glanceDeviceImg.visible || phoneMirror.deviceImageSource === ""
                    text: "smartphone"
                    fill: 1
                    iconSize: Math.round(parent.width * 0.6)
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            // The phone screen is being recorded to a file.
            Rectangle {
                visible: PhoneScrcpyService.recordingRunning
                anchors.right: phoneMirrorAvatar.right
                anchors.top: phoneMirrorAvatar.top
                width: Math.max(8, Math.round(root.diameter * 0.26))
                height: width
                radius: width / 2
                color: Appearance.colors.colError
            }
        }
    }

    // ── Bluetooth devices: earbuds, phone ────────────────────────────────────
    // A device's glyph in a ring whose sweep is its battery. Painted once per change of
    // level or colour: a Canvas holds its image between paints, so the bubble at rest
    // costs nothing. A device with no battery reading (`percent` < 0) is the glyph alone.
    // Handed the bubble's metrics like CountBadge: an inline component cannot see `root`.
    component BatteryRing: Item {
        id: batteryRing
        required property real diameter
        required property color glyphColor
        property int percent: -1
        property string glyph: "bluetooth"

        readonly property real preferredWidth: batteryRing.diameter
        // The ring is the device: it lands on the card's avatar whole.
        readonly property var heroItems: [batteryRing]
        readonly property color ringColor: batteryRing.percent <= 15
            ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
        readonly property color trackColor: Appearance.colors.colSurfaceContainerHighest

        onPercentChanged: ring.requestPaint()
        onRingColorChanged: ring.requestPaint()
        onTrackColorChanged: ring.requestPaint()

        Canvas {
            id: ring
            anchors.fill: parent
            anchors.margins: 2
            visible: batteryRing.percent >= 0
            // A first battery reading shows a ring that was never painted.
            onVisibleChanged: {
                if (ring.visible)
                    ring.requestPaint();
            }
            onPaint: {
                const ctx = ring.getContext("2d");
                const line = 2.5;
                const r = Math.min(ring.width, ring.height) / 2 - line / 2;
                const cx = ring.width / 2, cy = ring.height / 2;
                ctx.reset();
                ctx.lineWidth = line;
                ctx.lineCap = "round";
                ctx.strokeStyle = batteryRing.trackColor;
                ctx.beginPath();
                ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                ctx.stroke();
                const sweep = Math.max(0, Math.min(100, batteryRing.percent)) / 100;
                if (sweep <= 0)
                    return;
                ctx.strokeStyle = batteryRing.ringColor;
                ctx.beginPath();
                ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + sweep * 2 * Math.PI);
                ctx.stroke();
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: batteryRing.glyph
            fill: 1
            iconSize: Math.round(batteryRing.diameter * 0.5)
            color: batteryRing.glyphColor
        }
    }

    Component {
        id: earbudsGlance

        BatteryRing {
            diameter: root.diameter
            glyphColor: root.colText
            percent: EarbudsControlService.glancePercent
            glyph: "headphones"
        }
    }

    Component {
        id: phoneGlance

        BatteryRing {
            readonly property var device: BluetoothStatus.phoneDevice
            diameter: root.diameter
            glyphColor: root.colText
            percent: (device && device.batteryAvailable) ? Math.round(device.battery * 100) : -1
            glyph: "smartphone"
        }
    }

    // ── System tray ──────────────────────────────────────────────────────────
    // The chevron the bar's tray overflow button wears — the tray's own mark, not one
    // program's icon — and a badge saying how many programs wait inside the card.
    Component {
        id: systemTrayGlance

        Item {
            id: tray
            readonly property var items: TrayService.pinnedItems.concat(TrayService.unpinnedItems)
            readonly property real preferredWidth: root.diameter

            MaterialSymbol {
                anchors.centerIn: parent
                text: "expand_more"
                fill: 1
                iconSize: root.glyphSize(0.55)
                color: Appearance.colors.colPrimary
            }

            CountBadge {
                diameter: root.diameter
                visible: tray.items.length > 1
                label: String(tray.items.length)
            }
        }
    }

    // ── Drop Shelf ───────────────────────────────────────────────────────────
    // The drop shelf's glyph ("shelves"), with the item count in a badge when multiple.
    Component {
        id: shelfGlance

        Item {
            id: shelfItem
            readonly property var items: FileShelf.items
            readonly property real preferredWidth: root.diameter

            MaterialSymbol {
                anchors.centerIn: parent
                text: "shelves"
                fill: 1
                iconSize: root.glyphSize(0.55)
                color: Appearance.colors.colTertiary
            }

            CountBadge {
                diameter: root.diameter
                visible: shelfItem.items.length > 1
                label: String(shelfItem.items.length)
            }
        }
    }

    // ── EasyEffects ──────────────────────────────────────────────────────────
    // The loaded preset's glyph ("music_note" for "A50 · Music"), dimmed and unfilled
    // while every effect is bypassed. A scroll steps through the device's presets; the
    // touchpad's small deltas add up to one notch before anything switches.
    Component {
        id: easyEffectsGlance

        Item {
            id: effects
            readonly property real preferredWidth: root.diameter
            readonly property var heroItems: [effectsIcon]
            property real wheelDelta: 0

            MaterialSymbol {
                id: effectsIcon
                anchors.centerIn: parent
                text: EasyEffects.iconFor(EasyEffects.outputPreset)
                iconSize: root.glyphSize(0.54)
                fill: EasyEffects.bypassed ? 0 : 1
                color: EasyEffects.bypassed ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                opacity: EasyEffects.bypassed ? 0.6 : 1

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            WheelHandler {
                enabled: root.interactive
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    effects.wheelDelta += event.angleDelta.y;
                    if (Math.abs(effects.wheelDelta) < 120)
                        return;
                    EasyEffects.cyclePreset(effects.wheelDelta > 0 ? -1 : 1);
                    effects.wheelDelta = 0;
                }
            }
        }
    }

    // ── Soundscapes ──────────────────────────────────────────────────────────
    // The first sound of the mix, as the app draws it: its pictogram in its group's tone.
    // While the mix plays, rings leave the disc and fade towards the rim, the way a sound
    // spreads; paused, the rings stop, the pictogram dims and a pause badge sits on the
    // rim. With a sleep timer running the bubble widens into a pill with the time left.
    Component {
        id: soundscapesGlance

        Item {
            id: scape

            readonly property bool playing: SoundscapesService.playing
            readonly property bool timed: SoundscapesService.timerRunning
            readonly property var ids: SoundscapesService.active
            readonly property var lead: SoundscapesService.sound(scape.ids[0] ?? "")
            readonly property int tone: SoundscapesService.styleOf(scape.lead?.groupId ?? "").tone
            readonly property color tint: scape.tone === 1 ? Appearance.colors.colSecondaryContainer
                : scape.tone === 2 ? Appearance.colors.colTertiaryContainer : Appearance.colors.colPrimaryContainer
            readonly property color onTint: scape.tone === 1 ? Appearance.colors.colOnSecondaryContainer
                : scape.tone === 2 ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnPrimaryContainer
            readonly property color accent: scape.tone === 1 ? Appearance.colors.colSecondary
                : scape.tone === 2 ? Appearance.colors.colTertiary : Appearance.colors.colPrimary
            readonly property real discSize: root.diameter - 8
            // Folded to the disc while no timer runs; the weight stays one circle's so that the
            // row is not re-dealt each time a timer starts or ends.
            readonly property real preferredWidth: scape.timed
                ? (root.diameter - scape.discSize) / 2 + row.implicitWidth + root.endPadding
                : root.diameter
            readonly property real balanceWidth: root.diameter
            readonly property var heroItems: [disc]
            property real wheelDelta: 0

            Row {
                id: row
                x: (root.diameter - scape.discSize) / 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Item {
                    width: scape.discSize
                    height: scape.discSize
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: 2

                        Rectangle {
                            id: ripple
                            required property int index
                            anchors.centerIn: parent
                            width: scape.discSize
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.width: 1.5
                            border.color: scape.accent
                            opacity: 0
                            scale: 1

                            SequentialAnimation {
                                running: scape.playing && !Appearance.motionOff
                                loops: Animation.Infinite
                                PauseAnimation { duration: ripple.index * 1300 }
                                ParallelAnimation {
                                    NumberAnimation { target: ripple; property: "scale"; from: 1; to: 1.32; duration: 2600; easing.type: Easing.OutCubic }
                                    SequentialAnimation {
                                        NumberAnimation { target: ripple; property: "opacity"; from: 0; to: 0.55; duration: 260 }
                                        NumberAnimation { target: ripple; property: "opacity"; to: 0; duration: 2340; easing.type: Easing.OutQuad }
                                    }
                                }
                                onRunningChanged: if (!running) { ripple.opacity = 0; ripple.scale = 1; }
                            }
                        }
                    }

                    Rectangle {
                        id: disc
                        anchors.centerIn: parent
                        width: scape.discSize
                        height: width
                        radius: width / 2
                        color: scape.playing ? scape.tint : Appearance.colors.colSurfaceContainerHighest
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        SoundIcon {
                            anchors.centerIn: parent
                            width: Math.round(scape.discSize * 0.56)
                            height: width
                            source: scape.lead?.icon ?? ""
                            color: scape.playing ? scape.onTint : Appearance.colors.colSubtext
                            opacity: scape.playing ? 1 : 0.7
                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }

                        // No pictogram (the library is still loading, or the sound is gone)
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: !scape.lead || (scape.lead.icon ?? "") === ""
                            text: "waves"
                            fill: 1
                            iconSize: Math.round(scape.discSize * 0.56)
                            color: scape.playing ? scape.onTint : Appearance.colors.colSubtext
                        }
                    }
                }

                StyledText {
                    id: scapeTime
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: scape.timed ? 1 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(scapeTime)
                    }
                    text: SoundscapesService.formatTime(SoundscapesService.timerLeft)
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    font.features: ({ "tnum": 1 })
                    color: root.colText
                }
            }

            // How many sounds are in the mix, or that it is paused. Inside the island itself
            // (glanceOnly) the glance is small and the badge is dropped.
            CountBadge {
                diameter: root.diameter
                visible: !root.glanceOnly && !scape.timed && (!scape.playing || scape.ids.length > 1)
                glyph: scape.playing ? "" : "pause"
                label: String(scape.ids.length)
            }

            WheelHandler {
                enabled: root.interactive
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    scape.wheelDelta += event.angleDelta.y;
                    if (Math.abs(scape.wheelDelta) < 40)
                        return;
                    SoundscapesService.setMaster(Math.max(0, Math.min(1, SoundscapesService.master + (scape.wheelDelta > 0 ? 0.05 : -0.05))));
                    scape.wheelDelta = 0;
                }
            }
        }
    }

    // ── Quick Share ──────────────────────────────────────────────────────────
    // A phone glyph on a disc. Visible to nearby devices: rings leave the disc, the way a
    // signal spreads. Moving a file: the rim fills as a progress ring. A request waiting
    // for an answer: the disc turns to the accent and a badge counts what is waiting.
    Component {
        id: quickShareGlance

        Item {
            id: share

            readonly property bool waiting: QuickShareService.incoming.length > 0
            readonly property bool moving: QuickShareService.active.some(t => t.state === "ReceivingFiles" || t.state === "SendingFiles")
            readonly property bool discoverable: QuickShareService.visibility !== "invisible"
            readonly property real fraction: {
                const t = QuickShareService.active.find(x => x.state === "ReceivingFiles" || x.state === "SendingFiles");
                const m = t?.meta ?? {};
                return m.total_bytes > 0 ? Math.min(1, m.ack_bytes / m.total_bytes) : 0;
            }
            readonly property real discSize: root.diameter - 8
            readonly property real preferredWidth: root.diameter
            readonly property real balanceWidth: root.diameter
            readonly property var heroItems: [shareDisc]

            Item {
                id: shareBox
                x: (root.diameter - share.discSize) / 2
                anchors.verticalCenter: parent.verticalCenter
                width: share.discSize
                height: share.discSize

                Repeater {
                    model: 2

                    Rectangle {
                        id: shareRipple
                        required property int index
                        anchors.centerIn: parent
                        width: share.discSize
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 1.5
                        border.color: Appearance.colors.colPrimary
                        opacity: 0
                        scale: 1

                        SequentialAnimation {
                            running: share.discoverable && !share.moving && !Appearance.motionOff
                            loops: Animation.Infinite
                            PauseAnimation { duration: shareRipple.index * 1300 }
                            ParallelAnimation {
                                NumberAnimation { target: shareRipple; property: "scale"; from: 1; to: 1.32; duration: 2600; easing.type: Easing.OutCubic }
                                SequentialAnimation {
                                    NumberAnimation { target: shareRipple; property: "opacity"; from: 0; to: 0.55; duration: 260 }
                                    NumberAnimation { target: shareRipple; property: "opacity"; to: 0; duration: 2340; easing.type: Easing.OutQuad }
                                }
                            }
                            onRunningChanged: if (!running) { shareRipple.opacity = 0; shareRipple.scale = 1; }
                        }
                    }
                }

                Rectangle {
                    id: shareDisc
                    anchors.centerIn: parent
                    width: share.discSize
                    height: width
                    radius: width / 2
                    color: share.waiting ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainer
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "send_to_mobile"
                        fill: 1
                        iconSize: Math.round(share.discSize * 0.56)
                        color: share.waiting ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                    }
                }

                // Progress rim while a file moves.
                Canvas {
                    anchors.fill: parent
                    visible: share.moving
                    property real f: share.fraction
                    onFChanged: requestPaint()
                    onVisibleChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.lineWidth = 2.5;
                        ctx.lineCap = "round";
                        ctx.strokeStyle = Appearance.colors.colPrimary;
                        ctx.beginPath();
                        ctx.arc(width / 2, height / 2, width / 2 - 1.5, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.02, f));
                        ctx.stroke();
                    }
                }
            }

            CountBadge {
                diameter: root.diameter
                visible: !root.glanceOnly && share.waiting
                label: String(QuickShareService.incoming.length)
            }
        }
    }
    // Background jobs: a disc whose rim fills with how far the running ones have got, a
    // check when they are done and the error tint if one failed. A badge counts them when
    // there are several. The card lists them.
    Component {
        id: progressGlance

        Item {
            id: jobs

            readonly property var running: ProgressService.runningJobs
            readonly property bool failed: jobs.running.length === 0 && ProgressService.jobs.some(j => j.state === "failed")
            readonly property real discSize: root.diameter - 8
            readonly property real preferredWidth: root.diameter
            readonly property real balanceWidth: root.diameter
            readonly property var heroItems: [jobsDisc]

            Item {
                id: jobsBox
                x: (root.diameter - jobs.discSize) / 2
                anchors.verticalCenter: parent.verticalCenter
                width: jobs.discSize
                height: jobs.discSize

                Rectangle {
                    id: jobsDisc
                    anchors.centerIn: parent
                    width: jobs.discSize
                    height: width
                    radius: width / 2
                    color: jobs.failed ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: jobs.running.length > 0 ? (jobs.running[0].icon ?? "downloading") : (jobs.failed ? "error" : (ProgressService.pausedJobs.length > 0 && ProgressService.pausedJobs.length === ProgressService.jobs.length ? "pause" : "check"))
                        fill: 1
                        iconSize: Math.round(jobs.discSize * 0.56)
                        color: jobs.failed ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
                    }
                }

                Canvas {
                    anchors.fill: parent
                    property real f: ProgressService.overallFraction
                    property color stroke: jobs.failed ? Appearance.colors.colError : Appearance.colors.colPrimary
                    onFChanged: requestPaint()
                    onStrokeChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.lineWidth = 2.5;
                        ctx.lineCap = "round";
                        ctx.strokeStyle = stroke;
                        ctx.beginPath();
                        ctx.arc(width / 2, height / 2, width / 2 - 1.5, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.02, Math.min(1, f)));
                        ctx.stroke();
                    }
                }
            }

            CountBadge {
                diameter: root.diameter
                visible: !root.glanceOnly && jobs.running.length > 1
                label: String(jobs.running.length)
            }
        }
    }

    // CPU or memory held high: an error-tinted disc with the metric's glyph, and a rim that
    // is how full it is right now.
    Component {
        id: monitorAlertGlance

        Item {
            id: alert

            readonly property bool isMemory: ResourceAlerts.kind === "memory"
            readonly property real discSize: root.diameter - 8
            readonly property real preferredWidth: root.diameter
            readonly property real balanceWidth: root.diameter
            readonly property var heroItems: [alertDisc]

            Item {
                id: alertBox
                x: (root.diameter - alert.discSize) / 2
                anchors.verticalCenter: parent.verticalCenter
                width: alert.discSize
                height: alert.discSize

                Rectangle {
                    id: alertDisc
                    anchors.centerIn: parent
                    width: alert.discSize
                    height: width
                    radius: width / 2
                    color: Appearance.colors.colErrorContainer

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: alert.isMemory ? "memory" : "speed"
                        fill: 1
                        iconSize: Math.round(alert.discSize * 0.56)
                        color: Appearance.colors.colOnErrorContainer
                    }
                }

                Canvas {
                    anchors.fill: parent
                    property real f: ResourceAlerts.value
                    onFChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.lineWidth = 2.5;
                        ctx.lineCap = "round";
                        ctx.strokeStyle = Appearance.colors.colError;
                        ctx.beginPath();
                        ctx.arc(width / 2, height / 2, width / 2 - 1.5, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.02, Math.min(1, f)));
                        ctx.stroke();
                    }
                }
            }
        }
    }

    // A Grit focus session: the tag's shape and the time left, folding to the shape alone
    // while paused. The card pauses, skips or opens Focus.
    Component {
        id: focusGlance

        Item {
            id: focus

            readonly property bool running: GritService.timerRunning
            readonly property bool onBreak: GritService.timerPhase !== "focus"
            readonly property int secondsLeft: GritService.timerSecondsLeft
            readonly property real markerSize: root.diameter - 10
            readonly property real preferredWidth: focus.running
                ? (root.diameter - focus.markerSize) / 2 + focusRow.implicitWidth + root.endPadding
                : root.diameter
            readonly property var heroItems: [focusMarker, focusText]

            Row {
                id: focusRow
                x: (root.diameter - focus.markerSize) / 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                MaterialShapeWrappedMaterialSymbol {
                    id: focusMarker
                    anchors.verticalCenter: parent.verticalCenter
                    shape: focus.onBreak ? "SoftBurst" : String(GritService.activeTag?.shape ?? "Cookie7Sided")
                    implicitSize: focus.markerSize
                    iconSize: Appearance.font.pixelSize.normal
                    padding: 3
                    text: !focus.running ? "pause" : (focus.onBreak ? "coffee" : "psychiatry")
                    color: focus.onBreak ? Appearance.colors.colTertiaryContainer : Appearance.colors.colPrimary
                    colSymbol: focus.onBreak ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnPrimary
                }

                StyledText {
                    id: focusText
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: focus.running ? 1 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(focusText)
                    }
                    text: String(Math.floor(focus.secondsLeft / 60)).padStart(2, "0") + ":" + String(focus.secondsLeft % 60).padStart(2, "0")
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    font.features: ({ "tnum": 1 })
                    color: root.colText
                }
            }
        }
    }

    // The next prayer as a small sky: a disc bearing that prayer's own glyph (dawn, sun, dusk,
    // night), a rim that fills as the wait goes by with a bead riding its end, and the minutes
    // left in a small badge on the corner. Once the time has come the rim is full and the glyph is filled.
    Component {
        id: prayerGlance

        Item {
            id: prayer

            readonly property var current: PrayerTimes.glancePrayer
            readonly property bool begun: PrayerTimes.glanceBegan
            readonly property string prayerId: prayer.current?.id ?? ""
            readonly property real fraction: prayer.begun ? 1 : PrayerTimes.progress
            readonly property real discSize: root.diameter - 8
            readonly property real preferredWidth: root.diameter
            readonly property real balanceWidth: root.diameter
            readonly property var heroItems: [prayerDisc]

            function glyphFor(id: string): string {
                switch (id) {
                case "Fajr": return "wb_twilight";
                case "Dhuhr": return "light_mode";
                case "Asr": return "wb_sunny";
                case "Maghrib": return "wb_twilight";
                case "Isha": return "bedtime";
                }
                return "mosque";
            }
            // Dawn and dusk lean on the warm tertiary, noon on primary, night on the cool secondary.
            readonly property bool nightish: prayer.prayerId === "Isha" || prayer.prayerId === "Fajr"
            readonly property color rim: prayer.nightish ? Appearance.colors.colSecondary
                : (prayer.prayerId === "Maghrib" ? Appearance.colors.colTertiary : Appearance.colors.colPrimary)
            readonly property color discColor: prayer.nightish ? Appearance.colors.colSecondaryContainer
                : (prayer.prayerId === "Maghrib" ? Appearance.colors.colTertiaryContainer : Appearance.colors.colPrimaryContainer)
            readonly property color onDisc: prayer.nightish ? Appearance.colors.colOnSecondaryContainer
                : (prayer.prayerId === "Maghrib" ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnPrimaryContainer)

            Item {
                x: (root.diameter - prayer.discSize) / 2
                anchors.verticalCenter: parent.verticalCenter
                width: prayer.discSize
                height: prayer.discSize

                Rectangle {
                    id: prayerDisc
                    anchors.centerIn: parent
                    width: prayer.discSize
                    height: width
                    radius: width / 2
                    color: prayer.discColor
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: prayer.glyphFor(prayer.prayerId)
                        fill: prayer.begun ? 1 : 0
                        iconSize: Math.round(prayer.discSize * 0.56)
                        color: prayer.onDisc
                    }
                }

                Canvas {
                    anchors.fill: parent
                    anchors.margins: -3
                    property real f: prayer.fraction
                    property color stroke: prayer.rim
                    onFChanged: requestPaint()
                    onStrokeChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        const r = width / 2 - 4.5;
                        const a0 = -Math.PI / 2;
                        const a1 = a0 + Math.PI * 2 * Math.max(0.03, Math.min(1, f));
                        ctx.lineWidth = 2.5;
                        ctx.lineCap = "round";
                        ctx.strokeStyle = stroke;
                        ctx.beginPath();
                        ctx.arc(width / 2, height / 2, r, a0, a1);
                        ctx.stroke();
                        // The bead: the sun on its way round.
                        if (f < 1) {
                            ctx.fillStyle = stroke;
                            ctx.beginPath();
                            ctx.arc(width / 2 + r * Math.cos(a1), height / 2 + r * Math.sin(a1), 3.2, 0, Math.PI * 2);
                            ctx.fill();
                        }
                    }
                }
            }

            CountBadge {
                diameter: root.diameter
                visible: !root.glanceOnly && !prayer.begun && prayer.current !== null
                label: String(PrayerTimes.minutesToNext)
            }
        }
    }
}
