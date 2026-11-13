pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The battery page of the Lite quick settings: charge, time left, draw, health, the power profile,
 * the automatic saver, and the processes using the most CPU. The process list is read only while the
 * page is on screen, one `top` sample every few seconds.
 */
ColumnLayout {
    id: root

    signal back()

    spacing: 12

    function clock(seconds: real): string {
        if (!seconds || seconds <= 0)
            return "–";
        const h = Math.floor(seconds / 3600);
        const m = Math.round(seconds % 3600 / 60);
        return h > 0 ? Translation.tr("%1 h %2 min").arg(h).arg(m) : Translation.tr("%1 min").arg(m);
    }

    readonly property string stateText: Battery.isCharging ? Translation.tr("Charging")
        : Battery.isFullyCharged ? Translation.tr("Full")
        : Battery.isPluggedIn ? Translation.tr("Plugged in") : Translation.tr("On battery")
    readonly property string timeText: Battery.isCharging ? root.clock(Battery.timeToFull) + " " + Translation.tr("to full")
        : !Battery.isPluggedIn ? root.clock(Battery.timeToEmpty) + " " + Translation.tr("left") : ""

    /// `top` prints RES in KiB, or with a unit once it gets large ("812m", "1.2g").
    function memory(res: string): string {
        if (/^\d+$/.test(res))
            return Math.round(Number(res) / 1024) + " MB";
        const m = res.match(/^([\d.]+)([kmgt])$/i);
        if (!m)
            return res;
        return m[1] + " " + { k: "KB", m: "MB", g: "GB", t: "TB" }[m[2].toLowerCase()];
    }

    LitePageHeader {
        Layout.fillWidth: true
        title: Translation.tr("Battery")
        subtitle: root.stateText
        showSwitch: false
        onBack: root.back()
    }

    // ── charge ──
    RowLayout {
        Layout.fillWidth: true
        spacing: 14
        StyledText {
            text: Battery.percent + "%"
            color: Battery.percent <= 15 && !Battery.isPluggedIn ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer0
            font.pixelSize: 34
            font.weight: Font.DemiBold
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            StyledText {
                Layout.fillWidth: true
                text: root.timeText
                visible: text !== ""
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 6
                radius: 3
                color: Appearance.colors.colLayer2
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, Battery.percentage))
                    height: parent.height
                    radius: 3
                    color: Battery.percent <= 15 && !Battery.isPluggedIn ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
                }
            }
        }
    }

    // ── figures ──
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: [
                { label: Translation.tr("Draw"), value: Battery.energyRate > 0 ? Battery.energyRate.toFixed(1) + " W" : "–" },
                { label: Translation.tr("Health"), value: Battery.health > 0 ? Math.round(Battery.health) + "%" : "–" },
                { label: Translation.tr("Cycles"), value: Battery.cycles >= 0 ? String(Battery.cycles) : "–" }
            ]
            delegate: Rectangle {
                id: figure
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 52
                radius: 14
                color: Appearance.colors.colLayer1
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 0
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: figure.modelData.value
                        color: Appearance.colors.colOnLayer0
                        font.weight: Font.Medium
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: figure.modelData.label
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }
        }
    }

    // ── power profile ──
    StyledText {
        text: Translation.tr("Power profile")
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: [
                { profile: PowerProfile.PowerSaver, icon: "battery_saver", label: Translation.tr("Saver"), available: PowerProfiles.hasPowerSaverProfile ?? true },
                { profile: PowerProfile.Balanced, icon: "balance", label: Translation.tr("Balanced"), available: true },
                { profile: PowerProfile.Performance, icon: "speed", label: Translation.tr("Performance"), available: PowerProfiles.hasPerformanceProfile ?? false }
            ].filter(p => p.available)
            delegate: Rectangle {
                id: choice
                required property var modelData
                readonly property bool current: PowerProfiles.profile === choice.modelData.profile
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 52
                radius: 16
                color: choice.current ? Appearance.colors.colPrimaryContainer
                    : choiceArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                Behavior on color { enabled: !Appearance.reducedMotion; ColorAnimation { duration: Appearance.dur(120) } }
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 0
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: choice.modelData.icon
                        iconSize: 22
                        fill: choice.current ? 1 : 0
                        color: choice.current ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: choice.modelData.label
                        color: choice.current ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
                MouseArea {
                    id: choiceArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: PowerProfiles.profile = choice.modelData.profile
                }
            }
        }
    }

    // ── automatic saver ──
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: saverRow.implicitHeight + 20
        radius: 16
        color: Appearance.colors.colLayer1
        RowLayout {
            id: saverRow
            anchors.fill: parent
            anchors.margins: 10
            anchors.leftMargin: 14
            spacing: 10
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Automatic saver")
                    color: Appearance.colors.colOnLayer0
                    font.weight: Font.Medium
                }
                StyledText {
                    Layout.fillWidth: true
                    text: GlobalStates.liteAutoSaverActive ? Translation.tr("On now, turned on at %1%").arg(Config.options.lite.autoSaver.threshold)
                        : Translation.tr("Power saver below %1% on battery").arg(Config.options.lite.autoSaver.threshold)
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    elide: Text.ElideRight
                }
            }
            Repeater {
                model: [{ icon: "remove", step: -5 }, { icon: "add", step: 5 }]
                delegate: Rectangle {
                    id: stepper
                    required property var modelData
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: 15
                    color: stepArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer0Base
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: stepper.modelData.icon
                        iconSize: 18
                        color: Appearance.colors.colOnLayer0
                    }
                    MouseArea {
                        id: stepArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Config.options.lite.autoSaver.threshold = Math.max(5, Math.min(80, Config.options.lite.autoSaver.threshold + stepper.modelData.step))
                    }
                }
            }
            Rectangle {
                implicitWidth: 46
                implicitHeight: 26
                radius: 13
                color: Config.options.lite.autoSaver.enable ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                Behavior on color { enabled: !Appearance.reducedMotion; ColorAnimation { duration: Appearance.dur(120) } }
                Rectangle {
                    width: 20
                    height: 20
                    radius: 10
                    anchors.verticalCenter: parent.verticalCenter
                    x: Config.options.lite.autoSaver.enable ? parent.width - width - 3 : 3
                    color: Config.options.lite.autoSaver.enable ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                    Behavior on x { enabled: !Appearance.reducedMotion; NumberAnimation { duration: Appearance.dur(120); easing.type: Easing.OutCubic } }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Config.options.lite.autoSaver.enable = !Config.options.lite.autoSaver.enable
                }
            }
        }
    }

    // ── top processes ──
    StyledText {
        text: Translation.tr("Using the most CPU")
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        StyledText {
            visible: root.processes.length === 0
            Layout.fillWidth: true
            text: Translation.tr("Sampling…")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        Repeater {
            model: root.processes
            delegate: RowLayout {
                id: proc
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                StyledText {
                    Layout.fillWidth: true
                    text: proc.modelData.name
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                }
                StyledText {
                    text: proc.modelData.memory
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                StyledText {
                    Layout.preferredWidth: 46
                    horizontalAlignment: Text.AlignRight
                    text: proc.modelData.cpu.toFixed(0) + "%"
                    color: proc.modelData.cpu >= 50 ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer0
                    font.weight: Font.Medium
                }
            }
        }
    }

    // `top` is sampled twice a second apart and the second frame read, since the first reports
    // averages since the process started. It runs only while this page exists.
    property var processes: []

    Process {
        id: sampler
        command: ["top", "-b", "-n", "2", "-d", "1", "-w", "200", "-o", "%CPU"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                let start = -1;
                lines.forEach((line, i) => { if (/^\s*PID\s+USER/.test(line)) start = i + 1; });
                if (start < 0)
                    return;
                const rows = [];
                for (let i = start; i < lines.length && rows.length < 5; i++) {
                    const f = lines[i].trim().split(/\s+/);
                    if (f.length < 12)
                        continue;
                    const name = f.slice(11).join(" ");
                    if (name === "top")
                        continue;
                    const cpu = parseFloat(f[8]);
                    if (!(cpu >= 0))
                        continue;
                    rows.push({ name: name, cpu: cpu, memory: root.memory(f[5]) });
                }
                root.processes = rows;
            }
        }
        onExited: refresh.restart()
    }
    Timer {
        id: refresh
        interval: 3000
        onTriggered: sampler.running = true
    }
    Component.onCompleted: sampler.running = true
    Component.onDestruction: refresh.stop()
}
