import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/// A year of contributions as weeks (columns) of days (rows), darker to brighter with the count.
Item {
    id: root

    property var weeks: []
    property var dates: []
    readonly property int cols: root.weeks.length
    readonly property real gap: 3
    readonly property real cell: root.cols > 0 ? Math.max(6, Math.min(30, (width - 30 - (root.cols - 1) * root.gap) / root.cols)) : 10
    readonly property real maxCount: {
        let m = 1;
        for (const w of root.weeks)
            for (const c of w)
                m = Math.max(m, c);
        return m;
    }
    property string hoverText: ""

    implicitHeight: 24 + 7 * (root.cell + root.gap) + 34

    function level(c: int): int {
        if (c <= 0) return 0;
        const r = c / root.maxCount;
        return r > 0.75 ? 4 : r > 0.5 ? 3 : r > 0.25 ? 2 : 1;
    }
    function tone(l: int): color {
        const base = Appearance.colors.colPrimary;
        if (l === 0) return Appearance.colors.colSurfaceContainerHighest;
        return Qt.rgba(base.r, base.g, base.b, [0, 0.28, 0.5, 0.75, 1][l]);
    }
    function monthLabel(i: int): string {
        const d = root.dates[i] ? root.dates[i][0] : "";
        if (!d) return "";
        const dt = new Date(d + "T00:00:00");
        const prev = i > 0 && root.dates[i - 1] ? new Date(root.dates[i - 1][0] + "T00:00:00") : null;
        return (!prev || prev.getMonth() !== dt.getMonth()) && dt.getDate() <= 14 || i === 0
            ? dt.toLocaleDateString(Qt.locale(), "MMM") : "";
    }

    Row {
        id: labels
        x: 30
        y: 0
        height: 20
        spacing: root.gap
        Repeater {
            model: root.cols
            delegate: Item {
                required property int index
                width: root.cell
                height: 20
                StyledText {
                    text: root.monthLabel(parent.index)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnSurfaceVariant
                    width: 40
                }
            }
        }
    }

    Column {
        x: 0
        y: 24
        spacing: root.gap
        Repeater {
            model: ["", "Mon", "", "Wed", "", "Fri", ""]
            delegate: Item {
                required property string modelData
                width: 28
                height: root.cell
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }
    }

    Row {
        id: grid
        x: 30
        y: 24
        spacing: root.gap
        Repeater {
            model: root.weeks
            delegate: Column {
                id: weekCol
                required property var modelData
                required property int index
                spacing: root.gap
                Repeater {
                    model: weekCol.modelData
                    delegate: Rectangle {
                        id: dayCell
                        required property int modelData
                        required property int index
                        width: root.cell
                        height: root.cell
                        radius: Math.max(2, root.cell * 0.28)
                        color: root.tone(root.level(modelData))
                        scale: dayArea.containsMouse ? 1.35 : 1
                        z: dayArea.containsMouse ? 2 : 0
                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                        MouseArea {
                            id: dayArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onContainsMouseChanged: {
                                if (!containsMouse) { root.hoverText = ""; return; }
                                const d = root.dates[weekCol.index]?.[dayCell.index] ?? "";
                                const when = d ? new Date(d + "T00:00:00").toLocaleDateString(Qt.locale(), "ddd d MMM yyyy") : "";
                                root.hoverText = dayCell.modelData === 0
                                    ? Translation.tr("No contributions · %1").arg(when)
                                    : Translation.tr("%n contribution(s) · %1", "", dayCell.modelData).arg(when);
                            }
                        }
                    }
                }
            }
        }
    }

    Row {
        anchors { left: parent.left; leftMargin: 30; bottom: parent.bottom }
        spacing: 6
        StyledText {
            text: root.hoverText !== "" ? root.hoverText : Translation.tr("Hover a day for its count")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.hoverText !== "" ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant
        }
    }

    Row {
        anchors { right: parent.right; bottom: parent.bottom }
        spacing: 4
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: Translation.tr("Less")
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnSurfaceVariant
        }
        Repeater {
            model: 5
            delegate: Rectangle {
                required property int index
                width: 12; height: 12; radius: 4
                color: root.tone(index)
            }
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: Translation.tr("More")
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnSurfaceVariant
        }
    }
}
