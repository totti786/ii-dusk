pragma ComponentBehavior: Bound

import QtQuick

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The graph drawn: nodes in three columns (what makes sound, what passes it on, what plays
 * it), links as curves between their ports. Drag from a port to another of the same kind to
 * connect, drag a node's header to move it, click a link to select it and Delete to remove.
 */
Rectangle {
    id: root

    property bool showAudio: true
    property bool showMidi: true
    property bool showVideo: false
    property bool showMonitors: false
    property bool connectedOnly: false

    readonly property int nodeWidth: 230
    readonly property int columnGap: 150
    readonly property int headerH: 32
    readonly property int rowH: 22
    readonly property int margin: 36

    property int selectedLink: -1
    property int hoverLink: -1
    // A link being dragged out of a port
    property var pending: null
    property real cursorX: 0
    property real cursorY: 0
    property string hoveredPort: ""

    readonly property var layout: {
        const graph = PatchbayService.graph;
        const saved = PatchbayService.positions;
        const kinds = { "audio": root.showAudio, "midi": root.showMidi, "video": root.showVideo };
        const linked = {};
        graph.links.forEach(l => {
            linked[l.outPort] = true;
            linked[l.inPort] = true;
        });

        const columns = [[], [], []];
        for (const node of graph.nodes) {
            const visible = node.ports.filter(p => kinds[p.kind] && (root.showMonitors || !p.monitor));
            if (visible.length === 0)
                continue;
            if (root.connectedOnly && !visible.some(p => linked[p.id]))
                continue;
            const ins = visible.filter(p => p.direction === "in");
            const outs = visible.filter(p => p.direction === "out");
            const rows = Math.max(ins.length, outs.length);
            const entry = { "node": node, "ins": ins, "outs": outs, "w": root.nodeWidth,
                "headerH": root.headerH, "rowH": root.rowH, "h": root.headerH + rows * root.rowH + 8, "x": 0, "y": 0 };
            columns[ins.length > 0 && outs.length > 0 ? 1 : (outs.length > 0 ? 0 : 2)].push(entry);
        }

        const entries = [];
        let width = 0;
        let height = 0;
        columns.forEach((column, c) => {
            column.sort((a, b) => a.node.title.localeCompare(b.node.title));
            let y = root.margin;
            for (const entry of column) {
                const at = saved[entry.node.name];
                entry.x = at ? at.x : root.margin + c * (root.nodeWidth + root.columnGap);
                entry.y = at ? at.y : y;
                y += entry.h + 18;
                width = Math.max(width, entry.x + entry.w);
                height = Math.max(height, entry.y + entry.h);
                entries.push(entry);
            }
        });

        // Where each port's dot is, for the links and for dropping onto
        const ports = {};
        for (const entry of entries) {
            entry.ins.forEach((p, i) => ports[p.id] = { "id": p.id, "kind": p.kind, "dir": "in", "node": entry.node.id,
                "x": entry.x, "y": entry.y + entry.headerH + (i + 0.5) * entry.rowH });
            entry.outs.forEach((p, i) => ports[p.id] = { "id": p.id, "kind": p.kind, "dir": "out", "node": entry.node.id,
                "x": entry.x + entry.w, "y": entry.y + entry.headerH + (i + 0.5) * entry.rowH });
        }
        const byId = {};
        entries.forEach(e => byId[e.node.id] = e);
        return { "entries": entries, "byId": byId, "ports": ports, "linked": linked,
            "width": width + root.margin, "height": height + root.margin,
            "links": graph.links.filter(l => ports[l.outPort] && ports[l.inPort]) };
    }

    color: ClockStyle.colBackground
    radius: ClockStyle.radiusCard
    border.width: 2
    border.color: ClockStyle.colPane
    clip: true

    function kindColor(kind) {
        return kind === "midi" ? ClockStyle.colTertiary : kind === "video" ? Appearance.colors.colSecondary : ClockStyle.colPrimary;
    }

    function curve(a, b, t) {
        const dx = Math.max(60, Math.abs(b.x - a.x) / 2);
        const x1 = a.x + dx, x2 = b.x - dx;
        const u = 1 - t;
        return {
            "x": u * u * u * a.x + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * b.x,
            "y": u * u * u * a.y + 3 * u * u * t * a.y + 3 * u * t * t * b.y + t * t * t * b.y
        };
    }

    function linkAt(x, y) {
        let best = -1;
        let bestDistance = 8;
        for (const link of root.layout.links) {
            const a = root.layout.ports[link.outPort];
            const b = root.layout.ports[link.inPort];
            for (let i = 0; i <= 24; i++) {
                const p = root.curve(a, b, i / 24);
                const d = Math.hypot(p.x - x, p.y - y);
                if (d < bestDistance) {
                    bestDistance = d;
                    best = link.id;
                }
            }
        }
        return best;
    }

    // The nearest port of the right kind and direction to connect a pending link to
    function targetAt(x, y) {
        const from = root.pending;
        if (!from)
            return null;
        let best = null;
        let bestDistance = 18;
        for (const id in root.layout.ports) {
            const p = root.layout.ports[id];
            if (p.dir === from.dir || p.kind !== from.kind || p.node === from.node)
                continue;
            const d = Math.hypot(p.x - x, p.y - y);
            if (d < bestDistance) {
                bestDistance = d;
                best = p;
            }
        }
        return best;
    }

    function removeSelected(): void {
        if (root.selectedLink >= 0) {
            PatchbayService.disconnectLink(root.selectedLink);
            root.selectedLink = -1;
        }
    }

    // The nodes on show, by id. The list is replaced only when the set changes: a new array
    // would make the Repeater rebuild every card, and a card being dragged with it.
    property var entryIds: []
    readonly property var emptyEntry: ({ "node": { "id": -1, "name": "", "title": "", "mediaClass": "" },
        "ins": [], "outs": [], "w": 0, "h": 0, "headerH": 0, "rowH": 0, "x": 0, "y": 0 })

    onLayoutChanged: {
        const ids = root.layout.entries.map(e => e.node.id);
        if (ids.join(",") !== root.entryIds.join(","))
            root.entryIds = ids;
        canvas.requestPaint();
    }
    onSelectedLinkChanged: canvas.requestPaint()
    onHoverLinkChanged: canvas.requestPaint()
    onCursorXChanged: if (root.pending) canvas.requestPaint()
    onCursorYChanged: if (root.pending) canvas.requestPaint()
    onPendingChanged: canvas.requestPaint()

    Flickable {
        WheelScroll {}
        id: flick
        anchors.fill: parent
        contentWidth: Math.max(root.layout.width, width)
        contentHeight: Math.max(root.layout.height, height)
        interactive: root.pending === null
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Canvas {
            id: canvas
            width: flick.contentWidth
            height: flick.contentHeight
            renderTarget: Canvas.FramebufferObject
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.lineCap = "round";
                const ports = root.layout.ports;
                for (const link of root.layout.links) {
                    const a = ports[link.outPort];
                    const b = ports[link.inPort];
                    const c = root.kindColor(a.kind);
                    const selected = link.id === root.selectedLink;
                    const hover = link.id === root.hoverLink;
                    ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, selected || hover ? 1 : (link.state === "active" ? 0.7 : 0.4));
                    ctx.lineWidth = selected ? 4.5 : hover ? 3.5 : 2.5;
                    const dx = Math.max(60, Math.abs(b.x - a.x) / 2);
                    ctx.beginPath();
                    ctx.moveTo(a.x, a.y);
                    ctx.bezierCurveTo(a.x + dx, a.y, b.x - dx, b.y, b.x, b.y);
                    ctx.stroke();
                }
                const from = root.pending;
                if (from) {
                    const a = from.dir === "out" ? from : { "x": root.cursorX, "y": root.cursorY };
                    const b = from.dir === "out" ? { "x": root.cursorX, "y": root.cursorY } : from;
                    const c = root.kindColor(from.kind);
                    ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.9);
                    ctx.lineWidth = 3;
                    ctx.setLineDash([6, 5]);
                    const dx = Math.max(60, Math.abs(b.x - a.x) / 2);
                    ctx.beginPath();
                    ctx.moveTo(a.x, a.y);
                    ctx.bezierCurveTo(a.x + dx, a.y, b.x - dx, b.y, b.x, b.y);
                    ctx.stroke();
                }
            }

            // Behind the nodes: hovering, selecting and removing links
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: mouse => root.hoverLink = root.linkAt(mouse.x, mouse.y)
                onExited: root.hoverLink = -1
                onClicked: mouse => root.selectedLink = root.linkAt(mouse.x, mouse.y)
                onDoubleClicked: mouse => {
                    const id = root.linkAt(mouse.x, mouse.y);
                    if (id >= 0)
                        PatchbayService.disconnectLink(id);
                }
            }
        }

        // The cards sit in their own layer over the canvas, in the same coordinates
        Item {
            id: nodesLayer
            width: canvas.width
            height: canvas.height

        Repeater {
            model: root.entryIds
            delegate: PatchbayNode {
                id: card
                required property int modelData
                entry: root.layout.byId[card.modelData] ?? root.emptyEntry
                hoveredPort: root.hoveredPort
                linkedPorts: root.layout.linked
                onHeaderMoved: (dx, dy) => PatchbayService.setPosition(card.entry.node.name,
                    Math.max(0, card.entry.x + dx), Math.max(0, card.entry.y + dy))
                onPortPressed: (port, px, py) => {
                    root.cursorX = px;
                    root.cursorY = py;
                    root.pending = root.layout.ports[port.id] ?? null;
                }
                onPortMoved: (px, py) => {
                    root.cursorX = px;
                    root.cursorY = py;
                    const target = root.targetAt(px, py);
                    root.hoveredPort = target ? String(target.id) : "";
                }
                onPortReleased: (px, py) => {
                    const target = root.targetAt(px, py);
                    const from = root.pending;
                    root.pending = null;
                    root.hoveredPort = "";
                    if (!target || !from)
                        return;
                    const out = from.dir === "out" ? from : target;
                    const inn = from.dir === "out" ? target : from;
                    const exists = root.layout.links.some(l => l.outPort === out.id && l.inPort === inn.id);
                    if (!exists)
                        PatchbayService.connectPorts(out.id, inn.id);
                }
            }
        }
        }
    }

    ClockEmptyState {
        anchors.centerIn: parent
        visible: root.layout.entries.length === 0
        symbol: "account_tree"
        title: Translation.tr("Nothing to show")
        subtitle: PatchbayService.graph.nodes.length === 0 ? Translation.tr("Is PipeWire running?")
            : Translation.tr("Every node is hidden by the filters above")
    }
}
