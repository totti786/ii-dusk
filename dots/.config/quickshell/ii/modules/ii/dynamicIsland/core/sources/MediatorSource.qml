pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/** Native anime playback owns its own activity; playback itself is adopted through MPRIS. */
ContinuousSource {
    id: source

    activityId: "mediator"
    condition: MediatorService.nativePillVisible
}
