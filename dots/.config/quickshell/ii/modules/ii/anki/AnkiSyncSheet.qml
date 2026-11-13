pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** AnkiWeb: sign in, sync, and choose a direction when both sides changed. */
ClockSheet {
    id: root

    title: Translation.tr("AnkiWeb sync")
    subtitle: AnkiService.loggedIn
        ? Translation.tr("Signed in as %1").arg(AnkiService.username)
        : Translation.tr("Sign in to sync your decks")

    readonly property string stageText: {
        switch (AnkiService.syncStage) {
        case "collection": return Translation.tr("Syncing the collection…");
        case "upload": return Translation.tr("Uploading to AnkiWeb…");
        case "download": return Translation.tr("Downloading from AnkiWeb…");
        case "media": return Translation.tr("Syncing media…");
        default: return AnkiService.syncing ? Translation.tr("Syncing…") : "";
        }
    }

    property bool signingIn: false

    function signIn(): void {
        if (root.signingIn || userField.text.trim().length === 0 || passwordField.text.length === 0)
            return;
        root.signingIn = true;
        AnkiService.login(userField.text.trim(), passwordField.text, ok => {
            root.signingIn = false;
            if (ok) {
                passwordField.text = "";
                AnkiService.sync();
            }
        });
    }

    Component.onCompleted: {
        passwordField.input.echoMode = TextInput.Password;
        if (!AnkiService.loggedIn)
            Qt.callLater(userField.focusInput);
    }

    // ---- Signed out ----
    ColumnLayout {
        Layout.fillWidth: true
        visible: !AnkiService.loggedIn
        spacing: ClockStyle.gap

        ClockFormField {
            id: userField
            symbol: "person"
            caption: Translation.tr("AnkiWeb email")
            onAccepted: passwordField.focusInput()
        }

        ClockFormField {
            id: passwordField
            symbol: "key"
            caption: Translation.tr("Password")
            onAccepted: root.signIn()
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Your password is sent to AnkiWeb once. Only the sign-in token it returns is kept, in a private file in your data folder.")
            font.pixelSize: ClockStyle.textSmall
            color: ClockStyle.colSubtext
            wrapMode: Text.WordWrap
        }
    }

    // ---- Signed in ----
    ColumnLayout {
        Layout.fillWidth: true
        visible: AnkiService.loggedIn
        spacing: ClockStyle.gap

        StyledText {
            Layout.fillWidth: true
            visible: root.stageText.length > 0
            text: root.stageText
            font.pixelSize: ClockStyle.textNormal
            color: ClockStyle.colOnSurface
            wrapMode: Text.WordWrap
        }

        StyledText {
            Layout.fillWidth: true
            visible: AnkiService.lastSyncOk && !AnkiService.syncing && !AnkiService.syncConflict && AnkiService.syncError.length === 0
            text: AnkiService.syncMessage.length > 0 ? AnkiService.syncMessage : Translation.tr("Up to date.")
            font.pixelSize: ClockStyle.textNormal
            color: ClockStyle.colOnSurface
            wrapMode: Text.WordWrap
        }

        // Both sides changed in a way that cannot merge: never picked automatically.
        ColumnLayout {
            Layout.fillWidth: true
            visible: AnkiService.syncConflict
            spacing: ClockStyle.gap

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("This collection and AnkiWeb have both changed and cannot be merged. Choose which one to keep. The other is replaced.")
                font.pixelSize: ClockStyle.textNormal
                color: ClockStyle.colOnSurface
                wrapMode: Text.WordWrap
            }

            ClockButton {
                Layout.fillWidth: true
                label: Translation.tr("Keep this collection (replace AnkiWeb)")
                symbol: "cloud_upload"
                danger: true
                onClicked: AnkiService.fullSync(true)
            }

            ClockButton {
                Layout.fillWidth: true
                label: Translation.tr("Keep AnkiWeb (replace this collection)")
                symbol: "cloud_download"
                danger: true
                onClicked: AnkiService.fullSync(false)
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: AnkiService.syncError.length > 0
        text: AnkiService.syncError
        font.pixelSize: ClockStyle.textSmall
        color: ClockStyle.colError
        wrapMode: Text.WordWrap
    }

    actions: [
        ClockSheetAction {
            visible: AnkiService.loggedIn
            label: Translation.tr("Sign out")
            symbol: "logout"
            enabled: !AnkiService.syncing
            onClicked: AnkiService.logout()
        },
        ClockSheetAction {
            visible: !AnkiService.loggedIn
            primary: true
            label: root.signingIn ? Translation.tr("Signing in…") : Translation.tr("Sign in")
            symbol: "login"
            enabled: !root.signingIn
            onClicked: root.signIn()
        },
        ClockSheetAction {
            visible: AnkiService.loggedIn && !AnkiService.syncConflict
            primary: true
            label: AnkiService.syncing ? Translation.tr("Syncing…") : Translation.tr("Sync now")
            symbol: "sync"
            enabled: !AnkiService.syncing
            onClicked: AnkiService.sync()
        }
    ]
}
