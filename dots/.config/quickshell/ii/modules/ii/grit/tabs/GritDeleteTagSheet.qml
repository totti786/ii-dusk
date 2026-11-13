import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.grit.components

/** A deliberate stop before a tag and its history disappear from the selector. */
ClockSheet {
    id: root

    property string tagId: ""
    property ClockSidePanel panels: null

    readonly property var tag: GritService.tagById(root.tagId)

    title: Translation.tr("Delete tag?")
    subtitle: Translation.tr("Past sessions keep their tag name")
    scrollable: false

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 92
        radius: GritStyle.radiusLarge
        color: GritStyle.tagContainer(root.tag)

        RowLayout {
            anchors {
                fill: parent
                margins: GritStyle.gapLarge
            }
            spacing: GritStyle.gap

            MaterialShapeWrappedMaterialSymbol {
                text: GritStyle.tagIcon(root.tag)
                iconSize: 22
                padding: 10
                shape: String(root.tag?.shape ?? "Cookie7Sided")
                color: GritStyle.tagColor(root.tag)
                colSymbol: GritStyle.tagOnSolid(root.tag)
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
                    color: GritStyle.tagOn(root.tag)
                }

                StyledText {
                    text: Translation.tr("This removes it from the timer and stats.")
                    font.pixelSize: GritStyle.textSmall
                    color: GritStyle.tagOn(root.tag)
                    opacity: 0.8
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: GritStyle.gapSmall
        text: Translation.tr("Your finished sessions are kept, so the time you already spent still counts. You can create a tag with the same name later.")
        wrapMode: Text.WordWrap
        font.pixelSize: GritStyle.textNormal
        color: GritStyle.colSubtext
    }

    actions: ColumnLayout {
        Layout.fillWidth: true
        spacing: GritStyle.gapSmall

        ClockButton {
            Layout.fillWidth: true
            danger: true
            symbol: "delete"
            label: Translation.tr("Delete tag")
            onClicked: {
                GritService.deleteTag(root.tagId);
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
