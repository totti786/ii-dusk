pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * Front for ii-fand (scripts/thermal/ii-fand), the root daemon that drives the fan curve,
 * CPU turbo and TCC offset. The shell never writes sysfs: it reads the daemon's status file
 * and hands new configs to `pkexec ii-fand set`. Before the daemon is installed the page
 * still shows live readings through `ii-fand detect` from the repo copy.
 *
 * Nothing polls unless a page holds a watch (`watchers`), so an unopened page costs nothing.
 */
Singleton {
    id: root

    readonly property string repoScript: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/thermal/ii-fand"))
    readonly property string installScript: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/thermal/install.sh"))
    readonly property string daemonPath: "/usr/local/bin/ii-fand"
    readonly property string ecPath: "/usr/local/bin/ii-fand-ec"   // same program, polkit asks for a password
    readonly property string statusPath: "/run/ii-fand/status.json"

    // Pages bump this while they are visible.
    property int watchers: 0

    property var caps: null          // ii-fand detect
    property var status: null        // /run/ii-fand/status.json
    property bool daemonInstalled: false
    // The installed daemon/unit differ from the copies in the shell repo (new backend, fix…)
    property bool updateAvailable: false
    readonly property bool daemonRunning: root.status !== null && (Date.now() / 1000 - root.status.time) < 15
    readonly property bool ready: root.caps !== null

    readonly property string backend: root.caps?.backend ?? "none"
    readonly property bool controllable: root.backend !== "none"
    // alienware_wmi adds the boost to the EC's own speed: the curve can raise the fans, never lower them
    readonly property bool additive: root.backend === "alienware_wmi"
    readonly property bool turboAvailable: root.caps?.turbo?.available ?? false
    readonly property bool tccAvailable: root.caps?.tcc?.available ?? false
    readonly property int tccMax: Math.min(root.caps?.tcc?.max ?? 0, 40)
    readonly property int tjMax: root.caps?.tcc?.tjmax ?? 100

    // Live values: the daemon's when it runs, detect's otherwise
    readonly property var temps: (root.daemonRunning ? root.status.temps : root.caps?.temps) ?? []
    readonly property var fans: (root.daemonRunning ? root.status.fans : root.caps?.fans) ?? []
    // Board-ambient sensors (Framework EC: ambient, charger) are shown but don't drive the curve
    readonly property var curveTemps: root.temps.filter(t => t.drive !== false)
    readonly property real hottest: root.curveTemps.reduce((m, t) => Math.max(m, t.c), 0)
    readonly property real appliedPct: root.daemonRunning && root.status.targetPct !== null ? root.status.targetPct : -1
    readonly property bool turboEnabled: (root.daemonRunning ? root.status.turbo : root.caps?.turbo?.enabled) ?? true
    readonly property int tccOffset: (root.daemonRunning ? root.status.tcc : root.caps?.tcc?.current) ?? 0

    // ── Framework laptops ──
    // Detection runs as the user: DMI vendor, the cros_ec hwmon and framework_tool on PATH.
    // Everything framework_tool reads needs root, so the values come from the daemon only.
    readonly property var frameworkCaps: root.caps?.framework ?? null
    readonly property bool isFramework: root.frameworkCaps?.detected ?? false
    readonly property bool frameworkToolInstalled: root.frameworkCaps?.tool ?? false
    readonly property bool frameworkEcDriver: root.frameworkCaps?.ec ?? false
    readonly property bool frameworkReady: root.isFramework && root.frameworkToolInstalled && root.frameworkEcDriver
    readonly property bool frameworkLaptop16: root.frameworkCaps?.laptop16 ?? false
    readonly property var frameworkStatus: root.daemonRunning ? (root.status.framework ?? null) : null
    readonly property var frameworkConfig: root.config.framework ?? ({ "chargeLimit": null, "fpLevel": null })

    function applyFramework(changes) {
        root.apply(Object.assign({}, root.config, { "framework": Object.assign({}, root.frameworkConfig, changes) }));
    }

    // The stored config, or the curve the old g15-fancurve shipped with
    readonly property var defaultConfig: ({
        "enabled": true,
        "curve": { "tStart": 60, "tMax": 80, "minPct": 40, "maxPct": 100, "steepness": 2.0 },
        "hysteresis": 4, "interval": 2, "turbo": null, "tccOffset": null,
        "framework": { "chargeLimit": null, "fpLevel": null }
    })
    readonly property var config: root.status?.config ?? root.defaultConfig

    property bool busy: false
    property string lastError: ""
    signal saved()

    // The curve being edited. Kept here rather than on the page so leaving Settings doesn't
    // lose it; null = nothing edited, the page shows the stored curve.
    property var draftCurve: null
    readonly property bool curveDirty: root.draftCurve !== null && !root.sameCurve(root.draftCurve, root.config.curve)

    function sameCurve(a, b) {
        return a.tStart === b.tStart && a.tMax === b.tMax && a.minPct === b.minPct
            && a.maxPct === b.maxPct && a.steepness === b.steepness;
    }

    function applyDraft() {
        if (root.draftCurve !== null)
            root.apply(Object.assign({}, root.config, { "curve": root.draftCurve }));
    }

    function discardDraft() {
        root.draftCurve = null;
    }

    // Same formula as ii-fand's curve_pct
    function curvePct(curve, temp) {
        const span = curve.tMax - curve.tStart;
        const x = span > 0 ? Math.max(0, Math.min(1, (temp - curve.tStart) / span)) : (temp >= curve.tMax ? 1 : 0);
        const k = curve.steepness;
        let shaped;
        if (Math.abs(k) < 1e-3)
            shaped = x;
        else if (k > 0)
            shaped = Math.expm1(k * x) / Math.expm1(k);
        else
            shaped = 1 - Math.expm1(-k * (1 - x)) / Math.expm1(-k);
        return curve.minPct + (curve.maxPct - curve.minPct) * shaped;
    }

    function apply(cfg) {
        if (root.busy || !root.daemonInstalled)
            return;
        root.busy = true;
        root.lastError = "";
        setProc.command = ["pkexec", root.daemonPath, "set", JSON.stringify(cfg)];
        setProc.running = true;
    }

    // ── EC profile setup (laptops with no kernel fan driver) ──
    // nbfc configs found on disk, the one picked, what ii-fand made of it, and what the
    // registers hold. Enabling is a separate, authenticated step.
    property var ecConfigs: []          // [{ name, path }]
    property string ecSelected: ""      // path
    property var ecImported: null       // { key, profile } from `ii-fand ec-import`
    property string ecImportError: ""
    property string ecCheckText: ""
    property bool ecChecked: false
    property bool ecBusy: false
    readonly property bool ecReady: root.daemonInstalled && !root.updateAvailable

    function ecScan() {
        if (!scanProc.running)
            scanProc.running = true;
    }

    function ecPick(path) {
        root.ecSelected = path;
        root.ecImported = null;
        root.ecImportError = "";
        root.ecCheckText = "";
        root.ecChecked = false;
        importProc.command = ["python3", "-I", root.repoScript, "ec-import", path];
        importProc.running = true;
    }

    // Read-only, but root: the debugfs file is not readable otherwise
    function ecReadRegisters() {
        if (root.ecBusy || root.ecImported === null)
            return;
        root.ecBusy = true;
        // checks the candidate profile before anything is stored
        checkProc.command = ["pkexec", root.ecPath, "ec-check", JSON.stringify(root.ecImported)];
        checkProc.running = true;
    }

    function ecEnable() {
        if (root.ecBusy || root.ecImported === null || !root.ecChecked)
            return;
        root.ecBusy = true;
        root.lastError = "";
        addProc.command = ["pkexec", root.ecPath, "ec-add", JSON.stringify(root.ecImported)];
        addProc.running = true;
    }

    function install() {
        if (root.busy)
            return;
        root.busy = true;
        root.lastError = "";
        installProc.running = true;
    }

    function refresh() {
        if (!detectProc.running)
            detectProc.running = true;
        statusFile.reload();
        installedCheck.reload();
        if (!diffProc.running)
            diffProc.running = true;
    }

    onWatchersChanged: if (root.watchers > 0) root.refresh()

    Timer {
        interval: 2000
        repeat: true
        running: root.watchers > 0
        onTriggered: {
            statusFile.reload();
            // detect spawns python; without the daemon it is the only live source
            if (!root.daemonRunning && !detectProc.running)
                detectProc.running = true;
        }
    }

    Process {
        id: detectProc
        command: ["python3", "-I", root.repoScript, "detect"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.caps = JSON.parse(text);
                } catch (e) {
                    console.warn("[FanControl] detect failed:", e);
                }
            }
        }
    }

    FileView {
        id: statusFile
        path: root.statusPath
        printErrors: false
        blockLoading: false
        onLoaded: {
            try {
                root.status = JSON.parse(text());
            } catch (e) {
                root.status = null;
            }
        }
        onLoadFailed: root.status = null
    }

    Process {
        id: diffProc
        command: ["sh", "-c", "cmp -s \"$1\" \"$2\" && cmp -s \"$1\" \"$5\" && cmp -s \"$3\" \"$4\"",
            "sh", root.repoScript, root.daemonPath,
            root.repoScript.replace(/ii-fand$/, "ii-fand.service"), "/etc/systemd/system/ii-fand.service",
            root.ecPath]
        // a missing installed file also counts as different; the install prompt covers that case
        onExited: (code, status) => root.updateAvailable = code !== 0
    }

    FileView {
        id: installedCheck
        path: root.daemonPath
        printErrors: false
        onLoaded: root.daemonInstalled = true
        onLoadFailed: root.daemonInstalled = false
    }

    Process {
        id: setProc
        stderr: StdioCollector {
            id: setErr
        }
        onExited: (code, status) => {
            root.busy = false;
            if (code === 0) {
                root.saved();
                // the daemon picks the config up on SIGHUP; read its next tick
                reloadSoon.restart();
            } else {
                root.lastError = code === 126 || code === 127
                    ? Translation.tr("Authorisation was refused")
                    : (setErr.text.trim().split("\n").pop() || `ii-fand exited with ${code}`);
            }
        }
    }

    Process {
        id: installProc
        command: ["pkexec", "sh", root.installScript]
        stderr: StdioCollector {
            id: installErr
        }
        onExited: (code, status) => {
            root.busy = false;
            if (code !== 0)
                root.lastError = installErr.text.trim().split("\n").pop() || `install.sh exited with ${code}`;
            reloadSoon.restart();
        }
    }

    Process {
        id: scanProc
        command: ["sh", "-c", "for d in /opt/nbfc/Configs \"$HOME/.local/share/ii-fand/nbfc-configs\"; do [ -d \"$d\" ] && find \"$d\" -maxdepth 1 -name '*.xml'; done | sort"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.ecConfigs = text.split("\n").filter(l => l.length > 0).map(p => ({
                    "name": p.split("/").pop().replace(/\.xml$/, ""), "path": p
                }));
            }
        }
    }

    Process {
        id: importProc
        stdout: StdioCollector { id: importOut }
        stderr: StdioCollector { id: importErr }
        onExited: (code, status) => {
            if (code === 0) {
                try {
                    root.ecImported = JSON.parse(importOut.text);
                    return;
                } catch (e) {}
            }
            root.ecImported = null;
            root.ecImportError = importErr.text.trim() || `ec-import exited with ${code}`;
        }
    }

    Process {
        id: checkProc
        stdout: StdioCollector { id: checkOut }
        stderr: StdioCollector { id: checkErr }
        onExited: (code, status) => {
            root.ecBusy = false;
            if (code === 0) {
                root.ecCheckText = checkOut.text.trim();
                root.ecChecked = true;
            } else {
                root.ecChecked = false;
                root.ecCheckText = "";
                root.ecImportError = code === 126 || code === 127
                    ? Translation.tr("Authorisation was refused")
                    : (checkErr.text.trim().split("\n").pop() || `ec-check exited with ${code}`);
            }
        }
    }

    Process {
        id: addProc
        stderr: StdioCollector { id: addErr }
        onExited: (code, status) => {
            root.ecBusy = false;
            if (code === 0) {
                root.ecImported = null;
                root.ecChecked = false;
                reloadSoon.restart();
            } else {
                root.lastError = code === 126 || code === 127
                    ? Translation.tr("Authorisation was refused")
                    : (addErr.text.trim().split("\n").pop() || `ec-add exited with ${code}`);
            }
        }
    }

    Timer {
        id: reloadSoon
        interval: 2500
        onTriggered: root.refresh()
    }
}
