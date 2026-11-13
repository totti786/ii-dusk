pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The Books library: search, filters, "continue reading" and the cover grid.
 *
 * BooksService owns the data; this file only decides what to show and opens books.
 */
FocusScope {
    id: root

    signal closeRequested()

    focus: true

    property string query: ""
    property string statusFilter: "all"   // all | reading
    property string formatFilter: ""      // "" | pdf | epub
    property string folderFilter: ""
    property bool settingsOpen: false
    property string mode: "library"   // library | browse
    property var menuBook: null
    property point menuPoint: Qt.point(0, 0)
    readonly property string sortMode: Config.options.books?.sort ?? "recent"

    readonly property string rootDir: BooksService.libraryDir

    function topFolder(book): string {
        const folder = book.folder ?? "";
        if (folder.length === 0)
            return Translation.tr("Library");
        if (folder.startsWith("/"))
            return Translation.tr("Elsewhere");
        return folder.split("/")[0];
    }

    readonly property var folders: {
        const counts = {};
        for (const book of BooksService.books)
            counts[root.topFolder(book)] = (counts[root.topFolder(book)] ?? 0) + 1;
        return Object.keys(counts).sort((a, b) => counts[b] - counts[a]);
    }

    readonly property var started: BooksService.books
        .filter(b => b.page !== null && b.page !== undefined && b.lastRead !== null && Number(b.page) > 0)
        .sort((a, b) => b.lastRead - a.lastRead)

    readonly property var shown: {
        const needle = root.query.trim().toLowerCase();
        let list = BooksService.books.filter(book => {
            if (root.statusFilter === "reading" && !(book.page !== null && Number(book.page) > 0))
                return false;
            if (root.formatFilter.length > 0 && book.format !== root.formatFilter)
                return false;
            if (root.folderFilter.length > 0 && root.topFolder(book) !== root.folderFilter)
                return false;
            if (needle.length > 0 && !(book.title.toLowerCase().includes(needle)
                    || book.folder.toLowerCase().includes(needle)))
                return false;
            return true;
        });
        if (root.sortMode === "title")
            list = list.sort((a, b) => a.title.localeCompare(b.title));
        else if (root.sortMode === "added")
            list = list.sort((a, b) => b.added - a.added);
        else
            list = list.sort((a, b) => (b.lastRead ?? 0) - (a.lastRead ?? 0) || b.added - a.added);
        return list;
    }

    readonly property bool filtering: root.query.length > 0 || root.statusFilter !== "all"
        || root.formatFilter.length > 0 || root.folderFilter.length > 0

    function openBook(book): void {
        BooksService.open(book);
        root.closeRequested();
    }

    /// From a shelf: the book is carried off it and opened before the viewer takes over.
    function openFromShelf(book, cover): void {
        if (ClockStyle.reducedMotion || !cover) {
            root.openBook(book);
            return;
        }
        const at = cover.mapToItem(lift, 0, 0);
        root.liftedBook = book;
        lift.play(BooksService.coverFor(book), book.title, Qt.rect(at.x, at.y, cover.width, cover.height));
    }

    property var liftedBook: null


    function cycleSort(): void {
        const order = ["recent", "title", "added"];
        Config.options.books.sort = order[(order.indexOf(root.sortMode) + 1) % order.length];
    }

    function sortLabel(): string {
        switch (root.sortMode) {
        case "title": return Translation.tr("Title");
        case "added": return Translation.tr("Newest");
        default: return Translation.tr("Recent");
        }
    }

    /// Escape in the browse view: close the form, step back a page, then return to the library.
    function leaveBrowse(): void {
        if (!browse.stepBack())
            root.mode = "library";
    }

    onModeChanged: {
        if (root.mode === "browse")
            browse.focusSearch();
        else
            search.forceActiveFocus();
    }

    function otherViewer(): string {
        return BooksService.viewers.find(v => v !== BooksService.viewer) ?? BooksService.viewer;
    }

    function showMenu(book, point): void {
        root.menuBook = book;
        root.menuPoint = root.mapFromItem(null, point.x, point.y);
    }

    function cycleViewer(): void {
        const list = BooksService.viewers;
        BooksService.setViewer(list[(list.indexOf(BooksService.viewer) + 1) % list.length]);
    }

    Component.onCompleted: {
        BooksService.refresh();
        if (BooksService.browseWanted) {
            root.mode = "browse";
            BooksService.browseWanted = false;
        } else {
            search.forceActiveFocus();
        }
    }

    Connections {
        target: BooksService

        function onLoadingChanged() {
            if (!BooksService.loading && BooksService.books.length > 0)
                BooksService.startCovers();
        }

        function onBrowseRequested() {
            root.mode = "browse";
            BooksService.browseWanted = false;
        }
    }

    Connections {
        target: BooksService

        function onLibraryDirChanged() {
            folderInput.text = BooksService.libraryDir;
        }
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (ctrl && (event.key === Qt.Key_W || event.key === Qt.Key_Q)) {
            root.closeRequested();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_R) {
            BooksService.refresh();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            if (root.menuBook !== null)
                root.menuBook = null;
            else if (cases.navActive)
                cases.clearSelection();
            else if (root.mode === "browse" && !root.settingsOpen)
                root.leaveBrowse();
            else if (root.settingsOpen)
                root.settingsOpen = false;
            else if (root.query.length > 0)
                search.text = "";
            else
                root.closeRequested();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: ClockStyle.colBackground
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.paneGap
        spacing: ClockStyle.paneGap

        ClockTopBar {
            Layout.fillWidth: true
            title: Translation.tr("Books")
            subtitle: Translation.tr("%1 books  ·  %2 in progress")
                .arg(BooksService.books.length).arg(root.started.length)
            onCloseRequested: root.closeRequested()

            ClockChip {
                symbol: "local_library"
                label: Translation.tr("Library")
                selected: root.mode === "library"
                onClicked: root.mode = "library"
            }

            ClockChip {
                symbol: "travel_explore"
                label: Translation.tr("Browse")
                selected: root.mode === "browse"
                onClicked: root.mode = "browse"
            }

            ClockIconButton {
                symbol: "refresh"
                tooltip: Translation.tr("Rescan the library")
                onClicked: BooksService.refresh()
            }

            ClockIconButton {
                symbol: "folder_open"
                tooltip: Translation.tr("Open the library folder")
                onClicked: Quickshell.execDetached(["xdg-open", BooksService.libraryDir])
            }

            ClockIconButton {
                symbol: "settings"
                tooltip: Translation.tr("Settings")
                toggled: root.settingsOpen
                onClicked: root.settingsOpen = !root.settingsOpen
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.mode === "library"
            spacing: ClockStyle.gapSmall

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 46
                radius: ClockStyle.radiusLarge
                color: search.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField

                MaterialSymbol {
                    id: searchIcon
                    anchors {
                        left: parent.left
                        leftMargin: 14
                        verticalCenter: parent.verticalCenter
                    }
                    text: "search"
                    iconSize: 20
                    color: ClockStyle.colSubtext
                }

                StyledTextInput {
                    id: search
                    anchors {
                        fill: parent
                        leftMargin: 46
                        rightMargin: 14
                    }
                    verticalAlignment: TextInput.AlignVCenter
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: ClockStyle.colOnSurface
                    onTextChanged: {
                        root.query = text;
                        cases.clearSelection();
                    }
                    onAccepted: {
                        if (root.shown.length > 0)
                            root.openBook(root.shown[0]);
                    }

                    // Arrows walk the covers; once a book is chosen, Enter opens that one.
                    Keys.onPressed: event => {
                        if (root.mode !== "library")
                            return;
                        if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                            cases.navigate(0, event.key === Qt.Key_Down ? 1 : -1);
                            event.accepted = true;
                        } else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && cases.navActive) {
                            cases.navigate(event.key === Qt.Key_Right ? 1 : -1, 0);
                            event.accepted = true;
                        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && cases.navActive) {
                            cases.activateSelected();
                            event.accepted = true;
                        }
                    }
                }

                StyledText {
                    anchors {
                        fill: parent
                        leftMargin: 46
                        rightMargin: 14
                    }
                    verticalAlignment: Text.AlignVCenter
                    visible: search.text.length === 0
                    text: Translation.tr("Search %1 books").arg(BooksService.books.length)
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1Inactive
                }
            }

            ClockChip {
                symbol: "sort"
                label: root.sortLabel()
                onClicked: root.cycleSort()
            }

            ClockChip {
                symbol: "menu_book"
                label: Translation.tr("Opens in %1").arg(BooksService.viewer)
                onClicked: root.cycleViewer()
            }
        }

        Flow {
            Layout.fillWidth: true
            visible: root.mode === "library"
            spacing: ClockStyle.gapSmall

            ClockChip {
                label: Translation.tr("All")
                selected: !root.filtering
                onClicked: {
                    search.text = "";
                    root.statusFilter = "all";
                    root.formatFilter = "";
                    root.folderFilter = "";
                }
            }

            ClockChip {
                symbol: "auto_stories"
                label: Translation.tr("Reading")
                selected: root.statusFilter === "reading"
                onClicked: root.statusFilter = root.statusFilter === "reading" ? "all" : "reading"
            }

            ClockChip {
                label: "PDF"
                selected: root.formatFilter === "pdf"
                onClicked: root.formatFilter = root.formatFilter === "pdf" ? "" : "pdf"
            }

            ClockChip {
                label: "EPUB"
                selected: root.formatFilter === "epub"
                onClicked: root.formatFilter = root.formatFilter === "epub" ? "" : "epub"
            }

            Repeater {
                model: root.folders

                delegate: ClockChip {
                    required property string modelData
                    symbol: "folder"
                    label: modelData
                    selected: root.folderFilter === modelData
                    onClicked: root.folderFilter = root.folderFilter === modelData ? "" : modelData
                }
            }
        }

        BooksBrowse {
            id: browse
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.mode === "browse"
            onOpenPath: path => root.openBook({ "path": path })
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.mode === "library"
            radius: ClockStyle.radiusLarge
            color: ClockStyle.colPane
            clip: true

            Bookcase {
                anchors.fill: parent
                visible: !cases.empty
                id: cases
                books: root.shown
                started: root.started
                folderOrder: root.folders
                filtering: root.filtering
                groupOf: book => root.topFolder(book)
                onActivated: (book, cover) => root.openFromShelf(book, cover)
                onContextRequested: (book, point) => root.showMenu(book, point)
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(520, parent.width - 40)
                visible: cases.empty
                spacing: ClockStyle.gap

                ClockEmptyState {
                    Layout.alignment: Qt.AlignHCenter
                    symbol: BooksService.loading ? "hourglass_top"
                        : !BooksService.folderExists ? "folder_off"
                        : BooksService.errorText.length > 0 ? "error"
                        : "search_off"
                    title: BooksService.loading ? Translation.tr("Reading the library")
                        : !BooksService.folderExists ? Translation.tr("Library folder not found")
                        : BooksService.errorText.length > 0 ? BooksService.errorText
                        : root.filtering ? Translation.tr("No books match") : Translation.tr("No books yet")
                    subtitle: BooksService.loading ? ""
                        : !BooksService.folderExists ? BooksService.libraryDir
                        : root.filtering ? Translation.tr("Try a different search or clear the filters.")
                        : Translation.tr("Put PDFs and EPUBs in %1.").arg(BooksService.libraryDir)
                }
            }
        }
    }

    BookOpenLift {
        id: lift
        anchors.fill: parent
        onStarted: {
            if (root.liftedBook)
                BooksService.open(root.liftedBook);
        }
        onFinished: {
            root.liftedBook = null;
            root.closeRequested();
        }
    }

    // ---- Right-click menu ----
    MouseArea {
        anchors.fill: parent
        visible: root.menuBook !== null
        z: 20
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: root.menuBook = null

        Rectangle {
            id: menu
            x: Math.max(8, Math.min(root.menuPoint.x, root.width - width - 8))
            y: Math.max(8, Math.min(root.menuPoint.y, root.height - height - 8))
            width: 250
            height: menuColumn.implicitHeight + 12
            radius: ClockStyle.radiusCard
            color: ClockStyle.colSurfaceHighest
            border.width: 1
            border.color: ClockStyle.colOutline

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: menuColumn
                anchors {
                    fill: parent
                    margins: 6
                }
                spacing: 2

                MenuEntry {
                    symbol: "menu_book"
                    label: Translation.tr("Open")
                    onTriggered: root.openBook(root.menuBook)
                }
                MenuEntry {
                    symbol: "open_in_new"
                    label: Translation.tr("Open in %1").arg(root.otherViewer())
                    visible: root.otherViewer() !== BooksService.viewer
                    onTriggered: {
                        BooksService.open(root.menuBook, root.otherViewer());
                        root.closeRequested();
                    }
                }
                MenuEntry {
                    symbol: "folder_open"
                    label: Translation.tr("Show in folder")
                    onTriggered: BooksService.showInFolder(root.menuBook)
                }
                MenuEntry {
                    symbol: "history_toggle_off"
                    label: Translation.tr("Remove from history")
                    danger: true
                    enabled: root.menuBook?.known ?? false
                    onTriggered: BooksService.forget(root.menuBook)
                }
            }
        }
    }

    component MenuEntry: Rectangle {
        id: entry

        property string symbol: ""
        property string label: ""
        property bool danger: false

        signal triggered()

        Layout.fillWidth: true
        implicitHeight: visible ? 40 : 0
        radius: ClockStyle.radiusSmall
        opacity: entry.enabled ? 1 : 0.4
        color: entryPointer.containsMouse && entry.enabled ? ClockStyle.colSurfaceHover : "transparent"

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 12
                rightMargin: 12
            }
            spacing: 12

            MaterialSymbol {
                text: entry.symbol
                iconSize: 20
                color: entry.danger ? Appearance.colors.colError : ClockStyle.colOnSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                text: entry.label
                elide: Text.ElideRight
                color: entry.danger ? Appearance.colors.colError : ClockStyle.colOnSurface
                font.pixelSize: ClockStyle.textNormal
            }
        }

        MouseArea {
            id: entryPointer
            anchors.fill: parent
            hoverEnabled: true
            enabled: entry.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                entry.triggered();
                root.menuBook = null;
            }
        }
    }

    // ---- Settings ----
    Rectangle {
        anchors.fill: parent
        visible: root.settingsOpen
        z: 10
        color: ClockStyle.colScrim
        opacity: 0.45

        MouseArea {
            anchors.fill: parent
            onClicked: root.settingsOpen = false
        }
    }

    Rectangle {
        id: settingsCard
        visible: root.settingsOpen
        z: 11
        anchors.centerIn: parent
        width: Math.min(560, parent.width - 40)
        height: settingsColumn.implicitHeight + 40
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colSurfaceHighest

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: settingsColumn
            anchors {
                fill: parent
                margins: 20
            }
            spacing: 16

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Books settings")
                    color: ClockStyle.colOnSurface
                    font.pixelSize: ClockStyle.textLarge
                    font.weight: Font.DemiBold
                }

                ClockIconButton {
                    symbol: "close"
                    tooltip: Translation.tr("Close")
                    onClicked: root.settingsOpen = false
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    text: Translation.tr("Library folder")
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: ClockStyle.radiusLarge
                        color: folderInput.activeFocus ? ClockStyle.colSurfaceHigh : ClockStyle.colSurface
                        border.width: 1
                        border.color: folderInput.activeFocus ? ClockStyle.colPrimary : ClockStyle.colOutline

                        StyledTextInput {
                            id: folderInput
                            anchors {
                                fill: parent
                                leftMargin: 14
                                rightMargin: 14
                            }
                            verticalAlignment: TextInput.AlignVCenter
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: ClockStyle.colOnSurface
                            clip: true
                            text: BooksService.libraryDir
                            onAccepted: {
                                BooksService.setLibraryDir(text);
                                root.forceActiveFocus();
                            }
                        }
                    }

                    ClockButton {
                        symbol: "folder_open"
                        label: Translation.tr("Browse")
                        onClicked: BooksService.browseLibraryDir()
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: !BooksService.folderExists
                        ? Translation.tr("This folder does not exist.")
                        : Translation.tr("Subfolders are scanned too. Press Enter to apply a typed path.")
                    color: BooksService.folderExists ? ClockStyle.colSubtext : Appearance.colors.colError
                    font.pixelSize: ClockStyle.textSmall
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    text: Translation.tr("Open books in")
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                    Repeater {
                        model: BooksService.viewers

                        delegate: ClockChip {
                            required property string modelData
                            label: modelData
                            selected: BooksService.viewer === modelData
                            onClicked: BooksService.setViewer(modelData)
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    text: Translation.tr("History")
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Translation.tr("Right-click a book and choose Remove from history to forget its page. Files are never deleted.")
                    color: ClockStyle.colOnSurface
                    font.pixelSize: ClockStyle.textNormal
                }

                ClockButton {
                    symbol: "restore"
                    label: Translation.tr("Show forgotten books again")
                    onClicked: BooksService.restoreForgotten()
                }
            }
        }
    }
}
