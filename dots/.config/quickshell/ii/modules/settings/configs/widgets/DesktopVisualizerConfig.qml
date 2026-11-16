import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var configEntry: Config.options.background.widgets.visualizer ?? ({})

    readonly property bool isAnyActive: {
        return Config.isWidgetActive("visualizer")
            || Config.isWidgetActive("visualizer_ring")
            || Config.isWidgetActive("visualizer_aurora")
            || Config.isWidgetActive("visualizer_mirror")
            || Config.isWidgetActive("visualizer_dots")
            || Config.isWidgetActive("visualizer_bars");
    }

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
            text: Translation.tr("Visualizer Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Visualizer Settings")
        icon: "graphic_eq"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !root.isAnyActive

            PagePlaceholder {
                anchors.fill: parent
                icon: "graphic_eq"
                shape: MaterialShape.Shape.Burst
                title: Translation.tr("Visualizer not on desktop")
                description: Translation.tr("Add the Visualizer widget from Desktop Widgets or Edit Mode (Super+Shift+E) to use it.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.isAnyActive

            ContentSubsectionLabel {
                text: Translation.tr("Style & Appearance")
            }

            ConfigSelectionArray {
                text: Translation.tr("Visualizer Style")
                icon: "style"
                currentValue: root.configEntry.style ?? "bars"
                onSelected: newValue => {
                    Config.options.background.widgets.visualizer.style = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Classic Bars"),
                        icon: "bar_chart",
                        value: "bars"
                    },
                    {
                        displayName: Translation.tr("Mirror Wave"),
                        icon: "equalizer",
                        value: "mirror"
                    },
                    {
                        displayName: Translation.tr("Aurora Wave"),
                        icon: "waves",
                        value: "aurora"
                    },
                    {
                        displayName: Translation.tr("Album Ring"),
                        icon: "album",
                        value: "ring"
                    },
                    {
                        displayName: Translation.tr("Dots Matrix"),
                        icon: "grid_on",
                        value: "dots"
                    }
                ]
            }

            ConfigSelectionArray {
                text: Translation.tr("Colors")
                icon: "palette"
                enabled: (root.configEntry.style ?? "bars") !== "bars"
                currentValue: root.configEntry.colorSource ?? "theme"
                onSelected: newValue => {
                    Config.options.background.widgets.visualizer.colorSource = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Theme"),
                        icon: "palette",
                        value: "theme"
                    },
                    {
                        displayName: Translation.tr("Album Cover"),
                        icon: "album",
                        value: "cover"
                    }
                ]
            }

            Item { Layout.preferredHeight: 4 }

            ContentSubsectionLabel {
                text: Translation.tr("Audio Tuning")
            }

            ConfigSlider {
                text: Translation.tr("Sensitivity (%)")
                buttonIcon: "tune"
                usePercentTooltip: false
                value: (root.configEntry.sensitivity ?? 1) * 100
                from: 50
                to: 300
                stopIndicatorValues: [100]
                onValueChanged: {
                    Config.options.background.widgets.visualizer.sensitivity = Math.round(value) / 100;
                }
            }

            Item { Layout.preferredHeight: 4 }

            ContentSubsectionLabel {
                text: Translation.tr("Dimensions")
            }

            ConfigSlider {
                text: Translation.tr("Band Height (px)")
                buttonIcon: "height"
                usePercentTooltip: false
                enabled: (root.configEntry.style ?? "bars") !== "ring"
                value: root.configEntry.height ?? 260
                from: 120
                to: 600
                stopIndicatorValues: [260]
                onValueChanged: {
                    Config.options.background.widgets.visualizer.height = Math.round(value);
                }
            }

            ConfigSlider {
                text: Translation.tr("Ring Diameter (px)")
                buttonIcon: "aspect_ratio"
                usePercentTooltip: false
                enabled: (root.configEntry.style ?? "bars") === "ring"
                value: root.configEntry.ringSize ?? 380
                from: 200
                to: 900
                stopIndicatorValues: [380]
                onValueChanged: {
                    Config.options.background.widgets.visualizer.ringSize = Math.round(value);
                }
            }
        }
    }
}
