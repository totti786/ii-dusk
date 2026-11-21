pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Install fonts for your own account, without a terminal or root:
 *
 *   From Google Fonts   type a family name; the files come from the Google Fonts repository
 *   From a file or link a .ttf/.otf file, a .zip, a folder, or a download link
 *
 * Everything goes to ~/.local/share/fonts/ii-installed/<Name>/ with a marker, so the list below
 * can remove exactly what was installed here and nothing else (scripts/fonts/font_install.py).
 * The shell reads its font list once at start, so a new family shows up in Custom fonts after a
 * restart; the button below does that.
 */
ContentSection {
    id: root

    icon: "font_download"
    title: Translation.tr("Install fonts")
    tooltip: Translation.tr("Adds fonts to your own account only, in ~/.local/share/fonts/ii-installed. Nothing needs a password, and every font installed here can be removed again from the list below. The shell finds new families after a restart.")

    readonly property string script: Quickshell.shellPath("scripts/fonts/font_install.py")
    readonly property string guard: Quickshell.shellPath("scripts/quickshell-guard/qs-guard.sh")

    property bool busy: false
    property string stepText: ""
    property string message: ""
    property bool messageIsError: false
    property bool needsRestart: false
    property var installed: []
    property string confirmRemove: ""

    // The fonts the shell itself relies on (scripts/deps/envcheck.py fonts), and a queue so
    // "Install all missing" fetches them one after another.
    property var needed: []
    property var queue: []
    readonly property int missingCount: root.needed.filter(f => !f.ok && f.source.length > 0).length
    readonly property int requiredMissing: root.needed.filter(f => !f.ok && f.required).length

    function run(args: var): void {
        if (root.busy)
            return;
        root.busy = true;
        root.stepText = Translation.tr("Starting…");
        root.message = "";
        root.confirmRemove = "";
        fontProc.command = ["python3", root.script].concat(args);
        fontProc.running = true;
    }

    function installGoogle(): void {
        const name = googleField.text.trim();
        if (name.length > 0)
            root.run(["google", name]);
    }

    function installSource(): void {
        const source = sourceField.text.trim();
        if (source.length > 0)
            root.run(["file", source]);
    }

    function refresh(): void {
        if (!listProc.running)
            listProc.running = true;
        if (!neededProc.running)
            neededProc.running = true;
    }

    function argsFor(font: var): var {
        // ["google", family] or ["url", link] from the checker; the installer calls the second "file".
        return [font.source[0] === "url" ? "file" : font.source[0], font.source[1]];
    }

    function installNeeded(font: var): void {
        if (font.source.length > 0)
            root.run(root.argsFor(font));
    }

    function installAllMissing(): void {
        const todo = root.needed.filter(f => !f.ok && f.source.length > 0).map(f => root.argsFor(f));
        if (todo.length === 0)
            return;
        root.queue = todo.slice(1);
        root.run(todo[0]);
    }

    function restartShell(): void {
        // Detached, so it outlives the shell it is about to stop.
        Quickshell.execDetached(["sh", "-c",
            `setsid -f sh -c 'sleep 0.5; qs -c ii kill; sleep 2; exec "${root.guard}" -c ii' >/dev/null 2>&1`]);
    }

    function megabytes(bytes: real): string {
        return `${(bytes / 1048576).toFixed(1)} MB`;
    }

    Component.onCompleted: root.refresh()

    Process {
        id: fontProc
        property string finalLine: ""
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("STEP "))
                    root.stepText = line.substring(5);
                else if (line.startsWith("RESULT "))
                    fontProc.finalLine = line.substring(7);
            }
        }
        onStarted: fontProc.finalLine = ""
        onExited: code => {
            root.busy = false;
            let data = null;
            try {
                data = JSON.parse(fontProc.finalLine);
            } catch (error) {
                data = null;
            }
            if (data && data.ok && data.removed !== undefined) {
                root.messageIsError = false;
                root.message = Translation.tr("Removed %1.").arg(data.removed);
                root.needsRestart = true;
            } else if (data && data.ok) {
                root.messageIsError = false;
                const families = data.families.length > 0 ? data.families.join(", ") : data.folder;
                root.message = Translation.tr("Installed %1 (%2 files).").arg(families).arg(data.files);
                root.needsRestart = true;
                googleField.text = "";
                sourceField.text = "";
            } else {
                root.messageIsError = true;
                root.message = data && data.error ? data.error : Translation.tr("That did not work.");
            }
            root.refresh();
            if (root.queue.length > 0 && !(data && !data.ok)) {
                const next = root.queue[0];
                root.queue = root.queue.slice(1);
                root.run(next);
            } else {
                root.queue = [];
            }
        }
    }

    Process {
        id: neededProc
        command: ["python3", Quickshell.shellPath("scripts/deps/envcheck.py"), "fonts"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.needed = JSON.parse(text);
                } catch (error) {
                    root.needed = [];
                }
            }
        }
    }

    Process {
        id: listProc
        command: ["python3", root.script, "list"]
        stdout: SplitParser {
            onRead: line => {
                if (!line.startsWith("RESULT "))
                    return;
                try {
                    root.installed = JSON.parse(line.substring(7)).items;
                } catch (error) {
                    root.installed = [];
                }
            }
        }
    }

    // ── Fonts the shell uses ────────────────────────────────────────────────────
    NoticeBox {
        Layout.fillWidth: true
        visible: root.missingCount > 0
        isFirst: true
        isLast: true
        materialIcon: root.requiredMissing > 0 ? "warning" : "info"
        text: root.requiredMissing > 0
            ? Translation.tr("%1 fonts the shell relies on are not installed, so it is showing a default font in their place. Install them below.").arg(root.requiredMissing)
            : Translation.tr("Some optional fonts are not installed. They are only used by alternate styles and Arabic text.")
    }

    ContentSubsection {
        Layout.fillWidth: true
        title: Translation.tr("Fonts the shell uses")
        icon: "fact_check"
        tooltip: Translation.tr("The families the interface is designed around. A missing one is replaced by a default font, so nothing breaks, but it looks different. Install fetches it from its source into your own fonts folder.")

        RowLayout {
            Layout.fillWidth: true
            visible: root.missingCount > 1
            Item { Layout.fillWidth: true }
            RippleButtonWithIcon {
                enabled: !root.busy
                materialIcon: "download_for_offline"
                mainText: Translation.tr("Install all missing (%1)").arg(root.missingCount)
                onClicked: root.installAllMissing()
            }
        }

        Repeater {
            model: root.needed

            delegate: Rectangle {
                id: neededRow
                required property var modelData

                Layout.fillWidth: true
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2
                implicitHeight: neededLayout.implicitHeight + 20

                RowLayout {
                    id: neededLayout
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 12
                    spacing: 12

                    MaterialSymbol {
                        iconSize: Appearance.font.pixelSize.larger
                        text: neededRow.modelData.ok ? "check_circle" : neededRow.modelData.required ? "error" : "do_not_disturb_on"
                        color: neededRow.modelData.ok ? Appearance.colors.colPrimary
                            : neededRow.modelData.required ? Appearance.colors.colError : Appearance.colors.colSubtext
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText {
                            Layout.fillWidth: true
                            text: neededRow.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: `${neededRow.modelData.ok ? Translation.tr("Installed") : neededRow.modelData.required ? Translation.tr("Missing, required") : Translation.tr("Missing, optional")} · ${neededRow.modelData.feature}`
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }
                    RippleButtonWithIcon {
                        visible: !neededRow.modelData.ok && neededRow.modelData.source.length === 0 && neededRow.modelData.package.length > 0
                        materialIcon: "content_copy"
                        mainText: Translation.tr("Copy install command")
                        onClicked: Quickshell.clipboardText = `sudo pacman -S ${neededRow.modelData.package}`
                    }
                    RippleButtonWithIcon {
                        visible: !neededRow.modelData.ok && neededRow.modelData.source.length > 0
                        enabled: !root.busy
                        materialIcon: "download"
                        mainText: Translation.tr("Install")
                        colBackground: neededRow.modelData.required ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                        colText: neededRow.modelData.required ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        onClicked: root.installNeeded(neededRow.modelData)
                    }
                }
            }
        }
    }

    // ── From Google Fonts ───────────────────────────────────────────────────────
    ContentSubsection {
        Layout.fillWidth: true
        title: Translation.tr("Any other Google font")
        icon: "cloud_download"
        tooltip: Translation.tr("Type the family name as it appears on fonts.google.com, for example Inter, Roboto Slab or Noto Naskh Arabic. Needs the network.")

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialTextField {
                id: googleField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Family name")
                enabled: !root.busy
                onAccepted: root.installGoogle()
            }
            RippleButtonWithIcon {
                enabled: !root.busy && googleField.text.trim().length > 0
                materialIcon: "download"
                mainText: Translation.tr("Install")
                onClicked: root.installGoogle()
            }
        }
    }

    // ── From a file, folder or link ─────────────────────────────────────────────
    ContentSubsection {
        Layout.fillWidth: true
        title: Translation.tr("Your own font file or link")
        icon: "folder_zip"
        tooltip: Translation.tr("A font file (.ttf, .otf, .ttc), a .zip of fonts, a folder that holds some, or a link to one of those. Anything that is not a real font file is skipped.")

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialTextField {
                id: sourceField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Path or link")
                font.family: Appearance.font.family.monospace
                enabled: !root.busy
                onAccepted: root.installSource()
            }
            RippleButtonWithIcon {
                enabled: !root.busy && sourceField.text.trim().length > 0
                materialIcon: "download"
                mainText: Translation.tr("Install")
                onClicked: root.installSource()
            }
        }
    }

    // ── Progress and result ─────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        visible: root.busy
        spacing: 10
        MaterialLoadingIndicator {
            loading: root.busy
            implicitSize: 22
        }
        StyledText {
            Layout.fillWidth: true
            text: root.stepText
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.message.length > 0 && !root.busy
        text: root.message
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.small
        color: root.messageIsError ? Appearance.colors.colError : Appearance.colors.colPrimary
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.needsRestart && !root.busy
        spacing: 10
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("The shell finds fonts when it starts. Restart it to use the change; the Settings window will close and come back in a few seconds.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
        RippleButtonWithIcon {
            materialIcon: "restart_alt"
            mainText: Translation.tr("Restart the shell")
            onClicked: root.restartShell()
        }
    }

    // ── Installed here ──────────────────────────────────────────────────────────
    ContentSubsection {
        Layout.fillWidth: true
        title: Translation.tr("Installed here")
        icon: "inventory_2"

        StyledText {
            Layout.fillWidth: true
            visible: root.installed.length === 0
            text: Translation.tr("Nothing yet. Fonts you install on this page are listed here and can be removed again.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        Repeater {
            model: root.installed

            delegate: Rectangle {
                id: entry
                required property var modelData

                Layout.fillWidth: true
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2
                implicitHeight: entryRow.implicitHeight + 20

                RowLayout {
                    id: entryRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 12
                    spacing: 12

                    MaterialSymbol {
                        iconSize: Appearance.font.pixelSize.larger
                        text: "text_fields"
                        color: Appearance.colors.colSubtext
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText {
                            Layout.fillWidth: true
                            text: entry.modelData.families.length > 0 ? entry.modelData.families.join(", ") : entry.modelData.folder
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: `${Translation.tr("%1 files").arg(entry.modelData.files)} · ${root.megabytes(entry.modelData.bytes)}`
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                    RippleButtonWithIcon {
                        enabled: !root.busy
                        materialIcon: root.confirmRemove === entry.modelData.folder ? "warning" : "delete"
                        mainText: root.confirmRemove === entry.modelData.folder ? Translation.tr("Remove now") : Translation.tr("Remove")
                        colBackground: root.confirmRemove === entry.modelData.folder ? Appearance.colors.colError : Appearance.colors.colLayer3
                        colText: root.confirmRemove === entry.modelData.folder ? Appearance.colors.colOnError : Appearance.colors.colOnLayer2
                        onClicked: {
                            if (root.confirmRemove === entry.modelData.folder)
                                root.run(["remove", entry.modelData.folder]);
                            else
                                root.confirmRemove = entry.modelData.folder;
                        }
                    }
                }
            }
        }
    }
}
