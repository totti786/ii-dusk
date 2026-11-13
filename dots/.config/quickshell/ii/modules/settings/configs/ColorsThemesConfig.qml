import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.configs.colors

Item {
    id: colorsThemesRoot
    anchors.fill: parent

    property alias contentY: pageRoot.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    ContentPage {
        id: pageRoot
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        // ── Wallpapers ──────────────────────────────────────────────────
        ColorsWallpaperHero {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
        }

        // ── Colour scheme ───────────────────────────────────────────────
        ColorsPalettePane {
            Layout.fillWidth: true
        }

        // ── Automation & integrations ───────────────────────────────────
        LazyBlock {
            placeholderHeight: 440
            Layout.topMargin: 12
            AppSettingsSection {
                title: Translation.tr("Automation & integrations")
                symbol: "auto_awesome"

                Item {
                    id: tiles
                    Layout.fillWidth: true
                    implicitHeight: tileFlow.implicitHeight

                    readonly property int gap: 12
                    readonly property int fits: Math.max(1, Math.floor((width + gap) / (300 + gap)))
                    // Five tiles: one row of five, 3 + 2, two columns or one, never 4 + 1.
                    readonly property int columns: fits >= 5 ? 5 : fits >= 3 ? 3 : fits >= 2 ? 2 : 1
                    readonly property int tileWidth: Math.floor((width - gap * (columns - 1)) / columns)
                    readonly property int tileHeight: 200

                    Flow {
                        id: tileFlow
                        width: parent.width
                        spacing: tiles.gap

                        ColorsFeatureTile {
                            width: tiles.tileWidth
                            height: tiles.tileHeight
                            symbol: "nightlight"
                            shapeOn: MaterialShape.Shape.Cookie12Sided
                            title: Translation.tr("Automatic dark mode")
                            summary: {
                                const light = Config.options.light;
                                const parts = [];
                                if (light.darkMode.automatic)
                                    parts.push(Translation.tr("Dark %1–%2").arg(light.darkMode.from).arg(light.darkMode.to));
                                if (light.night.automatic)
                                    parts.push(Translation.tr("Night Light %1–%2").arg(light.night.from).arg(light.night.to));
                                return parts.length > 0 ? parts.join(" · ")
                                    : Translation.tr("Switch to dark mode and warm the screen on a schedule");
                            }
                            checked: Config.options.light.darkMode.automatic || Config.options.light.night.automatic
                            configurable: true
                            onConfigureRequested: colorsThemesRoot.activeSubPage = Qt.resolvedUrl("widgets/SchedulingConfig.qml")
                            onToggled: value => {
                                Config.options.light.darkMode.automatic = value;
                                Config.options.light.night.automatic = value;
                                if (!value)
                                    Hyprsunset.disableTemperature();
                            }
                        }

                        ColorsFeatureTile {
                            id: themingTile
                            width: tiles.tileWidth
                            height: tiles.tileHeight
                            symbol: "format_color_fill"
                            shapeOn: MaterialShape.Shape.Flower
                            title: Translation.tr("App theming")
                            summary: Translation.tr("Wallpaper colors for the shell and utilities, Qt apps and terminals")
                            checked: Config.options.appearance.wallpaperTheming.enableAppsAndShell
                            configurable: true
                            onConfigureRequested: colorsThemesRoot.activeSubPage = Qt.resolvedUrl("widgets/MatugenTemplatesConfig.qml")
                            onToggled: value => Config.options.appearance.wallpaperTheming.enableAppsAndShell = value

                            ColorsChip {
                                enabled: themingTile.checked
                                label: Translation.tr("Qt apps")
                                symbol: "widgets"
                                chosen: Config.options.appearance.wallpaperTheming.enableQtApps
                                colContent: themingTile.colContent
                                colChosen: Appearance.colors.colPrimary
                                colOnChosen: Appearance.colors.colOnPrimary
                                onClicked: Config.options.appearance.wallpaperTheming.enableQtApps = !chosen
                            }
                        }

                        ColorsFeatureTile {
                            id: glassTile
                            compactFooter: true
                            width: tiles.tileWidth
                            height: tiles.tileHeight
                            symbol: "blur_on"
                            shapeOn: MaterialShape.Shape.Pentagon
                            title: Translation.tr("Glass")
                            summary: Translation.tr("See-through bar, dock and panels with the same blur as the desktop widgets")
                            checked: Config.options.appearance.transparency.enable
                            configurable: true
                            onConfigureRequested: colorsThemesRoot.activeSubPage = Qt.resolvedUrl("widgets/WindowsBlurConfig.qml")
                            onToggled: value => Config.options.appearance.transparency.enable = value

                            ColorsChip {
                                compact: true
                                enabled: glassTile.checked
                                label: Translation.tr("Auto")
                                symbol: "auto_awesome"
                                chosen: Config.options.appearance.transparency.automatic
                                colContent: glassTile.colContent
                                colChosen: Appearance.colors.colPrimary
                                colOnChosen: Appearance.colors.colOnPrimary
                                onClicked: Config.options.appearance.transparency.automatic = !chosen
                            }
                            ColorsChip {
                                compact: true
                                enabled: glassTile.checked
                                label: Translation.tr("Menus")
                                symbol: "menu_open"
                                chosen: Config.options.appearance.transparency.popups
                                colContent: glassTile.colContent
                                colChosen: Appearance.colors.colPrimary
                                colOnChosen: Appearance.colors.colOnPrimary
                                onClicked: Config.options.appearance.transparency.popups = !chosen
                            }
                            ColorsChip {
                                compact: true
                                enabled: glassTile.checked
                                label: Translation.tr("Widgets")
                                symbol: "widgets"
                                chosen: (Config.options.background.widgets.glassPreset ?? "shell") === "shell"
                                colContent: glassTile.colContent
                                colChosen: Appearance.colors.colPrimary
                                colOnChosen: Appearance.colors.colOnPrimary
                                onClicked: WidgetColorScheme.applyGlassPreset(chosen ? "solid" : "shell")
                            }
                            ColorsChip {
                                compact: true
                                enabled: glassTile.checked
                                label: Translation.tr("Terminal")
                                symbol: "terminal"
                                chosen: Config.options.appearance.transparency.terminal ?? false
                                colContent: glassTile.colContent
                                colChosen: Appearance.colors.colPrimary
                                colOnChosen: Appearance.colors.colOnPrimary
                                onClicked: Config.options.appearance.transparency.terminal = !chosen
                            }
                        }

                        ColorsFeatureTile {
                            width: tiles.tileWidth
                            height: tiles.tileHeight
                            symbol: "play_circle"
                            shapeOn: MaterialShape.Shape.SoftBurst
                            title: Translation.tr("Wallpaper Engine")
                            summary: Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId
                                ? Translation.tr("Playing Workshop item %1").arg(Config.options.background.wallpaperEngineId)
                                : Translation.tr("Animated wallpapers from the Steam Workshop")
                            checked: Config.options.background.useWallpaperEngine
                            configurable: true
                            onConfigureRequested: colorsThemesRoot.activeSubPage = Qt.resolvedUrl("widgets/WallpaperEngineConfig.qml")
                            onToggled: value => {
                                if (Config.options.background.useWallpaperEngine === value)
                                    return;
                                Config.options.background.useWallpaperEngine = value;
                                Config.saveOptionsNow();
                                if (value && Config.options.background.wallpaperEngineId) {
                                    Wallpapers.apply(Config.options.background.wallpaperEngineId);
                                } else if (!value) {
                                    Quickshell.execDetached(["bash", "-c", "pkill -f linux-wallpaperengine; sleep 0.3; pkill -9 -f linux-wallpaperengine 2>/dev/null; true"]);
                                    if (Config.options.background.wallpaperPath)
                                        Wallpapers.apply(Config.options.background.wallpaperPath);
                                }
                            }
                        }

                        ColorsFeatureTile {
                            width: tiles.tileWidth
                            height: tiles.tileHeight
                            symbol: "keyboard"
                            shapeOn: MaterialShape.Shape.Clover4Leaf
                            title: Translation.tr("OpenRGB integration")
                            summary: Translation.tr("Light your keyboard and peripherals with the palette")
                            checked: Config.options.appearance.openrgb.enable
                            configurable: true
                            onConfigureRequested: colorsThemesRoot.activeSubPage = Qt.resolvedUrl("widgets/OpenRGBConfig.qml")
                            onToggled: value => Config.options.appearance.openrgb.enable = value
                        }
                    }
                }
            }
        }

        // ── Wallpaper picker ────────────────────────────────────────────
        LazyBlock {
            placeholderHeight: 261
            Layout.topMargin: 12
            AppSettingsSection {
                title: Translation.tr("Wallpaper picker")
                symbol: "imagesmode"

                AppChoiceRow {
                    symbol: "folder_open"
                    title: Translation.tr("Picker")
                    description: Translation.tr("What opens when you change a wallpaper")
                    options: [
                        { label: Translation.tr("Built-in"), value: false, icon: "grid_view" },
                        { label: Translation.tr("System dialog"), value: true, icon: "folder_shared" }
                    ]
                    currentValue: Config.options.wallpaperSelector.useSystemFileDialog
                    onSelected: value => Config.options.wallpaperSelector.useSystemFileDialog = value
                }

                AppChoiceRow {
                    symbol: "view_carousel"
                    title: Translation.tr("Picker style")
                    description: Translation.tr("Grid, or a deck of cards showing the colours each wallpaper would give")
                    options: [
                        { label: Translation.tr("Grid"), value: "grid", icon: "grid_view" },
                        { label: Translation.tr("Deck"), value: "deck", icon: "view_carousel" }
                    ]
                    currentValue: Config.options.wallpaperSelector.style
                    onSelected: value => Config.options.wallpaperSelector.style = value
                }

                AppFieldRow {
                    symbol: "download"
                    title: Translation.tr("Download folder")
                    description: Translation.tr("Where the wallpaper browser saves images")
                    placeholder: Translation.tr("Download path...")
                    value: Config.options.wallpapers.paths.download
                    onEdited: text => Config.options.wallpapers.paths.download = text
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
