pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A cinematic header for movies, shows and anime. There is no card: the backdrop is faded into
 * the page along its bottom edge, so the title page reads as one surface with the content under
 * it. `tall` is the title page (poster, back link); the shorter form is the billboard on top of
 * the Streaming page, with dots to move between featured titles and a ring when the keyboard is on it.
 * Text sits on a dark scrim and is always white.
 */
Item {
    id: root

    property string name: ""
    property string poster: ""
    property string background: ""
    property string logo: ""
    property string description: ""
    /// Facts in reading order (year, runtime, genres...); empty ones are skipped
    property var facts: []
    property string rating: ""
    property bool tall: false
    /// The keyboard cursor is on this header
    property bool focused: false
    property int dots: 0
    property int dotIndex: 0
    readonly property bool hovered: hover.hovered
    default property alias actions: actionRow.data
    /// The buttons placed in the action row
    readonly property var actionItems: actionRow.children
    /// A button the keyboard is on: it gets a ring
    property Item focusItem: null

    signal backRequested()
    signal dotRequested(int index)

    Layout.fillWidth: true
    Layout.preferredHeight: root.tall ? 440 : 280
    implicitHeight: root.tall ? 440 : 280

    // The pane is translucent over the window colour: paint the same composite, opaque
    readonly property bool dark: Appearance.m3colors.darkmode
    /// Text colour: white over the scrim in a dark theme, the theme's own ink in a light one
    readonly property color ink: root.dark ? "white" : Appearance.colors.colOnLayer0
    readonly property color scrim: root.dark ? "black" : Appearance.colors.colLayer1

    // The backdrop is masked twice, to fade out at the bottom and along the sides, so it melts
    // into whatever the page is: no card edge and no colour to match.
    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: root.width
                height: root.height
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.9) }
                    GradientStop { position: 0.14; color: "white" }
                    GradientStop { position: root.tall ? 0.55 : 0.6; color: "white" }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                }
            }
        }

        Item {
            anchors.fill: parent
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: root.width
                    height: root.height
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0) }
                        GradientStop { position: 0.07; color: "white" }
                        GradientStop { position: 0.93; color: "white" }
                        GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                    }
                }
            }

            Image {
                id: backdrop
                anchors.fill: parent
                source: MediatorService.cachedImage(root.background !== "" ? root.background : root.poster)
                fillMode: Image.PreserveAspectCrop
                horizontalAlignment: Image.AlignHCenter
                verticalAlignment: Image.AlignTop
                asynchronous: true
                sourceSize.width: 1400
                opacity: status === Image.Ready ? (root.background !== "" ? 1 : 0.4) : 0
                Behavior on opacity {
                    NumberAnimation { duration: Appearance.dur(420); easing.type: Easing.OutCubic }
                }
            }
            // Behind the text
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.alpha(root.scrim, 0.78) }
                    GradientStop { position: 0.45; color: Qt.alpha(root.scrim, 0.5) }
                    GradientStop { position: 1; color: Qt.alpha(root.scrim, 0.05) }
                }
            }
        }
    }

    // Keyboard ring around the billboard
    Rectangle {
        anchors.fill: parent
        visible: root.focused
        radius: Appearance.rounding.verylarge
        color: "transparent"
        border.width: 3
        border.color: Appearance.colors.colPrimary
    }

    Rectangle {
        parent: root.focusItem
        visible: root.focusItem !== null
        anchors { fill: parent; margins: -4 }
        radius: height / 2
        color: "transparent"
        border.width: 3
        border.color: Appearance.colors.colPrimary
    }

    // Back: a quiet link rather than a button floating on the art
    Rectangle {
        visible: root.tall
        anchors { top: parent.top; left: parent.left; topMargin: 14; leftMargin: 18 }
        implicitWidth: backRow.implicitWidth + 22
        implicitHeight: 32
        radius: Appearance.rounding.full
        color: backArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer1
        Row {
            id: backRow
            anchors.centerIn: parent
            spacing: 6
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: "chevron_left"
                iconSize: 18
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Back"
                color: Appearance.colors.colOnLayer0
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
        MouseArea {
            id: backArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.backRequested()
        }
    }

    RowLayout {
        anchors {
            fill: parent
            leftMargin: 34; rightMargin: 34
            topMargin: root.tall ? 56 : 24
            bottomMargin: root.dots > 1 ? 44 : root.tall ? 56 : 30
        }
        spacing: 30

        RoundedBox {
            visible: root.tall
            Layout.alignment: Qt.AlignBottom
            Layout.preferredHeight: Math.min(root.height - 130, 300)
            Layout.preferredWidth: Layout.preferredHeight / 1.5
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer2
            Image {
                anchors.fill: parent
                source: MediatorService.cachedImage(root.poster)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 460
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignBottom
            Layout.maximumWidth: 680
            spacing: 10

            // Logo art when the title has one and it loads; the name otherwise
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: logoImage.status === Image.Ready ? (root.tall ? 84 : 60) : titleText.implicitHeight
                Image {
                    id: logoImage
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: Math.min(parent.width, 440)
                    source: root.logo ? MediatorService.cachedImage(root.logo) : ""
                    fillMode: Image.PreserveAspectFit
                    horizontalAlignment: Image.AlignLeft
                    asynchronous: true
                    sourceSize.height: 170
                    visible: status === Image.Ready
                }
                StyledText {
                    id: titleText
                    visible: logoImage.status !== Image.Ready
                    width: parent.width
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    text: root.name
                    color: root.ink
                    font.pixelSize: root.tall ? 38 : 32
                    font.weight: Font.Bold
                }
            }

            // Facts: rating first, then the rest separated by quiet dots
            Flow {
                Layout.fillWidth: true
                spacing: 8

                Row {
                    visible: root.rating !== ""
                    spacing: 4
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "star"
                        fill: 1
                        iconSize: 17
                        color: "#ffd166"
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.rating
                        color: root.ink
                        font.weight: Font.DemiBold
                    }
                }
                Repeater {
                    model: root.facts.filter(x => x)
                    delegate: Row {
                        id: fact
                        required property string modelData
                        required property int index
                        spacing: 8
                        StyledText {
                            visible: fact.index > 0 || root.rating !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: "·"
                            color: Qt.alpha(root.ink, 0.5)
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: fact.modelData
                            color: Qt.alpha(root.ink, 0.85)
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: root.tall ? 4 : 2
                text: root.description
                color: Qt.alpha(root.ink, 0.78)
                font.pixelSize: Appearance.font.pixelSize.small
                lineHeight: 1.15
            }

            Flow {
                id: actionRow
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8
            }
        }
    }

    // Which featured title this is
    Row {
        visible: root.dots > 1
        anchors { left: parent.left; leftMargin: 34; bottom: parent.bottom; bottomMargin: 18 }
        spacing: 6
        Repeater {
            model: root.dots
            delegate: Rectangle {
                id: dot
                required property int index
                readonly property bool on: root.dotIndex === index
                width: on ? 22 : 8
                height: 8
                radius: 4
                color: on ? root.ink : Qt.alpha(root.ink, 0.4)
                Behavior on width {
                    NumberAnimation { duration: Appearance.dur(200); easing.type: Easing.OutCubic }
                }
                MouseArea {
                    anchors { fill: parent; margins: -5 }
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dotRequested(dot.index)
                }
            }
        }
    }

    HoverHandler {
        id: hover
    }
}
