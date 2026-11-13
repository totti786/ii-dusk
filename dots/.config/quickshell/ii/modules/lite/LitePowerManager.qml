pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.UPower

import qs
import qs.services
import qs.modules.common

/**
 * The Lite family's automatic power saver. Below the configured charge, unplugged, it switches the
 * power profile to power saver, and puts the profile that was in use back once the charger is in or
 * the charge has recovered. It touches the profile and nothing else: the blur and animation
 * settings are shared with the other families, and Lite already runs without them.
 *
 * If the profile is changed by hand while the saver is on, the saver lets go of it and does not put
 * anything back, so a choice made in the battery page is never undone behind the user's back.
 */
Scope {
    id: root

    readonly property bool wanted: Battery.available && (Config.options?.lite?.autoSaver?.enable ?? true)
    readonly property int threshold: Config.options?.lite?.autoSaver?.threshold ?? 30
    /// Back above the threshold by this much before the saver lets go, so it does not flap.
    readonly property int margin: 5

    property bool applied: false
    property int previous: PowerProfile.Balanced

    function evaluate(): void {
        if (!root.wanted) {
            root.release();
            return;
        }
        if (!root.applied) {
            if (!Battery.isPluggedIn && Battery.percent <= root.threshold
                    && PowerProfiles.hasPowerSaverProfile && PowerProfiles.profile !== PowerProfile.PowerSaver) {
                root.previous = PowerProfiles.profile;
                root.applied = true;
                PowerProfiles.profile = PowerProfile.PowerSaver;
            }
        } else if (Battery.isPluggedIn || Battery.percent > root.threshold + root.margin) {
            root.release();
        }
    }

    function release(): void {
        if (!root.applied)
            return;
        root.applied = false;
        if (PowerProfiles.profile === PowerProfile.PowerSaver)
            PowerProfiles.profile = root.previous;
    }

    onAppliedChanged: GlobalStates.liteAutoSaverActive = root.applied
    onWantedChanged: root.evaluate()
    onThresholdChanged: root.evaluate()

    Connections {
        target: Battery
        function onPercentChanged() { root.evaluate(); }
        function onIsPluggedInChanged() { root.evaluate(); }
    }
    Connections {
        target: PowerProfiles
        function onProfileChanged() {
            if (root.applied && PowerProfiles.profile !== PowerProfile.PowerSaver)
                root.applied = false;
        }
    }

    Component.onCompleted: root.evaluate()
}
