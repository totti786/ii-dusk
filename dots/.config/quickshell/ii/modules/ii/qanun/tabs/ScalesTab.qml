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
 * Maqams & scales: a searchable index of the main Arabic maqamat and Western
 * scales, each opened into its degrees, interval formula, ajnas and a playable
 * qanun diagram with the Arabic mandal pattern.
 */
Item {
    id: root

    property bool compact: false
    property bool wide: false

    property string query: ""
    property string category: "all"
    property var selectedScale: null
    property int rootShift: 0
    property string notation: String(QanunStore.settings.general.notation ?? "letters")

    readonly property var effectiveScale: root.selectedScale ?? QanunData.allScales("maqam")[0]
    readonly property var filteredScales: {
        const needle = root.query.trim().toLowerCase();
        const list = QanunData.allScales(root.category);
        if (needle.length === 0)
            return list;
        return list.filter(item => String(item.searchText ?? "").includes(needle)
            || String(item.name ?? "").toLowerCase().includes(needle)
            || String(item.arabic ?? "").includes(root.query.trim()));
    }
    readonly property real effectiveRoot: {
        const base = Number(root.effectiveScale?.rootPc ?? 0);
        const shifted = base + root.rootShift;
        return ((shifted % 12) + 12) % 12;
    }
    readonly property var degrees: QanunData.scaleNotes(root.effectiveScale, root.effectiveRoot, root.notation)
    readonly property var previewNotes: {
        const result = [];
        for (let i = 0; i < root.degrees.length; ++i) {
            const item = root.degrees[i];
            result.push({
                letter: item.letter, alter: item.alter, octave: item.octave,
                duration: i === root.degrees.length - 1 ? 2 : 1, rest: false,
                dotted: false, tie: false, midi: item.midi
            });
        }
        return result;
    }
    readonly property var highlightPitchClasses: {
        const result = [];
        for (const note of root.degrees) {
            const pc = Math.round(Number(note.midi)) % 12;
            if (result.indexOf(pc) < 0)
                result.push(pc);
        }
        return result;
    }
    readonly property var liftedMandals: {
        // The qanun is referenced to C major: every four-mandal course starts
        // with two mandals lifted, except Si (B) and Mi (E), whose four are all
        // lifted in C major. Courses with three, two or one mandal start fully
        // lifted. Each scale then moves the affected letter up/down by quarter
        // tones; a semitone is two mandals.
        const alterations = {};
        for (const note of root.degrees) {
            const letter = String(note.letter ?? "").toUpperCase();
            if (letter.length > 0)
                alterations[letter] = Number(note.alter ?? 0);
        }

        const result = {};
        const strings = QanunData.qanunStrings;
        for (let index = 0; index < strings.length; ++index) {
            const item = strings[index];
            const count = Number(item.mandals ?? 0);
            if (count <= 0)
                continue;
            const letter = String(item.letter ?? "").toUpperCase();
            let base = count;
            if (count === 4)
                base = (letter === "B" || letter === "E") ? 4 : 2;
            else if (count === 3)
                base = 3;
            else if (count === 2)
                base = 2;
            else if (count === 1)
                base = 1;
            const delta = Math.round(Number(alterations[letter] ?? 0) * 2);
            const lifted = Math.max(0, Math.min(count, base + delta));
            const dots = [];
            for (let dot = 0; dot < lifted; ++dot)
                dots.push(dot);
            result[index] = dots;
        }
        return result;
    }
    readonly property int liftedMandalCount: {
        let total = 0;
        for (const key in root.liftedMandals)
            total += root.liftedMandals[key].length;
        return total;
    }
    readonly property string rootLabel: {
        const spelling = QanunData.rootSpelling(root.effectiveRoot);
        return QanunData.noteLabel(spelling.letter, spelling.alter, root.notation);
    }
    readonly property string scaleFormula: QanunData.scaleFormula(root.effectiveScale)
    readonly property int mandalTotal: QanunData.qanunMandalCounts.reduce((sum, value) => sum + value, 0)
    readonly property string pageSubtitle: Translation.tr("%1 maqams · %2 Western scales · %3 mandals on the qanun")
        .arg(String(QanunData.maqams.length)).arg(String(QanunData.westernScales.length)).arg(String(root.mandalTotal))

    Connections {
        target: QanunStore
        function onDataChanged() {
            root.notation = String(QanunStore.settings.general.notation ?? "letters");
        }
    }

    function chooseScale(item): void {
        root.selectedScale = item;
        root.rootShift = 0;
    }

    function nudgeRoot(delta: int): void {
        root.rootShift += delta;
    }

    function playScale(): void {
        const ascending = root.degrees.map((note, index) => ({
            midi: note.midi, beats: index === root.degrees.length - 1 ? 2 : 1
        }));
        const descending = ascending.slice(0, -1).reverse();
        QanunStore.playMidiSequence(ascending.concat(descending), 84,
            root.effectiveScale.name + " · " + root.rootLabel);
    }

    function playDegree(note): void {
        QanunStore.playTone(note.midi, 1.0);
    }

    // ── Search and index ────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.gap
        spacing: ClockStyle.gap

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 70
            radius: ClockStyle.radiusCard
            color: ClockStyle.colPane

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: ClockStyle.gapLarge
                anchors.rightMargin: ClockStyle.gapLarge
                spacing: ClockStyle.gap

                MaterialSymbol {
                    text: "search"
                    iconSize: ClockStyle.iconNormal
                    color: QanunStyle.colOnSurfaceVariant
                }

                MaterialTextField {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.maximumWidth: 520
                    placeholderText: Translation.tr("Search maqams and scales — Rast, Hijaz, Dorian…")
                    text: root.query
                    onTextChanged: root.query = text
                }

                Item { Layout.fillWidth: true }

                Repeater {
                    model: [
                        { id: "all", label: Translation.tr("All") },
                        { id: "maqam", label: Translation.tr("Maqams") },
                        { id: "western", label: Translation.tr("Western") }
                    ]
                    ClockChip {
                        required property var modelData
                        label: modelData.label
                        selected: root.category === modelData.id
                        onClicked: root.category = modelData.id
                    }
                }

                ClockButton {
                    symbol: "play_arrow"
                    label: Translation.tr("Play")
                    variant: "tonal"
                    onClicked: root.playScale()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: ClockStyle.gap

            // Index
            Rectangle {
                visible: !root.compact || root.selectedScale === null
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 330
                Layout.minimumWidth: 260
                Layout.maximumWidth: root.compact ? 100000 : 380
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
                            text: Translation.tr("Scale index")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: QanunStyle.colOnSurface
                        }
                        StyledText {
                            text: String(root.filteredScales.length)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.numbers
                            color: QanunStyle.colSubtext
                        }
                    }

                    ListView {
                        id: scaleList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        model: root.filteredScales
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: StyledScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: RippleButton {
                            id: row
                            required property var modelData
                            width: scaleList.width
                            implicitHeight: 66
                            buttonRadius: ClockStyle.radiusNormal
                            interactionScale: 1
                            scaleBehaviorEnabled: false
                            toggled: root.selectedScale?.id === row.modelData.id
                                && root.selectedScale?.category === row.modelData.category
                            colBackground: "transparent"
                            colBackgroundHover: Qt.alpha(QanunStyle.colOnSurface, 0.04)
                            colBackgroundActive: Qt.alpha(QanunStyle.colOnSurface, 0.08)
                            colBackgroundToggled: Qt.alpha(QanunStyle.colPrimary, 0.12)
                            colBackgroundToggledHover: Qt.alpha(QanunStyle.colPrimary, 0.16)
                            colRipple: Qt.alpha(QanunStyle.colPrimary, 0.12)
                            onClicked: root.chooseScale(row.modelData)

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
                                        text: row.modelData.category === "maqam" ? "auto_awesome" : "piano"
                                        iconSize: 19
                                        fill: row.toggled ? 1 : 0
                                        color: row.toggled ? QanunStyle.colPrimary : QanunStyle.colOnSurfaceVariant
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 1
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 5
                                        StyledText {
                                            text: row.modelData.name
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                            color: row.toggled ? QanunStyle.colPrimary : QanunStyle.colOnSurface
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        StyledText {
                                            visible: String(row.modelData.arabic ?? "").length > 0
                                            text: String(row.modelData.arabic ?? "")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: QanunStyle.colSubtext
                                        }
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: (row.modelData.kind ?? "") + " · " + row.modelData.family
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: QanunStyle.colSubtext
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Detail
            Rectangle {
                visible: !root.compact || root.selectedScale !== null
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: ClockStyle.radiusCard
                color: ClockStyle.colPane
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: ClockStyle.gapLarge
                    spacing: ClockStyle.gap

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall

                        ClockIconButton {
                            visible: root.compact
                            symbol: "arrow_back"
                            tooltip: Translation.tr("Back to the index")
                            onClicked: root.selectedScale = null
                        }

                        ClockBadge {
                            size: 44
                            text: root.effectiveScale.category === "maqam" ? "auto_awesome" : "piano"
                            shape: root.effectiveScale.category === "maqam"
                                ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Clover4Leaf
                            color: root.effectiveScale.category === "maqam"
                                ? ClockStyle.colPrimary : ClockStyle.colTertiary
                            colSymbol: root.effectiveScale.category === "maqam"
                                ? ClockStyle.colOnPrimary : ClockStyle.colOnTertiary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 1
                            RowLayout {
                                spacing: 6
                                StyledText {
                                    text: root.effectiveScale.name
                                    font.family: Appearance.font.family.title
                                    font.variableAxes: ({ "wght": 720, "wdth": 100, "ROND": 100 })
                                    font.pixelSize: Appearance.font.pixelSize.huge
                                    color: QanunStyle.colOnSurface
                                }
                                StyledText {
                                    visible: String(root.effectiveScale.arabic ?? "").length > 0
                                    text: String(root.effectiveScale.arabic ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.large
                                    color: QanunStyle.colSubtext
                                    Layout.alignment: Qt.AlignBottom
                                }
                            }
                            StyledText {
                                text: (root.effectiveScale.kind ?? "") + " · " + root.effectiveScale.family
                                    + " · " + (root.effectiveScale.mood ?? "")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: QanunStyle.colSubtext
                            }
                        }

                        RowLayout {
                            spacing: 2
                            ClockIconButton {
                                symbol: "remove"
                                tooltip: Translation.tr("Transpose down")
                                size: 34
                                onClicked: root.nudgeRoot(-1)
                            }
                            Rectangle {
                                implicitWidth: 62
                                implicitHeight: 34
                                radius: Appearance.rounding.full
                                color: QanunStyle.colField
                                StyledText {
                                    anchors.centerIn: parent
                                    text: "root " + root.rootLabel
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    color: QanunStyle.colOnSurface
                                }
                            }
                            ClockIconButton {
                                symbol: "add"
                                tooltip: Translation.tr("Transpose up")
                                size: 34
                                onClicked: root.nudgeRoot(1)
                            }
                        }

                        ClockButton {
                            symbol: QanunStore.playingSequenceLabel.length > 0 ? "stop" : "play_arrow"
                            label: QanunStore.playingSequenceLabel.length > 0 ? Translation.tr("Stop") : Translation.tr("Play")
                            variant: QanunStore.playingSequenceLabel.length > 0 ? "tonal" : "filled"
                            onClicked: {
                                if (QanunStore.playingSequenceLabel.length > 0)
                                    QanunStore.stopSequence();
                                else
                                    root.playScale();
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Qt.alpha(QanunStyle.colOnSurface, 0.08)
                    }

                    StyledFlickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: width
                        contentHeight: detailBody.implicitHeight

                        RowLayout {
                            id: detailBody
                            width: parent.width
                            spacing: ClockStyle.gapLarge
                            height: Math.max(parent.height, implicitHeight)

                            QanunDiagram {
                                Layout.fillHeight: true
                                Layout.preferredWidth: root.width >= 860 ? 280 : 100
                                Layout.minimumWidth: 230
                                Layout.maximumWidth: 330
                                highlightPitchClasses: root.highlightPitchClasses
                                liftedMandals: root.liftedMandals
                                interactive: true
                                showLabels: true
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: ClockStyle.gap

                                // Degree chips.
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Repeater {
                                        model: root.degrees
                                        Rectangle {
                                            required property var modelData
                                            required property int index
                                            implicitWidth: degreeRow.implicitWidth + 20
                                            implicitHeight: 48
                                            radius: Appearance.rounding.small
                                            color: root.rootShift === 0 && index === 0
                                                ? Qt.alpha(QanunStyle.colPrimary, 0.16)
                                                : QanunStyle.colField

                                            RowLayout {
                                                id: degreeRow
                                                anchors.centerIn: parent
                                                spacing: 6
                                                StyledText {
                                                    text: modelData.name
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    font.weight: Font.Bold
                                                    color: root.rootShift === 0 && index === 0
                                                        ? QanunStyle.colPrimary : QanunStyle.colOnSurface
                                                }
                                                StyledText {
                                                    visible: root.notation !== "solfege"
                                                    text: modelData.solfege
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: QanunStyle.colSubtext
                                                }
                                                Rectangle {
                                                    width: 18
                                                    height: 18
                                                    radius: Appearance.rounding.full
                                                    color: Qt.alpha(QanunStyle.colOnSurface, 0.08)
                                                    StyledText {
                                                        anchors.centerIn: parent
                                                        text: String(index + 1)
                                                        font.pixelSize: 8
                                                        color: QanunStyle.colSubtext
                                                    }
                                                }
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.playDegree(modelData)
                                            }
                                        }
                                    }
                                }

                                // Formula.
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: ClockStyle.gapSmall
                                    StyledText {
                                        text: Translation.tr("Steps")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: QanunStyle.colSubtext
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.scaleFormula
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: QanunStyle.colOnSurface
                                    }
                                    StyledText {
                                        visible: QanunData.scaleIntervalLabels(root.effectiveScale).some(step => step === "¼" || step === "¾" || step === "A2")
                                        text: Translation.tr("quarter-tone aware")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: QanunStyle.colTertiary
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: description.implicitHeight + 24
                                    radius: Appearance.rounding.normal
                                    color: QanunStyle.colField

                                    StyledText {
                                        id: description
                                        anchors {
                                            fill: parent
                                            margins: 12
                                        }
                                        text: root.effectiveScale.description ?? ""
                                        wrapMode: Text.WordWrap
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: QanunStyle.colOnSurfaceVariant
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: ClockStyle.gapSmall
                                    StyledText {
                                        text: Translation.tr("Ajnas")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.DemiBold
                                        color: QanunStyle.colSubtext
                                    }
                                    Repeater {
                                        model: root.effectiveScale.jins ?? []
                                        Rectangle {
                                            required property var modelData
                                            implicitWidth: jinsText.implicitWidth + 16
                                            implicitHeight: 24
                                            radius: Appearance.rounding.full
                                            color: QanunStyle.colSecondaryContainer
                                            StyledText {
                                                id: jinsText
                                                anchors.centerIn: parent
                                                text: String(modelData)
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: QanunStyle.colOnSecondaryContainer
                                            }
                                        }
                                    }
                                }

                                MusicStaff {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 178
                                    notes: root.previewNotes
                                    clef: "treble"
                                    keySignature: 0
                                    timeSignature: [root.degrees.length, 4]
                                    showTimeSignature: false
                                    centerSingle: false
                                    accentIndex: 0
                                    accentColor: QanunStyle.colPrimary
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: ClockStyle.gapSmall
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("Mandal pattern: 0 · 2 · 3 · 3 · 4 on courses 5–23 · 3 on 24 · 1 · 1 (%1 dots). %2 lit for this scale.")
                                            .arg(String(root.mandalTotal)).arg(String(root.liftedMandalCount))
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: QanunStyle.colSubtext
                                        wrapMode: Text.WordWrap
                                    }
                                    ClockButton {
                                        symbol: "volume_up"
                                        label: Translation.tr("Play degrees")
                                        variant: "text"
                                        onClicked: root.playScale()
                                    }
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }
                    }
                }
            }
        }
    }
}
