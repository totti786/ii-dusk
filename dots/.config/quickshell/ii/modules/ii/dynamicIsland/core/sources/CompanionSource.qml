pragma ComponentBehavior: Bound
import QtQuick
import qs.services.ai

ContinuousSource {
    activityId: "companion"
    condition: AiCompanionUi.orbEnabled && AiCompanionUi.saved.visible
        && (AiCompanionUi.docked || (AiCompanionUi.dragging && AiCompanionUi.canDock))
    payload: ({phase: AiCompanionUi.phase})
}
