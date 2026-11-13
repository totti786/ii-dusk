pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/// Reading options in the quran.com spirit: how the page is laid out, text sizes, the Madani font and
/// which translation. Grouped into cards; the translations are searchable and open on the chosen one.
Rectangle {
    id: root

    /// [[id, name, author, language]]
    property var translations: []
    property int translationId: 20
    property bool showTranslation: true
    property int arabicSize: 36
    property int transSize: 17
    property bool downloading: false
    property string error: ""
    property bool pageFontsPresent: false
    property bool pageFontsBusy: false
    property string pageFontsProgress: ""
    property bool mushaf: false
    property bool pageFontsOn: false

    signal translationPicked(int id)
    signal showTranslationToggled(bool on)
    signal arabicSizeChanged2(int size)
    signal transSizeChanged2(int size)
    signal mushafToggled(bool on)
    signal pageFontsToggled(bool on)
    signal pageFontsRemoveRequested()
    signal closeRequested()

    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    MouseArea { anchors.fill: parent; onWheel: wheel => wheel.accepted = true }

    readonly property var sorted: {
        const rows = root.translations.slice();
        const rank = l => l === "english" ? 0 : l === "arabic" ? 1 : 2;
        rows.sort((a, b) => (rank(a[3]) - rank(b[3])) || a[3].localeCompare(b[3]) || a[1].localeCompare(b[1]));
        // objects, so the list can section on `lang`
        return rows.map(r => ({ id: r[0], name: r[1], author: r[2], lang: r[3] }));
    }

    readonly property string needle: filterField.text.trim().toLowerCase()
    readonly property var shown: root.needle === "" ? root.sorted : root.sorted.filter(t =>
        (t.name + " " + t.author + " " + t.lang).toLowerCase().includes(root.needle))
    readonly property var current: root.sorted.find(t => t.id === root.translationId) ?? null

    /// Open on the chosen translation instead of the top of the list
    function revealCurrent(): void {
        const i = root.shown.findIndex(t => t.id === root.translationId);
        if (i >= 0)
            list.positionViewAtIndex(i, ListView.Center);
    }
    /// The options hug their content; the list of translations takes what it is given
    readonly property real wantedHeight: root.picking ? 560 : headerRow.implicitHeight + optionsColumn.implicitHeight + 28 + 10

    /// The translation list is a page of its own: it needs the whole height, and the other options do not
    property bool picking: false
    onPickingChanged: {
        if (root.picking) {
            filterField.text = "";
            Qt.callLater(root.revealCurrent);
        }
    }
    onVisibleChanged: {
        if (!visible)
            root.picking = false;
        else
            Qt.callLater(root.revealCurrent);
    }
    onSortedChanged: if (visible) Qt.callLater(root.revealCurrent)

    /// One rounded group of rows
    component Card: Rectangle {
        id: card
        property string title: ""
        default property alias rows: cardRows.data
        Layout.fillWidth: true
        implicitHeight: cardColumn.implicitHeight + 24
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer2

        ColumnLayout {
            id: cardColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            StyledText {
                visible: card.title !== ""
                text: card.title
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: Appearance.colors.colPrimary
            }
            ColumnLayout {
                id: cardRows
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10
            }
        }
    }

    /// A switch row: the label with what it does under it
    component SwitchRow: RowLayout {
        id: switchRow
        property string label: ""
        property string hint: ""
        property bool checked: false
        property bool busy: false
        signal toggled(bool on)
        Layout.fillWidth: true
        spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            StyledText {
                Layout.fillWidth: true
                text: switchRow.label
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                visible: switchRow.hint !== ""
                text: switchRow.hint
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
        StyledSwitch {
            enabled: !switchRow.busy
            checked: switchRow.checked
            onToggled: switchRow.toggled(checked)
        }
    }

    /// A number row: - value +
    component StepRow: RowLayout {
        id: stepRow
        property string label: ""
        property int value: 0
        property int from: 0
        property int to: 100
        property int step: 1
        signal edited(int value)
        Layout.fillWidth: true
        spacing: 6

        StyledText { Layout.fillWidth: true; text: stepRow.label; color: Appearance.colors.colOnLayer1 }
        QuranButton {
            icon: "remove"
            enabled: stepRow.value > stepRow.from
            onClicked: stepRow.edited(Math.max(stepRow.from, stepRow.value - stepRow.step))
        }
        StyledText {
            Layout.preferredWidth: 32
            horizontalAlignment: Text.AlignHCenter
            text: String(stepRow.value)
            color: Appearance.colors.colOnLayer1
        }
        QuranButton {
            icon: "add"
            enabled: stepRow.value < stepRow.to
            onClicked: stepRow.edited(Math.min(stepRow.to, stepRow.value + stepRow.step))
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // ── Header: the title, or the way back from the translation list
        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            spacing: 6
            QuranButton {
                visible: root.picking
                icon: "arrow_back"
                onClicked: root.picking = false
            }
            StyledText {
                Layout.fillWidth: true
                text: root.picking ? Translation.tr("Translation") : Translation.tr("Reading settings")
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            QuranButton {
                icon: "close"
                onClicked: root.closeRequested()
            }
        }

        // ── The options
        ColumnLayout {
            id: optionsColumn
            Layout.fillWidth: true
            visible: !root.picking
            spacing: 10

            Card {
                SwitchRow {
                    label: Translation.tr("Mushaf layout")
                    hint: Translation.tr("Printed pages instead of verse by verse")
                    checked: root.mushaf
                    onToggled: on => root.mushafToggled(on)
                }
                SwitchRow {
                    label: Translation.tr("Show translation")
                    checked: root.showTranslation
                    onToggled: on => root.showTranslationToggled(on)
                }
            }

            Card {
                StepRow {
                    label: Translation.tr("Arabic size")
                    value: root.arabicSize
                    from: 24; to: 64; step: 2
                    onEdited: v => root.arabicSizeChanged2(v)
                }
                StepRow {
                    label: Translation.tr("Translation size")
                    value: root.transSize
                    from: 12; to: 30
                    onEdited: v => root.transSizeChanged2(v)
                }
            }

            Card {
                // Not on disk yet: say what it costs and let the person start the download,
                // rather than a switch that quietly begins fetching ~200 MB
                RowLayout {
                    visible: !root.pageFontsPresent
                    Layout.fillWidth: true
                    spacing: 10
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Madani mushaf font")
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.pageFontsBusy ? (root.pageFontsProgress || Translation.tr("Downloading…"))
                                : Translation.tr("The printed Madani page glyphs. Needs a one-time download of about 200 MB; until then the Hafs font is used.")
                            wrapMode: Text.WordWrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    QuranPill {
                        implicitHeight: 34
                        icon: root.pageFontsBusy ? "hourglass_top" : "download"
                        text: root.pageFontsBusy ? Translation.tr("Downloading") : Translation.tr("Download")
                        active: root.pageFontsBusy
                        enabled: !root.pageFontsBusy
                        onClicked: root.pageFontsToggled(true)
                    }
                }
                // Downloaded: a plain switch, and a way to free the space
                RowLayout {
                    visible: root.pageFontsPresent
                    Layout.fillWidth: true
                    spacing: 10
                    SwitchRow {
                        Layout.fillWidth: true
                        label: Translation.tr("Madani mushaf font")
                        hint: root.pageFontsOn ? Translation.tr("quran.com page glyphs, ~200 MB on disk") : Translation.tr("Off, using the Hafs font (the download is kept)")
                        checked: root.pageFontsOn
                        onToggled: on => root.pageFontsToggled(on)
                    }
                    QuranButton {
                        enabled: !root.pageFontsBusy
                        icon: "delete"
                        onClicked: root.pageFontsRemoveRequested()
                    }
                }
            }

            // Opens the list of translations
            Card {
                id: translationCard
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText {
                            text: Translation.tr("Translation")
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.downloading ? Translation.tr("Downloading…")
                                : root.error !== "" ? root.error
                                : root.current ? root.current.name : ""
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: root.error !== "" && !root.downloading ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                        }
                    }
                    MaterialSymbol {
                        text: "chevron_right"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colSubtext
                    }
                }
                MouseArea {
                    parent: translationCard
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picking = true
                }
            }

            Item { Layout.fillHeight: true }
        }

        // ── The translations
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.picking
            spacing: 8

            MaterialTextField {
                id: filterField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Search translations")
            }

            ListView {
                id: list
                TouchpadScrollHandler { flickable: list }
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: root.shown
                boundsBehavior: Flickable.StopAtBounds
                section.property: "lang"
                section.criteria: ViewSection.FullString
                section.delegate: Item {
                    required property string section
                    width: list.width
                    height: 28
                    StyledText {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.bottom: parent.bottom
                        text: section.charAt(0).toUpperCase() + section.slice(1)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colSubtext
                    }
                }
                delegate: Rectangle {
                    id: item
                    required property var modelData
                    readonly property bool chosen: modelData.id === root.translationId
                    width: list.width
                    height: 46
                    radius: Appearance.rounding.normal
                    color: item.chosen ? Appearance.colors.colSecondaryContainer : itemArea.containsMouse ? Appearance.colors.colLayer2 : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8
                        MaterialSymbol {
                            text: "check"
                            iconSize: 18
                            opacity: item.chosen ? 1 : 0
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: item.modelData.name
                                elide: Text.ElideRight
                                color: item.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: item.modelData.author
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                    MouseArea {
                        id: itemArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.translationPicked(item.modelData.id)
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: root.shown.length === 0
                    text: root.translations.length === 0 ? Translation.tr("No translations found") : Translation.tr("Nothing matches")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
