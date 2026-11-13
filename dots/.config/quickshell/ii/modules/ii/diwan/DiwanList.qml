pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "DiwanCore.js" as Core

/// A page of poems or poets: search results, a poet's poems, a theme or an era, the poets
/// themselves, the saved poems and verses.
Item {
    id: root

    /// What the page is about, set large above the rows
    property string label: ""
    /// "poet" (one poet's poems), "poets" (the poets themselves), "saved", or "" for the rest
    property string kind: ""
    /// The server's answer: { poems: [...], poets: [...], page, pages, total }
    property var result: ({})
    property bool loading: false
    property string error: ""
    property string family: "Amiri"
    /// Chips that switch what is listed: [{ id, label }], none when there is nothing to switch
    property var sections: []
    property string section: ""
    property bool paged: true
    /// The row picked with the arrow keys, or -1
    property int cursor: -1

    signal openPoem(string slug, int index)
    signal openPoet(string slug, string name)
    signal pageTo(int page)
    signal sectionTo(string section)
    signal filterPoets(string query)
    signal retry()

    /// Whether the rows are poets rather than poems
    readonly property bool poets: root.result.poets !== undefined
    readonly property var rows: root.poets ? root.result.poets : (root.result.poems ?? [])
    readonly property real cardW: Math.min(root.width - (root.width < 700 ? 32 : 64), 820)
    readonly property int total: root.result.total ?? root.rows.length
    readonly property string subtitle: {
        if (root.loading || root.error !== "")
            return "";
        if (root.kind === "poet") {
            const era = root.rows.length > 0 ? root.rows[0].era : "";
            return [era, Core.count(root.total) + " قصيدة"].filter(s => s).join("  ·  ");
        }
        if (root.poets)
            return Core.count(root.total) + " شاعر";
        if (root.kind === "saved")
            return root.rows.length > 0 ? Core.count(root.rows.length) + (root.section === "verses" ? " بيت" : " قصيدة") : "";
        return root.total > 0 ? Core.count(root.total) + " نتيجة" : "";
    }

    onResultChanged: root.cursor = -1

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

    /// Arrow keys: move the picked row, keeping it in view
    function moveCursor(d: int): void {
        const n = root.rows.length;
        if (n === 0)
            return;
        glide.stop();
        root.cursor = Math.max(0, Math.min(n - 1, root.cursor < 0 ? (d > 0 ? 0 : n - 1) : root.cursor + d));
        list.positionViewAtIndex(root.cursor, ListView.Contain);
    }

    function activateCurrent(): void {
        const r = root.rows[root.cursor];
        if (r)
            root.open(r);
    }

    function open(r: var): void {
        if (root.poets)
            root.openPoet(r.slug, r.name);
        else
            root.openPoem(r.slug, r.index ?? -1);
    }

    function canPage(dir: int): bool {
        const p = (root.result.page ?? 1) + dir;
        return root.paged && !root.loading && p >= 1 && p <= (root.result.pages ?? 1);
    }

    function pageBy(dir: int): void {
        root.pageTo((root.result.page ?? 1) + dir);
    }

    ListView {
        id: list
        WheelScroll {}
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        spacing: 10
        model: root.rows
        header: Component {
            ColumnLayout {
                width: list.width
                spacing: 0
                Item { Layout.preferredHeight: 26 }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.kind === "poet"
                    text: "شاعر"
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colPrimary
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Math.min(root.cardW, implicitWidth)
                    text: root.label
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    font.family: root.family
                    font.pixelSize: root.width < 700 ? 32 : 40
                    color: Appearance.colors.colOnLayer0
                }
                DiwanOrnament {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 6
                    visible: root.kind === "poet"
                    span: 200
                }
                Item { Layout.preferredHeight: 8 }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.subtitle !== ""
                    text: root.subtitle
                    font.family: root.family
                    font.pixelSize: 20
                    color: Appearance.colors.colSubtext
                }
                Item { Layout.preferredHeight: 12 }

                // Poets: look one up by name
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Math.min(root.cardW, 420)
                    visible: root.kind === "poets"
                    implicitHeight: 42
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer1
                    border.width: poetFilter.activeFocus ? 2 : 0
                    border.color: Appearance.colors.colPrimary
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        layoutDirection: Qt.RightToLeft
                        spacing: 8
                        MaterialSymbol { text: "person_search"; iconSize: 20; color: Appearance.colors.colSubtext }
                        TextInput {
                            id: poetFilter
                            Layout.fillWidth: true
                            color: Appearance.colors.colOnLayer0
                            selectByMouse: true
                            clip: true
                            horizontalAlignment: TextInput.AlignRight
                            font.family: root.family
                            font.pixelSize: 20
                            onAccepted: root.filterPoets(text)
                            Keys.onEscapePressed: root.forceActiveFocus()
                            Text {
                                visible: !poetFilter.text && !poetFilter.activeFocus
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: "ابحث عن شاعر بالاسم"
                                font.family: root.family
                                font.pixelSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }

                Row {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.sections.length > 0
                    spacing: 8
                    layoutDirection: Qt.RightToLeft
                    Repeater {
                        model: root.sections
                        delegate: DiwanChip {
                            required property var modelData
                            text: modelData.label
                            active: root.section === modelData.id
                            clickable: true
                            onClicked: root.sectionTo(modelData.id)
                        }
                    }
                }
                Item { Layout.preferredHeight: 18 }
            }
        }

        delegate: Item {
            id: row
            required property int index
            required property var modelData
            width: ListView.view.width
            height: card.height

            Rectangle {
                id: card
                x: (parent.width - width) / 2
                width: root.cardW
                height: col.implicitHeight + 28
                radius: 18
                color: area.containsMouse || root.cursor === row.index ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                border.width: root.cursor === row.index ? 2 : 0
                border.color: Appearance.colors.colPrimary
                Behavior on color { ColorAnimation { duration: Appearance.dur(120) } }

                ColumnLayout {
                    id: col
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.title ?? row.modelData.name ?? ""
                        elide: Text.ElideLeft
                        horizontalAlignment: Text.AlignRight
                        font.family: root.family
                        font.pixelSize: 26
                        color: Appearance.colors.colOnLayer0
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.poets
                            ? [row.modelData.era, row.modelData.count ? Core.count(row.modelData.count) + " قصيدة" : ""].filter(s => s).join("  ·  ")
                            : [root.kind === "poet" ? "" : row.modelData.poet, row.modelData.era, row.modelData.meter !== "غير معروف" ? row.modelData.meter : "", row.modelData.index !== undefined ? "البيت " + Core.digits(row.modelData.index + 1) : ""].filter(s => s).join("  ·  ")
                        visible: text.length > 0
                        elide: Text.ElideLeft
                        horizontalAlignment: Text.AlignRight
                        font.family: root.family
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colPrimary
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !root.poets && (row.modelData.snippet ?? "").length > 0
                        text: row.modelData.snippet ?? ""
                        elide: Text.ElideLeft
                        horizontalAlignment: Text.AlignRight
                        font.family: root.family
                        font.pixelSize: 21
                        color: Appearance.colors.colSubtext
                    }
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.open(row.modelData)
                }
            }
        }

        footer: Component {
            ColumnLayout {
                width: list.width
                spacing: 0
                Item { Layout.preferredHeight: 20 }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.paged && (root.result.pages ?? 1) > 1
                    layoutDirection: Qt.RightToLeft
                    spacing: 14
                    DiwanButton {
                        icon: "arrow_forward"
                        tip: "السابقة"
                        enabled: root.canPage(-1)
                        onClicked: root.pageBy(-1)
                    }
                    Text {
                        text: "صفحة " + Core.digits(root.result.page ?? 1) + " من " + Core.digits(root.result.pages ?? 1)
                        font.family: root.family
                        font.pixelSize: 20
                        color: Appearance.colors.colSubtext
                    }
                    DiwanButton {
                        icon: "arrow_back"
                        tip: "التالية"
                        enabled: root.canPage(1)
                        onClicked: root.pageBy(1)
                    }
                }
                Item { Layout.preferredHeight: 60 }
            }
        }
    }

    // Loading, nothing found and errors sit over the empty list
    ColumnLayout {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 40
        spacing: 12
        visible: root.rows.length === 0
        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: root.error !== "" ? "cloud_off" : root.loading ? "hourglass_top" : root.kind === "saved" ? "bookmarks" : "search_off"
            iconSize: 40
            color: Appearance.colors.colSubtext
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: 460
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            font.family: root.family
            font.pixelSize: Appearance.font.pixelSize.huge
            color: Appearance.colors.colSubtext
            text: root.error !== "" ? root.error
                : root.loading ? "جارٍ البحث…"
                : root.kind === "saved" ? "لا شيء محفوظ بعد. اضغط S لحفظ قصيدة، أو اختر بيتًا واضغط B لحفظه."
                : "لا نتائج"
        }
        DiwanChip {
            Layout.alignment: Qt.AlignHCenter
            visible: root.error !== ""
            text: "حاول مرة أخرى"
            clickable: true
            onClicked: root.retry()
        }
    }
}
