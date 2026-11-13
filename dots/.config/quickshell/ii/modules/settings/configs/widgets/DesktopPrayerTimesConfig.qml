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

    readonly property var options: Config.options.background.widgets.prayer_times

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
            text: Translation.tr("Prayer Times Widget Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Prayer Times Settings")
        icon: "mosque"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("prayer_times")

            PagePlaceholder {
                anchors.fill: parent
                icon: "mosque"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Prayer Times Widget disabled")
                description: Translation.tr("Enable the Prayer Times Widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("prayer_times")

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Uses the weather location (Bar → Weather): %1").arg(PrayerTimes.city || Translation.tr("not resolved yet"))
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
            }

            ContentSubsectionLabel {
                text: Translation.tr("Calculation method")
            }

            ConfigSelectionArray {
                Layout.fillWidth: true
                currentValue: root.options.method ?? 5
                onSelected: value => root.options.method = Number(value)
                options: [
                    { displayName: Translation.tr("Egyptian"), value: 5, icon: "public" },
                    { displayName: Translation.tr("Umm al-Qura"), value: 4, icon: "location_city" },
                    { displayName: Translation.tr("MWL"), value: 3, icon: "language" },
                    { displayName: Translation.tr("ISNA"), value: 2, icon: "map" },
                    { displayName: Translation.tr("Karachi"), value: 1, icon: "south_asia" }
                ]
            }

            DesktopWidgetVisualOptions {
                widgetId: "prayer_times"
                Layout.fillWidth: true
            }
        }
    }
}
