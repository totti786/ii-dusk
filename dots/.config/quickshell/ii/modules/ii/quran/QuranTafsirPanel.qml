pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/// The commentary on one ayah. A surah of a tafsir is fetched the first time it is read and kept on disk;
/// many tafsirs comment on a run of ayahs under the first, so a verse shows the nearest commentary at or
/// before it and says which verses that text covers.
Rectangle {
    id: root

    property int surah: 1
    property int ayah: 1
    property int tafsirId: 169
    /// [[id, name, author, language]]
    property var tafsirs: []
    property string home: ""
    property int fontSize: 17
    /// "Surah name" for the header
    property string surahName: ""
    property bool canStepBack: true
    property bool canStepForward: true

    signal tafsirPicked(int id)
    signal stepRequested(int delta)
    signal fontSizeRequested(int size)
    signal closeRequested()

    radius: Appearance.rounding.verylarge
    // A sheet: square at the bottom edge it rises from
    color: Appearance.colors.colLayer1
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    MouseArea { anchors.fill: parent; onWheel: wheel => wheel.accepted = true }

    // ------------------------------------------------------------------ what is shown

    readonly property var rows: root.tafsirs.map(r => ({ id: r[0], name: r[1], author: r[2], lang: r[3] }))
    readonly property var current: root.rows.find(t => t.id === root.tafsirId) ?? null
    readonly property bool rtl: ["arabic", "urdu", "kurdish", "persian"].includes(root.current?.lang ?? "")

    /// "ayah" -> html, for the surah and tafsir on screen
    property var verses: ({})
    property string status: "loading"   // loading | ready | error

    /// The ayah that holds the text for this one, and the run it covers
    readonly property var entry: {
        const keys = Object.keys(root.verses).map(Number).sort((a, b) => a - b);
        let head = -1;
        for (const k of keys)
            if (k <= root.ayah)
                head = k;
        if (head < 0)
            return null;
        const next = keys.find(k => k > head);
        return { head: head, last: next !== undefined ? next - 1 : -1, text: root.verses[String(head)] };
    }
    readonly property string coverage: {
        const e = root.entry;
        if (!e || (e.head === e.last && e.last === root.ayah))
            return "";
        if (e.head === e.last)
            return "";
        return e.last < 0
            ? Translation.tr("Covers %1:%2 to the end of the surah").arg(root.surah).arg(e.head)
            : Translation.tr("Covers %1:%2 to %1:%3").arg(root.surah).arg(e.head).arg(e.last);
    }

    // ------------------------------------------------------------------ loading

    readonly property string file: root.home + "/tafsir/" + root.tafsirId + "/" + root.surah + ".json"

    FileView {
        id: fData
        // Nothing is read or fetched while the panel is closed
        path: root.visible ? root.file : ""
        onLoaded: {
            try {
                root.verses = JSON.parse(fData.text()).v ?? {};
                root.status = "ready";
            } catch (e) {
                root.status = "error";
            }
        }
        onLoadFailed: if (root.visible) root.fetch()
    }

    // The file of the previous surah must not linger under the next one's heading
    onFileChanged: {
        root.verses = ({});
        root.status = "loading";
    }

    Process {
        id: fetcher
        property string wanted: ""
        onExited: code => {
            watchdog.stop();
            if (fetcher.wanted !== root.file) {
                // The reader moved on while this was downloading: fetch the one on screen, unless it is already there
                if (root.status !== "ready")
                    root.fetch();
                return;
            }
            if (code === 0)
                fData.reload();
            else
                root.status = "error";
        }
    }

    // A download that never answers must end in a message and a retry, not in "downloading" for good
    Timer {
        id: watchdog
        interval: 60000
        onTriggered: {
            fetcher.running = false;
            root.status = "error";
        }
    }

    function fetch(): void {
        if (fetcher.running)
            return;
        root.status = "loading";
        fetcher.wanted = root.file;
        fetcher.command = ["python3", Quickshell.shellPath("scripts/quran/tafsir.py"), String(root.tafsirId), String(root.surah)];
        fetcher.running = true;
        watchdog.restart();
    }

    // ------------------------------------------------------------------ the list of tafsirs

    property bool picking: false
    onVisibleChanged: if (!visible) root.picking = false

    // ------------------------------------------------------------------ layout

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            QuranButton {
                visible: root.picking
                icon: "arrow_back"
                onClicked: root.picking = false
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.picking ? Translation.tr("Choose a tafsir") : Translation.tr("Tafsir · %1:%2").arg(root.surah).arg(root.ayah)
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: !root.picking && root.surahName !== ""
                    text: root.surahName
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            QuranButton {
                visible: !root.picking
                icon: "text_decrease"
                enabled: root.fontSize > 14
                onClicked: root.fontSizeRequested(Math.max(14, root.fontSize - 2))
            }
            StyledText {
                visible: !root.picking
                Layout.preferredWidth: 26
                horizontalAlignment: Text.AlignHCenter
                text: String(root.fontSize)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            QuranButton {
                visible: !root.picking
                icon: "text_increase"
                enabled: root.fontSize < 44
                onClicked: root.fontSizeRequested(Math.min(44, root.fontSize + 2))
            }
            QuranButton {
                visible: !root.picking
                icon: "chevron_left"
                enabled: root.canStepBack
                onClicked: root.stepRequested(-1)
            }
            QuranButton {
                visible: !root.picking
                icon: "chevron_right"
                enabled: root.canStepForward
                onClicked: root.stepRequested(1)
            }
            QuranButton {
                icon: "close"
                onClicked: root.closeRequested()
            }
        }

        // Which tafsir: opens the list
        Rectangle {
            Layout.fillWidth: true
            visible: !root.picking
            implicitHeight: 44
            radius: Appearance.rounding.large
            color: pickArea.containsMouse ? Appearance.colors.colLayer3 : Appearance.colors.colLayer2

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                spacing: 8
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.current ? root.current.name : Translation.tr("Tafsir")
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.current ? root.current.author : ""
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                MaterialSymbol {
                    text: "unfold_more"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                }
            }
            MouseArea {
                id: pickArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picking = true
            }
        }

        // ── The commentary
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.picking

            StyledFlickable {
                id: flick
                anchors.fill: parent
                visible: root.status === "ready" && root.entry !== null
                clip: true
                contentHeight: bodyColumn.implicitHeight + 8
                boundsBehavior: Flickable.StopAtBounds

                // Back to the top for each ayah
                Connections {
                    target: root
                    function onAyahChanged() { flick.contentY = 0; }
                    function onTafsirIdChanged() { flick.contentY = 0; }
                }

                ColumnLayout {
                    id: bodyColumn
                    width: flick.width
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.coverage !== ""
                        text: root.coverage
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colPrimary
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.entry ? `<div dir="${root.rtl ? "rtl" : "ltr"}">${root.entry.text}</div>` : ""
                        textFormat: Text.RichText
                        wrapMode: Text.WordWrap
                        horizontalAlignment: root.rtl ? Text.AlignRight : Text.AlignLeft
                        font.family: Appearance.font.family.main
                        font.pixelSize: root.fontSize
                        lineHeight: 1.3
                        color: Appearance.colors.colOnLayer1
                        linkColor: Appearance.colors.colPrimary
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                visible: !flick.visible
                spacing: 8
                width: parent.width - 24

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.status === "error" ? "cloud_off" : root.status === "ready" ? "notes" : "hourglass_top"
                    iconSize: 32
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: root.status === "error" ? Translation.tr("Could not get this tafsir. Check the connection.")
                        : root.status === "ready" ? Translation.tr("This tafsir has nothing on this verse.")
                        : Translation.tr("Downloading this surah's tafsir…")
                    color: Appearance.colors.colSubtext
                }
                QuranButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.status === "error"
                    icon: "refresh"
                    onClicked: root.fetch()
                }
            }
        }

        // ── The list of tafsirs
        ListView {
            id: list
            TouchpadScrollHandler { flickable: list }
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.picking
            clip: true
            spacing: 2
            model: root.rows
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
                readonly property bool chosen: modelData.id === root.tafsirId
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
                    onClicked: {
                        root.picking = false;
                        root.tafsirPicked(item.modelData.id);
                    }
                }
            }
        }
    }
}
