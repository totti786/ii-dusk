pragma ComponentBehavior: Bound

import "aminoacids"
import "aminoacids/amino_acids.js" as AA
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    readonly property bool isCurrentTab: {
        try {
            return swipeView.currentIndex === index;
        } catch (e) {
            return true;
        }
    }
    readonly property bool isTabActive: root.visible && root.isCurrentTab

    readonly property string schemeName: Config.options.cheatsheet.aminoAcidScheme
    readonly property var classes: AA.scheme(root.schemeName).classes

    property string filter: ""
    property string classFilter: ""
    property var selected: null
    property bool codonTableOpen: false

    onFocusChanged: focus => {
        if (focus)
            filterField.forceActiveFocus();
    }

    // Amino acids grouped by class, in the scheme's class order.
    readonly property var ordered: {
        const out = [];
        for (let i = 0; i < root.classes.length; i++) {
            const key = root.classes[i].key;
            for (let j = 0; j < AA.aminoAcids.length; j++) {
                const aa = AA.aminoAcids[j];
                if (AA.classOf(aa, root.schemeName) === key)
                    out.push({
                        aa: aa,
                        hueOffset: root.classes[i].hueOffset,
                        shade: root.classes[i].shade,
                        classKey: key
                    });
            }
        }
        return out;
    }

    // Filtering hides cards in place rather than rebuilding the model, so the
    // entrance animation doesn't replay on every keystroke.
    function matches(entry) {
        if (root.classFilter !== "" && entry.classKey !== root.classFilter)
            return false;
        const f = root.filter.trim().toLowerCase();
        if (f === "")
            return true;
        return AA.searchBlob(entry.aa, root.schemeName).includes(f);
    }

    readonly property int matchCount: {
        let n = 0;
        for (let i = 0; i < root.ordered.length; i++)
            if (root.matches(root.ordered[i]))
                n++;
        return n;
    }

    // 22 cards + a 2-slot summary = 24 = exactly four full rows of six.
    readonly property int gridColumns: 6
    readonly property real gridSpacing: 10

    // The summary card is laid out for two slots and always takes exactly two.
    // Stretching it across every free slot left it swimming in dead space on a
    // sparse row, and a final row with nothing to spare dropped it entirely.
    readonly property int summarySpan: Math.min(2, root.gridColumns)

    // Slots left over on the last row of cards. The summary trails there when it
    // fits; otherwise GridLayout wraps it onto a row of its own.
    readonly property int trailingSlots: {
        const rem = root.matchCount % root.gridColumns;
        return rem === 0 ? 0 : root.gridColumns - rem;
    }
    readonly property bool summaryWrapped: root.matchCount > 0 && root.trailingSlots < root.summarySpan

    // Columns the grid actually occupies. Sized off the flickable rather than
    // off the grid itself, so the grid can shrink to fit without the card width
    // feeding back into it.
    readonly property real gridWidth: gridFlickable.width - 12
    readonly property int usedColumns: Math.min(root.gridColumns, root.summaryWrapped ? root.matchCount : root.matchCount + root.summarySpan)

    // Cards are sized explicitly rather than with Layout.fillWidth: the layout
    // then settles in one pass instead of renegotiating widths, and each
    // molecule's geometry is built once.
    readonly property real cardWidth: Math.floor((root.gridWidth - (root.gridColumns - 1) * root.gridSpacing) / root.gridColumns)
    readonly property real cardHeight: Math.max(150, Math.floor((gridFlickable.height - 3 * root.gridSpacing - 4) / 4))

    ColumnLayout {
        anchors {
            fill: parent
            bottomMargin: 62
        }
        spacing: 8

        // ── Class legend ─────────────────────────────────────────────────────
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 6

            Repeater {
                model: root.classes

                delegate: RippleButton {
                    id: chip
                    required property var modelData

                    readonly property color tint: ColorUtils.categoryAccent(modelData.hueOffset, modelData.shade, Appearance.m3colors.m3primary)
                    readonly property bool picked: root.classFilter === modelData.key

                    implicitWidth: chipRow.implicitWidth + 22
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    colBackground: chip.picked ? ColorUtils.transparentize(chip.tint, 0.55) : Appearance.colors.colLayer1
                    colBackgroundHover: ColorUtils.transparentize(chip.tint, 0.7)
                    colRipple: ColorUtils.transparentize(chip.tint, 0.5)

                    onClicked: root.classFilter = chip.picked ? "" : chip.modelData.key

                    RowLayout {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 7

                        Rectangle {
                            implicitWidth: 10
                            implicitHeight: 10
                            radius: Appearance.rounding.full
                            color: chip.tint
                        }

                        StyledText {
                            text: chip.modelData.name
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: chip.picked ? Font.DemiBold : Font.Normal
                        }
                    }
                }
            }
        }

        // ── Card grid ────────────────────────────────────────────────────────
        StyledFlickable {
            id: gridFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: cardGrid.implicitHeight + 8

            GridLayout {
                id: cardGrid
                // Only as wide as the columns in use — given the full width,
                // GridLayout would hand the slack to the columns and open gaps
                // between the cards instead of leaving it at the edge. What is
                // left over goes to the margins, so a short set sits centred.
                width: root.usedColumns * root.cardWidth + (root.usedColumns - 1) * root.gridSpacing
                x: 4 + Math.round((root.gridWidth - width) / 2)
                columns: root.gridColumns
                rowSpacing: root.gridSpacing
                columnSpacing: root.gridSpacing

                // One group fade instead of 22 staggered per-card reveals.
                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.dur(180)
                        easing.type: Easing.OutCubic
                    }
                }

                Repeater {
                    model: root.ordered

                    delegate: AminoAcidCard {
                        required property var modelData
                        required property int index
                        visible: root.matches(modelData)
                        Layout.preferredWidth: root.cardWidth
                        Layout.preferredHeight: root.cardHeight
                        aa: modelData.aa
                        hueOffset: modelData.hueOffset
                        shade: modelData.shade
                        selected: root.selected === modelData.aa
                        onClicked: root.selected = modelData.aa
                    }
                }

                // Trails the last card, wrapping to its own row when that one is
                // full. On a row of its own it claims every column so the centre
                // alignment has the whole width to work against — otherwise it
                // would sit hard against the left edge under a full row.
                AminoAcidSummaryCard {
                    visible: root.matchCount > 0
                    schemeName: root.schemeName
                    Layout.alignment: Qt.AlignHCenter
                    Layout.columnSpan: root.summaryWrapped ? root.usedColumns : root.summarySpan
                    Layout.preferredWidth: root.cardWidth * root.summarySpan + root.gridSpacing * (root.summarySpan - 1)
                    Layout.preferredHeight: root.cardHeight
                }
            }
        }
    }

    PagePlaceholder {
        anchors.centerIn: parent
        shown: root.matchCount === 0
        icon: "search_off"
        description: Translation.tr("No amino acid matches")
        shape: MaterialShape.Shape.Ghostish
        descriptionHorizontalAlignment: Text.AlignHCenter
    }

    // ── Search toolbar ───────────────────────────────────────────────────────
    Toolbar {
        id: extraOptions
        z: 2
        enableShadow: false
        colBackground: Appearance.colors.colSecondaryContainer
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: 8
        }

        transform: Translate {
            y: root.isTabActive ? 0 : 35
        }
        opacity: root.isTabActive ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.dur(250)
                easing.type: Easing.OutCubic
            }
        }
        Behavior on transform {
            NumberAnimation {
                duration: Appearance.dur(350)
                easing.type: Easing.OutBack
                easing.overshoot: 1.3
            }
        }

        ToolbarTextField {
            id: filterField
            placeholderText: focus ? Translation.tr("Filter amino acids") : Translation.tr("Hit \"/\" to filter")
            clip: true
            font.pixelSize: Appearance.font.pixelSize.small
            onTextChanged: root.filter = text
        }

        IconToolbarButton {
            implicitWidth: height
            text: "close"
            onClicked: {
                root.filter = filterField.text = "";
                root.classFilter = "";
            }

            StyledToolTip {
                text: Translation.tr("Clear filter")
            }
        }
    }

    // ── Genetic code button ──────────────────────────────────────────────────
    RippleButton {
        id: codonButton
        z: 2
        implicitWidth: 44
        implicitHeight: 44
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        onClicked: root.codonTableOpen = true

        anchors {
            right: parent.right
            bottom: parent.bottom
            rightMargin: 8
            bottomMargin: 8
        }

        opacity: root.isTabActive ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.dur(250)
                easing.type: Easing.OutCubic
            }
        }

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: "table_chart"
            iconSize: 22
            color: Appearance.colors.colOnSecondaryContainer
        }

        StyledToolTip {
            text: Translation.tr("Genetic code table")
        }
    }

    // ── Overlays ─────────────────────────────────────────────────────────────
    FadeLoader {
        id: detailLoader
        anchors.fill: parent
        z: 20
        shown: root.selected !== null
        // Stay loaded until the fade-out finishes, then drop the instance.
        active: shown || opacity > 0

        sourceComponent: AminoAcidDetail {
            aa: root.selected
            schemeName: root.schemeName
            onCloseRequested: root.selected = null
        }
    }

    FadeLoader {
        id: codonLoader
        anchors.fill: parent
        z: 21
        shown: root.codonTableOpen
        active: shown || opacity > 0

        sourceComponent: CodonTablePopup {
            schemeName: root.schemeName
            highlightLetter: root.selected ? root.selected.one : ""
            onCloseRequested: root.codonTableOpen = false
        }
    }

    // Hand focus back to the filter field once a popup closes.
    onSelectedChanged: {
        if (root.selected === null && !root.codonTableOpen && root.isTabActive)
            filterField.forceActiveFocus();
    }
    onCodonTableOpenChanged: {
        if (!root.codonTableOpen && root.selected === null && root.isTabActive)
            filterField.forceActiveFocus();
    }
}
