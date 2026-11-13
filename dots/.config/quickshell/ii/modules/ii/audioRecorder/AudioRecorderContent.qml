pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The recorder page follows the windowed app pattern: a shared top bar, a compact
 * recorder pane, a persistent player pane, and a list that owns the remaining height.
 * Capture and playback live in AudioRecorderService, so closing this view is harmless.
 */
FocusScope {
    id: root

    signal closeRequested()

    readonly property var svc: AudioRecorderService
    readonly property bool compact: root.width < ClockStyle.compactMax
    readonly property bool dense: root.height < 650
    readonly property bool active: root.svc.recording
    readonly property bool hasSelection: root.svc.selectedEntry !== null
    readonly property string stateLabel: root.svc.starting
        ? Translation.tr("Starting…")
        : root.active
            ? (root.svc.paused ? Translation.tr("Paused") : Translation.tr("Recording"))
            : Translation.tr("Ready")
    readonly property real displayedPosition: playbackSlider.pressed
        ? playbackSlider.value : root.svc.playbackPosition

    focus: true

    function recordButtonLabel(): string {
        if (root.svc.starting)
            return Translation.tr("Starting…");
        return root.active ? Translation.tr("Stop") : Translation.tr("Record");
    }

    function playbackButtonLabel(): string {
        if (root.svc.playbackError.length > 0)
            return Translation.tr("Retry");
        if (root.svc.loading)
            return Translation.tr("Loading audio");
        return root.svc.playing ? Translation.tr("Pause") : Translation.tr("Play");
    }

    function durationFor(entry): string {
        if (!entry || String(entry.path) !== root.svc.selectedPath || root.svc.playbackDuration <= 0)
            return "";
        return root.svc.formatElapsed(root.svc.playbackDuration);
    }

    // Controls and the native slider own Space and arrows. The page only handles those
    // keys when focus is still on the page itself, so keyboard seeking is never hijacked.
    function interactiveChildHasFocus(): bool {
        const focused = root.Window.window?.activeFocusItem;
        return focused !== null && focused !== undefined && focused !== root;
    }

    function restorePlaybackBinding(): void {
        playbackSlider.value = Qt.binding(() => root.svc.playbackDuration > 0
            ? root.svc.playbackPosition : 0);
    }

    Component.onCompleted: {
        root.forceActiveFocus();
        root.svc.refresh();
    }

    Keys.onPressed: event => {
        const navigationKey = event.key === Qt.Key_Space || event.key === Qt.Key_Left
            || event.key === Qt.Key_Right || event.key === Qt.Key_Up || event.key === Qt.Key_Down;
        if (root.interactiveChildHasFocus() && navigationKey)
            return;

        if (event.key === Qt.Key_Escape
                || ((event.modifiers & Qt.ControlModifier)
                    && (event.key === Qt.Key_W || event.key === Qt.Key_Q))) {
            root.closeRequested();
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R) {
            if (root.active)
                root.svc.stopRecording();
            else
                root.svc.startRecording();
            event.accepted = true;
        } else if (event.key === Qt.Key_Space) {
            if (root.active)
                root.svc.togglePause();
            else
                root.svc.togglePlayback();
            event.accepted = true;
        } else if (event.key === Qt.Key_P && root.active) {
            root.svc.togglePause();
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.paneGap
        anchors.topMargin: ClockStyle.gapTiny
        spacing: ClockStyle.gapTiny

        ClockTopBar {
            Layout.fillWidth: true
            title: Translation.tr("Audio recorder")
            subtitle: Translation.tr("48 kHz stereo WAV  ·  Ctrl+R record  ·  Space play/pause")
            onCloseRequested: root.closeRequested()

            ClockIconButton {
                symbol: "refresh"
                tooltip: Translation.tr("Refresh recordings")
                Accessible.name: Translation.tr("Refresh recordings")
                focusPolicy: Qt.StrongFocus
                borderWidth: activeFocus ? 2 : 0
                borderColor: ClockStyle.colFocus
                onClicked: root.svc.refresh()
            }

            ClockIconButton {
                symbol: "folder_open"
                tooltip: Translation.tr("Open recordings folder")
                Accessible.name: Translation.tr("Open recordings folder")
                focusPolicy: Qt.StrongFocus
                borderWidth: activeFocus ? 2 : 0
                borderColor: ClockStyle.colFocus
                onClicked: root.svc.openFolder()
            }
        }

        ColumnLayout {
            id: page
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.compact ? ClockStyle.gapTiny : ClockStyle.paneGap

            StyledFlickable {
                id: contentFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: contentColumn.height
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                // The nested recordings ListView carries the persistent compact
                // affordance; this page bar appears while the surrounding body is moved.
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                ColumnLayout {
                    id: contentColumn
                    width: contentFlickable.width
                    height: Math.max(contentFlickable.height, implicitHeight)
                    spacing: root.compact ? ClockStyle.gapSmall : ClockStyle.paneGap

                    Rectangle {
                        id: recorderPane
                        Layout.fillWidth: true
                        Layout.minimumHeight: 0
                        implicitHeight: recorderRow.implicitHeight + ClockStyle.gapLarge * 2
                        radius: ClockStyle.radiusCard
                        color: ClockStyle.colPane

                        RowLayout {
                            id: recorderRow
                            anchors {
                                fill: parent
                                leftMargin: ClockStyle.gapLarge
                                rightMargin: ClockStyle.gapLarge
                                topMargin: ClockStyle.gapLarge
                                bottomMargin: ClockStyle.gapLarge
                            }
                            spacing: ClockStyle.gap

                            RowLayout {
                                id: captureControls
                                spacing: ClockStyle.gapSmall

                                ClockButton {
                                    id: recordButton
                                    Layout.preferredWidth: root.compact ? 128 : 148
                                    Layout.minimumWidth: root.compact ? 112 : 136
                                    symbol: root.active ? "stop" : "fiber_manual_record"
                                    label: root.recordButtonLabel()
                                    variant: "filled"
                                    danger: root.active
                                    enabled: !root.svc.starting && !root.svc.stopping
                                    focusPolicy: Qt.StrongFocus
                                    borderWidth: activeFocus ? 2 : 0
                                    borderColor: root.active ? ClockStyle.colOnError : ClockStyle.colFocus
                                    Accessible.name: root.active
                                        ? Translation.tr("Stop recording") : Translation.tr("Start recording")
                                    onClicked: root.svc.toggle()
                                }

                                ClockButton {
                                    id: pauseButton
                                    Layout.preferredWidth: root.compact ? 48 : 118
                                    symbol: root.svc.paused ? "play_arrow" : "pause"
                                    label: root.svc.paused ? Translation.tr("Resume") : Translation.tr("Pause")
                                    iconOnly: root.compact
                                    variant: "tonal"
                                    enabled: root.active
                                    focusPolicy: Qt.StrongFocus
                                    borderWidth: activeFocus ? 2 : 0
                                    borderColor: ClockStyle.colFocus
                                    Accessible.name: root.svc.paused
                                        ? Translation.tr("Resume recording") : Translation.tr("Pause recording")
                                    onClicked: root.svc.togglePause()
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                visible: !captureDetail.visible
                            }

                            StyledText {
                                id: captureDetail
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                visible: root.svc.currentFile.length > 0 || root.svc.error.length > 0
                                text: root.svc.error.length > 0 ? root.svc.error : root.svc.currentFile
                                color: root.svc.error.length > 0 ? ClockStyle.colError : ClockStyle.colSubtext
                                font.pixelSize: ClockStyle.textSmall
                                elide: Text.ElideMiddle
                                property bool hovered: captureDetailHover.hovered
                                Accessible.name: text

                                HoverHandler { id: captureDetailHover }
                                StyledToolTip {
                                    text: captureDetail.text
                                    extraVisibleCondition: captureDetail.truncated
                                    requireOverlay: false
                                }
                            }

                            RowLayout {
                                id: timerStatus
                                spacing: ClockStyle.gapSmall

                                StyledText {
                                    id: elapsedLabel
                                    Layout.minimumWidth: 84
                                    Layout.preferredWidth: Math.max(84, elapsedLabel.implicitWidth)
                                    text: root.svc.formatElapsed(root.svc.elapsed)
                                    color: ClockStyle.colOnSurface
                                    font.pixelSize: ClockStyle.textTitle + 4
                                    font.family: ClockStyle.fontNumbers
                                }

                                RowLayout {
                                    spacing: ClockStyle.gapSmall

                                    Rectangle {
                                        implicitWidth: 9
                                        implicitHeight: 9
                                        radius: 5
                                        color: root.svc.starting ? ClockStyle.colTertiary
                                            : root.active ? (root.svc.paused ? ClockStyle.colTertiary : ClockStyle.colError)
                                            : ClockStyle.colSubtext
                                    }

                                    StyledText {
                                        text: root.stateLabel
                                        color: root.active && !root.svc.paused
                                            ? ClockStyle.colError : ClockStyle.colOnSurface
                                        font.pixelSize: ClockStyle.textNormal
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: recordingsPane
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        // Keep the nested list useful even when the page is short. The outer
                        // flickable absorbs any remaining overflow instead of collapsing its
                        // viewport below one complete, keyboard reachable row.
                        Layout.minimumHeight: Math.max(listHeader.implicitHeight, ClockStyle.buttonHeight)
                            + (root.compact ? ClockStyle.gapSmall : ClockStyle.cardPadding)
                            + ClockStyle.gap
                            + ClockStyle.cardPadding + 60
                        radius: ClockStyle.radiusCard
                        color: ClockStyle.colPane
                        clip: true

                        RowLayout {
                            id: listHeader
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                leftMargin: ClockStyle.cardPadding
                                rightMargin: ClockStyle.cardPadding
                                topMargin: root.compact ? ClockStyle.gapSmall : ClockStyle.cardPadding
                            }
                            spacing: ClockStyle.gap

                            ClockBadge {
                                size: root.compact ? 32 : 44
                                text: "library_music"
                                shape: MaterialShape.Shape.Cookie9Sided
                                color: ClockStyle.colPrimary
                                colSymbol: ClockStyle.colOnPrimary
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Recordings")
                                color: ClockStyle.colOnBackground
                                font.family: Appearance.font.family.title
                                font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                                font.pixelSize: root.compact ? ClockStyle.textLarge : Appearance.font.pixelSize.huge
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                visible: root.svc.recordings.length >= 0
                                implicitWidth: Math.max(28, recordingCount.implicitWidth + 16)
                                implicitHeight: 28
                                radius: 14
                                color: ClockStyle.colSecondaryContainer

                                StyledText {
                                    id: recordingCount
                                    anchors.centerIn: parent
                                    text: String(root.svc.recordings.length)
                                    font.pixelSize: ClockStyle.textSmall
                                    color: ClockStyle.colOnSecondaryContainer
                                }
                            }

                            ClockIconButton {
                                symbol: "refresh"
                                tooltip: Translation.tr("Refresh recordings")
                                Accessible.name: Translation.tr("Refresh recordings")
                                focusPolicy: Qt.StrongFocus
                                borderWidth: activeFocus ? 2 : 0
                                borderColor: ClockStyle.colFocus
                                onClicked: root.svc.refresh()
                            }

                            ClockIconButton {
                                symbol: "folder_open"
                                tooltip: Translation.tr("Open recordings folder")
                                Accessible.name: Translation.tr("Open recordings folder")
                                focusPolicy: Qt.StrongFocus
                                borderWidth: activeFocus ? 2 : 0
                                borderColor: ClockStyle.colFocus
                                onClicked: root.svc.openFolder()
                            }
                        }

                        Item {
                            id: recordingsBody
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: listHeader.bottom
                                bottom: parent.bottom
                                leftMargin: ClockStyle.cardPadding
                                rightMargin: ClockStyle.cardPadding
                                topMargin: root.compact ? ClockStyle.gapTiny : ClockStyle.gap
                                bottomMargin: root.compact ? ClockStyle.gapSmall : ClockStyle.cardPadding
                            }
                            visible: root.svc.recordings.length > 0

                            ListView {
                                id: list
                                anchors.fill: parent
                                clip: true
                                spacing: ClockStyle.gapTiny
                                boundsBehavior: Flickable.StopAtBounds
                                model: root.svc.recordings
                                WheelScroll {}
                                ScrollBar.vertical: StyledScrollBar {
                                    policy: root.compact ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                                }

                                delegate: RippleButton {
                                    id: row
                                    required property var modelData
                                    width: list.width
                                    implicitHeight: 60
                                    focusPolicy: Qt.StrongFocus
                                    toggled: root.svc.selectedPath === String(row.modelData.path)
                                    buttonRadius: ClockStyle.radiusNormal
                                    buttonRadiusPressed: ClockStyle.radiusNormal
                                    interactionScale: 1
                                    scaleBehaviorEnabled: false
                                    colBackground: "transparent"
                                    colBackgroundHover: Qt.alpha(ClockStyle.colOnSurface, 0.04)
                                    colBackgroundActive: Qt.alpha(ClockStyle.colOnSurface, 0.08)
                                    colBackgroundToggled: Qt.alpha(ClockStyle.colPrimary, 0.10)
                                    colBackgroundToggledHover: Qt.alpha(ClockStyle.colPrimary, 0.14)
                                    colBackgroundToggledActive: Qt.alpha(ClockStyle.colPrimary, 0.18)
                                    colRipple: Qt.alpha(ClockStyle.colOnSurface, 0.08)
                                    colRippleToggled: Qt.alpha(ClockStyle.colPrimary, 0.12)
                                    borderWidth: row.activeFocus ? 2 : 0
                                    borderColor: ClockStyle.colFocus
                                    Accessible.name: row.modelData.name
                                    Accessible.description: Translation.tr("Select recording")
                                    onClicked: root.svc.selectRecording(row.modelData)

                                    property bool confirmDelete: false

                                    Timer {
                                        id: confirmTimer
                                        interval: 2600
                                        onTriggered: row.confirmDelete = false
                                    }

                                    contentItem: RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: root.compact ? ClockStyle.gapTiny : ClockStyle.gapSmall
                                        spacing: ClockStyle.gapSmall

                                        Rectangle {
                                            implicitWidth: 36
                                            implicitHeight: 36
                                            radius: ClockStyle.radiusSmall
                                            color: row.toggled ? Qt.alpha(ClockStyle.colPrimary, 0.16) : ClockStyle.colSurfaceHigh

                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: row.toggled && root.svc.playing ? "equalizer"
                                                    : row.toggled ? "check" : "graphic_eq"
                                                iconSize: 20
                                                color: row.toggled ? ClockStyle.colPrimary : ClockStyle.colOnSurfaceVariant
                                                fill: 1
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 1

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: row.modelData.name
                                                color: ClockStyle.colOnSurface
                                                font.pixelSize: ClockStyle.textNormal
                                                font.weight: Font.Medium
                                                elide: Text.ElideMiddle
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: [root.durationFor(row.modelData),
                                                    root.svc.formatSize(row.modelData.size),
                                                    root.svc.formatWhen(row.modelData.mtime)]
                                                    .filter(part => part.length > 0).join("  ·  ")
                                                color: ClockStyle.colSubtext
                                                font.pixelSize: ClockStyle.textSmall
                                                elide: Text.ElideRight
                                            }
                                        }

                                        ClockIconButton {
                                            symbol: row.toggled && root.svc.playing ? "pause" : "play_arrow"
                                            tooltip: row.toggled && root.svc.playing
                                                ? Translation.tr("Pause") : Translation.tr("Play")
                                            Accessible.name: row.toggled && root.svc.playing
                                                ? Translation.tr("Pause %1").arg(row.modelData.name)
                                                : Translation.tr("Play %1").arg(row.modelData.name)
                                            toggled: row.toggled && root.svc.playing
                                            focusPolicy: Qt.StrongFocus
                                            borderWidth: activeFocus ? 2 : 0
                                            borderColor: ClockStyle.colFocus
                                            onClicked: root.svc.togglePlayback(row.modelData)
                                        }

                                        ClockIconButton {
                                            symbol: "folder_open"
                                            tooltip: Translation.tr("Show in folder")
                                            Accessible.name: Translation.tr("Show %1 in folder").arg(row.modelData.name)
                                            focusPolicy: Qt.StrongFocus
                                            borderWidth: activeFocus ? 2 : 0
                                            borderColor: ClockStyle.colFocus
                                            onClicked: root.svc.showInFolder(row.modelData.path)
                                        }

                                        ClockIconButton {
                                            symbol: row.confirmDelete ? "delete_forever" : "delete"
                                            tooltip: row.confirmDelete
                                                ? Translation.tr("Click again to delete") : Translation.tr("Delete")
                                            Accessible.name: row.confirmDelete
                                                ? Translation.tr("Confirm delete %1").arg(row.modelData.name)
                                                : Translation.tr("Delete %1").arg(row.modelData.name)
                                            colIcon: row.confirmDelete ? ClockStyle.colError : ClockStyle.colOnSurfaceVariant
                                            focusPolicy: Qt.StrongFocus
                                            borderWidth: activeFocus ? 2 : 0
                                            borderColor: ClockStyle.colFocus
                                            onClicked: {
                                                if (row.confirmDelete) {
                                                    root.svc.remove(row.modelData.path);
                                                    row.confirmDelete = false;
                                                } else {
                                                    row.confirmDelete = true;
                                                    confirmTimer.restart();
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: listHeader.bottom
                                bottom: parent.bottom
                                leftMargin: ClockStyle.cardPadding
                                rightMargin: ClockStyle.cardPadding
                                topMargin: root.compact ? ClockStyle.gapTiny : ClockStyle.gap
                                bottomMargin: root.compact ? ClockStyle.gapSmall : ClockStyle.cardPadding
                            }
                            visible: root.svc.recordings.length === 0
                            spacing: ClockStyle.gapSmall

                            ClockEmptyState {
                                Layout.alignment: Qt.AlignHCenter
                                visible: !root.compact
                                shapeSize: ClockStyle.emptyShapeSmall
                                symbol: root.svc.listLoading ? "progress_activity" : "mic_none"
                                title: root.svc.listLoading
                                    ? Translation.tr("Loading recordings")
                                    : root.svc.listError.length > 0
                                        ? Translation.tr("Could not load recordings")
                                        : Translation.tr("No recordings yet")
                                subtitle: root.svc.listError.length > 0
                                    ? root.svc.listError
                                    : Translation.tr("Finished recordings will appear here.")
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.compact
                                spacing: ClockStyle.gapSmall

                                MaterialSymbol {
                                    text: root.svc.listLoading ? "progress_activity" : "mic_none"
                                    iconSize: ClockStyle.iconNormal
                                    fill: 1
                                    color: root.svc.listError.length > 0 ? ClockStyle.colError : ClockStyle.colOnSurfaceVariant
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.svc.listLoading
                                        ? Translation.tr("Loading recordings…")
                                        : root.svc.listError.length > 0
                                            ? root.svc.listError
                                            : Translation.tr("No recordings yet")
                                    color: root.svc.listError.length > 0 ? ClockStyle.colError : ClockStyle.colSubtext
                                    font.pixelSize: ClockStyle.textSmall
                                    elide: Text.ElideRight
                                }
                            }

                            ClockButton {
                                Layout.alignment: Qt.AlignHCenter
                                visible: !root.compact && (root.svc.listError.length > 0
                                    || (!root.svc.listLoading && root.svc.recordings.length === 0))
                                symbol: root.svc.listError.length > 0 ? "refresh" : "folder_open"
                                label: root.svc.listError.length > 0
                                    ? Translation.tr("Try again") : Translation.tr("Open folder")
                                variant: "tonal"
                                focusPolicy: Qt.StrongFocus
                                borderWidth: activeFocus ? 2 : 0
                                borderColor: ClockStyle.colFocus
                                Accessible.name: root.svc.listError.length > 0
                                    ? Translation.tr("Try loading recordings again") : Translation.tr("Open recordings folder")
                                onClicked: root.svc.listError.length > 0 ? root.svc.refresh() : root.svc.openFolder()
                            }
                        }
                    }
                }
            }

            ClockPane {
                id: playerPane
                Layout.fillWidth: true
                Layout.minimumHeight: 0
                title: root.dense ? "" : Translation.tr("Playback")
                symbol: root.dense ? "" : "play_arrow"

                StyledText {
                    Layout.fillWidth: true
                    visible: !root.hasSelection
                    text: Translation.tr("Select a recording to play it.")
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textNormal
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.hasSelection
                    spacing: ClockStyle.gapSmall

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall

                        StyledText {
                            Layout.fillWidth: true
                            text: root.svc.selectedName
                            color: ClockStyle.colOnSurface
                            font.pixelSize: ClockStyle.textNormal
                            font.weight: Font.DemiBold
                            elide: Text.ElideMiddle
                        }

                        StyledText {
                            text: root.svc.loading ? Translation.tr("Loading…")
                                : root.svc.playbackError.length > 0 ? Translation.tr("Unavailable")
                                : root.svc.playing ? Translation.tr("Playing")
                                : root.svc.playbackPaused ? Translation.tr("Paused")
                                : Translation.tr("Ready")
                            color: root.svc.playbackError.length > 0 ? ClockStyle.colError : ClockStyle.colSubtext
                            font.pixelSize: ClockStyle.textSmall
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall

                        StyledText {
                            Layout.preferredWidth: 40
                            text: root.svc.formatElapsed(root.displayedPosition)
                            color: ClockStyle.colSubtext
                            font.pixelSize: ClockStyle.textSmall
                            font.family: ClockStyle.fontNumbers
                            horizontalAlignment: Text.AlignRight
                        }

                        Item {
                            Layout.fillWidth: true
                            implicitHeight: playbackSlider.implicitHeight

                            StyledSlider {
                                id: playbackSlider
                                anchors.fill: parent
                                configuration: StyledSlider.Configuration.M
                                from: 0
                                to: Math.max(1, root.svc.playbackDuration)
                                value: root.svc.playbackDuration > 0 ? root.svc.playbackPosition : 0
                                enabled: root.svc.seekable
                                Accessible.name: Translation.tr("Playback position")
                                Accessible.description: Translation.tr("Use Left and Right arrows to seek")
                                focusPolicy: Qt.StrongFocus
                                onMoved: {
                                    root.svc.seek(value);
                                    // Keyboard moves do not toggle pressed. Restore the
                                    // service binding after the native seek is requested.
                                    if (!pressed)
                                        Qt.callLater(root.restorePlaybackBinding);
                                }
                                // QQuickSlider writes value while dragging and removes the
                                // binding. Reattach it when the pointer is released.
                                onPressedChanged: if (!pressed)
                                    root.restorePlaybackBinding()
                            }

                            Rectangle {
                                anchors.fill: playbackSlider
                                color: "transparent"
                                border.width: playbackSlider.activeFocus ? 2 : 0
                                border.color: ClockStyle.colFocus
                                radius: ClockStyle.radiusSmall
                            }
                        }

                        StyledText {
                            Layout.preferredWidth: 40
                            text: root.svc.playbackDuration > 0
                                ? root.svc.formatElapsed(root.svc.playbackDuration) : "--:--"
                            color: ClockStyle.colSubtext
                            font.pixelSize: ClockStyle.textSmall
                            font.family: ClockStyle.fontNumbers
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                        spacing: ClockStyle.gapSmall

                        ClockIconButton {
                            symbol: "replay_10"
                            tooltip: Translation.tr("Back 10 seconds")
                            Accessible.name: Translation.tr("Back 10 seconds")
                            enabled: root.svc.seekable
                            focusPolicy: Qt.StrongFocus
                            borderWidth: activeFocus ? 2 : 0
                            borderColor: ClockStyle.colFocus
                            onClicked: root.svc.skip(-10)
                        }

                        ClockButton {
                            Layout.preferredWidth: 48
                            iconOnly: true
                            symbol: root.svc.playbackError.length > 0 ? "refresh"
                                : root.svc.playing ? "pause" : "play_arrow"
                            label: root.playbackButtonLabel()
                            variant: "filled"
                            enabled: root.hasSelection && !root.svc.loading
                            focusPolicy: Qt.StrongFocus
                            borderWidth: activeFocus ? 2 : 0
                            borderColor: ClockStyle.colFocus
                            Accessible.name: root.playbackButtonLabel()
                            onClicked: root.svc.togglePlayback()
                        }

                        ClockIconButton {
                            symbol: "stop"
                            tooltip: Translation.tr("Stop playback")
                            Accessible.name: Translation.tr("Stop playback")
                            enabled: root.svc.playing || root.svc.playbackPaused
                            focusPolicy: Qt.StrongFocus
                            borderWidth: activeFocus ? 2 : 0
                            borderColor: ClockStyle.colFocus
                            onClicked: root.svc.stopPlayback()
                        }

                        ClockIconButton {
                            symbol: "forward_10"
                            tooltip: Translation.tr("Forward 10 seconds")
                            Accessible.name: Translation.tr("Forward 10 seconds")
                            enabled: root.svc.seekable
                            focusPolicy: Qt.StrongFocus
                            borderWidth: activeFocus ? 2 : 0
                            borderColor: ClockStyle.colFocus
                            onClicked: root.svc.skip(10)
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.svc.playbackError.length > 0
                        text: root.svc.playbackError
                        color: ClockStyle.colError
                        font.pixelSize: ClockStyle.textSmall
                        elide: Text.ElideRight
                    }
                }
            }


        }
    }
}
