pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "PackagesFormat.js" as Fmt

/** Everything the databases say about one package, with the buttons that act on it. */
Rectangle {
    id: root

    readonly property var d: PackagesService.detail
    readonly property bool isInstalled: root.d.source === "installed"
    readonly property bool isAur: (root.d.repo ?? "") === "aur" || root.d.source === "aur"
    readonly property bool foreign: root.isInstalled && PackagesService.installed.some(p => p.name === root.d.name && p.repo === "aur")

    signal closeRequested()
    signal removeRequested(string name)
    signal installRequested(string name, bool aur)
    signal openRequested(string name)

    radius: ClockStyle.radiusExtraLarge
    color: ClockStyle.colSheet
    clip: true

    Flickable {
        WheelScroll {}
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + ClockStyle.gapHuge * 2
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            x: ClockStyle.gapLarge
            y: ClockStyle.gapLarge
            width: flick.width - ClockStyle.gapLarge * 2
            spacing: ClockStyle.gap

            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.d.name ?? ""
                        color: ClockStyle.colOnBackground
                        font.pixelSize: ClockStyle.textLarge
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: `${root.d.version ?? ""}${root.d.repo ? "  ·  " + root.d.repo : ""}`
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                    }
                }
                ClockIconButton {
                    symbol: "close"
                    tooltip: Translation.tr("Close")
                    onClicked: root.closeRequested()
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: PackagesService.loadingDetail
                text: Translation.tr("Loading…")
                color: ClockStyle.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.d.description ?? ""
                color: ClockStyle.colOnBackground
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                visible: !PackagesService.loadingDetail && !root.d.error
                spacing: ClockStyle.gapSmall
                ClockButton {
                    visible: !root.isInstalled
                    variant: "filled"
                    symbol: "download"
                    label: root.isAur ? Translation.tr("Install in terminal") : Translation.tr("Install")
                    onClicked: root.installRequested(root.d.name, root.isAur)
                }
                ClockButton {
                    visible: root.isInstalled
                    variant: "tonal"
                    danger: true
                    symbol: "delete"
                    label: Translation.tr("Remove")
                    onClicked: root.removeRequested(root.d.name)
                }
            }

            Repeater {
                model: [
                    { label: Translation.tr("Installed size"), value: root.d.size > 0 ? Fmt.bytes(root.d.size) : "" },
                    { label: Translation.tr("Download size"), value: root.d.downloadSize > 0 ? Fmt.bytes(root.d.downloadSize) : "" },
                    { label: Translation.tr("Installed"), value: root.d.installedOn ?? "" },
                    { label: Translation.tr("Reason"), value: root.d.reason ?? "" },
                    { label: Translation.tr("License"), value: (root.d.licenses ?? []).join(", ") },
                    { label: Translation.tr("Website"), value: root.d.url ?? "" },
                    { label: Translation.tr("Packager"), value: root.d.packager ?? "" }
                ].filter(row => row.value !== "")
                delegate: ColumnLayout {
                    id: factRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: factRow.modelData.label
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: factRow.modelData.value
                        color: ClockStyle.colOnBackground
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }

            Repeater {
                model: [
                    { label: Translation.tr("Depends on"), items: root.d.depends ?? [] },
                    { label: Translation.tr("Needed by"), items: root.d.requiredBy ?? [] },
                    { label: Translation.tr("Optional"), items: root.d.optional ?? [] },
                    { label: Translation.tr("Provides"), items: root.d.provides ?? [] },
                    { label: Translation.tr("Conflicts with"), items: root.d.conflicts ?? [] }
                ].filter(group => group.items.length > 0)
                delegate: ColumnLayout {
                    id: group
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapTiny
                    StyledText {
                        text: `${group.modelData.label} (${group.modelData.items.length})`
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapTiny
                        Repeater {
                            model: group.modelData.items.slice(0, 40)
                            delegate: ClockChip {
                                required property string modelData
                                // "bash-completion: for tab completion" -> "bash-completion"
                                readonly property string pkgName: modelData.split(/[:<>=]/)[0].trim()
                                height_: 28
                                label: modelData.length > 38 ? modelData.slice(0, 36) + "…" : modelData
                                onClicked: root.openRequested(pkgName)
                            }
                        }
                        StyledText {
                            visible: group.modelData.items.length > 40
                            text: Translation.tr("and %1 more").arg(group.modelData.items.length - 40)
                            color: ClockStyle.colSubtext
                            font.pixelSize: ClockStyle.textSmall
                        }
                    }
                }
            }
        }
    }
}
