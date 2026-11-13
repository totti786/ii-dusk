pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "QuranCore.js" as Core
import "QuranText.js" as Verses

/// Results under the search field: a jump when the query is "2:255", matching surahs, then
/// the verses that contain every word, by their Arabic or their translation.
Rectangle {
    id: root

    property string query: ""
    property int dataRevision: 0
    property string fontFamily: "serif"
    property int current: 0

    signal surahPicked(int surah)
    signal versePicked(int surah, int ayah)

    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    property var result: ({ jump: null, surahs: [], verses: [], total: 0, arabic: false, words: [] })
    // A search costs a few ms, so only the typing burst is debounced; the first character goes straight through
    function run(): void {
        debounce.stop();
        root.result = Verses.search(root.query, 40);
        root.current = 0;
    }
    Timer {
        id: debounce
        interval: 45
        onTriggered: root.run()
    }
    onQueryChanged: {
        if (root.query.trim().length <= 1) root.run();
        else debounce.restart();
    }
    onDataRevisionChanged: debounce.restart()

    /// Height the content needs, so a short result list does not sit in a tall empty box
    readonly property real wantedHeight: root.rows.length === 0 ? 84 : Math.min(list.contentHeight + 20, 560)

    // Flat rows: { kind: "jump"|"head"|"surah"|"verse", ... }
    readonly property var rows: {
        const out = [];
        const r = root.result;
        if (r.jump)
            out.push({ kind: "jump", s: r.jump.s, a: r.jump.a });
        if (r.surahs.length > 0) {
            out.push({ kind: "head", text: Translation.tr("Surahs") });
            for (const s of r.surahs.slice(0, 6))
                out.push({ kind: "surah", s: s });
        }
        if (r.verses.length > 0) {
            out.push({ kind: "head", text: r.total > r.verses.length
                ? Translation.tr("Verses · showing %1 of %2").arg(r.verses.length).arg(r.total)
                : Translation.tr("Verses · %1").arg(r.total) });
            for (const v of r.verses)
                out.push({ kind: "verse", s: v.s, a: v.a });
        }
        return out;
    }
    readonly property var pickable: root.rows.filter(x => x.kind !== "head")
    readonly property bool empty: root.query.trim() !== "" && root.rows.length === 0
    readonly property bool needTranslation: !/[ء-ي]/.test(root.query) && !Verses.hasTranslation()

    function move(d: int): void {
        if (root.pickable.length === 0) return;
        root.current = (root.current + d + root.pickable.length) % root.pickable.length;
        const target = root.pickable[root.current];
        const i = root.rows.indexOf(target);
        if (i >= 0) list.positionViewAtIndex(i, ListView.Contain);
    }

    function activate(): void {
        const r = root.pickable[root.current];
        if (r) root.pick(r);
    }

    function pick(r: var): void {
        if (r.kind === "surah") root.surahPicked(r.s);
        else root.versePicked(r.s, r.kind === "jump" || r.kind === "verse" ? r.a : 1);
    }

    ListView {
        id: list
        TouchpadScrollHandler { flickable: list }
        anchors.fill: parent
        anchors.margins: 8
        clip: true
        model: root.rows
        boundsBehavior: Flickable.StopAtBounds
        spacing: 2
        reuseItems: true
        cacheBuffer: 200

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool selectable: modelData.kind !== "head"
            readonly property bool active: selectable && root.pickable[root.current] === modelData
            width: list.width
            height: modelData.kind === "head" ? 34 : modelData.kind === "verse" ? verseCol.implicitHeight + 20 : 52

            StyledText {
                visible: row.modelData.kind === "head"
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                text: row.modelData.text ?? ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: Appearance.colors.colSubtext
            }

            Rectangle {
                visible: row.selectable
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: row.active ? Appearance.colors.colSecondaryContainer
                    : area.containsMouse ? Appearance.colors.colLayer2 : "transparent"

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pick(row.modelData)
                }

                // go to / surah
                RowLayout {
                    visible: row.modelData.kind === "jump" || row.modelData.kind === "surah"
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12
                    Rectangle {
                        implicitWidth: 32; implicitHeight: 32; radius: 16
                        color: Appearance.colors.colLayer2
                        StyledText {
                            anchors.centerIn: parent
                            text: row.modelData.kind === "jump" ? "↵" : String(row.modelData.s)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: row.modelData.kind === "jump"
                                ? Translation.tr("Go to %1:%2").arg(row.modelData.s).arg(row.modelData.a)
                                : (Verses.chapter(row.modelData.s)?.name ?? "")
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            text: row.modelData.kind === "jump"
                                ? (Verses.chapter(row.modelData.s)?.name ?? "")
                                : (Verses.chapter(row.modelData.s)?.meaning ?? "") + " · " + Translation.tr("%1 verses").arg(Verses.chapter(row.modelData.s)?.count ?? 0)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    StyledText {
                        text: row.modelData.s ? Core.SURAH_NAMES_AR[row.modelData.s] : ""
                        font.family: root.fontFamily
                        font.pixelSize: 22
                        color: Appearance.colors.colOnLayer0
                    }
                }

                // a verse
                ColumnLayout {
                    id: verseCol
                    visible: row.modelData.kind === "verse"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            text: (Verses.chapter(row.modelData.s)?.name ?? "") + " " + row.modelData.s + ":" + row.modelData.a
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.colors.colPrimary
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: row.modelData.kind === "verse"
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        text: row.modelData.kind === "verse" ? Core.ayahText(row.modelData.s, row.modelData.a) : ""
                        font.family: root.fontFamily
                        font.pixelSize: 22
                        color: Appearance.colors.colOnLayer0
                        renderType: Text.NativeRendering
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text !== ""
                        textFormat: Text.StyledText
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        text: row.modelData.kind === "verse" && Verses.hasTranslation()
                            ? Verses.highlightTranslation(Verses.translationFor(row.modelData.s, row.modelData.a), root.result.arabic ? [] : root.result.words, Appearance.colors.colPrimary.toString())
                            : ""
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        footer: Item { width: list.width; height: 6 }
    }

    StyledText {
        anchors.centerIn: parent
        visible: root.query.trim() === "" || root.empty || (root.needTranslation && root.rows.length === 0)
        width: parent.width - 48
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.query.trim() === "" ? Translation.tr("Search a surah, a word in Arabic or English, or jump with 2:255")
            : root.needTranslation ? Translation.tr("Loading the translation…")
            : Translation.tr("Nothing found for “%1”").arg(root.query.trim())
        color: Appearance.colors.colSubtext
    }
}
