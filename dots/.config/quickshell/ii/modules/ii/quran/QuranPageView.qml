pragma ComponentBehavior: Bound

import QtQuick

import qs.modules.common
import "QuranCore.js" as Core

/**
 * One Madina page: exactly 15 fixed-height lines on a paper sheet, scaled to fill the space it is
 * given. A justified line is stretched horizontally from its right edge by
 * min(stretch * stretchScale, lineWidth / measuredWidth); title and basmalah lines are centred.
 * Text is rendered as whole words so Arabic letter joining is never broken.
 */
Item {
    id: root

    /// Result of Core.buildPage
    property var pageModel: null
    property int fontSize: 25
    property string selectedKey: ""
    property string playingKey: ""
    /// "surah:ayah:wordIndex" of the word being recited
    property string activeWordKey: ""
    /// { "2:255": true }
    property var savedKeys: ({})
    /// Where the sheet sits in the space it is given: Qt.AlignLeft or Qt.AlignRight hug that
    /// edge (the gutter of a spread), anything else centres it
    property int sheetAlign: Qt.AlignHCenter

    signal ayahClicked(string key)
    signal ayahPlayRequested(string key)

    readonly property string fontFamily: quranFont.name
    /// The page is drawn in quran.com's per-page Madani font when its data is on disk
    readonly property bool qcfOn: pageModel !== null && pageModel.qcf === true
    readonly property bool qcfReady: root.qcfOn && pageFont.status === FontLoader.Ready
    readonly property real lineWidth: root.qcfOn ? root.fontSize * 18.6 : (pageModel ? pageModel.lineWidth : 410)
    // the two opening pages are set larger in a narrower column, as in the printed mushaf
    readonly property bool shortPage: pageModel !== null && pageModel.page <= 2
    readonly property real boost: shortPage && pageModel.page === 1 ? 1.2 : 1
    readonly property real span: qcfOn && shortPage ? lineWidth * 0.8 : lineWidth
    readonly property real lineHeight: fontSize * 1.7
    readonly property real frameWidth: lineWidth + 4
    readonly property real barHeight: fontSize * 1.05
    // short pages (the Fatihah, the start of the Baqarah) fill only the first lines: centre them in the frame
    readonly property int usedLines: {
        const ls = pageModel ? pageModel.lines : [];
        let last = 0;
        for (let i = 0; i < ls.length; i++)
            if (ls[i].kind !== "text" || (ls[i].parts && ls[i].parts.length > 0) || (ls[i].words && ls[i].words.length > 0))
                last = i + 1;
        return last;
    }
    readonly property real frameHeight: 15 * lineHeight + 8 + 2 * barHeight
    readonly property real fit: Math.max(0.1, Math.min(width / frameWidth, height / frameHeight))

    // The sheet follows the shell theme
    readonly property color ink: Appearance.colors.colOnLayer0
    readonly property color wordInk: Appearance.colors.colPrimary
    readonly property color gold: Appearance.colors.colPrimary

    FontLoader {
        id: quranFont
        source: Qt.resolvedUrl("../../../assets/quran/quran-hafs.ttf")
    }

    FontLoader {
        id: pageFont
        source: root.qcfOn ? root.pageModel.fontUrl : ""
    }

    // Advance of the original marker tokens, one per digit count
    TextMetrics { id: mark1; font.family: root.fontFamily; font.pixelSize: root.fontSize; text: "﴿١﴾" }
    TextMetrics { id: mark2; font.family: root.fontFamily; font.pixelSize: root.fontSize; text: "﴿١٢﴾" }
    TextMetrics { id: mark3; font.family: root.fontFamily; font.pixelSize: root.fontSize; text: "﴿١٢٣﴾" }
    function markWidthFor(digits: int): real {
        const m = digits <= 1 ? mark1 : digits === 2 ? mark2 : mark3;
        return m.advanceWidth > 0 ? m.advanceWidth : root.fontSize * 2.4;
    }

    Rectangle {
        id: paper
        width: root.frameWidth
        height: root.frameHeight
        anchors.verticalCenter: parent.verticalCenter
        readonly property real shownWidth: root.frameWidth * root.fit
        x: (root.sheetAlign === Qt.AlignLeft ? shownWidth / 2
            : root.sheetAlign === Qt.AlignRight ? root.width - shownWidth / 2
            : root.width / 2) - root.frameWidth / 2
        scale: root.fit
        color: "transparent"

        // Running header: the juz on the right, the surah on the left, like the printed book
        Text {
            visible: root.pageModel !== null
            anchors.right: parent.right
            anchors.rightMargin: 2
            y: 0
            height: root.barHeight
            verticalAlignment: Text.AlignVCenter
            text: root.pageModel ? "الجزء " + Core.toArabicDigits(root.pageModel.juz) : ""
            font.family: root.fontFamily
            font.pixelSize: root.fontSize * 0.7
            color: Qt.alpha(root.ink, 0.75)
            renderType: Text.QtRendering
        }
        Text {
            visible: root.pageModel !== null
            anchors.left: parent.left
            anchors.leftMargin: 2
            y: 0
            height: root.barHeight
            verticalAlignment: Text.AlignVCenter
            text: root.pageModel ? "سورة " + Core.SURAH_NAMES_AR[root.pageModel.surah] : ""
            font.family: root.fontFamily
            font.pixelSize: root.fontSize * 0.7
            color: Qt.alpha(root.ink, 0.75)
            renderType: Text.QtRendering
        }
        Text {
            visible: root.pageModel !== null
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            height: root.barHeight
            verticalAlignment: Text.AlignVCenter
            text: root.pageModel ? Core.toArabicDigits(root.pageModel.page) : ""
            font.family: root.fontFamily
            font.pixelSize: root.fontSize * 0.7
            color: Qt.alpha(root.ink, 0.75)
            renderType: Text.QtRendering
        }

        Column {
            x: 2
            y: 4 + root.barHeight + (root.qcfOn && root.usedLines > 0 && root.usedLines < 15 ? (15 - root.usedLines) * root.lineHeight / 2 : 0)
            width: root.lineWidth

            Repeater {
                model: root.pageModel ? root.pageModel.lines : []

                delegate: Item {
                    id: ln
                    required property var modelData
                    width: root.lineWidth
                    height: root.lineHeight

                    // Surah title frame (the Hafs-font pages, before the page data is on disk)
                    Loader {
                        anchors.fill: parent
                        active: ln.modelData.kind === "title"
                        sourceComponent: Component {
 Item {
 anchors.fill: parent

                            Rectangle {
                                width: root.span
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.topMargin: 2
                                anchors.bottomMargin: 2
                                radius: 6
                                color: Qt.alpha(root.gold, 0.1)
                                border.width: 1.5
                                border.color: Qt.alpha(root.gold, 0.5)
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    radius: 4
                                    color: "transparent"
                                    border.width: 0.8
                                    border.color: Qt.alpha(root.gold, 0.6)
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: ln.modelData.title
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize * 1.15
                                    color: root.ink
                                    renderType: Text.QtRendering
                                }
                            }

                        
 }
}
                    }

                    Loader {
                        anchors.fill: parent
                        active: ln.modelData.kind === "basmalah"
                        sourceComponent: Component {
 Item {
 anchors.fill: parent

                            Text {
                                anchors.centerIn: parent
                                text: ln.modelData.basmalah
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize * 1.2
                                color: root.gold
                                renderType: Text.QtRendering
                            }
                        
 }
}
                    }

                    // A line in the page's own font: whole words spread edge to edge like the printed page.
                    // One Text per word and nothing else: highlights, saved dots and clicks are drawn and
                    // resolved per line from the word widths, which keeps a page turn cheap.
                    Item {
                        id: ql
                        visible: qcfWords
                        width: root.lineWidth
                        height: parent.height
                        // Madani words once their font is loaded; until then (and without the fonts) the line is the Hafs one below
                        readonly property bool qcfWords: ln.modelData.kind === "text" && root.qcfReady && ln.modelData.words !== undefined
                        readonly property var words: qcfWords ? ln.modelData.words : []
                        property var widths: []
                        property real sum: 0
                        // quran.com spreads every nearly full line edge to edge, including the last line of a
                        // surah that the KFGQPC data marks as unjustified; short lines (under 85%) stay as set
                        readonly property bool justified: ln.modelData.stretch >= 0
                            || (ql.sum + root.fontSize * 0.3 * Math.max(0, ql.words.length - 1) >= root.span * 0.85)
                        property string hoverKey: ""
                        readonly property real gap: {
                            const n = ql.words.length;
                            if (!ql.justified || n < 2)
                                return root.fontSize * 0.3;
                            return Math.max(0, (root.span - ql.sum) / (n - 1));
                        }
                        readonly property real total: ql.sum + ql.gap * Math.max(0, ql.words.length - 1)
                        readonly property real shrink: ql.total > root.span + 0.5 ? root.span / ql.total : 1
                        // Where the row sits, and its right edge (the scale below is anchored there)
                        // The row scales from its right edge, so that edge sits on the line edge whatever the shrink
                        readonly property real rowX: !ql.justified
            ? (root.lineWidth + ql.total * ql.shrink) / 2 - ql.total   // short lines sit centred, as on quran.com
            : (root.lineWidth + root.span) / 2 - ql.total
                        readonly property real rightEdge: ql.rowX + ql.total

                        function recalc(): void {
                            const w = [];
                            let t = 0;
                            for (let i = 0; i < wordRep.count; i++) {
                                const it = wordRep.itemAt(i);
                                const x = it ? it.implicitWidth : 0;
                                w.push(x);
                                t += x;
                            }
                            ql.widths = w;
                            ql.sum = t;
                        }

                        /// The word under a point of the line, by distance from the right edge
                        function wordAt(x: real): int {
                            const d = (ql.rightEdge - x) / ql.shrink;
                            if (d < -ql.gap)
                                return -1;
                            let acc = 0;
                            for (let i = 0; i < ql.widths.length; i++) {
                                acc += ql.widths[i] + ql.gap;
                                if (d < acc)
                                    return i;
                            }
                            return -1;
                        }

                        // Runs of words to tint, in row coordinates measured from the row's left edge
                        readonly property var marks: {
                            const play = root.playingKey, sel = root.selectedKey, hov = ql.hoverKey, act = root.activeWordKey;
                            const ws = ql.widths, words = ql.words;
                            const out = [], dots = [];
                            if (ws.length !== words.length)
                                return { runs: out, dots: dots };
                            let right = ql.total;
                            let cur = null;
                            for (let i = 0; i < words.length; i++) {
                                const w = words[i];
                                const left = right - ws[i];
                                let kind = 0;
                                // the recited ayah is tinted; its current word only changes colour
                                if (w.key === play) kind = 3;
                                else if (w.key === sel) kind = 2;
                                else if (w.key === hov) kind = 1;
                                if (w.end && root.savedKeys[w.key] === true)
                                    dots.push((left + right) / 2);
                                if (kind !== 0) {
                                    if (cur && cur.kind === kind && cur.key === w.key) cur.left = left - ql.gap / 2;
                                    else {
                                        cur = { kind: kind, key: w.key, right: right + ql.gap / 2, left: left - ql.gap / 2 };
                                        out.push(cur);
                                    }
                                } else {
                                    cur = null;
                                }
                                right = left - ql.gap;
                            }
                            return { runs: out, dots: dots };
                        }

                        Item {
                            id: tint
                            x: ql.rowX
                            width: ql.total
                            height: parent.height
                            transform: Scale { origin.x: tint.width; xScale: ql.shrink }
                            Repeater {
                                model: ql.marks.runs
                                delegate: Rectangle {
                                    required property var modelData
                                    x: modelData.left
                                    width: modelData.right - modelData.left
                                    anchors.top: parent.top
                                    anchors.topMargin: 3
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 3
                                    radius: 5
                                    color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b,
                                        modelData.kind === 3 ? 0.25 : modelData.kind === 2 ? 0.2 : 0.12)
                                }
                            }
                            Repeater {
                                model: ql.marks.dots
                                delegate: Rectangle {
                                    required property real modelData
                                    x: modelData - 3
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 3
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: Appearance.colors.colPrimary
                                }
                            }
                        }

                        Row {
                            id: wordRow
                            layoutDirection: Qt.RightToLeft
                            spacing: ql.gap
                            height: parent.height
                            x: ql.rowX
                            transform: Scale { origin.x: wordRow.width; xScale: ql.shrink }

                            Repeater {
                                id: wordRep
                                model: ql.words
                                onItemAdded: ql.recalc()
                                delegate: Item {
                                    id: wordItem
                                    required property var modelData
                                    readonly property bool mark: modelData.marker === true
                                    height: root.lineHeight
                                    // The sajdah bar and similar overlay glyphs have no advance but are as wide as their word. Qt
                                    // counts that overhang as width, which spread the words of the line apart; quran.com lays
                                    // out by the font's advance. Only a clear overhang switches to it, so other words keep Qt's width.
                                    readonly property bool overhang: !mark && ql.qcfWords && label.implicitWidth - advance.advanceWidth > root.fontSize * 0.15
                                    implicitWidth: mark ? root.markWidthFor(modelData.digits.length) : overhang ? advance.advanceWidth : label.implicitWidth
                                    onImplicitWidthChanged: ql.recalc()

                                    TextMetrics {
                                        id: advance
                                        font.family: label.font.family
                                        font.pixelSize: label.font.pixelSize
                                        text: wordItem.modelData.code ?? ""
                                    }

                                    Text {
                                        id: label
                                        visible: !wordItem.mark
                                        anchors.verticalCenter: parent.verticalCenter
                                        // With an overhang the text is as wide as the word's advance and sits against its right edge, so the overlay lies over the word
                                        width: wordItem.overhang ? wordItem.implicitWidth : implicitWidth
                                        horizontalAlignment: wordItem.overhang ? Text.AlignRight : Text.AlignLeft
                                        text: wordItem.modelData.code
                                        textFormat: Text.PlainText
                                        font.family: ql.qcfWords ? pageFont.name : root.fontFamily
                                        font.pixelSize: root.fontSize * (ql.qcfWords ? root.boost : 1)
                                        color: wordItem.modelData.i >= 0 && root.activeWordKey === wordItem.modelData.key + ":" + wordItem.modelData.i ? root.wordInk : root.ink
                                        renderType: Text.QtRendering
                                    }
                                    // Hafs rosette: the token is wide, so it is drawn smaller around its centre.
                                    // Built only for a marker: its vector paths are costly to create.
                                    Loader {
                                        active: wordItem.mark
                                        anchors.verticalCenter: parent.verticalCenter
                                        sourceComponent: Component {
                                            AyahMark {
                                                digits: wordItem.modelData.digits
                                                markWidth: wordItem.implicitWidth
                                                fontFamily: root.fontFamily
                                                accentColor: root.gold
                                                accentStrength: 0.16
                                                inkColor: root.ink
                                                numberColor: root.ink
                                                scale: 0.6
                                                transformOrigin: Item.Center
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: ql.hoverKey !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                            function keyAt(x: real): string {
                                const i = ql.wordAt(x);
                                return i >= 0 ? ql.words[i].key : "";
                            }
                            onPositionChanged: mouse => ql.hoverKey = keyAt(mouse.x)
                            onExited: ql.hoverKey = ""
                            onClicked: mouse => {
                                const k = keyAt(mouse.x);
                                if (k !== "")
                                    root.ayahClicked(k);
                            }
                            onDoubleClicked: mouse => {
                                const k = keyAt(mouse.x);
                                if (k !== "")
                                    root.ayahPlayRequested(k);
                            }
                        }
                    }

                    // Text line: parts side by side, first part on the right
                    // Built only for a line the Madani font does not draw (it holds the Hafs rosettes)
                    Loader {
                        anchors.fill: parent
                        active: ln.modelData.kind === "text" && !(root.qcfOn && ln.modelData.words !== undefined)
                        sourceComponent: Component {
 Item {
 anchors.fill: parent

                            Item {
                                id: content
                                // The bundled Hafs font: whole ayahs side by side, each line stretched to the
                                // page's own width as the data records it. The Madani page fonts use the block above.
                                height: parent.height
                                width: partsRow.implicitWidth
                                readonly property real stretch: ln.modelData.stretch
                                readonly property real requested: stretch < 0 || !root.pageModel ? 1 : stretch * root.pageModel.stretchScale
                                readonly property real effective: stretch >= 0 && width > 0 && width * requested > root.lineWidth + 0.5
                                    ? root.lineWidth / width : requested
                                x: stretch < 0 ? (root.lineWidth - width) / 2 : root.lineWidth - width
                                transform: Scale {
                                    origin.x: content.width
                                    xScale: content.stretch < 0 ? 1 : content.effective
                                }

                                Row {
                                    id: partsRow
                                    layoutDirection: Qt.RightToLeft
                                    height: parent.height

                                    Repeater {
                                        model: ln.modelData.parts

                                        delegate: Rectangle {
                                            id: partBox
                                            required property var modelData
                                            readonly property string key: modelData.key
                                            /// Word by word only while this ayah is recited
                                            readonly property bool detailed: key !== "" && key === root.playingKey
                                            height: root.lineHeight
                                            width: tokens.implicitWidth
                                            radius: 4
                                            color: key !== "" && key === root.playingKey ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.28)
                                                : key !== "" && key === root.selectedKey ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.2)
                                                : partArea.containsMouse && key !== "" ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.12)
                                                : "transparent"

                                            Row {
                                                id: tokens
                                                layoutDirection: Qt.RightToLeft
                                                anchors.verticalCenter: parent.verticalCenter

                                                Repeater {
                                                    model: partBox.detailed ? partBox.modelData.tokens : partBox.modelData.segs

                                                    delegate: Item {
                                                        id: tk
                                                        required property var modelData
                                                        readonly property bool isMark: modelData.k === "m"
                                                        readonly property bool wordActive: modelData.k === "w" && partBox.key !== ""
                                                            && root.activeWordKey === partBox.key + ":" + modelData.i
                                                        width: isMark ? root.markWidthFor(modelData.v.length) : tokenLabel.implicitWidth
                                                        height: root.lineHeight

                                                        Rectangle {
                                                            visible: tk.wordActive
                                                            anchors.fill: parent
                                                            anchors.topMargin: 6
                                                            anchors.bottomMargin: 6
                                                            radius: 3
                                                            color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.5)
                                                        }
                                                        Text {
                                                            id: tokenLabel
                                                            visible: !tk.isMark
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: tk.isMark ? "" : tk.modelData.v
                                                            textFormat: Text.PlainText
                                                            font.family: root.fontFamily
                                                            font.pixelSize: root.fontSize
                                                            color: root.ink
                                                            renderType: Text.QtRendering
                                                        }
                                                        AyahMark {
                                                            visible: tk.isMark
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            digits: tk.isMark ? tk.modelData.v : ""
                                                            markWidth: tk.width
                                                            fontFamily: root.fontFamily
                                                            accentColor: root.gold
                                                            accentStrength: 0.16
                                                            inkColor: root.ink
                                                            numberColor: root.ink
                                                        }
                                                        // Saved-ayah dot under its rosette
                                                        Rectangle {
                                                            visible: tk.isMark && root.savedKeys[partBox.key] === true
                                                            anchors.horizontalCenter: parent.horizontalCenter
                                                            anchors.bottom: parent.bottom
                                                            anchors.bottomMargin: 3
                                                            width: 6
                                                            height: 6
                                                            radius: 3
                                                            color: Appearance.colors.colPrimary
                                                        }
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: partArea
                                                anchors.fill: parent
                                                enabled: partBox.key !== ""
                                                hoverEnabled: true
                                                cursorShape: partBox.key !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: root.ayahClicked(partBox.key)
                                                onDoubleClicked: root.ayahPlayRequested(partBox.key)
                                            }
                                        }
                                    }
                                }
                            }
                        
 }
}
                    }
                }
            }
        }
    }
}
