import QtQuick
import QtQuick.Controls
import QtTest
import "../../../modules/ii/aiCompanion" as Companion

Item {
    id: scene
    width: 640; height: 480
    property int clicks: 0
    property int orbTaps: 0
    Companion.CompanionSurface {
        id: surface
        x: 100; y: 100
        interactionHeld: action.down
        Companion.CompanionPointer {
            anchors.centerIn: parent
            width: 88; height: 88
            onActivated: scene.orbTaps++
        }
        Button {
            id: action
            x: 110; y: 157; width: 44; height: 44
            enabled: surface.controlsOpen
            hoverEnabled: true
            onClicked: scene.clicks++
        }
    }
    TestCase {
        name: "CompanionSurface"
        when: windowShown
        function init() { mouseMove(scene,20,20); wait(350); scene.clicks=0; scene.orbTaps=0; }
        function reveal() { mouseMove(scene,204,204); tryCompare(surface,"controlsOpen",true); }
        function test_orbit_button_stays_clickable_after_hover_grace() {
            reveal();
            mouseMove(scene,232,279);
            wait(450);
            verify(surface.controlsOpen);
            mouseClick(scene,232,279);
            compare(scene.clicks,1);
            compare(scene.orbTaps,0);
        }
        function test_held_button_is_not_cancelled_by_close_timer() {
            reveal();
            mouseMove(scene,232,279);
            mousePress(scene,232,279);
            verify(action.down);
            mouseMove(scene,400,400);
            wait(450);
            verify(surface.controlsOpen);
            mouseMove(scene,232,279);
            mouseRelease(scene,232,279);
            compare(scene.clicks,1);
        }
        function test_leaving_the_whole_menu_closes_it() {
            reveal();
            mouseMove(scene,400,400);
            tryCompare(surface,"controlsOpen",false,1000);
        }
    }
}
