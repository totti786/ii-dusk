import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The question/answer surface and the answer buttons.
 *
 * The controller owns the service state; this pane only renders it and emits intent.
 */
Item {
    id: root

    property var card: null
    property var answer: null
    property string phase: "closed"
    property bool busy: false
    property bool autoPlayAudio: true
    property var counts: ({})

    property alias typedText: typedInput.text
    readonly property bool typing: typedInput.activeFocus
    readonly property bool compactStatus: root.width < 640

    // Anki's answer template usually starts with {{FrontSide}} and a rule, so the answer
    // HTML repeats the question. The question stays on screen above, so show only what
    // follows the rule.
    readonly property string answerOnlyHtml: {
        const html = root.answer?.answerHtml ?? "";
        const parts = html.split(/<hr[^>]*\bid\s*=\s*["']?answer["']?[^>]*>/i);
        return parts.length > 1 ? parts[parts.length - 1] : html;
    }

    signal revealRequested(string typed)
    signal answerRequested(int rating)

    function replayAudio(): void {
        if (root.phase === "answer" && answerMedia.count > 0)
            answerMedia.playAll();
        else
            questionMedia.playAll();
    }

    readonly property var flagColors: ["transparent", "#ef5350", "#ffa726", "#66bb6a", "#42a5f5", "#ec407a", "#26a69a", "#ab47bc"]

    function colorFor(rating: int): color {
        switch (rating) {
        case 0: return ClockStyle.colErrorContainer;
        case 1: return ClockStyle.colTertiaryContainer;
        case 2: return ClockStyle.colPrimary;
        default: return ClockStyle.colSecondaryContainer;
        }
    }

    function contentColorFor(rating: int): color {
        switch (rating) {
        case 0: return ClockStyle.colOnErrorContainer;
        case 1: return ClockStyle.colOnTertiaryContainer;
        case 2: return ClockStyle.colOnPrimary;
        default: return ClockStyle.colOnSecondaryContainer;
        }
    }

    function kindLabel(kind: string): string {
        switch (kind) {
        case "new": return Translation.tr("New");
        case "learning": return Translation.tr("Learning");
        case "relearning": return Translation.tr("Relearning");
        default: return Translation.tr("Review");
        }
    }

    onCardChanged: {
        if (root.card)
            typedInput.text = "";
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: ClockStyle.paneGap

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: ClockStyle.radiusLarge
            color: ClockStyle.colPane

            // Status line: what kind of card this is, and what is left in the deck.
            RowLayout {
                id: statusRow
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: ClockStyle.cardPadding
                }
                spacing: ClockStyle.gapSmall

                ClockChip {
                    label: root.kindLabel(root.card?.kind ?? "review")
                    selected: true
                }

                MaterialSymbol {
                    visible: root.card?.marked ?? false
                    text: "star"
                    fill: 1
                    iconSize: 20
                    color: "#ffca28"
                }

                MaterialSymbol {
                    visible: (root.card?.flag ?? 0) > 0
                    text: "flag"
                    fill: 1
                    iconSize: 20
                    color: root.flagColors[root.card?.flag ?? 0] ?? "transparent"
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.card?.scripted ?? false
                    text: Translation.tr("Scripted card — open in Anki for the full view")
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                    elide: Text.ElideRight
                }

                Item {
                    Layout.fillWidth: true
                    visible: !(root.card?.scripted ?? false)
                }

                Repeater {
                    model: [
                        { key: "new", label: Translation.tr("New"), tint: ClockStyle.colPrimary },
                        { key: "learn", label: Translation.tr("Learning"), tint: ClockStyle.colError },
                        { key: "review", label: Translation.tr("Review"), tint: ClockStyle.colTertiary }
                    ]

                    delegate: Rectangle {
                        id: countPill
                        required property var modelData
                        readonly property bool current: (root.card?.kind === "new" && modelData.key === "new")
                            || ((root.card?.kind === "learning" || root.card?.kind === "relearning") && modelData.key === "learn")
                            || (root.card?.kind === "review" && modelData.key === "review")
                        implicitWidth: pillRow.implicitWidth + 20
                        implicitHeight: 28
                        radius: height / 2
                        color: countPill.current ? ClockStyle.colSurfaceHigh : "transparent"

                        Row {
                            id: pillRow
                            anchors.centerIn: parent
                            spacing: 6

                            StyledText {
                                text: Number(root.counts?.[countPill.modelData.key] ?? 0)
                                color: countPill.modelData.tint
                                font.pixelSize: ClockStyle.textNormal
                                font.weight: Font.DemiBold
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: countPill.modelData.label
                                color: ClockStyle.colSubtext
                                font.pixelSize: ClockStyle.textSmall
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !root.compactStatus
                            }
                        }
                    }
                }
            }

            Flickable {
                WheelScroll {}
                id: flick
                anchors {
                    top: statusRow.bottom
                    bottom: parent.bottom
                    left: parent.left
                    right: parent.right
                    topMargin: ClockStyle.gap
                    leftMargin: ClockStyle.cardPadding
                    rightMargin: ClockStyle.cardPadding
                    bottomMargin: ClockStyle.cardPadding
                }
                contentWidth: width
                contentHeight: Math.max(height, cardColumn.implicitHeight)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick

                // A short card sits in the middle of the surface; a long one scrolls.
                ColumnLayout {
                    id: cardColumn
                    width: Math.min(flick.width, 760)
                    x: (flick.width - width) / 2
                    y: Math.max(0, (flick.height - implicitHeight) / 2)
                    spacing: ClockStyle.gap

                    AnkiCardHtml {
                        Layout.fillWidth: true
                        pixelSize: root.phase === "answer" ? 24 : 34
                        textColor: root.phase === "answer" ? ClockStyle.colSubtext : ClockStyle.colOnSurface
                        html: root.card?.questionHtml ?? ""
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.maximumWidth: 480
                        Layout.alignment: Qt.AlignHCenter
                        visible: !!root.card?.typeAnswer && root.phase === "question"
                        implicitHeight: 52
                        radius: ClockStyle.radiusLarge
                        color: typedInput.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField

                        StyledTextInput {
                            id: typedInput
                            anchors.fill: parent
                            anchors.leftMargin: 18
                            anchors.rightMargin: 18
                            verticalAlignment: TextInput.AlignVCenter
                            horizontalAlignment: TextInput.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.larger
                            color: ClockStyle.colOnSurface
                            onAccepted: root.revealRequested(typedInput.text)
                        }

                        StyledText {
                            anchors.fill: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            visible: typedInput.text.length === 0
                            text: Translation.tr("Type the answer")
                            font.pixelSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer1Inactive
                        }
                    }

                    AnkiMedia {
                        id: questionMedia
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: implicitWidth
                        clips: root.card?.audio ?? []
                        active: root.phase === "question" && root.visible
                        autoPlay: root.autoPlayAudio
                    }

                    // Between question and answer: a hairline with the word "Answer" on it.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: ClockStyle.gap
                        Layout.bottomMargin: ClockStyle.gapSmall
                        visible: root.phase === "answer"
                        spacing: ClockStyle.gap

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: ClockStyle.colOutline
                        }

                        StyledText {
                            text: Translation.tr("Answer")
                            color: ClockStyle.colSubtext
                            font.pixelSize: ClockStyle.textSmall
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 1.2
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: ClockStyle.colOutline
                        }
                    }

                    AnkiCardHtml {
                        Layout.fillWidth: true
                        visible: root.phase === "answer"
                        pixelSize: 30
                        html: root.answerOnlyHtml
                    }

                    AnkiMedia {
                        id: answerMedia
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: implicitWidth
                        visible: root.phase === "answer" && (root.answer?.audio ?? []).length > 0
                        clips: root.answer?.audio ?? []
                        active: root.phase === "answer" && root.visible
                        autoPlay: root.autoPlayAudio
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.card?.hasMissingMedia ?? false
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("Some media is missing from the local Anki media folder.")
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        ClockButton {
            Layout.fillWidth: true
            Layout.maximumWidth: 760
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 56
            visible: root.phase === "question"
            label: Translation.tr("Show answer  ·  Space")
            symbol: "visibility"
            variant: "filled"
            enabled: !root.busy
            onClicked: root.revealRequested(root.typedText)
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: 760
            Layout.alignment: Qt.AlignHCenter
            visible: root.phase === "answer"
            spacing: ClockStyle.gapSmall

            Repeater {
                model: root.phase === "answer" ? (root.answer?.buttons ?? []) : []

                delegate: GradeButton {
                    required property var modelData
                    required property int index
                    keyHint: String(index + 1)
                    label: modelData.label
                    interval: modelData.interval
                    buttonColor: root.colorFor(modelData.rating)
                    contentColor: root.contentColorFor(modelData.rating)
                    enabled: !root.busy
                    onClicked: root.answerRequested(modelData.rating)
                }
            }
        }
    }
}
