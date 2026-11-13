pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * CPU or memory has been high for a while: how high and for how long, the programs using the
 * most of it, and what to do. Ending a program asks twice (the button turns into "End?" for a
 * few seconds), and the shell's own parts are listed but never offered.
 *
 * Self-contained on purpose: the bubble loads cards by URL, and such a file gets none of its
 * directory's types. It reads ResourceAlerts, which the island already follows.
 */
Item {
    id: root

    readonly property bool isMemory: ResourceAlerts.kind === "memory"
    readonly property real value: ResourceAlerts.value
    readonly property var heroItems: [heroDisc]

    // Ticks "for 2 min" while the card is shown.
    QtObject {
        id: clock
        property real now: Date.now()
    }
    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: clock.now = Date.now()
    }
    readonly property int minutes: Math.max(0, Math.floor((clock.now - ResourceAlerts.since) / 60000))

    readonly property string title: root.isMemory ? Translation.tr("Memory is nearly full") : Translation.tr("The CPU is busy")
    readonly property string subtitle: Translation.tr("%1%  ·  for %2").arg(Math.round(root.value * 100))
        .arg(root.minutes < 1 ? Translation.tr("under a minute") : Translation.tr("%1 min").arg(root.minutes))

    /// Which program is being asked "are you sure?", and until when it is forgotten.
    property int armedPid: 0

    readonly property real margin: 14
    readonly property real preferredExpandedWidth: 340
    readonly property real preferredExpandedHeight: column.implicitHeight + 2 * root.margin

    Timer {
        id: disarm
        interval: 3500
        onTriggered: root.armedPid = 0
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.margin
        }
        spacing: 12

        // ── Header ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                id: heroDisc
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: width / 2
                color: Appearance.colors.colErrorContainer
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.isMemory ? "memory" : "speed"
                    iconSize: 22
                    fill: 1
                    color: Appearance.colors.colOnErrorContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.subtitle
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.features: ({ "tnum": 1 })
                    color: Appearance.colors.colSubtext
                }
            }
        }

        // ── How full ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 6
            radius: 3
            color: Appearance.colors.colSurfaceContainerHighest
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, root.value))
                height: parent.height
                radius: 3
                color: Appearance.colors.colError
                Behavior on width {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        // ── The culprits ──
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: ResourceAlerts.processes

                delegate: Rectangle {
                    id: proc
                    required property var modelData
                    readonly property bool armed: root.armedPid === proc.modelData.pid

                    Layout.fillWidth: true
                    implicitHeight: 46
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colSurfaceContainerHigh

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 12
                            rightMargin: 8
                        }
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: proc.modelData.name
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurface
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("CPU %1%  ·  RAM %2%").arg(proc.modelData.cpu).arg(proc.modelData.mem)
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.features: ({ "tnum": 1 })
                                color: Appearance.colors.colSubtext
                            }
                        }

                        RippleButton {
                            visible: !proc.modelData.protectedProcess
                            implicitWidth: proc.armed ? 64 : 56
                            implicitHeight: 30
                            buttonRadius: Appearance.rounding.full
                            colBackground: proc.armed ? Appearance.colors.colErrorContainer : Appearance.colors.colSurfaceContainerHighest
                            colBackgroundHover: proc.armed ? Appearance.colors.colErrorContainerHover : Appearance.colors.colSurfaceContainerHighest
                            onClicked: {
                                if (proc.armed) {
                                    ResourceAlerts.endProcess(proc.modelData.pid);
                                    root.armedPid = 0;
                                } else {
                                    root.armedPid = proc.modelData.pid;
                                    disarm.restart();
                                }
                            }
                            contentItem: Item {
                                StyledText {
                                    anchors.centerIn: parent
                                    text: proc.armed ? Translation.tr("End?") : Translation.tr("End")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    color: proc.armed ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSurface
                                }
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: ResourceAlerts.processes.length === 0
                Layout.fillWidth: true
                text: Translation.tr("Looking for what is using it…")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        // ── What to do ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ActionButton {
                Layout.fillWidth: true
                label: Translation.tr("Open Monitor")
                onClicked: GlobalStates.openMonitorApp("")
            }
            ActionButton {
                Layout.fillWidth: true
                filled: true
                label: Translation.tr("Snooze 30 min")
                onClicked: ResourceAlerts.snooze(30)
            }
        }
    }

    component ActionButton: RippleButton {
        id: action
        property string label
        property bool filled: false

        implicitHeight: 38
        buttonRadius: Appearance.rounding.full
        colBackground: action.filled ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHigh
        colBackgroundHover: action.filled ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighest
        colRipple: action.filled ? Appearance.colors.colPrimaryActive : Appearance.colors.colSurfaceContainerHighestActive

        contentItem: Item {
            StyledText {
                anchors.centerIn: parent
                text: action.label
                font.weight: Font.DemiBold
                color: action.filled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
            }
        }
    }
}
