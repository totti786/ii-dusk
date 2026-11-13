pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * A prayer is near: a glance beside the clock for the last stretch before it, and for a few
 * minutes after it begins ("Asr" on its own, once the time has come).
 *
 * PrayerTimes fetches nothing until someone asks, so this asks for the month's data only
 * while the activity is allowed, and lets go of it otherwise.
 */
ContinuousSource {
    id: source

    activityId: "prayer"

    condition: PrayerTimes.hasLocation && PrayerTimes.glancePrayer !== null
    payload: PrayerTimes.glancePrayer

    // The data is only fetched for those who ask; ask only while this is switched on.
    property bool _holding: false
    function _syncHold(): void {
        if (source.allowed && !source._holding) {
            source._holding = true;
            PrayerTimes.requestData();
        } else if (!source.allowed && source._holding) {
            source._holding = false;
            PrayerTimes.releaseData();
        }
    }
    onAllowedChanged: source._syncHold()

    // Not on the source itself: ContinuousSource has its own Component.onCompleted, and a
    // second one on the same object would replace it and quietly stop the activity starting.
    property QtObject _lifetime: QtObject {
        Component.onCompleted: source._syncHold()
        Component.onDestruction: {
            if (source._holding)
                PrayerTimes.releaseData();
        }
    }
}
