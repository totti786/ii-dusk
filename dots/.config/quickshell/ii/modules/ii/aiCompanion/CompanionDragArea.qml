pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.services.ai
import qs.services
import qs.modules.common
import qs.modules.common.widgets

CompanionPointer {
    id: grip
    property bool fromIsland: false
    property string monitorName: String(grip.QsWindow.window?.screen?.name ?? "")
    onPressedChanged: AiCompanionUi.controlPressed = pressed
    onDragStarted: (pointer, center) => AiCompanionUi.beginDrag(pointer.x, pointer.y, center.x, center.y, monitorName, fromIsland)
    onDragMoved: pointer => AiCompanionUi.moveDrag(pointer.x, pointer.y)
    onDragFinished: AiCompanionUi.finishDrag()
    onDragCancelled: AiCompanionUi.cancelDrag()
    onActivated: rightButton => rightButton ? AiCompanionUi.transcript() : AiCompanionUi.toggle()
    Accessible.role: Accessible.Button
    Accessible.name: Translation.tr("Voice companion. %1").arg(AiCompanionUi.label)
    Accessible.onPressAction: AiCompanionUi.toggle()
    StyledToolTip {
        text: AiCompanionUi.voice.errorText || Translation.tr("Click to talk or interrupt · right-click for the conversation\nDrag to float · release over the island to dock")
    }
}
