import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.grit.components

/**
 * Focus time per day, stacked by tag. Every segment keeps its tag's colour, so the
 * chart answers both "when did I focus?" and "on what?" without a second graph.
 */
Item {
    id: root

    property var series: []
    property real chartHeight: 150
    property bool showLabels: true
    property int labelEvery: 1
    property color colEmpty: GritStyle.colField
    property color colFallback: GritStyle.colPrimary

    readonly property real maxValue: {
        let max = 0;
        for (const day of Array.from(root.series ?? []))
            max = Math.max(max, Number(day?.total ?? 0));
        return Math.max(1, max);
    }

    implicitHeight: root.chartHeight + (root.showLabels ? 22 : 0)

    RowLayout {
        anchors.fill: parent
        spacing: 3

        Repeater {
            model: root.series

            Item {
                id: barColumn
                required property var modelData
                required property int index

                readonly property real total: Number(barColumn.modelData?.total ?? 0)
                readonly property real totalHeight: (barColumn.total / root.maxValue) * root.chartHeight
                readonly property var pieces: {
                    const segments = Array.from(barColumn.modelData?.segments ?? []);
                    const out = [];
                    let offset = 0;
                    for (const segment of segments) {
                        const seconds = Math.max(0, Number(segment.seconds ?? 0));
                        if (seconds <= 0)
                            continue;
                        const height = barColumn.totalHeight * seconds / Math.max(1, barColumn.total);
                        out.push({ segment: segment, height: height, offset: offset });
                        offset += height;
                    }
                    return out;
                }

                Layout.fillWidth: true
                Layout.fillHeight: true

                Rectangle {
                    id: track
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: labels.top
                        bottomMargin: root.showLabels ? 6 : 0
                    }
                    height: root.chartHeight
                    radius: GritStyle.radiusSmall
                    color: root.colEmpty
                    opacity: 0.3
                }

                Item {
                    id: stack
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: labels.top
                        bottomMargin: root.showLabels ? 6 : 0
                    }
                    height: barColumn.totalHeight

                    Repeater {
                        model: barColumn.pieces

                        Rectangle {
                            id: piece
                            required property var modelData

                            width: stack.width
                            height: Math.max(0, piece.modelData.height)
                            y: stack.height - piece.modelData.offset - piece.modelData.height
                            radius: Math.min(3, height / 2)
                            color: piece.modelData.segment?.tag
                                ? GritStyle.tagColor(piece.modelData.segment.tag)
                                : root.colFallback

                            Behavior on height {
                                enabled: !GritStyle.reducedMotion
                                NumberAnimation {
                                    duration: GritStyle.motionSpatial.duration
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: GritStyle.motionSpatial.bezierCurve
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    id: hover
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: labels.top
                        top: parent.top
                    }
                    hoverEnabled: true
                }

                StyledToolTip {
                    text: {
                        const day = barColumn.modelData;
                        if (!day)
                            return "";
                        const parts = [String(day.label ?? day.date ?? "") + " · "
                            + GritStyle.durationShort(Math.round(Number(day.total ?? 0) / 60))];
                        for (const segment of Array.from(day.segments ?? []))
                            if (Number(segment.seconds ?? 0) > 0)
                                parts.push(String(segment.tag?.name ?? Translation.tr("Untagged")) + " "
                                    + GritStyle.durationShort(Math.round(Number(segment.seconds) / 60)));
                        return parts.join("\n");
                    }
                    extraVisibleCondition: hover.containsMouse
                }

                RowLayout {
                    id: labels
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    visible: root.showLabels
                    height: 16

                    StyledText {
                        Layout.fillWidth: true
                        text: (barColumn.index % Math.max(1, root.labelEvery) === 0)
                            ? String(barColumn.modelData?.label ?? "") : ""
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: GritStyle.colSubtext
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
