import QtQuick
import QtTest
import "../../../modules/ii/dynamicIsland/styles/notch" as Notch

Rectangle {
    id: scene
    width: 300; height: 100; color: "black"
    Notch.NotchShape {
        id: island
        x: 20; y: 10; width: 240; height: 50
        surfaceHeight: 40
        topRadius: 20; bottomRadius: 20
        color: "white"
    }
    TestCase {
        name: "IslandDockingEdge"
        when: windowShown
        function init() { island.bottomWaveAmplitude=0; island.sculpted=false; island.attached=false; }
        function test_flat_edge_returns_after_ripple() {
            wait(50);
            const flat=grabImage(scene);
            island.bottomWaveAmplitude=7;
            island.bottomWavePhase=Math.PI/2;
            wait(50);
            const wave=grabImage(scene);
            verify(!flat.equals(wave), "Docking deforms the rendered silhouette");
            island.bottomWaveAmplitude=0;
            wait(50);
            verify(flat.equals(grabImage(scene)), "Release restores the exact original silhouette");
        }
        function test_wave_renders_outward_below_the_logical_body() {
            island.bottomWaveAmplitude=7;
            island.bottomWavePhase=Math.PI/2;
            wait(50);
            const image=grabImage(scene);
            let drawnBelow=0;
            for(let x=60;x<220;x++) {
                for(let y=51;y<57;y++) {
                    if(image.red(x,y)>.5) drawnBelow++;
                }
            }
            verify(drawnBelow>20, "Outward scallops have room below the original body");
        }
        function test_sculpted_edge_responds_too() {
            island.sculpted=true; island.attached=true;
            island.shoulder=12; island.foot=18;
            wait(50);
            const flat=grabImage(scene);
            island.bottomWaveAmplitude=7;
            wait(50);
            verify(!flat.equals(grabImage(scene)));
        }
    }
}
