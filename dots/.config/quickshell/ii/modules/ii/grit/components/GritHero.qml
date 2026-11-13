import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.grit.components

/**
 * The banner at the top of a page: our own sentence about the page, with a large
 * scalloped ornament and room for a live control on the right.
 */
Rectangle {
    id: root

    property string symbol: ""
    property string title: ""
    property string text: ""
    property bool compact: false
    property string shapeName: "Cookie9Sided"
    property color colContainer: GritStyle.colTertiaryContainer
    property color colOnContainer: GritStyle.colOnTertiaryContainer
    property color colAccent: GritStyle.colTertiary
    default property alias content: trailingRow.data

    implicitHeight: Math.max(root.compact ? 96 : GritStyle.heroMinHeight, body.implicitHeight + GritStyle.gapHuge * 2)
    radius: GritStyle.radiusCard
    color: root.colContainer

    Item {
        id: ornament
        anchors.fill: parent
        visible: false
        MaterialShape {
            width: 260
            height: width
            x: root.width - width * 0.7
            y: -height * 0.3
            shapeString: "Cookie12Sided"
            color: root.colOnContainer
        }
    }
    Rectangle {
        id: mask
        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        anchors.fill: parent
        source: ornament
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
        opacity: 0.08
    }

    RowLayout {
        id: body
        anchors {
            fill: parent
            leftMargin: GritStyle.gapHuge
            rightMargin: GritStyle.gapHuge
        }
        spacing: GritStyle.gapLarge

        MaterialShapeWrappedMaterialSymbol {
            visible: !root.compact && root.symbol.length > 0
            text: root.symbol
            iconSize: 30
            padding: 16
            shape: root.shapeName
            color: root.colAccent
            colSymbol: ColorUtils.mostReadable(root.colAccent, [GritStyle.colOnPrimary, GritStyle.colBackground])
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: root.title
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: GritStyle.fontTitle
                font.variableAxes: GritStyle.axesTitle
                font.pixelSize: root.compact ? Appearance.font.pixelSize.huge : Appearance.font.pixelSize.huge + 6
                color: root.colOnContainer
            }

            StyledText {
                Layout.fillWidth: true
                Layout.maximumWidth: 640
                visible: root.text.length > 0
                text: root.text
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: GritStyle.textNormal
                color: root.colOnContainer
                opacity: 0.86
            }
        }

        RowLayout {
            id: trailingRow
            Layout.alignment: Qt.AlignVCenter
            spacing: GritStyle.gapSmall
        }
    }
}
