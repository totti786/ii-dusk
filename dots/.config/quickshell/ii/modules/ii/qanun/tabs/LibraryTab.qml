import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.qanun
import qs.modules.ii.qanun.components

/**
 * Sheet music: a searchable local library, the CC0 OpenScore String Quartets
 * provider, a saved shelf, and a small notation editor with real note values,
 * accidentals, dots, ties, bent bar lines and a click-to-place staff.
 */
Item {
    id: root

    property bool compact: false
    property bool wide: false

    property string mode: "discover"
    property string query: ""
    property var selectedItem: null

    property var composer: null
    property var composerNotes: []
    property string composerTitle: "Untitled score"
    property string composerClef: "treble"
    property int composerKey: 0
    property var composerTime: [4, 4]
    property int composerTempo: 90
    property real composerDuration: 1
    property bool composerDotted: false
    property bool composerTie: false
    property int composerAccidental: 0
    property bool composerRestMode: false

    readonly property var builtIns: QanunData.builtInScores.map(score => Object.assign({}, score, {
        kind: "builtin", source: "Built-in · public domain"
    }))
    readonly property var providerItems: QanunStore.onlineCatalog.map(entry => Object.assign({}, entry, {
        kind: "provider"
    }))
    readonly property var savedBuiltIns: root.builtIns.filter(score => QanunStore.isBuiltInSaved(score.id))
    readonly property var savedProvider: QanunStore.savedScores.map(entry => Object.assign({}, entry, { kind: "provider" }))
    readonly property var compositionItems: QanunStore.compositions.map(item => Object.assign({}, item, {
        kind: "composition", source: "My composition", category: "Composition", composer: "You"
    }))

    readonly property var baseItems: {
        if (root.mode === "saved")
            return root.savedBuiltIns.concat(root.savedProvider, root.compositionItems);
        return root.builtIns.concat(root.providerItems);
    }
    readonly property var visibleItems: {
        const needle = root.query.trim().toLowerCase();
        if (needle.length === 0)
            return root.baseItems;
        return root.baseItems.filter(item => QanunData.scoreSearchText(item).includes(needle));
    }
    readonly property var detailItem: {
        const chosen = root.selectedItem ?? root.visibleItems[0] ?? null;
        if (!chosen)
            return null;
        if (chosen.kind === "provider") {
            const saved = QanunStore.savedScores.find(entry => String(entry.id) === String(chosen.id));
            return saved ? Object.assign({}, chosen, saved, { kind: "provider" }) : chosen;
        }
        return chosen;
    }
    readonly property var detailNotes: QanunData.scoreNotes(root.detailItem)
    readonly property bool detailSaved: {
        if (!root.detailItem)
            return false;
        if (root.detailItem.kind === "builtin")
            return QanunStore.isBuiltInSaved(root.detailItem.id);
        if (root.detailItem.kind === "provider")
            return QanunStore.isProviderSaved(root.detailItem.id);
        return true;
    }
    readonly property bool detailWide: !root.compact && root.width >= 780
    readonly property string pageSubtitle: root.mode === "compose"
        ? Translation.tr("Composer · click the staff to place notes")
        : root.mode === "convert"
            ? Translation.tr("Convert audio into engraved notation")
            : Translation.tr("%1 works · %2 saved").arg(String(root.visibleItems.length))
                .arg(String(root.savedBuiltIns.length + root.savedProvider.length + root.compositionItems.length))

    function setMode(next: string): void {
        root.mode = next;
        root.selectedItem = null;
        if (next === "compose")
            root.ensureComposer();
    }

    function openConvertedInComposer(score): void {
        if (!score)
            return;
        root.composer = null;
        root.ensureComposer();
        root.composerTitle = String(score.title ?? "Converted audio");
        root.composerClef = String(score.clef ?? "treble");
        root.composerKey = Number(score.key ?? 0);
        root.composerTime = Array.from(score.time ?? [4, 4]);
        root.composerTempo = Number(score.tempo ?? 100);
        root.composerNotes = Array.from(score.notes ?? []);
        root.mode = "compose";
    }

    function ensureComposer(): void {
        if (root.composer !== null)
            return;
        root.composer = {
            id: "comp-" + Date.now().toString(36),
            title: "Untitled score",
            created: Date.now(),
            modified: Date.now()
        };
        root.composerNotes = [];
        root.composerTitle = "Untitled score";
        root.composerClef = "treble";
        root.composerKey = 0;
        root.composerTime = [4, 4];
        root.composerTempo = 90;
    }

    function newComposition(): void {
        root.composer = null;
        root.ensureComposer();
        root.mode = "compose";
        root.selectedItem = null;
    }

    function loadComposition(item): void {
        if (!item)
            return;
        root.composer = item;
        root.composerNotes = Array.from(item.notes ?? []);
        root.composerTitle = String(item.title ?? "Untitled score");
        root.composerClef = String(item.clef ?? "treble");
        root.composerKey = Number(item.key ?? 0);
        root.composerTime = Array.from(item.time ?? [4, 4]);
        root.composerTempo = Number(item.tempo ?? 90);
        root.mode = "compose";
        root.selectedItem = null;
    }

    function addPitchedNote(letter: string, octave: int): void {
        const beats = Math.max(0.05, root.composerDuration * (root.composerDotted ? 1.5 : 1));
        const next = Array.from(root.composerNotes);
        next.push({
            letter: String(letter).toUpperCase(), octave: octave, alter: root.composerAccidental,
            duration: beats, dotted: root.composerDotted, tie: root.composerTie,
            rest: false, midi: QanunData.midiForNote({
                letter: letter, octave: octave, alter: root.composerAccidental
            })
        });
        root.composerNotes = next;
        root.composerDotted = false;
        root.composerTie = false;
    }

    function addRest(): void {
        const beats = Math.max(0.05, root.composerDuration * (root.composerDotted ? 1.5 : 1));
        const next = Array.from(root.composerNotes);
        next.push({ rest: true, letter: "B", octave: 4, alter: 0, duration: beats, dotted: root.composerDotted, tie: false, midi: -1 });
        root.composerNotes = next;
        root.composerDotted = false;
        root.composerTie = false;
    }

    function undoComposer(): void {
        if (root.composerNotes.length === 0)
            return;
        root.composerNotes = root.composerNotes.slice(0, -1);
    }

    function clearComposer(): void {
        root.composerNotes = [];
    }

    function saveComposer(): void {
        root.ensureComposer();
        const composition = Object.assign({}, root.composer, {
            id: root.composer.id,
            title: root.composerTitle.trim() || "Untitled score",
            clef: root.composerClef,
            key: root.composerKey,
            time: Array.from(root.composerTime),
            tempo: root.composerTempo,
            notes: JSON.parse(JSON.stringify(root.composerNotes)),
            modified: Date.now()
        });
        QanunStore.saveComposition(composition);
        root.composer = composition;
        root.composerTitle = composition.title;
    }

    function playComposer(): void {
        if (root.composerNotes.length === 0)
            return;
        QanunStore.playMidiSequence(root.composerNotes, root.composerTempo, "Composer · " + root.composerTitle);
    }

    function playDetail(): void {
        if (root.detailNotes.length === 0)
            return;
        QanunStore.playMidiSequence(root.detailNotes, Number(root.detailItem?.tempo ?? 90),
            root.detailItem?.title ?? "");
    }

    function saveDetail(): void {
        if (!root.detailItem)
            return;
        if (root.detailItem.kind === "builtin") {
            QanunStore.toggleBuiltInSave(root.detailItem.id);
        } else if (root.detailItem.kind === "provider") {
            if (root.detailSaved)
                QanunStore.removeSavedScore(root.detailItem.id);
            else
                QanunStore.downloadScore(root.detailItem);
        }
    }

    function copyToComposer(): void {
        if (!root.detailItem)
            return;
        if (root.detailItem.kind === "composition") {
            root.loadComposition(root.detailItem);
            return;
        }
        root.composer = null;
        root.ensureComposer();
        root.composerTitle = (root.detailItem.title ?? "Untitled") + " — study";
        root.composerClef = String(root.detailItem.clef ?? "treble");
        root.composerKey = Number(root.detailItem.key ?? 0);
        root.composerTime = Array.from(root.detailItem.time ?? [4, 4]);
        root.composerTempo = Number(root.detailItem.tempo ?? 90);
        root.composerNotes = Array.from(root.detailNotes);
        root.mode = "compose";
    }

    function deleteDetail(): void {
        if (!root.detailItem)
            return;
        if (root.detailItem.kind === "composition")
            QanunStore.deleteComposition(root.detailItem.id);
        else if (root.detailItem.kind === "provider" && root.detailSaved)
            QanunStore.removeSavedScore(root.detailItem.id);
        root.selectedItem = null;
    }

    Component.onCompleted: {
        if (QanunStore.onlineCatalog.length === 0)
            QanunStore.fetchCatalog();
    }

    Connections {
        target: QanunStore
        function onDownloadFinished(result) {
            if (result && result.id) {
                root.selectedItem = Object.assign({}, result, { kind: "provider" });
                root.mode = "discover";
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.gap
        spacing: ClockStyle.gap

        // ── Search / mode strip ────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 70
            radius: ClockStyle.radiusCard
            color: ClockStyle.colPane

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: ClockStyle.gapLarge
                anchors.rightMargin: ClockStyle.gapLarge
                spacing: ClockStyle.gapSmall

                MaterialSymbol {
                    visible: root.mode !== "convert"
                    text: "library_music"
                    iconSize: ClockStyle.iconNormal
                    color: QanunStyle.colOnSurfaceVariant
                }

                MaterialTextField {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.maximumWidth: 520
                    visible: root.mode !== "convert"
                    placeholderText: Translation.tr("Search sheet music — composer, title, region…")
                    text: root.query
                    onTextChanged: root.query = text
                }

                Item { Layout.fillWidth: true }

                Repeater {
                    model: [
                        { id: "discover", label: Translation.tr("Discover"), symbol: "explore" },
                        { id: "saved", label: Translation.tr("Saved"), symbol: "bookmark" },
                        { id: "convert", label: Translation.tr("Convert"), symbol: "auto_fix_high" },
                        { id: "compose", label: Translation.tr("Compose"), symbol: "edit_note" }
                    ]
                    ClockChip {
                        required property var modelData
                        label: modelData.label
                        symbol: modelData.symbol
                        selected: root.mode === modelData.id
                        onClicked: root.setMode(modelData.id)
                    }
                }

                ClockIconButton {
                    visible: root.mode !== "convert"
                    symbol: "cloud_download"
                    tooltip: Translation.tr("Refresh the OpenScore catalogue")
                    size: 34
                    enabled: !QanunStore.catalogLoading
                    onClicked: QanunStore.fetchCatalog(true)
                }
            }
        }

        // ── Library / saved ────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: ClockStyle.gap
            visible: root.mode === "discover" || root.mode === "saved"

            Rectangle {
                visible: !root.compact || root.selectedItem === null
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 360
                Layout.minimumWidth: 250
                Layout.maximumWidth: root.compact ? 100000 : 410
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
                            text: root.mode === "saved" ? "bookmark" : "library_music"
                            shape: MaterialShape.Shape.Cookie9Sided
                            color: ClockStyle.colPrimaryContainer
                            colSymbol: ClockStyle.colOnPrimaryContainer
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.mode === "saved" ? Translation.tr("Saved sheet music") : Translation.tr("Sheet music")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: QanunStyle.colOnSurface
                        }
                        StyledText {
                            text: String(root.visibleItems.length)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.numbers
                            color: QanunStyle.colSubtext
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Qt.alpha(QanunStyle.colOnSurface, 0.06)
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        visible: root.mode === "discover"
                        implicitHeight: providerRow.implicitHeight + 16
                        radius: Appearance.rounding.small
                        color: QanunStyle.colField

                        RowLayout {
                            id: providerRow
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8
                            MaterialSymbol {
                                text: QanunStore.catalogLoading ? "progress_activity" : "public"
                                iconSize: 18
                                color: QanunStyle.colTertiary
                                NumberAnimation on rotation {
                                    running: QanunStore.catalogLoading
                                    from: 0; to: 360; duration: 1200; loops: Animation.Infinite
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("OpenScore String Quartets")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    color: QanunStyle.colOnSurface
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: QanunStore.catalogError.length > 0
                                        ? QanunStore.catalogError
                                        : Translation.tr("CC0 · %1 public-domain scores").arg(String(QanunStore.onlineCatalog.length))
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: QanunStore.catalogError.length > 0 ? QanunStyle.colError : QanunStyle.colSubtext
                                    elide: Text.ElideRight
                                }
                            }
                            ClockButton {
                                symbol: "sync"
                                label: Translation.tr("Load")
                                variant: "text"
                                enabled: !QanunStore.catalogLoading
                                onClicked: QanunStore.fetchCatalog(true)
                            }
                        }
                    }

                    ListView {
                        id: libraryList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.visibleItems.length > 0
                        clip: true
                        spacing: 2
                        model: root.visibleItems
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: StyledScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: RippleButton {
                            id: row
                            required property var modelData
                            readonly property bool selected: root.detailItem
                                && String(root.detailItem.id) === String(row.modelData.id)
                                && root.detailItem.kind === row.modelData.kind
                            width: libraryList.width
                            implicitHeight: 66
                            buttonRadius: ClockStyle.radiusNormal
                            interactionScale: 1
                            scaleBehaviorEnabled: false
                            toggled: row.selected
                            colBackground: "transparent"
                            colBackgroundHover: Qt.alpha(QanunStyle.colOnSurface, 0.04)
                            colBackgroundActive: Qt.alpha(QanunStyle.colOnSurface, 0.08)
                            colBackgroundToggled: Qt.alpha(QanunStyle.colPrimary, 0.12)
                            colBackgroundToggledHover: Qt.alpha(QanunStyle.colPrimary, 0.16)
                            colRipple: Qt.alpha(QanunStyle.colPrimary, 0.12)
                            onClicked: root.selectedItem = row.modelData

                            contentItem: RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 10

                                Rectangle {
                                    width: 36
                                    height: 36
                                    radius: Appearance.rounding.verysmall
                                    color: row.toggled ? Qt.alpha(QanunStyle.colPrimary, 0.18) : QanunStyle.colField
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: row.modelData.kind === "composition" ? "edit_note"
                                            : row.modelData.kind === "provider" ? "public" : "music_note"
                                        iconSize: 19
                                        fill: row.toggled ? 1 : 0
                                        color: row.toggled ? QanunStyle.colPrimary : QanunStyle.colOnSurfaceVariant
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 1
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: row.modelData.title ?? "Untitled"
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: row.toggled ? QanunStyle.colPrimary : QanunStyle.colOnSurface
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: [row.modelData.composer, row.modelData.category,
                                            row.modelData.difficulty].filter(part => String(part ?? "").length > 0).join("  ·  ")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: QanunStyle.colSubtext
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    ClockEmptyState {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillHeight: true
                        visible: root.visibleItems.length === 0
                        shapeSize: 96
                        symbol: root.mode === "saved" ? "bookmark_border" : "search_off"
                        title: root.mode === "saved" ? Translation.tr("Nothing saved yet") : Translation.tr("No scores found")
                        subtitle: root.mode === "saved"
                            ? Translation.tr("Save a built-in score or download one from OpenScore.")
                            : Translation.tr("Try a composer, a title, or load the OpenScore catalogue.")
                    }
                }
            }

            Rectangle {
                visible: root.detailWide || root.selectedItem !== null
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: ClockStyle.radiusCard
                color: ClockStyle.colPane
                clip: true

                StyledFlickable {
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: detailColumn.implicitHeight + ClockStyle.gapLarge * 2
                    clip: true

                    ColumnLayout {
                        id: detailColumn
                        width: parent.width
                        anchors.margins: ClockStyle.gapLarge
                        spacing: ClockStyle.gap

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapSmall

                            ClockIconButton {
                                visible: root.compact && root.selectedItem !== null
                                symbol: "arrow_back"
                                tooltip: Translation.tr("Back to the library")
                                onClicked: root.selectedItem = null
                            }

                            ClockBadge {
                                size: 44
                                text: root.detailItem?.kind === "provider" ? "public"
                                    : root.detailItem?.kind === "composition" ? "edit_note" : "music_note"
                                shape: MaterialShape.Shape.Cookie9Sided
                                color: ClockStyle.colPrimaryContainer
                                colSymbol: ClockStyle.colOnPrimaryContainer
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 1
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.detailItem?.title ?? Translation.tr("Choose a score")
                                    font.family: Appearance.font.family.title
                                    font.variableAxes: ({ "wght": 700, "wdth": 100, "ROND": 100 })
                                    font.pixelSize: Appearance.font.pixelSize.huge
                                    color: QanunStyle.colOnSurface
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.detailItem
                                        ? [root.detailItem.composer, root.detailItem.category,
                                            root.detailItem.license, root.detailItem.source]
                                            .filter(part => String(part ?? "").length > 0).join("  ·  ")
                                        : ""
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: QanunStyle.colSubtext
                                    elide: Text.ElideRight
                                }
                            }

                            ClockIconButton {
                                visible: root.detailItem?.kind === "provider"
                                symbol: "open_in_new"
                                tooltip: Translation.tr("Open on OpenScore / MuseScore")
                                onClicked: QanunStore.openExternal(root.detailItem?.link ?? "")
                            }

                            ClockIconButton {
                                visible: root.detailItem?.kind === "provider" && String(root.detailItem?.file ?? "").length > 0
                                symbol: "folder_open"
                                tooltip: Translation.tr("Show downloaded score")
                                onClicked: root.detailItem?.file ? Quickshell.execDetached(["xdg-open", String(root.detailItem.file)]) : null
                            }

                            ClockIconButton {
                                visible: root.detailItem?.kind === "composition"
                                symbol: "delete"
                                tooltip: Translation.tr("Delete composition")
                                onClicked: root.deleteDetail()
                            }

                            ClockButton {
                                symbol: root.detailSaved ? "bookmark" : "bookmark_add"
                                label: root.detailItem?.kind === "provider" && !root.detailSaved
                                    ? Translation.tr("Download") : (root.detailSaved ? Translation.tr("Saved") : Translation.tr("Save"))
                                variant: root.detailSaved ? "tonal" : "filled"
                                enabled: root.detailItem !== null && QanunStore.downloadingId.length === 0
                                onClicked: root.saveDetail()
                            }

                            ClockButton {
                                symbol: "play_arrow"
                                label: Translation.tr("Play")
                                variant: "text"
                                enabled: root.detailNotes.length > 0
                                onClicked: root.playDetail()
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: Qt.alpha(QanunStyle.colOnSurface, 0.08)
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ClockStyle.gap

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: ClockStyle.gapSmall

                                MusicStaff {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.detailNotes.length > 0 ? Math.max(190, implicitHeight) : 190
                                    notes: root.detailNotes
                                    clef: root.detailItem?.clef ?? "treble"
                                    keySignature: Number(root.detailItem?.key ?? 0)
                                    timeSignature: root.detailItem?.time ?? [4, 4]
                                    showTimeSignature: true
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: root.detailNotes.length === 0
                                    text: root.detailItem?.kind === "provider"
                                        ? Translation.tr("Download this CC0 score to decode its first measures into the preview.")
                                        : Translation.tr("This score has no preview notation yet.")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: QanunStyle.colSubtext
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: root.detailItem?.description
                                    text: root.detailItem?.description ?? ""
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: QanunStyle.colOnSurfaceVariant
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: ClockStyle.gapSmall
                                    ClockButton {
                                        symbol: root.detailItem?.kind === "composition" ? "edit" : "edit_note"
                                        label: root.detailItem?.kind === "composition"
                                            ? Translation.tr("Edit composition") : Translation.tr("Open in composer")
                                        variant: "tonal"
                                        enabled: root.detailNotes.length > 0 || root.detailItem?.kind === "composition"
                                        onClicked: root.copyToComposer()
                                    }
                                    Item { Layout.fillWidth: true }
                                    StyledText {
                                        text: root.detailItem?.kind === "provider" && root.detailSaved
                                            ? Translation.tr("Downloaded CC0 score · OpenScore String Quartets")
                                            : root.detailItem?.license ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: QanunStyle.colSubtext
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Convert ───────────────────────────────────────────────────
        ConvertSheetPage {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.mode === "convert"
            compact: root.compact
            wide: root.wide
            onEditRequested: score => root.openConvertedInComposer(score)
        }

        // ── Composer ───────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.mode === "compose"
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

                    ClockIconButton {
                        symbol: "arrow_back"
                        tooltip: Translation.tr("Back to the library")
                        onClicked: root.setMode("discover")
                    }
                    ClockButton {
                        symbol: "add"
                        label: Translation.tr("New")
                        variant: "text"
                        onClicked: root.newComposition()
                    }
                    MaterialTextField {
                        Layout.fillWidth: true
                        Layout.maximumWidth: 380
                        text: root.composerTitle
                        placeholderText: Translation.tr("Score title")
                        font.pixelSize: Appearance.font.pixelSize.large
                        onTextChanged: root.composerTitle = text
                    }
                    Item { Layout.fillWidth: true }
                    ClockButton {
                        symbol: "undo"
                        label: Translation.tr("Undo")
                        variant: "text"
                        enabled: root.composerNotes.length > 0
                        onClicked: root.undoComposer()
                    }
                    ClockButton {
                        symbol: "delete_sweep"
                        label: Translation.tr("Clear")
                        variant: "text"
                        enabled: root.composerNotes.length > 0
                        onClicked: root.clearComposer()
                    }
                    ClockButton {
                        symbol: "play_arrow"
                        label: Translation.tr("Play")
                        variant: "tonal"
                        enabled: root.composerNotes.length > 0
                        onClicked: root.playComposer()
                    }
                    ClockButton {
                        symbol: "save"
                        label: Translation.tr("Save")
                        variant: "filled"
                        onClicked: root.saveComposer()
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { value: 4, label: "𝅝  4" },
                            { value: 2, label: "𝅗𝅥  2" },
                            { value: 1, label: "♩  1" },
                            { value: 0.5, label: "♪  ½" },
                            { value: 0.25, label: "𝅘𝅥𝅯  ¼" }
                        ]
                        ClockChip {
                            required property var modelData
                            label: modelData.label
                            selected: root.composerDuration === modelData.value
                            onClicked: root.composerDuration = modelData.value
                        }
                    }

                    ClockChip {
                        label: "Dot"
                        selected: root.composerDotted
                        onClicked: root.composerDotted = !root.composerDotted
                    }
                    ClockChip {
                        label: "Tie"
                        symbol: "link"
                        selected: root.composerTie
                        onClicked: root.composerTie = !root.composerTie
                    }
                    ClockChip {
                        label: "Rest"
                        symbol: "pause"
                        onClicked: root.addRest()
                    }

                    Rectangle {
                        width: 1
                        height: 32
                        color: Qt.alpha(QanunStyle.colOnSurface, 0.12)
                    }

                    Repeater {
                        model: [
                            { value: 0, label: "♮" },
                            { value: 1, label: "♯" },
                            { value: -1, label: "♭" },
                            { value: -0.5, label: "½♭" }
                        ]
                        ClockChip {
                            required property var modelData
                            label: modelData.label
                            selected: root.composerAccidental === modelData.value
                            onClicked: root.composerAccidental = modelData.value
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                    StyledText {
                        text: Translation.tr("Clef")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: QanunStyle.colSubtext
                    }
                    ClockChip {
                        label: "Treble"
                        selected: root.composerClef === "treble"
                        height_: 28
                        onClicked: root.composerClef = "treble"
                    }
                    ClockChip {
                        label: "Bass"
                        selected: root.composerClef === "bass"
                        height_: 28
                        onClicked: root.composerClef = "bass"
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: Translation.tr("Key")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: QanunStyle.colSubtext
                    }
                    Repeater {
                        model: [
                            { value: 0, label: "C" }, { value: 1, label: "G" }, { value: 2, label: "D" },
                            { value: -1, label: "F" }, { value: -2, label: "B♭" }, { value: -3, label: "E♭" }
                        ]
                        ClockChip {
                            required property var modelData
                            label: modelData.label
                            selected: root.composerKey === modelData.value
                            height_: 28
                            onClicked: root.composerKey = modelData.value
                        }
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: Translation.tr("Time")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: QanunStyle.colSubtext
                    }
                    Repeater {
                        model: [[2, 4], [3, 4], [4, 4], [6, 8]]
                        ClockChip {
                            required property var modelData
                            label: modelData[0] + "/" + modelData[1]
                            selected: root.composerTime[0] === modelData[0] && root.composerTime[1] === modelData[1]
                            height_: 28
                            onClicked: root.composerTime = Array.from(modelData)
                        }
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: Translation.tr("Tempo")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: QanunStyle.colSubtext
                    }
                    ClockStepper {
                        Layout.preferredWidth: 150
                        value: root.composerTempo
                        from: 40
                        to: 240
                        stepSize: 2
                        format: value => String(value) + " BPM"
                        onMoved: value => root.composerTempo = value
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.normal
                    color: QanunStyle.colField
                    clip: true

                    StyledFlickable {
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: composerStaff.implicitHeight + 24
                        clip: true

                        MusicStaff {
                            id: composerStaff
                            width: parent.width - 24
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 12
                            notes: root.composerNotes
                            clef: root.composerClef
                            keySignature: root.composerKey
                            timeSignature: root.composerTime
                            editable: true
                            showTimeSignature: true
                            onStaffClicked: (letter, octave, y) => root.addPitchedNote(letter, octave)
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall
                    StyledText {
                        Layout.fillWidth: true
                        text: root.composerNotes.length > 0
                            ? Translation.tr("Click the staff to add a note. Saved compositions live in the Saved shelf.")
                            : Translation.tr("Blank sheet — click a line or space to place the first note.")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: QanunStyle.colSubtext
                    }
                    StyledText {
                        text: String(root.composerNotes.length) + " notes"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.numbers
                        color: QanunStyle.colSubtext
                    }
                }
            }
        }
    }
}
