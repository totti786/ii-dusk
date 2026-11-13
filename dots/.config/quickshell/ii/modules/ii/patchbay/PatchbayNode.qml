pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One node of the graph: a card with its name on top and its ports below, inputs on the
 * left edge and outputs on the right, one pair to a row. The ports' positions are decided
 * by the view, which draws the links; this draws the dots to match.
 */
Rectangle {
    id: root

    required property var entry
    property string hoveredPort: ""
    property int dragPortId: -1
    property var linkedPorts: ({})

    readonly property var node: root.entry.node

    signal headerMoved(real dx, real dy)
    signal headerPressed()
    signal portPressed(var port, real px, real py)
    signal portMoved(real px, real py)
    signal portReleased(real px, real py)

    function kindColor(kind) {
        return kind === "midi" ? ClockStyle.colTertiary : kind === "video" ? Appearance.colors.colSecondary : ClockStyle.colPrimary;
    }

    function portLabel(port) {
        if (port.channel !== "")
            return port.channel;
        return port.short.replace(/^(playback|capture|monitor|output|input)_/, "");
    }

    x: root.entry.x
    y: root.entry.y
    width: root.entry.w
    height: root.entry.h
    radius: ClockStyle.radiusLarge
    color: ClockStyle.colPane
    border.width: 1
    border.color: ClockStyle.colOutline

    // The header is the handle: pressing it and moving drags the whole node
    Rectangle {
        id: header
        width: parent.width
        height: root.entry.headerH
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colSurfaceHigh

        // square off the bottom corners so the header sits flat on the body
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.radius
            color: parent.color
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 6
            MaterialSymbol {
                text: root.node.mediaClass.startsWith("Video") ? "videocam"
                    : root.node.mediaClass.startsWith("Midi") ? "piano"
                    : root.node.mediaClass.includes("Stream") ? "apps"
                    : root.node.mediaClass.includes("Sink") ? "speaker"
                    : root.node.mediaClass.includes("Source") ? "mic" : "graph_2"
                iconSize: 16
                color: ClockStyle.colOnSurfaceVariant
            }
            StyledText {
                Layout.fillWidth: true
                text: root.node.title
                color: ClockStyle.colOnBackground
                font.pixelSize: ClockStyle.textSmall
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: drag
            property real lastX: 0
            property real lastY: 0
            anchors.fill: parent
            preventStealing: true
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onPressed: mouse => {
                const p = mapToItem(root.parent, mouse.x, mouse.y);
                lastX = p.x;
                lastY = p.y;
                root.headerPressed();
            }
            onPositionChanged: mouse => {
                if (!pressed)
                    return;
                const p = mapToItem(root.parent, mouse.x, mouse.y);
                root.headerMoved(p.x - lastX, p.y - lastY);
                lastX = p.x;
                lastY = p.y;
            }
        }
    }

    // Input ports, left
    Repeater {
        model: root.entry.ins
        delegate: Item {
            id: inRow
            required property var modelData
            required property int index
            x: 0
            y: root.entry.headerH + index * root.entry.rowH
            width: root.width / 2
            height: root.entry.rowH

            Rectangle {
                id: dot
                readonly property bool linked: root.linkedPorts[inRow.modelData.id] === true
                readonly property bool hot: root.hoveredPort === String(inRow.modelData.id)
                x: -width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: hot ? 14 : 10
                height: width
                radius: width / 2
                color: linked || hot ? root.kindColor(inRow.modelData.kind) : ClockStyle.colPane
                border.width: 2
                border.color: root.kindColor(inRow.modelData.kind)
                Behavior on width { NumberAnimation { duration: Appearance.dur(90) } }
            }
            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - 16)
                elide: Text.ElideRight
                text: root.portLabel(inRow.modelData)
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
            }
            MouseArea {
                anchors.fill: parent
                anchors.leftMargin: -8
                preventStealing: true
                cursorShape: Qt.CrossCursor
                onPressed: mouse => {
                    const p = mapToItem(root.parent, mouse.x, mouse.y);
                    root.portPressed(inRow.modelData, p.x, p.y);
                }
                onPositionChanged: mouse => {
                    const p = mapToItem(root.parent, mouse.x, mouse.y);
                    root.portMoved(p.x, p.y);
                }
                onReleased: mouse => {
                    const p = mapToItem(root.parent, mouse.x, mouse.y);
                    root.portReleased(p.x, p.y);
                }
            }
        }
    }

    // Output ports, right
    Repeater {
        model: root.entry.outs
        delegate: Item {
            id: outRow
            required property var modelData
            required property int index
            x: root.width / 2
            y: root.entry.headerH + index * root.entry.rowH
            width: root.width / 2
            height: root.entry.rowH

            Rectangle {
                id: dot
                readonly property bool linked: root.linkedPorts[outRow.modelData.id] === true
                readonly property bool hot: root.hoveredPort === String(outRow.modelData.id)
                x: parent.width - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: hot ? 14 : 10
                height: width
                radius: width / 2
                color: linked || hot ? root.kindColor(outRow.modelData.kind) : ClockStyle.colPane
                border.width: 2
                border.color: root.kindColor(outRow.modelData.kind)
                Behavior on width { NumberAnimation { duration: Appearance.dur(90) } }
            }
            StyledText {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - 16)
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: root.portLabel(outRow.modelData)
                color: outRow.modelData.monitor ? ClockStyle.colSubtext : ClockStyle.colOnSurfaceVariant
                font.italic: outRow.modelData.monitor
                font.pixelSize: ClockStyle.textSmall
            }
            MouseArea {
                anchors.fill: parent
                anchors.rightMargin: -8
                preventStealing: true
                cursorShape: Qt.CrossCursor
                onPressed: mouse => {
                    const p = mapToItem(root.parent, mouse.x, mouse.y);
                    root.portPressed(outRow.modelData, p.x, p.y);
                }
                onPositionChanged: mouse => {
                    const p = mapToItem(root.parent, mouse.x, mouse.y);
                    root.portMoved(p.x, p.y);
                }
                onReleased: mouse => {
                    const p = mapToItem(root.parent, mouse.x, mouse.y);
                    root.portReleased(p.x, p.y);
                }
            }
        }
    }
}
