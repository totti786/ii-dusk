pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "CalculatorMath.js" as CalcMath

/**
 * The calculator as a floating window, built from the same parts as the clock app: the app
 * bar with mode chips, a display card, and a Material keypad.
 *
 * The expression is plain ASCII (+ - * / ^ % !, names like sin( ), the same text the engine in
 * CalculatorMath.js reads and the launcher stores. Typographic signs exist only on screen.
 * Esc clears; the window closes with Ctrl+W, Ctrl+Q or its close button.
 */
FloatingWindow {
    id: root

    signal closeRequested()

    // ── State ──────────────────────────────────────────────────────────
    property string expression: ""
    property string previousExpression: ""
    property bool justEvaluated: false
    property bool failed: false
    property string errorText: ""
    property string heldResult: ""
    property var ans: null
    property real memory: 0
    property bool hasMemory: false
    property bool inverse: false
    property bool historyOpen: false
    property bool copied: false
    property string flashId: ""

    readonly property string mode: Persistent.states.calculator.mode === "scientific" ? "scientific" : "standard"
    readonly property string angle: Persistent.states.calculator.angle === "rad" ? "rad" : "deg"
    readonly property bool grouping: Persistent.states.calculator.grouping
    readonly property bool scientific: root.mode === "scientific"
    readonly property bool historyDocked: root.historyOpen && root.width >= (root.scientific ? 1000 : 720)
    readonly property bool historyOverlay: root.historyOpen && !root.historyDocked
    readonly property var history: Array.from(Persistent.states.search.calculatorHistory ?? [])

    readonly property var engineOptions: ({ angle: root.angle, ans: root.ans })
    readonly property bool simple: /^-?\d*\.?\d*(e[+-]?\d+)?$/i.test(root.expression)

    readonly property string topLine: {
        if (root.failed || root.expression === "")
            return "";
        if (root.justEvaluated)
            return CalcMath.prettyExpression(root.previousExpression, root.grouping) + " =";
        return root.simple ? "" : CalcMath.prettyExpression(root.expression, root.grouping);
    }
    readonly property string mainText: {
        if (root.failed)
            return root.errorText;
        if (root.expression === "")
            return "0";
        if (root.simple)
            return CalcMath.prettyNumber(root.expression, root.grouping);
        return root.heldResult === "" ? CalcMath.prettyExpression(root.expression, root.grouping) : CalcMath.prettyNumber(root.heldResult, root.grouping);
    }
    // What a copy takes: the number without spaces
    readonly property string plainResult: {
        if (root.failed || root.expression === "")
            return "0";
        return root.simple ? root.expression : root.heldResult;
    }

    onExpressionChanged: {
        if (root.expression === "") {
            root.heldResult = "";
            return;
        }
        const value = CalcMath.preview(root.expression, root.engineOptions);
        // Keeps the last answer while the expression is mid-edit ("2+" after "2+3")
        if (value !== null)
            root.heldResult = CalcMath.format(value);
    }
    onAngleChanged: {
        const value = root.expression === "" ? null : CalcMath.preview(root.expression, root.engineOptions);
        if (value !== null)
            root.heldResult = CalcMath.format(value);
    }

    // ── Editing ────────────────────────────────────────────────────────
    function lastChar(): string {
        return root.expression.slice(-1);
    }

    function startFresh(): void {
        root.expression = "";
        root.previousExpression = "";
        root.justEvaluated = false;
        root.failed = false;
    }

    // Typing after a result or an error: digits, brackets and names start over, operators carry on
    function prepare(startsNew: bool): void {
        if (root.failed) {
            root.startFresh();
        } else if (root.justEvaluated) {
            if (startsNew)
                root.startFresh();
            else
                root.justEvaluated = false;
        }
    }

    function clearAll(): void {
        root.startFresh();
    }

    function backspace(): void {
        if (root.failed || root.justEvaluated) {
            root.startFresh();
            return;
        }
        const m = root.expression.match(/(?:a?(?:sin|cos|tan)h?|ln|log2|log|sqrt|cbrt|abs|exp|floor|ceil|round)\($|ans$|pi$|\s*mod\s*$/);
        const cut = m ? m[0].length : 1;
        root.expression = root.expression.slice(0, -cut);
    }

    function digit(d: string): void {
        root.prepare(true);
        const m = root.expression.match(/(?:^|[^0-9.])(0)$/);
        if (m)
            root.expression = root.expression.slice(0, -1) + d;
        else
            root.expression += d;
    }

    function dot(): void {
        root.prepare(true);
        if (/(\d+\.?\d*(e[+-]?\d+)?|\.\d*)$/i.test(root.expression)) {
            const m = root.expression.match(/(\d+\.?\d*(e[+-]?\d+)?|\.\d*)$/i);
            if (m && (m[0].includes(".") || /e/i.test(m[0])))
                return;
            root.expression += ".";
        } else {
            root.expression += "0.";
        }
    }

    function operator(op: string): void {
        root.prepare(false);
        if (root.expression === "") {
            if (op === "-")
                root.expression = "-";
            else if (root.ans !== null)
                root.expression = "ans" + op;
            else
                root.expression = "0" + op;
            return;
        }
        if (root.expression === "-")
            return;
        const last = root.lastChar();
        if (/[+\-*\/^]/.test(last)) {
            root.expression = root.expression.slice(0, -1) + op;
        } else if (last === "(") {
            if (op === "-")
                root.expression += op;
        } else {
            root.expression += op;
        }
    }

    function openBracket(): void {
        root.prepare(true);
        root.expression += "(";
    }

    function closeBracket(): void {
        root.prepare(false);
        const open = (root.expression.match(/\(/g) || []).length;
        const closed = (root.expression.match(/\)/g) || []).length;
        if (open > closed && !/[+\-*\/^(]$/.test(root.expression))
            root.expression += ")";
    }

    // A word (a constant or a function name) must not run into a letter before it, and the
    // constant e after a digit would read as an exponent
    function insertWord(word: string): void {
        root.prepare(true);
        const last = root.lastChar();
        const glue = /[A-Za-z]/.test(last) || (word === "e" && /[0-9.]/.test(last)) ? "*" : "";
        root.expression += glue + word;
    }

    // A function key on a typed number or a result wraps it: 30 then sin gives sin(30)
    function applyFunction(name: string): void {
        if (root.failed)
            root.startFresh();
        if (root.expression !== "" && root.simple) {
            root.expression = name + "(" + root.expression + ")";
            root.previousExpression = "";
            root.justEvaluated = false;
            return;
        }
        root.insertWord(name + "(");
    }

    function operand(): string {
        return /^-/.test(root.expression) ? "(" + root.expression + ")" : root.expression;
    }

    // x², x³ and the like: raise the last thing typed
    function power(n: string): void {
        if (root.failed)
            root.startFresh();
        if (root.expression === "")
            return;
        root.justEvaluated = false;
        if (root.simple)
            root.expression = root.operand() + "^" + n;
        else if (/[0-9)!%]$|pi$|e$|ans$/.test(root.expression))
            root.expression += "^" + n;
    }

    function reciprocal(): void {
        if (root.failed)
            root.startFresh();
        if (root.expression === "")
            return;
        root.justEvaluated = false;
        root.expression = "1/(" + root.expression + ")";
    }

    function tenPower(): void {
        if (root.failed)
            root.startFresh();
        if (root.expression !== "" && root.simple) {
            root.expression = "10^(" + root.expression + ")";
            root.justEvaluated = false;
        } else {
            root.insertWord("10^(");
        }
    }

    function postfix(sign: string): void {
        if (root.failed)
            root.startFresh();
        if (root.expression === "" || !/[0-9)!%]$|pi$|e$|ans$/.test(root.expression))
            return;
        root.justEvaluated = false;
        root.expression += sign;
    }

    function negate(): void {
        if (root.failed)
            root.startFresh();
        root.justEvaluated = false;
        if (root.expression === "") {
            root.expression = "-";
        } else if (root.simple) {
            root.expression = root.expression.startsWith("-") ? root.expression.slice(1) : "-" + root.expression;
        } else if (/\(-(\d+\.?\d*(e[+-]?\d+)?|\.\d+)\)$/i.test(root.expression)) {
            root.expression = root.expression.replace(/\(-(\d+\.?\d*(e[+-]?\d+)?|\.\d+)\)$/i, "$1");
        } else if (/(\d+\.?\d*(e[+-]?\d+)?|\.\d+)$/i.test(root.expression)) {
            root.expression = root.expression.replace(/(\d+\.?\d*(e[+-]?\d+)?|\.\d+)$/i, "(-$1)");
        }
    }

    function modulo(): void {
        if (root.failed)
            root.startFresh();
        if (root.expression === "" || /[+\-*\/^(]\s*$/.test(root.expression))
            return;
        root.justEvaluated = false;
        if (!/mod\s*$/.test(root.expression))
            root.expression += " mod ";
    }

    function equals(): void {
        if (root.expression === "" || root.failed || (root.justEvaluated && root.simple))
            return;
        let value = null;
        let message = "";
        try {
            value = CalcMath.evaluate(root.expression, Object.assign({ lenient: true }, root.engineOptions));
        } catch (e) {
            // "2+" is read as 2; anything else keeps its message
            value = CalcMath.preview(root.expression, root.engineOptions);
            message = e.message;
        }
        if (value === null) {
            root.failed = true;
            root.errorText = Translation.tr(message === "" ? "Error" : message);
            return;
        }
        const open = (root.expression.match(/\(/g) || []).length - (root.expression.match(/\)/g) || []).length;
        const closed = root.expression.replace(/[+\-*\/^(]\s*$/, "") + ")".repeat(Math.max(0, open));
        const text = CalcMath.format(value);
        if (!root.simple && Persistent.ready)
            LauncherSearch.recordCalculation(closed, text);
        root.previousExpression = closed;
        root.expression = text;
        root.ans = value;
        root.justEvaluated = true;
        root.failed = false;
    }

    // ── Memory ─────────────────────────────────────────────────────────
    function currentValue(): var {
        if (root.expression === "")
            return 0;
        return CalcMath.preview(root.expression, root.engineOptions);
    }

    function memoryAdd(sign: int): void {
        const v = root.currentValue();
        if (v === null)
            return;
        root.memory += sign * v;
        root.hasMemory = true;
    }

    function memoryRecall(): void {
        if (!root.hasMemory)
            return;
        root.prepare(true);
        const text = CalcMath.format(root.memory);
        const glue = /[0-9.)]$/.test(root.expression) ? "*" : "";
        root.expression += glue + (root.memory < 0 ? "(" + text + ")" : text);
    }

    function memoryClear(): void {
        root.memory = 0;
        root.hasMemory = false;
    }

    // ── Clipboard and history ──────────────────────────────────────────
    function copyText(text: string): void {
        Quickshell.clipboardText = text;
        root.copied = true;
        copiedTimer.restart();
    }

    function paste(): void {
        const text = CalcMath.sanitize(Quickshell.clipboardText);
        if (text === "")
            return;
        root.startFresh();
        root.expression = text;
    }

    function recall(expression: string, result: string): void {
        root.startFresh();
        root.expression = expression;
        root.heldResult = result;
        if (root.historyOverlay)
            root.historyOpen = false;
    }

    function insertResult(result: string): void {
        root.prepare(true);
        const glue = /[0-9.)]$/.test(root.expression) ? "*" : "";
        root.expression += glue + (result.startsWith("-") ? "(" + result + ")" : result);
        if (root.historyOverlay)
            root.historyOpen = false;
    }

    function setMode(next: string): void {
        Persistent.states.calculator.mode = next;
    }

    function toggleAngle(): void {
        Persistent.states.calculator.angle = root.angle === "deg" ? "rad" : "deg";
    }

    // ── Keys ───────────────────────────────────────────────────────────
    function press(id: string): void {
        if (/^[0-9]$/.test(id)) {
            root.digit(id);
            return;
        }
        switch (id) {
        case ".": root.dot(); break;
        case "+": case "-": case "*": case "/": case "^": root.operator(id); break;
        case "(": root.openBracket(); break;
        case ")": root.closeBracket(); break;
        case "%": root.postfix("%"); break;
        case "!": root.postfix("!"); break;
        case "=": root.equals(); break;
        case "C": root.clearAll(); break;
        case "bs": root.backspace(); break;
        case "neg": root.negate(); break;
        case "x2": root.power("2"); break;
        case "x3": root.power("3"); break;
        case "inv": root.reciprocal(); break;
        case "ten": root.tenPower(); break;
        case "mod": root.modulo(); break;
        case "pi": root.insertWord("pi"); break;
        case "e": root.insertWord("e"); break;
        case "ans": if (root.ans !== null) root.insertWord("ans"); break;
        case "2nd": root.inverse = !root.inverse; break;
        case "angle": root.toggleAngle(); break;
        case "mc": root.memoryClear(); break;
        case "mr": root.memoryRecall(); break;
        case "mplus": root.memoryAdd(1); break;
        case "mminus": root.memoryAdd(-1); break;
        default: root.applyFunction(id);
        }
    }

    function handleKey(event): void {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        if (ctrl) {
            switch (event.key) {
            case Qt.Key_W:
            case Qt.Key_Q:
                root.closeRequested();
                break;
            case Qt.Key_C:
                root.copyText(root.plainResult);
                break;
            case Qt.Key_V:
                root.paste();
                break;
            case Qt.Key_H:
                root.historyOpen = !root.historyOpen;
                break;
            case Qt.Key_1:
                root.setMode("standard");
                break;
            case Qt.Key_2:
                root.setMode("scientific");
                break;
            default:
                return;
            }
            event.accepted = true;
            return;
        }
        const text = event.text;
        let id = "";
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Equal) {
            id = "=";
        } else if (event.key === Qt.Key_Backspace) {
            id = "bs";
        } else if (event.key === Qt.Key_Delete) {
            id = "C";
        } else if (event.key === Qt.Key_Escape) {
            // Esc only steps back: close the history sheet, otherwise clear
            if (root.historyOverlay) {
                root.historyOpen = false;
                event.accepted = true;
                return;
            }
            id = "C";
        } else if (/^[0-9]$/.test(text)) {
            id = text;
        } else if (text === "." || text === ",") {
            id = ".";
        } else if (text.length === 1 && "+-*/^()%!".includes(text)) {
            id = text;
        } else if (text === "x" || text === "X" || text === "×") {
            id = "*";
        } else if (text === "÷") {
            id = "/";
        } else if (text === "−") {
            id = "-";
        } else {
            return;
        }
        root.press(id);
        root.flash(id);
        event.accepted = true;
    }

    // Lights the on-screen key that a typed key stands for
    function flash(id: string): void {
        root.flashId = id;
        flashTimer.restart();
    }

    // ── Layout data ────────────────────────────────────────────────────
    // id: what press() gets; alt/altId: the same key while 2nd is on
    readonly property var scientificKeys: [
        { label: "2nd", id: "2nd", role: "function" },
        { label: "π", id: "pi", role: "function" },
        { label: "e", id: "e", role: "function" },
        { label: "Ans", id: "ans", role: "function" },
        { label: "sin", id: "sin", alt: "sin⁻¹", altId: "asin", role: "function" },
        { label: "cos", id: "cos", alt: "cos⁻¹", altId: "acos", role: "function" },
        { label: "tan", id: "tan", alt: "tan⁻¹", altId: "atan", role: "function" },
        { label: "n!", id: "!", role: "function" },
        { label: "ln", id: "ln", role: "function" },
        { label: "log", id: "log", role: "function" },
        { label: "xʸ", id: "^", role: "function" },
        { label: "eˣ", id: "exp", role: "function" },
        { label: "∛", id: "cbrt", role: "function" },
        { label: "|x|", id: "abs", role: "function" },
        { label: "mod", id: "mod", role: "function" },
        { label: "round", id: "round", role: "function" },
        { label: "x³", id: "x3", role: "function" },
        { label: "1/x", id: "inv", role: "function" },
        { label: "10ˣ", id: "ten", role: "function" },
        { label: "log₂", id: "log2", role: "function" },
        { label: "sinh", id: "sinh", role: "function" },
        { label: "cosh", id: "cosh", role: "function" },
        { label: "tanh", id: "tanh", role: "function" },
        { label: "angle", id: "angle", role: "function" }
    ]

    readonly property var standardKeys: [
        { label: "(", id: "(", role: "function" },
        { label: ")", id: ")", role: "function" },
        { label: "x²", id: "x2", role: "function" },
        { label: "√", id: "sqrt", role: "function" },
        { label: "C", id: "C", role: "clear" },
        { label: "⌫", id: "bs", symbol: "backspace", role: "clear" },
        { label: "%", id: "%", role: "operator" },
        { label: "÷", id: "/", role: "operator" },
        { label: "7", id: "7", role: "digit" },
        { label: "8", id: "8", role: "digit" },
        { label: "9", id: "9", role: "digit" },
        { label: "×", id: "*", role: "operator" },
        { label: "4", id: "4", role: "digit" },
        { label: "5", id: "5", role: "digit" },
        { label: "6", id: "6", role: "digit" },
        { label: "−", id: "-", role: "operator" },
        { label: "1", id: "1", role: "digit" },
        { label: "2", id: "2", role: "digit" },
        { label: "3", id: "3", role: "digit" },
        { label: "+", id: "+", role: "operator" },
        { label: "±", id: "neg", role: "digit" },
        { label: "0", id: "0", role: "digit" },
        { label: ".", id: ".", role: "digit" },
        { label: "=", id: "=", role: "equals" }
    ]

    readonly property var memoryKeys: [
        { label: "MC", id: "mc" },
        { label: "MR", id: "mr" },
        { label: "M+", id: "mplus" },
        { label: "M−", id: "mminus" }
    ]

    // Closed by the window manager (Super+Q, the compositor's close): tell the app, or its
    // open flag stays true and "open" does nothing afterwards.
    onVisibleChanged: {
        if (!root.visible)
            root.closeRequested();
    }

    title: "ii Calculator"
    implicitWidth: 480
    implicitHeight: 720
    minimumSize: Qt.size(ClockStyle.windowMinWidth, 560)
    color: ClockStyle.colBackground

    Timer {
        id: flashTimer
        interval: 140
        onTriggered: root.flashId = ""
    }

    Timer {
        id: copiedTimer
        interval: 1400
        onTriggered: root.copied = false
    }

    // Takes the keyboard while the window is open. Nothing else is allowed to keep focus.
    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => root.handleKey(event)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        ClockTopBar {
            Layout.fillWidth: true
            title: Translation.tr("Calculator")
            subtitle: root.scientific ? Translation.tr("Scientific") : ""
            onCloseRequested: root.closeRequested()

            ClockChip {
                focusPolicy: Qt.NoFocus
                label: Translation.tr("Standard")
                selected: !root.scientific
                onClicked: root.setMode("standard")
            }

            ClockChip {
                focusPolicy: Qt.NoFocus
                label: Translation.tr("Scientific")
                selected: root.scientific
                onClicked: root.setMode("scientific")
            }

            ClockIconButton {
                focusPolicy: Qt.NoFocus
                symbol: "history"
                toggled: root.historyOpen
                tooltip: Translation.tr("History")
                onClicked: root.historyOpen = !root.historyOpen
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: ClockStyle.pagePadding
                    rightMargin: ClockStyle.pagePadding
                    bottomMargin: ClockStyle.pagePadding
                }
                spacing: ClockStyle.paneGap

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: ClockStyle.gap

                    CalculatorDisplay {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(150, Math.min(210, root.height * 0.24))
                        topLine: root.topLine
                        mainText: root.mainText
                        failed: root.failed
                        hasMemory: root.hasMemory
                        showAngle: root.scientific
                        angle: root.angle
                        copied: root.copied
                        onCopyRequested: root.copyText(root.plainResult)
                        onAngleToggled: root.toggleAngle()
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.maximumWidth: pad.maxWidth
                        Layout.alignment: Qt.AlignHCenter
                        spacing: ClockStyle.gapSmall

                        Repeater {
                            model: root.memoryKeys

                            CalculatorKey {
                                required property var modelData

                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                label: modelData.label
                                role: "function"
                                labelSize: ClockStyle.textNormal
                                enabled: (modelData.id !== "mc" && modelData.id !== "mr") || root.hasMemory
                                opacity: enabled ? 1 : 0.5
                                onClicked: root.press(modelData.id)
                            }
                        }
                    }

                    RowLayout {
                        id: pad
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.maximumWidth: pad.maxWidth
                        Layout.alignment: Qt.AlignHCenter
                        spacing: ClockStyle.gapSmall

                        // Keys stretch with the window, but never past twice their height:
                        // a wide window gets margins instead of flat pills
                        readonly property int columnCount: root.scientific ? 8 : 4
                        readonly property real maxWidth: pad.columnCount * pad.keyHeight * 2 + (pad.columnCount - 1) * ClockStyle.gapSmall

                        readonly property real keyHeight: (pad.height - 5 * ClockStyle.gapSmall) / 6
                        readonly property real labelSize: Math.max(15, Math.min(28, pad.keyHeight * 0.36))

                        GridLayout {
                            visible: root.scientific
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: 1
                            columns: 4
                            rowSpacing: ClockStyle.gapSmall
                            columnSpacing: ClockStyle.gapSmall
                            uniformCellWidths: true
                            uniformCellHeights: true

                            Repeater {
                                model: root.scientificKeys

                                CalculatorKey {
                                    required property var modelData

                                    readonly property bool swapped: root.inverse && modelData.altId !== undefined
                                    readonly property bool isAngle: modelData.id === "angle"

                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    label: isAngle ? (root.angle === "rad" ? "RAD" : "DEG") : swapped ? modelData.alt : modelData.label
                                    role: modelData.role
                                    labelSize: pad.labelSize * (label.length > 3 ? 0.62 : 0.78)
                                    selected: modelData.id === "2nd" && root.inverse
                                    flashed: root.flashId === modelData.id
                                    enabled: modelData.id !== "ans" || root.ans !== null
                                    opacity: enabled ? 1 : 0.5
                                    onClicked: root.press(swapped ? modelData.altId : modelData.id)
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: 1
                            columns: 4
                            rowSpacing: ClockStyle.gapSmall
                            columnSpacing: ClockStyle.gapSmall
                            uniformCellWidths: true
                            uniformCellHeights: true

                            Repeater {
                                model: root.standardKeys

                                CalculatorKey {
                                    required property var modelData

                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    label: modelData.label
                                    symbol: modelData.symbol ?? ""
                                    role: modelData.role
                                    labelSize: modelData.role === "function" ? pad.labelSize * 0.8 : pad.labelSize
                                    flashed: root.flashId === modelData.id
                                    onClicked: root.press(modelData.id)
                                }
                            }
                        }
                    }
                }

                CalculatorHistory {
                    visible: root.historyDocked
                    Layout.fillHeight: true
                    Layout.preferredWidth: 300
                    entries: root.history
                    grouping: root.grouping
                    onRecallRequested: (expression, result) => root.recall(expression, result)
                    onResultRequested: result => root.insertResult(result)
                    onCopyRequested: result => root.copyText(result)
                    onRemoveRequested: index => LauncherSearch.removeCalculation(index)
                    onClearRequested: Persistent.states.search.calculatorHistory = []
                    onCloseRequested: root.historyOpen = false
                }
            }

            // Narrow window, or scientific without room: the history slides over the keypad
            Item {
                anchors.fill: parent
                visible: root.historyOverlay

                Rectangle {
                    anchors.fill: parent
                    color: ClockStyle.colScrim
                    opacity: 0.4

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.historyOpen = false
                    }
                }

                CalculatorHistory {
                    anchors {
                        top: parent.top
                        bottom: parent.bottom
                        right: parent.right
                        rightMargin: ClockStyle.pagePadding
                        bottomMargin: ClockStyle.pagePadding
                    }
                    width: Math.min(360, parent.width - ClockStyle.pagePadding * 2)
                    color: ClockStyle.colSheet
                    entries: root.history
                    grouping: root.grouping
                    onRecallRequested: (expression, result) => root.recall(expression, result)
                    onResultRequested: result => root.insertResult(result)
                    onCopyRequested: result => root.copyText(result)
                    onRemoveRequested: index => LauncherSearch.removeCalculation(index)
                    onClearRequested: Persistent.states.search.calculatorHistory = []
                    onCloseRequested: root.historyOpen = false
                }
            }
        }
    }
}
