import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "ai_chat"

    // 1x1 is the greeting and the button; 1x0.5 is the icon and the button on one line; 2x1 puts
    // the icon and greeting beside the button
    supportedSizes: ["1x0.5", "1x1", "2x1"]
    defaultSize: "1x1"
    readonly property bool strip: root.sizeClass === "1x0.5"
    readonly property bool wide: root.sizeClass === "2x1"
    implicitWidth: root.sizeClassDims.width
    implicitHeight: root.sizeClassDims.height

    function openComposer() {
        Ai.surfaceRouter.open({
            surface: "sidebar",
            focusIntent: "composer"
        });
    }

    // Color tokens from WidgetColorScheme
    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg
    readonly property color subtextColorOnBg: WidgetColorScheme.subtextColorOnBg
    readonly property color accentColor: WidgetColorScheme.accentColor
    readonly property color onAccentColor: WidgetColorScheme.onAccentColor
    readonly property color innerShapeColor: WidgetColorScheme.innerShapeColor

    StyledRectangularShadow {
        id: bgShadow
        target: bgRect
        visible: Config.options.background.widgets.enableShadows ?? false
    }

    // Outer Container
    Rectangle {
        id: bgRect
        anchors.fill: parent
        color: WidgetColorScheme.tintBackground(root.cardBgColor)
        radius: Appearance.rounding.windowRounding

        layer.enabled: Config.options.background.widgets.enableInnerShadow ?? false
        layer.effect: InnerShadow {
            color: Qt.rgba(0, 0, 0, 0.15)
            radius: 8.0
            samples: 16
            horizontalOffset: 0
            verticalOffset: 1
            spread: 0.0
        }

        // Mask container for rounded corner clipping
        Item {
            id: contentContainer
            anchors.fill: parent
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: contentContainer.width
                    height: contentContainer.height
                    radius: bgRect.radius
                }
            }

            // The two shapes that are not the square: the icon and the button side by side, with
            // the greeting between them once there is room
            RowLayout {
                visible: root.strip || root.wide
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    visible: Config.options.bar.useMaterialSymbolForTopLeftIcon
                    text: Config.options.bar.topLeftIcon ?? "spark"
                    iconSize: root.wide ? 64 : 40
                    fill: 1
                    color: root.accentColor
                }
                CustomIcon {
                    Layout.alignment: Qt.AlignVCenter
                    visible: !Config.options.bar.useMaterialSymbolForTopLeftIcon
                    Layout.preferredWidth: root.wide ? 64 : 40
                    Layout.preferredHeight: root.wide ? 64 : 40
                    source: Config.options.bar.topLeftIcon == 'distro' ? SystemInfo.distroIcon : `${Config.options.bar.topLeftIcon}-symbolic`
                    colorize: true
                    color: root.accentColor
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    Item { Layout.fillHeight: true; visible: root.wide }
                    StyledText {
                        visible: root.wide
                        Layout.fillWidth: true
                        text: Translation.tr("How can I help you with today?")
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.DemiBold
                        color: root.textColorOnBg
                        wrapMode: Text.Wrap
                    }
                    RippleButton {
                        Layout.fillWidth: true
                        Layout.fillHeight: root.strip
                        Layout.preferredHeight: 44
                        buttonRadius: Appearance.rounding.normal
                        colBackground: root.innerShapeColor
                        colBackgroundHover: Qt.darker(root.innerShapeColor, 1.1)
                        colRipple: Qt.darker(root.innerShapeColor, 1.2)

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            MaterialSymbol {
                                text: "edit"
                                iconSize: 18
                                color: root.subtextColorOnBg
                            }
                            StyledText {
                                text: Translation.tr("Ask something")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: root.subtextColorOnBg
                            }
                        }
                        onClicked: root.openComposer()
                    }
                    Item { Layout.fillHeight: true; visible: root.wide }
                }
            }

            ColumnLayout {
                visible: !root.strip && !root.wide
                anchors.fill: parent
                anchors.margins: 16
                spacing: 0

                // Top: Single Spark Icon in Accent color (56px)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    Layout.alignment: Qt.AlignTop | Qt.AlignHCenter

                    CustomIcon {
                        anchors.centerIn: parent
                        visible: !Config.options.bar.useMaterialSymbolForTopLeftIcon
                        width: 56
                        height: 56
                        source: Config.options.bar.topLeftIcon == 'distro' ? SystemInfo.distroIcon : `${Config.options.bar.topLeftIcon}-symbolic`
                        colorize: true
                        color: root.accentColor
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: Config.options.bar.useMaterialSymbolForTopLeftIcon
                        text: Config.options.bar.topLeftIcon ?? "spark"
                        iconSize: 56
                        fill: 1
                        color: root.accentColor
                    }
                }

                // Vertical spacer for space-between layout
                Item {
                    Layout.fillHeight: true
                }

                // Middle: Title Text
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("How can I help you\nwith today?")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: root.textColorOnBg
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    lineHeight: 1.1
                }

                // Vertical spacer for space-between layout
                Item {
                    Layout.fillHeight: true
                }

                // Bottom: Ask Something Button
                RippleButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    buttonRadius: Appearance.rounding.normal
                    colBackground: root.innerShapeColor
                    colBackgroundHover: Qt.darker(root.innerShapeColor, 1.1)
                    colRipple: Qt.darker(root.innerShapeColor, 1.2)

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        MaterialSymbol {
                            text: "edit"
                            iconSize: 18
                            color: root.subtextColorOnBg
                        }

                        StyledText {
                            text: Translation.tr("Ask something")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: root.subtextColorOnBg
                        }
                    }

                    onClicked: {
                        Ai.surfaceRouter.open({
                            surface: "sidebar",
                            focusIntent: "composer"
                        });
                    }
                }
            }
        }
    }
}
