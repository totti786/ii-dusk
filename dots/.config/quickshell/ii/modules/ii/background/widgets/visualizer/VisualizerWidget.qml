import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: widgetInstance ? (widgetInstance.widgetId || "visualizer") : "visualizer"
    property bool wallpaperSafetyTriggered: false

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom" || root.lockBehavior === "center" || root.lockBehavior === "lockOnly"
    opacity: {
        if (root.lockBehavior === "lockOnly") return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked) return 0;
        return 1;
    }

    readonly property var widgetOpts: {
        const wid = widgetInstance ? (widgetInstance.widgetId || root.configEntryName) : root.configEntryName;
        return (Config.options.background.widgets && Config.options.background.widgets[wid]) || (Config.options.background.widgets && Config.options.background.widgets.visualizer) || ({});
    }

    // Determine style based on widget variant or settings
    readonly property string defaultStyleForWidget: {
        const wid = widgetInstance ? (widgetInstance.widgetId || root.configEntryName) : root.configEntryName;
        if (wid === "visualizer_ring") return "ring";
        if (wid === "visualizer_aurora") return "aurora";
        if (wid === "visualizer_mirror") return "mirror";
        if (wid === "visualizer_dots") return "dots";
        if (wid === "visualizer_bars") return "bars";
        return "bars";
    }

    readonly property string style: widgetOpts.style ?? defaultStyleForWidget
    readonly property bool shaderStyle: ["aurora", "ring", "dots", "mirror"].includes(style)
    readonly property bool isRing: style === "ring"
    readonly property bool useCoverColors: shaderStyle && ((widgetOpts.colorSource ?? "theme") === "cover")

    readonly property real ringSize: widgetOpts.ringSize ?? 380
    readonly property real bandHeight: widgetOpts.height ?? 260
    readonly property real barsHeight: 240

    implicitWidth: isRing ? ringSize : screenWidth
    implicitHeight: isRing ? ringSize : (shaderStyle ? bandHeight : barsHeight)

    // Palettes: color1 and color2 carry the shape, color3 the accent (peaks, fallback cover)
    readonly property var themePalette: {
        const c = Appearance.m3colors;
        switch (root.style) {
            case "aurora": return [c.m3primary, c.m3tertiary, c.m3secondary];
            case "ring": return [c.m3primary, c.m3tertiary, c.m3primaryContainer];
            case "dots": return [c.m3onBackground, c.m3primary, c.m3error];
            default: return [c.m3primary, c.m3primaryContainer, c.m3tertiary];
        }
    }

    readonly property var coverPalette: {
        if (!coverQuantizer || !coverQuantizer.colors || coverQuantizer.colors.length < 3) return null;
        try {
            let list = [];
            for (let i = 0; i < coverQuantizer.colors.length; i++) {
                list.push(coverQuantizer.colors[i]);
            }
            list.sort((a, b) => (b.hslSaturation ?? 0) - (a.hslSaturation ?? 0));
            if (list.length < 3) return null;
            const lifted = list.map(c => Qt.hsla(Math.max(c.hslHue, 0), Math.max(c.hslSaturation, 0.45), Math.min(Math.max(c.hslLightness, 0.62), 0.85), 1));
            return root.style === "dots" ? [root.themePalette[0], lifted[0], lifted[1]] : lifted.slice(0, 3);
        } catch (e) {
            return null;
        }
    }

    readonly property var visualizerColors: (root.useCoverColors && root.coverPalette) ? root.coverPalette : root.themePalette

    // Cover art of the current track
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string artUrl: activePlayer ? (activePlayer.trackArtUrl || "") : ""
    readonly property bool needsCover: isRing || useCoverColors
    readonly property string coverUrl: root.needsCover ? CoverArt.source(root.artUrl) : ""

    ColorQuantizer {
        id: coverQuantizer
        source: root.useCoverColors ? root.coverUrl : ""
        depth: 2
        rescaleSize: 64
    }

    VisualizerEngine {
        id: levelEngine
        active: root.shaderStyle && root.live && CavaService.active
        sensitivity: root.widgetOpts.sensitivity ?? 1
    }

    Loader {
        anchors.fill: parent
        active: root.style === "bars"
        sourceComponent: BarsVisualizer {}
    }

    Loader {
        anchors.fill: parent
        active: root.shaderStyle
        sourceComponent: Item {
            // Ring: the cover is rendered into a texture so the shader gets it already cropped
            Item {
                id: coverItem
                width: 512
                height: 512
                visible: root.isRing
                Image {
                    id: coverImage
                    anchors.fill: parent
                    source: root.isRing ? root.coverUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(512, 512)
                    asynchronous: true
                    smooth: true
                }
            }
            ShaderEffectSource {
                id: coverTexture
                sourceItem: coverItem
                hideSource: true
                visible: false
            }

            VisualizerShader {
                anchors.fill: parent
                style: root.style
                engine: levelEngine
                color1: root.visualizerColors[0]
                color2: root.visualizerColors[1]
                color3: root.visualizerColors[2]
                cover: coverTexture
                hasCover: (root.isRing && coverImage.status === Image.Ready) ? 1 : 0
            }
        }
    }

    // Classic visualizer: rounded Rectangles along screen width
    component BarsVisualizer: Item {
        id: bars

        readonly property var points: CavaService.visualizerPoints

        property real barWidth: 4
        property real barSpacing: 8
        property real maxBarHeight: Math.max(50, root.implicitHeight - 20)
        property real maxVisualizerValue: 1000
        property real smoothingDuration: 150

        readonly property int barCount: Math.max(1, Math.floor(root.width / (barWidth + barSpacing)))

        readonly property var smoothedPoints: {
            let raw = points;
            if (!raw || raw.length === 0) return Array(barCount).fill(0);
            let count = barCount;
            let mapped = new Array(count);
            let rawLenM1 = raw.length - 1;

            for (let i = 0; i < count; i++) {
                let progress = i / (count - 1 || 1);
                let relPos = progress * rawLenM1;
                let low = Math.floor(relPos);
                let high = Math.ceil(relPos);
                let mix = relPos - low;
                mapped[i] = (raw[low] * (1 - mix)) + (raw[high] * (high < raw.length ? mix : 0));
            }

            let smoothed = new Array(count);
            let sW = 0.2;
            for (let j = 0; j < count; j++) {
                let p = mapped[Math.max(0, j - 1)];
                let n = mapped[Math.min(count - 1, j + 1)];
                smoothed[j] = (p * sW) + (mapped[j] * (1.0 - 2 * sW)) + (n * sW);
            }
            return smoothed;
        }

        property real activityOpacity: 0
        Behavior on activityOpacity {
            NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
        }

        Timer {
            id: silenceTimer
            interval: 1000
            onTriggered: bars.activityOpacity = 0
        }

        onPointsChanged: {
            if (points.some(p => p > 0)) {
                bars.activityOpacity = 1.0;
                silenceTimer.restart();
            }
        }

        Row {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: bars.barSpacing
            opacity: bars.activityOpacity

            Behavior on opacity {
                NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
            }

            Repeater {
                model: bars.barCount
                Rectangle {
                    required property int index
                    width: bars.barWidth
                    property real pointValue: {
                        const v = bars.smoothedPoints[index] ?? 0;
                        return Math.max(bars.barWidth, (v / bars.maxVisualizerValue) * bars.maxBarHeight);
                    }
                    height: pointValue
                    topLeftRadius: bars.barWidth / 2
                    topRightRadius: bars.barWidth / 2
                    anchors.bottom: parent.bottom

                    property real intensity: pointValue / bars.maxBarHeight
                    color: Qt.rgba(
                        Appearance.colors.colPrimary.r * intensity + Appearance.colors.colPrimaryContainer.r * (1 - intensity),
                        Appearance.colors.colPrimary.g * intensity + Appearance.colors.colPrimaryContainer.g * (1 - intensity),
                        Appearance.colors.colPrimary.b * intensity + Appearance.colors.colPrimaryContainer.b * (1 - intensity),
                        1
                    )

                    Behavior on height {
                        NumberAnimation { duration: bars.smoothingDuration; easing.type: Easing.OutQuad }
                    }
                }
            }
        }
    }
}
