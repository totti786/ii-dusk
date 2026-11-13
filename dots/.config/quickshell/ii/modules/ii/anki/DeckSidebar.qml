pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Searchable, collapsible deck navigation. The bridge owns Anki's deck tree; this pane
 * only flattens the visible branches and reports the deck the user picked.
 */
Rectangle {
    id: root

    property var decks: null
    property real currentDeckId: 0
    property string query: ""
    property bool dueOnly: false

    property var expanded: ({})
    property var flatModel: []
    property bool initialized: false

    signal deckSelected(var deckId)
    signal searchDismissed()

    function focusSearch(): void {
        searchInput.forceActiveFocus();
        searchInput.selectAll();
    }

    /// The deck above (-1) or below (+1) the current one in the list as shown.
    function selectRelative(delta: int): void {
        const list = root.flatModel;
        if (list.length === 0)
            return;
        let at = list.findIndex(item => Number(item.node.id) === Number(root.currentDeckId));
        at = at < 0 ? (delta > 0 ? 0 : list.length - 1) : Math.max(0, Math.min(list.length - 1, at + delta));
        root.deckSelected(Number(list[at].node.id));
    }

    radius: ClockStyle.radiusCard
    color: ClockStyle.colPane

    function _matches(node, needle): bool {
        return needle === "" || String(node.name).toLowerCase().includes(needle);
    }

    function _subtreeMatches(node, needle): bool {
        if (root._matches(node, needle))
            return true;
        const children = node.children ?? [];
        for (const child of children) {
            if (root._subtreeMatches(child, needle))
                return true;
        }
        return false;
    }

    function _hasDue(node): bool {
        if (Number(node.new ?? 0) + Number(node.learn ?? 0) + Number(node.review ?? 0) > 0)
            return true;
        const children = node.children ?? [];
        for (const child of children) {
            if (root._hasDue(child))
                return true;
        }
        return false;
    }

    function _pathTo(node, target, path): var {
        if (!node)
            return null;
        const next = path.concat([String(node.id)]);
        if (Number(node.id) === Number(target))
            return next;
        const children = node.children ?? [];
        for (const child of children) {
            const found = root._pathTo(child, target, next);
            if (found !== null)
                return found;
        }
        return null;
    }

    function initialize(): void {
        const next = {};
        const top = root.decks?.children ?? [];
        for (const child of top)
            next[String(child.id)] = true;
        const path = root._pathTo(root.decks, root.currentDeckId, []);
        if (path !== null) {
            for (const id of path)
                next[id] = true;
        }
        root.expanded = next;
        root.initialized = true;
        root.rebuild();
    }

    function rebuild(): void {
        const out = [];
        const needle = root.query.trim().toLowerCase();

        function visit(node, depth) {
            if (needle !== "" && !root._subtreeMatches(node, needle))
                return;
            if (root.dueOnly && !root._hasDue(node))
                return;
            const children = node.children ?? [];
            out.push({
                "node": node,
                "depth": depth,
                "hasChildren": children.length > 0
            });
            const open = needle !== "" || root.expanded[String(node.id)] === true;
            if (open) {
                for (const child of children)
                    visit(child, depth + 1);
            }
        }

        const top = root.decks?.children ?? [];
        for (const child of top)
            visit(child, 0);
        root.flatModel = out;
    }

    function toggle(deckId): void {
        const next = Object.assign({}, root.expanded);
        const key = String(deckId);
        next[key] = next[key] !== true;
        root.expanded = next;
        root.rebuild();
    }

    onDecksChanged: {
        if (root.initialized)
            root.rebuild();
        else
            root.initialize();
    }
    onCurrentDeckIdChanged: {
        const path = root._pathTo(root.decks, root.currentDeckId, []);
        if (path !== null) {
            const next = Object.assign({}, root.expanded);
            for (const id of path)
                next[id] = true;
            root.expanded = next;
            root.rebuild();
        }
    }

    Component.onCompleted: root.initialize()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.cardPadding
        spacing: ClockStyle.gapSmall

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Decks")
                font.pixelSize: ClockStyle.textLarge
                font.weight: Font.DemiBold
                color: ClockStyle.colOnSurface
            }

            StyledText {
                text: root.flatModel.length
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 46
            radius: ClockStyle.pill(46)
            color: searchInput.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField

            StyledTextInput {
                id: searchInput
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                verticalAlignment: TextInput.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                color: ClockStyle.colOnSurface
                onTextChanged: {
                    root.query = searchInput.text;
                    root.rebuild();
                }
                onAccepted: {
                    if (root.flatModel.length > 0)
                        root.deckSelected(Number(root.flatModel[0].node.id));
                    searchInput.text = "";
                    searchInput.focus = false;
                    root.searchDismissed();
                }
                Keys.onEscapePressed: event => {
                    searchInput.text = "";
                    searchInput.focus = false;
                    root.searchDismissed();
                    event.accepted = true;
                }
            }

            StyledText {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                verticalAlignment: Text.AlignVCenter
                visible: searchInput.text.length === 0
                text: Translation.tr("Search decks")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1Inactive
            }
        }

        ClockChip {
            label: Translation.tr("Due only")
            selected: root.dueOnly
            onClicked: {
                root.dueOnly = !root.dueOnly;
                root.rebuild();
            }
        }

        ListView {
            WheelScroll {}
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: root.flatModel

            delegate: Item {
                id: row

                required property var modelData
                required property int index

                readonly property var node: modelData.node
                readonly property int depth: modelData.depth
                readonly property bool selected: Number(node.id) === Number(root.currentDeckId)

                width: list.width
                height: 42

                Rectangle {
                    anchors.fill: parent
                    radius: ClockStyle.radiusSmall
                    color: row.selected
                        ? ClockStyle.colActiveCard
                        : pointer.containsMouse ? ClockStyle.colSurfaceHover : "transparent"
                }

                MouseArea {
                    id: pointer
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.deckSelected(Number(row.node.id))
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6 + row.depth * 14
                    anchors.rightMargin: 6
                    spacing: 4

                    ClockIconButton {
                        visible: row.modelData.hasChildren
                        symbol: root.expanded[String(row.node.id)] === true ? "expand_more" : "chevron_right"
                        size: 24
                        iconSize: 16
                        tooltip: ""
                        onClicked: root.toggle(row.node.id)
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: row.node.name
                        elide: Text.ElideRight
                        color: row.selected ? ClockStyle.colOnActiveCard : ClockStyle.colOnSurface
                        font.pixelSize: ClockStyle.textNormal
                    }

                    RowLayout {
                        spacing: 4

                        StyledText {
                            visible: Number(row.node.new ?? 0) > 0
                            text: Number(row.node.new ?? 0)
                            color: ClockStyle.colPrimary
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            visible: Number(row.node.learn ?? 0) > 0
                            text: Number(row.node.learn ?? 0)
                            color: ClockStyle.colTertiary
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            visible: Number(row.node.review ?? 0) > 0
                            text: Number(row.node.review ?? 0)
                            color: Appearance.colors.colSecondary
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }
    }
}
