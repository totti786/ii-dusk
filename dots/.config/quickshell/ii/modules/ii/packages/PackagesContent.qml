pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The Packages app inside its window, built from the clock app's parts so it reads as one
 * of the family: top bar, rail on the left and the page. A package's details slide in from
 * the right, questions come up over the page and the running change sits along the bottom.
 */
FocusScope {
    id: root

    signal closeRequested()

    readonly property bool compact: root.width < ClockStyle.compactMax
    readonly property bool canExpandRail: root.width >= ClockStyle.railExpandMin
    property bool railExpanded: true
    readonly property bool railOpen: root.canExpandRail && root.railExpanded
    readonly property real railWidth: root.railOpen ? ClockStyle.railExpandedWidth : ClockStyle.railCollapsedWidth
    readonly property bool wideDetail: root.width >= 1100
    readonly property real detailWidth: root.wideDetail ? 400 : Math.min(420, root.width - 48)
    readonly property real pageLayoutWidth: Math.max(0, root.width - ClockStyle.paneGap * 2
        - (root.compact ? 0 : root.railWidth + ClockStyle.paneGap)
        - (detail.open && root.wideDetail ? root.detailWidth + ClockStyle.paneGap : 0))

    readonly property var tabs: [
        { id: "updates", icon: "system_update_alt", label: Translation.tr("Updates") },
        { id: "installed", icon: "inventory_2", label: Translation.tr("Installed") },
        { id: "browse", icon: "storefront", label: Translation.tr("Browse") },
        { id: "maintenance", icon: "cleaning_services", label: Translation.tr("Maintenance") }
    ]
    readonly property var tabIds: root.tabs.map(tab => tab.id)
    readonly property var badges: ({
        updates: PackagesService.updateCount > 0 ? String(PackagesService.updateCount) : "",
        installed: "",
        browse: "",
        maintenance: PackagesService.orphans.names.length > 0 ? String(PackagesService.orphans.names.length) : ""
    })

    property string currentTab: "updates"
    readonly property bool shown: root.Window.window?.visible ?? true

    function selectTab(tabId: string): void {
        if (root.tabIds.includes(tabId))
            root.currentTab = tabId;
    }

    function consumePendingTab(): void {
        const pending = GlobalStates.packagesPendingTab;
        GlobalStates.packagesPendingTab = "";
        if (root.tabIds.includes(pending))
            root.selectTab(pending);
    }

    function subtitleFor(tabId: string): string {
        switch (tabId) {
        case "updates": return Translation.tr("What is waiting to be installed");
        case "installed": return Translation.tr("Everything on this computer");
        case "browse": return Translation.tr("Find software in the repositories and the AUR");
        default: return Translation.tr("Clean up what is no longer needed");
        }
    }

    function showDetail(name: string): void {
        PackagesService.loadDetail(name);
        detail.open = true;
    }

    function ask(title, message, label, danger, callback): void {
        confirm.ask(title, message, label, danger, callback);
    }

    Component.onCompleted: {
        root.consumePendingTab();
        PackagesService.checkUpdates();
    }

    onShownChanged: {
        if (root.shown) {
            root.consumePendingTab();
            // A list older than half an hour is not worth showing as current
            if (Date.now() - PackagesService.lastChecked > 30 * 60 * 1000)
                PackagesService.checkUpdates();
            Qt.callLater(() => root.forceActiveFocus());
        } else {
            detail.open = false;
        }
    }

    Connections {
        target: GlobalStates
        function onPackagesPendingTabChanged() {
            if (GlobalStates.packagesPendingTab.length > 0)
                root.consumePendingTab();
        }
    }

    // A field that held the keys is destroyed or hidden on close; take them back
    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            if (root.Window.window && !root.Window.window.activeFocusItem)
                Qt.callLater(() => root.forceActiveFocus());
        }
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (ctrl && event.key >= Qt.Key_1 && event.key < Qt.Key_1 + root.tabIds.length) {
            root.selectTab(root.tabIds[event.key - Qt.Key_1]);
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_F) {
            root.selectTab("browse");
            event.accepted = true;
        } else if (ctrl && (event.key === Qt.Key_W || event.key === Qt.Key_Q)) {
            root.closeRequested();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && detail.open) {
            detail.open = false;
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
        anchors.topMargin: ClockStyle.gapTiny
        spacing: ClockStyle.gapTiny

        ClockTopBar {
            Layout.fillWidth: true
            title: root.tabs.find(tab => tab.id === root.currentTab)?.label ?? ""
            subtitle: root.subtitleFor(root.currentTab)
            showRailToggle: !root.compact && root.canExpandRail
            railExpanded: root.railOpen
            onRailToggled: root.railExpanded = !root.railExpanded
            onCloseRequested: root.closeRequested()
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            ClockRail {
                Layout.fillHeight: true
                Layout.preferredWidth: root.railWidth
                Layout.rightMargin: ClockStyle.paneGap
                visible: !root.compact
                tabs: root.tabs
                currentTab: root.currentTab
                expanded: root.railOpen
                showSettings: false
                badges: root.badges
                onSelected: tabId => root.selectTab(tabId)

                Behavior on Layout.preferredWidth {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: ClockStyle.paneGap

                Item {
                    id: pageHost
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Loader {
                        anchors.fill: parent
                        sourceComponent: root.currentTab === "updates" ? updatesComponent
                            : root.currentTab === "installed" ? installedComponent
                            : root.currentTab === "browse" ? browseComponent : maintenanceComponent
                    }

                    PackageTaskPanel {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: ClockStyle.gap
                    }
                }

                ClockNavigation {
                    Layout.fillWidth: true
                    visible: root.compact
                    tabs: root.tabs
                    currentTab: root.currentTab
                    onSelected: tabId => root.selectTab(tabId)
                }
            }

            // Beside the page when there is room; over it when there is not
            PackageDetailPanel {
                id: detail
                property bool open: false
                visible: open
                Layout.fillHeight: true
                Layout.preferredWidth: root.detailWidth
                Layout.leftMargin: ClockStyle.paneGap
                // Over the page in a narrow window
                Layout.maximumWidth: root.wideDetail ? root.detailWidth : 0
                onCloseRequested: open = false
                onOpenRequested: name => root.showDetail(name)
                onRemoveRequested: name => root.ask(Translation.tr("Remove %1?").arg(name),
                    Translation.tr("It and the dependencies nothing else uses will be removed. Your own files and settings stay."),
                    Translation.tr("Remove"), true, () => {
                        detail.open = false;
                        PackagesService.remove([name]);
                    })
                onInstallRequested: (name, aur) => {
                    if (aur)
                        root.ask(Translation.tr("Install %1 from the AUR?").arg(name),
                            Translation.tr("A terminal opens where yay shows the recipe and asks before it builds and installs anything."),
                            Translation.tr("Open terminal"), false, () => PackagesService.installAur(name));
                    else
                        PackagesService.installRepo([name]);
                }
            }
        }
    }

    // A narrow window shows the details over everything
    PackageDetailPanel {
        id: overlayDetail
        visible: detail.open && !root.wideDetail
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: ClockStyle.paneGap
        width: root.detailWidth
        z: 15
        onCloseRequested: detail.open = false
        onOpenRequested: name => root.showDetail(name)
        onRemoveRequested: name => detail.removeRequested(name)
        onInstallRequested: (name, aur) => detail.installRequested(name, aur)
    }

    PackageConfirm {
        id: confirm
        anchors.fill: parent
    }

    Component {
        id: updatesComponent
        UpdatesPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            onDetailRequested: name => root.showDetail(name)
            onConfirm: (title, message, label, danger, callback) => root.ask(title, message, label, danger, callback)
        }
    }

    Component {
        id: installedComponent
        InstalledPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            active: root.shown
            onDetailRequested: name => root.showDetail(name)
            onConfirm: (title, message, label, danger, callback) => root.ask(title, message, label, danger, callback)
        }
    }

    Component {
        id: browseComponent
        BrowsePage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            active: root.shown
            onDetailRequested: name => root.showDetail(name)
            onConfirm: (title, message, label, danger, callback) => root.ask(title, message, label, danger, callback)
        }
    }

    Component {
        id: maintenanceComponent
        MaintenancePage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            active: root.shown
            onConfirm: (title, message, label, danger, callback) => root.ask(title, message, label, danger, callback)
        }
    }
}
