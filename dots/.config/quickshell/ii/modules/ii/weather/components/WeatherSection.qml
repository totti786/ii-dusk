import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import ".."

/**
 * A titled pane, built the way the clock family builds its panes: a scalloped badge,
 * a title in the rounded title face, then the content. Pages are compositions of these.
 */
Rectangle {
    id: root

    property string title: ""
    property string subtitle: ""
    property string icon: ""
    property string actionLabel: ""
    property bool flat: false
    property int contentSpacing: WeatherStyle.gap
    property int padding: WeatherStyle.cardPadding
    /// Varied by icon so neighbouring sections do not wear the same badge.
    property var shape: WeatherStyle.shapeFor(root.icon)
    property alias headerExtras: extras.data
    default property alias contentData: body.data

    signal actionClicked()

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + root.padding * 2
    radius: WeatherStyle.radiusCard
    color: root.flat ? "transparent" : WeatherStyle.colPane

    Behavior on color {
        animation: WeatherStyle.motionFast.colorAnimation.createObject(this)
    }

    ColumnLayout {
        id: layout
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.padding
        }
        spacing: WeatherStyle.gap

        RowLayout {
            Layout.fillWidth: true
            spacing: WeatherStyle.gap
            visible: root.title.length > 0 || root.actionLabel.length > 0

            ClockBadge {
                visible: root.icon.length > 0
                size: 44
                text: root.icon
                shape: root.shape
                color: WeatherStyle.colPrimary
                colSymbol: WeatherStyle.colOnPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    visible: root.title.length > 0
                    text: root.title
                    font.family: WeatherStyle.fontTitle
                    font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                    font.pixelSize: WeatherStyle.textTitle
                    color: WeatherStyle.colOnBackground
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.subtitle.length > 0
                    text: root.subtitle
                    font.pixelSize: WeatherStyle.textSmall
                    color: WeatherStyle.colSubtext
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                id: extras
                spacing: WeatherStyle.gapSmall
            }

            ClockButton {
                visible: root.actionLabel.length > 0
                label: root.actionLabel
                symbol: "arrow_forward"
                variant: "text"
                onClicked: root.actionClicked()
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: root.contentSpacing
        }
    }
}
