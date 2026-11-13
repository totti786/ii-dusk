pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The library as a full-screen overlay built for finding a book: one cover in the middle at
 * a time, the rest fanned to either side. Scroll, use the arrows, or just type to narrow the
 * library; Enter opens the one in the middle.
 */
PanelWindow {
    id: root

    signal closeRequested()

    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:books"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }

    property string query: ""
    property string folderFilter: ""      // "" | "__reading" | folder name
    /// "library", or the id of a source (Gutenberg, Z-Library, ...) being searched.
    property string scope: "library"
    readonly property bool remote: root.scope !== "library"
    property bool pendingReset: false
    /// The cover in the middle, for the open animation to start from.
    property Item centerCover: null
    property string submitted: ""
    property real appear: 0

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

    readonly property var shown: {
        const needle = root.query.trim().toLowerCase();
        const list = BooksService.books.filter(book => {
            if (root.folderFilter === "__reading" && !(book.page !== null && Number(book.page) > 0))
                return false;
            if (root.folderFilter.length > 0 && root.folderFilter !== "__reading" && root.topFolder(book) !== root.folderFilter)
                return false;
            return needle.length === 0 || book.title.toLowerCase().includes(needle) || book.folder.toLowerCase().includes(needle);
        });
        return list.sort((a, b) => (b.lastRead ?? 0) - (a.lastRead ?? 0) || b.added - a.added);
    }

    readonly property var items: {
        if (!root.remote)
            return root.shown;
        // A catalogue page is books, or, on a menu page such as Popular/Latest, folders to open.
        const entries = BooksService.browsePage?.entries ?? [];
        const books = entries.filter(e => e.kind === "book");
        return books.length > 0 ? books : entries;
    }
    readonly property var current: root.items.length > 0 ? root.items[Math.max(0, Math.min(carousel.currentIndex, root.items.length - 1))] : null
    readonly property real coverH: Math.min(root.height * 0.46, 480)
    readonly property real coverW: root.coverH * 0.68
    /// Centre-to-centre distance of neighbouring covers: wide enough that five fit either side.
    /// Distance of each cover's centre from the middle, one to seven books out. Each step clears
    /// the previous cover's shrunken, turned width plus a gap, so no two covers overlap.
    readonly property var stops: {
        const gap = 20;
        const half = n => root.coverW * (n === 0 ? 1 : Math.max(0.6, 1 - n * 0.095) * 0.87) / 2;
        const out = [0];
        for (let n = 1; n <= 7; n++)
            out.push(out[n - 1] + half(n - 1) + half(n) + gap);
        return out;
    }

    function centreAt(near: real): real {
        const a = Math.min(near, root.stops.length - 1.001);
        const i = Math.floor(a);
        return root.stops[i] + (root.stops[i + 1] - root.stops[i]) * (a - i);
    }
    readonly property bool mangaScope: root.scope === "manga"

    function coverOf(book): string {
        return root.remote ? (book.thumb ?? "") : BooksService.coverFor(book);
    }

    function resetPosition(): void {
        carousel.jumpTo(0);
    }

    function setScope(id: string): void {
        if (root.scope === id)
            return;
        root.scope = id;
        input.text = "";
        root.submitted = "";
        if (root.remote) {
            root.pendingReset = true;
            BooksService.selectSource(id);
        } else {
            root.resetPosition();
        }
    }

    function sourceName(): string {
        return BooksService.sources.find(x => x.id === root.scope)?.name ?? "";
    }

    function submitSearch(): void {
        root.submitted = input.text.trim();
        root.pendingReset = true;
        BooksService.browseSearch(root.submitted);
    }

    /// A manga is a series with chapters: that page lives in the window app.
    function handOffManga(entry): void {
        GlobalStates.booksOverlayOpen = false;
        GlobalStates.openBooksApp();
        BooksService.browseWanted = true;
        BooksService.browseOpen(entry.href);
    }

    function actOnCurrent(cover): void {
        const book = root.current;
        if (!book)
            return;
        if (!root.remote) {
            root.openCurrent(cover);
            return;
        }
        if (book.kind === "nav") {
            root.pendingReset = true;
            BooksService.browseOpen(book.href);
            return;
        }
        if (root.mangaScope) {
            root.handOffManga(book);
            return;
        }
        const format = (book.formats ?? [])[0];
        if (!format)
            return;
        const state = BooksService.downloads[format.href];
        if (state?.state === "done") {
            BooksService.open({ "path": state.path });
            root.closeRequested();
        } else {
            BooksService.download(book, format);
        }
    }

    function step(delta: int): void {
        if (root.items.length === 0)
            return;
        carousel.currentIndex = Math.max(0, Math.min(root.items.length - 1, carousel.currentIndex + delta));
    }

    function openCurrent(cover): void {
        const book = root.current;
        if (!book)
            return;
        if (ClockStyle.reducedMotion || !cover) {
            BooksService.open(book);
            root.closeRequested();
            return;
        }
        const at = cover.mapToItem(lift, 0, 0);
        lift.book = book;
        lift.play(BooksService.coverFor(book), book.title, Qt.rect(at.x, at.y, cover.width, cover.height));
    }

    function cycleFolder(direction: int): void {
        if (root.remote)
            return;
        const order = ["", "__reading"].concat(root.folders);
        const at = order.indexOf(root.folderFilter);
        root.folderFilter = order[(at + direction + order.length) % order.length];
    }

    onShownChanged: {
        if (!root.remote)
            root.resetPosition();
    }

    Component.onCompleted: {
        BooksService.refresh();
        if (BooksService.sources.length === 0)
            BooksService.refreshSources();
        if (ClockStyle.reducedMotion)
            root.appear = 1;
        else
            appearAnim.start();
        input.forceActiveFocus();
        Qt.callLater(() => root.resetPosition());
    }
    Component.onDestruction: BooksService.stopCovers()

    Connections {
        target: BooksService
        function onBrowseLoadingChanged() {
            if (!BooksService.browseLoading && root.pendingReset) {
                root.pendingReset = false;
                root.resetPosition();
            }
        }
        function onLoadingChanged() {
            if (!BooksService.loading && BooksService.books.length > 0)
                BooksService.startCovers();
        }
    }

    NumberAnimation {
        id: appearAnim
        target: root
        property: "appear"
        from: 0
        to: 1
        duration: Appearance.dur(420)
        easing.type: Easing.OutCubic
    }

    // ---- Backdrop: the middle book's cover, blurred, over the shell's own background ----
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Appearance.colors.colLayer0.r, Appearance.colors.colLayer0.g, Appearance.colors.colLayer0.b, 1)
        opacity: root.appear
    }

    Image {
        id: ambient
        anchors.fill: parent
        visible: false
        source: root.current ? root.coverOf(root.current) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: 200
        onStatusChanged: if (status === Image.Ready && !ClockStyle.reducedMotion) fade.restart()
    }
    MultiEffect {
        anchors.fill: parent
        source: ambient
        blurEnabled: true
        blur: 1
        blurMax: 64
        saturation: 0.2
        opacity: 0
        NumberAnimation on opacity { id: fade; from: 0; to: 0.16; duration: Appearance.dur(500); running: false }
    }

    MouseArea {
        id: scroller
        anchors.fill: parent
        onClicked: root.closeRequested()

        // Scroll anywhere on the overlay, not only over the covers, along either axis. The
        // shell's own rule tells a wheel notch (one book) from a finger (distance in pixels,
        // one book per 50 px); amounts add up and a book moves each time they pass 120, the
        // remainder carried on, as in Mediator.
        property real acc: 0
        property real last: 0

        function feed(angle: real, pixel: real, phase: int): void {
            const settings = Config.options?.interactions?.scrolling;
            const amount = ScrollWheel.isNotch(angle, settings, phase)
                ? angle
                : ScrollWheel.touchpadStep(angle, pixel, settings) * (120 / 50);
            if (amount === 0)
                return;
            const now = Date.now();
            if (now - scroller.last > 400 || Math.sign(amount) !== Math.sign(scroller.acc))
                scroller.acc = 0;
            scroller.last = now;
            scroller.acc += amount;
            const steps = Math.trunc(scroller.acc / 120);
            if (steps === 0)
                return;
            scroller.acc -= steps * 120;
            root.step(-steps);
        }

        // A WheelHandler listens to one axis only, so there is one for each.
        WheelHandler {
            target: null
            orientation: Qt.Vertical
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                event.accepted = true;
                scroller.feed(event.angleDelta.y, event.pixelDelta.y, event.phase);
            }
        }
        WheelHandler {
            target: null
            orientation: Qt.Horizontal
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                event.accepted = true;
                scroller.feed(event.angleDelta.x, event.pixelDelta.x, event.phase);
            }
        }
    }

    // ---- Top bar: where to look ----
    Row {
        id: scopes
        anchors {
            top: parent.top
            topMargin: 28
            horizontalCenter: parent.horizontalCenter
        }
        spacing: ClockStyle.gapSmall
        opacity: root.appear

        ClockChip {
            symbol: "local_library"
            label: Translation.tr("Library")
            selected: !root.remote
            onClicked: root.setScope("library")
        }
        Repeater {
            model: BooksService.sources
            delegate: ClockChip {
                required property var modelData
                symbol: "travel_explore"
                label: modelData.name
                selected: root.scope === modelData.id
                onClicked: root.setScope(modelData.id)
            }
        }
    }

    Row {
        id: chips
        visible: !root.remote
        anchors {
            top: scopes.bottom
            topMargin: 12
            horizontalCenter: parent.horizontalCenter
        }
        spacing: ClockStyle.gapSmall
        opacity: root.appear

        ClockChip {
            label: Translation.tr("All")
            selected: root.folderFilter === ""
            onClicked: root.folderFilter = ""
        }
        ClockChip {
            symbol: "auto_stories"
            label: Translation.tr("Reading")
            selected: root.folderFilter === "__reading"
            onClicked: root.folderFilter = root.folderFilter === "__reading" ? "" : "__reading"
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

    ClockIconButton {
        anchors {
            top: parent.top
            right: parent.right
            topMargin: 24
            rightMargin: 28
        }
        symbol: "close"
        tooltip: Translation.tr("Close")
        onClicked: root.closeRequested()
    }

    // ---- The coverflow ----
    Item {
        id: carousel
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            topMargin: Math.max(130, (root.height - root.coverH - 70 - 150) / 2 + 20)
        }
        height: root.coverH + 70
        opacity: root.appear
        scale: 0.94 + 0.06 * root.appear

        /// The book in the middle; the title, the counter and Enter all follow it.
        property int currentIndex: 0
        // Same idea as the Mediator carousel: one animated position lays out every cover, so
        // the covers and the title can never disagree, however the book was chosen.
        property real pos: 0
        Behavior on pos {
            id: posMove
            NumberAnimation { duration: Appearance.dur(260); easing.type: Easing.OutCubic }
        }

        /// Jump without sweeping across the whole library (a new search, a new source).
        function jumpTo(index: int): void {
            posMove.enabled = false;
            carousel.currentIndex = index;
            carousel.pos = index;
            posMove.enabled = true;
        }

        onCurrentIndexChanged: {
            carousel.pos = carousel.currentIndex;
            if (root.remote && carousel.currentIndex >= root.items.length - 4)
                BooksService.browseMore();
        }

        // Only the covers near the middle exist; the rest of the library costs nothing.
        Repeater {
            model: root.items.length

            delegate: Loader {
                id: holder
                required property int index
                active: Math.abs(holder.index - carousel.pos) < 6
                sourceComponent: slotComponent
            }
        }

        Component {
            id: slotComponent

        Item {
            id: slot

            readonly property int index: parent && parent.index !== undefined ? parent.index : 0
            readonly property var modelData: root.items[slot.index]
            readonly property real offset: slot.index - carousel.pos
            readonly property real near: Math.abs(slot.offset)
            readonly property bool center: slot.index === carousel.currentIndex
            readonly property real progress: root.remote ? -1 : BooksService.progressFor(slot.modelData)

            width: root.coverW
            height: root.coverH
            x: (carousel.width - root.coverW) / 2 + (slot.offset < 0 ? -1 : 1) * root.centreAt(slot.near)
            y: 0
            z: 100 - slot.near * 10
            visible: slot.near < 5.6
            scale: Math.max(0.6, 1 - Math.min(slot.near, 4) * 0.095)
            opacity: Math.max(0, 1 - Math.max(0, slot.near - 3.6) * 0.5)
            transform: Rotation {
                origin.x: slot.width / 2
                origin.y: slot.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: -Math.max(-1.5, Math.min(1.5, slot.offset)) * 30
            }

            Rectangle {
                anchors.fill: cover
                anchors.topMargin: 14
                anchors.bottomMargin: -14
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                radius: 24
                color: "#000000"
                opacity: slot.center ? 0.4 : 0.26
            }

            Binding {
                when: slot.center
                target: root
                property: "centerCover"
                value: cover
            }

            BookCover {
                id: cover
                anchors.fill: parent
                source: root.coverOf(slot.modelData)
                title: slot.modelData.title
                format: ""
                radius: 24

                Rectangle {
                    visible: !root.remote && slot.progress >= 0 && Number(slot.modelData.page) > 0
                    anchors {
                        right: parent.right
                        top: parent.top
                        margins: 12
                    }
                    width: pct.implicitWidth + 18
                    height: 26
                    radius: 13
                    color: ClockStyle.colPrimaryContainer

                    StyledText {
                        id: pct
                        anchors.centerIn: parent
                        text: Math.round(Math.max(0, slot.progress) * 100) + "%"
                        color: ClockStyle.colOnPrimaryContainer
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }
            }

            // Dim as it recedes, like the Mediator carousel.
            Rectangle {
                anchors.fill: cover
                radius: 24
                color: "black"
                opacity: Math.min(0.6, slot.near * 0.2)
                visible: opacity > 0.01
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (slot.center)
                        root.actOnCurrent(cover);
                    else
                        carousel.currentIndex = slot.index;
                }
            }
        }
        }
    }

    // ---- What you are looking at ----
    Column {
        anchors {
            top: carousel.bottom
            topMargin: 8
            horizontalCenter: parent.horizontalCenter
        }
        width: Math.min(root.width - 120, 760)
        spacing: 8
        visible: root.current !== null
        opacity: root.appear

        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.current ? root.current.title : ""
            maximumLineCount: 2
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            color: ClockStyle.colOnSurface
            font.pixelSize: 30
            font.weight: Font.DemiBold
        }
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            color: root.remote ? ClockStyle.colPrimary : ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textNormal
            text: {
                const b = root.current;
                if (!b)
                    return "";
                if (root.remote && b.kind === "nav")
                    return b.subtitle ?? "";
                if (root.remote)
                    return [b.author ?? "", root.sourceName()].filter(x => x.length > 0).join("  ·  ");
                const parts = [root.topFolder(b), b.format.toUpperCase()];
                if (b.page !== null && b.page !== undefined) {
                    const total = BooksService.pagesFor(b);
                    parts.push(total > 0
                        ? Translation.tr("p. %1 / %2").arg(Number(b.page) + 1).arg(total)
                        : Translation.tr("p. %1").arg(Number(b.page) + 1));
                    if (b.lastRead)
                        parts.push(BooksService.ago(b.lastRead));
                }
                return parts.join("  ·  ");
            }
        }

        // Source books: what can be downloaded, one button per format.
        Row {
            visible: root.remote && !root.mangaScope && root.current !== null && root.current.kind !== "nav"
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: ClockStyle.gapSmall

            Repeater {
                model: root.remote && root.current ? (root.current.formats ?? []).slice(0, 4) : []

                delegate: Rectangle {
                    id: pill
                    required property var modelData
                    readonly property var state: BooksService.downloads[pill.modelData.href] ?? null
                    readonly property bool done: pill.state?.state === "done"
                    readonly property bool running: pill.state?.state === "running"

                    width: pillRow.implicitWidth + 32
                    height: 40
                    radius: 20
                    color: pill.done ? ClockStyle.colPrimary
                        : pillPointer.containsMouse ? ClockStyle.colPrimaryContainerHover : ClockStyle.colPrimaryContainer

                    Row {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: 8

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: pill.done ? "auto_stories" : pill.state?.state === "error" ? "refresh" : "download"
                            iconSize: 20
                            color: pill.done ? ClockStyle.colOnPrimary : ClockStyle.colOnPrimaryContainer
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            color: pill.done ? ClockStyle.colOnPrimary : ClockStyle.colOnPrimaryContainer
                            font.pixelSize: ClockStyle.textNormal
                            font.weight: Font.Medium
                            text: {
                                if (pill.done)
                                    return Translation.tr("Open");
                                if (pill.running)
                                    return pill.state.total > 0 ? Math.round(pill.state.received / pill.state.total * 100) + "%" : "…";
                                const size = Number(pill.modelData.size ?? 0);
                                return String(pill.modelData.ext ?? "").toUpperCase() + (size > 0 ? "  ·  " + (size / 1048576).toFixed(1) + " MB" : "");
                            }
                        }
                    }

                    MouseArea {
                        id: pillPointer
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (pill.done) {
                                BooksService.open({ "path": pill.state.path });
                                root.closeRequested();
                            } else if (!pill.running) {
                                BooksService.download(root.current, pill.modelData);
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            visible: root.remote && root.mangaScope && root.current !== null && root.current.kind !== "nav"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Enter opens the chapters in the Books window")
            color: ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textSmall
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        visible: root.items.length === 0
        spacing: ClockStyle.gap

        ClockEmptyState {
            Layout.alignment: Qt.AlignHCenter
            readonly property bool busy: root.remote ? BooksService.browseLoading : BooksService.loading
            symbol: busy ? "hourglass_top" : root.remote && BooksService.browseError.length > 0 ? "error" : "search_off"
            title: busy ? (root.remote ? Translation.tr("Loading…") : Translation.tr("Reading the library"))
                : root.remote && BooksService.browseError.length > 0 ? BooksService.browseError
                : Translation.tr("No books match")
            subtitle: busy ? "" : root.remote ? Translation.tr("Type a title and press Enter to search.")
                : Translation.tr("Try a different search or clear the filters.")
        }
    }

    // ---- Search: always listening ----
    Rectangle {
        id: searchPill
        anchors {
            bottom: parent.bottom
            bottomMargin: 36
            horizontalCenter: parent.horizontalCenter
        }
        width: Math.min(root.width - 80, 520)
        height: 54
        radius: 27
        color: ClockStyle.colSurfaceHighest
        opacity: root.appear
        y: parent.height - 36 - height + (1 - root.appear) * 20

        MaterialSymbol {
            anchors {
                left: parent.left
                leftMargin: 20
                verticalCenter: parent.verticalCenter
            }
            text: "search"
            iconSize: 22
            color: ClockStyle.colSubtext
        }

        StyledTextInput {
            id: input
            anchors {
                fill: parent
                leftMargin: 56
                rightMargin: 90
            }
            verticalAlignment: TextInput.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.normal
            color: ClockStyle.colOnSurface
            focus: true
            onTextChanged: root.query = text

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                    root.step(1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                    root.step(-1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageDown) {
                    root.step(8);
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageUp) {
                    root.step(-8);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Home && input.text.length === 0) {
                    carousel.currentIndex = 0;
                    event.accepted = true;
                } else if (event.key === Qt.Key_End && input.text.length === 0) {
                    carousel.currentIndex = Math.max(0, root.items.length - 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Tab) {
                    root.cycleFolder(1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Backtab) {
                    root.cycleFolder(-1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (root.remote && input.text.trim().length > 0 && input.text.trim() !== root.submitted) {
                        root.submitSearch();
                    } else {
                        const item = root.centerCover;
                        root.actOnCurrent(item ? item : null);
                    }
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    if (input.text.length > 0)
                        input.text = "";
                    else if (root.remote && BooksService.canGoBack) {
                        root.pendingReset = true;
                        BooksService.browseBack();
                    } else if (root.remote)
                        root.setScope("library");
                    else if (root.folderFilter.length > 0)
                        root.folderFilter = "";
                    else
                        root.closeRequested();
                    event.accepted = true;
                }
            }
        }

        StyledText {
            anchors {
                fill: parent
                leftMargin: 56
                rightMargin: 90
            }
            verticalAlignment: Text.AlignVCenter
            visible: input.text.length === 0
            text: root.remote ? Translation.tr("Search %1, then press Enter").arg(root.sourceName()) : Translation.tr("Search %1 books").arg(BooksService.books.length)
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnLayer1Inactive
        }

        StyledText {
            anchors {
                right: parent.right
                rightMargin: 22
                verticalCenter: parent.verticalCenter
            }
            visible: root.items.length > 0
            text: (carousel.currentIndex + 1) + " / " + root.items.length
            color: ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textSmall
        }
    }

    BookOpenLift {
        id: lift
        anchors.fill: parent
        property var book: null
        onStarted: {
            if (lift.book)
                BooksService.open(lift.book);
        }
        onFinished: {
            lift.book = null;
            root.closeRequested();
        }
    }
}
