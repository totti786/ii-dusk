pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * The charger was plugged in, the battery filled, or the power profile changed.
 *
 * Only transitions count. The old island announced this from three separate handlers
 * (`isCharging`, `isPluggedIn` and `chargeState`) so one physical event restarted the
 * notch up to three times, and it announced *being* plugged in at every startup - a
 * state, not an event, which is why the notch appeared after every reload.
 */
TransientSource {
    id: source

    activityId: "battery"
    ttlMs: 5000
    cooldownMs: 1500   // one physical plug-in reaches us through several signals

    readonly property bool pluggedIn: Battery.isPluggedIn
    readonly property bool available: Battery.available
    property var previousProfile: null

    function announce(reason): bool {
        if (!source.available)
            return false;
        return source.trigger({ reason: reason, pluggedIn: source.pluggedIn, percentage: Battery.percentage });
    }

    onPluggedInChanged: {
        if (source.pluggedIn)
            source.announce("plugged");
    }

    property Connections _battery: Connections {
        target: Battery
        function onChargeStateChanged() {
            // Reaching full, or starting to charge, while on the charger.
            if (!Battery.isPluggedIn)
                return;
            // The end of the charge comes in through `onChargedReached` below, which also decides
            // whether the desktop notification is needed; announcing it here as well would spend
            // the cooldown and leave that announcement refused as a duplicate.
            if (Battery.isFullyCharged || Battery.chargeLimitReached)
                return;
            source.announce("chargeState");
        }

        /**
         * The battery service hands the end of charging over instead of notifying: the banner is
         * the announcement. Only a refusal - the quiet window after a boot, a reload or an unlock -
         * sends it back to the desktop, so the event is never lost and never said twice.
         */
        function onChargedReached(title, body, icon) {
            if (!source.announce("charged"))
                Battery.notify(title, body, icon);
        }
    }

    property Connections _profiles: Connections {
        target: (typeof PowerProfiles !== "undefined") ? PowerProfiles : null
        ignoreUnknownSignals: true
        function onProfileChanged() {
            if (typeof PowerProfiles === "undefined")
                return;
            // The first reading after boot is not a choice the user made.
            if (source.previousProfile !== null && source.previousProfile !== PowerProfiles.profile)
                source.announce("profile");
            source.previousProfile = PowerProfiles.profile;
        }
    }

    Component.onCompleted: {
        if (typeof PowerProfiles !== "undefined" && PowerProfiles.profile !== undefined)
            source.previousProfile = PowerProfiles.profile;
    }
}
