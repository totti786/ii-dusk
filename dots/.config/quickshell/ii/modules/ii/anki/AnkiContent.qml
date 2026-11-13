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
 * The Anki reviewer window: deck navigation, the card surface, settings and states.
 *
 * AnkiService owns the bridge and the collection; this file only decides what to show.
 */
FocusScope {
    id: root

    signal closeRequested()

    focus: true
    property string collectionOverride: ""
    readonly property bool compact: root.width < 1000
    readonly property bool shown: root.Window.window?.visible ?? true
    readonly property bool settingsOpen: sidePanel.open
    readonly property Item settingsSheet: sidePanel.current
    property bool decksOpen: false
    property bool helpOpen: false

    function findDeckName(node, deckId): string {
        if (!node)
            return "";
        if (Number(node.id) === Number(deckId))
            return String(node.name);
        const children = node.children ?? [];
        for (const child of children) {
            const name = root.findDeckName(child, deckId);
            if (name.length > 0)
                return name;
        }
        return "";
    }

    function deckTitle(): string {
        if (AnkiService.card && String(AnkiService.card.deckName ?? "").length > 0)
            return String(AnkiService.card.deckName);
        const found = root.findDeckName(AnkiService.decks, AnkiService.currentDeckId);
        return found.length > 0 ? found : Translation.tr("Anki Review");
    }

    function countsText(): string {
        const c = AnkiService.counts ?? {};
        return Translation.tr("%1 new · %2 learning · %3 review")
            .arg(Number(c.new ?? 0))
            .arg(Number(c.learn ?? 0))
            .arg(Number(c.review ?? 0));
    }

    function errorTitle(): string {
        switch (AnkiService.errorCode) {
        case "collection_locked": return Translation.tr("Anki is open");
        case "anki_missing": return Translation.tr("The Anki engine is not installed");
        case "collection_missing": return Translation.tr("Collection not found");
        case "unsupported_version": return Translation.tr("Unsupported Anki version");
        case "no_profiles": return Translation.tr("No Anki profile found");
        default: return Translation.tr("Could not open Anki");
        }
    }

    function errorSubtitle(): string {
        switch (AnkiService.errorCode) {
        case "collection_locked":
            return Translation.tr("Close Anki desktop, then retry. Only one program can write to a collection at a time.");
        case "anki_missing":
            if (AnkiService.installingEngine)
                return AnkiService.installStep + "…";
            if (AnkiService.installError.length > 0)
                return Translation.tr("The install failed: %1").arg(AnkiService.installError);
            return Translation.tr("The app runs on its own copy of Anki's engine (about 75 MB, installed once). It does not need Anki desktop.");
        default:
            return AnkiService.errorMessage.length > 0
                ? AnkiService.errorMessage
                : Translation.tr("The Anki helper could not open the collection.");
        }
    }

    function openSettings(): void {
        root.toggleSheet(settingsComponent);
    }

    function openSync(): void {
        root.toggleSheet(syncComponent);
    }

    function openAdd(): void {
        root.toggleSheet(addComponent);
    }

    /// Show a sheet in the side panel; asking for the one already there closes it.
    function toggleSheet(component): void {
        if (sidePanel.isShowing(component)) {
            sidePanel.close();
            return;
        }
        sidePanel.show(component, {});
    }

    function openInAnki(): void {
        AnkiService.stop();
        GlobalStates.ankiOpen = false;
        Quickshell.execDetached(["bash", "-c", "sleep 1.2; command -v anki >/dev/null 2>&1 && exec anki"]);
    }

    function retry(): void {
        AnkiService.retry();
    }

    Component.onCompleted: {
        AnkiService.collectionOverride = root.collectionOverride;
        AnkiService.start();
    }

    // The window reports "not visible" while it is still being created. Only a window that
    // has been on screen and then hidden releases the collection.
    property bool wasShown: false

    onShownChanged: {
        if (root.shown) {
            root.wasShown = true;
            AnkiService.collectionOverride = root.collectionOverride;
            AnkiService.start();
        } else if (root.wasShown) {
            AnkiService.stop();
        }
    }

    Connections {
        target: AnkiService

        function onOpened() {
            if (GlobalStates.ankiPendingDeck > 0) {
                const deckId = GlobalStates.ankiPendingDeck;
                GlobalStates.ankiPendingDeck = 0;
                AnkiService.selectDeck(deckId);
            } else {
                AnkiService.requestCard();
            }
        }
    }

    // The app is already open and an IPC/launcher request names another deck.
    Connections {
        target: GlobalStates

        function onAnkiPendingDeckChanged() {
            if (GlobalStates.ankiPendingDeck <= 0)
                return;
            if (AnkiService.phase === "starting" || AnkiService.phase === "closed" || AnkiService.phase === "error")
                return;
            const deckId = GlobalStates.ankiPendingDeck;
            GlobalStates.ankiPendingDeck = 0;
            AnkiService.selectDeck(deckId);
        }
    }

    // Shortcuts follow Anki desktop where it has one. The scan codes are the physical keys
    // (X11 keycodes), so letters keep working on a non-Latin layout such as Arabic.
    function isKey(event, qtKey: int, scanCode: int): bool {
        return event.key === qtKey || event.nativeScanCode === scanCode;
    }

    function focusDeckSearch(): void {
        if (root.compact)
            root.decksOpen = true;
        (root.compact ? drawerSidebar : sidebar).focusSearch();
    }

    function selectRelativeDeck(delta: int): void {
        sidebar.selectRelative(delta);
    }

    function gradeButton(rating: int): void {
        const buttons = AnkiService.answer?.buttons ?? [];
        if (buttons.some(button => button.rating === rating))
            AnkiService.submitAnswer(rating);
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const reviewing = AnkiService.phase === "question" || AnkiService.phase === "answer";

        if (ctrl && (event.key === Qt.Key_W || event.key === Qt.Key_Q)) {
            root.closeRequested();
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Escape) {
            if (root.helpOpen)
                root.helpOpen = false;
            else if (root.settingsOpen)
                sidePanel.close();
            else if (root.decksOpen)
                root.decksOpen = false;
            else
                root.closeRequested();
            event.accepted = true;
            return;
        }

        if (root.helpOpen) {
            // Any other key just dismisses the cheat sheet.
            root.helpOpen = false;
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_F1 || event.text === "?") {
            root.helpOpen = true;
            event.accepted = true;
            return;
        }

        if (ctrl) {
            if (event.key === Qt.Key_F || event.key === Qt.Key_L) {
                root.focusDeckSearch();
            } else if (root.isKey(event, Qt.Key_Z, 52) && !(event.modifiers & Qt.ShiftModifier)) {
                if (AnkiService.phase === "question" && !AnkiService.busy)
                    AnkiService.undo();
            } else if (event.key === Qt.Key_Comma) {
                root.openSettings();
            } else if (event.key === Qt.Key_N) {
                root.openAdd();
            } else if (event.key === Qt.Key_Y) {
                root.openSync();
            } else if (event.key === Qt.Key_O) {
                root.openInAnki();
            } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_4 && reviewing) {
                AnkiService.cardAction("flag", event.key - Qt.Key_0);
            } else {
                return;
            }
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Slash) {
            root.focusDeckSearch();
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_BracketLeft || event.key === Qt.Key_BracketRight) {
            root.selectRelativeDeck(event.key === Qt.Key_BracketLeft ? -1 : 1);
            event.accepted = true;
            return;
        }

        if (!reviewing) {
            if (event.key === Qt.Key_R && AnkiService.phase === "done")
                AnkiService.requestCard();
            return;
        }

        const confirm = event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
        if (AnkiService.phase === "question") {
            if (confirm && !reviewPane.typing) {
                AnkiService.reveal(reviewPane.typedText);
                event.accepted = true;
                return;
            }
        } else if (confirm) {
            // As in Anki: Space (or Enter) answers "Good".
            root.gradeButton(2);
            event.accepted = true;
            return;
        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_4) {
            const buttons = AnkiService.answer?.buttons ?? [];
            const index = event.key - Qt.Key_1;
            if (index < buttons.length)
                AnkiService.submitAnswer(buttons[index].rating);
            event.accepted = true;
            return;
        }

        if (root.isKey(event, Qt.Key_Z, 52) || root.isKey(event, Qt.Key_U, 30)) {
            if (AnkiService.phase === "question" && !AnkiService.busy)
                AnkiService.undo();
        } else if (root.isKey(event, Qt.Key_R, 27) || event.key === Qt.Key_F5) {
            reviewPane.replayAudio();
        } else if (event.text === "*") {
            AnkiService.cardAction("mark");
        } else if (event.text === "@") {
            AnkiService.cardAction("suspend");
        } else if (event.text === "!") {
            AnkiService.cardAction("suspendNote");
        } else if (event.text === "-") {
            AnkiService.cardAction("bury");
        } else if (event.text === "=") {
            AnkiService.cardAction("buryNote");
        } else {
            return;
        }
        event.accepted = true;
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
            title: Translation.tr("Anki Review")
            subtitle: root.deckTitle() + "  ·  " + root.countsText()
            onCloseRequested: root.closeRequested()

            ClockIconButton {
                visible: root.compact
                symbol: "view_list"
                tooltip: Translation.tr("Decks")
                onClicked: root.decksOpen = !root.decksOpen
            }

            ClockIconButton {
                symbol: "keyboard"
                tooltip: Translation.tr("Keyboard shortcuts (?)")
                onClicked: root.helpOpen = !root.helpOpen
            }

            ClockIconButton {
                symbol: "undo"
                tooltip: Translation.tr("Undo last answer")
                enabled: AnkiService.phase === "question" && !AnkiService.busy
                onClicked: AnkiService.undo()
            }

            ClockIconButton {
                symbol: "open_in_new"
                tooltip: Translation.tr("Open in Anki")
                onClicked: root.openInAnki()
            }

            ClockIconButton {
                symbol: "note_add"
                tooltip: Translation.tr("Add a note, make a deck, import (Ctrl+N)")
                onClicked: root.openAdd()
            }

            ClockIconButton {
                symbol: AnkiService.syncing ? "sync" : (AnkiService.loggedIn ? "cloud_sync" : "cloud_off")
                tooltip: AnkiService.loggedIn ? Translation.tr("Sync with AnkiWeb (Ctrl+Y)") : Translation.tr("Sign in to AnkiWeb (Ctrl+Y)")
                onClicked: root.openSync()
            }

            ClockIconButton {
                symbol: "settings"
                tooltip: Translation.tr("Anki settings")
                onClicked: root.openSettings()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            DeckSidebar {
                id: sidebar
                Layout.fillHeight: true
                Layout.preferredWidth: 270
                Layout.rightMargin: ClockStyle.paneGap
                visible: !root.compact
                decks: AnkiService.decks
                currentDeckId: AnkiService.currentDeckId
                onDeckSelected: deckId => AnkiService.selectDeck(deckId)
                onSearchDismissed: root.forceActiveFocus()
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ReviewPane {
                    id: reviewPane
                    anchors.fill: parent
                    visible: AnkiService.phase === "question" || AnkiService.phase === "answer"
                    card: AnkiService.card
                    answer: AnkiService.answer
                    phase: AnkiService.phase
                    busy: AnkiService.busy
                    autoPlayAudio: Config.options.anki.autoPlayAudio
                    counts: AnkiService.counts
                    onRevealRequested: typed => AnkiService.reveal(typed)
                    onAnswerRequested: rating => AnkiService.submitAnswer(rating)
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(560, parent.width - 40)
                    spacing: ClockStyle.gap
                    visible: AnkiService.phase === "done"

                    ClockEmptyState {
                        Layout.alignment: Qt.AlignHCenter
                        symbol: "check_circle"
                        title: Translation.tr("No cards due")
                        subtitle: Translation.tr("%1 new · %2 learning · %3 review remaining")
                            .arg(Number(AnkiService.counts.new ?? 0))
                            .arg(Number(AnkiService.counts.learn ?? 0))
                            .arg(Number(AnkiService.counts.review ?? 0))
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: ClockStyle.gap

                        ClockButton {
                            label: Translation.tr("Refresh")
                            symbol: "refresh"
                            variant: "tonal"
                            onClicked: AnkiService.requestCard()
                        }

                        ClockButton {
                            label: Translation.tr("Open in Anki")
                            symbol: "open_in_new"
                            variant: "text"
                            onClicked: root.openInAnki()
                        }
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(560, parent.width - 40)
                    spacing: ClockStyle.gap
                    visible: AnkiService.phase === "starting" || AnkiService.phase === "loading" || AnkiService.phase === "closed"

                    ClockEmptyState {
                        Layout.alignment: Qt.AlignHCenter
                        symbol: "hourglass_top"
                        title: Translation.tr("Opening Anki")
                        subtitle: Translation.tr("Reading the deck tree and the next card…")
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(620, parent.width - 40)
                    spacing: ClockStyle.gap
                    visible: AnkiService.phase === "error"

                    ClockEmptyState {
                        Layout.alignment: Qt.AlignHCenter
                        symbol: AnkiService.errorCode === "collection_locked" ? "lock" : "error"
                        title: root.errorTitle()
                        subtitle: root.errorSubtitle()
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: AnkiService.errorDetail.length > 0
                            && !["collection_locked", "anki_missing", "collection_missing", "no_profiles", "unsupported_version"].includes(AnkiService.errorCode)
                        text: AnkiService.errorDetail
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 6
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: ClockStyle.gap

                        ClockButton {
                            visible: AnkiService.errorCode === "anki_missing"
                            label: AnkiService.installingEngine ? Translation.tr("Installing…") : Translation.tr("Install the Anki engine")
                            symbol: "download"
                            variant: "filled"
                            enabled: !AnkiService.installingEngine
                            onClicked: AnkiService.installEngine()
                        }

                        ClockButton {
                            visible: AnkiService.errorCode !== "anki_missing"
                            label: Translation.tr("Retry")
                            symbol: "refresh"
                            variant: "filled"
                            onClicked: root.retry()
                        }

                        ClockButton {
                            label: Translation.tr("Open in Anki")
                            symbol: "open_in_new"
                            variant: "text"
                            onClicked: root.openInAnki()
                        }
                    }
                }
            }

            Item {
                id: sheetSlot
                Layout.fillHeight: true
                Layout.preferredWidth: sidePanel.open ? 360 + (root.compact ? 0 : ClockStyle.paneGap) : 0
                visible: Layout.preferredWidth > 1
                clip: true

                Behavior on Layout.preferredWidth {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                }

                ClockSidePanel {
                    id: sidePanel
                    anchors {
                        top: parent.top
                        bottom: parent.bottom
                        right: parent.right
                    }
                    width: 360
                }
            }
        }
    }

    // Compact deck drawer
    Rectangle {
        anchors.fill: parent
        z: 20
        visible: root.compact && root.decksOpen
        color: "#66000000"

        MouseArea {
            anchors.fill: parent
            onClicked: root.decksOpen = false
        }
    }

    Rectangle {
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
        }
        z: 21
        visible: root.compact && root.decksOpen
        width: Math.min(330, parent.width * 0.86)
        color: ClockStyle.colBackground

        DeckSidebar {
            id: drawerSidebar
            anchors.fill: parent
            anchors.margins: ClockStyle.paneGap
            onSearchDismissed: {
                root.decksOpen = false;
                root.forceActiveFocus();
            }
            decks: AnkiService.decks
            currentDeckId: AnkiService.currentDeckId
            onDeckSelected: deckId => {
                root.decksOpen = false;
                AnkiService.selectDeck(deckId);
            }
        }
    }

    // A sheet with text fields leaves the focus on a field that is about to be destroyed:
    // take it back, or the review shortcuts stay dead until the next click.
    Connections {
        target: sidePanel
        function onClosed(): void {
            root.forceActiveFocus();
        }
    }

    Component {
        id: settingsComponent
        AnkiSettingsSheet {}
    }

    Component {
        id: syncComponent
        AnkiSyncSheet {}
    }

    Component {
        id: addComponent
        AnkiAddSheet {}
    }

    // ---- Keyboard cheat sheet ----
    Rectangle {
        anchors.fill: parent
        z: 30
        visible: root.helpOpen
        color: ClockStyle.colScrim
        opacity: 0.5

        MouseArea {
            anchors.fill: parent
            onClicked: root.helpOpen = false
        }
    }

    Rectangle {
        z: 31
        visible: root.helpOpen
        anchors.centerIn: parent
        width: Math.min(620, parent.width - 40)
        height: Math.min(helpColumn.implicitHeight + 40, parent.height - 40)
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colSurfaceHighest

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: helpColumn
            anchors {
                fill: parent
                margins: 20
            }
            spacing: 6

            StyledText {
                text: Translation.tr("Keyboard shortcuts")
                color: ClockStyle.colOnSurface
                font.pixelSize: ClockStyle.textLarge
                font.weight: Font.DemiBold
                Layout.bottomMargin: 6
            }

            Repeater {
                model: [
                    { keys: "Space · Enter", what: Translation.tr("Show the answer, then answer Good") },
                    { keys: "1  2  3  4", what: Translation.tr("Again · Hard · Good · Easy") },
                    { keys: "Z · U · Ctrl+Z", what: Translation.tr("Undo the last answer") },
                    { keys: "R · F5", what: Translation.tr("Replay audio") },
                    { keys: "*", what: Translation.tr("Mark the note") },
                    { keys: "Ctrl+1 … 4", what: Translation.tr("Flag the card red, orange, green, blue") },
                    { keys: "@  ·  !", what: Translation.tr("Suspend the card  ·  the note") },
                    { keys: "-  ·  =", what: Translation.tr("Bury the card  ·  the note") },
                    { keys: "/ · Ctrl+F", what: Translation.tr("Search decks (Enter opens the first match)") },
                    { keys: "[  ]", what: Translation.tr("Previous / next deck") },
                    { keys: "Ctrl+N", what: Translation.tr("Add a note, make a deck, import a package") },
                    { keys: "Ctrl+Y", what: Translation.tr("Sync with AnkiWeb") },
                    { keys: "Ctrl+,", what: Translation.tr("Settings") },
                    { keys: "Ctrl+O", what: Translation.tr("Open in Anki") },
                    { keys: "Esc · Ctrl+W", what: Translation.tr("Close panel, then the window") }
                ]

                delegate: RowLayout {
                    id: helpRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 170
                        implicitHeight: 30
                        radius: ClockStyle.radiusSmall
                        color: ClockStyle.colSurfaceHigh

                        StyledText {
                            anchors.centerIn: parent
                            text: helpRow.modelData.keys
                            color: ClockStyle.colOnSurface
                            font.pixelSize: ClockStyle.textSmall
                            font.family: Appearance.font.family.monospace
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: helpRow.modelData.what
                        color: ClockStyle.colOnSurface
                        font.pixelSize: ClockStyle.textNormal
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
