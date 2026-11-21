pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Everything the shell needs from outside its own folder, and whether this machine has it.
 *
 *   Python environment  the one venv every script runs in, compared with the lock file
 *   Programs, packages and fonts  required and optional, grouped, each with the command that
 *                       installs it
 *
 * The list lives in scripts/deps/envcheck.py (also behind `scripts/deps/check.sh`), so this page
 * and the command line cannot disagree. Nothing here runs pacman by itself: an install opens a
 * terminal with the command in it, because it needs your password and you should see it.
 *
 * Loaded when scrolled into view and read once; the buttons re-read it.
 */
ContentSection {
    id: root

    icon: "deployed_code"
    title: Translation.tr("Dependencies")
    tooltip: Translation.tr("The programs, packages and fonts the shell relies on, and the one Python environment all its scripts run in. Required items break something when missing; optional ones only matter for a single feature.")

    readonly property string script: Quickshell.shellPath("scripts/deps/envcheck.py")

    property var data: null
    property bool loading: false
    property string loadError: ""
    property bool onlyMissing: false

    // The environment actions (sync to the lock, rebuild from scratch).
    property string actionName: ""
    property string actionStep: ""
    property var actionTail: []
    property string actionResult: ""
    property bool confirmRebuild: false

    property bool showPackages: false
    property var packages: []
    property bool checkingUpdates: false
    property var outdated: null

    readonly property var env: root.data ? root.data.env : null
    readonly property var summary: root.data ? root.data.summary : null
    readonly property bool busy: actionProc.running
    readonly property int envIssues: root.data && root.data.summary ? root.data.summary.environmentIssues : 0
    readonly property int requiredMissing: root.data && root.data.summary ? root.data.summary.requiredMissing : 0

    function refresh(): void {
        if (statusProc.running)
            return;
        root.loading = true;
        root.loadError = "";
        statusProc.running = true;
    }

    function runInTerminal(command: string): void {
        // Needs a password, so it gets a terminal rather than a hidden process.
        Quickshell.execDetached([Config.options.apps.terminal, "-e", "bash", "-c",
            `${command}; echo; read -r -n1 -p "Finished. Press any key to close." _`]);
    }

    function startAction(name: string): void {
        if (root.busy)
            return;
        root.actionName = name;
        root.actionStep = Translation.tr("Starting…");
        root.actionTail = [];
        root.actionResult = "";
        root.confirmRebuild = false;
        actionProc.command = ["python3", root.script, name];
        actionProc.running = true;
    }

    function consume(line: string): void {
        const text = String(line).trim();
        if (text.length === 0)
            return;
        if (text.startsWith("STEP"))
            root.actionStep = text.replace(/^STEP\s*/, "");
        const tail = root.actionTail.concat([text]);
        root.actionTail = tail.slice(-12);
    }

    Component.onCompleted: root.refresh()

    Process {
        id: statusProc
        command: ["python3", root.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    root.data = JSON.parse(text);
                } catch (error) {
                    root.loadError = Translation.tr("Could not read the dependency report.");
                }
            }
        }
        onExited: code => {
            root.loading = false;
            if (code !== 0 && root.data === null)
                root.loadError = Translation.tr("Could not read the dependency report.");
        }
    }

    Process {
        id: packagesProc
        command: ["python3", root.script, "packages"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.packages = JSON.parse(text);
                } catch (error) {
                    root.packages = [];
                }
            }
        }
    }

    Process {
        id: outdatedProc
        command: ["python3", root.script, "outdated"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.checkingUpdates = false;
                try {
                    root.outdated = JSON.parse(text);
                } catch (error) {
                    root.outdated = { ok: false, packages: [] };
                }
            }
        }
    }

    Process {
        id: actionProc
        stdout: SplitParser { onRead: line => root.consume(line) }
        stderr: SplitParser { onRead: line => root.consume(line) }
        onExited: code => {
            root.actionResult = code === 0 ? "ok" : "failed";
            root.actionName = "";
            root.outdated = null;
            root.refresh();
            if (root.showPackages)
                packagesProc.running = true;
        }
    }

    NoticeBox {
        Layout.fillWidth: true
        isFirst: true
        isLast: true
        materialIcon: "info"
        text: Translation.tr("Every Python script in the shell runs in one environment, so there is one place to look and one command to rebuild it. Programs and fonts come from your system; the command beside each missing one installs it.")
    }

    // ── Overview ────────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        StyledText {
            Layout.fillWidth: true
            text: root.loading && !root.data ? Translation.tr("Checking…")
                : root.loadError.length > 0 ? root.loadError
                : root.requiredMissing > 0 ? Translation.tr("%1 required missing").arg(root.requiredMissing)
                : root.envIssues > 0 ? Translation.tr("The Python environment differs from its lock")
                : Translation.tr("Everything required is installed")
            color: root.loadError.length > 0 || (root.requiredMissing > 0) ? Appearance.colors.colError
                : root.envIssues > 0 ? Appearance.colors.colTertiary
                : Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.normal
            elide: Text.ElideRight
        }
        RippleButtonWithIcon {
            materialIcon: root.onlyMissing ? "filter_alt_off" : "filter_alt"
            mainText: root.onlyMissing ? Translation.tr("Show all") : Translation.tr("Only missing")
            onClicked: root.onlyMissing = !root.onlyMissing
        }
        RippleButtonWithIcon {
            enabled: !root.loading && !root.busy
            materialIcon: "refresh"
            mainText: Translation.tr("Check")
            onClicked: root.refresh()
        }
    }

    // ── Python environment ──────────────────────────────────────────────────────
    ContentSubsection {
        Layout.fillWidth: true
        title: Translation.tr("Python environment")
        icon: "terminal"
        tooltip: Translation.tr("One virtual environment holds every Python package the shell uses: colours, images, the voice assistant, Anki, Music, Syncplay and the rest. Nothing is read from the system Python packages. requirements.lock in scripts/deps is the exact list.")

        Rectangle {
            Layout.fillWidth: true
            visible: root.env !== null
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            implicitHeight: envLayout.implicitHeight + 24

            ColumnLayout {
                id: envLayout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Rectangle {
                        implicitWidth: 38
                        implicitHeight: 38
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colLayer3
                        MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: Appearance.font.pixelSize.larger
                            text: !root.env || !root.env.exists ? "error"
                                : root.envIssues > 0 ? "update" : "check_circle"
                            color: !root.env || !root.env.exists ? Appearance.colors.colError
                                : root.envIssues > 0 ? Appearance.colors.colTertiary : Appearance.colors.colPrimary
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText {
                            Layout.fillWidth: true
                            text: !root.env ? "" : !root.env.exists ? Translation.tr("Not built")
                                : `Python ${root.env.python} · ${Translation.tr("%1 packages").arg(root.env.installed)}`
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: !root.env ? "" : root.env.path.replace(/^\/home\/[^/]+/, "~")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideMiddle
                        }
                    }
                    MaterialLoadingIndicator {
                        visible: root.busy
                        loading: root.busy
                        implicitSize: 22
                    }
                }

                // What differs from the lock, in words.
                StyledText {
                    Layout.fillWidth: true
                    visible: root.env && root.env.exists
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.envIssues > 0 ? Appearance.colors.colTertiary : Appearance.colors.colSubtext
                    text: {
                        if (!root.env || !root.env.exists)
                            return Translation.tr("The environment does not exist yet. Build it to make the voice assistant, colours, Anki, Music and Syncplay work.");
                        const parts = [];
                        if (root.env.missing.length > 0)
                            parts.push(Translation.tr("%1 missing: %2").arg(root.env.missing.length).arg(root.env.missing.slice(0, 4).map(p => p.name).join(", ")));
                        if (root.env.changed.length > 0)
                            parts.push(Translation.tr("%1 at another version: %2").arg(root.env.changed.length).arg(root.env.changed.slice(0, 4).map(p => `${p.name} ${p.installed}`).join(", ")));
                        const brokenModules = root.env.modules.filter(m => !m.ok);
                        if (brokenModules.length > 0)
                            parts.push(Translation.tr("cannot import: %1").arg(brokenModules.slice(0, 5).map(m => m.name).join(", ")));
                        if (!root.env.isolated)
                            parts.push(Translation.tr("it can see the system's Python packages"));
                        if (!root.env.python.startsWith(root.env.wantPython))
                            parts.push(Translation.tr("Python %1 expected").arg(root.env.wantPython));
                        return parts.length > 0 ? parts.join(" · ") : Translation.tr("Matches requirements.lock, and every module the shell imports is present.");
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: root.env !== null

                    RippleButtonWithIcon {
                        enabled: !root.busy && root.env && root.env.uv
                        materialIcon: "sync"
                        mainText: root.env && !root.env.exists ? Translation.tr("Build") : Translation.tr("Sync to lock")
                        colBackground: root.envIssues > 0 ? Appearance.colors.colTertiary : Appearance.colors.colLayer3
                        colText: root.envIssues > 0 ? Appearance.colors.colOnTertiary : Appearance.colors.colOnLayer2
                        onClicked: root.startAction("sync")
                    }
                    RippleButtonWithIcon {
                        enabled: !root.busy && !root.checkingUpdates && root.env && root.env.exists
                        materialIcon: "update"
                        mainText: root.checkingUpdates ? Translation.tr("Checking…") : Translation.tr("Look for updates")
                        onClicked: {
                            root.checkingUpdates = true;
                            root.outdated = null;
                            outdatedProc.running = true;
                        }
                    }
                    RippleButtonWithIcon {
                        enabled: root.env && root.env.exists
                        materialIcon: root.showPackages ? "unfold_less" : "unfold_more"
                        mainText: root.showPackages ? Translation.tr("Hide packages") : Translation.tr("Packages")
                        onClicked: {
                            root.showPackages = !root.showPackages;
                            if (root.showPackages && root.packages.length === 0)
                                packagesProc.running = true;
                        }
                    }
                    Item { Layout.fillWidth: true }
                    RippleButtonWithIcon {
                        enabled: !root.busy && root.env && root.env.uv
                        materialIcon: root.confirmRebuild ? "warning" : "delete_sweep"
                        mainText: root.confirmRebuild ? Translation.tr("Rebuild now") : Translation.tr("Rebuild from scratch")
                        colBackground: root.confirmRebuild ? Appearance.colors.colError : Appearance.colors.colLayer3
                        colText: root.confirmRebuild ? Appearance.colors.colOnError : Appearance.colors.colOnLayer2
                        onClicked: root.confirmRebuild ? root.startAction("rebuild") : (root.confirmRebuild = true)
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.confirmRebuild && !root.busy
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colError
                    text: Translation.tr("This deletes the environment and installs everything again from the lock. It takes a minute or two, needs the network, and the voice assistant, colours and Anki stop working until it finishes.")
                }

                // Progress and result of the running or last action.
                StyledText {
                    Layout.fillWidth: true
                    visible: root.busy
                    text: root.actionStep
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
                HelperCodeBox {
                    Layout.fillWidth: true
                    visible: root.actionResult === "failed"
                    icon: "error"
                    title: Translation.tr("That did not finish")
                    codeSnippet: root.actionTail.join("\n")
                    snippetWrapMode: Text.WrapAnywhere
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.actionResult === "ok" && !root.busy
                    text: Translation.tr("Done.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colPrimary
                }

                // Newer releases than the lock, when asked for.
                StyledText {
                    Layout.fillWidth: true
                    visible: root.outdated !== null
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    text: !root.outdated ? ""
                        : !root.outdated.ok ? Translation.tr("Could not reach the package index.")
                        : root.outdated.packages.length === 0 ? Translation.tr("Nothing newer is available.")
                        : Translation.tr("Newer releases exist for %1 packages: %2. The lock keeps versions the shell was tested with; raise them in requirements.in on purpose.")
                            .arg(root.outdated.packages.length)
                            .arg(root.outdated.packages.slice(0, 8).map(p => `${p.name} ${p.version} → ${p.latest}${p.pinned ? " (pinned)" : ""}`).join(", "))
                }

                // Every package, on request.
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.showPackages
                    spacing: 0
                    Repeater {
                        model: root.showPackages ? root.packages : []
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8
                            StyledText {
                                Layout.fillWidth: true
                                text: parent.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer2
                                elide: Text.ElideRight
                            }
                            StyledText {
                                visible: parent.modelData.pinned
                                text: Translation.tr("pinned")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colTertiary
                            }
                            StyledText {
                                text: parent.modelData.version
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: root.env !== null && !root.env.wrapperOnPath
            isFirst: true
            isLast: true
            materialIcon: "warning"
            text: Translation.tr("scripts/deps/bin is not first on PATH here, so a bare python3 would be the system one. The shell adds it itself when it starts; this only matters for scripts you start by hand.")
        }
        NoticeBox {
            Layout.fillWidth: true
            visible: root.env !== null && root.env.staleVenvs.length > 0
            isFirst: true
            isLast: true
            materialIcon: "delete"
            text: Translation.tr("Old environments from before the merge are still on disk and unused: %1. Delete them to get the space back.").arg(root.env ? root.env.staleVenvs.join(", ") : "")
        }
    }

    // ── System programs, packages and fonts ─────────────────────────────────────
    Repeater {
        model: root.data ? root.data.groups : []

        delegate: ContentSubsection {
            id: group
            required property var modelData

            readonly property var shown: group.modelData.items.filter(item => !root.onlyMissing || !item.ok)
            readonly property int missingCount: group.modelData.items.filter(item => !item.ok).length

            Layout.fillWidth: true
            visible: group.shown.length > 0
            title: `${group.modelData.title}${group.missingCount > 0 ? "  ·  " + Translation.tr("%1 missing").arg(group.missingCount) : ""}`
            icon: group.modelData.id === "fonts" ? "font_download" : group.modelData.id === "build" ? "construction"
                : group.modelData.id === "qt" ? "widgets" : group.modelData.id === "media" ? "movie"
                : group.modelData.id === "devices" ? "devices" : "settings"

            Repeater {
                model: group.shown

                delegate: Rectangle {
                    id: item
                    required property var modelData

                    Layout.fillWidth: true
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2
                    implicitHeight: itemRow.implicitHeight + 16

                    RowLayout {
                        id: itemRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 12
                        spacing: 12

                        MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.larger
                            text: item.modelData.ok ? "check_circle" : item.modelData.required ? "error" : "do_not_disturb_on"
                            color: item.modelData.ok ? Appearance.colors.colPrimary
                                : item.modelData.required ? Appearance.colors.colError : Appearance.colors.colSubtext
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            StyledText {
                                Layout.fillWidth: true
                                text: item.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: `${item.modelData.required ? Translation.tr("Required") : Translation.tr("Optional")} · ${item.modelData.feature}`
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                        }
                        RippleButtonWithIcon {
                            visible: !item.modelData.ok && item.modelData.kind !== "font" && /^(sudo|paru|yay) /.test(item.modelData.install)
                            materialIcon: "terminal"
                            mainText: Translation.tr("Install")
                            onClicked: root.runInTerminal(item.modelData.install)
                        }
                        RippleButtonWithIcon {
                            visible: !item.modelData.ok && item.modelData.kind !== "font" && item.modelData.install.length > 0
                            materialIcon: "content_copy"
                            mainText: Translation.tr("Copy command")
                            onClicked: Quickshell.clipboardText = item.modelData.install
                        }
                        RippleButtonWithIcon {
                            visible: !item.modelData.ok && item.modelData.kind === "font" && item.modelData.fontSource.length > 0
                            materialIcon: "font_download"
                            mainText: Translation.tr("Install font")
                            onClicked: Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "settings", "openSection", "interfaceFonts", "Install fonts"])
                        }
                    }
                }
            }
        }
    }

    HelperCodeBox {
        Layout.fillWidth: true
        visible: root.env !== null && !root.env.uv
        icon: "terminal"
        title: Translation.tr("uv is not installed")
        text: Translation.tr("The Python environment is built with uv. Install it, then press Check:")
        codeSnippet: "sudo pacman -S --needed uv"
        snippetWrapMode: Text.WrapAnywhere
    }
}
