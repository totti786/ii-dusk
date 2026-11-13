import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.qanun

/**
 * The vertical cents ruler from Chronal's tuner, rebuilt with the shell's
 * Material surfaces: one tick every five cents, labels every ten, and a marker
 * that carries the note colour.
 */
Item {
    id: root

    property real cents: 0
    property real inTuneCents: 5
    property string noteLabel: "—"
    property color markerColor: QanunStyle.tuningColor(root.cents, root.inTuneCents)
    property color tickColor: Qt.alpha(QanunStyle.colOnSurface, 0.26)
    property color labelColor: QanunStyle.colSubtext

    implicitWidth: 132
    clip: false

    property real shownCents: Number(root.cents) || 0
    Behavior on shownCents {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    readonly property real usableHeight: Math.max(1, height - 44)
    function yFor(value): real {
        return 22 + (50 - Math.max(-50, Math.min(50, Number(value) || 0))) / 100 * root.usableHeight;
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: QanunStyle.colPane
    }

    StyledText {
        anchors {
            top: parent.top
            topMargin: 10
            horizontalCenter: parent.horizontalCenter
        }
        text: "SHARP"
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Bold
        font.letterSpacing: 1.4
        color: QanunStyle.colSubtext
    }

    StyledText {
        anchors {
            bottom: parent.bottom
            bottomMargin: 10
            horizontalCenter: parent.horizontalCenter
        }
        text: "FLAT"
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Bold
        font.letterSpacing: 1.4
        color: QanunStyle.colSubtext
    }

    // Centre line and the in-tune band.
    Rectangle {
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: 22 + (50 - root.inTuneCents) / 100 * root.usableHeight
        }
        width: parent.width - 24
        height: (root.inTuneCents * 2 / 100) * root.usableHeight
        color: Qt.alpha(QanunStyle.colInTune, 0.11)
        radius: 4
    }

    Repeater {
        model: 21

        Item {
            id: tick
            required property int index
            readonly property int value: 50 - tick.index * 5
            readonly property bool major: tick.value % 10 === 0
            readonly property real centre: 50

            y: root.yFor(tick.value)
            width: root.width
            height: 1

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 20
                width: tick.major ? 18 : 10
                height: 1
                color: tick.value === 0
                    ? QanunStyle.colOnSurface
                    : (Math.abs(tick.value) <= root.inTuneCents ? QanunStyle.colInTune : root.tickColor)
                opacity: tick.value === 0 ? 0.8 : 0.75
            }

            StyledText {
                visible: tick.major
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                text: (tick.value > 0 ? "+" : "") + String(tick.value)
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.numbers
                color: Math.abs(tick.value) <= root.inTuneCents
                    ? QanunStyle.colInTune : root.labelColor
            }
        }
    }

    // Marker: a needle over the ruler, with the current offset printed on it.
    Item {
        id: marker
        width: root.width
        height: 30
        y: root.yFor(root.shownCents) - height / 2

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: 12
            width: root.width - 24
            height: 2
            radius: 1
            color: root.markerColor
            opacity: 0.82
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: 8
            width: 10
            height: 10
            radius: 5
            color: root.markerColor
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 24
            implicitWidth: centsPill.implicitWidth + 14
            implicitHeight: 22
            radius: Appearance.rounding.full
            color: QanunStyle.colOnSurface
            opacity: 0.92

            StyledText {
                id: centsPill
                anchors.centerIn: parent
                text: {
                    const value = Number(root.cents) || 0;
                    return (value > 0 ? "+" : "") + value.toFixed(1);
                }
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.numbers
                font.weight: Font.DemiBold
                color: QanunStyle.colBackground
            }
        }
    }

    // Tick marks still paint at the very edges; the marker clamps itself.
    onCentsChanged: root.shownCents = Number(root.cents) || 0
    onHeightChanged: root.shownCents = Number(root.cents) || 0
}
