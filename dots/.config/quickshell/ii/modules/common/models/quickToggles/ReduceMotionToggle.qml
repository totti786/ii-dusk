import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Reduce motion")
    toggled: Config.options?.appearance?.reduceMotion ?? false
    icon: toggled ? "motion_photos_off" : "motion_photos_on"
    statusText: toggled ? Translation.tr("On") : Translation.tr("Off")

    mainAction: () => {
        Config.options.appearance.reduceMotion = !(Config.options.appearance.reduceMotion ?? false);
    }

    tooltipText: Translation.tr("Turn off the shell's and Hyprland's animations")
}
