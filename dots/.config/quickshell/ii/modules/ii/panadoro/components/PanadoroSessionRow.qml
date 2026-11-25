import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.panadoro.components

/** A finished focus or break session, with the tag that earned it. */
Rectangle {
    id: root

    required property var modelData

    property var session: root.modelData
    property bool showDate: true

    readonly property var tag: PanadoroService.tagById(root.session?.tagId ?? "")
    readonly property bool isFocus: String(root.session?.phase ?? "focus") === "focus"
    readonly property color colAccent: PanadoroStyle.tagColor(root.tag)
    readonly property color colContainer: PanadoroStyle.tagContainer(root.tag)
    readonly property color colOn: PanadoroStyle.tagOn(root.tag)
    readonly property int minutes: Math.max(1, Math.round(Number(root.session?.durationSec ?? 0) / 60))

    implicitHeight: 66
    radius: PanadoroStyle.radiusNormal
    color: rowMouse.containsMouse ? PanadoroStyle.colFieldHover : PanadoroStyle.colSurface

    Behavior on color {
        animation: PanadoroStyle.motionFast.colorAnimation.createObject(this)
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    RowLayout {
        anchors {
            fill: parent
            leftMargin: PanadoroStyle.gapLarge
            rightMargin: PanadoroStyle.gapLarge
        }
        spacing: PanadoroStyle.gap

        MaterialShapeWrappedMaterialSymbol {
            text: root.isFocus ? PanadoroStyle.tagIcon(root.tag) : "coffee"
            iconSize: 18
            padding: 8
            shape: root.isFocus ? String(root.tag?.shape ?? "Cookie7Sided") : "SoftBurst"
            color: root.colContainer
            colSymbol: root.colOn
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.isFocus ? String(root.tag?.name ?? Translation.tr("Focus"))
                    : (String(root.session?.phase ?? "") === "longBreak" ? Translation.tr("Long break") : Translation.tr("Short break"))
                elide: Text.ElideRight
                font.pixelSize: PanadoroStyle.textNormal
                font.weight: Font.DemiBold
                color: PanadoroStyle.colOnSurface
            }

            StyledText {
                Layout.fillWidth: true
                text: {
                    const parts = [];
                    if (root.showDate)
                        parts.push(PanadoroService.relativeDay(PanadoroService.dateKey(new Date(Number(root.session?.endedAt ?? 0)))));
                    parts.push(Qt.formatTime(new Date(Number(root.session?.endedAt ?? 0)), "HH:mm"));
                    if (String(root.session?.note ?? "").length > 0)
                        parts.push(String(root.session.note));
                    return parts.join(" · ");
                }
                elide: Text.ElideRight
                font.pixelSize: PanadoroStyle.textSmall
                color: PanadoroStyle.colSubtext
            }
        }

        StyledText {
            text: PanadoroStyle.durationShort(root.minutes)
            font.family: PanadoroStyle.fontNumbers
            font.variableAxes: PanadoroStyle.axesDigits
            font.pixelSize: Appearance.font.pixelSize.large
            color: root.isFocus ? root.colAccent : PanadoroStyle.colOnSurfaceVariant
        }

        ClockIconButton {
            symbol: "delete"
            size: 30
            iconSize: 16
            tooltip: Translation.tr("Remove session")
            colIcon: PanadoroStyle.colSubtext
            onClicked: PanadoroService.deleteSession(root.session?.id ?? "")
        }
    }
}
