import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.grit.components

/** A finished focus or break session, with the tag that earned it. */
Rectangle {
    id: root

    required property var modelData

    property var session: root.modelData
    property bool showDate: true

    readonly property var tag: GritService.tagById(root.session?.tagId ?? "")
    readonly property bool isFocus: String(root.session?.phase ?? "focus") === "focus"
    readonly property color colAccent: GritStyle.tagColor(root.tag)
    readonly property color colContainer: GritStyle.tagContainer(root.tag)
    readonly property color colOn: GritStyle.tagOn(root.tag)
    readonly property int minutes: Math.max(1, Math.round(Number(root.session?.durationSec ?? 0) / 60))

    implicitHeight: 66
    radius: GritStyle.radiusNormal
    color: rowMouse.containsMouse ? GritStyle.colFieldHover : GritStyle.colSurface

    Behavior on color {
        animation: GritStyle.motionFast.colorAnimation.createObject(this)
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
            leftMargin: GritStyle.gapLarge
            rightMargin: GritStyle.gapLarge
        }
        spacing: GritStyle.gap

        MaterialShapeWrappedMaterialSymbol {
            text: root.isFocus ? GritStyle.tagIcon(root.tag) : "coffee"
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
                font.pixelSize: GritStyle.textNormal
                font.weight: Font.DemiBold
                color: GritStyle.colOnSurface
            }

            StyledText {
                Layout.fillWidth: true
                text: {
                    const parts = [];
                    if (root.showDate)
                        parts.push(GritService.relativeDay(GritService.dateKey(new Date(Number(root.session?.endedAt ?? 0)))));
                    parts.push(Qt.formatTime(new Date(Number(root.session?.endedAt ?? 0)), "HH:mm"));
                    if (String(root.session?.note ?? "").length > 0)
                        parts.push(String(root.session.note));
                    return parts.join(" · ");
                }
                elide: Text.ElideRight
                font.pixelSize: GritStyle.textSmall
                color: GritStyle.colSubtext
            }
        }

        StyledText {
            text: GritStyle.durationShort(root.minutes)
            font.family: GritStyle.fontNumbers
            font.variableAxes: GritStyle.axesDigits
            font.pixelSize: Appearance.font.pixelSize.large
            color: root.isFocus ? root.colAccent : GritStyle.colOnSurfaceVariant
        }

        ClockIconButton {
            symbol: "delete"
            size: 30
            iconSize: 16
            tooltip: Translation.tr("Remove session")
            colIcon: GritStyle.colSubtext
            onClicked: GritService.deleteSession(root.session?.id ?? "")
        }
    }
}
