pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets
import "../../../quran/QuranCore.js" as Core
import "../../../quran/QuranText.js" as Verses

/*
 * Ayah card. Idle it shows an ayah of the day (one pick per date, an ayah of a readable length)
 * in the Hafs font with its translation; while the Quran player recites it follows the recitation
 * instead, the word being said lit in the accent colour, with play/pause and next-ayah on the card.
 * A tap on the text opens the reader at that ayah.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "quran_ayah"

    // One card in four shapes: a strip (one line and play), a tile (the surah and play), the
    // wide card (ayah, translation, controls) and the big card (the same with room to read).
    supportedSizes: ["2x0.5", "1x1", "2x1", "2x2"]
    defaultSize: "2x1"
    readonly property bool strip: root.sizeClass === "2x0.5"
    readonly property bool tile: root.sizeClass === "1x1"
    readonly property bool tall: root.sizeClass === "2x2"

    readonly property real padding: root.tile ? 18 : 26
    readonly property color textColor: root.cardScheme.textColorOnBg
    readonly property color subtextColor: root.cardScheme.subtextColorOnBg
    readonly property color accentColor: root.cardScheme.accentColor
    readonly property color faint: ColorUtils.applyAlpha(root.textColor, 0.10)
    readonly property string family: hafs.name !== "" ? hafs.name : "serif"

    FontLoader { id: hafs; source: Qt.resolvedUrl("../../../../../assets/quran/quran-hafs.ttf") }

    // ── data: the reader's shared libraries, loaded here when the reader has not yet ──
    property int rev: 0
    FileView { id: fManifest16; path: Quickshell.shellPath("assets/quran/manifest-16.json"); blockLoading: true }
    FileView { id: fManifest24; path: Quickshell.shellPath("assets/quran/manifest-24.json"); blockLoading: true }
    FileView { id: fUnified; path: Quickshell.shellPath("assets/quran/mushaf-unified.json"); blockLoading: true }
    FileView { id: fChapters; path: Quickshell.shellPath("assets/quran/chapters.json"); blockLoading: true }
    FileView { id: fTr; path: Quickshell.shellPath("assets/quran/tr-20.json"); blockLoading: true }

    function loadData(): void {
        try {
            if (!Core.isReady())
                Core.setData(fManifest16.text(), fManifest24.text(), fUnified.text());
            if (!Verses.chapter(1))
                Verses.setChapters(fChapters.text());
            if (!Verses.hasTranslation())
                Verses.setTranslation(fTr.text(), "Saheeh International");
        } catch (e) {
            console.log("[QuranAyahWidget] data load failed: " + e);
        }
        root.rev++;
    }
    Component.onCompleted: Qt.callLater(root.loadData)

    // ── what is shown ──
    readonly property var q: GlobalStates.quranPlayer
    readonly property bool live: (root.q?.active ?? false) && (root.q?.currentKey ?? "") !== ""
    readonly property string todayKey: Qt.formatDate(DateTime.clock.date, "yyyy-MM-dd")
    readonly property var daily: { root.rev; root.todayKey; return root.pickDaily(); }
    readonly property var shown: {
        if (root.live) {
            const p = root.q.currentKey.split(":");
            return { s: +p[0], a: +p[1] };
        }
        return root.daily;
    }
    readonly property int surah: root.shown ? (root.shown.s || 0) : 0
    readonly property int ayah: root.shown ? (root.shown.a || 0) : 0

    readonly property var liveWords: {
        const e = root.q?.entry;
        return root.live && e && e.surah === root.surah && e.wordText[root.ayah] ? e.wordText[root.ayah] : [];
    }
    readonly property string plain: { root.rev; return root.surah > 0 ? Core.ayahText(root.surah, root.ayah) : ""; }
    readonly property string richText: {
        if (root.liveWords.length === 0)
            return root.plain;
        // The scheme's own accent is too close to the text colour on a secondary-container card to
        // show which word is being said: the others dim, the recited one takes the tertiary colour
        const on = root.q.apiWordPos;
        if (!root.q.playing || on < 1)
            return root.liveWords.join(" ");
        const hi = String(Appearance.colors.colTertiary);
        const dim = String(ColorUtils.mix(root.textColor, root.cardScheme.cardBgColor, 0.55));
        return root.liveWords.map((w, i) => `<span style="color:${i + 1 === on ? hi : dim}">${w}</span>`).join(" ");
    }
    readonly property string translation: { root.rev; return root.surah > 0 && Verses.hasTranslation() ? (Verses.translationFor(root.surah, root.ayah) ?? "") : ""; }
    readonly property string surahNameAr: root.surah > 0 ? Core.SURAH_NAMES_AR[root.surah] : ""
    readonly property var reciter: Core.RECITATIONS.find(r => r.code === Config.options.quran.recitation)

    /// One ayah per date: a hashed start, then the first one of a readable length
    function pickDaily(): var {
        if (!Core.isReady())
            return null;
        const day = Math.floor(DateTime.clock.date.getTime() / 86400000);
        const total = 6236;
        const start = (day * 2654435761) % total;
        for (let k = 0; k < total; k++) {
            let f = (start + k) % total;
            let s = 1;
            while (s <= 114 && f >= Core.ayahCount(s)) {
                f -= Core.ayahCount(s);
                s++;
            }
            const n = Core.ayahText(s, f + 1).split(" ").length;
            if (n >= 7 && n <= 40)
                return { s: s, a: f + 1 };
        }
        return { s: 1, a: 1 };
    }

    function playOrPause(): void {
        if (!root.q || root.surah === 0)
            return;
        if (root.live)
            root.q.toggle();
        else
            root.q.playFrom(root.surah, root.ayah);
    }

    onCardTapped: {
        if (root.surah > 0)
            GlobalStates.quranPendingKey = root.surah + ":" + root.ayah;
        GlobalStates.openQuranApp();
    }

    cursorShape: root.editModeActive ? Qt.ArrowCursor : Qt.PointingHandCursor

    // The accent hairline across the top, fading out to both sides
    Rectangle {
        parent: root.contentItem
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        width: parent.width * 0.5
        height: 2
        radius: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.5; color: root.accentColor }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    // Caption: the occasion on the right, the ayah's number on the left
    RowLayout {
        visible: !root.strip
        x: root.padding
        y: root.tile ? 14 : 16
        width: root.designWidth - root.padding * 2
        layoutDirection: Qt.RightToLeft
        spacing: 8

        MaterialSymbol {
            text: root.live ? "graphic_eq" : "menu_book"
            iconSize: Appearance.font.pixelSize.larger
            fill: 1
            color: root.accentColor
        }
        Text {
            text: root.live ? (root.q.playing ? "تُتلى الآن" : "متوقفة مؤقتًا") : "آية اليوم"
            font.family: root.family
            font.pixelSize: 21
            color: root.accentColor
        }
        Item { Layout.fillWidth: true }
        Rectangle {
            visible: root.ayah > 0 && !root.tile
            implicitWidth: numberText.implicitWidth + 22
            implicitHeight: 24
            radius: root.pill(height)
            color: root.faint
            Text {
                id: numberText
                anchors.centerIn: parent
                text: "الآية " + Core.toArabicDigits(root.ayah)
                font.family: root.family
                font.pixelSize: 16
                color: root.subtextColor
            }
        }
    }

    // The ayah, as large as fits
    // Hafs lines are tall (diacritics) and Text.Fit only looks at the layout box, so the size is
    // chosen here: the largest one whose wrapped lines, at a fixed pitch, fit the slot
    readonly property real translationH: root.tall ? 120 : 32
    readonly property real footerY: root.designHeight - 54
    readonly property real translationY: root.footerY - 6 - root.translationH - 2
    readonly property real ayahSlotH: root.translationY - 4 - 46
    readonly property real ayahSize: {
        const n = Math.max(1, root.plain.split(" ").length);
        const w = root.designWidth - root.padding * 2;
        for (let s = root.tall ? 44 : 32; s > 15; s--) {
            const lines = Math.ceil(n * 2.3 * s / w);
            if (lines * s * 1.7 <= root.ayahSlotH)
                return s;
        }
        return 15;
    }

    Text {
        id: ayahText
        visible: !root.strip && !root.tile
        x: root.padding
        y: 46
        width: root.designWidth - root.padding * 2
        height: root.ayahSlotH
        clip: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.RichText
        wrapMode: Text.Wrap
        font.family: root.family
        font.pixelSize: root.ayahSize
        lineHeightMode: Text.FixedHeight
        lineHeight: root.ayahSize * 1.7
        color: root.textColor
        text: root.richText !== "" ? root.richText : "جارٍ التحميل…"
        opacity: root.richText !== "" ? 1 : 0.5
    }

    Text {
        x: root.padding + 6
        y: root.translationY
        width: root.designWidth - (root.padding + 6) * 2
        height: root.translationH
        visible: root.translation !== "" && !root.strip && !root.tile
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.Wrap
        maximumLineCount: root.tall ? 6 : 2
        elide: Text.ElideRight
        text: root.translation
        font.pixelSize: root.tall ? 15 : 13
        color: root.subtextColor
    }

    Rectangle {
        visible: !root.strip && !root.tile
        x: root.padding
        y: root.footerY - 6
        width: root.designWidth - root.padding * 2
        height: 1
        color: root.faint
    }

    // Footer: surah and reciter on the right, the controls on the left
    RowLayout {
        visible: !root.strip
        x: root.padding
        y: root.footerY
        width: root.designWidth - root.padding * 2
        height: 38
        spacing: 8

        WidgetButton {
            Layout.fillWidth: root.tile && !root.live
            Layout.preferredWidth: root.tile && !root.live ? -1 : (root.live ? 100 : 118)
            Layout.preferredHeight: 38
            symbol: root.live && root.q.playing ? "pause" : "play_arrow"
            symbolSize: 20
            label: root.live ? (root.q.playing ? "إيقاف" : "متابعة") : "استماع"
            labelSize: 15
            colFill: root.accentColor
            colContent: root.cardScheme.onAccentColor
            onClicked: root.playOrPause()
        }
        WidgetButton {
            visible: root.live
            Layout.preferredWidth: 38
            Layout.preferredHeight: 38
            symbol: "skip_next"
            symbolSize: 20
            colFill: root.cardScheme.pillBgColor
            colContent: root.cardScheme.textColorOnBg
            onClicked: root.q.step(1)
        }
        Item { Layout.fillWidth: !root.tile || root.live }
        // One line, so nothing hangs below the card: the surah, then the reciter
        RowLayout {
            visible: !root.tile
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: root.designWidth * 0.5
            layoutDirection: Qt.RightToLeft
            spacing: 8
            Text {
                text: root.surahNameAr !== "" ? "سورة " + root.surahNameAr : ""
                font.family: root.family
                font.pixelSize: 21
                color: root.textColor
            }
            Text {
                Layout.fillWidth: true
                visible: root.live && !!root.reciter
                text: root.reciter?.nameAr ?? ""
                font.family: root.family
                font.pixelSize: 15
                color: root.subtextColor
                elide: Text.ElideLeft
            }
        }
    }

    // Tile: the surah's name and the ayah's number, with play below
    ColumnLayout {
        visible: root.tile
        x: root.padding
        y: 52
        width: root.designWidth - root.padding * 2
        height: root.footerY - 52 - 6
        spacing: 4
        Item { Layout.fillHeight: true }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.surahNameAr !== "" ? "سورة " + root.surahNameAr : ""
            font.family: root.family
            font.pixelSize: 34
            color: root.textColor
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: root.ayah > 0
            text: "الآية " + Core.toArabicDigits(root.ayah)
            font.family: root.family
            font.pixelSize: 18
            color: root.subtextColor
        }
        Item { Layout.fillHeight: true }
    }

    // Strip: the surah, the start of the ayah on one line, and play
    RowLayout {
        visible: root.strip
        x: root.padding
        y: (root.designHeight - 44) / 2
        width: root.designWidth - root.padding * 2
        height: 44
        layoutDirection: Qt.RightToLeft
        spacing: 12
        Text {
            text: root.surahNameAr !== "" ? root.surahNameAr + " " + Core.toArabicDigits(root.ayah) : ""
            font.family: root.family
            font.pixelSize: 20
            color: root.accentColor
        }
        Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            maximumLineCount: 1
            text: root.plain
            font.family: root.family
            font.pixelSize: 22
            color: root.textColor
        }
        WidgetButton {
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
            symbol: root.live && root.q.playing ? "pause" : "play_arrow"
            symbolSize: 22
            colFill: root.accentColor
            colContent: root.cardScheme.onAccentColor
            onClicked: root.playOrPause()
        }
    }
}
