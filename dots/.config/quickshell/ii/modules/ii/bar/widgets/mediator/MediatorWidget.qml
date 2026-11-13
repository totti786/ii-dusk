pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.mediator
import qs.services

// A small stateful bar pill for the native anime player. It stays out of the
// bar until there is either a saved episode, an active player, or a stream
// being opened, then rests as a circle and opens into a media-style capsule
// while the pointer is over it or its popup is open.
MouseArea {
    id: root

    property bool vertical: false
    readonly property bool hasState: MediatorService.displayHasState
    readonly property bool active: MediatorService.nativeActive
    readonly property bool shown: MediatorService.nativePillVisible
    readonly property bool popupOpen: popupLoader.item !== null
        && (popupLoader.item.opened || popupLoader.item.active)
    property bool pointerInside: false
    property bool pressHeld: false
    readonly property bool expanded: root.vertical || root.pointerInside || root.pressHeld || root.popupOpen
    // "Title · EP 3", "Title · S01E02", or just the title for a movie
    readonly property string pillLabel: {
        const st = MediatorService.displayState;
        const name = st.title || st.show_id;
        const number = String(st.episode_number ?? "").trim();
        if (String(st.show_id ?? "").startsWith("stremio:movie:") || st.movie === true)
            return name;
        if (st.local === true)
            return number === "" ? name : `${name} · ${number}`;
        return `${name} · ${/^S\d+E\d+$/i.test(number) ? number : "EP " + (number || "?")}`;
    }
    readonly property string episodeLabel: root.hasState
        ? root.pillLabel
        : (MediatorService.streamResolving ? "Opening…" : "Anime stream")
    readonly property color iconFill: root.active
        ? Appearance.colors.colPrimaryContainer
        : Appearance.colors.colSurfaceContainerHigh
    readonly property color iconText: root.active
        ? Appearance.colors.colOnPrimaryContainer
        : Appearance.colors.colOnSurface

    // Keep the exit frame alive until the fade has finished. The size itself
    // follows the shared bar-resize curve so neighbouring widgets move with it.
    property bool internalVisible: root.shown
    property bool motionReady: false
    property real motionOffset: 0
    readonly property real pillHeight: root.vertical
        ? Appearance.sizes.verticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8
    readonly property color pillColor: root.active
        ? (root.containsMouse && !BarInteraction.clickToShow
            ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer)
        : (root.containsMouse && !BarInteraction.clickToShow
            ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1)
    readonly property color actionHoverColor: root.active
        ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighest

    Layout.fillHeight: root.vertical
    // The inline capsule is deliberately hoverable even when popup interaction
    // is configured for click-to-show. StyledPopup still reads clickToShow for
    // its own opening rules; this only controls the small media-style expansion.
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    clip: true

    implicitWidth: root.shown
        ? (root.vertical ? Appearance.sizes.verticalBarWidth
            : (root.expanded ? horizontalCapsule.implicitWidth : root.pillHeight))
        : 0
    implicitHeight: root.shown
        ? (root.vertical ? Appearance.sizes.verticalBarWidth : root.pillHeight)
        : 0

    visible: root.internalVisible || root.opacity > 0.01
    opacity: root.shown ? 1 : 0
    transform: Translate {
        x: root.vertical ? root.motionOffset : 0
        y: root.vertical ? 0 : root.motionOffset
    }

    Behavior on implicitWidth {
        enabled: root.motionReady && !Appearance.reducedMotion
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }
    Behavior on implicitHeight {
        enabled: root.motionReady && !Appearance.reducedMotion
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }
    Behavior on opacity {
        enabled: root.motionReady && !Appearance.reducedMotion
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    // HoverHandler covers the child RippleButtons as well as the empty space
    // between them, so the capsule does not fold while the pointer crosses a
    // control during its expansion.
    HoverHandler {
        id: hoverHandler
        onHoveredChanged: root.pointerInside = hoverHandler.hovered
    }

    SequentialAnimation {
        id: entranceAnimation
        running: false
        PropertyAction { target: root; property: "internalVisible"; value: true }
        PropertyAction { target: root; property: "motionOffset"; value: root.vertical ? -8 : -6 }
        NumberAnimation {
            target: root
            property: "motionOffset"
            to: 0
            duration: Appearance.reducedMotion ? 0 : Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
    }

    SequentialAnimation {
        id: exitAnimation
        running: false
        NumberAnimation {
            target: root
            property: "motionOffset"
            to: root.vertical ? 8 : 6
            duration: Appearance.reducedMotion ? 0 : Appearance.animation.elementMoveExit.duration
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        ScriptAction {
            script: {
                root.internalVisible = false;
                root.motionOffset = 0;
                root.syncVisibility();
            }
        }
    }

    // Keep the wrapper's stored visibility in step with the live player. The
    // guard lets the same component remain usable in isolated QML checks.
    function syncVisibility(): void {
        if (typeof rootItem !== "undefined" && rootItem?.toggleVisible)
            rootItem.toggleVisible(root.shown);
    }

    Component.onCompleted: {
        root.syncVisibility();
        root.internalVisible = root.shown;
        root.motionOffset = 0;
        Qt.callLater(() => root.motionReady = true);
    }

    onShownChanged: {
        if (!root.motionReady) {
            root.internalVisible = root.shown;
            if (root.shown)
                root.syncVisibility();
            return;
        }
        if (root.shown) {
            exitAnimation.stop();
            root.syncVisibility();
            root.internalVisible = true;
            entranceAnimation.restart();
        } else {
            entranceAnimation.stop();
            exitAnimation.restart();
        }
    }

    function togglePopup(): void {
        if (popupLoader.item)
            popupLoader.item.toggleFromPress();
    }

    // Empty space around the actions still opens the popup. The child
    // RippleButtons consume their own clicks first.
    onClicked: root.togglePopup()

    Rectangle {
        id: horizontalSurface
        visible: !root.vertical && root.internalVisible
        anchors.fill: parent
        radius: Appearance.rounding.full
        color: root.pillColor
        z: -1

        Behavior on color {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    RowLayout {
        id: horizontalCapsule
        visible: !root.vertical && root.internalVisible
        enabled: root.expanded
        anchors.fill: parent
        spacing: 4
        implicitHeight: root.pillHeight
        opacity: root.expanded ? 1 : 0

        Behavior on opacity {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        // The main action is a real shell button, so the capsule has the same
        // hover/press/ripple feedback as the other bar pills.
        RippleButton {
            id: capsuleAction
            animationsEnabled: !Appearance.reducedMotion
            Layout.preferredHeight: root.pillHeight
            implicitWidth: Math.min(190, capsuleTitle.implicitWidth + 52)
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: root.actionHoverColor
            colRipple: root.active ? Appearance.colors.colPrimary : Appearance.colors.colLayer1Active
            onClicked: root.togglePopup()

            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 5
                anchors.rightMargin: 9
                spacing: 7

                MaterialShapeWrappedMaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: MediatorService.streamResolving ? "hourglass_top"
                        : (root.active ? "play_circle" : "movie")
                    iconSize: 16
                    padding: 6
                    shape: root.active ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                    color: root.iconFill
                    colSymbol: root.iconText

                    Behavior on color {
                        enabled: !Appearance.reducedMotion
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                StyledText {
                    id: capsuleTitle
                    Layout.fillWidth: true
                    Layout.maximumWidth: 140
                    text: root.episodeLabel
                    color: root.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight

                    Behavior on color {
                        enabled: !Appearance.reducedMotion
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }
        }

        RippleButton {
            id: playArea
            animationsEnabled: !Appearance.reducedMotion
            visible: root.hasState
            Layout.preferredWidth: root.pillHeight
            Layout.preferredHeight: root.pillHeight
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSurfaceContainerHigh
            colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
            colRipple: Appearance.colors.colPrimary
            enabled: !MediatorService.streamResolving
            onClicked: root.active
                ? MediatorService.nativeControl("toggle")
                : MediatorService.playRememberedNative()

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: MediatorService.streamResolving ? "hourglass_top"
                    : (root.active && !MediatorService.nativePaused ? "pause" : "play_arrow")
                iconSize: 16
                color: Appearance.colors.colOnSurface
            }
        }
    }

    // The resting state is a true circle: the BarComponent wrapper is
    // paddingless for this widget, so its diameter is exactly pillHeight. The
    // capsule row fades over it as the width grows instead of leaving a second
    // background or an oval caused by hidden text padding.
    RippleButton {
        id: collapsedAction
        visible: !root.vertical && root.internalVisible
        // Keep the button enabled for the full press/release gesture. The
        // press itself expands the capsule, so `enabled: !expanded` would
        // cancel the release before Button can emit clicked.
        enabled: !root.expanded || root.pressHeld
        anchors.fill: parent
        opacity: root.expanded ? 0 : 1
        animationsEnabled: !Appearance.reducedMotion
        buttonRadius: Appearance.rounding.full
        colBackground: "transparent"
        colBackgroundHover: root.actionHoverColor
        colRipple: root.active ? Appearance.colors.colPrimary : Appearance.colors.colLayer1Active
        pressedAction: () => root.pressHeld = true
        canceledAction: () => root.pressHeld = false
        onClicked: {
            root.togglePopup();
            root.pressHeld = false;
        }

        Behavior on opacity {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        contentItem: MaterialShapeWrappedMaterialSymbol {
            anchors.centerIn: parent
            text: MediatorService.streamResolving ? "hourglass_top"
                : (root.active ? "play_circle" : "movie")
            iconSize: 16
            padding: 6
            shape: root.active ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
            color: root.iconFill
            colSymbol: root.iconText
        }
    }

    ColumnLayout {
        id: verticalCapsule
        visible: root.vertical && root.internalVisible
        anchors.centerIn: parent

        RippleButton {
            animationsEnabled: !Appearance.reducedMotion
            Layout.preferredWidth: root.pillHeight
            Layout.preferredHeight: root.pillHeight
            buttonRadius: Appearance.rounding.full
            colBackground: root.pillColor
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colRipple: Appearance.colors.colPrimary
            onClicked: root.togglePopup()

            contentItem: MaterialShapeWrappedMaterialSymbol {
                anchors.centerIn: parent
                text: MediatorService.streamResolving ? "hourglass_top"
                    : (root.active ? "play_circle" : "movie")
                iconSize: 16
                padding: 6
                shape: root.active ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                color: root.iconFill
                colSymbol: root.iconText
            }
        }
    }

    // The controller stays cheap and available for hover/click bars; the
    // actual StyledPopup window is still lazy.
    PopupLoader {
        id: popupLoader
        active: BarInteraction.enablePopups && (root.shown || root.internalVisible)
        sourceComponent: MediatorPopup {
            hoverTarget: root
            touchToggle: false
        }
    }
}
