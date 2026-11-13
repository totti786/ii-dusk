pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../quran/QuranCore.js" as Core

/**
 * Media card for the Quran player: the ayah being recited with the word highlighted, progress
 * through the surah instead of through one ayah's audio, and ayah-level controls. State comes from
 * the running QuranPlayer (GlobalStates.quranPlayer); the MPRIS player is only the fallback.
 */
Item {
    id: root
    required property var player
    property real radius
    readonly property var q: GlobalStates.quranPlayer

    readonly property var parts: (q?.currentKey ?? "").split(":")
    readonly property int surah: parts.length === 2 ? +parts[0] : 0
    readonly property int ayah: parts.length === 2 ? +parts[1] : 0
    readonly property int ayahCount: q?.surahAyahCount ?? 0
    readonly property var reciter: Core.RECITATIONS.find(r => r.code === (q?.recitation ?? ""))
    readonly property var words: {
        const e = q?.entry;
        return e && e.surah === root.surah && e.wordText[root.ayah] ? e.wordText[root.ayah] : [];
    }
    readonly property string plainText: root.words.length > 0 ? "" : (Core.isReady() ? Core.ayahText(root.surah, root.ayah) : "")

    /// Inside the island: no surface of its own, tighter spacing
    property bool embedded: false
    readonly property int pad: embedded ? 10 : 14
    property real elevationMargin: embedded ? 0 : Appearance.sizes.elevationMargin
    implicitWidth: (embedded ? 420 : 470) + elevationMargin * 2
    implicitHeight: content.implicitHeight + pad * 2 + elevationMargin * 2

    FontLoader { id: hafs; source: Qt.resolvedUrl("../../../assets/quran/quran-hafs.ttf") }
    readonly property string fontFamily: hafs.name !== "" ? hafs.name : "serif"

    component IconButton: RippleButton {
        id: btn
        property string symbol
        property int size: 36
        property bool on: false
        implicitWidth: size
        implicitHeight: size
        buttonRadius: size / 2
        colBackground: on ? Appearance.colors.colSecondaryContainer : "transparent"
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        contentItem: MaterialSymbol {
            iconSize: btn.size * 0.62
            fill: btn.on ? 1 : 0
            horizontalAlignment: Text.AlignHCenter
            color: btn.on ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
            text: btn.symbol
        }
    }

    StyledRectangularShadow { target: background; visible: !root.embedded }
    Rectangle {
        id: background
        anchors.fill: parent
        anchors.margins: root.elevationMargin
        color: root.embedded ? "transparent" : Appearance.colors.colLayer0
        radius: root.radius
        clip: true

        // Faint rosette in the corner, in place of a blurred cover
        Image {
            visible: !root.embedded
            source: Qt.resolvedUrl("../../../assets/quran/cover.png")
            width: 170
            height: 170
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: -40
            anchors.topMargin: -40
            opacity: 0.08
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: root.pad
            spacing: root.embedded ? 5 : 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer0
                        elide: Text.ElideRight
                        text: root.surah > 0 ? "سورة " + Core.SURAH_NAMES_AR[root.surah] : "القرآن الكريم"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                        text: root.reciter ? root.reciter.nameAr : (root.q?.recitation ?? "")
                    }
                }
                StyledText {
                    visible: root.ayah > 0
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colPrimary
                    text: "الآية " + Core.toArabicDigits(root.ayah) + (root.ayahCount > 0 ? " / " + Core.toArabicDigits(root.ayahCount) : "")
                }
                IconButton {
                    symbol: "menu_book"
                    size: 32
                    downAction: () => {
                        if (root.ayah > 0)
                            GlobalStates.quranPendingKey = root.surah + ":" + root.ayah;
                        GlobalStates.openQuranApp();
                    }
                }
            }

            // The ayah, word by word; scrolls to keep the recited word in view
            Flickable {
                id: ayahView
                Layout.fillWidth: true
                Layout.preferredHeight: root.embedded ? 60 : 112
                contentWidth: width
                contentHeight: Math.max(ayahFlow.implicitHeight, height)
                clip: true
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds

                Behavior on contentY { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                function reveal() {
                    const it = wordRepeater.itemAt((root.q?.apiWordPos ?? 0) - 1);
                    const y = it ? it.y : 0;
                    contentY = Math.max(0, Math.min(contentHeight - height, y - height / 3));
                }
                Connections {
                    target: root.q
                    function onApiWordPosChanged() { ayahView.reveal(); }
                    function onCurrentKeyChanged() { ayahView.contentY = 0; }
                }

                Flow {
                    id: ayahFlow
                    width: ayahView.width
                    layoutDirection: Qt.RightToLeft
                    spacing: 7
                    // Centre short ayahs vertically
                    y: Math.max(0, (ayahView.height - implicitHeight) / 2)

                    Repeater {
                        id: wordRepeater
                        model: root.words
                        delegate: Text {
                            required property string modelData
                            required property int index
                            readonly property bool current: (root.q?.apiWordPos ?? -1) === index + 1 && (root.q?.playing ?? false)
                            text: modelData
                            font.family: root.fontFamily
                            font.pixelSize: root.embedded ? 22 : 27
                            color: current ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                            opacity: current || !(root.q?.playing ?? false) || (root.q?.apiWordPos ?? -1) < 1 ? 1 : 0.72
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }
                    }
                    Text {
                        visible: root.words.length === 0 && root.plainText !== ""
                        width: ayahFlow.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: root.plainText
                        font.family: root.fontFamily
                        font.pixelSize: root.embedded ? 22 : 27
                        color: Appearance.colors.colOnLayer0
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: root.words.length === 0 && root.plainText === ""
                    color: Appearance.colors.colSubtext
                    text: root.q?.error ? root.q.error : (root.q?.loading ? Translation.tr("Loading…") : "")
                }
            }

            // Progress through the surah: a tap jumps to that ayah
            Item {
                id: surahBar
                Layout.fillWidth: true
                implicitHeight: 14
                visible: root.ayahCount > 0

                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Appearance.colors.colSecondaryContainer
                    Rectangle {
                        // Right to left, like the text it follows
                        anchors.right: parent.right
                        height: parent.height
                        radius: parent.radius
                        width: root.ayahCount > 0 ? parent.width * root.ayah / root.ayahCount : 0
                        color: Appearance.colors.colPrimary
                        Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        const f = 1 - mouse.x / width;
                        root.q.playFrom(root.surah, Math.max(1, Math.min(root.ayahCount, Math.ceil(f * root.ayahCount))));
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                IconButton {
                    symbol: "repeat_one"
                    on: root.q?.repeatAyah ?? false
                    downAction: () => root.q.setRepeat(!root.q.repeatAyah)
                }
                IconButton {
                    id: speedPill
                    readonly property var steps: [0.75, 1, 1.25, 1.5, 2]
                    implicitWidth: 48
                    buttonRadius: height / 2
                    contentItem: StyledText {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer0
                        text: (root.q?.speed ?? 1) + "×"
                    }
                    downAction: () => {
                        const i = steps.indexOf(Config.options.quran.speed);
                        Config.options.quran.speed = steps[(i + 1) % steps.length];
                    }
                }
                Item { Layout.fillWidth: true }
                IconButton {
                    symbol: "skip_previous"
                    size: 40
                    downAction: () => root.q.step(-1)
                }
                RippleButton {
                    id: playButton
                    readonly property bool playing: root.q?.playing ?? false
                    implicitWidth: root.embedded ? 44 : 52
                    implicitHeight: implicitWidth
                    buttonRadius: playing ? Appearance.rounding.normal : implicitWidth / 2
                    colBackground: playing ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                    colBackgroundHover: playing ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
                    colRipple: playing ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive
                    downAction: () => root.q.toggle()
                    contentItem: MaterialSymbol {
                        iconSize: Appearance.font.pixelSize.huge
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: playButton.playing ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                        text: playButton.playing ? "pause" : "play_arrow"
                    }
                }
                IconButton {
                    symbol: "skip_next"
                    size: 40
                    downAction: () => root.q.step(1)
                }
                Item { Layout.fillWidth: true }
                IconButton {
                    symbol: "stop"
                    downAction: () => root.q.stop()
                }
                IconButton {
                    symbol: "keep"
                    size: 30
                    on: GlobalStates.mediaControlsPinned
                    downAction: () => GlobalStates.mediaControlsPinned = !GlobalStates.mediaControlsPinned
                }
            }
        }
    }
}
