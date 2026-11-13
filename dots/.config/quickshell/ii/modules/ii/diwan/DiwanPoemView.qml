pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "DiwanCore.js" as Core

/**
 * One poem, set the way a diwan is written out: a classical verse is staggered, the first
 * half-line (sadr) on its own line against the right edge and the second (ʿajuz) on the line below
 * against the left edge, both at their natural width. Free verse is centred. Long poems scroll
 * in a ListView.
 */
Item {
    id: root

    required property var poem
    property real fontPx: 34
    property string family: "Amiri"
    property bool saved: false
    /// Whether the diacritics are shown
    property bool tashkeel: true
    /// The picked verse, or -1, and the saved verses as "slug:index" in a comma list
    property int selected: -1
    property string savedVerses: ""

    signal openPoem(string slug)
    signal openList(string label, var base)
    signal openPoet(string slug, string name)
    signal verseClicked(int index)

    /// The verses as drawn: with or without the diacritics
    readonly property var verses: Core.shown(root.poem?.verses ?? [], root.tashkeel)
    readonly property bool metric: Core.isMetric(root.poem?.verses ?? [])
    readonly property var savedIdx: Core.savedIndexes(root.savedVerses, root.poem?.slug ?? "")
    readonly property real sideMargin: root.width < 900 ? 36 : 112
    readonly property real contentW: Math.min(root.width - root.sideMargin, 1040)
    readonly property real gutter: Math.max(44, root.fontPx * 1.7)
    readonly property real colW: (root.contentW - root.gutter) / 2

    /// Width of the longest half-line per pixel of type, from a few measured candidates
    property real perPx: 0
    readonly property real fitPx: root.perPx > 0 ? root.colW * 0.985 / root.perPx : root.fontPx
    readonly property real minPx: Math.min(root.fontPx, 24)
    readonly property bool stacked: root.metric
    readonly property real stackedPx: root.perPx > 0 ? Math.min(root.fontPx, root.contentW * 0.8 / root.perPx) : root.fontPx
    /// Each half-line's slot is as wide as the longest one, so every verse shares one straight
    /// gutter instead of floating in a roomy column
    readonly property real slot: root.perPx > 0 ? Math.min(root.colW, root.perPx * root.size * 1.03) : root.colW
    readonly property real size: root.metric ? (root.stacked ? root.stackedPx : Math.min(root.fontPx, root.fitPx))
        : Math.min(root.fontPx, root.contentW * 0.86 / Math.max(root.perPx, 0.01))

    function remeasure(): void {
        let widest = 0;
        for (let i = 0; i < ruler.count; i++)
            widest = Math.max(widest, ruler.itemAt(i)?.implicitWidth ?? 0);
        root.perPx = widest / 40;
    }

    // positionViewAtBeginning() lands on the first verse, below the title block
    function toTop(): void {
        list.contentY = list.originY - list.topMargin;
    }
    /// Scroll a verse to the middle of the view (the poem has just arrived or changed)
    function focusVerse(index: int): void {
        Qt.callLater(() => list.positionViewAtIndex(index, ListView.Center));
    }
    onPoemChanged: Qt.callLater(root.toTop)
    Component.onCompleted: Qt.callLater(root.toTop)

    /// Keyboard scrolling: move by `dy` pixels (or to an end with ±Infinity), gliding
    function scrollBy(dy: real): void {
        const top = list.originY - list.topMargin;
        const bottom = Math.max(top, list.originY + list.contentHeight - list.height + list.bottomMargin);
        glide.stop();
        glide.to = Math.max(top, Math.min(bottom, list.contentY + dy));
        glide.start();
    }
    NumberAnimation {
        id: glide
        target: list
        property: "contentY"
        duration: Appearance.dur(220)
        easing.type: Easing.OutCubic
    }

    // Hidden rulers: the longest few half-lines at a reference size
    Repeater {
        id: ruler
        model: Core.widest(root.verses, 30)
        onItemAdded: root.remeasure()
        onItemRemoved: root.remeasure()
        delegate: Text {
            required property string modelData
            visible: false
            text: modelData
            font.family: root.family
            font.pixelSize: 40
            wrapMode: Text.NoWrap
            onImplicitWidthChanged: root.remeasure()
        }
    }

    ListView {
        id: list
        WheelScroll {}
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 1200
        model: root.verses
        header: headerBlock
        footer: footerBlock

        delegate: Item {
            id: verse
            required property int index
            required property var modelData
            readonly property bool paired: root.metric && modelData.length >= 2
            readonly property real px: root.size

            width: ListView.view.width
            height: body.height + verse.px * (root.metric ? 1.05 : 0.4)

            // A picked verse is lit, and a saved one wears a small bookmark in the margin
            Rectangle {
                x: body.x - 16
                y: -verse.px * 0.08
                width: root.contentW + 32
                height: body.height + verse.px * 0.16
                radius: 18
                color: root.selected === verse.index ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.16)
                    : verseArea.containsMouse ? Qt.rgba(Appearance.colors.colOnLayer0.r, Appearance.colors.colOnLayer0.g, Appearance.colors.colOnLayer0.b, 0.05) : "transparent"
                Behavior on color { ColorAnimation { duration: Appearance.dur(120) } }
            }
            MaterialSymbol {
                visible: root.savedIdx[verse.index] === true
                x: body.x - 14
                y: 2
                text: "bookmark"
                fill: 1
                iconSize: 18
                color: Appearance.colors.colPrimary
            }
            MouseArea {
                id: verseArea
                x: body.x - 16
                width: root.contentW + 32
                height: parent.height
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.verseClicked(verse.index)
            }

            Item {
                id: body
                x: (parent.width - root.contentW) / 2
                width: root.contentW
                height: verse.paired && root.stacked ? first.height + second.height - verse.px * 0.35
                    : Math.max(first.implicitHeight, second.visible ? second.implicitHeight : 0)

                DiwanHalf {
                    id: first
                    size: verse.px
                    family: root.family
                    text: verse.paired ? verse.modelData[0] : verse.modelData.join("   ")
                    slot: verse.paired ? (root.stacked ? root.contentW * 0.9 : root.slot) : root.contentW * 0.86
                    x: !verse.paired ? (root.contentW - slot) / 2 : root.stacked ? root.contentW - slot : (root.contentW + root.gutter) / 2
                    justify: verse.paired && !root.stacked
                    fit: verse.paired && !root.stacked
                    horizontalAlignment: verse.paired && root.stacked ? Text.AlignRight : Text.AlignHCenter
                }
                DiwanHalf {
                    id: second
                    visible: verse.paired
                    size: verse.px
                    family: root.family
                    text: verse.paired ? verse.modelData[1] : ""
                    slot: first.slot
                    x: root.stacked ? 0 : (root.contentW - root.gutter) / 2 - slot
                    y: root.stacked ? first.height - verse.px * 0.35 : 0
                    justify: !root.stacked
                    fit: !root.stacked
                    horizontalAlignment: root.stacked ? Text.AlignLeft : Text.AlignHCenter
                }
                // A ringed number in the margin every fifth verse, as editions mark them
                Rectangle {
                    visible: root.metric && (verse.index + 1) % 5 === 0
                    x: first.x + first.width + 16
                    y: first.height / 2 - height / 2
                    width: Math.max(30, verse.px * 0.95)
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    Text {
                        anchors.centerIn: parent
                        text: Core.digits(verse.index + 1)
                        font.family: root.family
                        font.pixelSize: Math.max(14, verse.px * 0.55)
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }

    Component {
        id: headerBlock
        ColumnLayout {
            width: list.width
            spacing: 0

            Item { Layout.preferredHeight: 28 }
            DiwanOrnament { Layout.alignment: Qt.AlignHCenter }
            Item { Layout.preferredHeight: 20 }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(root.contentW * 0.9, implicitWidth)
                text: root.poem?.title ?? ""
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                lineHeight: 1.35
                lineHeightMode: Text.ProportionalHeight
                color: Appearance.colors.colOnLayer0
                font.family: root.family
                font.pixelSize: Math.min(root.fontPx * 1.6, 66)
            }
            Item { Layout.preferredHeight: 8 }

            Text {
                id: poetLine
                Layout.alignment: Qt.AlignHCenter
                visible: text.length > 0
                text: root.poem?.poet ?? ""
                color: poetArea.containsMouse ? Appearance.colors.colOnLayer0 : Appearance.colors.colPrimary
                font.family: root.family
                font.pixelSize: Math.max(20, root.fontPx * 0.72)
                MouseArea {
                    id: poetArea
                    anchors.fill: parent
                    enabled: (root.poem?.poetSlug ?? "") !== ""
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openPoet(root.poem.poetSlug, root.poem.poet)
                }
            }
            Item { Layout.preferredHeight: 16 }

            Flow {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(root.contentW, implicitWidth)
                spacing: 8
                layoutDirection: Qt.RightToLeft
                DiwanChip {
                    visible: (root.poem?.era ?? "") !== ""
                    text: root.poem?.era ?? ""
                    clickable: (root.poem?.eraSlug ?? "") !== ""
                    onClicked: root.openList(root.poem.era, ["list", "--era", root.poem.eraSlug])
                }
                DiwanChip {
                    visible: (root.poem?.meter ?? "") !== "" && root.poem.meter !== "غير معروف"
                    text: root.poem?.meter ?? ""
                    clickable: (root.poem?.meterSlug ?? "") !== ""
                    onClicked: root.openList(root.poem.meter, ["list", "--meter", root.poem.meterSlug])
                }
                DiwanChip {
                    visible: (root.poem?.rhyme ?? "") !== "" && root.poem.rhyme !== "غير معروف"
                    text: "القافية: " + (root.poem?.rhyme ?? "")
                }
                DiwanChip {
                    visible: (root.poem?.theme ?? "") !== "" && root.poem.theme !== "غير معروف"
                    text: root.poem?.theme ?? ""
                }
                DiwanChip {
                    visible: root.verses.length > 0
                    text: Core.verseCount(root.verses.length, root.metric)
                }
            }

            Item { Layout.preferredHeight: 26 }
            DiwanOrnament { Layout.alignment: Qt.AlignHCenter; span: 180; opacity: 0.7 }
            Item { Layout.preferredHeight: 40 }
        }
    }

    Component {
        id: footerBlock
        ColumnLayout {
            id: footer
            width: list.width
            spacing: 0

            Item { Layout.preferredHeight: 28 }
            DiwanOrnament { Layout.alignment: Qt.AlignHCenter }
            Item { Layout.preferredHeight: 36 }

            // Previous sits on the right, as pages turn in an Arabic book
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                Layout.maximumWidth: 760
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                layoutDirection: Qt.RightToLeft
                spacing: 14
                Repeater {
                    model: [
                        { key: "prev", icon: "arrow_forward", caption: "السابقة" },
                        { key: "next", icon: "arrow_back", caption: "التالية" }
                    ]
                    delegate: Rectangle {
                        id: nav
                        required property var modelData
                        readonly property var target: root.poem ? root.poem[nav.modelData.key] : null
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        visible: nav.target !== null && nav.target !== undefined
                        implicitHeight: 76
                        radius: Appearance.rounding.full
                        color: navArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                        Behavior on color { ColorAnimation { duration: Appearance.dur(120) } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            layoutDirection: Qt.RightToLeft
                            spacing: 12
                            MaterialSymbol { text: nav.modelData.icon; iconSize: 22; color: Appearance.colors.colPrimary }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                StyledText {
                                    Layout.fillWidth: true
                                    text: nav.modelData.caption
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    horizontalAlignment: Text.AlignRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: nav.target?.title ?? ""
                                    elide: Text.ElideLeft
                                    horizontalAlignment: Text.AlignRight
                                    font.family: root.family
                                    font.pixelSize: Appearance.font.pixelSize.huge
                                    color: Appearance.colors.colOnLayer0
                                }
                            }
                        }
                        MouseArea {
                            id: navArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openPoem(nav.target.slug)
                        }
                    }
                }
            }

            // More from the same poet or the same era
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                Layout.maximumWidth: 760
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Layout.topMargin: 36
                visible: (root.poem?.related ?? []).length > 0
                spacing: 8
                StyledText {
                    Layout.fillWidth: true
                    text: "قد يعجبك أيضًا"
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    horizontalAlignment: Text.AlignRight
                }
                Repeater {
                    model: root.poem?.related ?? []
                    delegate: Rectangle {
                        id: rel
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: relCol.implicitHeight + 24
                        radius: Appearance.rounding.small
                        color: relArea.containsMouse ? Appearance.colors.colLayer2 : "transparent"
                        Behavior on color { ColorAnimation { duration: Appearance.dur(120) } }
                        ColumnLayout {
                            id: relCol
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: rel.modelData.title
                                elide: Text.ElideLeft
                                horizontalAlignment: Text.AlignRight
                                font.family: root.family
                                font.pixelSize: Appearance.font.pixelSize.huge
                                color: Appearance.colors.colOnLayer0
                            }
                            Text {
                                Layout.fillWidth: true
                                text: [rel.modelData.poet, rel.modelData.era].filter(s => s).join("  ·  ")
                                horizontalAlignment: Text.AlignRight
                                font.family: root.family
                                font.pixelSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colSubtext
                            }
                        }
                        MouseArea {
                            id: relArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openPoem(rel.modelData.slug)
                        }
                    }
                }
            }
            Item { Layout.preferredHeight: 60 }
        }
    }
}
