import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/*
 * The two shadow toggles under "Visual Options" are *global* — they apply to
 * every desktop widget, not to the page they sit on — but the block had been
 * copy-pasted into 50 separate per-widget config pages, which meant 50 places
 * to keep in step. This is that block, once.
 *
 *   DesktopWidgetVisualOptions { visible: Config.isWidgetActive("date_default") }
 */
ColumnLayout {
    id: root

    spacing: 4

    // Set on a card widget's page: its own style, laid over the global Card style (Widgets settings).
    // Left empty, the block is just the two global toggles.
    property string widgetId: ""
    readonly property var own: root.widgetId !== "" ? Config.getWidgetStyle(root.widgetId) : ({})
    readonly property var resolved: WidgetColorScheme.resolveStyle(root.own)
    readonly property bool hasOwn: Object.keys(root.own).length > 0

    ContentSubsectionLabel {
        text: Translation.tr("Visual Options")
    }

    ConfigSwitch {
        buttonIcon: "wb_sunny"
        text: Translation.tr("Enable Shadows")
        checked: Config.options.background.widgets.enableShadows ?? true
        onCheckedChanged: {
            Config.options.background.widgets.enableShadows = checked;
        }
    }

    ConfigSwitch {
        buttonIcon: "blur_on"
        text: Translation.tr("Enable Inner Shadows")
        checked: Config.options.background.widgets.enableInnerShadow ?? true
        onCheckedChanged: {
            Config.options.background.widgets.enableInnerShadow = checked;
        }
    }

    // The card's own look is the part nobody changes twice, so it folds away:
    // one line says what it currently is, and a click opens the pickers.
    property bool cardOpen: false
    readonly property var presetNames: ({
        "": Translation.tr("Global"),
        "solid": Translation.tr("Solid"),
        "frosted": Translation.tr("Frosted glass"),
        "clear": Translation.tr("Clear glass")
    })
    readonly property var schemeKeys: ["" ].concat(Object.keys(WidgetColorScheme.schemeNames))

    RippleButton {
        visible: root.widgetId !== ""
        Layout.fillWidth: true
        Layout.topMargin: 4
        implicitHeight: 44
        buttonRadius: Appearance.rounding.normal
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        onClicked: root.cardOpen = !root.cardOpen
        contentItem: RowLayout {
            spacing: 10
            MaterialSymbol {
                Layout.leftMargin: 12
                text: "palette"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                text: Translation.tr("Card style")
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: root.hasOwn ? Translation.tr("Customised") : Translation.tr("Global")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                elide: Text.ElideRight
            }
            MaterialSymbol {
                Layout.rightMargin: 12
                text: "keyboard_arrow_down"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colSubtext
                rotation: root.cardOpen ? 180 : 0
                Behavior on rotation {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }

    ColumnLayout {
        visible: root.widgetId !== "" && root.cardOpen
        Layout.fillWidth: true
        spacing: 4

        StyledComboBox {
            buttonIcon: "format_paint"
            textRole: "displayName"
            model: Object.keys(root.presetNames).map(k => ({ displayName: Translation.tr("Style") + ": " + root.presetNames[k], value: k }))
            currentIndex: Math.max(0, Object.keys(root.presetNames).indexOf(root.own.preset ?? ""))
            onActivated: index => {
                const v = Object.keys(root.presetNames)[index];
                Config.setWidgetStyle(root.widgetId, { "preset": v === "" ? null : v, "opacity": null, "border": null });
            }
        }

        StyledComboBox {
            buttonIcon: "palette"
            textRole: "displayName"
            model: root.schemeKeys.map(k => ({ displayName: Translation.tr("Colours") + ": " + (k === "" ? Translation.tr("Global") : WidgetColorScheme.schemeNames[k]), value: k }))
            currentIndex: Math.max(0, root.schemeKeys.indexOf(root.own.scheme ?? ""))
            onActivated: index => {
                const v = root.schemeKeys[index];
                Config.setWidgetStyle(root.widgetId, { "scheme": v === "" ? null : v });
            }
        }

        ConfigSlider {
            buttonIcon: "opacity"
            text: Translation.tr("Card opacity")
            from: 0
            to: 1
            stepSize: 0.01
            value: root.resolved.alpha
            badgeText: Math.round(value * 100) + "%"
            onMoved: Config.setWidgetStyle(root.widgetId, { "opacity": value })
        }

        ConfigSlider {
            buttonIcon: "rounded_corner"
            text: Translation.tr("Corner radius")
            from: 0
            to: 2
            stepSize: 0.05
            value: root.resolved.radiusScale
            badgeText: Math.round(value * 100) + "%"
            onMoved: Config.setWidgetStyle(root.widgetId, { "radius": value })
        }

        ConfigSlider {
            buttonIcon: "border_outer"
            text: Translation.tr("Border")
            from: 0
            to: 4
            stepSize: 0.5
            value: root.resolved.border
            badgeText: value <= 0 ? Translation.tr("None") : value + " px"
            onMoved: Config.setWidgetStyle(root.widgetId, { "border": value })
        }
    }

    RippleButton {
        visible: root.widgetId !== "" && root.cardOpen && root.hasOwn
        implicitHeight: 36
        implicitWidth: resetLabel.implicitWidth + 32
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        onClicked: Config.setWidgetStyle(root.widgetId, null)
        contentItem: StyledText {
            id: resetLabel
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: Appearance.colors.colOnSecondaryContainer
            text: Translation.tr("Use the global style")
        }
    }
}
