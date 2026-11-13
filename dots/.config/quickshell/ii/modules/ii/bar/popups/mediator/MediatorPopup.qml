pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.shared
import qs.services

// Popup compatibility wrapper. The player card is also hosted by the native island
// activity, so both entry points keep the same saved episode and worker controls.
StyledPopup {
    id: root

    popupId: "mediatorStream"
    stickyHover: true
    forceClick: false
    touchToggle: false
    popupRadius: Appearance.rounding.large

    property Connections playbackConnection: Connections {
        target: MediatorService
        function onProviderStreamStarted(): void { root.close(); }
    }

    contentItem: MediatorPlayerCard {
        onOpenAppRequested: {
            root.close();
            MediatorService.localPlaying ? GlobalStates.openMediatorApp("", true, String(MediatorService.localSession.title_id)) : GlobalStates.openMediatorApp("stream", true, "", MediatorService.nativeState);
        }
    }
}
