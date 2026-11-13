import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {

    // Auto-fetch only after this lazy section has been materialized. A Timer
    // is canceled automatically if the section is collapsed immediately.
    Timer {
        id: discoverKickoffTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (WidgetExtensionManager.communityWidgets.length === 0
                    && !WidgetExtensionManager.discoverLoading
                    && WidgetExtensionManager.discoverError === "") {
                WidgetExtensionManager.discoverWidgets();
            }
        }
    }

    Component.onCompleted: discoverKickoffTimer.start()

    // Header row: refresh button + status
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            text: WidgetExtensionManager.discoverLoading ? Translation.tr("Fetching community widgets from GitHub…") : WidgetExtensionManager.discoverError !== "" ? WidgetExtensionManager.discoverError : Translation.tr("%1 widget(s) found on GitHub").arg(WidgetExtensionManager.communityWidgets.length)
            color: WidgetExtensionManager.discoverError !== "" ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.small
            elide: Text.ElideRight
        }

        RippleButton {
            implicitWidth: refreshBtnRow.implicitWidth + 20
            implicitHeight: 32
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            enabled: !WidgetExtensionManager.discoverLoading
            onClicked: WidgetExtensionManager.discoverWidgets()

            Row {
                id: refreshBtnRow
                anchors.centerIn: parent
                spacing: 4

                MaterialSymbol {
                    text: WidgetExtensionManager.discoverLoading ? "hourglass_top" : "refresh"
                    iconSize: 14
                    color: Appearance.colors.colOnSecondaryContainer
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: WidgetExtensionManager.discoverLoading ? Translation.tr("Refreshing…") : Translation.tr("Refresh")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.bold: true
                    color: Appearance.colors.colOnSecondaryContainer
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // Community widget grid
    Flow {
        id: communityFlow
        Layout.fillWidth: true
        spacing: 12

        Repeater {
            model: WidgetExtensionManager.communityWidgets

            delegate: Rectangle {
                id: communityCard
                required property var modelData
                required property int index

                readonly property string extId: {
                    let name = modelData.fullName || modelData.name || "";
                    return name.split("/").pop().replace(/[^a-zA-Z0-9_\-]/g, "-");
                }
                readonly property bool alreadyInstalled: WidgetExtensionManager.installedWidgets[communityCard.extId] !== undefined

                width: 240
                implicitHeight: communityCardCol.implicitHeight + 24
                color: Appearance.colors.colLayer2Base
                radius: Appearance.rounding.large

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.dur(150)
                    }
                }

                ColumnLayout {
                    id: communityCardCol
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: 12
                    }
                    spacing: 6

                    // Repo name + stars row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: "extension"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: communityCard.modelData.name || ""
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                        }

                        MaterialSymbol {
                            text: "star"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colTertiary
                        }

                        StyledText {
                            text: communityCard.modelData.stars || "0"
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colTertiary
                        }
                    }

                    // Author
                    StyledText {
                        Layout.fillWidth: true
                        text: "@" + (communityCard.modelData.author || "")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }

                    // Description
                    StyledText {
                        Layout.fillWidth: true
                        text: communityCard.modelData.description || Translation.tr("No description")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    // Install / Installed button
                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 28
                        topLeftRadius: Appearance.rounding.full
                        topRightRadius: Appearance.rounding.full
                        bottomLeftRadius: Appearance.rounding.full
                        bottomRightRadius: Appearance.rounding.full
                        colBackground: communityCard.alreadyInstalled ? Appearance.colors.colSurfaceContainerLow : Appearance.colors.colPrimaryContainer
                        colBackgroundHover: communityCard.alreadyInstalled ? Appearance.colors.colSurfaceContainerLow : Appearance.colors.colPrimaryContainerHover
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        enabled: !communityCard.alreadyInstalled && !WidgetExtensionManager.loading
                        onClicked: {
                            if (!communityCard.alreadyInstalled)
                                WidgetExtensionManager.installWidget(communityCard.modelData.cloneUrl);
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                text: communityCard.alreadyInstalled ? "check_circle" : "download"
                                iconSize: 13
                                color: communityCard.alreadyInstalled ? Appearance.colors.colOnSurfaceVariant : Appearance.colors.colOnPrimaryContainer
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: communityCard.alreadyInstalled ? Translation.tr("Installed") : WidgetExtensionManager.loading ? Translation.tr("Installing…") : Translation.tr("Install")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.bold: true
                                color: communityCard.alreadyInstalled ? Appearance.colors.colOnSurfaceVariant : Appearance.colors.colOnPrimaryContainer
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }

        // Empty/loading state
        Item {
            visible: WidgetExtensionManager.communityWidgets.length === 0
            width: communityFlow.width
            height: 64

            StyledText {
                anchors.centerIn: parent
                text: WidgetExtensionManager.discoverLoading ? Translation.tr("Loading…") : WidgetExtensionManager.discoverError !== "" ? Translation.tr("Could not load community widgets. Check network and retry.") : Translation.tr("No community widgets found.")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                width: parent.width - 32
            }
        }
    }
}
