import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.panadoro.components

/** Panadoro settings: goals, the week, categories and the account. */
Rectangle {
    id: root

    property bool compact: false
    property bool wide: false
    property real layoutWidth: root.width
    property ClockSidePanel panels: null

    property bool resetArmed: false
    property bool importArmed: false

    readonly property real padding: root.compact ? PanadoroStyle.pagePadding : PanadoroStyle.pagePaddingWide
    readonly property real contentWidth: Math.min(root.layoutWidth - root.padding * 2, root.wide ? 1120 : 760)
    readonly property var panadoroState: Persistent.states.panadoro
    property string authEmailInput: ""
    property string authPasswordInput: ""

    function copy(text, message): void {
        Quickshell.clipboardText = String(text ?? "");
        copiedMessage.text = message;
        copiedToast.restart();
    }

    Component {
        id: categorySheet
        PanadoroCategoryEditorSheet {}
    }

    color: PanadoroStyle.colBackground

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + root.padding + PanadoroStyle.gapHuge
        clip: true

        ColumnLayout {
            id: column
            width: root.contentWidth
            x: Math.max(root.padding, (root.width - root.contentWidth) / 2)
            spacing: PanadoroStyle.gap

            // ── Goals ───────────────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Week")
                symbol: "date_range"

                ClockSettingsRow {
                    first: true
                    last: true
                    symbol: "date_range"
                    title: Translation.tr("Week starts on")
                    description: Translation.tr("Used by streaks and the weekly view")

                    RowLayout {
                        spacing: PanadoroStyle.gapTiny

                        ClockChip {
                            label: Translation.tr("Monday")
                            selected: root.panadoroState?.weekStartMonday === true
                            onClicked: root.panadoroState.weekStartMonday = true
                        }

                        ClockChip {
                            label: Translation.tr("Sunday")
                            selected: root.panadoroState?.weekStartMonday !== true
                            onClicked: root.panadoroState.weekStartMonday = false
                        }
                    }
                }
            }

            // ── Today ───────────────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Today")
                symbol: "checklist"

                ClockSettingsRow {
                    first: true
                    last: true
                    symbol: "visibility"
                    title: Translation.tr("Show completed habits")
                    description: Translation.tr("Completed rows stay in the list instead of disappearing")

                    StyledSwitch {
                        checked: root.panadoroState?.showCompleted === true
                        checkable: false
                        onClicked: root.panadoroState.showCompleted = !root.panadoroState.showCompleted
                    }
                }
            }

            // ── Categories ──────────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Categories")
                symbol: "label"

                Repeater {
                    model: PanadoroService.activeCategories

                    ClockSettingsRow {
                        id: categoryRow
                        required property var modelData
                        required property int index
                        first: categoryRow.index === 0
                        last: categoryRow.index === PanadoroService.activeCategories.length - 1
                        clickable: true
                        symbol: String(categoryRow.modelData.icon ?? "label")
                        title: String(categoryRow.modelData.name ?? "")
                        description: String(PanadoroService.activeHabits.filter(habit => String(habit.categoryId) === String(categoryRow.modelData.id)).length)
                            + " " + Translation.tr("habits")
                        onClicked: root.panels.show(categorySheet, {
                            categoryId: String(categoryRow.modelData.id),
                            panels: root.panels
                        })

                        MaterialShapeWrappedMaterialSymbol {
                            text: String(categoryRow.modelData.icon ?? "label")
                            iconSize: 16
                            padding: 7
                            shape: "Cookie7Sided"
                            color: PanadoroStyle.accentContainer(categoryRow.modelData.accent)
                            colSymbol: PanadoroStyle.accentOn(categoryRow.modelData.accent)
                        }

                        ClockIconButton {
                            symbol: "edit"
                            size: 32
                            iconSize: 16
                            tooltip: Translation.tr("Edit category")
                            onClicked: root.panels.show(categorySheet, {
                                categoryId: String(categoryRow.modelData.id),
                                panels: root.panels
                            })
                        }

                        ClockIconButton {
                            symbol: "delete"
                            size: 32
                            iconSize: 16
                            tooltip: Translation.tr("Delete category")
                            colIcon: PanadoroStyle.colError
                            onClicked: PanadoroService.deleteCategory(String(categoryRow.modelData.id))
                        }
                    }
                }

                ClockButton {
                    Layout.fillWidth: true
                    Layout.topMargin: PanadoroStyle.gapSmall
                    symbol: "add"
                    label: Translation.tr("New category")
                    onClicked: root.panels.show(categorySheet, { panels: root.panels })
                }
            }

            // ── Account & sync ──────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Account & sync")
                symbol: "account_circle"

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: syncStatus.implicitHeight + 24
                    radius: PanadoroStyle.radiusSmall
                    color: PanadoroService.syncStatus === "error"
                        ? PanadoroStyle.colErrorContainer
                        : PanadoroService.syncStatus === "synced"
                            ? PanadoroStyle.colSuccessContainer
                            : PanadoroStyle.colField

                    RowLayout {
                        id: syncStatus
                        anchors {
                            fill: parent
                            leftMargin: 12
                            rightMargin: 12
                        }
                        spacing: PanadoroStyle.gap

                        MaterialSymbol {
                            text: PanadoroService.syncStatus === "error" ? "cloud_off"
                                : PanadoroService.syncStatus === "syncing" ? "cloud_sync"
                                : PanadoroService.syncStatus === "synced" ? "cloud_done" : "cloud"
                            iconSize: 22
                            color: PanadoroService.syncStatus === "error" ? PanadoroStyle.colError
                                : PanadoroService.syncStatus === "synced" ? PanadoroStyle.colOnSuccessContainer
                                : PanadoroStyle.colOnSurfaceVariant
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: PanadoroService.syncMessage.length > 0
                                    ? PanadoroService.syncMessage
                                    : Translation.tr("Ready to sync")
                                wrapMode: Text.WordWrap
                                font.pixelSize: PanadoroStyle.textNormal
                                font.weight: Font.DemiBold
                                color: PanadoroService.syncStatus === "error" ? PanadoroStyle.colOnErrorContainer
                                    : PanadoroService.syncStatus === "synced" ? PanadoroStyle.colOnSuccessContainer
                                    : PanadoroStyle.colOnSurface
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: String(root.panadoroState?.lastSyncAt ?? "").length > 0
                                text: Translation.tr("Last sync %1").arg(String(root.panadoroState?.lastSyncAt ?? ""))
                                font.pixelSize: PanadoroStyle.textSmall
                                color: PanadoroStyle.colSubtext
                            }
                        }

                        ClockButton {
                            visible: PanadoroService.signedIn
                            variant: "tonal"
                            symbol: "sync"
                            label: Translation.tr("Sync now")
                            enabled: !PanadoroService.syncInProgress
                            onClicked: PanadoroService.syncNow()
                        }
                    }
                }

                ClockSettingsRow {
                    visible: PanadoroService.signedIn
                    symbol: "person"
                    title: PanadoroService.authEmail
                    description: Translation.tr("Signed in")

                    ClockButton {
                        symbol: "logout"
                        label: Translation.tr("Sign out")
                        variant: "tonal"
                        onClicked: PanadoroService.signOut()
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !PanadoroService.signedIn
                    spacing: PanadoroStyle.gapSmall

                    ClockFormField {
                        Layout.fillWidth: true
                        symbol: "mail"
                        shapeKind: MaterialShape.Shape.Cookie4Sided
                        caption: Translation.tr("Email")
                        placeholder: "you@example.com"
                        text: root.authEmailInput
                        input.echoMode: TextInput.Normal
                        onTextChanged: {
                            if (text !== root.authEmailInput)
                                root.authEmailInput = text;
                        }
                    }

                    ClockFormField {
                        Layout.fillWidth: true
                        symbol: "lock"
                        shapeKind: MaterialShape.Shape.Cookie7Sided
                        caption: Translation.tr("Password")
                        placeholder: Translation.tr("At least 6 characters")
                        text: root.authPasswordInput
                        input.echoMode: TextInput.Password
                        onTextChanged: {
                            if (text !== root.authPasswordInput)
                                root.authPasswordInput = text;
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: PanadoroStyle.gapSmall

                        ClockButton {
                            Layout.fillWidth: true
                            symbol: "login"
                            variant: "filled"
                            label: PanadoroService.authBusy
                                ? Translation.tr("Please wait…") : Translation.tr("Sign in")
                            enabled: !PanadoroService.authBusy
                            onClicked: PanadoroService.signIn(root.authEmailInput, root.authPasswordInput)
                        }

                        ClockButton {
                            Layout.fillWidth: true
                            symbol: "person_add"
                            label: Translation.tr("Create account")
                            enabled: !PanadoroService.authBusy
                            onClicked: PanadoroService.createAccount(root.authEmailInput, root.authPasswordInput)
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: PanadoroService.authError.length > 0
                        text: PanadoroService.authError
                        wrapMode: Text.WordWrap
                        font.pixelSize: PanadoroStyle.textSmall
                        color: PanadoroStyle.colError
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Create an account here, then sign in with the same email on your other devices. Your habits, tasks and focus history stay private to your account.")
                        wrapMode: Text.WordWrap
                        font.pixelSize: PanadoroStyle.textSmall
                        color: PanadoroStyle.colOnSurfaceVariant
                    }
                }

                ClockSettingsRow {
                    symbol: "sync"
                    title: Translation.tr("Live sync")
                    description: Translation.tr("Pushes after each edit and checks for changes every 5 seconds")

                    StyledSwitch {
                        checked: root.panadoroState?.autoSync === true
                        checkable: false
                        onClicked: PanadoroService.setAutoSync(!PanadoroService.autoSync)
                    }
                }
            }

            // ── Reset ───────────────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Data")
                symbol: "database"

                ClockSettingsRow {
                    first: true
                    symbol: "download"
                    title: Translation.tr("Backup JSON")
                    description: PanadoroService.backupMessage.length > 0
                        ? PanadoroService.backupMessage
                        : Translation.tr("Save a complete snapshot of habits, tasks, focus history and settings.")

                    ClockButton {
                        variant: "tonal"
                        symbol: "download"
                        label: Translation.tr("Backup…")
                        onClicked: backupDialog.open()
                    }
                }

                ClockSettingsRow {
                    symbol: "upload"
                    title: Translation.tr("Import backup")
                    description: root.importArmed
                        ? Translation.tr("Press again to choose a file. This replaces your current data on every synced device.")
                        : Translation.tr("Restore a backup and upload it to every synced device.")

                    ClockButton {
                        variant: root.importArmed ? "filled" : "tonal"
                        symbol: root.importArmed ? "warning" : "upload"
                        label: root.importArmed ? Translation.tr("Choose file") : Translation.tr("Restore…")
                        onClicked: {
                            if (root.importArmed) {
                                root.importArmed = false;
                                importDialog.open();
                            } else {
                                root.importArmed = true;
                                resetDisarm.restart();
                            }
                        }
                    }
                }

                ClockSettingsRow {
                    last: true
                    symbol: "delete_forever"
                    title: Translation.tr("Reset Panadoro data")
                    description: root.resetArmed
                        ? Translation.tr("Press again to erase habits, tasks and focus history. This syncs the deletion.")
                        : Translation.tr("Erase every habit, task and session on every synced device")

                    ClockButton {
                        danger: true
                        variant: root.resetArmed ? "filled" : "tonal"
                        symbol: root.resetArmed ? "warning" : "restart_alt"
                        label: root.resetArmed ? Translation.tr("Erase everything") : Translation.tr("Reset…")
                        onClicked: {
                            if (root.resetArmed) {
                                PanadoroService.resetAllData();
                                root.resetArmed = false;
                            } else {
                                root.resetArmed = true;
                                resetDisarm.restart();
                            }
                        }
                    }
                }
            }

            // ── About ───────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: PanadoroStyle.gapSmall
                implicitHeight: aboutColumn.implicitHeight + PanadoroStyle.cardPadding * 2
                radius: PanadoroStyle.radiusLarge
                color: PanadoroStyle.colSurface

                ColumnLayout {
                    id: aboutColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: PanadoroStyle.cardPadding
                    }
                    spacing: 4

                    RowLayout {
                        spacing: PanadoroStyle.gap

                        MaterialShapeWrappedMaterialSymbol {
                            text: "local_fire_department"
                            iconSize: 22
                            padding: 10
                            shape: "Cookie12Sided"
                            color: PanadoroStyle.colPrimary
                            colSymbol: PanadoroStyle.colOnPrimary
                        }

                        ColumnLayout {
                            spacing: 0

                            StyledText {
                                text: "Panadoro"
                                font.family: PanadoroStyle.fontTitle
                                font.variableAxes: PanadoroStyle.axesTitle
                                font.pixelSize: Appearance.font.pixelSize.large
                                color: PanadoroStyle.colOnSurface
                            }

                            StyledText {
                                text: Translation.tr("Habits, tasks and tagged focus in one quiet place")
                                font.pixelSize: PanadoroStyle.textSmall
                                color: PanadoroStyle.colSubtext
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        text: Translation.tr("Data is stored locally in %1 and merged record by record when sync is on. The timer and its sessions live in the service, so closing this window never stops a session.")
                            .arg(Directories.panadoroDataPath)
                        wrapMode: Text.WordWrap
                        font.pixelSize: PanadoroStyle.textSmall
                        color: PanadoroStyle.colOnSurfaceVariant
                    }

                    ClockButton {
                        Layout.fillWidth: true
                        Layout.topMargin: PanadoroStyle.gapSmall
                        variant: "tonal"
                        symbol: "open_in_new"
                        label: Translation.tr("Open project repository")
                        onClicked: Qt.openUrlExternally("https://github.com/ADH787/panadoro")
                    }
                }
            }


            // ── Credits ─────────────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.topMargin: PanadoroStyle.gapSmall
                title: Translation.tr("Credits")
                symbol: "favorite"

                ClockSettingsRow {
                    first: true
                    clickable: true
                    symbol: "local_fire_department"
                    title: "Panadoro · shub39"
                    description: "github.com/shub39/Panadoro"
                    onClicked: Qt.openUrlExternally("https://github.com/shub39/Panadoro")

                    MaterialSymbol {
                        text: "open_in_new"
                        iconSize: 18
                        color: PanadoroStyle.colSubtext
                    }
                }

                ClockSettingsRow {
                    last: true
                    clickable: true
                    symbol: "timer"
                    title: "Tomato · nsh07"
                    description: "github.com/nsh07/Tomato"
                    onClicked: Qt.openUrlExternally("https://github.com/nsh07/Tomato")

                    MaterialSymbol {
                        text: "open_in_new"
                        iconSize: 18
                        color: PanadoroStyle.colSubtext
                    }
                }
            }

            Item { Layout.preferredHeight: PanadoroStyle.gapHuge }
        }
    }

    FileDialog {
        id: backupDialog
        visible: false
        title: Translation.tr("Save Panadoro backup")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: [Translation.tr("JSON files (*.json)")]
        onAccepted: PanadoroService.exportBackup(selectedFile)
    }

    FileDialog {
        id: importDialog
        visible: false
        title: Translation.tr("Open Panadoro backup")
        fileMode: FileDialog.OpenFile
        nameFilters: [Translation.tr("JSON files (*.json)")]
        onAccepted: PanadoroService.importBackup(selectedFile)
    }

    Timer {
        id: resetDisarm
        interval: 5000
        onTriggered: {
            root.resetArmed = false;
            root.importArmed = false;
        }
    }

    Timer {
        id: copiedToast
        interval: 2200
    }

    StyledText {
        id: copiedMessage
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: PanadoroStyle.gapHuge
        opacity: copiedToast.running ? 1 : 0
        text: ""
        font.pixelSize: PanadoroStyle.textNormal
        font.weight: Font.DemiBold
        color: PanadoroStyle.colOnPrimary
        padding: 10
        style: Text.Outline
        styleColor: PanadoroStyle.colPrimary

        Behavior on opacity {
            animation: PanadoroStyle.motionFast.numberAnimation.createObject(this)
        }
    }
}
