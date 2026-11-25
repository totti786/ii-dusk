import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.panadoro.components

/** A deliberate stop before a tag and its history disappear from the selector. */
ClockSheet {
    id: root

    property string tagId: ""
    property ClockSidePanel panels: null

    readonly property var tag: PanadoroService.tagById(root.tagId)

    title: Translation.tr("Delete tag?")
    subtitle: Translation.tr("Past sessions keep their tag name")
    scrollable: false

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 92
        radius: PanadoroStyle.radiusLarge
        color: PanadoroStyle.tagContainer(root.tag)

        RowLayout {
            anchors {
                fill: parent
                margins: PanadoroStyle.gapLarge
            }
            spacing: PanadoroStyle.gap

            MaterialShapeWrappedMaterialSymbol {
                text: PanadoroStyle.tagIcon(root.tag)
                iconSize: 22
                padding: 10
                shape: String(root.tag?.shape ?? "Cookie7Sided")
                color: PanadoroStyle.tagColor(root.tag)
                colSymbol: PanadoroStyle.tagOnSolid(root.tag)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: String(root.tag?.name ?? "")
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: PanadoroStyle.tagOn(root.tag)
                }

                StyledText {
                    text: Translation.tr("This removes it from the timer and stats.")
                    font.pixelSize: PanadoroStyle.textSmall
                    color: PanadoroStyle.tagOn(root.tag)
                    opacity: 0.8
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: PanadoroStyle.gapSmall
        text: Translation.tr("Your finished sessions are kept, so the time you already spent still counts. You can create a tag with the same name later.")
        wrapMode: Text.WordWrap
        font.pixelSize: PanadoroStyle.textNormal
        color: PanadoroStyle.colSubtext
    }

    actions: ColumnLayout {
        Layout.fillWidth: true
        spacing: PanadoroStyle.gapSmall

        ClockButton {
            Layout.fillWidth: true
            danger: true
            symbol: "delete"
            label: Translation.tr("Delete tag")
            onClicked: {
                PanadoroService.deleteTag(root.tagId);
                root.close();
            }
        }

        ClockButton {
            Layout.fillWidth: true
            symbol: "close"
            label: Translation.tr("Cancel")
            onClicked: root.close()
        }
    }
}
