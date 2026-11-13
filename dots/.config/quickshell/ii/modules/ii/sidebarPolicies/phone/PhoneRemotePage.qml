pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * Controls the phone offers over KDE Connect that the Phone tab has no card for: lock the
 * screen, the volume of its audio outputs, and the commands set up on it.
 *
 * What is listed comes from the daemon, which only knows it while the phone is connected,
 * so each part says so when it has nothing to show instead of disappearing.
 */
Item {
    id: root
    signal goBack()

    readonly property var device: KdeConnectService.activeDevice
    readonly property string deviceId: root.device?.id ?? ""
    readonly property bool connected: root.device?.reachable === true
    readonly property var plugins: root.device?.enabledPlugins ?? []

    readonly property bool hasLock: root.plugins.includes("kdeconnect_lockdevice")
    readonly property bool hasVolume: root.plugins.includes("kdeconnect_remotesystemvolume")
    readonly property bool hasCommands: root.plugins.includes("kdeconnect_remotecommands")

    readonly property var sinks: root.device?.remoteSinks ?? []
    readonly property var commands: root.device?.remoteCommands ?? []

    // ─── Header ─────────────────────────────────────────────
    RowLayout {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 12

        RippleButton {
            implicitWidth: 40
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: root.goBack()

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Phone controls")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer2
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: root.device
                    ? (root.connected ? KdeConnectService.activeDeviceDisplayName : Translation.tr("%1 · not connected").arg(KdeConnectService.activeDeviceDisplayName))
                    : Translation.tr("No device selected")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }
    }

    // ─── Body ───────────────────────────────────────────────
    StyledFlickable {
        id: flick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: 12
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        clip: true
        contentHeight: body.implicitHeight + 16
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: body
            width: flick.width
            spacing: 18

            PagePlaceholder {
                Layout.fillWidth: true
                visible: !root.hasLock && !root.hasVolume && !root.hasCommands
                icon: "smartphone"
                title: Translation.tr("Nothing to control")
                description: Translation.tr("Pick a paired phone, and turn on the Lock device, Phone volume or Remote commands plugins for it in Phone settings.")
            }

            // ── Lock ──
            ControlGroup {
                visible: root.hasLock
                title: Translation.tr("Screen")
                symbol: "lock"

                ControlRow {
                    symbol: "lock"
                    title: Translation.tr("Lock the phone")
                    description: !root.connected ? Translation.tr("The phone is not connected")
                        : root.device?.locked === true ? Translation.tr("Locked") : ""
                    enabled: root.connected
                    clickable: true
                    onClicked: KdeConnectService.lockPhone(root.deviceId)
                }
            }

            // ── Volume ──
            ControlGroup {
                visible: root.hasVolume
                title: Translation.tr("Volume")
                symbol: "volume_up"

                Repeater {
                    model: root.sinks
                    delegate: ControlRow {
                        id: sinkRow
                        required property var modelData
                        readonly property real maxVolume: Math.max(1, Number(modelData.maxVolume ?? 100))
                        property real pending: -1

                        symbol: modelData.muted ? "volume_off" : "volume_up"
                        title: String(modelData.description ?? modelData.name ?? "")
                        enabled: root.connected

                        // The phone reports every change back, which would fight the thumb mid-drag,
                        // so only the last value is sent, at a steady pace.
                        Timer {
                            id: sendTimer
                            interval: 120
                            onTriggered: {
                                if (sinkRow.pending >= 0)
                                    KdeConnectService.setRemoteVolume(root.deviceId, sinkRow.modelData.name, sinkRow.pending);
                                sinkRow.pending = -1;
                            }
                        }

                        below: StyledSlider {
                            Layout.fillWidth: true
                            from: 0
                            to: sinkRow.maxVolume
                            stepSize: 1
                            value: Number(sinkRow.modelData.volume ?? 0)
                            usePercentTooltip: false
                            tooltipContent: `${Math.round(value / sinkRow.maxVolume * 100)}%`
                            onMoved: {
                                sinkRow.pending = value;
                                if (!sendTimer.running)
                                    sendTimer.start();
                            }
                        }

                        RippleButton {
                            implicitWidth: 34
                            implicitHeight: 34
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer3Hover
                            colRipple: Appearance.colors.colLayer3Active
                            onClicked: KdeConnectService.setRemoteMuted(root.deviceId, sinkRow.modelData.name, !sinkRow.modelData.muted)
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: sinkRow.modelData.muted ? "volume_off" : "volume_mute"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledToolTip {
                                text: sinkRow.modelData.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
                            }
                        }
                    }
                }

                ControlRow {
                    visible: root.sinks.length === 0
                    symbol: "info"
                    title: root.connected ? Translation.tr("The phone has not reported any outputs") : Translation.tr("The phone is not connected")
                    description: root.connected ? Translation.tr("Open KDE Connect on the phone and allow it to share its volume.") : ""
                }
            }

            // ── Commands ──
            ControlGroup {
                visible: root.hasCommands
                title: Translation.tr("Commands on the phone")
                symbol: "terminal"

                Repeater {
                    model: root.commands
                    delegate: ControlRow {
                        id: commandRow
                        required property var modelData
                        symbol: "play_circle"
                        title: modelData.name
                        description: modelData.command
                        enabled: root.connected
                        clickable: true
                        onClicked: KdeConnectService.triggerRemoteCommand(root.deviceId, modelData.key)
                    }
                }

                ControlRow {
                    visible: root.commands.length === 0
                    symbol: "info"
                    title: root.connected ? Translation.tr("No commands set up on the phone") : Translation.tr("The phone is not connected")
                    description: root.connected ? Translation.tr("Add them in the KDE Connect app on the phone, under this computer's Commands.") : ""
                }
            }
        }
    }

    // ─── Components ─────────────────────────────────────────
    /** A titled group; its rows share one surface split by 2 px gaps. */
    component ControlGroup: ColumnLayout {
        id: group
        property string title: ""
        property string symbol: ""
        default property alias rows: rowColumn.data

        Layout.fillWidth: true
        spacing: 8

        RowLayout {
            Layout.leftMargin: 8
            spacing: 8
            MaterialSymbol {
                text: group.symbol
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colPrimary
            }
            StyledText {
                text: group.title
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colPrimary
            }
        }

        ColumnLayout {
            id: rowColumn
            Layout.fillWidth: true
            spacing: 2
        }
    }

    /** One row. The first and last visible row of a group carry its large outer corners. */
    component ControlRow: Rectangle {
        id: row
        property string symbol: ""
        property string title: ""
        property string description: ""
        property bool clickable: false
        default property alias control: controlHolder.data
        property alias below: belowHolder.data
        signal clicked()

        readonly property var _siblings: parent ? parent.visibleChildren : []
        readonly property bool first: _siblings.length > 0 && _siblings[0] === row
        readonly property bool last: _siblings.length > 0 && _siblings[_siblings.length - 1] === row

        Layout.fillWidth: true
        implicitHeight: Math.max(56, content.implicitHeight + 20)
        topLeftRadius: row.first ? Appearance.rounding.large : Appearance.rounding.verysmall
        topRightRadius: topLeftRadius
        bottomLeftRadius: row.last ? Appearance.rounding.large : Appearance.rounding.verysmall
        bottomRightRadius: bottomLeftRadius
        color: row.clickable && row.enabled && rowHover.hovered ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer3
        opacity: row.enabled ? 1 : 0.45

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        HoverHandler {
            id: rowHover
        }
        TapHandler {
            enabled: row.clickable
            cursorShape: Qt.PointingHandCursor
            onTapped: row.clicked()
        }

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: belowHolder.implicitHeight > 0 ? 8 : 0

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                MaterialSymbol {
                    visible: row.symbol.length > 0
                    text: row.symbol
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    StyledText {
                        Layout.fillWidth: true
                        text: row.title
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer3
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: row.description.length > 0
                        text: row.description
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                RowLayout {
                    id: controlHolder
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 4
                }
            }

            ColumnLayout {
                id: belowHolder
                Layout.fillWidth: true
                visible: children.length > 0
                spacing: 0
            }
        }
    }
}
