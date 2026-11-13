pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Everything on this machine that was compiled from source (or bundled) rather than being
 * plain QML: what it is, what uses it, and whether it still matches the source beside it.
 *
 * The shell ships these helpers as source and builds them where they run. An update replaces
 * the `*_src` folder and leaves the old binary alone, so a helper can quietly keep running last
 * month's code; the state here is `scripts/rust-helpers.sh status`, which compares a hash of
 * the sources against the stamp written at build time.
 *
 *   Up to date   the binary matches its sources
 *   Needs rebuild  built from sources that have since changed
 *   Unverified   a binary with no stamp (built by hand, or before stamps existed)
 *   Not built    never compiled here. Nothing builds it behind your back, except a
 *                feature you turn on that needs it (Quick Share does)
 *
 * A stale helper keeps running. It only lacks the newest fixes, so this is a prompt, not a gate.
 */
ContentSection {
    id: root

    icon: "construction"
    title: Translation.tr("Compiled components")
    tooltip: Translation.tr("Small programs the shell runs next to its QML. They are built from the source in the ii folder, on this computer, and are never downloaded as binaries.")

    // name, folder under scripts/, title, what uses it. The binary is <folder>/<name>, the
    // source <folder>/<name>_src: the same table rust-helpers.sh keeps.
    readonly property var helpers: [
        { name: "mediator-rs", dir: "mediatorRs", title: Translation.tr("Mediator backend"), usedBy: Translation.tr("The media launcher and its daemon") },
        { name: "ii-quickshare", dir: "quickshare", title: Translation.tr("Quick Share daemon"), usedBy: Translation.tr("Sending files to and from Android phones") },
        { name: "health_watch", dir: "health", title: Translation.tr("System Health helper"), usedBy: Translation.tr("The System Health app: services, crashes, drives") },
        { name: "osk_autoshow", dir: "osk", title: Translation.tr("Keyboard auto-show"), usedBy: Translation.tr("On-screen keyboard that raises itself on text fields") },
        { name: "touch_gestures", dir: "touchGestures", title: Translation.tr("Touch gestures daemon"), usedBy: Translation.tr("Touchscreen gestures") },
        { name: "app_stats", dir: "appStats", title: Translation.tr("App usage sampler"), usedBy: Translation.tr("Per-app usage and energy history") },
        { name: "workspace_arranger", dir: "hyprland", title: Translation.tr("Workspace arranger"), usedBy: Translation.tr("Tidying windows across workspaces") },
        { name: "workspace_profile_manager", dir: "hyprland", title: Translation.tr("Workspace profiles"), usedBy: Translation.tr("Saving and restoring workspace layouts") },
        { name: "sni_watcher", dir: "tray", title: Translation.tr("Tray watcher"), usedBy: Translation.tr("System tray icons") }
    ]

    // Bundled and rebuilt by hand: not part of rust-helpers.sh, because their sources live
    // outside this folder.
    readonly property var bundles: [
        { file: "vendor/books.pyz", title: Translation.tr("Books bundle"), usedBy: Translation.tr("The Books app"), command: "scripts/build-books-zipapp.sh" }
    ]

    readonly property string scriptsDir: Quickshell.shellPath("scripts")

    // ── Rebuilding everything that is behind, one at a time ──────────────────────────
    // Cargo is already parallel, and several at once is how a laptop runs out of memory.
    property var queue: []
    property bool queueRunning: false
    // Counted by hand: each row learns its state asynchronously, after the rows exist, and a
    // binding over Repeater.itemAt() cannot see that.
    property int outdatedCount: 0
    function recount(): void {
        let n = 0;
        for (let i = 0; i < rows.count; i++) {
            const row = rows.itemAt(i);
            if (row && row.build.outdated)
                n++;
        }
        root.outdatedCount = n;
    }

    function rebuildOutdated(): void {
        const q = [];
        for (let i = 0; i < rows.count; i++) {
            const row = rows.itemAt(i);
            if (row && row.build.outdated && row.build.cargoAvailable)
                q.push(i);
        }
        root.queue = q;
        root.queueRunning = q.length > 0;
        root.next();
    }
    function next(): void {
        if (root.queue.length === 0) {
            root.queueRunning = false;
            return;
        }
        const index = root.queue[0];
        root.queue = root.queue.slice(1);
        const row = rows.itemAt(index);
        if (row)
            row.build.build();
        else
            root.next();
    }
    function refreshAll(): void {
        for (let i = 0; i < rows.count; i++) {
            const row = rows.itemAt(i);
            if (row)
                row.build.refreshState();
        }
    }
    Component.onCompleted: root.refreshAll()

    NoticeBox {
        Layout.fillWidth: true
        isFirst: true
        isLast: true
        materialIcon: "info"
        text: Translation.tr("These are compiled here from the source in the ii folder, so they match your CPU and stay readable. An update replaces the source but not the program built from it, so check here after updating. A program that is behind keeps working; it just lacks the newest fixes.")
    }

    // ── Overview ────────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        StyledText {
            Layout.fillWidth: true
            text: root.queueRunning ? Translation.tr("Rebuilding one at a time…")
                : root.outdatedCount > 0 ? Translation.tr("%1 behind their source").arg(root.outdatedCount)
                : Translation.tr("Everything built matches its source")
            color: root.outdatedCount > 0 ? Appearance.colors.colTertiary : Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.normal
            elide: Text.ElideRight
        }
        RippleButtonWithIcon {
            visible: root.outdatedCount > 0 || root.queueRunning
            enabled: !root.queueRunning
            materialIcon: "build"
            mainText: Translation.tr("Rebuild outdated")
            onClicked: root.rebuildOutdated()
        }
        RippleButtonWithIcon {
            materialIcon: "refresh"
            mainText: Translation.tr("Check")
            onClicked: root.refreshAll()
        }
    }

    // ── Compiled helpers ────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Repeater {
            id: rows
            model: root.helpers

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index

                readonly property RustHelperBuild build: helperBuild
                readonly property string state: helperBuild.state
                readonly property string stateLabel: row.state === "ok" ? Translation.tr("Up to date")
                    : row.state === "stale" ? Translation.tr("Needs rebuild")
                    : row.state === "unknown" ? Translation.tr("Unverified")
                    : row.state === "missing" ? Translation.tr("Not built")
                    : Translation.tr("Checking…")
                readonly property color stateColor: row.state === "ok" ? Appearance.colors.colPrimary
                    : row.state === "stale" || row.state === "unknown" ? Appearance.colors.colTertiary
                    : row.state === "missing" ? Appearance.colors.colSubtext
                    : Appearance.colors.colSubtext
                readonly property string stateIcon: row.state === "ok" ? "check_circle"
                    : row.state === "stale" ? "update"
                    : row.state === "unknown" ? "help"
                    : row.state === "missing" ? "do_not_disturb_on" : "hourglass_empty"

                Layout.fillWidth: true
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2
                implicitHeight: rowLayout.implicitHeight + 24

                RustHelperBuild {
                    id: helperBuild
                    label: row.modelData.title
                    sourceDir: `${root.scriptsDir}/${row.modelData.dir}/${row.modelData.name}_src`
                    crateName: row.modelData.name
                    onStateChanged: root.recount()
                    onFinished: ok => {
                        // The queue moves on whether this one worked or not.
                        root.next();
                    }
                }

                ColumnLayout {
                    id: rowLayout
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
                                text: helperBuild.building ? "construction" : row.stateIcon
                                color: row.stateColor
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            StyledText {
                                Layout.fillWidth: true
                                text: row.modelData.title
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer2
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: helperBuild.building ? helperBuild.progressText
                                    : `${row.stateLabel} · ${row.modelData.usedBy}`
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: helperBuild.buildResult === "failed" ? Appearance.colors.colError : Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                        }

                        RippleButtonWithIcon {
                            visible: !helperBuild.building && helperBuild.cargoAvailable
                                && (row.state === "missing" || row.state === "stale" || row.state === "unknown")
                            materialIcon: row.state === "missing" ? "build" : "refresh"
                            mainText: row.state === "missing" ? Translation.tr("Build") : Translation.tr("Rebuild")
                            colBackground: row.state === "stale" ? Appearance.colors.colTertiary : Appearance.colors.colLayer3
                            colText: row.state === "stale" ? Appearance.colors.colOnTertiary : Appearance.colors.colOnLayer2
                            onClicked: helperBuild.build()
                        }
                        MaterialLoadingIndicator {
                            visible: helperBuild.building
                            loading: helperBuild.building
                            implicitSize: 22
                        }
                    }

                    StyledProgressBar {
                        Layout.fillWidth: true
                        visible: helperBuild.building
                        value: helperBuild.progress
                    }

                    HelperCodeBox {
                        Layout.fillWidth: true
                        visible: helperBuild.buildResult === "failed"
                        icon: "error"
                        title: Translation.tr("The build failed")
                        codeSnippet: helperBuild.buildOutput.split("\n").slice(-10).join("\n")
                        snippetWrapMode: Text.WrapAnywhere
                    }
                }
            }
        }
    }

    // ── Without a toolchain ─────────────────────────────────────────────────────
    HelperCodeBox {
        Layout.fillWidth: true
        visible: rows.count > 0 && rows.itemAt(0) && !rows.itemAt(0).build.cargoAvailable
        icon: "terminal"
        title: Translation.tr("Rust is not installed")
        text: Translation.tr("Building needs the Rust toolchain. Install it, then press Check:")
        codeSnippet: "yay -S --needed rust"
        snippetWrapMode: Text.WrapAnywhere
    }

    // ── Bundled ─────────────────────────────────────────────────────────────────
    ContentSubsection {
        Layout.fillWidth: true
        title: Translation.tr("Bundled")
        icon: "inventory_2"
        tooltip: Translation.tr("Programs shipped inside the ii folder whose source lives elsewhere. They are rebuilt by hand with the command shown.")

        Repeater {
            model: root.bundles

            delegate: Rectangle {
                id: bundle
                required property var modelData

                property string size: ""
                property bool present: false

                Layout.fillWidth: true
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2
                implicitHeight: bundleLayout.implicitHeight + 24

                Process {
                    command: ["stat", "-c", "%s", `${Quickshell.shellPath(bundle.modelData.file)}`]
                    running: true
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const bytes = parseInt(text.trim());
                            bundle.present = !isNaN(bytes);
                            bundle.size = bundle.present ? `${(bytes / 1048576).toFixed(1)} MB` : "";
                        }
                    }
                }

                RowLayout {
                    id: bundleLayout
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 12

                    Rectangle {
                        implicitWidth: 38
                        implicitHeight: 38
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colLayer3
                        MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: Appearance.font.pixelSize.larger
                            text: bundle.present ? "inventory_2" : "error"
                            color: bundle.present ? Appearance.colors.colPrimary : Appearance.colors.colError
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText {
                            Layout.fillWidth: true
                            text: bundle.modelData.title
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: `${bundle.present ? Translation.tr("Present · %1").arg(bundle.size) : Translation.tr("Missing")} · ${bundle.modelData.usedBy}`
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: bundle.modelData.command
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideMiddle
                        }
                    }
                }
            }
        }
    }
}
