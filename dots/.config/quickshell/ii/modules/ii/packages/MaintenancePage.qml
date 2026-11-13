pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "PackagesFormat.js" as Fmt

/** Tidying: dependencies nothing needs any more, and the downloads pacman keeps. */
Rectangle {
    id: root

    property bool compact: false
    property real layoutWidth: root.width
    property bool active: true

    signal confirm(string title, string message, string label, bool danger, var callback)

    readonly property real padding: 0
    readonly property real contentWidth: root.width

    color: "transparent"

    onActiveChanged: if (root.active) PackagesService.loadMaintenance()
    Component.onCompleted: PackagesService.loadMaintenance()

    Flickable {
        WheelScroll {}
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + root.padding * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            x: Math.max(root.padding, (flick.width - root.contentWidth) / 2)
            y: root.padding
            width: root.contentWidth
            spacing: ClockStyle.gap

            ClockHero {
                Layout.fillWidth: true
                compact: root.compact
                symbol: "cleaning_services"
                title: Translation.tr("Keep the system tidy")
                text: Translation.tr("Remove dependencies nothing needs any more and clear the downloaded package files.")
            }

            // ── Orphans ──
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: orphanCol.implicitHeight + ClockStyle.gapLarge * 2
                radius: ClockStyle.radiusExtraLarge
                color: ClockStyle.colPane

                ColumnLayout {
                    id: orphanCol
                    anchors.fill: parent
                    anchors.margins: ClockStyle.gapLarge
                    spacing: ClockStyle.gapSmall

                    RowLayout {
                        spacing: ClockStyle.gap
                        MaterialSymbol {
                            text: "scan_delete"
                            iconSize: 28
                            color: ClockStyle.colOnSurfaceVariant
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: Translation.tr("Unused dependencies")
                                color: ClockStyle.colOnBackground
                                font.pixelSize: ClockStyle.textLarge
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                text: PackagesService.orphans.names.length === 0 ? Translation.tr("Nothing to clean up")
                                    : Translation.tr("%1 packages, %2, installed for something that is gone").arg(PackagesService.orphans.names.length).arg(Fmt.bytes(PackagesService.orphans.size))
                                color: ClockStyle.colSubtext
                                font.pixelSize: ClockStyle.textSmall
                            }
                        }
                        ClockButton {
                            visible: PackagesService.orphans.names.length > 0
                            variant: "tonal"
                            danger: true
                            symbol: "delete_sweep"
                            label: Translation.tr("Remove all")
                            enabled: !PackagesService.taskRunning
                            onClicked: root.confirm(Translation.tr("Remove %1 unused packages?").arg(PackagesService.orphans.names.length),
                                PackagesService.orphans.names.slice(0, 12).join(", ") + (PackagesService.orphans.names.length > 12 ? "…" : ""),
                                Translation.tr("Remove"), true, () => PackagesService.removeOrphans())
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        visible: PackagesService.orphans.names.length > 0
                        spacing: ClockStyle.gapTiny
                        Repeater {
                            model: PackagesService.orphans.names.slice(0, 60)
                            delegate: ClockChip {
                                required property string modelData
                                height_: 28
                                label: modelData
                            }
                        }
                    }
                }
            }

            // ── Cache ──
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: cacheCol.implicitHeight + ClockStyle.gapLarge * 2
                radius: ClockStyle.radiusExtraLarge
                color: ClockStyle.colPane

                ColumnLayout {
                    id: cacheCol
                    anchors.fill: parent
                    anchors.margins: ClockStyle.gapLarge
                    spacing: ClockStyle.gap

                    RowLayout {
                        spacing: ClockStyle.gap
                        MaterialSymbol {
                            text: "inventory_2"
                            iconSize: 28
                            color: ClockStyle.colOnSurfaceVariant
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: Translation.tr("Package cache")
                                color: ClockStyle.colOnBackground
                                font.pixelSize: ClockStyle.textLarge
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                text: Translation.tr("%1 in %2 files. Old downloads pacman keeps in case you need to go back.")
                                    .arg(Fmt.bytes(PackagesService.cache.size)).arg(PackagesService.cache.files)
                                color: ClockStyle.colSubtext
                                font.pixelSize: ClockStyle.textSmall
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                    }
                    RowLayout {
                        spacing: ClockStyle.gapSmall
                        ClockButton {
                            variant: "tonal"
                            symbol: "cleaning_services"
                            label: Translation.tr("Keep the last 2 versions")
                            enabled: !PackagesService.taskRunning
                            onClicked: root.confirm(Translation.tr("Trim the cache?"),
                                Translation.tr("Keeps the two newest downloads of every package and deletes older ones. You can still go back one version."),
                                Translation.tr("Trim"), false, () => PackagesService.cleanCache(2, false))
                        }
                        ClockButton {
                            variant: "tonal"
                            danger: true
                            symbol: "delete_forever"
                            label: Translation.tr("Delete uninstalled")
                            enabled: !PackagesService.taskRunning
                            onClicked: root.confirm(Translation.tr("Delete cached downloads of uninstalled packages?"),
                                Translation.tr("Packages you have installed are not touched."),
                                Translation.tr("Delete"), true, () => PackagesService.cleanCache(0, true))
                        }
                    }
                }
            }
        }
    }
}
