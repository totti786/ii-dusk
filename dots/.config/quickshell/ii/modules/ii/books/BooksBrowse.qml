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
 * Browse and search book sources (OPDS catalogues: a self-hosted Calibre-Web, Kavita or
 * Komga, or a public library) and download into the library.
 *
 * BooksService owns the sources, the pages and the downloads; this file only draws them.
 */
Item {
    id: root

    property bool addOpen: false
    property bool confirmRemove: false
    property bool zlibOpen: false
    readonly property var page: BooksService.browsePage
    readonly property var detail: root.page?.detail ?? null
    readonly property var books: (root.page?.entries ?? []).filter(e => e.kind === "book")
    readonly property var navs: (root.page?.entries ?? []).filter(e => e.kind === "nav")
    readonly property bool canSearch: BooksService.browseStack.length > 0 && BooksService.browseStack[0].page.search === true
    readonly property bool zlibLoggedOut: BooksService.source?.id === "zlib" && root.page?.loggedIn === false
    readonly property bool mangaSource: BooksService.source?.kind === "manga"

    signal openPath(string path)

    /// Escape steps out one level: the form, then the book page, then the browse view itself.
    function stepBack(): bool {
        if (root.zlibOpen) {
            root.zlibOpen = false;
            return true;
        }
        if (root.addOpen) {
            root.addOpen = false;
            return true;
        }
        if (BooksService.canGoBack) {
            BooksService.browseBack();
            return true;
        }
        return false;
    }

    function formatSize(bytes: real): string {
        if (!bytes || bytes <= 0)
            return "";
        if (bytes < 1024 * 1024)
            return Math.max(1, Math.round(bytes / 1024)) + " KB";
        return (bytes / (1024 * 1024)).toFixed(1) + " MB";
    }

    function focusSearch(): void {
        search.forceActiveFocus();
    }

    Component.onCompleted: {
        if (BooksService.sources.length === 0)
            BooksService.refreshSources();
    }

    onPageChanged: root.confirmRemove = false

    ColumnLayout {
        anchors.fill: parent
        spacing: ClockStyle.paneGap

        Flow {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall

            Repeater {
                model: BooksService.sources

                delegate: ClockChip {
                    required property var modelData
                    symbol: modelData.builtin ? "public" : (modelData.user.length > 0 ? "lock" : "dns")
                    label: modelData.name
                    selected: BooksService.sourceId === modelData.id
                    onClicked: BooksService.selectSource(modelData.id)
                }
            }

            ClockChip {
                symbol: "add"
                label: Translation.tr("Add source")
                onClicked: root.addOpen = true
            }

            ClockChip {
                visible: BooksService.source?.id === "zlib"
                symbol: "settings"
                label: Translation.tr("Z-Library settings")
                onClicked: root.zlibOpen = true
            }

            ClockChip {
                visible: BooksService.source !== null && !BooksService.source.builtin
                symbol: "delete"
                label: root.confirmRemove ? Translation.tr("Click again to remove") : Translation.tr("Remove source")
                onClicked: {
                    if (root.confirmRemove)
                        BooksService.removeSource(BooksService.sourceId);
                    else
                        root.confirmRemove = true;
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall

            ClockIconButton {
                visible: BooksService.canGoBack
                symbol: "arrow_back"
                tooltip: Translation.tr("Back")
                onClicked: BooksService.browseBack()
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 46
                radius: ClockStyle.radiusLarge
                color: search.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField
                opacity: root.canSearch ? 1 : 0.5

                MaterialSymbol {
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
                    enabled: root.canSearch
                    verticalAlignment: TextInput.AlignVCenter
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: ClockStyle.colOnSurface
                    onAccepted: BooksService.browseSearch(text)
                }

                StyledText {
                    anchors {
                        fill: parent
                        leftMargin: 46
                        rightMargin: 14
                    }
                    verticalAlignment: Text.AlignVCenter
                    visible: search.text.length === 0
                    text: root.canSearch
                        ? Translation.tr("Search %1  (Enter)").arg(BooksService.source?.name ?? "")
                        : Translation.tr("This source has no search")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1Inactive
                }
            }

            ClockIconButton {
                symbol: "home"
                tooltip: Translation.tr("Start page")
                onClicked: {
                    search.text = "";
                    BooksService.browseHome();
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: ClockStyle.radiusLarge
            color: ClockStyle.colPane
            clip: true

            // ---- A catalogue page: navigation rows and a cover grid ----
            ColumnLayout {
                anchors {
                    fill: parent
                    margins: ClockStyle.gap
                }
                spacing: ClockStyle.gap
                visible: root.detail === null && root.page !== null && (root.books.length > 0 || root.navs.length > 0)

                StyledText {
                    Layout.leftMargin: 8
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.page?.title ?? ""
                    elide: Text.ElideRight
                    color: ClockStyle.colOnSurface
                    font.pixelSize: ClockStyle.textLarge
                    font.weight: Font.DemiBold
                }

                // Categories and the like. With books beside them they stay a short strip.
                Flow {
                    Layout.fillWidth: true
                    Layout.maximumHeight: 84
                    clip: true
                    visible: root.navs.length > 0 && root.books.length > 0
                    spacing: ClockStyle.gapSmall

                    Repeater {
                        model: root.books.length > 0 ? root.navs.slice(0, 16) : []

                        delegate: ClockChip {
                            required property var modelData
                            symbol: "folder"
                            label: modelData.title
                            onClicked: BooksService.browseOpen(modelData.href)
                        }
                    }
                }

                ListView {
                    WheelScroll {}
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.books.length === 0
                    clip: true
                    spacing: 4
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.books.length === 0 ? root.navs : []

                    delegate: Rectangle {
                        id: navRow
                        required property var modelData
                        width: ListView.view.width
                        height: 56
                        radius: ClockStyle.radiusCard
                        color: navPointer.containsMouse ? ClockStyle.colSurfaceHover : ClockStyle.colSurfaceHigh

                        MouseArea {
                            id: navPointer
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: BooksService.browseOpen(navRow.modelData.href)
                        }

                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 16
                                rightMargin: 16
                            }
                            spacing: 12

                            MaterialSymbol {
                                text: navRow.modelData.subtitle.length > 0 && !navRow.modelData.subtitle.endsWith(".") ? "menu_book" : "folder"
                                iconSize: 22
                                color: ClockStyle.colPrimary
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: navRow.modelData.title
                                elide: Text.ElideRight
                                color: ClockStyle.colOnSurface
                                font.pixelSize: ClockStyle.textNormal
                                font.weight: Font.Medium
                            }

                            StyledText {
                                Layout.maximumWidth: 300
                                visible: text.length > 0
                                text: navRow.modelData.subtitle
                                elide: Text.ElideRight
                                color: ClockStyle.colSubtext
                                font.pixelSize: ClockStyle.textSmall
                            }

                            MaterialSymbol {
                                text: "chevron_right"
                                iconSize: 20
                                color: ClockStyle.colSubtext
                            }
                        }
                    }
                }

                GridView {
                    WheelScroll {}
                    id: grid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.books.length > 0
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.books

                    readonly property int columns: Math.max(2, Math.floor(width / 172))
                    cellWidth: Math.floor(width / columns)
                    cellHeight: Math.round(cellWidth * 1.5) + 84

                    delegate: RemoteBookCard {
                        required property var modelData
                        book: modelData
                        width: grid.cellWidth
                        height: grid.cellHeight
                        onActivated: root.mangaSource
                            ? BooksService.browseOpen(modelData.href)
                            : BooksService.browseShow(modelData)
                    }
                }

                ClockButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: (root.page?.next ?? "").length > 0
                    symbol: "expand_more"
                    label: BooksService.browseLoading ? Translation.tr("Loading…") : Translation.tr("Load more")
                    enabled: !BooksService.browseLoading
                    onClicked: BooksService.browseMore()
                }
            }

            // ---- One manga: cover, chapters, downloads ----
            BooksManga {
                anchors.fill: parent
                visible: root.detail !== null && root.mangaSource
                detail: root.detail
                onOpenPath: path => root.openPath(path)
            }

            // ---- One book: cover, details, formats to download ----
            RowLayout {
                anchors {
                    fill: parent
                    margins: 24
                }
                spacing: 28
                visible: root.detail !== null && !root.mangaSource

                BookCover {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: 220
                    Layout.preferredHeight: 330
                    source: root.detail?.cover ?? ""
                    title: root.detail?.title ?? ""
                    format: ""
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    StyledText {
                        Layout.fillWidth: true
                        text: root.detail?.title ?? ""
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        color: ClockStyle.colOnSurface
                        font.pixelSize: 26
                        font.weight: Font.DemiBold
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: root.detail?.author ?? ""
                        elide: Text.ElideRight
                        color: ClockStyle.colPrimary
                        font.pixelSize: ClockStyle.textLarge
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: (root.detail?.formats ?? []).length === 0
                        text: Translation.tr("No format the viewers can open (EPUB, PDF, DJVU, CBZ) is offered for this book.")
                        wrapMode: Text.WordWrap
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textNormal
                    }

                    Repeater {
                        model: (root.detail?.formats ?? []).slice(0, 6)

                        delegate: FormatRow {
                            required property var modelData
                            Layout.fillWidth: true
                            book: root.detail
                            format: modelData
                        }
                    }

                    Flickable {
                        WheelScroll {}
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.topMargin: 6
                        clip: true
                        contentHeight: summaryText.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        visible: (root.detail?.summary ?? "").length > 0

                        StyledText {
                            id: summaryText
                            width: parent.width
                            text: root.detail?.summary ?? ""
                            wrapMode: Text.WordWrap
                            color: ClockStyle.colOnSurface
                            font.pixelSize: ClockStyle.textNormal
                            lineHeight: 1.15
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                        visible: (root.detail?.summary ?? "").length === 0
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall
                        visible: (root.detail?.related ?? []).length > 0

                        Repeater {
                            model: (root.detail?.related ?? []).slice(0, 6)

                            delegate: ClockChip {
                                required property var modelData
                                symbol: "arrow_forward"
                                label: modelData.title
                                onClicked: BooksService.browseOpen(modelData.href)
                            }
                        }
                    }
                }
            }

            // ---- Loading, errors, empty ----
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(520, parent.width - 40)
                visible: root.detail === null && (root.page === null || (root.books.length === 0 && root.navs.length === 0))
                spacing: ClockStyle.gap

                ClockEmptyState {
                    Layout.alignment: Qt.AlignHCenter
                    symbol: root.zlibLoggedOut ? "login"
                        : BooksService.browseLoading || (root.page === null && BooksService.browseError.length === 0) ? "hourglass_top"
                        : BooksService.browseError.length > 0 ? "cloud_off"
                        : root.mangaSource ? "travel_explore" : "search_off"
                    title: root.zlibLoggedOut ? Translation.tr("Sign in to Z-Library")
                        : BooksService.browseLoading || (root.page === null && BooksService.browseError.length === 0) ? Translation.tr("Contacting the source")
                        : BooksService.browseError.length > 0 ? Translation.tr("Could not load this page")
                        : root.mangaSource ? Translation.tr("Search manga")
                        : Translation.tr("Nothing here")
                    subtitle: root.zlibLoggedOut ? (root.page?.message ?? Translation.tr("Log in to search and download."))
                        : BooksService.browseError.length > 0 ? BooksService.browseError
                        : BooksService.browseLoading ? ""
                        : root.mangaSource ? (root.page?.message ?? Translation.tr("Search for a manga above."))
                        : Translation.tr("Try another search.")
                }

                ClockButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.zlibLoggedOut
                    symbol: "login"
                    label: Translation.tr("Log in to Z-Library")
                    variant: "filled"
                    onClicked: root.zlibOpen = true
                }

                ClockButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: BooksService.browseError.length > 0
                    symbol: "refresh"
                    label: Translation.tr("Try again")
                    onClicked: BooksService.canGoBack ? BooksService.browseBack() : BooksService.browseHome()
                }
            }

            // Busy marker while a page loads over one that is already showing.
            Rectangle {
                anchors {
                    top: parent.top
                    horizontalCenter: parent.horizontalCenter
                    topMargin: 10
                }
                visible: BooksService.browseLoading && root.page !== null
                z: 5
                radius: 15
                height: 30
                width: busyLabel.implicitWidth + 28
                color: ClockStyle.colSurfaceHighest

                StyledText {
                    id: busyLabel
                    anchors.centerIn: parent
                    text: Translation.tr("Loading…")
                    color: ClockStyle.colOnSurface
                    font.pixelSize: ClockStyle.textSmall
                }
            }
        }
    }

    // ---- Add a source ----
    Rectangle {
        anchors.fill: parent
        visible: root.addOpen
        z: 10
        color: ClockStyle.colScrim
        opacity: 0.45

        MouseArea {
            anchors.fill: parent
            onClicked: root.addOpen = false
        }
    }

    Rectangle {
        id: addCard
        visible: root.addOpen
        z: 11
        anchors.centerIn: parent
        width: Math.min(560, parent.width - 40)
        height: addColumn.implicitHeight + 40
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colSurfaceHighest

        property string errorText: ""
        property bool working: false

        onVisibleChanged: {
            if (visible) {
                nameField.text = "";
                urlField.text = "";
                userField.text = "";
                passwordField.text = "";
                addCard.errorText = "";
                addCard.working = false;
                urlField.forceActiveFocus();
            }
        }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: addColumn
            anchors {
                fill: parent
                margins: 20
            }
            spacing: 12

            StyledText {
                text: Translation.tr("Add a book source")
                color: ClockStyle.colOnSurface
                font.pixelSize: ClockStyle.textLarge
                font.weight: Font.DemiBold
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Translation.tr("Any OPDS catalogue: Calibre-Web (http://host:8083/opds), Calibre content server (http://host:8080/opds), Kavita, Komga or COPS. Passwords go in the system keyring.")
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
            }

            AddField {
                id: urlField
                Layout.fillWidth: true
                caption: Translation.tr("Catalogue address")
                placeholder: "http://192.168.1.20:8083/opds"
                onAccepted: nameField.forceActiveFocus()
            }

            AddField {
                id: nameField
                Layout.fillWidth: true
                caption: Translation.tr("Name (optional)")
                placeholder: Translation.tr("Home library")
                onAccepted: userField.forceActiveFocus()
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                AddField {
                    id: userField
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    caption: Translation.tr("Username (if it needs a login)")
                    placeholder: ""
                    onAccepted: passwordField.forceActiveFocus()
                }

                AddField {
                    id: passwordField
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    caption: Translation.tr("Password")
                    placeholder: ""
                    secret: true
                    onAccepted: addCard.submit()
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: addCard.errorText.length > 0
                wrapMode: Text.WordWrap
                text: addCard.errorText
                color: Appearance.colors.colError
                font.pixelSize: ClockStyle.textSmall
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: ClockStyle.gapSmall

                ClockButton {
                    label: Translation.tr("Cancel")
                    variant: "text"
                    onClicked: root.addOpen = false
                }

                ClockButton {
                    label: addCard.working ? Translation.tr("Adding…") : Translation.tr("Add")
                    symbol: "add"
                    variant: "filled"
                    enabled: !addCard.working && urlField.text.trim().length > 0
                    onClicked: addCard.submit()
                }
            }
        }

        function submit(): void {
            if (addCard.working || urlField.text.trim().length === 0)
                return;
            addCard.working = true;
            addCard.errorText = "";
            BooksService.addSource(nameField.text, urlField.text.trim(), userField.text.trim(), passwordField.text, (ok, message) => {
                addCard.working = false;
                if (ok)
                    root.addOpen = false;
                else
                    addCard.errorText = message;
            });
        }
    }

    // ---- Z-Library account + settings ----
    Rectangle {
        anchors.fill: parent
        visible: root.zlibOpen
        z: 12
        color: ClockStyle.colScrim
        opacity: 0.45

        MouseArea {
            anchors.fill: parent
            onClicked: root.zlibOpen = false
        }
    }

    Rectangle {
        id: zlibCard
        visible: root.zlibOpen
        z: 13
        anchors.centerIn: parent
        width: Math.min(560, parent.width - 40)
        height: zlibColumn.implicitHeight + 40
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colSurfaceHighest

        property bool working: false
        property string errorText: ""
        readonly property bool signedIn: root.page?.loggedIn === true

        onVisibleChanged: {
            if (visible) {
                zlibCard.errorText = "";
                zlibCard.working = false;
                emailField.text = "";
                zlibPasswordField.text = "";
                domainField.text = "";
                const configured = String(Config.options.books?.zlibDownloadDir ?? "").trim();
                folderField.text = configured.length > 0 ? configured
                    : `${BooksService.libraryDir}/Downloaded/Z-Library`;
                BooksService.zlibSettings(data => {
                    if (data && data.domain)
                        domainField.text = data.domain;
                });
                if (zlibCard.signedIn)
                    folderField.forceActiveFocus();
                else
                    emailField.forceActiveFocus();
            }
        }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: zlibColumn
            anchors {
                fill: parent
                margins: 20
            }
            spacing: 12

            StyledText {
                text: Translation.tr("Z-Library")
                color: ClockStyle.colOnSurface
                font.pixelSize: ClockStyle.textLarge
                font.weight: Font.DemiBold
            }

            StyledText {
                Layout.fillWidth: true
                visible: !zlibCard.signedIn
                text: Translation.tr("Sign in with your Z-Library account. Credentials go straight to books-cli over stdin and are never stored by the shell.")
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
                wrapMode: Text.WordWrap
            }

            StyledText {
                Layout.fillWidth: true
                visible: zlibCard.signedIn
                text: root.page?.title ?? Translation.tr("Signed in. Credentials are managed by books-cli.")
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
                wrapMode: Text.WordWrap
            }

            AddField {
                id: emailField
                Layout.fillWidth: true
                visible: !zlibCard.signedIn
                caption: Translation.tr("Email")
                placeholder: ""
                onAccepted: zlibPasswordField.forceActiveFocus()
            }

            AddField {
                id: zlibPasswordField
                Layout.fillWidth: true
                visible: !zlibCard.signedIn
                caption: Translation.tr("Password")
                placeholder: ""
                secret: true
                onAccepted: zlibCard.login()
            }

            AddField {
                id: domainField
                Layout.fillWidth: true
                caption: Translation.tr("Domain")
                placeholder: "zlibrary-global.se"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                AddField {
                    id: folderField
                    Layout.fillWidth: true
                    caption: Translation.tr("Download folder")
                    placeholder: ""
                }

                ClockButton {
                    Layout.alignment: Qt.AlignBottom
                    label: Translation.tr("Choose…")
                    symbol: "folder_open"
                    variant: "text"
                    enabled: !zlibCard.working
                    onClicked: BooksService.zlibPickFolder(folderField.text.trim(), path => folderField.text = path)
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: {
                    const value = folderField.text.trim();
                    return value.length > 0 && !BooksService._expandPath(value).startsWith(BooksService.libraryDir);
                }
                text: Translation.tr("Outside the library — downloads won't appear in Books, but “Read now” still opens them.")
                color: Appearance.colors.colError
                font.pixelSize: ClockStyle.textSmall
                wrapMode: Text.WordWrap
            }

            StyledText {
                Layout.fillWidth: true
                visible: zlibCard.errorText.length > 0
                text: zlibCard.errorText
                color: Appearance.colors.colError
                font.pixelSize: ClockStyle.textSmall
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: ClockStyle.gapSmall

                ClockButton {
                    label: Translation.tr("Cancel")
                    variant: "text"
                    onClicked: root.zlibOpen = false
                }

                ClockButton {
                    visible: !zlibCard.signedIn
                    label: zlibCard.working ? Translation.tr("Signing in…") : Translation.tr("Log in")
                    symbol: "login"
                    variant: "filled"
                    enabled: !zlibCard.working && emailField.text.trim().length > 0 && zlibPasswordField.text.length > 0
                    onClicked: zlibCard.login()
                }

                ClockButton {
                    label: zlibCard.working ? Translation.tr("Saving…") : Translation.tr("Save")
                    symbol: "save"
                    variant: "filled"
                    enabled: !zlibCard.working && domainField.text.trim().length > 0
                    onClicked: zlibCard.save()
                }
            }
        }

        function login(): void {
            if (zlibCard.working || emailField.text.trim().length === 0 || zlibPasswordField.text.length === 0)
                return;
            zlibCard.working = true;
            zlibCard.errorText = "";
            BooksService.zlibLogin(emailField.text, zlibPasswordField.text, domainField.text.trim(), (ok, message) => {
                zlibCard.working = false;
                if (!ok) {
                    zlibCard.errorText = message;
                    return;
                }
                zlibPasswordField.text = "";
                root.zlibOpen = false;
                BooksService.selectSource("zlib");
            });
        }

        function save(): void {
            if (zlibCard.working || domainField.text.trim().length === 0)
                return;
            zlibCard.working = true;
            zlibCard.errorText = "";
            BooksService.zlibSaveSettings(domainField.text.trim(), (ok, message) => {
                if (!ok) {
                    zlibCard.working = false;
                    zlibCard.errorText = message;
                    return;
                }
                Config.options.books.zlibDownloadDir = folderField.text.trim();
                zlibCard.working = false;
                root.zlibOpen = false;
                BooksService.selectSource("zlib");
            });
        }
    }

    component AddField: ColumnLayout {
        id: field

        property string caption: ""
        property string placeholder: ""
        property bool secret: false
        property alias text: input.text

        signal accepted()

        function forceActiveFocus(): void {
            input.forceActiveFocus();
        }

        spacing: 6

        StyledText {
            text: field.caption
            color: ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textSmall
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 44
            radius: ClockStyle.radiusLarge
            color: input.activeFocus ? ClockStyle.colSurfaceHigh : ClockStyle.colSurface
            border.width: 1
            border.color: input.activeFocus ? ClockStyle.colPrimary : ClockStyle.colOutline

            StyledTextInput {
                id: input
                anchors {
                    fill: parent
                    leftMargin: 14
                    rightMargin: 14
                }
                verticalAlignment: TextInput.AlignVCenter
                echoMode: field.secret ? TextInput.Password : TextInput.Normal
                font.pixelSize: Appearance.font.pixelSize.small
                color: ClockStyle.colOnSurface
                clip: true
                onAccepted: field.accepted()
            }

            StyledText {
                anchors {
                    fill: parent
                    leftMargin: 14
                    rightMargin: 14
                }
                verticalAlignment: Text.AlignVCenter
                visible: input.text.length === 0 && field.placeholder.length > 0
                text: field.placeholder
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1Inactive
            }
        }
    }

    /// One downloadable edition: a button that becomes a progress bar, then "Open".
    component FormatRow: RowLayout {
        id: formatRow

        required property var book
        required property var format
        readonly property var download: BooksService.downloads[formatRow.format.href] ?? null
        readonly property string status: formatRow.download?.state ?? "idle"
        readonly property real fraction: (formatRow.download?.total ?? 0) > 0
            ? Math.min(1, formatRow.download.received / formatRow.download.total) : -1

        spacing: ClockStyle.gap

        ClockButton {
            Layout.preferredWidth: 520
            symbol: formatRow.status === "done" ? "check" : "download"
            variant: formatRow.status === "idle" || formatRow.status === "error" ? "filled" : "tonal"
            enabled: formatRow.status !== "running"
            label: {
                const kind = formatRow.format.label.length > 0 ? formatRow.format.label : formatRow.format.ext.toUpperCase();
                const size = root.formatSize(formatRow.format.size);
                const detail = [kind, size].filter(part => part.length > 0).join("  ·  ");
                return formatRow.status === "done" ? Translation.tr("Saved  ·  %1").arg(detail) : detail;
            }
            onClicked: BooksService.download(formatRow.book, formatRow.format)
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: formatRow.status === "running" || formatRow.status === "error"

            Rectangle {
                Layout.fillWidth: true
                visible: formatRow.status === "running"
                implicitHeight: 6
                radius: 3
                color: ClockStyle.colSurfaceHighest

                Rectangle {
                    width: parent.width * Math.max(0.03, formatRow.fraction)
                    height: parent.height
                    radius: parent.radius
                    color: ClockStyle.colPrimary
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: formatRow.status === "error"
                    ? (formatRow.download?.error ?? "")
                    : (formatRow.fraction >= 0
                        ? Translation.tr("Downloading  %1%").arg(Math.round(formatRow.fraction * 100))
                        : Translation.tr("Downloading…"))
                elide: Text.ElideRight
                color: formatRow.status === "error" ? Appearance.colors.colError : ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
            }
        }

        ClockButton {
            visible: formatRow.status === "done"
            symbol: "menu_book"
            label: Translation.tr("Read now")
            variant: "filled"
            onClicked: root.openPath(formatRow.download.path)
        }

        Item {
            Layout.fillWidth: true
            visible: formatRow.status === "idle" || formatRow.status === "done"
        }
    }
}
