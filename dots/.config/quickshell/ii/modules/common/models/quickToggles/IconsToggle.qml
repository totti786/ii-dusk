import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Themed Icons")
    toggled: (Config.options?.appearance?.icons?.enableThemed ?? true)
    icon: toggled ? "palette" : "image"
    statusText: toggled ? Translation.tr("On") : Translation.tr("Off")

    mainAction: () => {
        Config.options.appearance.icons.enableThemed = !(Config.options?.appearance?.icons?.enableThemed ?? true);
    }

    tooltipText: Translation.tr("Toggle icon theming")
}