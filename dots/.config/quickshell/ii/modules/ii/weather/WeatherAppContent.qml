pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "components"
import "pages"

/**
 * The weather app inside its floating window: top bar, rail, page, location sheet.
 *
 * The app is only awake while the window is visible; the service keeps the last
 * response while the retained window cools down, then both go away together.
 */
FocusScope {
    id: root

    signal closeRequested()

    // ── Layout ──────────────────────────────────────────────────────────
    readonly property bool compact: root.width < WeatherStyle.compactMax
    readonly property bool canExpandRail: root.width >= WeatherStyle.railExpandMin
    property bool railCollapsed: false
    readonly property bool railExpanded: root.canExpandRail && !root.railCollapsed
    readonly property real railWidth: root.railExpanded ? WeatherStyle.railExpandedWidth : WeatherStyle.railCollapsedWidth
    property bool chartSheetOpen: false
    property string chartSheetId: ""
    readonly property bool sideSheetOpen: root.locationSheetOpen || root.chartSheetOpen
    readonly property real locationSheetWidth: Math.max(WeatherStyle.sheetWidthMin, Math.min(WeatherStyle.sheetWidth, root.width * 0.30))
    readonly property real chartSheetWidth: Math.max(420, Math.min(540, root.width * 0.36))
    readonly property real sideSheetWidth: root.chartSheetOpen ? root.chartSheetWidth : root.locationSheetWidth
    readonly property real pageLayoutWidth: Math.max(0, root.width - WeatherStyle.paneGap * 2
        - (root.compact ? 0 : root.railWidth + WeatherStyle.paneGap)
        - (root.sideSheetOpen && !root.compact ? root.sideSheetWidth + WeatherStyle.paneGap : 0))
    readonly property bool wide: root.pageLayoutWidth >= 920
    readonly property bool shown: root.Window.window?.visible ?? true

    // ── Tabs ────────────────────────────────────────────────────────────
    readonly property var tabs: [
        { id: "overview", icon: "partly_cloudy_day", label: "Overview" },
        { id: "hourly", icon: "schedule", label: "Hourly" },
        { id: "daily", icon: "calendar_month", label: "Daily" },
        { id: "details", icon: "tune", label: "Details" }
    ]
    readonly property var tabIds: root.tabs.map(tab => tab.id)
    readonly property var tabComponents: ({
        overview: overviewComponent,
        hourly: hourlyComponent,
        daily: dailyComponent,
        details: detailsComponent
    })
    readonly property var badges: ({})
    readonly property string locationLabel: {
        if (WeatherAppService.settings.useGps)
            return "Current location";
        return WeatherAppService.data?.location?.name
            || WeatherAppService.resolvedLocation?.name
            || WeatherAppService.activeLocation?.name
            || "Location";
    }
    readonly property var currentTabInfo: root.tabs.find(tab => tab.id === root.shownTab) ?? root.tabs[0]

    property string currentTab: "overview"
    property string shownTab: "overview"
    property bool settingsOpen: false
    property bool locationSheetOpen: false


    Component.onCompleted: {
        root.currentTab = root.initialTab();
        root.shownTab = root.currentTab;
        if (root.shown)
            WeatherAppService.activate();
    }

    onShownChanged: {
        if (root.shown) {
            WeatherAppService.activate();
            Qt.callLater(() => root.forceActiveFocus());
        } else {
            WeatherAppService.deactivate();
            root.locationSheetOpen = false;
            root.settingsOpen = false;
        }
    }

    function initialTab(): string {
        const pending = GlobalStates.weatherAppPendingTab;
        GlobalStates.weatherAppPendingTab = "";
        if (pending === "settings") {
            root.settingsOpen = true;
            return "overview";
        }
        if (root.tabIds.includes(pending))
            return pending;
        const configured = Config.options.weatherApp?.startTab ?? "overview";
        return root.tabIds.includes(configured) ? configured : "overview";
    }

    function selectTab(tabId: string): void {
        if (!root.tabIds.includes(tabId))
            return;
        root.settingsOpen = false;
        root.locationSheetOpen = false;
        root.chartSheetOpen = false;
        root.currentTab = tabId;
        root.shownTab = tabId;
    }

    function toggleSettings(): void {
        root.locationSheetOpen = false;
        root.chartSheetOpen = false;
        root.settingsOpen = !root.settingsOpen;
        if (!root.settingsOpen)
            Qt.callLater(() => root.forceActiveFocus());
    }

    function toggleLocationSheet(): void {
        root.settingsOpen = false;
        root.chartSheetOpen = false;
        root.locationSheetOpen = !root.locationSheetOpen;
    }

    function openChartSheet(chartId: string): void {
        if (!chartId || chartId.length === 0)
            return;
        root.settingsOpen = false;
        root.locationSheetOpen = false;
        root.chartSheetId = chartId;
        root.chartSheetOpen = true;
    }

    Connections {
        target: GlobalStates

        function onWeatherAppPendingTabChanged() {
            const pending = GlobalStates.weatherAppPendingTab;
            if (pending.length === 0)
                return;
            GlobalStates.weatherAppPendingTab = "";
            if (pending === "settings")
                root.settingsOpen = true;
            else
                root.selectTab(pending);
        }
    }

    Connections {
        target: root.Window.window

        function onActiveFocusItemChanged() {
            if (root.Window.window && !root.Window.window.activeFocusItem)
                Qt.callLater(() => root.forceActiveFocus());
        }
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && event.key - Qt.Key_1 < root.tabIds.length) {
            root.selectTab(root.tabIds[event.key - Qt.Key_1]);
            event.accepted = true;
        } else if (ctrl && (event.key === Qt.Key_W || event.key === Qt.Key_Q)) {
            root.closeRequested();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_R) {
            WeatherAppService.refresh(true);
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_Comma) {
            root.toggleSettings();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_L) {
            root.toggleLocationSheet();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.sideSheetOpen) {
            root.locationSheetOpen = false;
            root.chartSheetOpen = false;
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.settingsOpen) {
            root.settingsOpen = false;
            Qt.callLater(() => root.forceActiveFocus());
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            root.closeRequested();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: WeatherStyle.colWindow
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: WeatherStyle.paneGap
        anchors.topMargin: WeatherStyle.gapTiny
        spacing: WeatherStyle.gapTiny

        ClockTopBar {
            id: topBar
            Layout.fillWidth: true
            title: root.settingsOpen ? "Weather settings" : (root.currentTabInfo?.label ?? "Weather")
            subtitle: root.settingsOpen ? "Sources, place, units and refresh" : (pageLoader.item?.pageSubtitle ?? "Weather for ii")
            showBack: root.settingsOpen
            showRailToggle: !root.compact && root.canExpandRail
            railExpanded: root.railExpanded
            onBackRequested: {
                root.settingsOpen = false;
                Qt.callLater(() => root.forceActiveFocus());
            }
            onRailToggled: root.railCollapsed = !root.railCollapsed
            onCloseRequested: root.closeRequested()

            WeatherChip {
                visible: !root.settingsOpen
                iconName: "location_on"
                label: root.compact ? "" : root.locationLabel
                compact: true
                onClicked: root.toggleLocationSheet()

                StyledToolTip {
                    text: root.locationLabel
                }
            }

            ClockIconButton {
                symbol: WeatherAppService.loading ? "sync" : "refresh"
                tooltip: WeatherAppService.loading ? "Updating weather…" : "Refresh weather (Ctrl+R)"
                onClicked: WeatherAppService.refresh(true)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            ClockRail {
                settingsTooltip: "Weather settings"
                Layout.fillHeight: true
                Layout.preferredWidth: root.railWidth
                Layout.rightMargin: WeatherStyle.paneGap
                visible: !root.compact
                tabs: root.tabs
                currentTab: root.currentTab
                expanded: root.railExpanded
                settingsOpen: root.settingsOpen
                badges: root.badges
                onSelected: tabId => root.selectTab(tabId)
                onSettingsRequested: root.toggleSettings()

                Behavior on Layout.preferredWidth {
                    animation: WeatherStyle.motionFast.numberAnimation.createObject(this)
                }
            }

            ColumnLayout {
                id: pageColumn
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !(root.compact && root.sideSheetOpen)
                spacing: WeatherStyle.paneGap

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? 38 : 0
                    visible: WeatherAppService.hasData && WeatherAppService.error.length > 0
                    radius: WeatherStyle.radiusSmall
                    color: WeatherStyle.alpha(WeatherStyle.colErrorContainer, 0.72)

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 12
                            rightMargin: 8
                        }
                        spacing: WeatherStyle.gapSmall

                        MaterialSymbol {
                            text: "error"
                            iconSize: 17
                            fill: 1
                            color: WeatherStyle.colOnErrorContainer
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: WeatherAppService.error
                            font.pixelSize: WeatherStyle.textTiny
                            color: WeatherStyle.colOnErrorContainer
                            elide: Text.ElideRight
                        }

                        RippleButton {
                            implicitHeight: 26
                            leftPadding: 8
                            rightPadding: 8
                            buttonRadius: WeatherStyle.radiusFull
                            colBackground: "transparent"
                            colBackgroundHover: WeatherStyle.alpha(WeatherStyle.colOnErrorContainer, 0.1)
                            onClicked: WeatherAppService.refresh(true)
                            contentItem: StyledText {
                                text: "Retry"
                                font.pixelSize: WeatherStyle.textTiny
                                font.weight: Font.DemiBold
                                color: WeatherStyle.colOnErrorContainer
                            }
                        }

                        WeatherIconButton {
                            symbol: "close"
                            tooltip: "Dismiss"
                            size: 28
                            iconSize: 15
                            colIcon: WeatherStyle.colOnErrorContainer
                            onClicked: WeatherAppService.dismissError()
                        }
                    }
                }

                Item {
                    id: pageArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    WeatherEmptyState {
                        anchors.fill: parent
                        visible: !WeatherAppService.hasData
                        icon: WeatherAppService.missingKey ? "key" : (WeatherAppService.loading ? "cloud_sync" : (WeatherAppService.error.length > 0 ? "cloud_off" : "cloud"))
                        title: WeatherAppService.missingKey
                            ? "An API key is needed"
                            : (WeatherAppService.loading
                                ? "Fetching the forecast…"
                                : (WeatherAppService.error.length > 0 ? "Couldn't fetch weather" : "No forecast yet"))
                        message: WeatherAppService.missingKey
                            ? `${WeatherAppService.currentProvider.name} needs a key before it can answer. Add one in Settings, or switch to a free source.`
                            : (WeatherAppService.loading
                                ? `Asking ${WeatherAppService.currentProvider.name} for ${root.locationLabel}.`
                                : (WeatherAppService.error.length > 0
                                    ? WeatherAppService.error
                                    : "Open Settings to choose a source and a place."))
                        busy: WeatherAppService.loading

                        WeatherChip {
                            visible: WeatherAppService.error.length > 0 || WeatherAppService.missingKey
                            iconName: "refresh"
                            label: "Retry"
                            onClicked: WeatherAppService.refresh(true)
                        }

                        WeatherChip {
                            visible: WeatherAppService.error.length > 0 || WeatherAppService.missingKey
                            iconName: "settings"
                            label: "Settings"
                            onClicked: root.settingsOpen = true
                        }
                    }

                    Loader {
                        id: pageLoader
                        anchors.fill: parent
                        visible: WeatherAppService.hasData
                        focus: !root.settingsOpen && !root.locationSheetOpen
                        sourceComponent: root.tabComponents[root.shownTab] ?? null
                    }

                    Item {
                        id: settingsHost
                        anchors.fill: parent
                        z: 10
                        opacity: root.settingsOpen ? 1 : 0
                        visible: opacity > 0

                        Behavior on opacity {
                            enabled: !WeatherStyle.reducedMotion
                            NumberAnimation {
                                duration: root.settingsOpen ? WeatherStyle.motionEnter.duration : WeatherStyle.motionExit.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: root.settingsOpen ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: WeatherStyle.colWindow
                        }

                        Loader {
                            id: settingsLoader
                            anchors.fill: parent
                            active: settingsHost.visible
                            sourceComponent: settingsComponent
                        }
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

            // ── Location sheet ─────────────────────────────────────────
            Item {
                id: sheetSlot
                Layout.fillHeight: true
                Layout.preferredWidth: root.sideSheetOpen
                    ? (root.compact ? root.width - WeatherStyle.paneGap * 2 : root.sideSheetWidth + WeatherStyle.paneGap)
                    : 0
                visible: Layout.preferredWidth > 1
                clip: true

                Behavior on Layout.preferredWidth {
                    enabled: !WeatherStyle.reducedMotion
                    animation: WeatherStyle.motionDefault.numberAnimation.createObject(this)
                }

                Loader {
                    id: sheetLoader
                    anchors {
                        top: parent.top
                        bottom: parent.bottom
                        right: parent.right
                    }
                    width: root.compact ? root.width - WeatherStyle.paneGap * 2 : root.sideSheetWidth
                    active: root.sideSheetOpen
                    sourceComponent: root.chartSheetOpen ? chartSheetComponent : locationSheetComponent
                }
            }
        }
    }

    Component {
        id: overviewComponent
        WeatherOverviewPage {
            layoutWidth: root.pageLayoutWidth
            compact: root.compact
            wide: root.wide
            onRequestTab: tabId => root.selectTab(tabId)
            onChartRequested: chartId => root.openChartSheet(chartId)
        }
    }

    Component {
        id: hourlyComponent
        WeatherHourlyPage {
            layoutWidth: root.pageLayoutWidth
            compact: root.compact
            wide: root.wide
        }
    }

    Component {
        id: dailyComponent
        WeatherDailyPage {
            layoutWidth: root.pageLayoutWidth
            compact: root.compact
            wide: root.wide
        }
    }

    Component {
        id: locationSheetComponent
        WeatherLocationSheet {
            onCloseRequested: root.locationSheetOpen = false
        }
    }

    Component {
        id: chartSheetComponent
        WeatherChartSheet {
            chartId: root.chartSheetId
            onCloseRequested: root.chartSheetOpen = false
        }
    }

    Component {
        id: detailsComponent
        WeatherDetailsPage {
            layoutWidth: root.pageLayoutWidth
            compact: root.compact
            wide: root.wide
            onChartRequested: chartId => root.openChartSheet(chartId)
        }
    }

    Component {
        id: settingsComponent
        WeatherSettingsPage {
            layoutWidth: root.pageLayoutWidth
            compact: root.compact
            wide: root.wide
        }
    }
}
