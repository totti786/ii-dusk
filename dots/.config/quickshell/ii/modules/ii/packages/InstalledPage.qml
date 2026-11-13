pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "PackagesFormat.js" as Fmt

/** Every package on the machine, searchable, with the ones you chose apart from the ones that came along. */
Rectangle {
    id: root

    property bool compact: false
    property real layoutWidth: root.width
    property bool active: true

    signal detailRequested(string name)
    signal confirm(string title, string message, string label, bool danger, var callback)

    property string filter: "all"
    property string sort: "name"

    readonly property real padding: 0
    readonly property real contentWidth: root.width
    readonly property var shown: {
        const q = search.text.trim().toLowerCase();
        let list = PackagesService.installed.filter(p => {
            if (root.filter === "explicit" && !p.explicit)
                return false;
            if (root.filter === "deps" && p.explicit)
                return false;
            if (root.filter === "aur" && p.repo !== "aur")
                return false;
            return q === "" || p.name.toLowerCase().includes(q) || p.description.toLowerCase().includes(q);
        });
        if (root.sort === "size")
            list = list.slice().sort((a, b) => b.size - a.size);
        return list;
    }

    color: "transparent"

    onActiveChanged: if (root.active && PackagesService.installed.length === 0) PackagesService.loadInstalled()
    Component.onCompleted: if (PackagesService.installed.length === 0) PackagesService.loadInstalled()

    ColumnLayout {
        x: Math.max(root.padding, (root.width - root.contentWidth) / 2)
        y: root.padding
        width: root.contentWidth
        height: root.height - root.padding * 2
        spacing: ClockStyle.gap

        ClockHero {
            Layout.fillWidth: true
            compact: root.compact
            symbol: "inventory_2"
            title: Translation.tr("Everything on this computer")
            text: Translation.tr("Search what is installed, see how much space each package takes, and remove what you no longer use.")
        }

        PackageSearchField {
            id: search
            placeholder: Translation.tr("Search %1 installed packages").arg(PackagesService.installed.length)
        }

        Flow {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall
            Repeater {
                model: [
                    { id: "all", label: Translation.tr("All") },
                    { id: "explicit", label: Translation.tr("Installed by you") },
                    { id: "deps", label: Translation.tr("Dependencies") },
                    { id: "aur", label: Translation.tr("AUR") }
                ]
                delegate: ClockChip {
                    required property var modelData
                    label: modelData.label
                    selected: root.filter === modelData.id
                    onClicked: root.filter = modelData.id
                }
            }
            Item { width: ClockStyle.gap; height: 1 }
            ClockChip {
                symbol: "sort_by_alpha"
                label: Translation.tr("A–Z")
                selected: root.sort === "name"
                onClicked: root.sort = "name"
            }
            ClockChip {
                symbol: "storage"
                label: Translation.tr("Biggest")
                selected: root.sort === "size"
                onClicked: root.sort = "size"
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: PackagesService.loadingInstalled && PackagesService.installed.length === 0 ? Translation.tr("Reading the package database…")
                : PackagesService.installedError.length > 0 ? PackagesService.installedError
                : Translation.tr("%1 packages").arg(root.shown.length)
            color: PackagesService.installedError.length > 0 ? ClockStyle.colError : ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textSmall
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
                model: root.shown
                cacheBuffer: 400

                delegate: PackageRow {
                    required property var modelData
                    width: list.width
                    name: modelData.name
                    version: modelData.version
                    description: modelData.description
                    repo: modelData.repo
                    size: modelData.size
                    onClicked: root.detailRequested(modelData.name)

                    ClockIconButton {
                        symbol: "delete"
                        tooltip: Translation.tr("Remove")
                        enabled: !PackagesService.taskRunning
                        onClicked: root.confirm(Translation.tr("Remove %1?").arg(modelData.name),
                            modelData.requiredBy > 0
                                ? Translation.tr("%1 other packages need it, so pacman will refuse unless they go too. Its unused dependencies are removed with it.").arg(modelData.requiredBy)
                                : Translation.tr("It and the dependencies nothing else uses will be removed. Your own files and settings stay."),
                            Translation.tr("Remove"), true, () => PackagesService.remove([modelData.name]))
                    }
                }
            }
        }
    }
}
