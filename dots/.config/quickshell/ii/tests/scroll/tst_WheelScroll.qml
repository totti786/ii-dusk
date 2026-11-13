import QtQuick
import QtTest
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: scene
    width: 640
    height: 420

    ListView {
        id: vertical
        width: 260
        height: 320
        model: 80
        delegate: Item { width: 260; height: 40 }
        WheelScroll { id: verticalWheel }
    }

    ListView {
        id: horizontal
        x: 300
        width: 320
        height: 120
        orientation: ListView.Horizontal
        model: 40
        delegate: Item { width: 90; height: 120 }
        WheelScroll { id: horizontalWheel }
    }

    TestCase {
        name: "WheelScroll"
        when: windowShown

        function init() {
            Config.options.appearance.settingsPerformanceMode = true;
            Config.options.interactions.scrolling.fasterTouchpadScroll = false;
            Config.options.interactions.scrolling.touchpadScrollFactor = 450;
            Config.options.interactions.scrolling.touchpadKinetic = false;
            Config.options.interactions.scrolling.mouseScrollFactor = 80;
            Config.options.interactions.scrolling.mouseScrollDeltaThreshold = 120;
            Appearance.animation.scroll.duration = 10;
            vertical.contentY = 500;
            horizontal.contentX = 200;
            wait(30);
        }

        function waitForTouchpad(handler, angle, pixel) {
            verify(handler.handleWheel(angle, pixel, Qt.ScrollUpdate));
            wait(200);
        }

        function test_01_touchpad_off_is_one_to_one_vertical() {
            const before = vertical.contentY;
            waitForTouchpad(verticalWheel, 0, -16);
            compare(Math.round(vertical.contentY - before), 16);
        }

        function test_02_touchpad_factor_scales_vertical_live() {
            Config.options.interactions.scrolling.fasterTouchpadScroll = true;
            Config.options.interactions.scrolling.touchpadScrollFactor = 50;
            let before = vertical.contentY;
            waitForTouchpad(verticalWheel, 0, -10);
            verify(Math.abs(vertical.contentY - before - 50) < 2);

            Config.options.interactions.scrolling.touchpadScrollFactor = 450;
            before = vertical.contentY;
            waitForTouchpad(verticalWheel, 0, -10);
            verify(Math.abs(vertical.contentY - before - 450) < 2);
        }

        function test_03_scroll_end_without_delta_releases_touchpad() {
            Config.options.interactions.scrolling.fasterTouchpadScroll = true;
            Config.options.interactions.scrolling.touchpadScrollFactor = 50;
            verify(verticalWheel.handleWheel(0, -10, Qt.ScrollUpdate));
            verify(verticalWheel.kinetic.active);
            verify(verticalWheel.handleWheel(0, 0, Qt.ScrollEnd));
            wait(200);
        }

        function test_04_mouse_factor_and_stacking_are_unchanged() {
            const before = vertical.contentY;
            verify(verticalWheel.handleWheel(120, 0, Qt.NoScrollPhase));
            verify(verticalWheel.handleWheel(120, 0, Qt.NoScrollPhase));
            wait(40);
            // Two 80 px notches are accumulated and clamped by the view.
            compare(Math.round(before - vertical.contentY), 160);
        }

        function test_05_vertical_touchpad_clamps_at_bounds() {
            vertical.contentY = 0;
            wait(20);
            waitForTouchpad(verticalWheel, 0, 99999);
            compare(Math.round(vertical.contentY), 0);
        }

        function test_06_horizontal_touchpad_uses_x_and_factor() {
            verify(horizontalWheel.horizontal);
            Config.options.interactions.scrolling.fasterTouchpadScroll = true;
            Config.options.interactions.scrolling.touchpadScrollFactor = 50;
            const before = horizontal.contentX;
            waitForTouchpad(horizontalWheel, 0, -10);
            verify(Math.abs(horizontal.contentX - before - 50) < 2);
        }

        function test_07_horizontal_orthogonal_event_is_not_accepted() {
            const before = horizontal.contentX;
            // WheelScroll receives only its selected axis. A zero selected
            // axis represents a vertical gesture on the horizontal row.
            compare(horizontalWheel.handleWheel(0, 0, Qt.ScrollUpdate), false);
            wait(40);
            compare(Math.round(horizontal.contentX), Math.round(before));
        }

        function test_08_hidden_view_stops_touchpad_motion() {
            Config.options.interactions.scrolling.fasterTouchpadScroll = true;
            Config.options.interactions.scrolling.touchpadScrollFactor = 450;
            verify(verticalWheel.handleWheel(0, -10, Qt.ScrollUpdate));
            verify(verticalWheel.kinetic.active);
            vertical.visible = false;
            wait(20);
            verify(!verticalWheel.kinetic.active);
            vertical.visible = true;
        }
    }
}
