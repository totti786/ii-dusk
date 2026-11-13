pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "PackagesFormat.js" as Fmt

/** What is waiting to be installed: the repositories (updated in the app) and the AUR (in a terminal). */
Rectangle {
    id: root

    property bool compact: false
    property real layoutWidth: root.width

    signal detailRequested(string name)
    signal confirm(string title, string message, string label, bool danger, var callback)

    readonly property real padding: 0
    readonly property real contentWidth: root.width
    readonly property bool restartAdvised: PackagesService.repoUpdates.some(p => Fmt.needsRestart(p.name))
    // One flat list so a single ListView draws the headings and the rows
    readonly property var rows: {
        const out = [];
        if (PackagesService.repoUpdates.length > 0) {
            out.push({ "heading": Translation.tr("Repositories"), "count": PackagesService.repoUpdates.length });
            PackagesService.repoUpdates.forEach(p => out.push(p));
        }
        if (PackagesService.aurUpdates.length > 0) {
            out.push({ "heading": Translation.tr("AUR"), "count": PackagesService.aurUpdates.length });
            PackagesService.aurUpdates.forEach(p => out.push(p));
        }
        return out;
    }

    color: "transparent"

    ColumnLayout {
        x: Math.max(root.padding, (root.width - root.contentWidth) / 2)
        y: root.padding
        width: root.contentWidth
        height: root.height - root.padding * 2
        spacing: ClockStyle.gap

        ClockHero {
            Layout.fillWidth: true
            compact: root.compact
            symbol: PackagesService.checking ? "sync" : (PackagesService.updateCount > 0 ? "system_update_alt" : "check")
            title: PackagesService.checking && PackagesService.lastChecked === 0 ? Translation.tr("Looking for updates…")
                : PackagesService.updateCount === 0 ? Translation.tr("Everything is up to date")
                : Translation.tr("%1 updates available").arg(PackagesService.updateCount)
            text: {
                const parts = [];
                if (PackagesService.repoUpdates.length > 0)
                    parts.push(Translation.tr("%1 from the repositories").arg(PackagesService.repoUpdates.length));
                if (PackagesService.aurUpdates.length > 0)
                    parts.push(Translation.tr("%1 from the AUR").arg(PackagesService.aurUpdates.length));
                if (PackagesService.lastChecked > 0)
                    parts.push(Translation.tr("checked %1").arg(Fmt.ago(PackagesService.lastChecked)));
                return parts.join("  ·  ");
            }
            trailing: ClockIconButton {
                symbol: "refresh"
                tooltip: Translation.tr("Check again")
                enabled: !PackagesService.checking
                onClicked: PackagesService.checkUpdates()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.restartAdvised
            implicitHeight: warn.implicitHeight + ClockStyle.gap * 2
            radius: ClockStyle.radiusLarge
            color: ClockStyle.colTertiaryContainer
            RowLayout {
                id: warn
                anchors.fill: parent
                anchors.margins: ClockStyle.gap
                spacing: ClockStyle.gap
                MaterialSymbol {
                    text: "restart_alt"
                    iconSize: 22
                    color: ClockStyle.colOnTertiaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("This includes the kernel or core system libraries. Restart after updating.")
                    color: ClockStyle.colOnTertiaryContainer
                    wrapMode: Text.WordWrap
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: PackagesService.updateCount > 0
            spacing: ClockStyle.gapSmall
            ClockButton {
                visible: PackagesService.repoUpdates.length > 0
                variant: "filled"
                symbol: "system_update_alt"
                label: Translation.tr("Update repositories")
                enabled: !PackagesService.taskRunning
                onClicked: root.confirm(Translation.tr("Update the system?"),
                    Translation.tr("This runs a full upgrade of %1 packages from the repositories. It asks for your password. Do not turn the computer off until it finishes.").arg(PackagesService.repoUpdates.length),
                    Translation.tr("Update"), false, () => PackagesService.upgradeRepo())
            }
            ClockButton {
                visible: PackagesService.aurUpdates.length > 0
                variant: "tonal"
                symbol: "terminal"
                label: Translation.tr("Update AUR in terminal")
                onClicked: root.confirm(Translation.tr("Update the AUR packages?"),
                    Translation.tr("AUR packages are built from recipes anyone can edit, so this opens a terminal where yay shows what it will do and asks first."),
                    Translation.tr("Open terminal"), false, () => PackagesService.updateAur())
            }
            Item { Layout.fillWidth: true }
        }

        StyledText {
            Layout.fillWidth: true
            visible: PackagesService.checkError.length > 0
            text: PackagesService.checkError
            color: ClockStyle.colError
            font.pixelSize: ClockStyle.textSmall
            wrapMode: Text.WordWrap
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
                model: root.rows
                cacheBuffer: 600

                delegate: Item {
                    id: entry
                    required property var modelData
                    readonly property bool isHeading: modelData.heading !== undefined
                    width: list.width
                    height: isHeading ? 30 : 64

                    StyledText {
                        anchors.bottom: parent.bottom
                        visible: entry.isHeading
                        text: entry.isHeading ? `${entry.modelData.heading}  ·  ${entry.modelData.count}` : ""
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: Font.DemiBold
                    }
                    PackageRow {
                        anchors.fill: parent
                        visible: !entry.isHeading
                        name: entry.modelData.name ?? ""
                        versionChange: entry.isHeading ? "" : `${entry.modelData.old}  →  ${entry.modelData.new}`
                        repo: entry.modelData.repo ?? ""
                        restartAdvised: !entry.isHeading && Fmt.needsRestart(entry.modelData.name)
                        onClicked: root.detailRequested(entry.modelData.name)
                    }
                }
            }
        }
    }
}
