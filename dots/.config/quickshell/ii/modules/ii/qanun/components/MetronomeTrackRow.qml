import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.qanun

/** One click track: enable, beat division, sound pack and level. */
Rectangle {
    id: root

    property var track: ({})
    property color accent: QanunStyle.colTrackPulse
    property bool expanded: false
    property bool removable: false

    signal patchRequested(var patch)
    signal removeRequested()

    implicitHeight: content.implicitHeight + 20
    radius: Appearance.rounding.normal
    color: root.expanded ? QanunStyle.colField : QanunStyle.colField
    border.width: 0

    ColumnLayout {
        id: content
        anchors {
            fill: parent
            margins: 10
        }
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                width: 10
                height: 10
                radius: 5
                color: root.accent
            }

            StyledText {
                Layout.fillWidth: true
                text: String(root.track.name ?? ("Track " + (root.index + 1)))
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: QanunStyle.colOnSurface
                elide: Text.ElideRight
            }

            StyledSwitch {
                checked: Boolean(root.track.enabled ?? true)
                onClicked: root.patchRequested({ enabled: !Boolean(root.track.enabled ?? true) })
            }

            ClockIconButton {
                symbol: root.expanded ? "expand_less" : "expand_more"
                size: 32
                iconSize: Appearance.font.pixelSize.normal
                tooltip: root.expanded ? Translation.tr("Hide track settings") : Translation.tr("Track settings")
                onClicked: root.expanded = !root.expanded
            }

            ClockIconButton {
                visible: root.removable
                symbol: "delete"
                size: 32
                iconSize: Appearance.font.pixelSize.normal
                tooltip: Translation.tr("Remove track")
                onClicked: root.removeRequested()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.expanded
            spacing: 8

            StyledText {
                text: Translation.tr("Divide")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: QanunStyle.colSubtext
            }

            Repeater {
                model: [1, 2, 3, 4, 6, 8]

                ClockChip {
                    required property int modelData
                    label: String(modelData)
                    selected: Number(root.track.division ?? 1) === modelData
                    height_: 28
                    onClicked: root.patchRequested({ division: modelData })
                }
            }

            Item { Layout.fillWidth: true }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.expanded
            spacing: 8

            StyledText {
                text: Translation.tr("Sound")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: QanunStyle.colSubtext
            }

            Repeater {
                model: QanunData.metronomeSoundPacks()

                ClockChip {
                    required property var modelData
                    label: modelData.name
                    selected: String(root.track.sound ?? "wood") === modelData.id
                    height_: 28
                    onClicked: root.patchRequested({ sound: modelData.id })
                }
            }

            Item { Layout.fillWidth: true }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.expanded
            spacing: 8

            MaterialSymbol {
                text: "volume_up"
                iconSize: Appearance.font.pixelSize.normal
                color: QanunStyle.colSubtext
            }

            StyledSlider {
                Layout.fillWidth: true
                from: 0
                to: 1
                value: Number(root.track.volume ?? 0.7)
                configuration: StyledSlider.Configuration.XS
                onMoved: root.patchRequested({ volume: value })
            }

            StyledText {
                Layout.preferredWidth: 34
                horizontalAlignment: Text.AlignRight
                text: Math.round(Number(root.track.volume ?? 0.7) * 100) + "%"
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.numbers
                color: QanunStyle.colSubtext
            }
        }
    }
}
