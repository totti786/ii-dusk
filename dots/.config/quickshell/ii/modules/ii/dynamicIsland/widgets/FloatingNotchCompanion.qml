pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.services.ai
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.aiCompanion
import "../../aiCompanion/CompanionPlacement.js" as Placement

Item {
    id: root
    property bool isExpanded: false
    property string bubbleSide: "right"
    property real bubbleDiameter: 40
    readonly property var orbCenter: Placement.bubbleAnchor(root.bubbleSide, root.width, root.bubbleDiameter, 6)
    readonly property real preferredExpandedHeight: 156
    readonly property var heroItems: [voiceOrb]
    readonly property bool holdsOpen: AiCompanionUi.fileHover || headerGrip.pressed || (AiCompanionUi.dragging && AiCompanionUi.dragFromIsland)
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.isExpanded ? 12 : 4
        spacing: 8
        RowLayout {
            id: header
            Layout.fillWidth: true
            layoutDirection: root.bubbleSide === "left" ? Qt.RightToLeft : Qt.LeftToRight
            spacing: 10
            Item {
                // Keep the orb near the grab point, with a small visual inset
                // so it belongs to the header rather than the rounded corner.
                Layout.preferredWidth: Math.max(0, root.bubbleDiameter - 12)
                Layout.preferredHeight: root.bubbleDiameter
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                StyledText {
                    Layout.fillWidth: true
                    text: AiCompanionUi.label
                    elide: Text.ElideRight
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.isExpanded
                    text: Ai.currentModelEntry?.title ?? Translation.tr("Voice companion")
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: root.isExpanded
            spacing: 4
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimaryContainer
                buttonText: AiCompanionUi.phase === "listening" ? Translation.tr("Send")
                    : AiCompanionUi.phase === "speaking" ? Translation.tr("Interrupt") : Translation.tr("Talk")
                onClicked: AiCompanionUi.toggle()
            }
            Action {
                text: AiCompanionUi.voice.active ? "stop" : "chat_bubble"
                tip: AiCompanionUi.voice.active ? Translation.tr("Stop voice conversation") : Translation.tr("Open conversation")
                onClicked: AiCompanionUi.voice.active ? AiCompanionUi.voice.stop() : AiCompanionUi.transcript()
            }
            Action { text: "chat_bubble"; visible: AiCompanionUi.voice.active; tip: Translation.tr("Open conversation"); onClicked: AiCompanionUi.transcript() }
            Action {
                text: "screenshot_region"
                visible: AiCompanionUi.canAttachScreen
                tip: Translation.tr("Attach screen region")
                onClicked: AiCompanionUi.attachScreen()
            }
            Action { text: "open_in_new"; tip: Translation.tr("Float on desktop"); onClicked: AiCompanionUi.undock() }
            Action { text: "close"; tip: Translation.tr("Hide companion"); onClicked: AiCompanionUi.hide() }
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.isExpanded
            text: AiCompanionUi.fileHover ? Translation.tr("Drop files to attach to the conversation") : AiCompanionUi.voice.errorText || Translation.tr("Drag the orb out to float it. Text stays in the sidebar.")
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }
    CompanionOrb {
        id: voiceOrb
        x: root.orbCenter.x-width/2
        y: root.orbCenter.y-height/2
        width: root.bubbleDiameter
        height: width
        hovered: headerGrip.containsMouse
    }
    CompanionDragArea {
        id: headerGrip
        x: 0; y: 0
        width: root.width; height: Math.max(56, root.bubbleDiameter+12)
        orbAnchor: voiceOrb
        fromIsland: true
    }
    CompanionFileDrop { anchors.fill: parent; z: 5 }
    component Action: IconToolbarButton {
        property string tip: ""
        implicitWidth: 34; implicitHeight: 36; iconSize: 18
        Accessible.name: tip
        scale: down ? .96 : 1
        Behavior on scale { enabled: !AiCompanionUi.reducedMotion; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        StyledToolTip { text: parent.tip }
    }
}
