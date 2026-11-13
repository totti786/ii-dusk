import QtQuick
import qs.modules.common
import qs.modules.common.functions

/**
 * The shell's wheel feel for a plain ListView, GridView or Flickable. Mouse
 * notches use the configured step and glide there; touchpad events follow the
 * finger through ScrollWheel.touchpadStep and use the shared short lift glide.
 * Declare it inside the view: `ListView { WheelScroll {} ... }`.
 *
 * The view's direction selects one axis. This matters for horizontal rows:
 * vertical finger movement must remain available to an enclosing scroller.
 */
WheelHandler {
    id: root

    // A handler declared inside a ListView is parented to its contentItem;
    // walk up to the owning Flickable instead of assuming a direct parent.
    function findView(item) {
        for (let candidate = item; candidate; candidate = candidate.parent) {
            if (candidate.contentY !== undefined && candidate.contentHeight !== undefined
                    && candidate.interactive !== undefined)
                return candidate;
        }
        return null;
    }

    readonly property Flickable view: root.findView(root.parent)
    readonly property bool horizontal: root.view !== null
        && root.view.flickableDirection === Flickable.HorizontalFlick
    readonly property string scrollProperty: root.horizontal ? "contentX" : "contentY"
    readonly property real position: root.view === null ? 0
        : (root.horizontal ? root.view.contentX : root.view.contentY)
    readonly property real minPosition: root.view === null ? 0
        : (root.horizontal ? root.view.originX - root.view.leftMargin : root.view.originY - root.view.topMargin)
    readonly property real maxPosition: root.view === null ? 0
        : (root.horizontal
            ? Math.max(root.minPosition, root.view.originX + root.view.contentWidth - root.view.width + root.view.rightMargin)
            : Math.max(root.minPosition, root.view.originY + root.view.contentHeight - root.view.height + root.view.bottomMargin))
    readonly property bool canScroll: root.view !== null && root.view.interactive
        && root.view.visible && root.view.enabled
        && root.maxPosition - root.minPosition > 1

    // The names ScrollWheel reads its settings from. Keep these as properties
    // so the controls update live while the shell is running.
    readonly property bool fasterTouchpadScroll: Config.options?.interactions?.scrolling?.fasterTouchpadScroll ?? false
    readonly property real touchpadScrollFactor: Config.options?.interactions?.scrolling?.touchpadScrollFactor ?? 450
    readonly property real mouseScrollFactor: Config.options?.interactions?.scrolling?.mouseScrollFactor ?? 120
    readonly property real mouseScrollDeltaThreshold: Config.options?.interactions?.scrolling?.mouseScrollDeltaThreshold ?? 120

    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    orientation: root.horizontal ? Qt.Horizontal : Qt.Vertical
    // Only the owning Flickable moves; WheelHandler must not apply its own
    // default target movement in parallel with the shared handlers below.
    target: null
    enabled: root.canScroll

    // TouchpadKinetic follows the selected axis. Its vertical default keeps
    // StyledFlickable and StyledListView behaviour unchanged.
    property TouchpadKinetic kinetic: TouchpadKinetic {
        flickable: root.view
        horizontal: root.horizontal
    }

    function axisDelta(event) {
        return root.horizontal ? event.angleDelta.x : event.angleDelta.y;
    }

    function axisPixelDelta(event) {
        return root.horizontal ? event.pixelDelta.x : event.pixelDelta.y;
    }

    function clamp(value) {
        return Math.max(root.minPosition, Math.min(root.maxPosition, value));
    }

    function stopMotion() {
        root.kinetic.stop();
        glide.stop();
    }

    /**
     * Shared handler body. Keeping this as a function gives the headless QML
     * tests the same path as WheelHandler's real onWheel delivery.
     */
    function handleWheel(angle, pixel, phase) {
        const hasDelta = angle !== 0 || pixel !== 0;

        // Qt sends ScrollEnd without a delta. It belongs to the axis that has
        // an active touch; an unrelated zero-delta event must pass through.
        if (!hasDelta) {
            const wasActive = root.kinetic.active;
            root.kinetic.feed(0, phase);
            return phase === Qt.ScrollEnd && wasActive;
        }

        // Do not turn a vertical gesture into horizontal motion (or vice versa).
        if (angle === 0 && pixel === 0)
            return false;

        if (!ScrollWheel.isNotch(angle, root, phase)) {
            // A touchpad phase can report angleDelta on the other axis while
            // this handler is selected for one axis. Let an enclosing Flickable
            // receive that orthogonal gesture.
            const step = ScrollWheel.touchpadStep(angle, pixel, root);
            if (step === 0)
                return false;
            glide.stop();
            root.kinetic.feed(step, phase);
            return true;
        }

        root.kinetic.stop();
        const step = ScrollWheel.notchStep(angle, root);
        const from = glide.running ? glide.to : root.position;
        glide.stop();
        glide.from = root.position;
        glide.to = root.clamp(from - step);
        glide.start();
        return true;
    }

    onWheel: event => {
        event.accepted = root.handleWheel(root.axisDelta(event), root.axisPixelDelta(event), event.phase);
    }

    // WheelHandler takes no child objects, so the glide hangs off a property.
    readonly property NumberAnimation glideAnimation: NumberAnimation {
        id: glide
        target: root.view
        property: root.scrollProperty
        duration: Appearance.animation.scroll.duration
        easing.type: Appearance.animation.scroll.type
        easing.bezierCurve: Appearance.animation.scroll.bezierCurve
    }

    onEnabledChanged: {
        if (!enabled)
            root.stopMotion();
    }

    property Connections viewLifecycle: Connections {
        target: root.view
        ignoreUnknownSignals: true
        function onMovementStarted() {
            root.stopMotion();
        }
        function onVisibleChanged() {
            if (!root.view.visible)
                root.stopMotion();
        }
        function onEnabledChanged() {
            if (!root.view.enabled)
                root.stopMotion();
        }
    }

    Component.onDestruction: {
        root.stopMotion();
    }
}
