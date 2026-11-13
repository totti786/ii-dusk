pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Quick Share as a floating window, in the shell's Material 3 Expressive vocabulary
 * (docs/design/material3-expressive.md), built from the Clock app's parts.
 *
 *   Receive   who can see this PC: the state as the one big word, the choice as chips.
 *   Send      a drop target for files, then one row per nearby device.
 *   Transfers appears with the first request or transfer, and goes when there are none.
 *
 * The window is only a frontend; transfers live in the daemon. The main action, choosing
 * files, is the floating button inside the page.
 */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property bool on: QuickShareService.enabled
    readonly property bool wide: root.width >= 820
    readonly property var files: QuickShareService.pending
    readonly property string visibility: QuickShareService.visibility
    readonly property bool shown: root.visibility !== "invisible"
    // Decided on the settled width, so a resize does not re-deal the page mid-drag.
    readonly property real pageGap: ClockStyle.paneGap

    onVisibleChanged: {
        if (!root.visible)
            root.closeRequested();
    }
    Component.onCompleted: QuickShareService.discover()
    Component.onDestruction: QuickShareService.stopDiscover()

    title: "ii Quick Share"
    implicitWidth: 980
    implicitHeight: 640
    minimumSize: Qt.size(Math.max(ClockStyle.windowMinWidth, 520), 480)
    color: ClockStyle.colBackground

    function fileLabel(paths: var): string {
        return paths.length === 1 ? String(paths[0]).split("/").pop()
            : Translation.tr("%1 files").arg(paths.length);
    }
    function leftLabel(): string {
        const left = Math.max(0, QuickShareService.tempMs - (clock.now - QuickShareService.tempSince));
        const m = Math.floor(left / 60000);
        const s = Math.floor((left % 60000) / 1000);
        return `${m}:${String(s).padStart(2, "0")}`;
    }
    function dropped(urls: var): void {
        const paths = [];
        for (let i = 0; i < urls.length; i++) {
            const u = String(urls[i]);
            if (u.startsWith("file://"))
                paths.push(decodeURIComponent(u.slice(7)));
        }
        if (paths.length > 0)
            QuickShareService.stage(paths);
    }

    // Takes the keyboard while the window is open.
    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            if (event.key === Qt.Key_Escape || (ctrl && (event.key === Qt.Key_W || event.key === Qt.Key_Q))) {
                root.closeRequested();
                event.accepted = true;
            } else if (ctrl && event.key === Qt.Key_O) {
                picker.running = true;
                event.accepted = true;
            }
        }
    }

    QtObject {
        id: clock
        property real now: Date.now()
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.visibility === "temporarily" && root.visible
        onTriggered: clock.now = Date.now()
    }

    Process {
        id: picker
        command: ["zenity", "--file-selection", "--multiple", "--separator=\n", "--title=Choose files to send"]
        stdout: StdioCollector { id: pickOut }
        onExited: {
            const list = pickOut.text.split("\n").map(s => s.trim()).filter(s => s.length > 0);
            if (list.length > 0)
                QuickShareService.stage(list);
        }
    }

    // The frame the Clock app gives its content: a pane gap all round, tight under the bar.
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.paneGap
        anchors.topMargin: ClockStyle.gapTiny
        spacing: ClockStyle.gapTiny

        ClockTopBar {
            Layout.fillWidth: true
            title: Translation.tr("Quick Share")
            subtitle: !root.on ? Translation.tr("Off")
                : root.visibility === "visible" ? Translation.tr("Visible to nearby devices")
                : root.visibility === "temporarily" ? Translation.tr("Visible · %1 left").arg(root.leftLabel())
                : Translation.tr("Hidden")
            onCloseRequested: root.closeRequested()
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ── Off ──────────────────────────────────────────────────────
            ClockEmptyState {
                anchors.centerIn: parent
                visible: !root.on
                symbol: "send_to_mobile"
                title: Translation.tr("Quick Share is off")
                subtitle: Translation.tr("Turn it on to send files to Android phones and receive from them.")
                ClockButton {
                    Layout.alignment: Qt.AlignHCenter
                    variant: "filled"
                    symbol: "power_settings_new"
                    label: Translation.tr("Turn on")
                    onClicked: Config.options.quickShare.enable = true
                }
            }

            // ── Page ─────────────────────────────────────────────────────
            // Wide: Receive and Send share the height, the state tile and the device grid take
            // whatever is left, and Transfers is a strip across the bottom. Narrow: one column.
            Flickable {
                id: page
                anchors.fill: parent
                visible: root.on
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: Math.max(page.height, stack.implicitHeight)

                // Files dropped anywhere on the page go to the device list.
                DropArea {
                    id: pageDrop
                    anchors.fill: parent
                    keys: ["text/uri-list"]
                    onDropped: drop => {
                        if (drop.hasUrls)
                            root.dropped(drop.urls);
                    }
                }

                ColumnLayout {
                    id: stack
                    width: page.width
                    height: Math.max(page.height, stack.implicitHeight)
                    spacing: root.pageGap

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: root.wide
                        columns: root.wide ? 2 : 1
                        columnSpacing: root.pageGap
                        rowSpacing: root.pageGap

                        // ── Receive ──
                        Pane {
                            Layout.fillWidth: true
                            Layout.fillHeight: root.wide
                            Layout.preferredWidth: 5
                            title: Translation.tr("Receive")
                            symbol: "download"
                            shape: MaterialShape.Shape.Cookie6Sided

                            // The state, as the one big word. It takes all the height there is.
                            Rectangle {
                                id: stateTile
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 148
                                radius: ClockStyle.radiusCard
                                color: root.shown ? ClockStyle.colPrimaryContainer : ClockStyle.colField
                                Behavior on color {
                                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                                }

                                // Shape is state: it morphs, it does not spin.
                                MaterialShape {
                                    id: stateShape
                                    readonly property real size: Math.round(Math.min(stateTile.height * 0.46, stateTile.width * 0.42, 176))
                                    width: stateShape.size
                                    height: stateShape.size
                                    anchors {
                                        top: parent.top
                                        right: parent.right
                                        topMargin: ClockStyle.cardPadding
                                        rightMargin: ClockStyle.cardPadding
                                    }
                                    shape: root.shown ? MaterialShape.Shape.Sunny : MaterialShape.Shape.Cookie9Sided
                                    color: root.shown ? ClockStyle.colPrimary : ClockStyle.colSecondaryContainer
                                    Behavior on width {
                                        animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: root.shown ? "visibility" : "visibility_off"
                                        fill: 1
                                        iconSize: Math.round(stateShape.size * 0.46)
                                        color: root.shown ? ClockStyle.colOnPrimary : ClockStyle.colOnSecondaryContainer
                                    }
                                }

                                ColumnLayout {
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        bottom: parent.bottom
                                        margins: ClockStyle.cardPadding
                                    }
                                    spacing: 0

                                    StyledText {
                                        text: Translation.tr("This PC is")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Bold
                                        color: root.shown ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurfaceVariant
                                        opacity: 0.8
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.shown ? Translation.tr("Visible") : Translation.tr("Hidden")
                                        elide: Text.ElideRight
                                        font.family: ClockStyle.fontMain
                                        font.variableAxes: root.shown ? ClockStyle.axesDigitsBold : ClockStyle.axesDigits
                                        font.pixelSize: Math.round(Math.max(40, Math.min(128, stateTile.height * 0.3, (stateTile.width - ClockStyle.cardPadding * 2) / 3.6)))
                                        color: root.shown ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.visibility === "temporarily" ? Translation.tr("%1 left").arg(root.leftLabel())
                                            : root.visibility === "visible" ? Translation.tr("until you hide it")
                                            : Translation.tr("nobody can send here")
                                        elide: Text.ElideRight
                                        font.family: ClockStyle.fontNumbers
                                        font.features: ({ "tnum": 1 })
                                        font.pixelSize: ClockStyle.textLarge
                                        color: root.shown ? ClockStyle.colOnPrimaryContainer : ClockStyle.colSubtext
                                        opacity: 0.86
                                    }
                                }
                            }

                            // Equal-width choices across the pane.
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ClockStyle.gapSmall
                                Repeater {
                                    model: [
                                        { id: "invisible", symbol: "visibility_off", label: Translation.tr("Hidden") },
                                        { id: "temporarily", symbol: "timer", label: Translation.tr("10 minutes") },
                                        { id: "visible", symbol: "visibility", label: Translation.tr("Always") }
                                    ]
                                    delegate: ClockChip {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        symbol: modelData.symbol
                                        label: modelData.label
                                        selected: root.visibility === modelData.id
                                        onClicked: QuickShareService.setVisibility(modelData.id)
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: Translation.tr("On the phone, open Quick Share and choose Everyone for 10 minutes. You always get to accept or decline, with a PIN to check.")
                                font.pixelSize: ClockStyle.textSmall
                                color: ClockStyle.colSubtext
                                opacity: 0.9
                            }
                        }

                        // ── Send ──
                        Pane {
                            id: sendPane
                            Layout.fillWidth: true
                            Layout.fillHeight: root.wide
                            Layout.preferredWidth: 7
                            title: Translation.tr("Send")
                            symbol: "upload"
                            count: QuickShareService.endpoints.length
                            shape: MaterialShape.Shape.Cookie7Sided

                            // The drop target. It fills while files hover and holds what is staged.
                            Rectangle {
                                id: dropTile
                                readonly property bool hovering: pageDrop.containsDrag
                                readonly property bool staged: root.files.length > 0
                                Layout.fillWidth: true
                                implicitHeight: 124
                                radius: ClockStyle.radiusCard
                                color: dropTile.hovering || dropTile.staged ? ClockStyle.colTertiaryContainer : ClockStyle.colField
                                Behavior on color {
                                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                                }

                                HoverHandler { id: dropHover }
                                TapHandler { onTapped: picker.running = true }

                                RowLayout {
                                    anchors {
                                        fill: parent
                                        margins: ClockStyle.cardPadding
                                    }
                                    spacing: ClockStyle.gapLarge

                                    MaterialShape {
                                        Layout.preferredWidth: 72
                                        Layout.preferredHeight: 72
                                        shape: dropTile.hovering || dropHover.hovered ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie4Sided
                                        color: dropTile.hovering || dropTile.staged ? ClockStyle.colTertiary : ClockStyle.colSecondaryContainer
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: dropTile.staged ? "attach_file" : "upload_file"
                                            fill: 1
                                            iconSize: 32
                                            color: dropTile.hovering || dropTile.staged ? ClockStyle.colOnTertiary : ClockStyle.colOnSecondaryContainer
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 2
                                        StyledText {
                                            Layout.fillWidth: true
                                            elide: Text.ElideMiddle
                                            text: dropTile.hovering ? Translation.tr("Release to stage")
                                                : dropTile.staged ? root.fileLabel(root.files)
                                                : Translation.tr("Drop files here")
                                            font.family: ClockStyle.fontTitle
                                            font.variableAxes: ClockStyle.axesTitle
                                            font.pixelSize: Appearance.font.pixelSize.huge + 4
                                            color: dropTile.hovering || dropTile.staged ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnSurface
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            text: dropTile.staged ? Translation.tr("Pick a phone below")
                                                : Translation.tr("or click to choose")
                                            font.pixelSize: ClockStyle.textNormal
                                            color: dropTile.hovering || dropTile.staged ? ClockStyle.colOnTertiaryContainer : ClockStyle.colSubtext
                                            opacity: 0.86
                                        }
                                    }

                                    ClockButton {
                                        visible: dropTile.staged
                                        variant: "text"
                                        iconOnly: true
                                        symbol: "close"
                                        label: Translation.tr("Clear")
                                        onClicked: QuickShareService.pending = []
                                    }
                                }
                            }

                            // Nearby devices: a grid of tiles that fills what is left, one shape each.
                            Item {
                                id: deviceArea
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 120
                                visible: QuickShareService.endpoints.length > 0
                                clip: true

                                readonly property int cols: Math.max(1, Math.floor((width + ClockStyle.gap) / (220 + ClockStyle.gap)))
                                readonly property real tileW: Math.floor((width - (cols - 1) * ClockStyle.gap) / cols)

                                Flickable {
                                    anchors.fill: parent
                                    contentWidth: width
                                    contentHeight: deviceFlow.implicitHeight + 72
                                    boundsBehavior: Flickable.StopAtBounds

                                    Flow {
                                        id: deviceFlow
                                        width: parent.width
                                        spacing: ClockStyle.gap

                                        Repeater {
                                            model: QuickShareService.endpoints
                                            delegate: Rectangle {
                                                id: dev
                                                required property var modelData
                                                required property int index
                                                readonly property var shapes: [
                                                    MaterialShape.Shape.Cookie6Sided, MaterialShape.Shape.Clover4Leaf,
                                                    MaterialShape.Shape.Flower, MaterialShape.Shape.Cookie12Sided,
                                                    MaterialShape.Shape.SoftBurst
                                                ]
                                                readonly property bool ready: root.files.length > 0
                                                width: deviceArea.tileW
                                                height: 132
                                                radius: ClockStyle.radiusCard
                                                color: devHover.hovered ? ClockStyle.colPrimaryContainer : ClockStyle.colField
                                                Behavior on color {
                                                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                                                }

                                                HoverHandler { id: devHover }
                                                TapHandler {
                                                    onTapped: {
                                                        if (dev.ready)
                                                            QuickShareService.sendFiles(dev.modelData, root.files);
                                                        else
                                                            picker.running = true;
                                                    }
                                                }

                                                ClockBadge {
                                                    x: ClockStyle.gap
                                                    y: ClockStyle.gap
                                                    size: 56
                                                    text: dev.modelData.rtype === "laptop" ? "laptop"
                                                        : dev.modelData.rtype === "tablet" ? "tablet" : "smartphone"
                                                    shape: dev.shapes[dev.index % dev.shapes.length]
                                                    color: devHover.hovered ? ClockStyle.colPrimary : ClockStyle.colPrimaryContainer
                                                    colSymbol: devHover.hovered ? ClockStyle.colOnPrimary : ClockStyle.colOnPrimaryContainer
                                                }
                                                MaterialSymbol {
                                                    anchors {
                                                        top: parent.top
                                                        right: parent.right
                                                        margins: ClockStyle.gap + 4
                                                    }
                                                    text: dev.ready ? "send" : "chevron_right"
                                                    fill: dev.ready ? 1 : 0
                                                    iconSize: ClockStyle.iconNormal
                                                    color: dev.ready || devHover.hovered ? ClockStyle.colPrimary : ClockStyle.colSubtext
                                                }
                                                ColumnLayout {
                                                    anchors {
                                                        left: parent.left
                                                        right: parent.right
                                                        bottom: parent.bottom
                                                        margins: ClockStyle.gap
                                                    }
                                                    spacing: 0
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                        text: dev.modelData.name ?? dev.modelData.id
                                                        font.family: ClockStyle.fontTitle
                                                        font.variableAxes: ClockStyle.axesTitle
                                                        font.pixelSize: ClockStyle.textLarge + 2
                                                        color: devHover.hovered ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                        text: dev.ready ? Translation.tr("Tap to send %1").arg(root.fileLabel(root.files))
                                                            : Translation.tr("Choose files first")
                                                        font.pixelSize: ClockStyle.textSmall
                                                        color: devHover.hovered ? ClockStyle.colOnPrimaryContainer : ClockStyle.colSubtext
                                                        opacity: 0.86
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Nothing nearby yet: the empty state takes the room that is left.
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 160
                                visible: QuickShareService.endpoints.length === 0

                                ClockEmptyState {
                                    anchors.centerIn: parent
                                    width: Math.min(parent.width, 360)
                                    symbol: "radar"
                                    shape: "Clover8Leaf"
                                    shapeSize: 96
                                    title: Translation.tr("Looking for phones…")
                                    subtitle: Translation.tr("Open Quick Share on the phone and let it receive from everyone.")
                                }
                            }
                        }
                    }

                    // ── Transfers: a strip across the bottom, only while there are any ──
                    Pane {
                        id: transfersPane
                        Layout.fillWidth: true
                        visible: QuickShareService.transfers.length > 0
                        title: Translation.tr("Transfers")
                        symbol: "swap_vert"
                        count: QuickShareService.transfers.length
                        shape: MaterialShape.Shape.Clover4Leaf

                        Flow {
                            id: transferFlow
                            Layout.fillWidth: true
                            spacing: ClockStyle.gap
                            readonly property int cols: Math.max(1, Math.floor((width + ClockStyle.gap) / (320 + ClockStyle.gap)))
                            readonly property real cardW: Math.floor((width - (cols - 1) * ClockStyle.gap) / cols)

                            Repeater {
                                model: QuickShareService.transfers
                                delegate: Rectangle {
                                    id: row
                                    required property var modelData
                                    readonly property var meta: modelData.meta ?? {}
                                    readonly property real frac: meta.total_bytes > 0 ? Math.min(1, meta.ack_bytes / meta.total_bytes) : 0
                                    readonly property bool waiting: modelData.state === "WaitingForUserConsent"
                                    readonly property bool inbound: modelData.rtype === "inbound"
                                    readonly property bool moving: modelData.state === "ReceivingFiles" || modelData.state === "SendingFiles"
                                    readonly property bool finished: modelData.state === "Finished"
                                    width: transferFlow.cardW
                                    implicitHeight: rowBody.implicitHeight + ClockStyle.gap * 2
                                    height: implicitHeight
                                    radius: ClockStyle.radiusLarge
                                    // A request waiting is the one thing that needs you.
                                    color: row.waiting ? ClockStyle.colPrimaryContainer : ClockStyle.colField

                                    ColumnLayout {
                                        id: rowBody
                                        anchors {
                                            fill: parent
                                            margins: ClockStyle.gap
                                        }
                                        spacing: ClockStyle.gapSmall

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: ClockStyle.gap

                                            ClockBadge {
                                                size: 44
                                                text: row.finished ? "check" : row.inbound ? "download" : "upload"
                                                shape: row.waiting ? MaterialShape.Shape.Sunny
                                                    : row.moving ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie9Sided
                                                color: row.waiting ? ClockStyle.colPrimary
                                                    : row.finished ? ClockStyle.colTertiary : ClockStyle.colSecondaryContainer
                                                colSymbol: row.waiting ? ClockStyle.colOnPrimary
                                                    : row.finished ? ClockStyle.colOnTertiary : ClockStyle.colOnSecondaryContainer
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                spacing: 0
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideMiddle
                                                    text: QuickShareService.describe(row.modelData) || Translation.tr("Transfer")
                                                    font.family: ClockStyle.fontTitle
                                                    font.variableAxes: ClockStyle.axesTitle
                                                    font.pixelSize: ClockStyle.textLarge
                                                    color: row.waiting ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface
                                                }
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                    font.pixelSize: ClockStyle.textSmall
                                                    color: row.waiting ? ClockStyle.colOnPrimaryContainer : ClockStyle.colSubtext
                                                    text: {
                                                        const who = row.meta.source?.name ?? "";
                                                        const pin = row.waiting && row.meta.pin_code ? Translation.tr("PIN %1").arg(row.meta.pin_code) : "";
                                                        const st = row.finished ? Translation.tr("Done")
                                                            : row.waiting ? Translation.tr("wants to share")
                                                            : row.modelData.done ? Translation.tr("Stopped")
                                                            : row.inbound ? Translation.tr("Receiving") : Translation.tr("Sending");
                                                        return [who, st, pin].filter(x => x !== "").join(" · ");
                                                    }
                                                }
                                            }
                                        }

                                        // The one thing a request needs from you.
                                        RowLayout {
                                            Layout.fillWidth: true
                                            visible: row.waiting && row.inbound
                                            spacing: ClockStyle.gapSmall
                                            ClockButton {
                                                Layout.fillWidth: true
                                                variant: "filled"
                                                symbol: "check"
                                                label: Translation.tr("Accept")
                                                onClicked: QuickShareService.accept(row.modelData.id)
                                            }
                                            ClockButton {
                                                Layout.fillWidth: true
                                                variant: "text"
                                                symbol: "close"
                                                label: Translation.tr("Decline")
                                                onClicked: QuickShareService.reject(row.modelData.id)
                                            }
                                        }

                                        // Progress: wavy while bytes move, as the ring does.
                                        RowLayout {
                                            Layout.fillWidth: true
                                            visible: !row.modelData.done && !row.waiting
                                            spacing: ClockStyle.gap
                                            Item {
                                                Layout.fillWidth: true
                                                implicitHeight: 12
                                                StyledProgressBar {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width
                                                    valueBarWidth: parent.width
                                                    valueBarHeight: 8
                                                    value: row.frac
                                                    wavy: row.moving
                                                    animateWave: row.moving
                                                    highlightColor: ClockStyle.colPrimary
                                                    trackColor: ClockStyle.colSurfaceHighest
                                                }
                                            }
                                            ClockButton {
                                                variant: "text"
                                                label: Translation.tr("Cancel")
                                                onClicked: QuickShareService.cancel(row.modelData.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // The page's main action: the floating button, label unfolding on hover.
            FloatingActionButton {
                id: fab
                visible: root.on
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: ClockStyle.gapSmall
                anchors.bottomMargin: ClockStyle.gapSmall
                z: 5
                baseSize: ClockStyle.fabSize
                iconSize: 28
                buttonRadius: Appearance.rounding.large
                buttonRadiusPressed: Appearance.rounding.normal
                iconText: "attach_file"
                buttonText: Translation.tr("Choose files")
                expanded: hovered
                shortcut: "Ctrl\n+ O"
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colBackgroundActive: Appearance.colors.colPrimaryContainerActive
                colRipple: Appearance.colors.colPrimaryContainerActive
                colOnBackground: Appearance.colors.colOnPrimaryContainer
                onClicked: picker.running = true

                StyledToolTip {
                    text: Translation.tr("Choose files to send (Ctrl+O)")
                }
            }
        }
    }

    /// A slab on the pane layer: a badge and title, then whatever it holds. Unlike ClockPane its
    /// body takes the height it is given, so the things inside can fill the window.
    component Pane: Rectangle {
        id: pane

        property string title: ""
        property string symbol: ""
        property int count: -1
        property var shape: MaterialShape.Shape.Cookie9Sided
        default property alias content: paneBody.data

        implicitHeight: paneColumn.implicitHeight + ClockStyle.cardPadding * 2
        radius: ClockStyle.radiusCard
        color: ClockStyle.colPane

        ColumnLayout {
            id: paneColumn
            anchors {
                fill: parent
                margins: ClockStyle.cardPadding
            }
            spacing: ClockStyle.gap

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gap

                ClockBadge {
                    size: 44
                    text: pane.symbol
                    shape: pane.shape
                    color: ClockStyle.colPrimary
                    colSymbol: ClockStyle.colOnPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: pane.title
                    elide: Text.ElideRight
                    font.family: Appearance.font.family.title
                    font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: ClockStyle.colOnBackground
                }
                Rectangle {
                    visible: pane.count >= 0
                    implicitWidth: Math.max(28, countText.implicitWidth + 16)
                    implicitHeight: 28
                    radius: 14
                    color: ClockStyle.colSecondaryContainer
                    StyledText {
                        id: countText
                        anchors.centerIn: parent
                        text: String(pane.count)
                        font.pixelSize: ClockStyle.textSmall
                        color: ClockStyle.colOnSecondaryContainer
                    }
                }
            }

            ColumnLayout {
                id: paneBody
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: ClockStyle.gap
            }
        }
    }
}
