pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Quick Share as an island activity: present while someone can send here (visible), while a
 * request or transfer is in flight, and while files wait for a device to be picked. Gone
 * when it is hidden and idle, so the bubble itself tells you that the PC is discoverable.
 *
 * It only reads the service; the service starts and attaches the daemon.
 */
ContinuousSource {
    id: source

    activityId: "quickShare"

    condition: QuickShareService.present
    onConditionChanged: console.log("[QuickShare] island activity", source.condition ? "on" : "off", QuickShareService.visibility)
}
