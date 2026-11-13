pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.fileManager

import "Highlighter.js" as Highlighter

/// The editor window's whole interior: tab strip, one CodeView per open file, find bar, status bar.
FocusScope {
    id: root

    signal closeRequested()

    readonly property var cfg: Persistent.states.background.mediaMode
    readonly property string home: Quickshell.env("HOME")
    readonly property int maxBytes: 6 * 1024 * 1024

    property int current: -1
    property string toastText: ""
    property var dialogItem: null
    readonly property var cur: root.current >= 0 && root.current < docs.count ? views.itemAt(root.current) : null

    ListModel { id: docs }

    function toast(t: string): void {
        root.toastText = t;
        toastTimer.restart();
    }
    Timer { id: toastTimer; interval: 2800; onTriggered: root.toastText = "" }

    function baseName(p: string): string { return p.slice(p.lastIndexOf("/") + 1); }
    function prettyPath(p: string): string { return p.startsWith(root.home) ? "~" + p.slice(root.home.length) : p; }
    function resolve(p: string): string {
        let q = p.trim();
        if (q.startsWith("file://")) q = decodeURIComponent(q.slice(7));
        if (q.startsWith("~")) q = root.home + q.slice(1);
        return q;
    }

    // ── documents ──

    function indexOfPath(path: string): int {
        for (let i = 0; i < docs.count; ++i)
            if (docs.get(i).path === path) return i;
        return -1;
    }

    function openFile(path: string, line: int): void {
        const p = root.resolve(path);
        if (p.length === 0) { root.newDoc(); return; }
        let i = root.indexOfPath(p);
        if (i < 0) {
            docs.append({ path: p, name: root.baseName(p), dirty: false, loading: true, failed: "" });
            i = docs.count - 1;
        }
        root.current = i;
        if (line > 0) Qt.callLater(() => { const v = views.itemAt(i); if (v) v.pendingLine = line; });
        Qt.callLater(root.focusEditor);
        root.saveSession();
    }

    function newDoc(): void {
        docs.append({ path: "", name: qsTr("Untitled"), dirty: false, loading: false, failed: "" });
        root.current = docs.count - 1;
        Qt.callLater(root.focusEditor);
    }

    function focusEditor(): void {
        if (root.cur) root.cur.view.editor.forceActiveFocus();
        else root.forceActiveFocus();
    }

    function closeDoc(i: int, force: bool): void {
        if (i < 0 || i >= docs.count) return;
        const d = docs.get(i);
        if (d.dirty && !force) {
            root.current = i;
            root.ask(qsTr("Save changes to “%1”?").arg(d.name), qsTr("Your changes will be lost if you do not save them."), [
                { text: qsTr("Cancel"), kind: "text" },
                { text: qsTr("Discard"), kind: "danger", fn: () => root.closeDoc(i, true) },
                { text: qsTr("Save"), kind: "filled", fn: () => root.saveDoc(i, () => root.closeDoc(i, true)) }
            ]);
            return;
        }
        docs.remove(i);
        if (docs.count === 0) { root.current = -1; root.saveSession(); root.closeRequested(); return; }
        root.current = Math.min(root.current > i ? root.current - 1 : root.current, docs.count - 1);
        root.saveSession();
        Qt.callLater(root.focusEditor);
    }

    // Closing the window with unsaved tabs asks once for all of them
    function dirtyCount(): int {
        let n = 0;
        for (let i = 0; i < docs.count; ++i) if (docs.get(i).dirty) n++;
        return n;
    }
    function requestClose(): void {
        const n = root.dirtyCount();
        if (n === 0) { root.closeRequested(); return; }
        root.ask(qsTr("Close with unsaved changes?"), qsTr("%n file(s) have unsaved changes.", "", n), [
            { text: qsTr("Cancel"), kind: "text" },
            { text: qsTr("Discard"), kind: "danger", fn: () => root.closeRequested() },
            { text: qsTr("Save all"), kind: "filled", fn: () => root.saveAll(() => root.closeRequested()) }
        ]);
    }

    function saveDoc(i: int, then): void {
        const d = docs.get(i), v = views.itemAt(i);
        if (!v) return;
        if (d.path === "") { root.saveAs(i, then); return; }
        v.save(then);
    }

    function saveAll(then): void {
        const todo = [];
        for (let i = 0; i < docs.count; ++i) if (docs.get(i).dirty) todo.push(i);
        const step = () => {
            if (todo.length === 0) { if (then) then(); return; }
            root.saveDoc(todo.shift(), step);
        };
        step();
    }

    function saveAs(i: int, then): void {
        const d = docs.get(i);
        root.prompt(qsTr("Save as"), qsTr("Path"), d.path !== "" ? root.prettyPath(d.path) : "~/untitled.txt", qsTr("Save"), p => {
            const path = root.resolve(p);
            if (path.length === 0 || path.endsWith("/")) return;
            const v = views.itemAt(i);
            const exists = root.indexOfPath(path) >= 0 && root.indexOfPath(path) !== i;
            if (exists) { root.toast(qsTr("That file is open in another tab")); return; }
            docs.setProperty(i, "path", path);
            docs.setProperty(i, "name", root.baseName(path));
            v.view.lang = Highlighter.languageFor(root.baseName(path));
            v.save(then);
            root.saveSession();
        });
    }

    function openPrompt(): void {
        const start = root.cur && docs.get(root.current).path !== "" ? root.prettyPath(docs.get(root.current).path.replace(/[^/]*$/, "")) : "~/";
        root.prompt(qsTr("Open file"), qsTr("Path"), start, qsTr("Open"), p => root.openFile(p, 0), false);
    }

    function saveSession(): void {
        const out = [];
        for (let i = 0; i < docs.count; ++i)
            if (docs.get(i).path !== "") out.push(docs.get(i).path);
        root.cfg.edSession = out;
    }

    function restoreSession(): void {
        if (docs.count > 0) return;
        for (const p of root.cfg.edSession) root.openFile(p, 0);
        if (docs.count === 0) root.newDoc();
    }

    // ── dialogs ──

    function closeDialog(): void {
        if (root.dialogItem) { root.dialogItem.destroy(); root.dialogItem = null; }
        Qt.callLater(root.focusEditor);
    }

    function prompt(title: string, label: string, text: string, confirm: string, fn, selectBase = true): void {
        root.closeDialog();
        const it = promptComp.createObject(dialogHost, { title: title, label: label, text: text, confirmText: confirm, selectBase: selectBase });
        it.accepted.connect(t => { root.closeDialog(); fn(t); });
        it.closed.connect(root.closeDialog);
        root.dialogItem = it;
    }

    function ask(title: string, message: string, buttons: var): void {
        root.closeDialog();
        const it = askComp.createObject(dialogHost, { title: title, message: message, buttons: buttons });
        it.closed.connect(root.closeDialog);
        it.picked.connect(b => { root.closeDialog(); if (b.fn) b.fn(); });
        root.dialogItem = it;
    }

    Component { id: promptComp; PromptDialog {} }
    Component {
        id: askComp
        FmDialog {
            id: dlg
            property string message: ""
            property var buttons: []
            signal picked(var button)
            cardWidth: 460
            StyledText {
                Layout.fillWidth: true
                text: dlg.message
                wrapMode: Text.WordWrap
                font.pixelSize: 14
                color: ClockStyle.colOnSurfaceVariant
            }
            actions: [
                Repeater {
                    model: dlg.buttons
                    delegate: FmButton {
                        required property var modelData
                        text: modelData.text
                        kind: modelData.kind
                        onClicked: modelData.fn ? dlg.picked(modelData) : dlg.close()
                    }
                }
            ]
        }
    }

    // ── find ──

    property var matches: []
    property int matchIndex: -1
    property bool badRegex: false

    function findRegex(): var {
        const q = find.findText;
        if (q.length === 0) return null;
        const src = find.useRegex ? q : q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        return new RegExp(src, find.matchCase ? "gm" : "gim");
    }

    function refind(fromCursor: bool): void {
        const v = root.cur;
        root.badRegex = false;
        if (!v || !find.visible || find.findText.length === 0) { root.matches = []; root.matchIndex = -1; return; }
        let re = null;
        try { re = root.findRegex(); } catch (e) { root.badRegex = true; root.matches = []; root.matchIndex = -1; return; }
        const t = v.view.getText(), out = [];
        let m;
        while ((m = re.exec(t)) !== null && out.length < 5000) {
            if (m[0].length === 0) { re.lastIndex++; continue; }
            out.push({ start: m.index, end: m.index + m[0].length });
        }
        root.matches = out;
        if (out.length === 0) { root.matchIndex = -1; return; }
        if (fromCursor) {
            const pos = Math.min(v.view.editor.selectionStart, v.view.editor.selectionEnd);
            let k = out.findIndex(x => x.start >= pos);
            root.matchIndex = k < 0 ? 0 : k;
        } else {
            root.matchIndex = Math.min(Math.max(root.matchIndex, 0), out.length - 1);
        }
    }

    function showMatch(): void {
        const v = root.cur;
        if (!v || root.matchIndex < 0) return;
        const m = root.matches[root.matchIndex];
        v.view.selectRange(m.start, m.end);
    }

    function stepMatch(dir: int): void {
        if (root.matches.length === 0) { root.refind(true); if (root.matches.length === 0) return; }
        else root.matchIndex = (root.matchIndex + dir + root.matches.length) % root.matches.length;
        root.showMatch();
    }

    function openFind(replace: bool): void {
        find.visible = true;
        if (replace) find.replaceMode = true;
        const v = root.cur;
        if (v) {
            const sel = v.view.editor.selectedText;
            if (sel.length > 0 && sel.indexOf(" ") < 0 && sel.length < 200) find.findText = sel;
        }
        root.refind(true);
        find.focusFind();
    }

    function replaceOne(): void {
        const v = root.cur;
        if (!v || v.view.readOnly) return;
        const ed = v.view.editor;
        const s = Math.min(ed.selectionStart, ed.selectionEnd), e2 = Math.max(ed.selectionStart, ed.selectionEnd);
        const hit = root.matches.findIndex(m => m.start === s && m.end === e2);
        if (hit < 0) { root.refind(true); root.showMatch(); return; }
        let rep = find.replaceText;
        if (find.useRegex) {
            try { rep = ed.selectedText.replace(root.findRegex(), rep).toString(); } catch (e) { return; }
            // a single regex match was selected, so the replace above ran on exactly that
        }
        v.view.replaceRange(s, e2, rep);
        root.refind(true);
        root.showMatch();
    }

    function replaceAll(): void {
        const v = root.cur;
        if (!v || v.view.readOnly || find.findText.length === 0) return;
        let re;
        try { re = root.findRegex(); } catch (e) { return; }
        const t = v.view.getText();
        const n = root.matches.length;
        const out = t.replace(re, find.useRegex ? find.replaceText : () => find.replaceText);
        if (out === t) return;
        v.view.replaceRange(0, t.length, out);
        root.refind(false);
        root.toast(qsTr("Replaced %n occurrence(s)", "", n));
    }

    onCurChanged: root.refind(true)

    // ── keyboard ──

    Keys.onPressed: e => {
        const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
        if (!ctrl) {
            if (e.key === Qt.Key_Escape && find.visible) { find.visible = false; root.focusEditor(); e.accepted = true; }
            return;
        }
        let ok = true;
        switch (e.key) {
        case Qt.Key_S: if (shift) root.saveAs(root.current, null); else root.saveDoc(root.current, null); break;
        case Qt.Key_O: root.openPrompt(); break;
        case Qt.Key_N: root.newDoc(); break;
        case Qt.Key_W: root.closeDoc(root.current, false); break;
        case Qt.Key_T: root.newDoc(); break;
        case Qt.Key_F: root.openFind(false); break;
        case Qt.Key_H: root.openFind(true); break;
        case Qt.Key_G:
            if (find.visible && find.findText.length > 0) root.stepMatch(shift ? -1 : 1);
            else root.gotoPrompt();
            break;
        case Qt.Key_L: root.gotoPrompt(); break;
        case Qt.Key_Tab: root.switchTab(1); break;
        case Qt.Key_Backtab: root.switchTab(-1); break;
        case Qt.Key_Plus: case Qt.Key_Equal: root.cfg.edFontSize = Math.min(32, root.cfg.edFontSize + 1); break;
        case Qt.Key_Minus: root.cfg.edFontSize = Math.max(8, root.cfg.edFontSize - 1); break;
        case Qt.Key_0: root.cfg.edFontSize = 14; break;
        case Qt.Key_Q: root.requestClose(); break;
        default: ok = false;
        }
        if (ok) e.accepted = true;
    }

    function switchTab(d: int): void {
        if (docs.count < 2) return;
        root.current = (root.current + d + docs.count) % docs.count;
        Qt.callLater(root.focusEditor);
    }

    function gotoPrompt(): void {
        const v = root.cur;
        if (!v) return;
        root.prompt(qsTr("Go to line"), qsTr("Line number, or line:column (1–%1)").arg(v.view.lineCount), String(v.view.cursorLine + 1), qsTr("Go"), t => {
            const m = t.trim().match(/^(\d+)(?:\s*[:,]\s*(\d+))?$/);
            if (m) v.view.goToLine(parseInt(m[1]) - 1, m[2] ? parseInt(m[2]) - 1 : 0);
        }, false);
    }

    Component.onCompleted: {
        if (GlobalStates.editorPath !== "") root.openFile(GlobalStates.editorPath, GlobalStates.editorLine);
        else root.restoreSession();
    }

    Connections {
        target: GlobalStates
        function onEditorRequestChanged(): void {
            if (GlobalStates.editorPath !== "") root.openFile(GlobalStates.editorPath, GlobalStates.editorLine);
            else if (docs.count === 0) root.restoreSession();
        }
    }

    // ── layout ──

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // tab strip + actions
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            spacing: 6

            Flickable {
                id: tabFlick
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                contentWidth: tabRow.implicitWidth
                clip: true
                interactive: contentWidth > width
                boundsBehavior: Flickable.StopAtBounds
                Row {
                    id: tabRow
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: docs
                        delegate: Rectangle {
                            id: tab
                            required property var model
                            required property int index
                            readonly property bool active: tab.index === root.current
                            width: Math.min(220, Math.max(120, tabLabel.implicitWidth + 74))
                            height: 36
                            radius: 18
                            color: tab.active ? ClockStyle.colSecondaryContainer : (tabArea.containsMouse ? ClockStyle.colSurfaceHover : "transparent")
                            MouseArea {
                                id: tabArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                onClicked: m => {
                                    if (m.button === Qt.MiddleButton) root.closeDoc(tab.index, false);
                                    else { root.current = tab.index; root.focusEditor(); }
                                }
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 6
                                spacing: 6
                                MaterialSymbol {
                                    text: tab.model.failed !== "" ? "error" : "description"
                                    iconSize: 17
                                    fill: tab.active ? 1 : 0
                                    color: tab.model.failed !== "" ? ClockStyle.colError : tab.active ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                                }
                                StyledText {
                                    id: tabLabel
                                    Layout.fillWidth: true
                                    text: tab.model.name
                                    elide: Text.ElideMiddle
                                    font.pixelSize: 13
                                    font.weight: tab.active ? Font.DemiBold : Font.Normal
                                    color: tab.active ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                                }
                                // dirty dot, turns into the close button on hover
                                Item {
                                    Layout.preferredWidth: 24
                                    Layout.preferredHeight: 24
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 8; height: 8; radius: 4
                                        visible: tab.model.dirty && !closeBtn.hovered
                                        color: ClockStyle.colPrimary
                                    }
                                    FmIconButton {
                                        id: closeBtn
                                        anchors.fill: parent
                                        size: 24; iconSize: 15
                                        symbol: "close"
                                        opacity: tab.model.dirty ? (hovered || tab.active ? 1 : 0) : 1
                                        visible: !tab.model.dirty || hovered
                                        onClicked: root.closeDoc(tab.index, false)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            FmIconButton { size: 34; iconSize: 20; symbol: "add"; tip: qsTr("New file (Ctrl+N)"); onClicked: root.newDoc() }
            FmIconButton { size: 34; iconSize: 20; symbol: "folder_open"; tip: qsTr("Open (Ctrl+O)"); onClicked: root.openPrompt() }
            FmIconButton {
                size: 34; iconSize: 20; symbol: "save"; tip: qsTr("Save (Ctrl+S)")
                enabled2: root.cur !== null && root.current >= 0 && docs.get(root.current).dirty
                onClicked: root.saveDoc(root.current, null)
            }
            FmIconButton { size: 34; iconSize: 20; symbol: "search"; tip: qsTr("Find (Ctrl+F)"); active: find.visible; onClicked: root.openFind(false) }
            FmIconButton { id: moreBtn; size: 34; iconSize: 20; symbol: "more_vert"; tip: qsTr("More"); onClicked: root.moreMenu() }
        }

        FindBar {
            id: find
            visible: false
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            Layout.bottomMargin: 8
            count: root.matches.length
            index: root.matchIndex
            invalid: root.badRegex
            onChanged: { root.refind(true); root.showMatch(); }
            onNext: root.stepMatch(1)
            onPrevious: root.stepMatch(-1)
            onReplaceOne: root.replaceOne()
            onReplaceAll: root.replaceAll()
            onCloseRequested: { find.visible = false; root.focusEditor(); }
        }

        // the editors
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            radius: 24
            color: ClockStyle.colSurface
            clip: true

            Repeater {
                id: views
                model: docs
                delegate: Item {
                    id: pane
                    required property var model
                    required property int index
                    readonly property alias view: cv
                    property int pendingLine: 0
                    property bool crlf: false
                    property bool ready: false
                    property string saved: ""
                    property var afterSave: null
                    anchors.fill: parent
                    visible: pane.index === root.current

                    function save(then): void {
                        const text = cv.getText();
                        pane.afterSave = then;
                        file.setText(pane.crlf ? text.replace(/\n/g, "\r\n") : text);
                        pane.saved = text;
                    }

                    FileView {
                        id: file
                        path: pane.model.path
                        // A file that does not exist yet is created by the first save
                        atomicWrites: true
                        printErrors: false
                        blockLoading: false
                        onLoaded: {
                            // Saving under a new name re-points the view at a file already shown
                            if (pane.ready) return;
                            pane.ready = true;
                            let t = file.text();
                            if (t.length > root.maxBytes) {
                                docs.setProperty(pane.index, "failed", qsTr("This file is larger than %1 MB").arg(Math.round(root.maxBytes / 1048576)));
                                docs.setProperty(pane.index, "loading", false);
                                return;
                            }
                            pane.crlf = t.indexOf("\r\n") >= 0;
                            if (pane.crlf) t = t.replace(/\r\n/g, "\n");
                            pane.saved = t;
                            cv.loadedText = t;
                            cv.setText(t);
                            cv.editor.deselect();
                            docs.setProperty(pane.index, "loading", false);
                            docs.setProperty(pane.index, "dirty", false);
                            if (pane.pendingLine > 0) cv.goToLine(pane.pendingLine - 1, 0);
                            if (pane.index === root.current) root.focusEditor();
                        }
                        onLoadFailed: error => {
                            // A missing file opens as an empty new document at that path
                            docs.setProperty(pane.index, "loading", false);
                            pane.ready = true;
                            if (error === FileViewError.FileNotFound) {
                                docs.setProperty(pane.index, "failed", "");
                            } else {
                                docs.setProperty(pane.index, "failed", qsTr("Cannot read this file"));
                            }
                        }
                        onSaved: {
                            docs.setProperty(pane.index, "dirty", cv.getText() !== pane.saved);
                            if (!docs.get(pane.index).dirty) root.toast(qsTr("Saved %1").arg(pane.model.name));
                            const f = pane.afterSave;
                            pane.afterSave = null;
                            if (f) f();
                        }
                        onSaveFailed: error => {
                            root.toast(qsTr("Could not save %1").arg(pane.model.name));
                            pane.afterSave = null;
                        }
                    }

                    CodeView {
                        id: cv
                        anchors.fill: parent
                        property string loadedText: ""
                        lang: Highlighter.languageFor(pane.model.name)
                        wrap: root.cfg.edWrap
                        lineNumbers: root.cfg.edLineNumbers
                        fontSize: root.cfg.edFontSize
                        tabSize: root.cfg.edTabSize
                        fontFamily: Appearance.font.family.monospace
                        readOnly: pane.model.failed !== "" || pane.model.loading
                        matches: pane.index === root.current ? root.matches : []
                        currentMatch: root.matchIndex
                        colBg: ClockStyle.colSurface
                        colGutter: ClockStyle.colSurface
                        colGutterText: ClockStyle.colSubtext
                        colGutterActive: ClockStyle.colOnSurface
                        colText: ClockStyle.colOnSurface
                        colCaret: ClockStyle.colPrimary
                        colSelection: Qt.rgba(ClockStyle.colPrimary.r, ClockStyle.colPrimary.g, ClockStyle.colPrimary.b, 0.32)
                        colLine: Qt.rgba(ClockStyle.colOnSurface.r, ClockStyle.colOnSurface.g, ClockStyle.colOnSurface.b, 0.05)
                        colMatch: Qt.rgba(ClockStyle.colTertiary.r, ClockStyle.colTertiary.g, ClockStyle.colTertiary.b, 0.30)
                        colMatchActive: Qt.rgba(ClockStyle.colTertiary.r, ClockStyle.colTertiary.g, ClockStyle.colTertiary.b, 0.65)
                        syntax: root.syntaxColors
                        onEdited: {
                            if (!pane.model.loading)
                                docs.setProperty(pane.index, "dirty", cv.getText() !== pane.saved);
                            if (pane.index === root.current && find.visible) root.refind(false);
                        }
                    }

                    // Shown instead of text when a file cannot be opened
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: pane.model.failed !== ""
                        spacing: 8
                        MaterialSymbol { Layout.alignment: Qt.AlignHCenter; text: "error"; iconSize: 40; color: ClockStyle.colError }
                        StyledText { Layout.alignment: Qt.AlignHCenter; text: pane.model.failed; font.pixelSize: 15; color: ClockStyle.colOnSurface }
                        StyledText { Layout.alignment: Qt.AlignHCenter; text: root.prettyPath(pane.model.path); font.pixelSize: 12; color: ClockStyle.colSubtext }
                    }
                }
            }

            // nothing open
            ColumnLayout {
                anchors.centerIn: parent
                visible: docs.count === 0
                spacing: 10
                MaterialSymbol { Layout.alignment: Qt.AlignHCenter; text: "edit_note"; iconSize: 48; color: ClockStyle.colSubtext }
                FmButton { Layout.alignment: Qt.AlignHCenter; text: qsTr("New file"); kind: "tonal"; onClicked: root.newDoc() }
            }
        }

        // status bar
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            spacing: 18
            StyledText {
                Layout.fillWidth: true
                text: root.cur ? (docs.get(root.current).path !== "" ? root.prettyPath(docs.get(root.current).path) : qsTr("Unsaved file")) : ""
                elide: Text.ElideMiddle
                font.pixelSize: 12
                color: ClockStyle.colSubtext
            }
            StyledText {
                visible: root.cur !== null && root.cur.view.selectedLength > 0
                text: qsTr("%1 selected").arg(root.cur ? root.cur.view.selectedLength : 0)
                font.pixelSize: 12
                color: ClockStyle.colSubtext
            }
            StyledText {
                text: root.cur ? qsTr("Ln %1, Col %2").arg(root.cur.view.cursorLine + 1).arg(root.cur.view.cursorColumn + 1) : ""
                font.pixelSize: 12
                color: ClockStyle.colSubtext
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.gotoPrompt() }
            }
            StyledText {
                text: root.cur ? Highlighter.languageName(root.cur.view.lang) : ""
                font.pixelSize: 12
                color: ClockStyle.colSubtext
            }
            StyledText {
                text: root.cur ? (root.cur.crlf ? "CRLF" : "LF") + " · UTF-8" : ""
                font.pixelSize: 12
                color: ClockStyle.colSubtext
            }
        }
    }

    readonly property var syntaxColors: ({
        comment: ClockStyle.colSubtext.toString(),
        string: ClockStyle.colTertiary.toString(),
        keyword: ClockStyle.colPrimary.toString(),
        number: Qt.lighter(ClockStyle.colTertiary, 1.15).toString(),
        function: Appearance.colors.colSecondary.toString(),
        constant: Qt.lighter(ClockStyle.colPrimary, 1.2).toString(),
        type: Qt.lighter(Appearance.colors.colSecondary, 1.15).toString(),
        decorator: ClockStyle.colSubtext.toString(),
        tag: ClockStyle.colPrimary.toString(),
        attr: Appearance.colors.colSecondary.toString()
    })

    // ── menu ──

    FmMenu {
        id: menu
        onTriggered: item => root.onMenu(item)
        onClosed: root.focusEditor()
    }

    function moreMenu(): void {
        const p = moreBtn.mapToItem(root, 0, moreBtn.height + 4);
        menu.popup([
            { id: "wrap", text: qsTr("Word wrap"), icon: "wrap_text", checked: root.cfg.edWrap },
            { id: "lines", text: qsTr("Line numbers"), icon: "format_list_numbered", checked: root.cfg.edLineNumbers },
            { separator: true },
            { id: "tab2", text: qsTr("Indent: 2 spaces"), checked: root.cfg.edTabSize === 2 },
            { id: "tab4", text: qsTr("Indent: 4 spaces"), checked: root.cfg.edTabSize === 4 },
            { id: "tab8", text: qsTr("Indent: 8 spaces"), checked: root.cfg.edTabSize === 8 },
            { separator: true },
            { id: "goto", text: qsTr("Go to line…"), icon: "pin", shortcut: "Ctrl+G" },
            { id: "replace", text: qsTr("Find and replace"), icon: "find_replace", shortcut: "Ctrl+H" },
            { id: "saveas", text: qsTr("Save as…"), icon: "save_as", shortcut: "Ctrl+Shift+S" },
            { id: "reveal", text: qsTr("Show in Files"), icon: "folder", disabled: !root.cur || docs.get(root.current).path === "" },
            { id: "saveall", text: qsTr("Save all"), icon: "save" }
        ], p.x - 190, p.y);
    }

    function onMenu(item: var): void {
        switch (item.id) {
        case "wrap": root.cfg.edWrap = !root.cfg.edWrap; break;
        case "lines": root.cfg.edLineNumbers = !root.cfg.edLineNumbers; break;
        case "tab2": root.cfg.edTabSize = 2; break;
        case "tab4": root.cfg.edTabSize = 4; break;
        case "tab8": root.cfg.edTabSize = 8; break;
        case "goto": root.gotoPrompt(); break;
        case "replace": root.openFind(true); break;
        case "saveas": root.saveAs(root.current, null); break;
        case "saveall": root.saveAll(null); break;
        case "reveal": GlobalStates.openFileManagerApp(docs.get(root.current).path); break;
        }
    }

    Rectangle {
        visible: root.toastText.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 52
        implicitWidth: toastLabel.implicitWidth + 36
        implicitHeight: 40
        radius: 20
        color: ClockStyle.colSurfaceHighest
        StyledText { id: toastLabel; anchors.centerIn: parent; text: root.toastText; font.pixelSize: 14; color: ClockStyle.colOnSurface }
    }

    Item { id: dialogHost; anchors.fill: parent; z: 900 }
}
