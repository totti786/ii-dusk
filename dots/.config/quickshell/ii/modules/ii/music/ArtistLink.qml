pragma ComponentBehavior: Bound

import QtQuick

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A song's artist names; each one opens that artist's page. The text is drawn whole (so it
 * elides like any label) and a hover line shows which name is under the pointer. Songs saved
 * before artist ids were kept have none, so their whole artist text is searched for instead.
 */
Item {
    id: root

    property var track: null
    property string artistText: root.track?.artist ?? ""
    /// Plain text after the names, e.g. " · Album", never a link
    property string suffix: ""
    property color color: ClockStyle.colSubtext
    property color hoverColor: ClockStyle.colPrimary
    property int pixelSize: ClockStyle.textSmall
    property bool linked: true

    readonly property var refs: root.track?.artistRefs ?? []
    // Only trust the ids when they spell exactly the text shown
    readonly property bool exact: root.refs.length > 0 && root.refs.map(r => r.name).join(", ") === root.artistText
    readonly property var names: root.exact ? root.refs.map(r => r.name) : (root.artistText.length > 0 ? [root.artistText] : [])
    property int hovered: -1

    implicitHeight: label.implicitHeight
    implicitWidth: label.implicitWidth

    FontMetrics {
        id: fm
        font: label.font
    }

    function segmentAt(x: real): int {
        let at = 0;
        const gap = fm.advanceWidth(", ");
        for (let i = 0; i < root.names.length; i++) {
            const w = fm.advanceWidth(root.names[i]);
            if (x >= at && x <= at + w)
                return x <= label.width - (label.truncated ? 8 : 0) ? i : -1;
            at += w + gap;
        }
        return -1;
    }

    function segmentX(i: int): real {
        let at = 0;
        for (let k = 0; k < i; k++)
            at += fm.advanceWidth(root.names[k]) + fm.advanceWidth(", ");
        return at;
    }

    StyledText {
        id: label
        anchors.fill: parent
        text: root.artistText + (root.suffix.length > 0 && root.artistText.length > 0 ? root.suffix : root.suffix.replace(/^ · /, ""))
        color: root.hovered >= 0 ? root.hoverColor : root.color
        font.pixelSize: root.pixelSize
        elide: Text.ElideRight
        Behavior on color { ColorAnimation { duration: Appearance.dur(100) } }
    }

    // The line under the hovered name
    Rectangle {
        visible: root.hovered >= 0
        x: root.hovered >= 0 ? root.segmentX(root.hovered) : 0
        width: root.hovered >= 0 ? Math.min(fm.advanceWidth(root.names[root.hovered]), label.width - x) : 0
        y: label.baselineOffset + 2
        height: 1
        color: root.hoverColor
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.linked && root.names.length > 0
        hoverEnabled: true
        cursorShape: root.hovered >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
        // Only the names are links; a click on the suffix or the gap goes through to the row
        propagateComposedEvents: true
        onPositionChanged: m => root.hovered = root.segmentAt(m.x)
        onExited: root.hovered = -1
        onClicked: m => {
            const i = root.segmentAt(m.x);
            if (i < 0) {
                m.accepted = false;
                return;
            }
            const ref = root.exact ? root.refs[i] : null;
            MusicService.requestArtist(ref ? ref.id : "", root.names[i], "");
        }
        onPressed: m => { if (root.segmentAt(m.x) < 0) m.accepted = false; }
    }
}
