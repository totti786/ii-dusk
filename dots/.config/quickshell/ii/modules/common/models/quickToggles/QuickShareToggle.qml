import QtQuick
import qs
import qs.services
import qs.modules.common

/**
 * Quick Share's visibility: tap to be seen by nearby phones for ten minutes (or hide again),
 * right-click for the window. Off means hidden: nobody can send here.
 *
 * It reads the service, which only exists to the daemon once Quick Share is enabled; the
 * first tap turns Quick Share on and then makes the PC visible.
 */
QuickToggleModel {
    id: root

    readonly property bool on: QuickShareService.enabled && QuickShareService.visibility !== "invisible"

    name: Translation.tr("Quick Share")
    toggled: root.on
    icon: "send_to_mobile"
    statusText: !QuickShareService.enabled ? Translation.tr("Off")
        : QuickShareService.visibility === "visible" ? Translation.tr("Visible")
        : QuickShareService.visibility === "temporarily" ? Translation.tr("Visible · 10 min")
        : Translation.tr("Hidden")
    tooltipText: Translation.tr("Quick Share | Right-click for the window")

    mainAction: () => QuickShareService.toggleVisible()
    altAction: () => GlobalStates.openQuickShareApp()
}
