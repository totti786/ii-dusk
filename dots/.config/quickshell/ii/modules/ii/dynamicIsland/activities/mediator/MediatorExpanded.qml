pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.ii.bar.popups.mediator

// Plain face for AuxiliaryBubble. The host supplies the animated card bounds;
// the shared player card supplies its own preferred size and native controls.
Item {
    id: root

    property string activityId: "mediator"
    property bool cardExpanded: false
    readonly property real preferredExpandedWidth: playerCard.implicitWidth
    readonly property real preferredExpandedHeight: playerCard.implicitHeight
    readonly property var heroItems: [playerCard.heroItem]

    MediatorPlayerCard {
        id: playerCard
        cardWidth: 360
        contentPadding: 16
        anchors.fill: parent
        onOpenAppRequested: MediatorService.localPlaying ? GlobalStates.openMediatorApp("", true, String(MediatorService.localSession.title_id)) : GlobalStates.openMediatorApp("stream", true, "", MediatorService.nativeState)
    }
}
