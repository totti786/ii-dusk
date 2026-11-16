pragma ComponentBehavior: Bound
import QtQuick
import qs.services.ai
import qs.modules.common
import qs.modules.common.widgets

/** One theme-colored voice visual, shared by the bubble, card and floating form. */
Item {
    id: root
    property bool hovered: false
    property bool showSymbol: true
    readonly property bool fileHover: AiCompanionUi.fileHover
    readonly property bool busy: ["thinking", "transcribing", "preparing", "reading-files"].includes(root.phase)
    onFileHoverChanged: field.requestPaint()
    property bool ambientMotion: false
    property real engagement: root.hovered ? 1 : 0
    property real activity: AiCompanionUi.voice.active ? 1 : 0
    Behavior on engagement { enabled: !AiCompanionUi.reducedMotion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on activity { enabled: !AiCompanionUi.reducedMotion; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    onEngagementChanged: field.requestPaint()
    onActivityChanged: field.requestPaint()
    property real phaseClock: 0
    readonly property string phase: AiCompanionUi.phase
    readonly property bool waveform: !root.fileHover && (phase === "idle" || phase === "listening" || phase === "speaking")
    onPhaseChanged: field.requestPaint()
    onHoveredChanged: field.requestPaint()
    property real amplitude: Math.max(0, Math.min(1, AiCompanionUi.level))
    readonly property bool alert: AiCompanionUi.phase === "attention" || AiCompanionUi.phase === "error"
    readonly property color tone: root.alert ? Appearance.m3colors.m3error : root.fileHover ? Appearance.colors.colTertiary : Appearance.colors.colPrimary
    readonly property color accent: Appearance.colors.colSecondary
    readonly property color highlight: Appearance.colors.colTertiary
    readonly property bool animated: !!(visible && !AiCompanionUi.reducedMotion
        && !AiCompanionUi.dragging && (root.ambientMotion || AiCompanionUi.voice.active || root.hovered))
    implicitWidth: 56
    implicitHeight: 56
    scale: AiCompanionUi.controlPressed && !AiCompanionUi.dragging ? .96 : 1
    Behavior on scale { enabled: !AiCompanionUi.reducedMotion; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on amplitude { enabled: !AiCompanionUi.reducedMotion; NumberAnimation { duration: 90 } }
    onAmplitudeChanged: field.requestPaint()
    onToneChanged: field.requestPaint()
    onAccentChanged: field.requestPaint()
    onHighlightChanged: field.requestPaint()
    Timer {
        property double lastFrame: 0
        interval: AiCompanionUi.voice.active || root.hovered ? 16 : 50
        repeat: true
        running: root.animated
        onRunningChanged: lastFrame = Date.now()
        onTriggered: {
            const now = Date.now();
            root.phaseClock += Math.min(.08, (now-lastFrame)/1000);
            lastFrame = now;
            field.requestPaint();
        }
    }
    Canvas {
        id: field
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx=width/2, cy=height/2, r=Math.min(width,height)*.43;
            const t=AiCompanionUi.reducedMotion ? 0 : root.phaseClock;
            const a=AiCompanionUi.reducedMotion ? 0 : root.amplitude;
            const motion=AiCompanionUi.reducedMotion || AiCompanionUi.dragging ? 0 : 1;
            const breath=1+motion*.014*Math.sin(t*1.4);
            const flow=.018+root.engagement*.018+root.activity*.012;
            // A single soft silhouette: no concentric discs or painted shine.
            ctx.beginPath();
            for (let i=0; i<=96; i++) {
                const angle=i/96*Math.PI*2;
                const wave=Math.sin(angle*6+t*.45)*flow
                    + motion*.009*Math.sin(angle*3-t*.8);
                const radius=r*(breath+wave+a*.075*Math.sin(angle*3+t*2));
                const x=cx+Math.cos(angle)*radius, y=cy+Math.sin(angle)*radius;
                if(i===0) ctx.moveTo(x,y); else ctx.lineTo(x,y);
            }
            ctx.closePath();
            const light=t*.22*motion;
            const base=ctx.createLinearGradient(cx-Math.cos(light)*r,cy-r,cx+Math.cos(light)*r,cy+r);
            base.addColorStop(0,String(root.tone));
            base.addColorStop(1,String(root.accent));
            ctx.fillStyle=base; ctx.fill();
            ctx.save(); ctx.clip();
            ctx.globalAlpha=.13; ctx.fillStyle=String(root.highlight);
            ctx.beginPath();
            const drift=motion*Math.sin(t*.65)*r*.18;
            ctx.moveTo(cx-r*1.4,cy+r*.45+drift);
            ctx.bezierCurveTo(cx-r*.3,cy-r*(.9+a)+drift,cx+r*.2,cy+r*.9-drift,cx+r*1.4,cy-r*.25);
            ctx.lineTo(cx+r*1.4,cy+r*1.4);ctx.lineTo(cx-r*1.4,cy+r*1.4);ctx.closePath();ctx.fill();
            ctx.restore();
            ctx.globalAlpha=1;
            if (root.showSymbol && root.busy && !root.fileHover) {
                ctx.fillStyle=String(Appearance.colors.colOnPrimary);
                for(let i=0;i<3;i++) {
                    const hop=motion*Math.sin(t*4-i*.7)*width*.025;
                    ctx.beginPath();ctx.arc(cx+(i-1)*width*.11,cy+hop,width*.025,0,Math.PI*2);ctx.fill();
                }
            }
            if (root.showSymbol && root.waveform) {
                ctx.fillStyle=String(root.alert ? Appearance.m3colors.m3onError : Appearance.colors.colOnPrimary);
                const unit=width/84, bar=3*unit, gap=3*unit;
                for (let i=0;i<5;i++) {
                    const rest=[7,14,22,14,7][i];
                    const idle=motion*Math.sin(t*1.8+i*.65)*(.6+root.engagement*.7+root.activity*1.1);
                    const height=Math.max(4,rest+idle+a*(8+10*Math.sin(t*5+i*1.2)))*unit;
                    const x=cx+(i-2)*(bar+gap)-bar/2, y=cy-height/2, round=bar/2;
                    ctx.beginPath();ctx.moveTo(x+round,y);
                    ctx.arc(x+round,y+round,round,Math.PI,Math.PI*2);
                    ctx.lineTo(x+bar,y+height-round);
                    ctx.arc(x+round,y+height-round,round,0,Math.PI);
                    ctx.closePath();ctx.fill();
                }
            }
        }
    }
    MaterialSymbol {
        anchors.centerIn: parent
        visible: root.showSymbol && !root.waveform && (!root.busy || root.fileHover)
        text: root.fileHover ? "attach_file" : AiCompanionUi.symbol
        iconSize: Math.max(13, Math.round(root.width*.29))
        fill: 1
        color: root.alert ? Appearance.m3colors.m3onError : Appearance.colors.colOnPrimary
    }
}
