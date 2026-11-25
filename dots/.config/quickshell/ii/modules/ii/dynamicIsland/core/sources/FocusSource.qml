pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * A Panadoro focus session is under way (or paused): a glance beside the clock with the tag's
 * shape and the time left. Panadoro's own timer, not the bar's pomodoro, which is TimerSource.
 */
ContinuousSource {
    id: source

    activityId: "focus"

    condition: PanadoroService.timerRunning || PanadoroService.timerPaused
    payload: PanadoroService.timerPhase
}
