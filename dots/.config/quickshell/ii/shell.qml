//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
// Qt's compiled-QML cache, written to ~/.cache/quickshell/qmlcache. It only applies to types
// served as file: URLs, which the patched Quickshell (file-url-compile-cache.patch in
// ~/Projects/quickshell-fast) does; with a stock build it does nothing. Startup compiles
// ~2300 files otherwise, ~13 s of the QML loader thread.
//@ pragma Env QML_DISK_CACHE=qmlc-read,qmlc-write
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
// Qt allocates a depth-stencil renderbuffer per window (and per layer) for 2D opaque batching. The rendered
// output is identical without it; it only trades a little GPU time on heavy overdraw for ~20 MB per
// fullscreen window on HiDPI.
//@ pragma Env QSG_NO_DEPTH_BUFFER=1
// Qt sizes each window's texture atlas to the next power of two over the window, so every
// full-screen layer (background, desktop widgets, island, overview transition) got a
// 2048x2048 RGBA atlas (16 MB of VRAM) the moment it showed its first small image. The atlas
// only batches small images; 1024x1024 holds everything up to 512 px and costs 4 MB.
//@ pragma Env QSG_ATLAS_WIDTH=1024
//@ pragma Env QSG_ATLAS_HEIGHT=1024
//@ pragma Env MALLOC_CONF=dirty_decay_ms:1000,muzzy_decay_ms:1000,background_thread:true
// FFmpeg's hardware decoders on NVIDIA create a CUDA context on the first sound of a session
// (~40 MB that is never released). The shell only plays short sounds and two optional videos
// (lock screen wallpaper, video editor preview), so software decoding is enough.
//@ pragma Env QT_FFMPEG_DECODING_HW_DEVICE_TYPES=
//@ pragma Env QT_FFMPEG_ENCODING_HW_DEVICE_TYPES=
// Qt falls back to the basic render loop on NVIDIA's Wayland EGL, which renders every window in
// turn on the GUI thread. When the GPU has clocked down after a while idle, the driver spin-waits
// there for 50-200 ms and every GUI-driven animation (the overview's opening zoom first) jumps.
// Threaded gives each window its own render thread and keeps the GUI thread's clock at 120 Hz.
//@ pragma Env QSG_RENDER_LOOP=threaded

// Remove two slashes below and adjust the value to change the UI scale
////@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import Quickshell
import "modules/common"
// The scanner needs these directories for the generated qs.* modules. Their
// types are resolved by URL when each startup stage is actually needed.
import "services"
import "panelFamilies"

ShellRoot {
    id: root
    property bool runtimeWanted: false

    Component.onCompleted: {
        if (Qt.application) {
            Qt.application.applicationName = "quickshell";
            Qt.application.organizationName = "Unknown Organization";
            Qt.application.organizationDomain = "unknown.organization";
        }
        console.info("[Startup] Loading wallpaper, bar and Dynamic Island first");
    }

    LazyLoader {
        source: Qt.resolvedUrl("CoreDesktop.qml")
        active: source !== ""
    }

    // A real painted frame releases this stage. The short event-loop break
    // lets Wayland present it before compiling optional panels and services.
    Timer {
        interval: 120
        running: StartupState.desktopReady
        onTriggered: root.runtimeWanted = true
    }
    LazyLoader {
        id: remaining
        source: root.runtimeWanted ? Qt.resolvedUrl("ShellRuntime.qml") : ""
        active: root.runtimeWanted && source !== ""
        onActiveChanged: {
            if (active) console.info("[Startup] Loading remaining panels and services");
        }
    }
}
