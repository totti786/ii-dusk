import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.widgets

// Generic options page for extension widgets: renders the widget's configSchema.
// The Edit Mode panel sets widgetId ("ext:<dir>") after loading.
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    property string widgetId: ""
    readonly property string extId: root.widgetId.replace(/^ext:/, "")
    readonly property var schema: WidgetExtensionManager.installedWidgets[root.extId]?.widgetJson?.configSchema ?? ({})

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
            text: WidgetExtensionManager.installedWidgets[root.extId]?.name ?? Translation.tr("Widget options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Options")
        icon: "tune"

        ExtensionWidgetSettingsRenderer {
            extId: root.extId
            schema: root.schema
        }
    }
}
