pragma ComponentBehavior: Bound

import QtQuick

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The in-progress titles as a carousel of full posters: the chosen one square on, its neighbours tucked
 * behind it, smaller, darker and turned toward the middle. Same look as the wallpaper picker's.
 * Cards sit at a fixed distance from the centre, so any number of titles (one included) reads
 * the same; the row does not wrap.
 */
Item {
    id: root

    property var model: []
    /// The centred card; the caller owns it (arrow keys), a click on a neighbour asks for it
    property int current: 0
    property bool active: false

    signal currentRequested(int index)
    signal activated(var title)
    signal openRequested(var title)

    readonly property real cardWidth: 310
    readonly property real cardHeight: 465
    // Card centres measured out from the middle, one to five cards away
    readonly property var offsets: [0, 290, 520, 736, 937, 1121]
    readonly property var chosen: root.model[root.current] ?? null

    implicitHeight: cardHeight + 16 + caption.implicitHeight + 8

    readonly property int count: root.model.length
    // From five cards up the row wraps, so both sides of the centre are always filled
    readonly property bool wraps: root.count >= 5

    // Where the row is heading. It runs past the ends when wrapping, so the cards take the
    // short way round instead of sweeping back through everything in between.
    property real target: root.current
    property int lastCurrent: root.current
    onCurrentChanged: {
        let step = root.current - root.lastCurrent;
        if (root.wraps && root.count > 0)
            step -= root.count * Math.round(step / root.count);
        root.target += root.wraps ? step : root.current - root.target;
        root.lastCurrent = root.current;
    }

    // The animated position the cards are laid out against
    property real pos: root.target
    Behavior on pos {
        NumberAnimation { duration: Appearance.dur(260); easing.type: Easing.OutCubic }
    }

    function lerp(a, b, t) {
        return a + (b - a) * t;
    }

    // Piecewise through the values at 0, 1, 2 ... cards from the middle
    function at(d, v) {
        const a = Math.min(Math.abs(d), v.length - 1);
        const i = Math.min(Math.floor(a), v.length - 2);
        return root.lerp(v[i], v[i + 1], a - i);
    }

    // Scroll amounts add up and the row moves a card each time they pass 120, the remainder
    // carried on. A WheelHandler listens to one axis only, so there is one for each: a sideways
    // swipe or a tilt wheel moves the row just as the vertical wheel does.
    property real wheelAcc: 0
    function wheelFeed(amount: real): void {
        if (amount === 0)
            return;
        if (Math.sign(amount) !== Math.sign(root.wheelAcc))
            root.wheelAcc = 0;
        root.wheelAcc += amount;
        const steps = Math.trunc(root.wheelAcc / 120);
        if (steps === 0)
            return;
        root.wheelAcc -= steps * 120;
        const to = root.current - steps;
        root.currentRequested(root.wraps ? ((to % root.count) + root.count) % root.count
            : Math.max(0, Math.min(root.count - 1, to)));
    }

    WheelHandler {
        target: null
        orientation: Qt.Vertical
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            event.accepted = true;
            root.wheelFeed(event.angleDelta.y);
        }
    }
    WheelHandler {
        target: null
        orientation: Qt.Horizontal
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            event.accepted = true;
            root.wheelFeed(event.angleDelta.x);
        }
    }

    Repeater {
        model: root.model

        ResumeCover {
            id: card
            required property var modelData
            required property int index

            // Distance from the centre in cards, the short way round when wrapping
            readonly property real d: {
                const raw = card.index - root.pos;
                return root.wraps ? raw - root.count * Math.round(raw / root.count) : raw;
            }
            readonly property bool isCentre: card.index === root.current

            title: card.modelData
            width: root.cardWidth
            height: root.cardHeight
            centred: card.isCentre
            selected: root.active && card.isCentre
            x: root.width / 2 - width / 2 + Math.sign(d) * root.at(d, root.offsets)
            y: 8
            z: 20 - Math.round(Math.abs(d) * 2)
            opacity: root.at(d, [1, 1, 1, 1, 0.7, 0])
            visible: opacity > 0.01

            transform: [
                Scale {
                    origin.x: card.width / 2
                    origin.y: card.height / 2
                    xScale: root.at(card.d, [1, 0.78, 0.64, 0.52, 0.43, 0.36])
                    yScale: xScale
                },
                Rotation {
                    origin.x: card.width / 2
                    origin.y: card.height / 2
                    axis { x: 0; y: 1; z: 0 }
                    angle: -Math.sign(card.d) * root.at(card.d, [0, 24, 32, 38, 42, 45])
                }
            ]

            // Away from the middle, a card first comes forward; the centred one acts
            onActivated: card.isCentre ? root.activated(card.modelData) : root.currentRequested(card.index)
            onOpenRequested: root.openRequested(card.modelData)

            // Dim as it recedes
            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.large
                color: "black"
                opacity: root.at(card.d, [0, 0.3, 0.45, 0.58, 0.7, 0.8])
                visible: opacity > 0.01
            }
        }
    }

    // One caption names the centred title and says what the button does
    Column {
        id: caption
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: root.cardHeight + 16 }
        width: 420
        spacing: 2
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.chosen ? String(root.chosen.display ?? root.chosen.name ?? "") : ""
            color: Appearance.colors.colOnLayer0
            font.pixelSize: Appearance.font.pixelSize.large
            font.weight: Font.Medium
        }
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            color: Appearance.colors.colPrimary
            font.pixelSize: Appearance.font.pixelSize.smaller
            text: {
                const n = root.chosen?.next;
                if (!n)
                    return "";
                const src = root.chosen.source === "jellyfin" ? "Jellyfin · " : "";
                const code = src + (n.code ? n.code + " · " : "");
                if (n.reason === "resume")
                    return code + "Resume at " + MediatorService.clock(n.position);
                if (n.reason === "next")
                    return code + "Up next";
                return code + "Play";
            }
        }
    }
}
