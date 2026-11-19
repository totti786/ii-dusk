pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

import "Highlighter.js" as Highlighter

/**
 * The editing surface: a TextEdit with transparent glyphs lying over a Text that draws the same
 * document syntax-highlighted, a line-number gutter, the current-line band and find matches.
 * It knows nothing of files or the shell; the owner feeds it text and colours.
 */
Item {
    id: root

    property string text: ""
    property string lang: "plain"
    property real fontSize: 14
    property string fontFamily: "monospace"
    property bool wrap: false
    property int tabSize: 4
    property bool readOnly: false
    property bool lineNumbers: true
    property var matches: []          // [{start, end}] find hits
    property int currentMatch: -1

    // Colours (the owner passes the palette)
    property color colBg: "#1e1e24"
    property color colGutter: "#1e1e24"
    property color colGutterText: "#6a6a78"
    property color colGutterActive: "#c8c8d8"
    property color colText: "#e0e0e8"
    property color colLine: "#0cffffff"
    property color colSelection: "#605a7bd8"
    property color colCaret: "#e0e0e8"
    property color colMatch: "#44e8b84a"
    property color colMatchActive: "#99e8b84a"
    property var syntax: ({ comment: "#7c7c8c", string: "#8fc48f", keyword: "#c792ea", number: "#f0a060", function: "#82aaff",
        constant: "#f07178", type: "#ffcb6b", decorator: "#9aa5a0", tag: "#f07178", attr: "#ffcb6b" })

    readonly property alias editor: edit
    readonly property alias flick: flick
    readonly property int cursorPosition: edit.cursorPosition
    readonly property int length: edit.length
    readonly property bool canUndo: edit.canUndo
    readonly property bool canRedo: edit.canRedo
    property int lineCount: 1
    property int cursorLine: 0
    property int cursorColumn: 0
    property int selectedLength: 0
    property var lineStarts: [0]

    readonly property real charWidth: metrics.advanceWidth
    readonly property real lineHeight: metrics.height
    // Pitch of one row as the editor lays it out (measured, since it is fractional)
    readonly property real rowHeight: {
        const h = probe.contentHeight;   // re-measure whenever the probe is laid out
        const pitch = probe.positionToRectangle(2).y - probe.positionToRectangle(0).y;
        return pitch > 1 ? pitch : Math.max(1, h / 2, root.lineHeight);
    }
    readonly property real gutterWidth: root.lineNumbers ? Math.max(48, String(root.lineCount).length * root.charWidth + 34) : 12

    signal edited()
    signal saveRequested()

    TextEdit {
        id: probe
        visible: false
        text: "x\nx"
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
    }
    TextMetrics { id: metrics; font.family: root.fontFamily; font.pixelSize: root.fontSize; text: "M" }

    // ── document ──

    function setText(t: string): void {
        edit.text = t;
        edit.cursorPosition = 0;
        flick.contentY = 0;
        flick.contentX = 0;
    }

    function getText(): string { return edit.text; }

    function lineAt(pos: int): int {
        const ls = root.lineStarts;
        let lo = 0, hi = ls.length - 1;
        while (lo < hi) {
            const mid = (lo + hi + 1) >> 1;
            if (ls[mid] <= pos) lo = mid; else hi = mid - 1;
        }
        return lo;
    }

    function lineStart(line: int): int { return root.lineStarts[Math.max(0, Math.min(line, root.lineStarts.length - 1))]; }

    function lineEnd(line: int): int {
        const next = line + 1 < root.lineStarts.length ? root.lineStarts[line + 1] - 1 : edit.length;
        return next;
    }

    function recount(): void {
        const t = edit.text;
        const ls = [0];
        for (let i = t.indexOf("\n"); i >= 0; i = t.indexOf("\n", i + 1))
            ls.push(i + 1);
        root.lineStarts = ls;
        root.lineCount = ls.length;
    }

    function goToLine(line: int, column: int): void {
        const l = Math.max(0, Math.min(line, root.lineStarts.length - 1));
        edit.cursorPosition = Math.min(root.lineStart(l) + Math.max(0, column), root.lineEnd(l));
        edit.forceActiveFocus();
        root.ensureCursorVisible(true);
    }

    function selectRange(a: int, b: int): void {
        edit.select(a, b);
        root.ensureCursorVisible(true);
    }

    function ensureCursorVisible(center: bool): void {
        const r = edit.cursorRectangle;
        if (center && (r.y < flick.contentY || r.y + r.height > flick.contentY + flick.height))
            flick.contentY = Math.max(0, Math.min(r.y - flick.height / 2, flick.contentHeight - flick.height));
        else if (r.y < flick.contentY)
            flick.contentY = r.y;
        else if (r.y + r.height > flick.contentY + flick.height)
            flick.contentY = r.y + r.height - flick.height;
        if (!root.wrap) {
            if (r.x < flick.contentX + 20)
                flick.contentX = Math.max(0, r.x - 40);
            else if (r.x > flick.contentX + flick.width - 30)
                flick.contentX = r.x - flick.width + 60;
        }
    }

    // Replace a span as one undoable edit (selection, then insert) and put the caret after it
    function replaceRange(a: int, b: int, s: string): void {
        edit.select(a, b);
        edit.remove(a, b);
        edit.insert(a, s);
        edit.cursorPosition = a + s.length;
    }


    // ── editing commands ──

    function indentUnit(): string { return "    ".slice(0, root.tabSize); }

    function commentPrefix(): string { return Highlighter.commentPrefix(root.lang); }

    // Lines touched by the selection (or the caret line): [first, last]
    function selectedLines(): var {
        const a = Math.min(edit.selectionStart, edit.selectionEnd), b = Math.max(edit.selectionStart, edit.selectionEnd);
        const first = root.lineAt(a);
        let last = root.lineAt(b);
        if (b > a && b === root.lineStart(last) && last > first) last--;
        return [first, last];
    }

    // Replace whole lines [first,last] with `s` (no trailing newline) and select the result
    function replaceLines(first: int, last: int, s: string, keepSel: bool): void {
        const a = root.lineStart(first), b = root.lineEnd(last);
        root.replaceRange(a, b, s);
        if (keepSel) edit.select(a, a + s.length);
    }

    function indentLines(out: bool): void {
        const [first, last] = root.selectedLines();
        const unit = root.indentUnit();
        const t = edit.text, lines = [];
        for (let l = first; l <= last; ++l) {
            const ln = t.slice(root.lineStart(l), root.lineEnd(l));
            if (!out) lines.push(ln.length > 0 ? unit + ln : ln);
            else if (ln.startsWith("\t")) lines.push(ln.slice(1));
            else {
                let n = 0;
                while (n < root.tabSize && ln[n] === " ") n++;
                lines.push(ln.slice(n));
            }
        }
        root.replaceLines(first, last, lines.join("\n"), true);
    }

    function toggleComment(): void {
        const pre = root.commentPrefix();
        if (!pre) return;
        const [first, last] = root.selectedLines();
        const t = edit.text, src = [];
        for (let l = first; l <= last; ++l) src.push(t.slice(root.lineStart(l), root.lineEnd(l)));
        const live = src.filter(x => x.trim().length > 0);
        const allCommented = live.length > 0 && live.every(x => x.trimStart().startsWith(pre));
        let minIndent = Infinity;
        for (const x of live) minIndent = Math.min(minIndent, x.length - x.trimStart().length);
        if (!isFinite(minIndent)) minIndent = 0;
        const out = src.map(x => {
            if (x.trim().length === 0) return x;
            if (allCommented) {
                const i = x.length - x.trimStart().length;
                let rest = x.slice(i + pre.length);
                if (rest.startsWith(" ")) rest = rest.slice(1);
                return x.slice(0, i) + rest;
            }
            return x.slice(0, minIndent) + pre + " " + x.slice(minIndent);
        });
        root.replaceLines(first, last, out.join("\n"), true);
    }

    function duplicateLines(): void {
        const [first, last] = root.selectedLines();
        const a = root.lineStart(first), b = root.lineEnd(last);
        const block = edit.text.slice(a, b);
        edit.insert(b, "\n" + block);
        edit.select(b + 1, b + 1 + block.length);
    }

    function deleteLines(): void {
        const [first, last] = root.selectedLines();
        let a = root.lineStart(first), b = root.lineEnd(last);
        if (b < edit.length) b++;
        else if (a > 0) a--;
        edit.remove(a, b);
        edit.cursorPosition = Math.min(a, edit.length);
    }

    function moveLines(dir: int): void {
        const [first, last] = root.selectedLines();
        const other = first + dir;
        const lastOther = last + dir;
        if (dir < 0 && first === 0) return;
        if (dir > 0 && last >= root.lineCount - 1) return;
        const t = edit.text;
        const blockText = t.slice(root.lineStart(first), root.lineEnd(last));
        if (dir < 0) {
            const prev = t.slice(root.lineStart(other), root.lineEnd(other));
            const a = root.lineStart(other);
            root.replaceRange(a, root.lineEnd(last), blockText + "\n" + prev);
            edit.select(a, a + blockText.length);
        } else {
            const next = t.slice(root.lineStart(lastOther), root.lineEnd(lastOther));
            const a = root.lineStart(first);
            root.replaceRange(a, root.lineEnd(lastOther), next + "\n" + blockText);
            edit.select(a + next.length + 1, a + next.length + 1 + blockText.length);
        }
    }

    readonly property var pairs: ({ "(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`" })

    // Called from the editor's key handler; true if the key was consumed
    function handleKey(e): bool {
        if (root.readOnly) return false;
        const ctrl = e.modifiers & Qt.ControlModifier, alt = e.modifiers & Qt.AltModifier, shift = e.modifiers & Qt.ShiftModifier;
        if (e.key === Qt.Key_Tab && !ctrl && !alt) {
            if (edit.selectedText.indexOf("\n") >= 0 || edit.selectedText.indexOf("\u2029") >= 0) {
                root.indentLines(false);
            } else {
                const a = edit.selectionStart;
                edit.remove(a, edit.selectionEnd);
                edit.insert(a, root.indentUnit());
                edit.cursorPosition = a + root.indentUnit().length;
            }
            return true;
        }
        if (e.key === Qt.Key_Backtab) { root.indentLines(true); return true; }
        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !ctrl && !alt) {
            const pos = edit.selectionStart;
            const line = root.lineAt(pos);
            const before = edit.text.slice(root.lineStart(line), pos);
            let indent = before.match(/^[ \t]*/)[0];
            const trimmed = before.trimEnd();
            const open = trimmed.slice(-1);
            const after = edit.text.slice(edit.selectionEnd, edit.selectionEnd + 1);
            const opens = "{[(:".indexOf(open) >= 0 && (open !== ":" || root.lang === "python" || root.lang === "yaml");
            edit.remove(edit.selectionStart, edit.selectionEnd);
            if (opens && root.pairs[open] === after && open !== ":") {
                edit.insert(pos, "\n" + indent + root.indentUnit() + "\n" + indent);
                edit.cursorPosition = pos + 1 + indent.length + root.indentUnit().length;
            } else {
                if (opens) indent += root.indentUnit();
                edit.insert(pos, "\n" + indent);
                edit.cursorPosition = pos + 1 + indent.length;
            }
            return true;
        }
        if (ctrl && e.key === Qt.Key_Slash) { root.toggleComment(); return true; }
        if (ctrl && !shift && e.key === Qt.Key_D) { root.duplicateLines(); return true; }
        if (ctrl && shift && e.key === Qt.Key_K) { root.deleteLines(); return true; }
        if (alt && !ctrl && (e.key === Qt.Key_Up || e.key === Qt.Key_Down)) { root.moveLines(e.key === Qt.Key_Up ? -1 : 1); return true; }
        if (!ctrl && !alt && e.text.length === 1) {
            const ch = e.text;
            const pos = edit.cursorPosition;
            const next = edit.text.slice(pos, pos + 1);
            if (edit.selectedText.length > 0 && root.pairs[ch] !== undefined) {
                const a = edit.selectionStart, b = edit.selectionEnd, sel = edit.selectedText;
                root.replaceRange(a, b, ch + sel + root.pairs[ch]);
                edit.select(a + 1, a + 1 + sel.length);
                return true;
            }
            const closers = ")]}\"'`";
            if (closers.indexOf(ch) >= 0 && next === ch) { edit.cursorPosition = pos + 1; return true; }
            if (root.pairs[ch] !== undefined) {
                const prev = edit.text.slice(pos - 1, pos);
                const quote = ch === "\"" || ch === "'" || ch === "`";
                // Quotes stay single next to a word (apostrophes, string prefixes)
                if (quote && /\w/.test(prev)) return false;
                if (next === "" || /[\s)\]}.,;:]/.test(next)) {
                    edit.insert(pos, ch + root.pairs[ch]);
                    edit.cursorPosition = pos + 1;
                    return true;
                }
            }
        }
        if (e.key === Qt.Key_Backspace && !ctrl && edit.selectedText.length === 0) {
            const pos = edit.cursorPosition;
            const prev = edit.text.slice(pos - 1, pos), next = edit.text.slice(pos, pos + 1);
            if (prev && root.pairs[prev] === next) { edit.remove(pos - 1, pos + 1); return true; }
        }
        return false;
    }

    // ── highlighted layer ──

    property string html: ""
    Timer {
        id: hlTimer
        interval: 25
        onTriggered: root.rehighlight()
    }
    function rehighlight(): void {
        const t = edit.text;
        // Beyond ~400 KB the highlighter would stall typing, so such files stay plain
        root.html = t.length > 400000 ? "" : Highlighter.highlight(t, root.lang, root.syntax, root.tabSize);
        root.highlightOff = t.length > 400000;
    }
    property bool highlightOff: false
    onLangChanged: hlTimer.restart()
    onSyntaxChanged: hlTimer.restart()
    onTabSizeChanged: hlTimer.restart()

    Rectangle { anchors.fill: parent; color: root.colBg }

    // ── gutter ──

    Rectangle {
        id: gutter
        visible: root.lineNumbers
        width: root.gutterWidth
        height: parent.height
        color: root.colGutter
        clip: true

        Repeater {
            model: root.lineNumbers ? root.visibleLines.length : 0
            delegate: Text {
                required property int index
                readonly property int line: root.visibleLines[index] ?? 0
                x: 0
                width: gutter.width - 14
                y: root.lineY(line) - flick.contentY + edit.topPadding
                horizontalAlignment: Text.AlignRight
                text: line + 1
                font.family: root.fontFamily
                font.pixelSize: root.fontSize - 1
                color: line === root.cursorLine ? root.colGutterActive : root.colGutterText
            }
        }
    }

    function lineY(line: int): real {
        return edit.positionToRectangle(root.lineStart(line)).y;
    }

    // Lines whose first row is on screen
    property var visibleLines: []
    function refreshVisible(): void {
        if (edit.length < 0) return;
        const first = root.lineAt(edit.positionAt(0, flick.contentY));
        const last = root.lineAt(edit.positionAt(0, flick.contentY + flick.height));
        const out = [];
        for (let l = first; l <= Math.min(last + 1, root.lineCount - 1); ++l)
            out.push(l);
        root.visibleLines = out;
    }

    // ── text area ──

    Flickable {
        id: flick
        anchors.left: parent.left
        anchors.leftMargin: root.lineNumbers ? root.gutterWidth : 0
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: root.wrap ? width : Math.max(width, edit.implicitWidth + 40)
        contentHeight: Math.max(height, edit.implicitHeight + root.lineHeight * 4)
        flickableDirection: Flickable.HorizontalAndVerticalFlick
        onContentYChanged: root.refreshVisible()
        onHeightChanged: root.refreshVisible()

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 10 }
        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded; height: 10 }

        // current line band
        Rectangle {
            visible: edit.activeFocus || true
            x: 0
            y: edit.cursorRectangle.y + edit.topPadding
            width: flick.contentWidth
            height: edit.cursorRectangle.height
            color: root.colLine
        }

        // find matches
        Repeater {
            model: root.matchRects
            delegate: Rectangle {
                required property var modelData
                x: modelData.x + edit.leftPadding
                y: modelData.y + edit.topPadding
                width: modelData.w
                height: modelData.h
                radius: 3
                color: modelData.active ? root.colMatchActive : root.colMatch
            }
        }

        // the highlighted copy of the document
        Text {
            id: hl
            x: edit.x
            y: edit.y
            width: edit.width
            leftPadding: edit.leftPadding
            topPadding: edit.topPadding
            text: root.highlightOff ? edit.text : "<div style=\"white-space:pre\">" + root.html + "</div>"
            textFormat: root.highlightOff ? Text.PlainText : Text.RichText
            wrapMode: root.wrap ? Text.Wrap : Text.NoWrap
            font: edit.font
            // The editor decides the row height; the copy has to follow it or the lines drift apart
            lineHeightMode: Text.FixedHeight
            lineHeight: root.rowHeight
            color: root.colText
        }

        TextEdit {
            id: edit
            x: 0
            y: 0
            width: root.wrap ? flick.width : Math.max(flick.width, implicitWidth + 40)
            leftPadding: 12
            rightPadding: 12
            topPadding: 6
            bottomPadding: 6
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
            tabStopDistance: root.charWidth * root.tabSize
            // The glyphs are drawn by the Text under this item; this one only shows caret and selection
            color: "transparent"
            selectedTextColor: "transparent"
            selectionColor: root.colSelection
            selectByMouse: true
            persistentSelection: true
            readOnly: root.readOnly
            wrapMode: root.wrap ? TextEdit.Wrap : TextEdit.NoWrap
            textFormat: TextEdit.PlainText
            activeFocusOnPress: true
            cursorDelegate: Rectangle { width: 2; color: root.colCaret; visible: edit.activeFocus; radius: 1 }

            Keys.onPressed: e => { if (root.handleKey(e)) e.accepted = true; }
            onTextChanged: {
                root.recount();
                hlTimer.restart();
                root.edited();
                root.refreshVisible();
            }
            onCursorPositionChanged: {
                root.cursorLine = root.lineAt(edit.cursorPosition);
                root.cursorColumn = edit.cursorPosition - root.lineStart(root.cursorLine);
                root.ensureCursorVisible(false);
            }
            onSelectionStartChanged: root.selectedLength = Math.abs(edit.selectionEnd - edit.selectionStart)
            onSelectionEndChanged: root.selectedLength = Math.abs(edit.selectionEnd - edit.selectionStart)
            Component.onCompleted: { root.recount(); root.rehighlight(); root.refreshVisible(); }
        }
    }

    // Rectangles of the visible find matches
    property var matchRects: {
        const out = [];
        if (root.matches.length === 0 || root.lineStarts.length === 0)
            return out;
        const top = edit.positionAt(0, flick.contentY), bottom = edit.positionAt(0, flick.contentY + flick.height);
        const ms = root.matches;
        for (let i = 0; i < ms.length && out.length < 400; ++i) {
            const m = ms[i];
            if (m.end < top || m.start > bottom) continue;
            const a = edit.positionToRectangle(m.start), b = edit.positionToRectangle(m.end);
            if (Math.abs(a.y - b.y) < 2)
                out.push({ x: a.x, y: a.y, w: Math.max(2, b.x - a.x), h: a.height, active: i === root.currentMatch });
            else
                out.push({ x: a.x, y: a.y, w: Math.max(8, flick.contentWidth - a.x), h: a.height, active: i === root.currentMatch });
        }
        return out;
    }
}
