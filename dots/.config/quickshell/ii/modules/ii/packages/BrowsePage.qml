pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** Find software to install from the repositories and, if asked, the AUR. */
Rectangle {
    id: root

    property bool compact: false
    property real layoutWidth: root.width
    property bool active: true

    signal detailRequested(string name)
    signal confirm(string title, string message, string label, bool danger, var callback)

    property bool includeAur: false

    readonly property real padding: 0
    readonly property real contentWidth: root.width

    color: "transparent"

    function runSearch(): void {
        PackagesService.search(search.text, root.includeAur);
    }

    onIncludeAurChanged: root.runSearch()
    onActiveChanged: if (root.active) search.focusInput()

    Timer {
        id: debounce
        interval: 450
        onTriggered: root.runSearch()
    }

    ColumnLayout {
        x: Math.max(root.padding, (root.width - root.contentWidth) / 2)
        y: root.padding
        width: root.contentWidth
        height: root.height - root.padding * 2
        spacing: ClockStyle.gap

        ClockHero {
            Layout.fillWidth: true
            compact: root.compact
            symbol: "travel_explore"
            title: Translation.tr("Find new software")
            text: Translation.tr("Search the repositories, or the AUR for community-made packages, and see what a package does before installing it.")
        }

        PackageSearchField {
            id: search
            placeholder: Translation.tr("Search for software to install")
            onTextChanged: debounce.restart()
            onAccepted: {
                debounce.stop();
                root.runSearch();
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall
            ClockChip {
                symbol: root.includeAur ? "check" : "deployed_code"
                label: Translation.tr("Include the AUR")
                selected: root.includeAur
                onClicked: root.includeAur = !root.includeAur
            }
            StyledText {
                Layout.fillWidth: true
                text: root.includeAur ? Translation.tr("AUR software is community-made and is built on your machine.") : ""
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
                elide: Text.ElideRight
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: ClockStyle.radiusCard
            color: ClockStyle.colPane

            ListView {
                WheelScroll {}
                id: list
                anchors.fill: parent
                anchors.margins: ClockStyle.gap
                clip: true
                spacing: ClockStyle.gapTiny
                boundsBehavior: Flickable.StopAtBounds
                model: PackagesService.results
                cacheBuffer: 400

                header: StyledText {
                    width: list.width
                    visible: text.length > 0
                    height: visible ? implicitHeight + ClockStyle.gapSmall : 0
                    text: PackagesService.searching ? Translation.tr("Searching…")
                        : PackagesService.resultsTruncated ? Translation.tr("Showing the first 200 matches. Narrow the search.")
                        : PackagesService.searchedQuery !== "" ? Translation.tr("%1 matches").arg(PackagesService.results.length) : ""
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                }

                delegate: PackageRow {
                    required property var modelData
                    width: list.width
                    name: modelData.name
                    version: modelData.version
                    description: modelData.description
                    repo: modelData.repo
                    installed: modelData.installed
                    onClicked: root.detailRequested(modelData.name)

                    ClockButton {
                        visible: !modelData.installed
                        variant: modelData.repo === "aur" ? "tonal" : "filled"
                        symbol: modelData.repo === "aur" ? "terminal" : "download"
                        label: modelData.repo === "aur" ? Translation.tr("Install in terminal") : Translation.tr("Install")
                        enabled: !PackagesService.taskRunning
                        onClicked: {
                            if (modelData.repo === "aur")
                                root.confirm(Translation.tr("Install %1 from the AUR?").arg(modelData.name),
                                    Translation.tr("A terminal opens where yay shows the recipe and asks before it builds and installs anything."),
                                    Translation.tr("Open terminal"), false, () => PackagesService.installAur(modelData.name));
                            else
                                PackagesService.installRepo([modelData.name]);
                        }
                    }
                }
            }

            ClockEmptyState {
                anchors.centerIn: parent
                visible: PackagesService.results.length === 0 && !PackagesService.searching
                symbol: "search"
                title: PackagesService.searchedQuery === "" ? Translation.tr("Search for anything") : Translation.tr("Nothing found")
                subtitle: PackagesService.searchedQuery === "" ? Translation.tr("Type a name or a few words about what you need")
                    : Translation.tr("Try fewer words%1").arg(root.includeAur ? "" : Translation.tr(", or include the AUR"))
            }
        }
    }
}
