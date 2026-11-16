import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A feature as a tile, the way the clock shows an alarm: the tile takes the primary
 * container while the feature is on and the pane colour while it is off, its switch
 * and actions follow that family, and the icon's shape morphs with the state.
 * `default` content goes in the footer, left of the optional "Configure" action.
 */
Rectangle {
    id: root

    property string symbol: ""
    property var shapeOn: MaterialShape.Shape.Cookie9Sided
    property var shapeOff: MaterialShape.Shape.Circle
    property string title: ""
    property string summary: ""
    property bool checked: false
    property bool configurable: false
    /// Many footer chips: the Configure action shrinks to its icon and the gaps tighten.
    property bool compactFooter: false
    property bool selectable: true
    property string warningBadge: ""
    property string warningTooltip: ""
    property string warningIcon: "warning"
    property color warningColor: Appearance.colors.colError
    default property alias footer: footerRow.data

    signal toggled(bool value)
    signal configureRequested()

    readonly property bool engaged: tileHover.hovered
    readonly property color colContent: (root.checked && root.selectable) ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1

    radius: Appearance.rounding.verylarge
    opacity: root.selectable ? 1.0 : 0.65
    Behavior on opacity {
        NumberAnimation { duration: 150 }
    }
    color: (root.checked && root.selectable)
        ? (root.engaged ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer)
        : (root.engaged ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1)
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: tileHover
    }
    // Under the content, so the switch and the buttons keep their own clicks.
    MouseArea {
        anchors.fill: parent
        cursorShape: (root.configurable || root.selectable) ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.configurable)
                root.configureRequested();
            else if (root.selectable)
                root.toggled(!root.checked);
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: 20
            topMargin: 18
            rightMargin: 18
        }
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialShapeWrappedMaterialSymbol {
                text: root.symbol
                iconSize: 22
                padding: 11
                fill: (root.checked && root.selectable) ? 1 : 0
                shape: (root.checked && root.selectable) ? root.shapeOn : root.shapeOff
                color: (root.checked && root.selectable) ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                colSymbol: (root.checked && root.selectable) ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Rectangle {
                visible: root.warningBadge !== ""
                Layout.alignment: Qt.AlignVCenter
                radius: Appearance.rounding.full
                color: ColorUtils.applyAlpha(root.warningColor, 0.14)
                border.color: ColorUtils.applyAlpha(root.warningColor, 0.35)
                border.width: 1
                implicitHeight: 24
                implicitWidth: warningRow.implicitWidth + 14
                clip: true

                RowLayout {
                    id: warningRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        text: root.warningIcon || "warning"
                        iconSize: 13
                        color: root.warningColor
                    }

                    StyledText {
                        text: root.warningBadge
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: root.warningColor
                        elide: Text.ElideRight
                    }
                }

                StyledToolTip {
                    text: root.warningTooltip !== "" ? root.warningTooltip : root.warningBadge
                }
            }

            StyledSwitch {
                Layout.alignment: Qt.AlignVCenter
                sizeScale: 0.85
                checked: root.checked && root.selectable
                enabled: root.selectable
                opacity: root.selectable ? 1.0 : 0.4
                activeColor: Appearance.colors.colPrimary
                activeThumbColor: Appearance.colors.colOnPrimary
                inactiveColor: Appearance.colors.colSurfaceContainerHighest
                onToggled: {
                    if (root.selectable)
                        root.toggled(checked)
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 14
            text: root.title
            font.family: Appearance.font.family.title
            font.variableAxes: Appearance.font.variableAxes.titleRounded
            font.pixelSize: Appearance.font.pixelSize.larger
            color: root.colContent
            elide: Text.ElideRight
        }

        StyledText {
            id: summaryText
            Layout.fillWidth: true
            Layout.topMargin: 2
            // Two lines are always reserved so tiles in a row keep their footers level.
            Layout.preferredHeight: summaryMetrics.height * 2
            text: root.summary
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.colContent
            opacity: 0.8
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop

            FontMetrics {
                id: summaryMetrics
                font: summaryText.font
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 12
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: root.compactFooter ? 4 : 8

            RowLayout {
                id: footerRow
                Layout.fillWidth: true
                spacing: root.compactFooter ? 4 : 8
            }

            // Built only for a tile that has a sub-page; most do not.
            Loader {
                active: root.configurable
                visible: active
                Layout.alignment: Qt.AlignRight
                sourceComponent: RippleButton {
                    implicitHeight: 36
                    implicitWidth: configureLabel.visible ? configureRow.implicitWidth + 28 : implicitHeight
                    buttonRadius: height / 2
                    buttonRadiusPressed: Appearance.rounding.small
                    colBackground: ColorUtils.applyAlpha(root.colContent, 0.1)
                    colBackgroundHover: ColorUtils.applyAlpha(root.colContent, 0.18)
                    colBackgroundActive: ColorUtils.applyAlpha(root.colContent, 0.26)
                    colRipple: ColorUtils.applyAlpha(root.colContent, 0.26)
                    onClicked: root.configureRequested()

                    contentItem: Item {
                        RowLayout {
                            id: configureRow
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: "tune"
                                iconSize: Appearance.font.pixelSize.normal
                                color: root.colContent
                            }
                            StyledText {
                                id: configureLabel
                                // Beside footer chips a narrow tile keeps only the icon.
                                visible: footerRow.children.length === 0 || root.width >= 400
                                text: Translation.tr("Configure")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: root.colContent
                            }
                        }
                    }
                }
            }
        }
    }
}
