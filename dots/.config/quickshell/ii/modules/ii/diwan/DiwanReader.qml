pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "DiwanCore.js" as Core

/**
 * The poetry reader: a front page, one poem at a time set large, search, poets, a theme's or an
 * era's poems, and the poems and verses saved. Everything the service has sent is cached on disk by
 * scripts/diwan/diwan.py, so reading again costs no request.
 */
FocusScope {
    id: root

    signal closeRequested()
    signal windowRequested()
    signal overlayRequested()

    /// True when hosted in a floating window rather than the full-screen overlay
    property bool windowed: false

    readonly property string script: `${Directories.scriptPath}/diwan/diwan.py`
    readonly property var fonts: ["Amiri", "Noto Naskh Arabic"]

    /// The poem on show, or null before the first arrives
    property var poem: null
    /// "home", "poem", "list" (a page of poems or poets) or "saved"
    property string mode: "home"
    /// Where a list or the saved page goes back to: "home" or "poem"
    property string listFrom: "home"
    /// The vocabularies of the home page: { themes, eras, meters, collections }
    property var homeData: ({})
    property bool loadingHome: false
    property string homeError: ""
    /// The poem of the day, and the poems read lately (rows as in a list)
    property var daily: null
    property var recentRows: []
    property bool loadingPoem: false
    property string poemError: ""
    /// Slugs left behind, newest last, for the back button
    property var trail: []
    /// What the list page was asked for: { label, base: [command args], page, section, kind }
    /// where kind is "poet" (one poet's poems), "poets" (the poets themselves) or ""
    property var listReq: ({ label: "", base: [], page: 1, section: "", kind: "" })
    property var listData: ({})
    property bool loadingList: false
    property string listError: ""
    /// "poems" or "verses" on the saved page
    property string savedSection: "poems"
    /// The poem a request is for; "" means a random one
    property string wantSlug: ""
    /// A verse to scroll to and select once the poem arrives
    property int wantVerse: -1
    /// The verse picked in the poem on show, or -1
    property int selectedVerse: -1
    property bool textMenuOpen: false

    readonly property string favorites: Config.options.diwan.favorites
    readonly property string savedVerses: Config.options.diwan.verses
    readonly property bool tashkeel: Config.options.diwan.tashkeel
    readonly property bool isSaved: root.poem !== null && Core.hasFav(root.favorites, root.poem.slug)
    readonly property bool verseSaved: root.poem !== null && root.selectedVerse >= 0
        && Core.hasFav(root.savedVerses, Core.verseKey(root.poem.slug, root.selectedVerse))
    readonly property real fontPx: Config.options.diwan.fontSize
    readonly property string family: Config.options.diwan.fontFamily

    /// In a narrow window the text controls fold into one menu, and the dice goes
    readonly property bool compact: root.width < 1000
    readonly property bool tiny: root.width < 720

    // ── loading ──

    function showPoem(slug: string, remember: bool, verse: int): void {
        if (remember && root.poem !== null && root.poem.slug !== slug)
            root.trail = root.trail.concat([root.poem.slug]).slice(-40);
        root.wantSlug = slug;
        root.wantVerse = verse ?? -1;
        root.selectedVerse = -1;
        root.loadingPoem = true;
        root.poemError = "";
        root.mode = "poem";
        poemProc.command = ["python3", "-I", root.script, "poem", slug];
        poemProc.running = true;
    }

    function randomPoem(): void {
        if (root.poem !== null)
            root.trail = root.trail.concat([root.poem.slug]).slice(-40);
        root.wantSlug = "";
        root.wantVerse = -1;
        root.selectedVerse = -1;
        root.loadingPoem = true;
        root.poemError = "";
        root.mode = "poem";
        poemProc.command = ["python3", "-I", root.script, "random"];
        poemProc.running = true;
    }

    function openHome(): void {
        root.mode = "home";
        if (root.homeData.themes === undefined && !root.loadingHome)
            root.fetchHome();
        if (root.daily === null && !dailyProc.running)
            dailyProc.running = true;
        root.refreshRecent();
    }

    function fetchHome(): void {
        root.loadingHome = true;
        root.homeError = "";
        homeProc.command = ["python3", "-I", root.script, "home"];
        homeProc.running = true;
    }

    function refreshRecent(): void {
        const slugs = Core.favList(Config.options.diwan.recent);
        if (slugs.length === 0) {
            root.recentRows = [];
            return;
        }
        recentProc.command = ["python3", "-I", root.script, "library"].concat(slugs);
        recentProc.running = true;
    }

    function openTerm(label: string, kind: string, slug: string): void {
        root.openList(label, ["list", "--" + kind, slug], "", "");
    }

    function openPoet(slug: string, name: string): void {
        root.openList(name, ["list", "--poet", slug], "", "poet");
    }

    function openPoets(query: string): void {
        const q = (query ?? "").trim();
        root.openList(q !== "" ? "الشعراء · " + q : "الشعراء", q !== "" ? ["poets", q] : ["poets"], "", "poets");
    }

    function openList(label: string, base: var, section: string, kind: string): void {
        if (root.mode === "home" || root.mode === "poem")
            root.listFrom = root.mode;
        root.listReq = { label: label, base: base, page: 1, section: section ?? "", kind: kind ?? "" };
        root.mode = "list";
        root.fetchList();
    }

    function fetchList(): void {
        root.loadingList = true;
        root.listError = "";
        const r = root.listReq;
        const base = r.section !== "" ? r.base.concat(["--section", r.section]) : r.base;
        listProc.command = ["python3", "-I", root.script].concat(base, ["--page", String(r.page)]);
        listProc.running = true;
    }

    function search(query: string): void {
        const q = query.trim();
        if (q.length === 0)
            return;
        root.openList(q, ["search", q], "poems", "");
    }

    function openSaved(section: string): void {
        if (root.mode === "home" || root.mode === "poem")
            root.listFrom = root.mode;
        root.savedSection = section === "verses" ? "verses" : "poems";
        root.mode = "saved";
        root.loadingList = true;
        root.listError = "";
        root.listData = {};
        const verses = root.savedSection === "verses";
        listProc.command = ["python3", "-I", root.script, verses ? "verses" : "library"]
            .concat(Core.favList(verses ? root.savedVerses : root.favorites));
        listProc.running = true;
    }

    function back(): void {
        if (root.mode === "list" || root.mode === "saved") {
            root.mode = root.listFrom === "poem" && root.poem === null ? "home" : root.listFrom;
        } else if (root.mode === "poem" && root.trail.length > 0) {
            const slug = root.trail[root.trail.length - 1];
            root.trail = root.trail.slice(0, -1);
            root.showPoem(slug, false, -1);
        }
    }

    function toggleSaved(): void {
        if (root.poem !== null)
            Config.options.diwan.favorites = Core.toggleFav(root.favorites, root.poem.slug);
    }

    function toggleVerse(): void {
        if (root.poem !== null && root.selectedVerse >= 0)
            Config.options.diwan.verses = Core.toggleFav(root.savedVerses, Core.verseKey(root.poem.slug, root.selectedVerse));
    }

    function setSize(px: real): void {
        Config.options.diwan.fontSize = Math.round(Math.max(22, Math.min(60, px)));
    }

    function toggleTashkeel(): void {
        Config.options.diwan.tashkeel = !Config.options.diwan.tashkeel;
    }

    function nextFont(): void {
        Config.options.diwan.fontFamily = root.fonts[(root.fonts.indexOf(root.family) + 1) % root.fonts.length];
    }

    function copyPoem(): void {
        if (root.poem !== null)
            Quickshell.clipboardText = Core.plainText(root.poem);
    }

    function copyVerse(): void {
        if (root.poem !== null && root.selectedVerse >= 0)
            Quickshell.clipboardText = Core.quote(root.poem, root.selectedVerse);
    }

    /// A request that arrived over IPC while the reader was closed or open
    function takePending(): bool {
        const g = GlobalStates;
        if (g.diwanPendingSlug !== "") {
            const slug = g.diwanPendingSlug;
            const verse = g.diwanPendingVerse;
            g.diwanPendingSlug = "";
            g.diwanPendingVerse = -1;
            root.showPoem(slug, true, verse);
            return true;
        }
        if (g.diwanPendingQuery !== "") {
            const q = g.diwanPendingQuery;
            g.diwanPendingQuery = "";
            root.search(q);
            return true;
        }
        if (g.diwanPendingAction === "random") {
            g.diwanPendingAction = "";
            root.randomPoem();
            return true;
        }
        if (g.diwanPendingAction === "saved") {
            g.diwanPendingAction = "";
            root.openSaved("poems");
            return true;
        }
        return false;
    }

    Connections {
        target: GlobalStates
        function onDiwanPendingSlugChanged() { root.takePending(); }
        function onDiwanPendingQueryChanged() { root.takePending(); }
        function onDiwanPendingActionChanged() { root.takePending(); }
    }

    Component.onCompleted: {
        root.fetchHome();
        dailyProc.running = true;
        root.refreshRecent();
        if (root.takePending())
            return;
        // The front page first; the poem last read waits behind its "continue" card
        const last = Config.options.diwan.lastSlug;
        if (last !== "") {
            root.showPoem(last, false, -1);
            root.mode = "home";
        }
    }

    // The layer surface is not focused yet when the reader is created, so ask again once it is
    Timer {
        interval: 120
        running: true
        onTriggered: root.forceActiveFocus()
    }

    /// Reads one helper answer; unreadable output counts as an error answer
    function parse(text: string): var {
        try {
            return JSON.parse(text);
        } catch (e) {
            return { ok: false, error: "أرسلت خدمة الشعر ما لا يمكن قراءته." };
        }
    }

    Process {
        id: poemProc
        stdout: StdioCollector {
            onStreamFinished: {
                const d = root.parse(text);
                if (!d.ok) {
                    root.poemError = d.error;
                } else if (root.wantSlug === "" || d.poem.slug === root.wantSlug) {
                    root.poem = d.poem;
                    root.poemError = "";
                    Config.options.diwan.lastSlug = d.poem.slug;
                    Config.options.diwan.recent = Core.pushRecent(Config.options.diwan.recent, d.poem.slug, 12);
                    if (root.wantVerse >= 0) {
                        root.selectedVerse = root.wantVerse;
                        poemView.focusVerse(root.wantVerse);
                        root.wantVerse = -1;
                    }
                } else {
                    return;  // an answer to a request already replaced
                }
                root.loadingPoem = false;
            }
        }
        onExited: if (root.loadingPoem && !poemProc.running) root.loadingPoem = false
    }

    Process {
        id: homeProc
        stdout: StdioCollector {
            onStreamFinished: {
                const d = root.parse(text);
                if (d.ok)
                    root.homeData = d;
                else
                    root.homeError = d.error;
                root.loadingHome = false;
            }
        }
    }

    Process {
        id: dailyProc
        command: ["python3", "-I", root.script, "daily"]
        stdout: StdioCollector {
            onStreamFinished: {
                const d = root.parse(text);
                if (d.ok)
                    root.daily = d.daily;
            }
        }
    }

    Process {
        id: recentProc
        stdout: StdioCollector {
            onStreamFinished: {
                const d = root.parse(text);
                if (d.ok)
                    root.recentRows = d.poems;
            }
        }
    }

    Process {
        id: listProc
        stdout: StdioCollector {
            onStreamFinished: {
                const d = root.parse(text);
                if (d.ok)
                    root.listData = d;
                else
                    root.listError = d.error;
                root.loadingList = false;
            }
        }
    }

    /// Whichever page is showing, for the scrolling keys
    readonly property var view: root.mode === "poem" ? poemView : root.mode === "home" ? homeView : listView

    // ── keys ──

    // A tap anywhere outside the search field hands the keys back to the reader
    TapHandler {
        gesturePolicy: TapHandler.ReleaseWithinBounds
        grabPermissions: PointerHandler.ApprovesTakeOverByAnything
        onTapped: if (searchField.activeFocus) root.forceActiveFocus()
    }

    Keys.onPressed: event => {
        const k = event.key;
        const mode = root.mode;
        if (k === Qt.Key_Escape) {
            if (root.textMenuOpen)
                root.textMenuOpen = false;
            else if (mode === "poem" && root.selectedVerse >= 0)
                root.selectedVerse = -1;
            else if (mode === "list" || mode === "saved")
                root.back();
            else
                root.closeRequested();
        } else if (k === Qt.Key_Slash || k === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
            searchField.forceActiveFocus();
        } else if (k === Qt.Key_Left) {
            if (mode === "poem" && root.poem?.next)
                root.showPoem(root.poem.next.slug, true, -1);
            else if (mode === "home")
                homeView.navMove(-1, 0);
            else if (mode === "list" && listView.canPage(1))
                listView.pageBy(1);
        } else if (k === Qt.Key_Right) {
            if (mode === "poem" && root.poem?.prev)
                root.showPoem(root.poem.prev.slug, true, -1);
            else if (mode === "home")
                homeView.navMove(1, 0);
            else if (mode === "list" && listView.canPage(-1))
                listView.pageBy(-1);
        } else if (k === Qt.Key_Down) {
            if (mode === "home")
                homeView.navMove(0, 1);
            else if (mode === "poem")
                root.view.scrollBy(140);
            else
                listView.moveCursor(1);
        } else if (k === Qt.Key_Up) {
            if (mode === "home")
                homeView.navMove(0, -1);
            else if (mode === "poem")
                root.view.scrollBy(-140);
            else
                listView.moveCursor(-1);
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            if (mode === "home")
                homeView.navActivate();
            else if (mode !== "poem")
                listView.activateCurrent();
        } else if (k === Qt.Key_Backspace) {
            root.back();
        } else if (k === Qt.Key_H) {
            root.openHome();
        } else if (k === Qt.Key_R) {
            root.randomPoem();
        } else if (k === Qt.Key_S) {
            if (mode === "poem")
                root.toggleSaved();
        } else if (k === Qt.Key_B) {
            if (mode === "poem")
                root.toggleVerse();
        } else if (k === Qt.Key_L) {
            root.openSaved("poems");
        } else if (k === Qt.Key_V) {
            root.openSaved("verses");
        } else if (k === Qt.Key_T) {
            root.toggleTashkeel();
        } else if (k === Qt.Key_C) {
            if (mode === "poem" && root.selectedVerse >= 0)
                root.copyVerse();
            else if (mode === "poem")
                root.copyPoem();
        } else if (k === Qt.Key_Plus || k === Qt.Key_Equal) {
            root.setSize(root.fontPx + 2);
        } else if (k === Qt.Key_Minus) {
            root.setSize(root.fontPx - 2);
        } else if (k === Qt.Key_PageDown || k === Qt.Key_Space) {
            root.view.scrollBy(root.view.height * 0.85);
        } else if (k === Qt.Key_PageUp) {
            root.view.scrollBy(-root.view.height * 0.85);
        } else if (k === Qt.Key_Home) {
            root.view.scrollBy(-Infinity);
        } else if (k === Qt.Key_End) {
            root.view.scrollBy(Infinity);
        } else {
            return;
        }
        event.accepted = true;
    }

    // ── layout ──

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        Item {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 4
            Layout.minimumWidth: 0
            implicitHeight: topBar.implicitHeight

            Rectangle {
                anchors.centerIn: parent
                width: Math.max(150, Math.min(260, root.width - (root.compact ? 500 : 680)))
                height: 40
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer1
                border.width: searchField.activeFocus ? 2 : 0
                border.color: Appearance.colors.colPrimary
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 8
                    layoutDirection: Qt.RightToLeft
                    MaterialSymbol { text: "search"; iconSize: 20; color: Appearance.colors.colSubtext }
                    TextInput {
                        id: searchField
                        Layout.fillWidth: true
                        color: Appearance.colors.colOnLayer0
                        selectByMouse: true
                        clip: true
                        horizontalAlignment: TextInput.AlignRight
                        font.family: root.family
                        font.pixelSize: 20
                        onAccepted: {
                            root.search(text);
                            root.forceActiveFocus();
                        }
                        Keys.onEscapePressed: {
                            text = "";
                            root.forceActiveFocus();
                        }
                        Text {
                            visible: !searchField.text && !searchField.activeFocus
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "ابحث في القصائد والأبيات"
                            font.family: root.family
                            font.pixelSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

        RowLayout {
            id: topBar
            anchors.fill: parent
            spacing: 4

            DiwanButton { icon: "close"; tip: "إغلاق"; onClicked: root.closeRequested() }
            DiwanButton {
                icon: root.windowed ? "fullscreen" : "open_in_new"
                tip: root.windowed ? "ملء الشاشة" : "في نافذة"
                onClicked: root.windowed ? root.overlayRequested() : root.windowRequested()
            }
            DiwanButton {
                icon: "home"
                tip: "الرئيسية"
                active: root.mode === "home"
                onClicked: root.openHome()
            }
            DiwanButton {
                icon: "arrow_back"
                tip: "رجوع"
                enabled: root.mode === "list" || root.mode === "saved" || (root.mode === "poem" && root.trail.length > 0)
                onClicked: root.back()
            }
            DiwanButton {
                visible: !root.tiny
                icon: "casino"
                tip: "قصيدة عشوائية"
                onClicked: root.randomPoem()
            }
            Item { Layout.fillWidth: true; Layout.minimumWidth: 0 }

            DiwanButton {
                icon: "favorite"
                tip: "حفظ القصيدة"
                active: root.isSaved
                enabled: root.poem !== null
                onClicked: root.toggleSaved()
            }
            DiwanButton {
                icon: "bookmarks"
                tip: "المحفوظات"
                active: root.mode === "saved"
                onClicked: root.openSaved("poems")
            }
            // Wide: every text control in the bar. Narrow: one button that opens them
            DiwanButton { visible: !root.compact; icon: "content_copy"; tip: "نسخ القصيدة"; enabled: root.poem !== null; onClicked: root.copyPoem() }
            DiwanButton { visible: !root.compact; icon: "text_decrease"; tip: "تصغير الخط"; onClicked: root.setSize(root.fontPx - 2) }
            DiwanButton { visible: !root.compact; icon: "text_increase"; tip: "تكبير الخط"; onClicked: root.setSize(root.fontPx + 2) }
            DiwanButton { visible: !root.compact; icon: "match_case"; tip: "تبديل الخط"; onClicked: root.nextFont() }
            DiwanButton {
                visible: !root.compact
                icon: "abc"
                tip: root.tashkeel ? "إخفاء التشكيل" : "إظهار التشكيل"
                active: !root.tashkeel
                onClicked: root.toggleTashkeel()
            }
            DiwanButton {
                visible: root.compact
                icon: "format_size"
                tip: "النص"
                active: root.textMenuOpen
                onClicked: root.textMenuOpen = !root.textMenuOpen
            }
        }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            DiwanHome {
                id: homeView
                anchors.fill: parent
                visible: root.mode === "home"
                terms: root.homeData
                poem: root.poem
                daily: root.daily
                recent: root.recentRows.filter(r => r.slug !== root.poem?.slug)
                savedCount: Core.favList(root.favorites).length
                loading: root.loadingHome
                error: root.homeError
                family: root.family
                onOpenTerm: (label, kind, slug) => root.openTerm(label, kind, slug)
                onOpenPoets: root.openPoets("")
                onOpenSaved: root.openSaved("poems")
                onOpenRandom: root.randomPoem()
                onOpenPoem: slug => root.showPoem(slug, true, -1)
                onResume: root.mode = "poem"
                onRetry: root.fetchHome()
            }

            DiwanPoemView {
                id: poemView
                anchors.fill: parent
                visible: root.mode === "poem" && root.poem !== null
                poem: root.poem
                fontPx: root.fontPx
                family: root.family
                tashkeel: root.tashkeel
                selected: root.selectedVerse
                savedVerses: root.savedVerses
                opacity: root.loadingPoem ? 0.35 : 1
                Behavior on opacity { NumberAnimation { duration: Appearance.dur(150) } }
                onOpenPoem: slug => root.showPoem(slug, true, -1)
                onOpenList: (label, base) => root.openList(label, base, "", "")
                onOpenPoet: (slug, name) => root.openPoet(slug, name)
                onVerseClicked: index => {
                    root.selectedVerse = root.selectedVerse === index ? -1 : index;
                    root.forceActiveFocus();
                }
            }

            DiwanList {
                id: listView
                anchors.fill: parent
                visible: root.mode === "list" || root.mode === "saved"
                label: root.mode === "saved" ? "المحفوظات" : root.listReq.label
                kind: root.mode === "saved" ? "saved" : root.listReq.kind
                result: root.listData
                loading: root.loadingList
                error: root.listError
                family: root.family
                sections: root.mode === "saved" ? [{ id: "poems", label: "القصائد" }, { id: "verses", label: "الأبيات" }]
                    : root.mode === "list" && root.listReq.section !== "" ? [{ id: "poems", label: "القصائد" }, { id: "poets", label: "الشعراء" }]
                    : []
                section: root.mode === "saved" ? root.savedSection : root.listReq.section
                paged: root.mode === "list"
                onOpenPoem: (slug, index) => root.showPoem(slug, true, index)
                onOpenPoet: (slug, name) => root.openPoet(slug, name)
                onFilterPoets: query => root.openPoets(query)
                onPageTo: page => {
                    root.listReq = Object.assign({}, root.listReq, { page: page });
                    root.fetchList();
                }
                onSectionTo: section => {
                    if (root.mode === "saved") {
                        root.openSaved(section);
                    } else {
                        root.listReq = Object.assign({}, root.listReq, { section: section, page: 1 });
                        root.fetchList();
                    }
                }
                onRetry: root.mode === "saved" ? root.openSaved(root.savedSection) : root.fetchList()
            }

            // First poem still on its way, or it could not come
            ColumnLayout {
                anchors.centerIn: parent
                visible: root.mode === "poem" && root.poem === null
                spacing: 12
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.poemError !== "" ? "cloud_off" : "auto_stories"
                    iconSize: 44
                    color: Appearance.colors.colSubtext
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: 440
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    font.family: root.family
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colSubtext
                    text: root.poemError !== "" ? root.poemError : "جارٍ اختيار قصيدة…"
                }
                DiwanChip {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.poemError !== ""
                    text: "حاول مرة أخرى"
                    clickable: true
                    onClicked: root.randomPoem()
                }
            }

            // An error over a poem already on show
            Rectangle {
                visible: root.mode === "poem" && root.poem !== null && root.poemError !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 24
                width: Math.min(parent.width - 32, errText.implicitWidth + 36)
                height: 44
                radius: Appearance.rounding.full
                color: Appearance.colors.colErrorContainer
                Text {
                    id: errText
                    anchors.centerIn: parent
                    width: parent.width - 24
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: root.poemError
                    font.family: root.family
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnErrorContainer
                }
            }

            // What you can do with the picked verse
            Rectangle {
                visible: root.mode === "poem" && root.selectedVerse >= 0
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                implicitHeight: 52
                implicitWidth: verseRow.implicitWidth + 24
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                z: 5
                RowLayout {
                    id: verseRow
                    anchors.centerIn: parent
                    spacing: 6
                    layoutDirection: Qt.RightToLeft
                    Text {
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        text: "البيت " + Core.digits(root.selectedVerse + 1)
                        font.family: root.family
                        font.pixelSize: 21
                        color: Appearance.colors.colOnLayer0
                    }
                    DiwanButton { icon: "content_copy"; tip: "نسخ البيت"; onClicked: root.copyVerse() }
                    DiwanButton { icon: "bookmark"; tip: root.verseSaved ? "إزالة من المحفوظات" : "حفظ البيت"; active: root.verseSaved; onClicked: root.toggleVerse() }
                    DiwanButton { icon: "close"; onClicked: root.selectedVerse = -1 }
                }
            }

            // The text controls of a narrow bar
            Rectangle {
                visible: root.textMenuOpen
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 8
                anchors.topMargin: 2
                implicitHeight: 52
                implicitWidth: textRow.implicitWidth + 20
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                z: 10
                RowLayout {
                    id: textRow
                    anchors.centerIn: parent
                    spacing: 4
                    DiwanButton { icon: "content_copy"; tip: "نسخ القصيدة"; enabled: root.poem !== null; onClicked: root.copyPoem() }
                    DiwanButton { icon: "text_decrease"; tip: "تصغير الخط"; onClicked: root.setSize(root.fontPx - 2) }
                    DiwanButton { icon: "text_increase"; tip: "تكبير الخط"; onClicked: root.setSize(root.fontPx + 2) }
                    DiwanButton { icon: "match_case"; tip: "تبديل الخط"; onClicked: root.nextFont() }
                    DiwanButton { icon: "abc"; tip: root.tashkeel ? "إخفاء التشكيل" : "إظهار التشكيل"; active: !root.tashkeel; onClicked: root.toggleTashkeel() }
                }
            }
        }
    }
}
