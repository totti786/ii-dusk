pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * CPU or memory held high for a while: a bubble that tells you, with the culprits in its
 * card. The detection (and the snooze) lives in ResourceAlerts, which the card reads too.
 */
ContinuousSource {
    id: source

    activityId: "monitorAlert"

    condition: ResourceAlerts.active
    payload: ResourceAlerts.kind
}
