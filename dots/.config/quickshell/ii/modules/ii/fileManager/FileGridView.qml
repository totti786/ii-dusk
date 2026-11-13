pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Icon view. All pointer input goes through one MouseArea on top, so selection, rubber-band,
 * drag-out and the context menu behave the same for every cell; the delegates only draw.
 */
Item {
    id: root

    property var model: []
    property var selected: ({})
    property int cursor: -1
    property string renamingPath: ""
    property real iconSize: 96
    property string dragUris: ""
    property var thumbs: ({})
    property var iconResolver: null
    property var starredSet: ({})
    property string dropHighlight: ""
    readonly property alias flick: view
    readonly property int columns: Math.max(1, Math.floor(view.width / view.cellWidth))
    readonly property int count: root.model.length

    signal selectRequested(int index, int modifiers)
    signal openRequested(int index)
    signal contextRequested(int index, real x, real y)
    signal openInTabRequested(int index)
    signal clearRequested()
    signal rubberBand(var indices, bool additive)
    signal renameCommitted(string path, string text)
    signal renameCancelled()
    signal zoomRequested(int direction)
    signal dropped(var urls, string folder, int action)
    signal thumbNeeded(var entry)

    function ensureVisible(i: int): void {
        if (i >= 0 && i < root.count)
            view.positionViewAtIndex(i, GridView.Contain);
    }

    function cellRect(i: int): rect {
        const col = i % root.columns;
        const row = Math.floor(i / root.columns);
        return Qt.rect(col * view.cellWidth - view.contentX, row * view.cellHeight - view.contentY, view.cellWidth, view.cellHeight);
    }

    function indexAtPoint(x: real, y: real): int {
        const col = Math.floor((x + view.contentX) / view.cellWidth);
        const row = Math.floor((y + view.contentY) / view.cellHeight);
        if (col < 0 || col >= root.columns || row < 0)
            return -1;
        const i = row * root.columns + col;
        return i < root.count ? i : -1;
    }

    GridView {
        id: view
        anchors.fill: parent
        anchors.margins: 6
        clip: true
        model: root.model
        cellWidth: Math.floor(width / Math.max(1, Math.floor(width / (root.iconSize + 36))))
        cellHeight: root.iconSize + 66
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 600
        WheelScroll {}
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            width: 10
        }

        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property bool isSelected: Boolean(root.selected[cell.modelData.path])
            readonly property bool hovered: mouse.hoverIndex === cell.index
            readonly property bool isDrop: root.dropHighlight !== "" && root.dropHighlight === cell.modelData.path
            readonly property bool renaming: root.renamingPath === cell.modelData.path
            width: view.cellWidth
            height: view.cellHeight
            // A selected item grows downwards to show its whole name, over the cells below it
            z: cell.isSelected ? 5 : 0

            Component.onCompleted: root.thumbNeeded(cell.modelData)

            Rectangle {
                x: 3
                y: 3
                width: parent.width - 6
                height: cell.isSelected && !cell.renaming ? Math.max(parent.height - 6, nameText.y + nameText.implicitHeight + 6) : parent.height - 6
                radius: 22
                color: cell.isDrop ? ClockStyle.colPrimaryContainer
                    : cell.isSelected ? ClockStyle.colSecondaryContainer
                    : cell.hovered ? ClockStyle.colSurfaceHover : "transparent"
                border.width: root.cursor === cell.index ? 2 : 0
                border.color: ClockStyle.colPrimary
                Behavior on color { ColorAnimation { duration: Appearance.dur(80) } }
            }

            FileIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 12
                width: root.iconSize
                height: root.iconSize
                entry: cell.modelData
                starred: Boolean(root.starredSet[cell.modelData.path])
                thumbSize: root.iconSize * 2
                thumb: root.thumbs[cell.modelData.path + "|" + cell.modelData.mtime] ?? ""
                iconNames: root.iconResolver ? root.iconResolver(cell.modelData) : []
            }
            StyledText {
                id: nameText
                visible: !cell.renaming
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.iconSize + 18
                width: parent.width - 14
                height: cell.isSelected ? Math.max(38, implicitHeight) : 38
                text: cell.modelData.name
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignTop
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: cell.isSelected ? 20 : 2
                elide: cell.isSelected ? Text.ElideNone : Text.ElideMiddle
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: cell.isSelected ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                opacity: cell.modelData.hidden ? 0.6 : 1
            }
        }
    }

    // Rename field, above the input area so it takes clicks
    Rectangle {
        id: renameBox
        readonly property int idx: {
            for (let i = 0; i < root.count; ++i)
                if (root.model[i].path === root.renamingPath)
                    return i;
            return -1;
        }
        visible: idx >= 0
        readonly property rect r: idx >= 0 ? root.cellRect(idx) : Qt.rect(0, 0, 0, 0)
        x: view.x + r.x + 4
        y: view.y + r.y + root.iconSize + 16
        width: r.width - 8
        height: 30
        radius: Appearance.rounding.verysmall
        color: ClockStyle.colField
        border.width: 2
        border.color: ClockStyle.colPrimary
        z: 5
        TextInput {
            id: renameInput
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            verticalAlignment: TextInput.AlignVCenter
            color: ClockStyle.colOnSurface
            font.pixelSize: Appearance.font.pixelSize.smallie
            font.family: Appearance.font.family.main
            selectByMouse: true
            clip: true
            onVisibleChanged: if (visible) beginRename()
            function beginRename(): void {
                const e = root.model.find(m => m.path === root.renamingPath);
                if (!e)
                    return;
                text = e.name;
                forceActiveFocus();
                const dot = !e.isDir ? e.name.lastIndexOf(".") : -1;
                select(0, dot > 0 ? dot : e.name.length);
            }
            Keys.onReturnPressed: root.renameCommitted(root.renamingPath, text)
            Keys.onEnterPressed: root.renameCommitted(root.renamingPath, text)
            Keys.onEscapePressed: root.renameCancelled()
            onActiveFocusChanged: if (!activeFocus && renameBox.visible) root.renameCancelled()
        }
    }

    // Rubber band
    Rectangle {
        id: band
        visible: false
        z: 4
        color: Qt.rgba(ClockStyle.colPrimary.r, ClockStyle.colPrimary.g, ClockStyle.colPrimary.b, 0.18)
        border.width: 1
        border.color: ClockStyle.colPrimary
        radius: 4
    }

    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onPositionChanged: drag => {
            const i = root.indexAtPoint(drag.x - view.x, drag.y - view.y);
            root.dropHighlight = i >= 0 && root.model[i].isDir ? root.model[i].path : "";
        }
        onExited: root.dropHighlight = ""
        onDropped: drop => {
            const i = root.indexAtPoint(drop.x - view.x, drop.y - view.y);
            const folder = i >= 0 && root.model[i].isDir ? root.model[i].path : "";
            root.dropHighlight = "";
            root.dropped(drop.urls, folder, drop.proposedAction);
            drop.acceptProposedAction();
        }
    }

    // Kept for the platform drag
    Item {
        id: dragProxy
        width: 1
        height: 1
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
        Drag.proposedAction: Qt.MoveAction
        Drag.onDragFinished: mouse.dragging = false
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        z: 2

        property int hoverIndex: -1
        property int pressIndex: -1
        property bool collapseOnRelease: false
        property real px: 0
        property real py: 0
        property bool rubber: false
        property bool dragging: false
        property bool additive: false

        onPositionChanged: m => {
            const i = root.indexAtPoint(m.x - view.x, m.y - view.y);
            hoverIndex = i;
            if (!pressed)
                return;
            if (pressIndex >= 0 && !dragging && !rubber && (Math.abs(m.x - px) + Math.abs(m.y - py)) > 8 && root.dragUris.length > 0) {
                dragging = true;
                collapseOnRelease = false;
                dragProxy.Drag.mimeData = { "text/uri-list": root.dragUris };
                // An automatic drag starts the moment Drag.active turns on (startDrag() only works once it is)
                dragProxy.Drag.active = true;
                return;
            }
            if (pressIndex < 0 && (rubber || (Math.abs(m.x - px) + Math.abs(m.y - py)) > 6)) {
                rubber = true;
                const x0 = Math.min(px, m.x), y0 = Math.min(py, m.y);
                band.x = x0;
                band.y = y0;
                band.width = Math.abs(m.x - px);
                band.height = Math.abs(m.y - py);
                band.visible = true;
                const hits = [];
                const cw = view.cellWidth, ch = view.cellHeight;
                const c0 = Math.max(0, Math.floor((x0 - view.x + view.contentX) / cw));
                const c1 = Math.min(root.columns - 1, Math.floor((x0 + band.width - view.x + view.contentX) / cw));
                const r0 = Math.max(0, Math.floor((y0 - view.y + view.contentY) / ch));
                const r1 = Math.floor((y0 + band.height - view.y + view.contentY) / ch);
                for (let r = r0; r <= r1; ++r)
                    for (let c = c0; c <= c1; ++c) {
                        const idx = r * root.columns + c;
                        if (idx < root.count)
                            hits.push(idx);
                    }
                root.rubberBand(hits, additive);
                // Scroll while dragging near the edges
                if (m.y < view.y + 20)
                    view.contentY = Math.max(0, view.contentY - 14);
                else if (m.y > root.height - 20)
                    view.contentY = Math.min(Math.max(0, view.contentHeight - view.height), view.contentY + 14);
            }
        }
        onExited: hoverIndex = -1

        onPressed: m => {
            if (m.button === Qt.MiddleButton) {
                // A middle click only opens; it never selects, drags or starts a rubber band
                pressIndex = -1;
                collapseOnRelease = false;
                const mi = root.indexAtPoint(m.x - view.x, m.y - view.y);
                if (mi >= 0)
                    root.openInTabRequested(mi);
                return;
            }
            px = m.x;
            py = m.y;
            rubber = false;
            dragging = false;
            collapseOnRelease = false;
            pressIndex = root.indexAtPoint(m.x - view.x, m.y - view.y);
            additive = (m.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) !== 0;
            if (m.button === Qt.RightButton) {
                if (pressIndex >= 0 && !root.selected[root.model[pressIndex].path])
                    root.selectRequested(pressIndex, 0);
                root.contextRequested(pressIndex, m.x, m.y);
                return;
            }
            if (pressIndex < 0) {
                if (!additive)
                    root.clearRequested();
                return;
            }
            if (root.selected[root.model[pressIndex].path] && !additive) {
                collapseOnRelease = true;
                return;
            }
            root.selectRequested(pressIndex, m.modifiers);
        }
        onReleased: m => {
            band.visible = false;
            if (collapseOnRelease && !dragging && pressIndex >= 0)
                root.selectRequested(pressIndex, 0);
            rubber = false;
            dragging = false;
        }
        onDoubleClicked: m => {
            const i = root.indexAtPoint(m.x - view.x, m.y - view.y);
            if (i >= 0 && m.button === Qt.LeftButton)
                root.openRequested(i);
        }
        onWheel: wheel => {
            if (wheel.modifiers & Qt.ControlModifier) {
                root.zoomRequested(wheel.angleDelta.y > 0 ? 1 : -1);
                wheel.accepted = true;
            } else {
                wheel.accepted = false;
            }
        }
    }
}
