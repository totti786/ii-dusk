import QtQuick
import qs.services

QuickToggleModel {
    name: Translation.tr("Game mode")
    toggled: HyprlandProfiles.gameModeActive
    icon: "gamepad"

    mainAction: () => HyprlandProfiles.setGameMode(!HyprlandProfiles.gameModeActive)

    tooltipText: Translation.tr("Game mode")
}
