import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ContentSection {
    title: Translation.tr("Wallpaper Theming & Matugen Integration")
    icon: "wallpaper"

    ContentSubsectionLabel {
        text: Translation.tr("Application theming")
    }

    ConfigSwitch {
        buttonIcon: "desktop_windows"
        text: Translation.tr("Shell & utilities")
        checked: Config.options.appearance.wallpaperTheming.enableAppsAndShell
        onCheckedChanged: Config.options.appearance.wallpaperTheming.enableAppsAndShell = checked
    }

    ConfigSwitch {
        buttonIcon: "widgets"
        text: Translation.tr("Qt apps")
        checked: Config.options.appearance.wallpaperTheming.enableQtApps
        onCheckedChanged: Config.options.appearance.wallpaperTheming.enableQtApps = checked
        StyledToolTip {
            text: Translation.tr("Shell & utilities theming must also be enabled")
        }
    }
}
