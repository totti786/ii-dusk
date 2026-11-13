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

    readonly property var options: Config.options.background.widgets.quran_ayah

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
            text: Translation.tr("Quran Ayah Widget Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Quran Ayah Settings")
        icon: "menu_book"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("quran_ayah")

            PagePlaceholder {
                anchors.fill: parent
                icon: "menu_book"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Quran Ayah Widget disabled")
                description: Translation.tr("Enable the Quran Ayah Widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("quran_ayah")

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("An ayah a day with its translation. While the Quran player recites, the card follows the recitation. Click the text to open the reader at that ayah.")
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
            }

            DesktopWidgetVisualOptions {
                widgetId: "quran_ayah"
                Layout.fillWidth: true
            }
        }
    }
}
