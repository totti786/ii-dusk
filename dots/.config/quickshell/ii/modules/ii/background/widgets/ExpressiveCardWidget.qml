import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/*
 * The base of the utility widgets that live on a card (To-Do, timers,
 * translator, phone, send, session, water): the lock behaviour every widget
 * repeats, the entry's options and size, and the card itself. Children go in
 * `content`, a box of the design size scaled by Widget Size, so they lay out
 * in design units.
 */
AbstractBackgroundWidget {
    id: root

    // A widget that lists supportedSizes gets its design box from the shape it is in
    property real designWidth: root.sizeable ? root.sizeClassDims.width : 240
    property real designHeight: root.sizeable ? root.sizeClassDims.height : 240
    property bool showCard: true
    // This card's look: the global style with the widget's own overrides on top
    // (Config.setWidgetStyle), resolved by WidgetColorScheme.
    readonly property var cardStyle: WidgetColorScheme.resolveStyle(root.widgetInstance ? root.widgetInstance.style : null)
    // The scheme this card draws with: its own, else the global one. The card's widget reads
    // its colours from here (root.cardScheme.textColorOnBg ...), never from WidgetColorScheme.
    readonly property var cardScheme: WidgetColorScheme.schemes[root.cardStyle.scheme] ?? WidgetColorScheme.schemes["default"]
    property color cardColor: {
        const c = root.cardScheme.cardBgColor;
        return Qt.rgba(c.r, c.g, c.b, c.a * root.cardStyle.alpha);
    }
    property real cardRadius: Appearance.rounding.large * root.cardStyle.radiusScale
    // A card that has more to say when it is wider keeps its face (the 1x1 layout) in the first
    // `faceWidth` units, laid out exactly as before, and puts the rest in `extras`, to its right.
    // 0 means there is no such split and the content takes the whole card.
    property real faceWidth: 0
    default property alias content: contentBox.data
    readonly property alias extraItem: extraBox
    readonly property alias contentItem: contentBox
    readonly property bool hasExtras: root.faceWidth > 0 && root.designWidth > root.faceWidth + 1

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === root.configEntryName)

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options?.background?.widgets?.[root.configEntryName] ?? ({})
    readonly property real contentScale: (root.options?.widgetSize ?? 100) / 100.0
    // Whether a press may do something: the Settings preview shows the widget
    // but never runs its actions (a preview of the session grid that powers off).
    readonly property bool actionsEnabled: !root.isPreview

    // Whichever of the card's two text colours reads better on `fill`: a
    // contrast for fills the scheme has no "on" colour for (the warning).
    function contentOn(fill) {
        const lum = c => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
        const a = root.cardScheme.textColorOnBg;
        const b = root.cardScheme.cardBgColor;
        return Math.abs(lum(a) - lum(fill)) >= Math.abs(lum(b) - lum(fill)) ? a : b;
    }

    // A left click that did not become a move, at a point in design units
    // (`contentItem` coordinates). Widgets act on it instead of covering the
    // card with a TapHandler or MouseArea, which would take the press and
    // leave the widget impossible to drag from there.
    signal cardTapped(point at)
    property bool _movedSincePress: false
    onIsDraggingChanged: {
        if (root.isDragging)
            root._movedSincePress = true;
        else
            Qt.callLater(() => root._movedSincePress = false);
    }
    onClicked: mouse => {
        // In Edit Mode a click selects the widget; it never runs its action.
        if (mouse.button !== Qt.LeftButton || root._movedSincePress || !root.actionsEnabled || root.editModeActive)
            return;
        root.cardTapped(contentBox.mapFromItem(root, mouse.x, mouse.y));
    }

    // A pill's corner that still respects sharp mode (rounding scale 0).
    function pill(height) {
        return Appearance.rounding.scale === 0 ? 0 : height / 2;
    }

    implicitWidth: root.designWidth * root.contentScale
    implicitHeight: root.designHeight * root.contentScale

    Item {
        anchors.centerIn: parent
        width: root.designWidth
        height: root.designHeight
        scale: root.contentScale

        StyledRectangularShadow {
            target: card
            visible: root.showCard && (Config.options.background.widgets.enableShadows ?? true)
        }

        Rectangle {
            id: card
            anchors.fill: parent
            visible: root.showCard
            radius: root.cardRadius
            color: root.cardColor
            // The glass rim: a light hairline, like light catching a pane. Kept at the shell's
            // glass-group value; any stronger reads as a border (see EditModeCard).
            border.width: root.cardStyle.border
            border.color: root.cardStyle.rim ? Qt.alpha(Appearance.m3colors.m3onSurface, 0.16) : Qt.alpha(root.cardScheme.outlineColor, 0.5)

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            // The sheen: light from above fading out over the top of the card
            Rectangle {
                anchors.fill: parent
                visible: root.cardStyle.sheen
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.alpha("white", 0.10) }
                    GradientStop { position: 0.45; color: Qt.alpha("white", 0.0) }
                }
            }
        }

        Item {
            id: contentBox
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.faceWidth > 0 ? Math.min(root.faceWidth, parent.width) : parent.width
        }

        Item {
            id: extraBox
            visible: root.hasExtras
            x: root.faceWidth
            width: parent.width - root.faceWidth
            height: parent.height
        }

        // A preview looks live but takes no input: nothing under it runs.
        MouseArea {
            anchors.fill: parent
            z: 100
            visible: root.isPreview
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
        }
    }
}
