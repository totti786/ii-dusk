pragma ComponentBehavior: Bound

import QtQuick

import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The library view: a hero for the book you are in the middle of, then one collection per top
 * folder, each a row of covers with a "Show all" to unfold the rest. One flat model of hero,
 * titles and rows keeps the list virtualised, so a thousand books cost the screenful in view.
 */
Item {
    id: root

    /// Filtered and sorted, as the library wants them shown.
    property var books: []
    /// Started books, newest first.
    property var started: []
    property var folderOrder: []
    property bool filtering: false
    property var groupOf: book => ""

    /// Collections the user unfolded, by title.
    property var expanded: ({})
    /// Rows that already played their entrance, so scrolling back does not replay it.
    property var seen: ({})

    signal activated(var book, var cover)
    signal contextRequested(var book, var point)

    readonly property real sidePad: 24
    readonly property real gap: 18
    readonly property real inner: root.width - 2 * root.sidePad
    readonly property int cols: Math.max(2, Math.floor((root.inner + root.gap) / (164 + root.gap)))
    readonly property real coverW: (root.inner - root.gap * (root.cols - 1)) / root.cols
    readonly property real heroHeight: 272

    onBooksChanged: {
        root.seen = ({});
        root.selectedId = "";
    }

    // ---- Keyboard: arrows walk the covers, Enter opens the one chosen ----
    property string selectedId: ""
    property Item selectedCover: null
    readonly property bool navActive: root.selectedId.length > 0

    function booksOf(row): var {
        if (row.kind === "shelf")
            return row.books;
        if (row.kind === "reading")
            return root.started.slice(0, 12);
        return null;
    }

    /// Where the chosen book is: { row, col }, or null.
    function locate(): var {
        for (let r = 0; r < root.rows.length; r++) {
            const list = root.booksOf(root.rows[r]);
            if (!list)
                continue;
            const c = list.findIndex(b => b.id === root.selectedId);
            if (c >= 0)
                return { row: r, col: c };
        }
        return null;
    }

    function nextRow(from: int, direction: int): int {
        for (let r = from + direction; r >= 0 && r < root.rows.length; r += direction) {
            if (root.booksOf(root.rows[r]))
                return r;
        }
        return -1;
    }

    function select(row: int, col: int): void {
        const list = root.booksOf(root.rows[row]);
        root.selectedId = list[col].id;
        if (root.rows[row].kind === "reading") {
            if (root.readingList)
                root.readingList.positionViewAtIndex(col, ListView.Contain);
            list.positionViewAtIndex(row, ListView.Contain);
        } else {
            list.positionViewAtIndex(row, ListView.Contain);
        }
    }

    /// Moves the choice by one cover: dx along a row, dy between rows.
    function navigate(dx: int, dy: int): void {
        const at = root.navActive ? root.locate() : null;
        if (!at) {
            const first = root.nextRow(-1, 1);
            if (first >= 0)
                root.select(first, 0);
            return;
        }
        const row = root.rows[at.row];
        const list = root.booksOf(row);
        // A right-to-left shelf is laid out mirrored, so left there is the next book.
        const step = row.rtl ? -dx : dx;
        if (dy !== 0) {
            const target = root.nextRow(at.row, dy);
            if (target >= 0) {
                const length = root.booksOf(root.rows[target]).length;
                root.select(target, Math.min(at.col, length - 1));
            }
            return;
        }
        const col = at.col + step;
        if (col >= 0 && col < list.length) {
            root.select(at.row, col);
        } else {
            const target = root.nextRow(at.row, step < 0 ? -1 : 1);
            if (target >= 0) {
                const length = root.booksOf(root.rows[target]).length;
                root.select(target, step < 0 ? length - 1 : 0);
            }
        }
    }

    function activateSelected(): void {
        const at = root.locate();
        if (!at)
            return;
        const book = root.booksOf(root.rows[at.row])[at.col];
        root.activated(book, root.selectedCover);
    }

    function clearSelection(): void {
        root.selectedId = "";
    }

    property Item readingList: null
    NumberAnimation {
        id: readingScroll
        property: "contentX"
        duration: Appearance.dur(280)
        easing.type: Easing.OutCubic
    }

    /// One screenful of cards to the left (-1) or right (+1).
    function scrollReading(direction: int): void {
        const view = root.readingList;
        if (!view)
            return;
        const target = Math.max(0, Math.min(view.contentWidth - view.width, view.contentX + direction * view.width * 0.8));
        readingScroll.target = view;
        readingScroll.from = view.contentX;
        readingScroll.to = target;
        readingScroll.restart();
    }

    function isArabic(text: string): bool {
        return /[؀-ۿ]/.test(text);
    }

    function toggle(title: string): void {
        const next = Object.assign({}, root.expanded);
        next[title] = !next[title];
        root.expanded = next;
    }

    readonly property var rows: {
        const out = [];
        if (!root.filtering && root.started.length > 0) {
            out.push({ kind: "title", title: Translation.tr("Continue reading"), count: Math.min(12, root.started.length), foldable: false, open: false, scroller: true, key: "t:reading" });
            out.push({ kind: "reading", key: "reading" });
        }

        const groups = {};
        const order = [];
        for (const book of root.books) {
            const name = root.groupOf(book);
            if (!(name in groups)) {
                groups[name] = [];
                order.push(name);
            }
            groups[name].push(book);
        }
        const rank = name => {
            const at = root.folderOrder.indexOf(name);
            return at < 0 ? 999 : at;
        };
        order.sort((a, b) => rank(a) - rank(b));

        for (const name of order) {
            const list = groups[name];
            const arabic = list.filter(b => root.isArabic(b.title)).length;
            const rtl = arabic * 2 > list.length;
            const open = root.filtering || root.expanded[name] === true;
            const foldable = !root.filtering && list.length > root.cols;
            out.push({ kind: "title", title: name, count: list.length, foldable: foldable, open: open, key: "t:" + name });
            const shown = open ? list.length : Math.min(list.length, root.cols);
            for (let i = 0; i < shown; i += root.cols)
                out.push({ kind: "shelf", books: list.slice(i, Math.min(i + root.cols, shown)), rtl: rtl, key: "s:" + name + ":" + i });
        }
        return out;
    }

    readonly property bool empty: root.rows.length === 0

    ListView {
        id: list
        WheelScroll {}
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.rows
        cacheBuffer: 900
        spacing: 0

        delegate: Item {
            id: row

            required property var modelData
            readonly property string kind: row.modelData.kind

            width: ListView.view.width
            height: row.kind === "reading" ? 216
                : row.kind === "title" ? 64
                : root.coverW * 1.46 + 84

            // ---- The books you have on the go ----
            Loader {
                active: row.kind === "reading"
                anchors.fill: parent
                sourceComponent: readingComponent
            }

            // ---- Collection title ----
            Item {
                visible: row.kind === "title"
                anchors.fill: parent

                Row {
                    x: root.sidePad
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    spacing: 12

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.kind === "title" ? row.modelData.title : ""
                        color: ClockStyle.colOnSurface
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.DemiBold
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: countText.implicitWidth + 20
                        height: 26
                        radius: 13
                        color: ClockStyle.colSecondaryContainer

                        StyledText {
                            id: countText
                            anchors.centerIn: parent
                            text: row.kind === "title" ? row.modelData.count : ""
                            color: ClockStyle.colOnSecondaryContainer
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.Medium
                        }
                    }
                }

                Row {
                    visible: row.kind === "title" && row.modelData.scroller === true
                    anchors {
                        right: parent.right
                        rightMargin: root.sidePad
                        bottom: parent.bottom
                        bottomMargin: 4
                    }
                    spacing: 4

                    ClockIconButton {
                        symbol: "chevron_left"
                        tooltip: Translation.tr("Earlier")
                        onClicked: root.scrollReading(-1)
                    }
                    ClockIconButton {
                        symbol: "chevron_right"
                        tooltip: Translation.tr("Later")
                        onClicked: root.scrollReading(1)
                    }
                }

                ClockChip {
                    visible: row.kind === "title" && row.modelData.foldable
                    anchors {
                        right: parent.right
                        rightMargin: root.sidePad
                        bottom: parent.bottom
                        bottomMargin: 4
                    }
                    symbol: row.kind === "title" && row.modelData.open ? "expand_less" : "expand_more"
                    label: row.kind === "title" && row.modelData.open ? Translation.tr("Show less") : Translation.tr("Show all")
                    onClicked: root.toggle(row.modelData.title)
                }
            }

            // ---- A row of covers ----
            Row {
                visible: row.kind === "shelf"
                spacing: root.gap
                layoutDirection: row.kind === "shelf" && row.modelData.rtl ? Qt.RightToLeft : Qt.LeftToRight
                x: row.kind === "shelf" && row.modelData.rtl ? parent.width - root.sidePad - width : root.sidePad
                y: 6

                Repeater {
                    model: row.kind === "shelf" ? row.modelData.books : []

                    delegate: ShelfBook {
                        required property var modelData
                        required property int index
                        book: modelData
                        host: root
                        order: index
                        rowKey: row.modelData.key
                        width: root.coverW
                        height: root.coverW * 1.46 + 70
                        onActivated: cover => root.activated(modelData, cover)
                        onContextRequested: point => root.contextRequested(modelData, point)
                    }
                }
            }
        }

        footer: Item {
            width: list.width
            height: 24
        }
    }

    Component {
        id: readingComponent

        ListView {
            id: cards
            WheelScroll {}
            orientation: ListView.Horizontal
            flickableDirection: Flickable.HorizontalFlick

            // A mouse has no sideways wheel, so its notches scroll this row. At either end the
            // wheel goes back to the page; a touchpad's vertical swipes always scroll the page.
            WheelHandler {
                target: null
                orientation: Qt.Vertical
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const angle = event.angleDelta.y;
                    const direction = angle < 0 ? 1 : -1;
                    const from = readingScroll.running ? readingScroll.to : cards.contentX;
                    const max = cards.contentWidth - cards.width + cards.rightMargin;
                    const min = -cards.leftMargin;
                    if (angle === 0 || !ScrollWheel.isNotch(angle, Config.options?.interactions?.scrolling, event.phase)
                            || (direction > 0 && from >= max - 1) || (direction < 0 && from <= min + 1)) {
                        event.accepted = false;
                        return;
                    }
                    event.accepted = true;
                    readingScroll.target = cards;
                    readingScroll.from = cards.contentX;
                    readingScroll.to = Math.max(min, Math.min(max, from - angle / 120 * 240));
                    readingScroll.restart();
                }
            }
            spacing: root.gap
            clip: true
            leftMargin: root.sidePad
            rightMargin: root.sidePad
            boundsBehavior: Flickable.StopAtBounds
            model: root.started.slice(0, 12)

            Component.onCompleted: root.readingList = cards

            delegate: Rectangle {
                id: card

                required property var modelData
                required property int index
                readonly property bool featured: card.index === 0
                readonly property real progress: BooksService.progressFor(card.modelData)
                readonly property int total: BooksService.pagesFor(card.modelData)
                readonly property color onCard: card.featured ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface
                readonly property color muted: card.featured ? Qt.alpha(ClockStyle.colOnPrimaryContainer, 0.75) : ClockStyle.colSubtext

                width: 430
                height: ListView.view.height - 20
                y: 6
                radius: 28
                readonly property bool chosen: root.selectedId === card.modelData.id
                color: card.featured
                    ? (cardPointer.containsMouse || card.chosen ? ClockStyle.colPrimaryContainerHover : ClockStyle.colPrimaryContainer)
                    : (cardPointer.containsMouse || card.chosen ? ClockStyle.colSurfaceHover : ClockStyle.colSurfaceHigh)

                Behavior on color { enabled: !ClockStyle.reducedMotion; ColorAnimation { duration: Appearance.dur(140) } }

                MouseArea {
                    id: cardPointer
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton)
                            root.contextRequested(card.modelData, cardPointer.mapToItem(null, mouse.x, mouse.y));
                        else
                            root.activated(card.modelData, cardCover);
                    }
                }

                Rectangle {
                    anchors.fill: cardCover
                    anchors.topMargin: 6
                    anchors.bottomMargin: -6
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    radius: 18
                    color: "#000000"
                    opacity: 0.24
                }

                Binding {
                    when: card.chosen
                    target: root
                    property: "selectedCover"
                    value: cardCover
                }

                BookCover {
                    id: cardCover
                    x: 16
                    y: 16
                    height: card.height - 32
                    width: height * 0.68
                    source: BooksService.coverFor(card.modelData)
                    title: card.modelData.title
                    format: ""
                    radius: 18
                }

                Column {
                    anchors {
                        left: cardCover.right
                        leftMargin: 18
                        right: parent.right
                        rightMargin: 18
                        top: parent.top
                        topMargin: 18
                        bottom: parent.bottom
                        bottomMargin: 18
                    }
                    spacing: 4

                    StyledText {
                        width: parent.width
                        text: card.modelData.lastRead ? Translation.tr("Read %1").arg(BooksService.ago(card.modelData.lastRead)) : Translation.tr("Started")
                        color: card.muted
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    StyledText {
                        width: parent.width
                        text: card.modelData.title
                        maximumLineCount: 3
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        color: card.onCard
                        font.pixelSize: ClockStyle.textLarge
                        font.weight: Font.DemiBold
                    }
                }

                // Bottom of the card: how far, and the way back in.
                Item {
                    anchors {
                        left: cardCover.right
                        leftMargin: 18
                        right: parent.right
                        rightMargin: 18
                        bottom: parent.bottom
                        bottomMargin: 18
                    }
                    height: 48

                    Column {
                        anchors {
                            left: parent.left
                            right: playButton.left
                            rightMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 8

                        StyledText {
                            width: parent.width
                            text: card.total > 0
                                ? Translation.tr("Page %1 of %2").arg(Number(card.modelData.page) + 1).arg(card.total)
                                : Translation.tr("Page %1").arg(Number(card.modelData.page) + 1)
                            color: card.onCard
                            font.pixelSize: ClockStyle.textSmall
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            visible: card.progress >= 0
                            width: parent.width
                            height: 8
                            radius: 4
                            color: Qt.alpha(card.onCard, 0.16)

                            Rectangle {
                                width: Math.max(8, parent.width * card.progress)
                                height: parent.height
                                radius: 4
                                color: card.featured ? ClockStyle.colPrimary : ClockStyle.colPrimary
                            }
                        }
                    }

                    Rectangle {
                        id: playButton
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        width: 48
                        height: 48
                        radius: cardPointer.containsMouse ? 16 : 24
                        color: ClockStyle.colPrimary

                        Behavior on radius { enabled: !ClockStyle.reducedMotion; NumberAnimation { duration: Appearance.dur(180); easing.type: Easing.OutCubic } }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "auto_stories"
                            fill: 1
                            iconSize: 24
                            color: ClockStyle.colOnPrimary
                        }
                    }
                }

                // Cards slide in once, in order.
                SequentialAnimation {
                    id: arrive
                    PauseAnimation { duration: Math.min(card.index, 6) * 60 }
                    ParallelAnimation {
                        NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: Appearance.dur(260) }
                        NumberAnimation { target: card; property: "y"; from: 30; to: 6; duration: Appearance.dur(420); easing.type: Easing.OutBack; easing.overshoot: 0.8 }
                    }
                }
                Component.onCompleted: {
                    const key = "reading/" + card.modelData.id;
                    if (ClockStyle.reducedMotion || root.seen[key])
                        return;
                    root.seen[key] = true;
                    card.opacity = 0;
                    arrive.start();
                }
            }
        }
    }
}
