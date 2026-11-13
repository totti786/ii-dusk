import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.grit.components

/** Grit's settings: goals, the week, categories and the sync server. */
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
    readonly property bool hostBusy: root.gritState?.hostLocal === true && !GritService.hostRunning

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

            // ── Sync ────────────────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Sync between devices")
                symbol: "sync"

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
                            visible: GritService.syncConfigured
                            variant: "tonal"
                            symbol: "sync"
                            label: Translation.tr("Sync now")
                            onClicked: GritService.syncNow()
                        }
                    }
                }

                ClockFormField {
                    Layout.fillWidth: true
                    symbol: "link"
                    shapeKind: MaterialShape.Shape.Cookie7Sided
                    caption: Translation.tr("Server URL")
                    placeholder: "http://192.168.1.20:8765/grit"
                    text: GritService.syncUrl
                    onTextChanged: {
                        if (text !== GritService.syncUrl)
                            GritService.setSyncUrl(text);
                    }
                }

                ClockFormField {
                    Layout.fillWidth: true
                    symbol: "key"
                    shapeKind: MaterialShape.Shape.Cookie4Sided
                    caption: Translation.tr("Shared key")
                    placeholder: Translation.tr("A long random string")
                    text: GritService.syncToken
                    input.echoMode: TextInput.Password
                    onTextChanged: {
                        if (text !== GritService.syncToken)
                            GritService.setSyncToken(text);
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: GritStyle.gapSmall

                    ClockButton {
                        Layout.fillWidth: true
                        symbol: "casino"
                        label: Translation.tr("Generate a key")
                        onClicked: {
                            root.gritState.syncToken = GritService.generateToken();
                            GritService.afterSyncSetting();
                        }
                    }

                    ClockButton {
                        Layout.fillWidth: true
                        symbol: "content_copy"
                        label: Translation.tr("Copy key")
                        onClicked: root.copy(GritService.syncToken, Translation.tr("Sync key copied"))
                    }
                }

                ClockSettingsRow {
                    symbol: "sync"
                    title: Translation.tr("Sync automatically")
                    description: Translation.tr("Merge in the background and after changes")

                    StyledSwitch {
                        checked: root.gritState?.autoSync === true
                        checkable: false
                        onClicked: GritService.setAutoSync(!GritService.autoSync)
                    }
                }

                ClockSettingsRow {
                    symbol: "schedule"
                    title: Translation.tr("Sync interval")
                    description: Translation.tr("How often the background loop checks the server")

                    ClockStepper {
                        value: Math.round(GritService.syncIntervalSec / 30) * 30
                        from: 15
                        to: 3600
                        stepSize: 15
                        format: value => value < 60 ? String(value) + "s" : GritStyle.durationShort(Math.round(value / 60))
                        onMoved: value => GritService.setSyncInterval(value)
                    }
                }
            }

            // ── Local server ────────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Host a server here")
                symbol: "dns"

                ClockSettingsRow {
                    first: true
                    symbol: "power"
                    title: Translation.tr("Run the sync server")
                    description: root.hostBusy ? Translation.tr("Starting…")
                        : GritService.hostStatus.length > 0 ? GritService.hostStatus
                        : Translation.tr("Serve this device's Grit data on the local network")

                    StyledSwitch {
                        checked: GritService.hostRunning
                        checkable: false
                        onClicked: GritService.toggleLocalHost()
                    }
                }

                ClockSettingsRow {
                    last: true
                    symbol: "settings_ethernet"
                    title: Translation.tr("Port")
                    description: Translation.tr("Open it in your firewall if other devices should reach it")

                    ClockStepper {
                        value: GritService.syncPort
                        from: 1024
                        to: 65535
                        stepSize: 1
                        format: value => String(value)
                        onMoved: value => GritService.setSyncPort(value)
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: serverHint.implicitHeight + 24
                    radius: GritStyle.radiusSmall
                    color: GritStyle.colField

                    ColumnLayout {
                        id: serverHint
                        anchors {
                            fill: parent
                            margins: 12
                        }
                        spacing: 6

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("To sync another device, run the server on one machine and use its address and key everywhere. The local address only works on this machine; use the machine's LAN address on the others.")
                            wrapMode: Text.WordWrap
                            font.pixelSize: GritStyle.textSmall
                            color: GritStyle.colOnSurfaceVariant
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: "python3 " + Directories.gritSyncServerPath + " --port "
                                + String(GritService.syncPort) + " --token <key> --data "
                                + Directories.gritSyncDataPath
                            wrapMode: Text.WrapAnywhere
                            font.family: GritStyle.fontNumbers
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: GritStyle.colSubtext
                        }
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
                    last: true
                    symbol: "delete_forever"
                    title: Translation.tr("Reset Grit data")
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
                                text: "Grit × Tomato"
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
                }
            }

            // ── Credits ─────────────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.topMargin: GritStyle.gapSmall
                title: Translation.tr("Credits")
                symbol: "favorite"

                ClockSettingsRow {
                    first: true
                    clickable: true
                    symbol: "local_fire_department"
                    title: "Grit · shub39"
                    description: "github.com/shub39/Grit"
                    onClicked: Qt.openUrlExternally("https://github.com/shub39/Grit")

                    MaterialSymbol {
                        text: "open_in_new"
                        iconSize: 18
                        color: GritStyle.colSubtext
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
                        color: GritStyle.colSubtext
                    }
                }
            }

            Item { Layout.preferredHeight: GritStyle.gapHuge }
        }
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
