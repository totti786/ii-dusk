pragma ComponentBehavior: Bound

import QtQuick

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Everyone in the call, as a grid of tiles that fills the space.
 *
 * Tiles are 16:9 and as large as the room allows, people with a camera first. Pressing a tile
 * enlarges it and moves the others to a strip beside it (below it in a narrow window); pressing
 * it again brings the grid back. People are matched to tiles by id, so a mute, a join or a leave
 * never rebuilds the other tiles and restarts their video.
 */
Item {
    id: root

    /** The people in the channel, as the service publishes them. */
    property var participants: []
    /** Ids of the people talking now. */
    property var speakingIds: []
    /** Camera streams: person id to the url the helper serves it on. */
    property var remoteVideo: ({})
    property bool audioSupported: false
    /** False while the stage is hidden: nothing plays then. */
    property bool active: true

    property string focusedId: ""

    signal volumeRequested(string userId)

    readonly property real gap: ClockStyle.gapSmall

    // ── Who is shown, and in what order ──────────────────────────────────────────────────
    readonly property var byId: {
        const map = {};
        for (const p of root.participants)
            map[String(p.id)] = p;
        return map;
    }

    // People with a camera first, otherwise the order the channel gives
    readonly property var orderedIds: {
        const list = root.participants.map((p, i) => ({ "id": String(p.id), "rank": root.remoteVideo[String(p.id)] ? 0 : 1, "i": i }));
        list.sort((a, b) => (a.rank - b.rank) || (a.i - b.i));
        return list.map(entry => entry.id);
    }

    ListModel {
        id: tileModel
    }

    // Bumped whenever the model changes order, which does not change its count
    property int revision: 0

    function syncTiles(): void {
        const want = root.orderedIds;
        for (let i = tileModel.count - 1; i >= 0; --i) {
            if (want.indexOf(tileModel.get(i).uid) < 0)
                tileModel.remove(i);
        }
        for (let i = 0; i < want.length; ++i) {
            let found = -1;
            for (let j = i; j < tileModel.count; ++j) {
                if (tileModel.get(j).uid === want[i]) {
                    found = j;
                    break;
                }
            }
            if (found < 0)
                tileModel.insert(i, { "uid": want[i] });
            else if (found !== i)
                tileModel.move(found, i, 1);
        }
        if (root.focusedId !== "" && want.indexOf(root.focusedId) < 0)
            root.focusedId = "";
        root.revision++;
    }

    onOrderedIdsChanged: root.syncTiles()
    Component.onCompleted: root.syncTiles()

    // ── Layout ───────────────────────────────────────────────────────────────────────────

    /** The biggest 16:9 grid of n tiles in w × h, rows centred. */
    function gridRects(n: int, w: real, h: real): var {
        const gap = root.gap;
        if (n <= 0 || w < 1 || h < 1)
            return [];
        let best = null;
        for (let cols = 1; cols <= n; ++cols) {
            const rows = Math.ceil(n / cols);
            let tw = (w - (cols - 1) * gap) / cols;
            let th = tw * 9 / 16;
            const maxH = (h - (rows - 1) * gap) / rows;
            if (th > maxH) {
                th = maxH;
                tw = th * 16 / 9;
            }
            if (tw < 1 || th < 1)
                continue;
            if (best === null || tw * th > best.w * best.h)
                best = { "cols": cols, "rows": rows, "w": tw, "h": th };
        }
        if (best === null)
            best = { "cols": 1, "rows": n, "w": w, "h": Math.max(1, (h - (n - 1) * gap) / n) };
        const top = (h - (best.rows * best.h + (best.rows - 1) * gap)) / 2;
        const rects = [];
        for (let i = 0; i < n; ++i) {
            const row = Math.floor(i / best.cols);
            const col = i % best.cols;
            const inRow = row === best.rows - 1 ? n - row * best.cols : best.cols;
            const rowWidth = inRow * best.w + (inRow - 1) * gap;
            rects.push({ "x": (w - rowWidth) / 2 + col * (best.w + gap), "y": top + row * (best.h + gap), "w": best.w, "h": best.h });
        }
        return rects;
    }

    /** One tile large, the rest in a strip: on the right when the room is wide, below when it is not. */
    function spotlightRects(ids: var, focused: string, w: real, h: real): var {
        const gap = root.gap;
        const others = ids.filter(id => id !== focused).length;
        const rects = [];
        if (others === 0) {
            return ids.map(() => ({ "x": 0, "y": 0, "w": w, "h": h }));
        }
        const wide = w >= h * 1.1 && w >= 520;
        const strip = wide ? Math.max(120, Math.min(220, w * 0.24)) : Math.max(80, Math.min(120, h * 0.25));
        let slot = 0;
        for (const id of ids) {
            if (id === focused) {
                rects.push(wide ? { "x": 0, "y": 0, "w": w - strip - gap, "h": h } : { "x": 0, "y": 0, "w": w, "h": h - strip - gap });
                continue;
            }
            if (wide) {
                const th = Math.min(strip * 9 / 16, (h - (others - 1) * gap) / others);
                const tw = th * 16 / 9;
                const top = (h - (others * th + (others - 1) * gap)) / 2;
                rects.push({ "x": w - strip + (strip - tw) / 2, "y": top + slot * (th + gap), "w": tw, "h": th });
            } else {
                const tw = Math.min(strip * 16 / 9, (w - (others - 1) * gap) / others);
                const th = tw * 9 / 16;
                const left = (w - (others * tw + (others - 1) * gap)) / 2;
                rects.push({ "x": left + slot * (tw + gap), "y": h - strip + (strip - th) / 2, "w": tw, "h": th });
            }
            slot++;
        }
        return rects;
    }

    readonly property var rects: {
        root.revision;
        const w = area.width;
        const h = area.height;
        const ids = [];
        for (let i = 0; i < tileModel.count; ++i)
            ids.push(tileModel.get(i).uid);
        if (root.focusedId !== "" && ids.indexOf(root.focusedId) >= 0)
            return root.spotlightRects(ids, root.focusedId, w, h);
        return root.gridRects(ids.length, w, h);
    }

    // ── View ─────────────────────────────────────────────────────────────────────────────

    Item {
        id: area
        anchors.fill: parent

        // Tiles settle into place with a short glide, but do not fly in from the corner on first layout
        property bool settled: false
        Timer {
            interval: 50
            running: true
            onTriggered: area.settled = true
        }

        Repeater {
            model: tileModel

            delegate: DiscordoVideoTile {
                id: tile

                required property int index
                required property string uid

                readonly property var person: root.byId[tile.uid] ?? ({})
                readonly property var rect: root.rects[tile.index] ?? ({ "x": 0, "y": 0, "w": 0, "h": 0 })

                x: tile.rect.x
                y: tile.rect.y
                width: tile.rect.w
                height: tile.rect.h
                Behavior on x { enabled: area.settled; NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                Behavior on y { enabled: area.settled; NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                Behavior on width { enabled: area.settled; NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                Behavior on height { enabled: area.settled; NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }

                name: String(tile.person.name || tile.person.id || Translation.tr("Participant"))
                avatarUrl: String(tile.person.avatar_url || "")
                videoUrl: String(root.remoteVideo[tile.uid] ?? "")
                speaking: root.speakingIds.indexOf(tile.uid) >= 0
                muted: tile.person.muted === true
                deafened: tile.person.deafened === true
                isSelf: tile.person.self === true
                mirrored: Persistent.ready && Persistent.states.discordoVoice.mirrorPreview
                onMirrorClicked: Persistent.states.discordoVoice.mirrorPreview = !Persistent.states.discordoVoice.mirrorPreview
                focused: root.focusedId === tile.uid
                active: root.active
                canAdjustVolume: root.audioSupported && tile.person.self !== true

                onClicked: root.focusedId = root.focusedId === tile.uid ? "" : tile.uid
                onVolumeClicked: root.volumeRequested(tile.uid)
            }
        }

        StyledText {
            anchors.centerIn: parent
            visible: tileModel.count === 0
            text: Translation.tr("Nobody here yet")
            color: ClockStyle.colOnSurfaceVariant
            font.pixelSize: ClockStyle.textNormal
        }
    }
}
