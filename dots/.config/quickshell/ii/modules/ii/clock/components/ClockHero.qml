import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * The banner at the top of a page: what the page is for, in a sentence, with a big scalloped
 * shape parked off its corner. Extra items (a button, a pill) go in `trailing`.
 */
Rectangle {
    id: root

    property string symbol: ""
    property string title: ""
    property string text: ""
    property bool compact: false
    property var shape: MaterialShape.Shape.Cookie9Sided
    property alias trailing: trailingRow.data

    implicitHeight: Math.max(root.compact ? 0 : 112, body.implicitHeight + ClockStyle.gapHuge * 2)
    radius: ClockStyle.radiusCard
    color: ClockStyle.colTertiaryContainer

    // A plain clip would square off the rounded corner, so a mask of the banner cuts it
    Item {
        id: ornament
        anchors.fill: parent
        visible: false
        MaterialShape {
            width: 250
            height: width
            x: root.width - width * 0.72
            y: -height * 0.24
            shapeString: "Cookie12Sided"
            color: ClockStyle.colOnTertiaryContainer
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
        opacity: 0.1
    }

    RowLayout {
        id: body
        anchors {
            fill: parent
            leftMargin: ClockStyle.gapHuge
            rightMargin: ClockStyle.gapHuge
        }
        spacing: ClockStyle.gapHuge - 2

        ClockBadge {
            visible: !root.compact && root.symbol.length > 0
            size: 72
            text: root.symbol
            shape: root.shape
            color: ClockStyle.colTertiary
            colSymbol: ClockStyle.colOnTertiary
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: ClockStyle.gapTiny
            StyledText {
                Layout.fillWidth: true
                text: root.title
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: Appearance.font.family.title
                font.variableAxes: ({ "wght": 760, "wdth": 100, "ROND": 100 })
                font.pixelSize: root.compact ? Appearance.font.pixelSize.huge : Appearance.font.pixelSize.huge + 8
                color: ClockStyle.colOnTertiaryContainer
            }
            StyledText {
                Layout.fillWidth: true
                Layout.maximumWidth: 640
                visible: root.text.length > 0
                text: root.text
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textNormal
                color: ClockStyle.colOnTertiaryContainer
                opacity: 0.86
            }
        }

        RowLayout {
            id: trailingRow
            spacing: ClockStyle.gapSmall
        }
    }
}
