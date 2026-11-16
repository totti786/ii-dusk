import QtQuick
import QtTest
import "../../../modules/ii/aiCompanion" as Companion

Item {
    id: scene
    width: 800; height: 600
    property point origin
    property point centre
    property bool dragging: false
    property int taps: 0
    Rectangle {
        id: moving
        x: 200; y: 200; width: 76; height: 76
        Companion.CompanionPointer {
            id: pointer
            anchors.fill: parent
            onActivated: scene.taps++
            onDragStarted: (p, c) => { scene.origin = p; scene.centre = c; scene.dragging = true; }
            onDragMoved: p => {
                moving.width = 76;
                moving.x = scene.centre.x + p.x-scene.origin.x - scene.mapToGlobal(0,0).x - 38;
                moving.y = scene.centre.y + p.y-scene.origin.y - scene.mapToGlobal(0,0).y - 38;
            }
            onDragFinished: scene.dragging = false
        }
    }
    TestCase {
        name: "CompanionPointer"
        when: windowShown
        function init() { moving.x=200; moving.y=200; moving.width=76; scene.dragging=false; scene.taps=0; }
        function test_moving_parent_does_not_feed_back_into_drag() {
            mousePress(scene, 238, 238);
            mouseMove(scene, 258, 258, 20);
            verify(scene.dragging);
            for (let i=1;i<=8;i++) {
                mouseMove(scene, 258+i*10, 258+i*5, 20);
                compare(Math.round(moving.x+38),258+i*10);
                compare(Math.round(moving.y+38),258+i*5);
            }
            mouseRelease(scene,338,298);
            verify(!scene.dragging);
            compare(scene.taps,0);
        }
        function test_resize_during_hold_keeps_press_offset() {
            mousePress(scene,220,220);
            moving.width=248;
            mouseMove(scene,240,250,20);
            verify(scene.dragging);
            compare(Math.round(moving.x),220);
            compare(Math.round(moving.y),230);
            mouseRelease(scene,240,250);
            compare(scene.taps,0);
        }
        function test_grab_from_the_edge_needs_no_precise_aim() {
            mousePress(scene,202,238);
            mouseMove(scene,210,238,20);
            verify(scene.dragging);
            compare(Math.round(moving.x),208);
            mouseRelease(scene,210,238);
            compare(scene.taps,0);
        }
        function test_click_remains_a_click() {
            mouseClick(scene,238,238);
            compare(scene.taps,1);
            verify(!scene.dragging);
        }
    }
}
