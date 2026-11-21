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
import qs.modules.ii.grit.components

/** Panadoro settings: goals, the week, categories and the account. */
Rectangle {
    id: root

    property bool compact: false
    property bool wide: false
    property real layoutWidth: root.width
    property ClockSidePanel panels: null

    property bool resetArmed: false

    readonly property real padding: root.compact ? GritStyle.pagePadding : GritStyle.pagePaddingWide
    readonly property real contentWidth: Math.min(root.layoutWidth - root.padding * 2, root.wide ? 1120 : 760)
    readonly property var gritState: Persistent.states.grit
    property string authEmailInput: ""
    property string authPasswordInput: ""

    function copy(text, message): void {
        Quickshell.clipboardText = String(text ?? "");
        copiedMessage.text = message;
        copiedToast.restart();
    }

    Component {
        id: categorySheet
        GritCategoryEditorSheet {}
    }

    color: GritStyle.colBackground

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + root.padding + GritStyle.gapHuge
        clip: true

        ColumnLayout {
            id: column
            width: root.contentWidth
            x: Math.max(root.padding, (root.width - root.contentWidth) / 2)
            spacing: GritStyle.gap

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
                        spacing: GritStyle.gapTiny

                        ClockChip {
                            label: Translation.tr("Monday")
                            selected: root.gritState?.weekStartMonday === true
                            onClicked: root.gritState.weekStartMonday = true
                        }

                        ClockChip {
                            label: Translation.tr("Sunday")
                            selected: root.gritState?.weekStartMonday !== true
                            onClicked: root.gritState.weekStartMonday = false
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
                        checked: root.gritState?.showCompleted === true
                        checkable: false
                        onClicked: root.gritState.showCompleted = !root.gritState.showCompleted
                    }
                }
            }

            // ── Categories ──────────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Categories")
                symbol: "label"

                Repeater {
                    model: GritService.activeCategories

                    ClockSettingsRow {
                        id: categoryRow
                        required property var modelData
                        required property int index
                        first: categoryRow.index === 0
                        last: categoryRow.index === GritService.activeCategories.length - 1
                        clickable: true
                        symbol: String(categoryRow.modelData.icon ?? "label")
                        title: String(categoryRow.modelData.name ?? "")
                        description: String(GritService.activeHabits.filter(habit => String(habit.categoryId) === String(categoryRow.modelData.id)).length)
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
                            color: GritStyle.accentContainer(categoryRow.modelData.accent)
                            colSymbol: GritStyle.accentOn(categoryRow.modelData.accent)
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
                            colIcon: GritStyle.colError
                            onClicked: GritService.deleteCategory(String(categoryRow.modelData.id))
                        }
                    }
                }

                ClockButton {
                    Layout.fillWidth: true
                    Layout.topMargin: GritStyle.gapSmall
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
                    radius: GritStyle.radiusSmall
                    color: GritService.syncStatus === "error"
                        ? GritStyle.colErrorContainer
                        : GritService.syncStatus === "synced"
                            ? GritStyle.colSuccessContainer
                            : GritStyle.colField

                    RowLayout {
                        id: syncStatus
                        anchors {
                            fill: parent
                            leftMargin: 12
                            rightMargin: 12
                        }
                        spacing: GritStyle.gap

                        MaterialSymbol {
                            text: GritService.syncStatus === "error" ? "cloud_off"
                                : GritService.syncStatus === "syncing" ? "cloud_sync"
                                : GritService.syncStatus === "synced" ? "cloud_done" : "cloud"
                            iconSize: 22
                            color: GritService.syncStatus === "error" ? GritStyle.colError
                                : GritService.syncStatus === "synced" ? GritStyle.colOnSuccessContainer
                                : GritStyle.colOnSurfaceVariant
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: GritService.syncMessage.length > 0
                                    ? GritService.syncMessage
                                    : Translation.tr("Ready to sync")
                                wrapMode: Text.WordWrap
                                font.pixelSize: GritStyle.textNormal
                                font.weight: Font.DemiBold
                                color: GritService.syncStatus === "error" ? GritStyle.colOnErrorContainer
                                    : GritService.syncStatus === "synced" ? GritStyle.colOnSuccessContainer
                                    : GritStyle.colOnSurface
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: String(root.gritState?.lastSyncAt ?? "").length > 0
                                text: Translation.tr("Last sync %1").arg(String(root.gritState?.lastSyncAt ?? ""))
                                font.pixelSize: GritStyle.textSmall
                                color: GritStyle.colSubtext
                            }
                        }

                        ClockButton {
                            visible: GritService.signedIn
                            variant: "tonal"
                            symbol: "sync"
                            label: Translation.tr("Sync now")
                            enabled: !GritService.syncInProgress
                            onClicked: GritService.syncNow()
                        }
                    }
                }

                ClockSettingsRow {
                    visible: GritService.signedIn
                    symbol: "person"
                    title: GritService.authEmail
                    description: Translation.tr("Signed in")

                    ClockButton {
                        symbol: "logout"
                        label: Translation.tr("Sign out")
                        variant: "tonal"
                        onClicked: GritService.signOut()
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !GritService.signedIn
                    spacing: GritStyle.gapSmall

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
                        spacing: GritStyle.gapSmall

                        ClockButton {
                            Layout.fillWidth: true
                            symbol: "login"
                            variant: "filled"
                            label: GritService.authBusy
                                ? Translation.tr("Please wait…") : Translation.tr("Sign in")
                            enabled: !GritService.authBusy
                            onClicked: GritService.signIn(root.authEmailInput, root.authPasswordInput)
                        }

                        ClockButton {
                            Layout.fillWidth: true
                            symbol: "person_add"
                            label: Translation.tr("Create account")
                            enabled: !GritService.authBusy
                            onClicked: GritService.createAccount(root.authEmailInput, root.authPasswordInput)
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: GritService.authError.length > 0
                        text: GritService.authError
                        wrapMode: Text.WordWrap
                        font.pixelSize: GritStyle.textSmall
                        color: GritStyle.colError
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Create an account here, then sign in with the same email on your other devices. Your habits, tasks and focus history stay private to your account.")
                        wrapMode: Text.WordWrap
                        font.pixelSize: GritStyle.textSmall
                        color: GritStyle.colOnSurfaceVariant
                    }
                }

                ClockSettingsRow {
                    symbol: "sync"
                    title: Translation.tr("Live sync")
                    description: Translation.tr("Pushes after each edit and checks for changes every 5 seconds")

                    StyledSwitch {
                        checked: root.gritState?.autoSync === true
                        checkable: false
                        onClicked: GritService.setAutoSync(!GritService.autoSync)
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
                    description: Translation.tr("Save a complete snapshot of habits, tasks, focus history and settings.")

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
                    description: Translation.tr("Restore a backup and upload it to every synced device.")

                    ClockButton {
                        variant: "tonal"
                        symbol: "upload"
                        label: Translation.tr("Restore…")
                        onClicked: importDialog.open()
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
                                GritService.resetAllData();
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
                Layout.topMargin: GritStyle.gapSmall
                implicitHeight: aboutColumn.implicitHeight + GritStyle.cardPadding * 2
                radius: GritStyle.radiusLarge
                color: GritStyle.colSurface

                ColumnLayout {
                    id: aboutColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: GritStyle.cardPadding
                    }
                    spacing: 4

                    RowLayout {
                        spacing: GritStyle.gap

                        MaterialShapeWrappedMaterialSymbol {
                            text: "local_fire_department"
                            iconSize: 22
                            padding: 10
                            shape: "Cookie12Sided"
                            color: GritStyle.colPrimary
                            colSymbol: GritStyle.colOnPrimary
                        }

                        ColumnLayout {
                            spacing: 0

                            StyledText {
                                text: "Panadoro"
                                font.family: GritStyle.fontTitle
                                font.variableAxes: GritStyle.axesTitle
                                font.pixelSize: Appearance.font.pixelSize.large
                                color: GritStyle.colOnSurface
                            }

                            StyledText {
                                text: Translation.tr("Habits, tasks and tagged focus in one quiet place")
                                font.pixelSize: GritStyle.textSmall
                                color: GritStyle.colSubtext
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        text: Translation.tr("Data is stored locally in %1 and merged record by record when sync is on. The timer and its sessions live in the service, so closing this window never stops a session.")
                            .arg(Directories.gritDataPath)
                        wrapMode: Text.WordWrap
                        font.pixelSize: GritStyle.textSmall
                        color: GritStyle.colOnSurfaceVariant
                    }

                    ClockButton {
                        Layout.fillWidth: true
                        Layout.topMargin: GritStyle.gapSmall
                        variant: "tonal"
                        symbol: "open_in_new"
                        label: Translation.tr("Open project repository")
                        onClicked: Qt.openUrlExternally("https://github.com/ADH787/panadoro")
                    }
                }
            }

            Item { Layout.preferredHeight: GritStyle.gapHuge }
        }
    }

    FileDialog {
        id: backupDialog
        visible: false
        title: Translation.tr("Save Panadoro backup")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: [Translation.tr("JSON files (*.json)")]
        onAccepted: GritService.exportBackup(selectedFile)
    }

    FileDialog {
        id: importDialog
        visible: false
        title: Translation.tr("Open Panadoro backup")
        fileMode: FileDialog.OpenFile
        nameFilters: [Translation.tr("JSON files (*.json)")]
        onAccepted: GritService.importBackup(selectedFile)
    }

    Timer {
        id: resetDisarm
        interval: 5000
        onTriggered: root.resetArmed = false
    }

    Timer {
        id: copiedToast
        interval: 2200
    }

    StyledText {
        id: copiedMessage
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: GritStyle.gapHuge
        opacity: copiedToast.running ? 1 : 0
        text: ""
        font.pixelSize: GritStyle.textNormal
        font.weight: Font.DemiBold
        color: GritStyle.colOnPrimary
        padding: 10
        style: Text.Outline
        styleColor: GritStyle.colPrimary

        Behavior on opacity {
            animation: GritStyle.motionFast.numberAnimation.createObject(this)
        }
    }
}
