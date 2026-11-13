pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "QuranCore.js" as Core

/// The book's index: surahs, juz and saved ayahs, with a filter. Picking one turns to its page.
Rectangle {
    id: root

    /// { "2:255": true }
    property var savedMap: ({})
    property int currentPage: 1
    /// The book's data is loaded; the rows are built from it
    property bool ready: false
    /// "surah", "juz" or "saved"
    property string tab: "surah"

    signal pageRequested(int page, string key)
    signal surahRequested(int surah)

    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    readonly property var savedKeys: {
        const keys = Object.keys(root.savedMap);
        keys.sort((a, b) => {
            const x = a.split(":"), y = b.split(":");
            return (+x[0] - +y[0]) || (+x[1] - +y[1]);
        });
        return keys;
    }

    /// Rows for the current tab: { title, sub, badge, page, key }
    readonly property var rows: {
        const out = [];
        if (!root.ready)
            return out;
        const q = filter.text.trim();
        if (root.tab === "surah") {
            for (let s = 1; s <= 114; s++) {
                const name = Core.SURAH_NAMES_AR[s];
                if (q !== "" && name.indexOf(q) < 0 && String(s) !== q)
                    continue;
                out.push({ title: name, sub: Translation.tr("%1 ayahs").arg(Core.ayahCount(s)), badge: String(s), page: Core.surahStartPage(s), key: "", surah: s });
            }
        } else if (root.tab === "juz") {
            for (let j = 1; j <= 30; j++) {
                if (q !== "" && String(j) !== q)
                    continue;
                out.push({ title: Translation.tr("Juz %1").arg(j), sub: Translation.tr("Page %1").arg(Core.juzStartPage(j)), badge: String(j), page: Core.juzStartPage(j), key: "" });
            }
        } else {
            for (const k of root.savedKeys) {
                const p = k.split(":");
                const name = Core.SURAH_NAMES_AR[+p[0]];
                if (q !== "" && name.indexOf(q) < 0 && k.indexOf(q) < 0)
                    continue;
                out.push({ title: name + " · " + p[1], sub: Core.ayahPreview(+p[0], +p[1], 6), badge: "", page: Core.findPageForAyah(+p[0], +p[1]), key: k });
            }
        }
        return out;
    }

    // Empty parts of the drawer belong to the drawer, not to the page behind it
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [
                    { id: "surah", icon: "format_list_numbered", text: Translation.tr("Surah") },
                    { id: "juz", icon: "view_module", text: Translation.tr("Juz") },
                    { id: "saved", icon: "bookmark", text: Translation.tr("Saved") }
                ]
                delegate: QuranPill {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: modelData.icon
                    text: modelData.text
                    active: root.tab === modelData.id
                    onClicked: {
                        root.tab = modelData.id;
                        filter.text = "";
                    }
                }
            }
        }

        // Filter field, the same pill as the search in the top bar
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2
            border.width: filter.activeFocus ? 2 : 0
            border.color: Appearance.colors.colPrimary
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 8
                MaterialSymbol { text: "search"; iconSize: 20; color: Appearance.colors.colSubtext }
                TextInput {
                    id: filter
                    Layout.fillWidth: true
                    color: Appearance.colors.colOnLayer0
                    selectByMouse: true
                    clip: true
                    font.pixelSize: Appearance.font.pixelSize.normal
                    Keys.onEscapePressed: event => {
                        if (text !== "") {
                            text = "";
                            event.accepted = true;
                        } else {
                            event.accepted = false;
                        }
                    }
                    StyledText {
                        visible: !filter.text
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Filter")
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        StyledListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            popin: false
            animateAppearance: false
            animatePopulate: false
            model: root.rows

            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool here: modelData.page === root.currentPage || modelData.page === root.currentPage - 1
                width: ListView.view.width
                height: 52
                radius: Appearance.rounding.normal
                color: area.containsMouse ? Appearance.colors.colLayer2 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 14
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: Appearance.rounding.full
                        color: row.here && root.tab !== "saved" ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                        MaterialSymbol {
                            visible: row.modelData.badge === ""
                            anchors.centerIn: parent
                            text: "bookmark"
                            iconSize: 18
                            fill: 1
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            visible: row.modelData.badge !== ""
                            anchors.centerIn: parent
                            text: row.modelData.badge
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: row.here ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.title
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.sub
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    MaterialSymbol {
                        text: "chevron_right"
                        iconSize: 20
                        color: Appearance.colors.colSubtext
                    }
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.modelData.surah ? root.surahRequested(row.modelData.surah) : root.pageRequested(row.modelData.page, row.modelData.key)
                }
            }

            StyledText {
                visible: list.count === 0
                anchors.centerIn: parent
                width: parent.width - 40
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.tab === "saved" ? Translation.tr("No saved ayahs yet. Select an ayah and press the bookmark.") : Translation.tr("Nothing matches")
                color: Appearance.colors.colSubtext
            }
        }
    }
}
