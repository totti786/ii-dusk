import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.panadoro.components

/** A grid of Material Symbols used to give a habit or tag its face. */
Item {
    id: root

    property string selected: ""
    property var icons: [
        "check_circle", "fitness_center", "menu_book", "water_drop",
        "bed", "self_improvement", "code", "music_note",
        "restaurant", "directions_run", "brush", "medication",
        "work", "school", "psychiatry", "local_fire_department"
    ]
    property color colAccent: PanadoroStyle.colPrimary

    signal picked(string icon)

    implicitHeight: flow.implicitHeight

    Flow {
        id: flow
        width: root.width
        spacing: PanadoroStyle.gapTiny + 2

        Repeater {
            model: root.icons

            RippleButton {
                id: iconButton
                required property string modelData
                readonly property bool active: root.selected === iconButton.modelData

                width: 42
                height: 42
                buttonRadius: iconButton.active ? PanadoroStyle.radiusSmall : PanadoroStyle.pill(42)
                buttonRadiusPressed: PanadoroStyle.radiusSmall
                colBackground: iconButton.active ? root.colAccent : PanadoroStyle.colField
                colBackgroundHover: iconButton.active
                    ? ColorUtils.mix(root.colAccent, PanadoroStyle.colOnSurface, 0.9)
                    : PanadoroStyle.colFieldHover
                colRipple: PanadoroStyle.colFieldHover
                onClicked: root.picked(iconButton.modelData)

                contentItem: Item {
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: iconButton.modelData
                        iconSize: 20
                        fill: iconButton.active ? 1 : 0
                        color: iconButton.active
                            ? ColorUtils.mostReadable(root.colAccent,
                                [PanadoroStyle.colOnPrimary, PanadoroStyle.colBackground])
                            : PanadoroStyle.colOnSurfaceVariant
                    }
                }
            }
        }
    }
}
