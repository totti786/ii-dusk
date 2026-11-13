pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import ".."

/**
 * Saved places, GPS and geocoding in one column. It is used inside the location sheet
 * and inside Settings, so both routes to a new place behave identically.
 */
ColumnLayout {
    id: root

    property bool showSavedPlaces: true
    property bool autoFocusSearch: false

    signal locationChosen()

    spacing: WeatherStyle.gap

    RowLayout {
        Layout.fillWidth: true
        spacing: WeatherStyle.gapSmall

        WeatherChip {
            Layout.fillWidth: true
            iconName: "my_location"
            label: WeatherAppService.settings.useGps ? "Using current location" : "Use current location"
            selected: WeatherAppService.settings.useGps
            onClicked: {
                if (WeatherAppService.settings.useGps)
                    WeatherAppService.disableGps();
                else
                    WeatherAppService.useGps();
            }
        }

        WeatherIconButton {
            symbol: "refresh"
            tooltip: "Refresh"
            size: 36
            iconSize: 17
            onClicked: WeatherAppService.refresh(true)
        }
    }

    MaterialTextField {
        id: searchField
        Layout.fillWidth: true
        placeholderText: "Search for a city…"
        text: ""
        onTextChanged: {
            if (text.length < 2)
                WeatherAppService.clearLocationSearch();
            searchDebounce.restart();
        }
        onAccepted: {
            searchDebounce.stop();
            WeatherAppService.searchLocations(text);
        }
    }

    Timer {
        id: searchDebounce
        interval: 360
        repeat: false
        onTriggered: WeatherAppService.searchLocations(searchField.text)
    }

    StyledText {
        Layout.fillWidth: true
        visible: WeatherAppService.searchingLocations
        text: "Searching…"
        font.pixelSize: WeatherStyle.textTiny
        color: WeatherStyle.colSubtext
    }

    StyledText {
        Layout.fillWidth: true
        visible: WeatherAppService.searchError.length > 0 && !WeatherAppService.searchingLocations
        text: WeatherAppService.searchError
        font.pixelSize: WeatherStyle.textTiny
        color: WeatherStyle.colError
        wrapMode: Text.Wrap
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        visible: WeatherAppService.locationResults.length > 0

        Repeater {
            model: WeatherAppService.locationResults

            RippleButton {
                id: resultButton
                required property var modelData
                required property int index

                Layout.fillWidth: true
                implicitHeight: 48
                leftPadding: 10
                rightPadding: 8
                buttonRadius: WeatherStyle.radiusTile
                colBackground: "transparent"
                colBackgroundHover: WeatherStyle.colSurfaceHover
                colBackgroundActive: WeatherStyle.colSurfaceActive
                onClicked: {
                    WeatherAppService.addLocation(resultButton.modelData);
                    searchField.text = "";
                    WeatherAppService.clearLocationSearch();
                    root.locationChosen();
                }

                contentItem: RowLayout {
                    spacing: WeatherStyle.gapSmall

                    MaterialSymbol {
                        text: "location_on"
                        iconSize: 18
                        color: WeatherStyle.colPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: resultButton.modelData.name
                            font.pixelSize: WeatherStyle.textSmall
                            font.weight: Font.Medium
                            color: WeatherStyle.colOnSurface
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: [resultButton.modelData.admin1, resultButton.modelData.country].filter(part => part.length > 0).join(", ")
                            font.pixelSize: WeatherStyle.textTiny
                            color: WeatherStyle.colSubtext
                            elide: Text.ElideRight
                        }
                    }

                    MaterialSymbol {
                        text: "add"
                        iconSize: 18
                        color: WeatherStyle.colPrimary
                    }
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        visible: root.showSavedPlaces

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: WeatherStyle.gapTiny
            text: "Saved places"
            font.pixelSize: WeatherStyle.textTiny
            font.weight: Font.DemiBold
            color: WeatherStyle.colSubtext
            visible: WeatherAppService.savedLocations.length > 0
        }

        Repeater {
            model: WeatherAppService.savedLocations

            RowLayout {
                id: savedRow
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 2

                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    leftPadding: 10
                    rightPadding: 8
                    buttonRadius: WeatherStyle.radiusTile
                    toggled: WeatherAppService.activeLocationIndex === savedRow.index && !WeatherAppService.settings.useGps
                    colBackground: "transparent"
                    colBackgroundHover: WeatherStyle.colSurfaceHover
                    colBackgroundActive: WeatherStyle.colSurfaceActive
                    colBackgroundToggled: WeatherStyle.alpha(WeatherStyle.colPrimary, 0.12)
                    colBackgroundToggledHover: WeatherStyle.alpha(WeatherStyle.colPrimary, 0.18)
                    colBackgroundToggledActive: WeatherStyle.alpha(WeatherStyle.colPrimary, 0.24)
                    onClicked: {
                        WeatherAppService.selectLocation(savedRow.index);
                        root.locationChosen();
                    }

                    contentItem: RowLayout {
                        spacing: WeatherStyle.gapSmall

                        MaterialSymbol {
                            text: WeatherAppService.activeLocationIndex === savedRow.index && !WeatherAppService.settings.useGps
                                ? "radio_button_checked"
                                : "radio_button_unchecked"
                            iconSize: 18
                            fill: WeatherAppService.activeLocationIndex === savedRow.index ? 1 : 0
                            color: WeatherAppService.activeLocationIndex === savedRow.index
                                ? WeatherStyle.colPrimary
                                : WeatherStyle.colSubtext
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: savedRow.modelData.name
                                font.pixelSize: WeatherStyle.textSmall
                                font.weight: Font.Medium
                                color: WeatherStyle.colOnSurface
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: [savedRow.modelData.admin1, savedRow.modelData.country].filter(part => part.length > 0).join(", ")
                                font.pixelSize: WeatherStyle.textTiny
                                color: WeatherStyle.colSubtext
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                WeatherIconButton {
                    symbol: "delete"
                    tooltip: "Remove " + savedRow.modelData.name
                    size: 34
                    iconSize: 16
                    colIcon: WeatherStyle.colSubtext
                    onClicked: WeatherAppService.removeLocation(savedRow.index)
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: WeatherStyle.gapTiny
            visible: WeatherAppService.savedLocations.length === 0
            text: "No saved places yet. Search above, or use your current location."
            font.pixelSize: WeatherStyle.textTiny
            color: WeatherStyle.colSubtext
            wrapMode: Text.Wrap
        }
    }

    StyledText {
        Layout.fillWidth: true
        text: "Search by Open-Meteo geocoding. GPS never leaves the shell."
        font.pixelSize: WeatherStyle.textTiny
        color: WeatherStyle.colSubtext
        wrapMode: Text.Wrap
    }

    Component.onCompleted: {
        if (root.autoFocusSearch)
            Qt.callLater(() => searchField.forceActiveFocus());
    }
}
