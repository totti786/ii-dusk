import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.qanun
import qs.modules.ii.qanun.components

/**
 * Audio → sheet music. The page offers a local file or a yt-dlp link, shows the
 * isolated-melody / pitch-tracking / engraving stages, and renders the result
 * directly in the app. The final score can be saved as a composition or opened
 * in the composer.
 */
Item {
    id: root

    property bool compact: false
    property bool wide: false
    property int tempo: 100
    property string mode: "file"
    property bool saved: false

    signal editRequested(var score)

    readonly property var service: QanunConvertService
    readonly property var stageRows: [
        { id: "input", label: Translation.tr("Input"), symbol: "audio_file" },
        { id: "separate", label: Translation.tr("Stem / melody focus"), symbol: "call_split" },
        { id: "transcribe", label: Translation.tr("Audio → MIDI"), symbol: "graphic_eq" },
        { id: "engrave", label: Translation.tr("MIDI → notation"), symbol: "description" }
    ]

    function statusFor(stage): string {
        return String(root.service.stageStates[stage] ?? "pending");
    }

    function statusColor(status): color {
        if (status === "done") return QanunStyle.colInTune;
        if (status === "running") return QanunStyle.colPrimary;
        if (status === "error") return QanunStyle.colError;
        if (status === "skipped" || status === "cancelled") return QanunStyle.colSubtext;
        return QanunStyle.colSubtext;
    }

    function statusIcon(status): string {
        if (status === "done") return "check_circle";
        if (status === "running") return "progress_activity";
        if (status === "error") return "error";
        if (status === "skipped" || status === "cancelled") return "skip_next";
        return "circle";
    }

    function statusLabel(status): string {
        if (status === "done") return Translation.tr("Done");
        if (status === "running") return Translation.tr("Working");
        if (status === "error") return Translation.tr("Failed");
        if (status === "skipped") return Translation.tr("Skipped");
        if (status === "cancelled") return Translation.tr("Cancelled");
        return Translation.tr("Waiting");
    }

    function beginFile(): void {
        root.saved = false;
        root.service.startFile(fileField.text, titleField.text, root.tempo);
    }

    function beginLink(): void {
        root.saved = false;
        root.service.startUrl(linkField.text, titleField.text, root.tempo);
    }

    function saveResult(): void {
        if (root.service.saveToLibrary()) {
            root.saved = true;
        }
    }

    Component.onCompleted: {
        if (root.service.source.length > 0) {
            if (root.service.source.startsWith("http"))
                linkField.text = root.service.source;
            else
                fileField.text = root.service.source;
        }
        root.tempo = Math.round(Number(root.service.bpm) || 100);
    }

    FileDialog {
        id: audioDialog
        title: Translation.tr("Choose audio to convert")
        fileMode: FileDialog.OpenFile
        nameFilters: [
            Translation.tr("Audio files (%1)").arg("*.wav *.mp3 *.flac *.ogg *.m4a *.aac *.opus"),
            Translation.tr("All files (%1)").arg("*")
        ]
        onAccepted: {
            fileField.text = String(selectedFile);
            root.mode = "file";
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: ClockStyle.gap

        // ── Input and stages ────────────────────────────────────────────
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: root.compact ? 340 : Math.min(430, root.width * 0.36)
            Layout.minimumWidth: 320
            radius: ClockStyle.radiusCard
            color: ClockStyle.colPane
            clip: true

            StyledFlickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: inputColumn.implicitHeight + ClockStyle.gapLarge * 2
                clip: true

                ColumnLayout {
                    id: inputColumn
                    width: parent.width
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.margins: ClockStyle.gapLarge
                    spacing: ClockStyle.gapSmall

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall
                        ClockBadge {
                            size: 38
                            text: "audio_file"
                            shape: MaterialShape.Shape.Cookie7Sided
                            color: ClockStyle.colPrimaryContainer
                            colSymbol: ClockStyle.colOnPrimaryContainer
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: Translation.tr("Audio to sheet music")
                                font.family: Appearance.font.family.title
                                font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                                font.pixelSize: Appearance.font.pixelSize.large
                                color: QanunStyle.colOnSurface
                            }
                            StyledText {
                                text: Translation.tr("Melody transcription, engraved in the app")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: QanunStyle.colSubtext
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        ClockChip {
                            label: Translation.tr("File")
                            symbol: "folder_open"
                            selected: root.mode === "file"
                            height_: 30
                            onClicked: root.mode = "file"
                        }
                        ClockChip {
                            label: Translation.tr("Link")
                            symbol: "link"
                            selected: root.mode === "link"
                            height_: 30
                            onClicked: root.mode = "link"
                        }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            text: Translation.tr("BPM")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: QanunStyle.colSubtext
                        }
                        ClockStepper {
                            Layout.preferredWidth: 132
                            value: root.tempo
                            from: 40
                            to: 240
                            stepSize: 2
                            format: value => String(value)
                            onMoved: value => root.tempo = value
                        }
                    }

                    MaterialTextField {
                        id: fileField
                        Layout.fillWidth: true
                        visible: root.mode === "file"
                        placeholderText: Translation.tr("Audio file path")
                        text: root.service.source.startsWith("http") ? "" : root.service.source
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.mode === "file"
                        spacing: ClockStyle.gapSmall
                        ClockButton {
                            Layout.fillWidth: true
                            symbol: "folder_open"
                            label: Translation.tr("Browse")
                            variant: "tonal"
                            enabled: !root.service.running
                            onClicked: audioDialog.open()
                        }
                        ClockButton {
                            Layout.fillWidth: true
                            symbol: "play_arrow"
                            label: Translation.tr("Convert")
                            variant: "filled"
                            enabled: !root.service.running && fileField.text.length > 0
                            onClicked: root.beginFile()
                        }
                    }

                    MaterialTextField {
                        id: linkField
                        Layout.fillWidth: true
                        visible: root.mode === "link"
                        placeholderText: Translation.tr("Paste an audio or video link")
                        text: root.service.source.startsWith("http") ? root.service.source : ""
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    ClockButton {
                        Layout.fillWidth: true
                        visible: root.mode === "link"
                        symbol: "cloud_download"
                        label: Translation.tr("Download & convert")
                        variant: "filled"
                        enabled: !root.service.running && linkField.text.length > 0
                        onClicked: root.beginLink()
                    }

                    MaterialTextField {
                        id: titleField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Score title (optional)")
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Qt.alpha(QanunStyle.colOnSurface, 0.08)
                    }

                    Repeater {
                        model: root.stageRows
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapSmall

                            MaterialSymbol {
                                text: modelData.symbol
                                iconSize: Appearance.font.pixelSize.normal
                                color: QanunStyle.colSubtext
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: QanunStyle.colOnSurface
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.statusLabel(root.statusFor(modelData.id))
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: root.statusColor(root.statusFor(modelData.id))
                                }
                            }
                            MaterialSymbol {
                                text: root.statusIcon(root.statusFor(modelData.id))
                                iconSize: Appearance.font.pixelSize.large
                                fill: 1
                                color: root.statusColor(root.statusFor(modelData.id))
                                NumberAnimation on rotation {
                                    running: root.statusFor(modelData.id) === "running"
                                    from: 0
                                    to: 360
                                    duration: 1000
                                    loops: Animation.Infinite
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.service.error.length > 0
                            ? root.service.error
                            : root.service.message.length > 0
                                ? root.service.message
                                : Translation.tr("Demucs is optional. Without it the converter uses a band-limited melody focus before pitch tracking.")
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: root.service.error.length > 0 ? QanunStyle.colError : QanunStyle.colSubtext
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall
                        ClockButton {
                            visible: root.service.running
                            Layout.fillWidth: true
                            symbol: "stop_circle"
                            label: Translation.tr("Cancel")
                            variant: "tonal"
                            onClicked: root.service.cancel()
                        }
                        ClockButton {
                            visible: !root.service.running && root.service.result !== null
                            Layout.fillWidth: true
                            symbol: "add"
                            label: Translation.tr("Convert another")
                            variant: "text"
                            onClicked: root.service.reset()
                        }
                    }
                }
            }
        }

        // ── Result ──────────────────────────────────────────────────────
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
                        text: root.service.result ? "music_note" : "auto_fix_high"
                        shape: MaterialShape.Shape.Sunny
                        color: ClockStyle.colTertiary
                        colSymbol: ClockStyle.colOnTertiary
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: root.service.result
                                ? String(root.service.result.title ?? Translation.tr("Converted score"))
                                : Translation.tr("Result")
                            font.family: Appearance.font.family.title
                            font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: QanunStyle.colOnSurface
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.service.result
                                ? Translation.tr("%1 notes · %2 BPM · melody transcription")
                                    .arg(String(root.service.result.notes?.length ?? 0))
                                    .arg(String(root.service.result.tempo ?? root.tempo))
                                : Translation.tr("A preview appears here when the engraving stage finishes.")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: QanunStyle.colSubtext
                        }
                    }
                    ClockButton {
                        visible: root.service.result !== null
                        symbol: root.saved ? "bookmark" : "bookmark_add"
                        label: root.saved ? Translation.tr("Saved") : Translation.tr("Save to sheets")
                        variant: root.saved ? "tonal" : "filled"
                        onClicked: root.saveResult()
                    }
                    ClockButton {
                        visible: root.service.result !== null
                        symbol: "edit_note"
                        label: Translation.tr("Composer")
                        variant: "text"
                        onClicked: root.editRequested(root.service.result.score)
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 250
                    radius: Appearance.rounding.normal
                    color: QanunStyle.colField
                    clip: true

                    MusicStaff {
                        anchors.fill: parent
                        anchors.margins: 16
                        visible: root.service.result !== null
                        notes: root.service.result?.notes ?? []
                        clef: root.service.result?.clef ?? "treble"
                        keySignature: Number(root.service.result?.score?.key ?? 0)
                        timeSignature: root.service.result?.score?.time ?? [4, 4]
                        showTimeSignature: true
                        accentIndex: -1
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: root.service.result === null
                        spacing: ClockStyle.gapSmall
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.service.running ? "graphic_eq" : "audio_file"
                            iconSize: 54
                            fill: 1
                            color: QanunStyle.colSubtext
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.service.running
                                ? Translation.tr("Listening for a melody…")
                                : Translation.tr("No conversion yet")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: QanunStyle.colOnSurface
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: 340
                            text: root.service.running
                                ? Translation.tr("The result will be engraved automatically when the notes are ready.")
                                : Translation.tr("Choose a file or paste a link on the left. A clear, monophonic melody works best.")
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: QanunStyle.colSubtext
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall
                    StyledText {
                        Layout.fillWidth: true
                        text: root.service.result
                            ? Translation.tr("%1 · %2").arg(root.service.result.stem ?? "").arg(root.service.result.musicxml ?? "")
                            : ""
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: QanunStyle.colSubtext
                        elide: Text.ElideMiddle
                    }
                    ClockButton {
                        visible: root.service.result !== null
                        symbol: "piano"
                        label: Translation.tr("MIDI")
                        variant: "text"
                        onClicked: root.service.openMIDI()
                    }
                    ClockButton {
                        visible: root.service.result !== null
                        symbol: "description"
                        label: Translation.tr("MusicXML")
                        variant: "tonal"
                        onClicked: root.service.openMusicXML()
                    }
                    ClockButton {
                        visible: root.service.result !== null
                        symbol: "folder_open"
                        label: Translation.tr("Folder")
                        variant: "text"
                        onClicked: root.service.openFolder()
                    }
                }
            }
        }
    }
}
