import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.qanun
import qs.modules.ii.qanun.components

/**
 * Tracks: the shell's recorder wrapped in a listening-first page. Finished takes
 * show their waveform, date and name in the list before you open one; the
 * selected take gets a full waveform scrubber and a persistent player.
 */
Item {
    id: root

    property bool compact: false
    property bool wide: false

    readonly property var svc: AudioRecorderService
    readonly property bool active: root.svc.recording
    readonly property bool hasSelection: root.svc.selectedEntry !== null
    readonly property var recordings: Array.from(root.svc.recordings ?? [])
    readonly property string pageSubtitle: root.active
        ? (root.svc.paused ? Translation.tr("Recording paused") : Translation.tr("Recording…"))
        : Translation.tr("%1 takes in %2").arg(String(root.recordings.length)).arg("~/Music/Recordings")

    function requestWaveforms(): void {
        for (const entry of root.recordings)
            QanunStore.requestWaveform(String(entry.path));
    }

    function durationText(entry): string {
        const fromWave = Number(QanunStore.waveformDurations[String(entry.path)] ?? 0);
        const value = String(entry.path) === root.svc.selectedPath && root.svc.playbackDuration > 0
            ? root.svc.playbackDuration : fromWave;
        return value > 0 ? root.svc.formatElapsed(value) : "";
    }

    function metaText(entry): string {
        return [root.durationText(entry), root.svc.formatSize(entry.size), root.svc.formatWhen(entry.mtime)]
            .filter(part => String(part).length > 0).join("  ·  ");
    }

    function seekFraction(fraction): void {
        if (!root.hasSelection || root.svc.playbackDuration <= 0)
            return;
        root.svc.seek(Math.max(0, Math.min(1, fraction)) * root.svc.playbackDuration);
    }

    function recordLabel(): string {
        if (root.svc.starting)
            return Translation.tr("Starting…");
        return root.active ? Translation.tr("Stop") : Translation.tr("Record");
    }

    Component.onCompleted: {
        root.svc.refresh();
        Qt.callLater(root.requestWaveforms);
    }

    Connections {
        target: root.svc
        function onRecordingsChanged() {
            Qt.callLater(root.requestWaveforms);
        }
        function onSelectedEntryChanged() {
            if (root.svc.selectedEntry)
                QanunStore.requestWaveform(String(root.svc.selectedEntry.path));
        }
    }

    Connections {
        target: QanunStore
        function onAudioStopRequested() {
            root.svc.stopPlayback();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.gap
        spacing: ClockStyle.gap

        // ── Recorder ────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
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

                Rectangle {
                    width: 54
                    height: 54
                    radius: Appearance.rounding.full
                    color: root.active
                        ? (root.svc.paused ? ClockStyle.colTertiaryContainer : ClockStyle.colErrorContainer)
                        : ClockStyle.colPrimaryContainer
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.active ? (root.svc.paused ? "pause" : "graphic_eq") : "mic"
                        iconSize: 26
                        fill: 1
                        color: root.active
                            ? (root.svc.paused ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnErrorContainer)
                            : ClockStyle.colOnPrimaryContainer
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: root.active
                            ? (root.svc.paused ? Translation.tr("Take paused") : Translation.tr("Recording a take"))
                            : Translation.tr("Record a track")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: QanunStyle.colOnSurface
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.active
                            ? root.svc.currentFile
                            : (root.svc.error.length > 0 ? root.svc.error
                                : Translation.tr("48 kHz stereo WAV · saved in ~/Music/Recordings"))
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: root.svc.error.length > 0 ? QanunStyle.colError : QanunStyle.colSubtext
                        elide: Text.ElideMiddle
                    }
                }

                StyledText {
                    text: root.svc.formatElapsed(root.svc.elapsed)
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: root.active && !root.svc.paused ? QanunStyle.colError : QanunStyle.colOnSurface
                }

                ClockButton {
                    symbol: root.active ? "stop" : "fiber_manual_record"
                    label: root.recordLabel()
                    variant: "filled"
                    danger: root.active
                    enabled: !root.svc.starting && !root.svc.stopping
                    onClicked: root.svc.toggle()
                }

                ClockButton {
                    symbol: root.svc.paused ? "play_arrow" : "pause"
                    label: root.svc.paused ? Translation.tr("Resume") : Translation.tr("Pause")
                    iconOnly: root.compact
                    variant: "tonal"
                    enabled: root.active
                    onClicked: root.svc.togglePause()
                }
            }
        }

        // ── Take list ───────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: ClockStyle.radiusCard
            color: ClockStyle.colPane
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: ClockStyle.gapLarge
                spacing: ClockStyle.gapSmall

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                    ClockBadge {
                        size: 36
                        text: "library_music"
                        shape: MaterialShape.Shape.Cookie9Sided
                        color: ClockStyle.colPrimaryContainer
                        colSymbol: ClockStyle.colOnPrimaryContainer
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Tracks")
                        font.family: Appearance.font.family.title
                        font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: QanunStyle.colOnSurface
                    }
                    StyledText {
                        text: String(root.recordings.length)
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.numbers
                        color: QanunStyle.colSubtext
                    }
                    ClockIconButton {
                        symbol: "refresh"
                        tooltip: Translation.tr("Refresh takes")
                        size: 34
                        onClicked: root.svc.refresh()
                    }
                    ClockIconButton {
                        symbol: "folder_open"
                        tooltip: Translation.tr("Open recordings folder")
                        size: 34
                        onClicked: root.svc.openFolder()
                    }
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.recordings.length > 0
                    clip: true
                    spacing: 2
                    model: root.recordings
                    boundsBehavior: Flickable.StopAtBounds
                    remove: Transition {
                        NumberAnimation { property: "opacity"; to: 0; duration: 170 }
                    }
                    displaced: Transition {
                        NumberAnimation {
                            property: "y"
                            duration: 220
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                    }
                    ScrollBar.vertical: StyledScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: RippleButton {
                        id: row
                        required property var modelData
                        readonly property bool selected: String(root.svc.selectedPath) === String(row.modelData.path)
                        property bool confirmDelete: false
                        property bool removing: false

                        width: list.width
                        implicitHeight: row.removing ? 0 : 78
                        opacity: row.removing ? 0 : 1
                        clip: true
                        buttonRadius: ClockStyle.radiusNormal
                        interactionScale: 1
                        scaleBehaviorEnabled: false
                        toggled: row.selected
                        colBackground: "transparent"
                        colBackgroundHover: Qt.alpha(QanunStyle.colOnSurface, 0.04)
                        colBackgroundActive: Qt.alpha(QanunStyle.colOnSurface, 0.08)
                        colBackgroundToggled: Qt.alpha(QanunStyle.colPrimary, 0.10)
                        colBackgroundToggledHover: Qt.alpha(QanunStyle.colPrimary, 0.14)
                        colRipple: Qt.alpha(QanunStyle.colPrimary, 0.12)
                        onClicked: {
                            if (row.selected && root.svc.playing)
                                root.svc.pausePlayback();
                            else
                                root.svc.play(row.modelData);
                        }

                        Timer {
                            interval: 2600
                            running: row.confirmDelete
                            onTriggered: row.confirmDelete = false
                        }

                        Timer {
                            id: deleteCommit
                            interval: 220
                            repeat: false
                            onTriggered: root.svc.remove(row.modelData.path)
                        }

                        Behavior on implicitHeight {
                            NumberAnimation {
                                duration: 220
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                            }
                        }
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 10

                            Rectangle {
                                width: 38
                                height: 38
                                radius: Appearance.rounding.full
                                color: row.selected ? Qt.alpha(QanunStyle.colPrimary, 0.16) : QanunStyle.colField
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: row.selected && root.svc.playing ? "pause" : "play_arrow"
                                    iconSize: 22
                                    fill: 1
                                    color: row.selected ? QanunStyle.colPrimary : QanunStyle.colOnSurfaceVariant
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (row.selected && root.svc.playing)
                                            root.svc.pausePlayback();
                                        else
                                            root.svc.play(row.modelData);
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 100
                                spacing: 1
                                StyledText {
                                    Layout.fillWidth: true
                                    text: row.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Medium
                                    color: QanunStyle.colOnSurface
                                    elide: Text.ElideMiddle
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.metaText(row.modelData)
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: QanunStyle.colSubtext
                                    elide: Text.ElideRight
                                }
                            }

                            WaveformView {
                                Layout.preferredWidth: root.compact ? 76 : Math.max(120, Math.min(220, row.width * 0.22))
                                Layout.preferredHeight: 34
                                peaks: QanunStore.waveforms[String(row.modelData.path)] ?? []
                                progress: row.selected && root.svc.playbackDuration > 0
                                    ? root.svc.playbackPosition / root.svc.playbackDuration : 0
                                interactive: false
                                waveColor: row.selected ? QanunStyle.colPrimary : Qt.alpha(QanunStyle.colOnSurface, 0.28)
                                playedColor: row.selected ? QanunStyle.colPrimary : Qt.alpha(QanunStyle.colOnSurface, 0.28)
                                idleColor: row.selected ? Qt.alpha(QanunStyle.colPrimary, 0.65) : Qt.alpha(QanunStyle.colOnSurface, 0.22)
                            }

                            ClockIconButton {
                                symbol: row.confirmDelete ? "delete_forever" : "delete"
                                tooltip: row.confirmDelete ? Translation.tr("Click again to delete") : Translation.tr("Delete take")
                                size: 32
                                colIcon: row.confirmDelete ? QanunStyle.colError : QanunStyle.colOnSurfaceVariant
                                onClicked: {
                                    if (row.confirmDelete) {
                                        row.removing = true;
                                        row.confirmDelete = false;
                                        deleteCommit.restart();
                                    } else {
                                        row.confirmDelete = true;
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.recordings.length === 0

                    ClockEmptyState {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - ClockStyle.gap * 2, 420)
                        shapeSize: ClockStyle.emptyShapeSmall
                        symbol: "mic_none"
                        title: root.svc.listLoading ? Translation.tr("Loading takes") : Translation.tr("No tracks yet")
                        subtitle: Translation.tr("Press Record above and the take will appear here with its waveform.")
                    }
                }
            }
        }

        // ── Player ──────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.hasSelection ? 142 : 0
            visible: opacity > 0
            opacity: root.hasSelection ? 1 : 0
            radius: ClockStyle.radiusCard
            color: ClockStyle.colPane
            clip: true

            Behavior on Layout.preferredHeight {
                NumberAnimation {
                    duration: 260
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
            }
            Behavior on opacity {
                NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: ClockStyle.gapLarge
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                    ClockIconButton {
                        symbol: root.svc.playing ? "pause" : "play_arrow"
                        tooltip: root.svc.playing ? Translation.tr("Pause") : Translation.tr("Play")
                        toggled: root.svc.playing
                        size: 42
                        onClicked: root.svc.togglePlayback()
                    }
                    ClockIconButton {
                        symbol: "replay_10"
                        tooltip: Translation.tr("Back 10 seconds")
                        size: 34
                        onClicked: root.svc.skip(-10)
                    }
                    ClockIconButton {
                        symbol: "forward_10"
                        tooltip: Translation.tr("Forward 10 seconds")
                        size: 34
                        onClicked: root.svc.skip(10)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: root.svc.selectedName
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: QanunStyle.colOnSurface
                            elide: Text.ElideMiddle
                        }
                        StyledText {
                            text: root.svc.formatElapsed(root.svc.playbackPosition) + " / "
                                + root.svc.formatElapsed(root.svc.playbackDuration)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.numbers
                            color: QanunStyle.colSubtext
                        }
                    }

                    MaterialSymbol {
                        text: "volume_up"
                        iconSize: Appearance.font.pixelSize.normal
                        color: QanunStyle.colSubtext
                    }
                    StyledSlider {
                        Layout.preferredWidth: 110
                        from: 0
                        to: 1
                        value: root.svc.volume
                        configuration: StyledSlider.Configuration.XS
                        onMoved: root.svc.volume = value
                    }
                    ClockIconButton {
                        symbol: "folder_open"
                        tooltip: Translation.tr("Show in folder")
                        size: 34
                        onClicked: root.svc.showInFolder(root.svc.selectedPath)
                    }
                }

                WaveformView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    peaks: QanunStore.waveforms[root.svc.selectedPath] ?? []
                    progress: root.svc.playbackDuration > 0
                        ? root.svc.playbackPosition / root.svc.playbackDuration : 0
                    interactive: root.svc.seekable
                    onSeekRequested: fraction => root.seekFraction(fraction)
                }
            }
        }
    }
}
