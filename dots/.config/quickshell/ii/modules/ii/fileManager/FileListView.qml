pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// Details view: a sortable table of the folder, one row per file. Input works as in FileGridView.
Item {
    id: root

    property var model: []
    property var selected: ({})
    property int cursor: -1
    property string renamingPath: ""
    property string dragUris: ""
    property var thumbs: ({})
    property var folderSizes: ({})
    property var iconResolver: null
    property var starredSet: ({})
    property string dropHighlight: ""
    property string sortKey: "name"
    property bool sortDesc: false
    property bool trashMode: false
    property bool searchMode: false
    readonly property bool locationMode: root.trashMode || root.searchMode
    property real iconSize: 24
    readonly property alias flick: view
    readonly property int columns: 1
    readonly property int count: root.model.length
    readonly property real rowHeight: 46
    readonly property real sizeW: 84
    readonly property real dateW: 140
    readonly property real typeW: root.locationMode ? 220 : 140
    readonly property bool wide: root.width > 560
    readonly property bool showType: root.width > 880
    readonly property real padR: 24
    readonly property real xType: root.width - root.padR - root.typeW
    readonly property real xSize: (root.showType ? root.xType : root.width - root.padR) - root.sizeW
    readonly property real xDate: root.xSize - root.dateW
    readonly property real nameX: 62
    readonly property real nameW: (root.wide ? root.xDate : root.xSize) - root.nameX - 12

    signal selectRequested(int index, int modifiers)
    signal openRequested(int index)
    signal contextRequested(int index, real x, real y)
    signal openInTabRequested(int index)
    signal clearRequested()
    signal rubberBand(var indices, bool additive)
    signal renameCommitted(string path, string text)
    signal renameCancelled()
    signal zoomRequested(int direction)
    signal sortRequested(string key)
    signal dropped(var urls, string folder, int action)
    signal thumbNeeded(var entry)

    function ensureVisible(i: int): void {
        if (i >= 0 && i < root.count)
            view.positionViewAtIndex(i, ListView.Contain);
    }

    function rowRect(i: int): rect {
        return Qt.rect(0, i * root.rowHeight - view.contentY, root.width, root.rowHeight);
    }

    function indexAtPoint(x: real, y: real): int {
        const i = Math.floor((y + view.contentY) / root.rowHeight);
        return i >= 0 && i < root.count ? i : -1;
    }

    function sizeText(e: var): string {
        let s = e.size;
        if (e.isDir) {
            const known = root.folderSizes[e.path];
            if (known === undefined)
                return e.itemCount !== undefined ? qsTr("%1 items").arg(e.itemCount) : "—";
            s = known;
        }
        if (s < 1024)
            return s + " B";
        const u = ["KiB", "MiB", "GiB", "TiB"];
        let v = s / 1024, i = 0;
        while (v >= 1024 && i < u.length - 1) {
            v /= 1024;
            i++;
        }
        return v.toFixed(v < 10 ? 1 : 0) + " " + u[i];
    }

    function dateText(t: real): string {
        const d = new Date(t * 1000);
        const now = new Date();
        if (d.toDateString() === now.toDateString())
            return Qt.formatTime(d, "HH:mm");
        if (d.getFullYear() === now.getFullYear())
            return Qt.formatDate(d, "d MMM") + ", " + Qt.formatTime(d, "HH:mm");
        return Qt.formatDate(d, "d MMM yyyy");
    }

    function typeText(e: var): string {
        if (e.isDir)
            return qsTr("Folder");
        const kinds = { image: "Image", video: "Video", audio: "Audio", pdf: "PDF", archive: "Archive", code: "Source code",
            text: "Text", sheet: "Spreadsheet", slides: "Presentation", doc: "Document", book: "E-book", font: "Font", exec: "Program", file: "File" };
        const ext = e.name.includes(".") ? e.name.split(".").pop().toUpperCase() : "";
        return (kinds[e.kind] ?? "File") + (ext && ext.length < 6 ? " · " + ext : "");
    }

    // Header
    Rectangle {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        height: 34
        color: "transparent"

        component HeadCell: Item {
            id: hc
            property string label: ""
            property string key: ""
            property int align: Text.AlignLeft
            readonly property bool current: root.sortKey === hc.key
            height: header.height
            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: hc.align === Text.AlignLeft ? parent.left : undefined
                anchors.right: hc.align === Text.AlignRight ? parent.right : undefined
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 4
                StyledText {
                    text: hc.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.letterSpacing: 0.3
                    font.weight: hc.current ? Font.DemiBold : Font.Normal
                    color: hc.current ? ClockStyle.colPrimary : ClockStyle.colSubtext
                }
                MaterialSymbol {
                    visible: hc.current
                    text: root.sortDesc ? "arrow_downward" : "arrow_upward"
                    iconSize: 14
                    color: ClockStyle.colPrimary
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (hc.key.length > 0) root.sortRequested(hc.key)
            }
        }

        HeadCell {
            x: root.nameX - 8
            width: root.nameW
            label: qsTr("Name")
            key: "name"
        }
        HeadCell {
            visible: root.wide
            x: root.xDate
            width: root.dateW
            label: root.trashMode ? qsTr("Deleted") : qsTr("Modified")
            key: "mtime"
        }
        HeadCell {
            x: root.xSize
            width: root.sizeW
            label: qsTr("Size")
            key: "size"
            align: Text.AlignRight
        }
        HeadCell {
            visible: root.showType
            x: root.xType
            width: root.typeW
            label: root.trashMode ? qsTr("Original location") : (root.searchMode ? qsTr("Folder") : qsTr("Type"))
            key: "type"
        }
    }

    ListView {
        id: view
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: 2
        clip: true
        model: root.model
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 800
        reuseItems: true
        WheelScroll {}
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            width: 10
        }

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool isSelected: Boolean(root.selected[row.modelData.path])
            readonly property bool hovered: mouse.hoverIndex === row.index
            readonly property bool isDrop: root.dropHighlight === row.modelData.path
            readonly property bool renaming: root.renamingPath === row.modelData.path
            width: view.width
            height: root.rowHeight

            Component.onCompleted: root.thumbNeeded(row.modelData)

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 12
                anchors.topMargin: 2
                anchors.bottomMargin: 2
                radius: 23
                color: row.isDrop ? ClockStyle.colPrimaryContainer
                    : row.isSelected ? ClockStyle.colSecondaryContainer
                    : row.hovered ? ClockStyle.colSurfaceHover : "transparent"
                border.width: root.cursor === row.index ? 2 : 0
                border.color: ClockStyle.colPrimary
                Behavior on color { ColorAnimation { duration: Appearance.dur(80) } }
            }

            FileIcon {
                x: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32
                entry: row.modelData
                starred: Boolean(root.starredSet[row.modelData.path])
                thumbSize: 64
                thumb: root.thumbs[row.modelData.path + "|" + row.modelData.mtime] ?? ""
                iconNames: root.iconResolver ? root.iconResolver(row.modelData) : []
            }
            // Selected and too long for its column: the name takes the row and the other columns step aside
            StyledText {
                id: fullName
                visible: false
                text: nameLabel.text
                font: nameLabel.font
            }
            readonly property bool nameOpen: row.isSelected && !row.renaming && fullName.implicitWidth > root.nameW
            StyledText {
                id: nameLabel
                visible: !row.renaming
                x: root.nameX
                anchors.verticalCenter: parent.verticalCenter
                width: row.nameOpen ? row.width - root.nameX - 24 : root.nameW
                text: row.modelData.name + (row.modelData.isLink && row.modelData.target ? "  → " + row.modelData.target : "")
                elide: row.nameOpen ? Text.ElideNone : Text.ElideMiddle
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: row.modelData.isDir ? Font.Medium : Font.Normal
                color: row.isSelected ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                opacity: row.modelData.hidden ? 0.6 : 1
            }
            StyledText {
                visible: root.wide && !row.nameOpen
                x: root.xDate
                width: root.dateW
                anchors.verticalCenter: parent.verticalCenter
                text: root.trashMode ? String(row.modelData.deleted ?? "").replace("T", " ").slice(0, 16) : root.dateText(row.modelData.mtime)
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: row.isSelected ? ClockStyle.colOnSecondaryContainer : ClockStyle.colSubtext
            }
            StyledText {
                visible: !row.nameOpen
                x: root.xSize
                width: root.sizeW
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: root.sizeText(row.modelData)
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: row.isSelected ? ClockStyle.colOnSecondaryContainer : ClockStyle.colSubtext
            }
            StyledText {
                visible: root.showType && !row.nameOpen
                x: root.xType
                width: root.typeW
                leftPadding: 8
                anchors.verticalCenter: parent.verticalCenter
                text: root.trashMode ? String(row.modelData.origPath ?? "") : (root.searchMode ? String(row.modelData.path).replace(/\/[^/]*$/, "") : root.typeText(row.modelData))
                elide: Text.ElideMiddle
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: row.isSelected ? ClockStyle.colOnSecondaryContainer : ClockStyle.colSubtext
            }
        }
    }

    Rectangle {
        id: renameBox
        readonly property int idx: {
            for (let i = 0; i < root.count; ++i)
                if (root.model[i].path === root.renamingPath)
                    return i;
            return -1;
        }
        visible: idx >= 0
        x: root.nameX - 8
        y: view.y + idx * root.rowHeight - view.contentY + 6
        width: Math.max(180, root.nameW + 8)
        height: 34
        radius: Appearance.rounding.full
        color: ClockStyle.colField
        border.width: 2
        border.color: ClockStyle.colPrimary
        z: 5
        TextInput {
            id: renameInput
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            color: ClockStyle.colOnSurface
            font.pixelSize: Appearance.font.pixelSize.small
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
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
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

        // Coordinates here are relative to this area, whose top edge is the list's top edge (+2)
        function idxAt(x: real, y: real): int {
            return root.indexAtPoint(x, y - 2);
        }

        onPositionChanged: m => {
            hoverIndex = idxAt(m.x, m.y);
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
                const y0 = Math.min(py, m.y), y1 = Math.max(py, m.y);
                band.x = Math.min(px, m.x);
                band.y = view.y + y0 - 0;
                band.width = Math.abs(m.x - px);
                band.height = y1 - y0;
                band.visible = true;
                const hits = [];
                const r0 = Math.max(0, Math.floor((y0 - 2 + view.contentY) / root.rowHeight));
                const r1 = Math.min(root.count - 1, Math.floor((y1 - 2 + view.contentY) / root.rowHeight));
                for (let r = r0; r <= r1; ++r)
                    hits.push(r);
                root.rubberBand(hits, additive);
                if (m.y < 20)
                    view.contentY = Math.max(0, view.contentY - 14);
                else if (m.y > height - 20)
                    view.contentY = Math.min(Math.max(0, view.contentHeight - view.height), view.contentY + 14);
            }
        }
        onExited: hoverIndex = -1

        onPressed: m => {
            if (m.button === Qt.MiddleButton) {
                // A middle click only opens; it never selects, drags or starts a rubber band
                pressIndex = -1;
                collapseOnRelease = false;
                const mi = idxAt(m.x, m.y);
                if (mi >= 0)
                    root.openInTabRequested(mi);
                return;
            }
            px = m.x;
            py = m.y;
            rubber = false;
            dragging = false;
            collapseOnRelease = false;
            pressIndex = idxAt(m.x, m.y);
            additive = (m.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) !== 0;
            if (m.button === Qt.RightButton) {
                if (pressIndex >= 0 && !root.selected[root.model[pressIndex].path])
                    root.selectRequested(pressIndex, 0);
                root.contextRequested(pressIndex, m.x, m.y + header.height);
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
            const i = idxAt(m.x, m.y);
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
