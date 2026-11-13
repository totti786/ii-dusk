pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "QuranCore.js" as Core
import "QuranText.js" as Verses

/**
 * The quran.com-style reading page: a surah banner, then every verse as a card with its
 * reference, actions, the Arabic and the translation underneath. One surah at a time, with
 * links to the neighbouring ones at the foot.
 */
Item {
    id: root

    property int surah: 1
    property var savedKeys: ({})
    property string playingKey: ""
    property string selectedKey: ""
    property int arabicSize: 36
    property int transSize: 17
    property bool showTranslation: true
    property string translationLabel: ""
    property bool translationRtl: false
    /// Bumped by the owner when the translation text arrives, so the cards redraw
    property int dataRevision: 0
    /// The chapter table is loaded (the JS library does not notify, so bindings key off this)
    property bool ready: false

    signal surahRequested(int surah)
    signal verseSelected(string key)
    signal playRequested(string key)
    signal bookmarkRequested(string key)
    signal copyRequested(string key)
    signal tafsirRequested(string key)
    /// The verse nearest the top of the page, reported once scrolling settles
    signal topVerseChanged(int surah, int ayah)

    readonly property var info: { root.ready; return Verses.chapter(root.surah); }
    readonly property int count: root.info ? root.info.count : 0
    readonly property string fontFamily: hafs.name !== "" ? hafs.name : "serif"
    readonly property real column: Math.min(root.width - 48, 860)

    FontLoader { id: hafs; source: Qt.resolvedUrl("../../../assets/quran/quran-hafs.ttf") }

    function goTo(s: int, a: int): void {
        if (s !== root.surah) {
            root.pendingAyah = a;
            root.surah = s;
            return;
        }
        root.scrollToVerse(a);
    }

    property int pendingAyah: 0
    function scrollToVerse(a: int): void {
        if (a <= 1 && root.pendingAyah <= 1) {
            list.contentY = list.originY;
            return;
        }
        list.positionViewAtIndex(Math.max(0, a - 1), ListView.Beginning);
        list.contentY -= 12;
    }

    function scrollBy(dy: real): void {
        list.flick(0, -dy * 6);
    }

    // The model is reassigned (which drops its binding), so also refill it whenever the verse count
    // changes: the chapter table can arrive after the surah is set, and the list stayed empty
    onCountChanged: {
        list.model = 0;
        list.model = root.count;
    }

    onSurahChanged: {
        list.model = 0;
        list.model = root.count;
        Qt.callLater(() => {
            if (root.pendingAyah > 1) root.scrollToVerse(root.pendingAyah);
            else list.contentY = list.originY;
            root.pendingAyah = 0;
        });
    }

    ListView {
        id: list
        TouchpadScrollHandler { flickable: list }
        anchors.fill: parent
        model: root.count
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 1600
        reuseItems: false
        spacing: 0
        flickDeceleration: 2600
        maximumFlickVelocity: 5200

        onContentYChanged: topTimer.restart()
        Timer {
            id: topTimer
            interval: 250
            onTriggered: {
                const i = list.indexAt(list.width / 2, list.contentY + 40);
                root.topVerseChanged(root.surah, i >= 0 ? i + 1 : 1);
            }
        }

        // ── the surah banner ──
        header: Item {
            width: list.width
            height: banner.implicitHeight + 44

            ColumnLayout {
                id: banner
                anchors.horizontalCenter: parent.horizontalCenter
                y: 28
                width: root.column
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: bannerCol.implicitHeight + 40
                    radius: Appearance.rounding.verylarge
                    color: Appearance.colors.colLayer1
                    ColumnLayout {
                        id: bannerCol
                        anchors.centerIn: parent
                        width: parent.width - 48
                        spacing: 6
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Core.SURAH_NAMES_AR[root.surah]
                            font.family: root.fontFamily
                            font.pixelSize: 46
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.surah + ". " + (root.info ? root.info.name : "")
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.info ? root.info.meaning : ""
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colSubtext
                        }
                        Flow {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 6
                            spacing: 8
                            Repeater {
                                model: root.info ? [
                                    root.info.place === "makkah" ? Translation.tr("Meccan") : Translation.tr("Medinan"),
                                    Translation.tr("%1 verses").arg(root.info.count),
                                    Translation.tr("Juz %1").arg(Core.juzNumberForPage(Core.surahStartPage(root.surah))),
                                    Translation.tr("Revelation order %1").arg(root.info.order)
                                ] : []
                                delegate: Rectangle {
                                    required property string modelData
                                    implicitWidth: chip.implicitWidth + 24
                                    implicitHeight: 28
                                    radius: Appearance.rounding.full
                                    color: Appearance.colors.colLayer2
                                    StyledText {
                                        id: chip
                                        anchors.centerIn: parent
                                        text: parent.modelData
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }
                        QuranPill {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 6
                            icon: "play_arrow"
                            text: Translation.tr("Listen")
                            onClicked: root.playRequested(root.surah + ":1")
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: 14
                    visible: root.info && root.info.bismillah
                    horizontalAlignment: Text.AlignHCenter
                    text: "بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ"
                    font.family: root.fontFamily
                    font.pixelSize: root.arabicSize + 2
                    color: Appearance.colors.colOnLayer0
                }
            }
        }

        // ── a verse ──
        delegate: Item {
            id: verse
            required property int index
            readonly property int ayah: verse.index + 1
            readonly property string key: root.surah + ":" + verse.ayah
            readonly property bool playing: root.playingKey === verse.key
            readonly property bool selected: root.selectedKey === verse.key
            readonly property bool saved: root.savedKeys[verse.key] === true
            readonly property string trText: { root.dataRevision; return Verses.translationFor(root.surah, verse.ayah); }
            width: list.width
            height: card.implicitHeight + 8

            Rectangle {
                id: card
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.column
                implicitHeight: col.implicitHeight + 36
                radius: Appearance.rounding.large
                color: verse.playing ? Qt.alpha(Appearance.colors.colPrimary, 0.12)
                    : verse.selected ? Qt.alpha(Appearance.colors.colPrimary, 0.07)
                    : hover.hovered ? Qt.alpha(Appearance.colors.colOnLayer0, 0.035) : "transparent"
                Behavior on color { ColorAnimation { duration: Appearance.dur(120) } }

                HoverHandler { id: hover }
                TapHandler { onTapped: root.verseSelected(verse.key) }

                ColumnLayout {
                    id: col
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Rectangle {
                            implicitWidth: ref.implicitWidth + 22
                            implicitHeight: 28
                            radius: Appearance.rounding.full
                            color: verse.playing ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                            StyledText {
                                id: ref
                                anchors.centerIn: parent
                                text: verse.key
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                color: verse.playing ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                            }
                        }
                        Item { Layout.fillWidth: true }
                        // Always there for the playing, selected or saved verse, otherwise on hover
                        RowLayout {
                            spacing: 0
                            opacity: hover.hovered || verse.selected || verse.playing || verse.saved ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Appearance.dur(120) } }
                            QuranButton { icon: verse.playing ? "graphic_eq" : "play_arrow"; active: verse.playing; onClicked: root.playRequested(verse.key) }
                            QuranButton { icon: "content_copy"; onClicked: root.copyRequested(verse.key) }
                            QuranButton { icon: "menu_book"; onClicked: root.tafsirRequested(verse.key) }
                            QuranButton { icon: "bookmark"; active: verse.saved; onClicked: root.bookmarkRequested(verse.key) }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        wrapMode: Text.Wrap
                        text: Core.ayahText(root.surah, verse.ayah) + " ﴿" + Core.toArabicDigits(verse.ayah) + "﴾"
                        font.family: root.fontFamily
                        font.pixelSize: root.arabicSize
                        lineHeight: 1.3
                        color: Appearance.colors.colOnLayer0
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.showTranslation && verse.trText !== ""
                        horizontalAlignment: root.translationRtl ? Text.AlignRight : Text.AlignLeft
                        wrapMode: Text.Wrap
                        text: verse.trText
                        font.pixelSize: root.transSize
                        lineHeight: 1.35
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.88
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: root.showTranslation && verse.trText !== "" && verse.ayah === 1
                        text: "— " + root.translationLabel
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 36
                    height: 1
                    color: Qt.alpha(Appearance.colors.colOnLayer0, 0.08)
                    visible: !verse.playing && !verse.selected
                }
            }
        }

        // ── neighbouring surahs ──
        footer: Item {
            width: list.width
            height: 110
            RowLayout {
                anchors.centerIn: parent
                width: root.column
                spacing: 12
                QuranPill {
                    Layout.fillWidth: true
                    visible: root.surah > 1
                    icon: "chevron_left"
                    text: { root.ready; return Translation.tr("Previous: %1").arg(Verses.chapter(root.surah - 1) ? Verses.chapter(root.surah - 1).name : ""); }
                    onClicked: root.surahRequested(root.surah - 1)
                }
                QuranPill {
                    Layout.fillWidth: true
                    visible: root.surah < 114
                    icon: "chevron_right"
                    text: { root.ready; return Translation.tr("Next: %1").arg(Verses.chapter(root.surah + 1) ? Verses.chapter(root.surah + 1).name : ""); }
                    onClicked: root.surahRequested(root.surah + 1)
                }
            }
        }
    }
}
