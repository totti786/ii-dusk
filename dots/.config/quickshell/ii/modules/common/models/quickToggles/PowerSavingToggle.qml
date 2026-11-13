import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Power saving is the power-saver profile. While it is on, animations are off in the shell and in
 * Hyprland (`appearance.powerSaving.reduceMotion`), and the panel family is left as it is: Lite is
 * its own switch (the shell switcher, the settings, the family keybind). Turning this off puts back
 * the profile that was in use, unless another one has been chosen since.
 */
QuickToggleModel {
    name: Translation.tr("Power Saving")
    toggled: PowerProfiles.profile === PowerProfile.PowerSaver
    icon: toggled ? "battery_saver" : "battery_full"
    statusText: toggled ? Translation.tr("On") : Translation.tr("Off")

    mainAction: () => {
        const saving = Config.options.appearance.powerSaving;
        if (PowerProfiles.profile !== PowerProfile.PowerSaver) {
            if (!(PowerProfiles.hasPowerSaverProfile ?? false))
                return;
            saving.returnProfile = PowerProfiles.profile;
            PowerProfiles.profile = PowerProfile.PowerSaver;
        } else {
            PowerProfiles.profile = saving.returnProfile >= 0 ? saving.returnProfile : PowerProfile.Balanced;
            saving.returnProfile = -1;
        }
    }

    tooltipText: Translation.tr("Switch to the power-saver profile, which also turns animations off; switch back to return")
}
