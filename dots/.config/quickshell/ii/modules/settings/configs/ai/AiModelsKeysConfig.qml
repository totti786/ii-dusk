import QtQuick
import QtQuick.Layouts
import qs.services
import qs.services.ai.blocks
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    anchors.fill: parent

    property alias activeSubPage: subPageOverlay.activeSubPage

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.rounding.small

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: Math.round(Appearance.font.pixelSize.huge * 1.8)
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Agents & Sign-in")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "account_circle"
            title: Translation.tr("Signed-in agents")

            AiApiKeyManager {
                Layout.fillWidth: true
            }
        }


    }

    property bool showBackButton: false
    signal goBack()

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
