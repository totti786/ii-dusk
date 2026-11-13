pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// Back/forward/up, the path bar, search and the view controls.
Item {
    id: root

    property bool canBack: false
    property bool canForward: false
    property bool canUp: false
    property string path: ""
    property string home: ""
    property string viewMode: "grid"
    property bool searching: false
    property bool deepSearch: false
    property string query: ""
    readonly property alias pathBar: bar
    readonly property alias searchInput: searchField

    signal back()
    signal forward()
    signal up()
    signal refresh()
    signal navigate(string path)
    signal dropped(var urls, string folder, int action)
    signal viewChanged(string mode)
    signal queryChanged2(string text)
    signal deepToggled()
    signal searchSubmitted()
    signal tabRequested(string path)
    signal moreRequested(real x, real y)
    signal searchClosed()
    signal searchOpened()

    function focusSearch(): void {
        searchField.forceActiveFocus();
        searchField.selectAll();
    }

    onSearchingChanged: if (searching) searchField.text = root.query

    implicitHeight: 38

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 0
        anchors.rightMargin: 0
        spacing: 10

        Rectangle {
            Layout.preferredHeight: 38
            Layout.preferredWidth: navRow.implicitWidth + 12
            radius: Appearance.rounding.full
            color: ClockStyle.colSurfaceHigh
            RowLayout {
                id: navRow
                anchors.centerIn: parent
                spacing: 2
                FmIconButton { symbol: "arrow_back"; tip: qsTr("Back  (Alt+←)"); enabled2: root.canBack; onClicked: root.back() }
                FmIconButton { symbol: "arrow_forward"; tip: qsTr("Forward  (Alt+→)"); enabled2: root.canForward; onClicked: root.forward() }
                FmIconButton { symbol: "arrow_upward"; tip: qsTr("Up  (Alt+↑)"); enabled2: root.canUp; onClicked: root.up() }
                FmIconButton { symbol: "refresh"; tip: qsTr("Refresh  (F5)"); onClicked: root.refresh() }
            }
        }

        PathBar {
            id: bar
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            path: root.path
            home: root.home
            visible: !root.searching
            onNavigate: p => root.navigate(p)
            onTabRequested: p => root.tabRequested(p)
            onDropped: (urls, folder, action) => root.dropped(urls, folder, action)
        }

        Rectangle {
            visible: root.searching
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            radius: Appearance.rounding.full
            color: ClockStyle.colField
            border.width: 2
            border.color: ClockStyle.colPrimary
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 8
                spacing: 8
                MaterialSymbol { text: "search"; iconSize: 20; color: ClockStyle.colSubtext }
                TextInput {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    color: ClockStyle.colOnSurface
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family.main
                    selectByMouse: true
                    clip: true
                    onTextEdited: root.queryChanged2(text)
                    Keys.onEscapePressed: root.searchClosed()
                    Keys.onReturnPressed: root.searchSubmitted()
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchField.text.length === 0
                        text: root.deepSearch ? qsTr("Search here and in subfolders  (* and ? work)") : qsTr("Filter this folder only")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: ClockStyle.colSubtext
                    }
                }
                FmChip {
                    text: qsTr("Subfolders")
                    checked: root.deepSearch
                    onClicked: root.deepToggled()
                }
                FmIconButton { size: 28; iconSize: 18; symbol: "close"; onClicked: root.searchClosed() }
            }
        }

        Rectangle {
            Layout.preferredHeight: 38
            Layout.preferredWidth: endRow.implicitWidth + 12
            radius: Appearance.rounding.full
            color: ClockStyle.colSurfaceHigh
            RowLayout {
                id: endRow
                anchors.centerIn: parent
                spacing: 2
                FmIconButton {
                    visible: !root.searching
                    symbol: "search"
                    tip: qsTr("Search  (Ctrl+F)")
                    onClicked: root.searchOpened()
                }
                FmIconButton {
                    symbol: root.viewMode === "grid" ? "view_list" : "grid_view"
                    tip: root.viewMode === "grid" ? qsTr("List view  (Ctrl+2)") : qsTr("Icon view  (Ctrl+1)")
                    onClicked: root.viewChanged(root.viewMode === "grid" ? "list" : "grid")
                }
                FmIconButton {
                    id: more
                    symbol: "more_vert"
                    tip: qsTr("More")
                    onClicked: {
                        const p = more.mapToItem(null, 0, more.height + 4);
                        root.moreRequested(p.x - 200, p.y);
                    }
                }
            }
        }
    }
}
