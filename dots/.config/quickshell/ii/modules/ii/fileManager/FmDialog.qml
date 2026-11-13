import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A modal card over a scrim, for the file manager's prompts and forms. Content goes in the
 * default slot, buttons in `actions`. Escape or a click on the scrim closes it.
 */
FocusScope {
    id: root

    property string title: ""
    property real cardWidth: 460
    property bool dismissOnScrim: true
    default property alias content: body.data
    property alias actions: actionRow.data

    signal closed()

    function close(): void {
        root.closed();
    }

    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: event => {
        root.close();
        event.accepted = true;
    }

    // Keyboard: the right-most action is the default; arrows or Tab move between actions and
    // Enter or Space presses the highlighted one. A text field has already used Enter, Left and
    // Right by the time they reach here, so a prompt still submits from its field.
    property int actionIndex: -1
    readonly property var actionButtons: {
        const out = [];
        for (const c of actionRow.children)
            if (c && c.clicked !== undefined && c.visible)
                out.push(c);
        return out;
    }
    onActionIndexChanged: root.markAction()
    function markAction(): void {
        const b = root.actionButtons;
        for (let i = 0; i < b.length; i++)
            if (b[i].kbFocus !== undefined)
                b[i].kbFocus = i === root.actionIndex;
    }
    function stepAction(d: int): void {
        const n = root.actionButtons.length;
        if (n === 0)
            return;
        root.actionIndex = (Math.max(0, root.actionIndex) + d + n) % n;
    }
    Keys.onPressed: event => {
        const k = event.key;
        if (k === Qt.Key_Left || k === Qt.Key_Up || k === Qt.Key_Backtab) {
            root.stepAction(-1);
        } else if (k === Qt.Key_Right || k === Qt.Key_Down || k === Qt.Key_Tab) {
            root.stepAction(1);
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            const b = root.actionButtons[root.actionIndex];
            if (b && b.enabled2 !== false)
                b.clicked();
        } else {
            return;
        }
        event.accepted = true;
    }

    opacity: 0
    Component.onCompleted: {
        opacity = 1;
        root.forceActiveFocus();
        root.actionIndex = root.actionButtons.length - 1;
        root.markAction();
    }
    Behavior on opacity { NumberAnimation { duration: Appearance.dur(140) } }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.5
        MouseArea {
            anchors.fill: parent
            onClicked: if (root.dismissOnScrim) root.close()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(root.cardWidth, root.width - 48)
        height: Math.min(col.implicitHeight + 56, root.height - 48)
        radius: 28
        color: ClockStyle.colSheet
        scale: root.opacity < 1 ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: Appearance.dur(160); easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 28
            spacing: 16

            StyledText {
                Layout.fillWidth: true
                visible: root.title.length > 0
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.DemiBold
                color: ClockStyle.colOnSurface
                elide: Text.ElideRight
            }
            Flickable {
                id: scroller
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: body.implicitHeight
                contentHeight: body.implicitHeight
                contentWidth: width
                clip: true
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                WheelScroll {}
                ColumnLayout {
                    id: body
                    width: scroller.width
                    spacing: 12
                }
            }
            RowLayout {
                id: actionRow
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignRight
                spacing: 8
            }
        }
    }
}
