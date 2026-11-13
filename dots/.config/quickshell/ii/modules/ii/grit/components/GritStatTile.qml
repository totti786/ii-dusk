import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.grit.components

/** One number worth looking at: an expressive icon badge, the value, and what it means. */
Rectangle {
    id: root

    property string symbol: "insights"
    property string value: ""
    property string label: ""
    property string hint: ""
    property string shapeName: "Cookie7Sided"
    property color colAccent: GritStyle.colPrimary
    property color colContainer: GritStyle.colPrimaryContainer
    property color colOnContainer: GritStyle.colOnPrimaryContainer
    /// The streak cards get a quietly breathing flame instead of a static glyph.
    property bool flame: false

    implicitHeight: 108
    radius: GritStyle.radiusLarge
    color: GritStyle.colSurface

    RowLayout {
        anchors {
            fill: parent
            margins: GritStyle.cardPadding
        }
        spacing: GritStyle.gapLarge

        MaterialShapeWrappedMaterialSymbol {
            id: badge
            text: root.symbol
            iconSize: 22
            padding: 11
            shape: root.shapeName
            color: root.colContainer
            colSymbol: ColorUtils.mostReadable(root.colContainer,
                [root.colOnContainer, GritStyle.colOnSurface])

            SequentialAnimation on scale {
                running: (root.flame && Number(root.value) > 0 && !GritStyle.reducedMotion) && !Appearance.motionOff
                loops: Animation.Infinite
                NumberAnimation {
                    from: 1
                    to: 1.08
                    duration: 1400
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    from: 1.08
                    to: 1
                    duration: 1400
                    easing.type: Easing.InOutSine
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.value
                elide: Text.ElideRight
                font.family: GritStyle.fontNumbers
                font.variableAxes: GritStyle.axesDigitsBold
                font.pixelSize: Appearance.font.pixelSize.huge + 2
                color: GritStyle.colOnSurface
                animateChange: !GritStyle.reducedMotion
            }

            StyledText {
                Layout.fillWidth: true
                text: root.label
                elide: Text.ElideRight
                font.pixelSize: GritStyle.textNormal
                font.weight: Font.DemiBold
                color: GritStyle.colOnSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.hint.length > 0
                text: root.hint
                elide: Text.ElideRight
                font.pixelSize: GritStyle.textSmall
                color: GritStyle.colSubtext
            }
        }
    }
}
