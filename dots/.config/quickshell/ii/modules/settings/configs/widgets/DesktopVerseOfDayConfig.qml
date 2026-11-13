import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.widgets

ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var options: Config.options.background.widgets.diwan_verse

    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Verse of the Day Widget Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Verse of the Day Settings")
        icon: "auto_stories"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("diwan_verse")

            PagePlaceholder {
                anchors.fill: parent
                icon: "auto_stories"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Verse of the Day Widget disabled")
                description: Translation.tr("Enable the Verse of the Day Widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("diwan_verse")

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("One verse a day from the Diwan poetry reader, the same pick as its home page. Click the card to open the poem.")
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
            }

            DesktopWidgetVisualOptions {
                widgetId: "diwan_verse"
                Layout.fillWidth: true
            }
        }
    }
}
