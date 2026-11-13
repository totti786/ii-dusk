pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Quick Share inside the auxiliary bubble's card. One thing at a time, in the order that
 * matters: a request waiting for an answer, a transfer moving, files waiting for a device,
 * and otherwise who can see this PC. The visibility choice sits at the bottom of every state.
 *
 * Self-contained on purpose: the bubble loads cards by URL, and such a file gets none of
 * its directory's types. It reads QuickShareService, which the island already follows.
 */
Item {
    id: root

    readonly property var request: QuickShareService.incoming[0] ?? null
    readonly property var moving: QuickShareService.active.find(t => t.state === "ReceivingFiles" || t.state === "SendingFiles") ?? null
    readonly property bool choosing: QuickShareService.pending.length > 0
    readonly property var heroItems: [heroDisc]

    // The card's mode, in priority order.
    readonly property string mode: root.request ? "request" : root.moving ? "moving" : root.choosing ? "choose" : "idle"

    function meta(t: var): var { return t?.meta ?? {}; }
    function fraction(t: var): real {
        const m = root.meta(t);
        return m.total_bytes > 0 ? Math.min(1, m.ack_bytes / m.total_bytes) : 0;
    }
    function leftLabel(): string {
        if (QuickShareService.visibility !== "temporarily")
            return "";
        const left = Math.max(0, QuickShareService.tempMs - (clock.now - QuickShareService.tempSince));
        const m = Math.floor(left / 60000);
        const s = Math.floor((left % 60000) / 1000);
        return `${m}:${String(s).padStart(2, "0")}`;
    }
    function fileLabel(paths: var): string {
        return paths.length === 1 ? String(paths[0]).split("/").pop() : Translation.tr("%1 files").arg(paths.length);
    }

    readonly property string title: root.mode === "request" ? (root.meta(root.request).source?.name ?? Translation.tr("A nearby device"))
        : root.mode === "moving" ? (QuickShareService.describe(root.moving) || Translation.tr("Transfer"))
        : root.mode === "choose" ? Translation.tr("Send %1").arg(root.fileLabel(QuickShareService.pending))
        : Translation.tr("Quick Share")
    readonly property string subtitle: {
        if (root.mode === "request") {
            const m = root.meta(root.request);
            const what = QuickShareService.describe(root.request);
            return (what ? what : Translation.tr("wants to share")) + (m.pin_code ? ` · PIN ${m.pin_code}` : "");
        }
        if (root.mode === "moving")
            return root.moving.rtype === "inbound" ? Translation.tr("Receiving") : Translation.tr("Sending");
        if (root.mode === "choose")
            return QuickShareService.endpoints.length > 0 ? Translation.tr("Pick a device") : Translation.tr("Looking for phones…");
        if (QuickShareService.visibility === "visible")
            return Translation.tr("Visible to nearby devices");
        if (QuickShareService.visibility === "temporarily")
            return Translation.tr("Visible · %1 left").arg(root.leftLabel());
        return Translation.tr("Hidden");
    }

    // Ticks the countdown while it is shown.
    QtObject {
        id: clock
        property real now: Date.now()
    }
    Timer {
        interval: 1000
        repeat: true
        running: QuickShareService.visibility === "temporarily"
        onTriggered: clock.now = Date.now()
    }

    // ── Geometry ──
    readonly property real margin: 14
    readonly property real preferredExpandedWidth: 340
    readonly property real preferredExpandedHeight: column.implicitHeight + 2 * root.margin

    // Files dropped onto the card go to the device picker.
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: drop => {
            if (!drop.hasUrls)
                return;
            const paths = [];
            for (let i = 0; i < drop.urls.length; i++) {
                const u = String(drop.urls[i]);
                if (u.startsWith("file://"))
                    paths.push(decodeURIComponent(u.slice(7)));
            }
            if (paths.length > 0)
                QuickShareService.stage(paths);
        }
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.margin
        }
        spacing: 12

        // ── Header ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                id: heroDisc
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: width / 2
                color: root.mode === "request" ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainer
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.mode === "moving" && root.moving.rtype === "outbound" ? "upload"
                        : root.mode === "moving" ? "download" : "send_to_mobile"
                    iconSize: 22
                    fill: 1
                    color: root.mode === "request" ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    elide: Text.ElideMiddle
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.subtitle
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.features: ({ "tnum": 1 })
                    color: Appearance.colors.colSubtext
                }
            }

            CornerButton {
                glyph: "attach_file"
                tip: Translation.tr("Choose files to send")
                onClicked: GlobalStates.openQuickShareApp()
            }
        }

        // ── Request ──
        RowLayout {
            visible: root.mode === "request"
            Layout.fillWidth: true
            spacing: 8
            ActionButton {
                Layout.fillWidth: true
                filled: true
                label: Translation.tr("Accept")
                onClicked: QuickShareService.accept(root.request.id)
            }
            ActionButton {
                Layout.fillWidth: true
                label: Translation.tr("Decline")
                onClicked: QuickShareService.reject(root.request.id)
            }
        }

        // ── Moving ──
        ColumnLayout {
            visible: root.mode === "moving"
            Layout.fillWidth: true
            spacing: 8
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 6
                radius: 3
                color: Appearance.colors.colSurfaceContainerHighest
                Rectangle {
                    width: parent.width * root.fraction(root.moving)
                    height: parent.height
                    radius: 3
                    color: Appearance.colors.colPrimary
                    Behavior on width {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }
            ActionButton {
                Layout.fillWidth: true
                label: Translation.tr("Cancel")
                onClicked: QuickShareService.cancel(root.moving.id)
            }
        }

        // ── Choose a device ──
        ColumnLayout {
            visible: root.mode === "choose"
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: QuickShareService.endpoints
                delegate: RippleButton {
                    id: device
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 44
                    buttonRadius: Appearance.rounding.normal
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                    onClicked: QuickShareService.sendFiles(device.modelData, QuickShareService.pending)
                    contentItem: RowLayout {
                        spacing: 10
                        MaterialSymbol {
                            Layout.leftMargin: 10
                            text: device.modelData.rtype === "laptop" ? "laptop" : device.modelData.rtype === "tablet" ? "tablet" : "smartphone"
                            iconSize: 20
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: device.modelData.name ?? device.modelData.id
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnSurface
                        }
                    }
                }
            }
            StyledText {
                visible: QuickShareService.endpoints.length === 0
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Translation.tr("Open Quick Share on the phone and let it receive from everyone.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            ActionButton {
                Layout.fillWidth: true
                label: Translation.tr("Cancel")
                onClicked: QuickShareService.pending = []
            }
        }

        // ── Send something that is not a file yet ──
        RowLayout {
            visible: root.mode === "idle"
            Layout.fillWidth: true
            spacing: 8
            ActionButton {
                Layout.fillWidth: true
                label: Translation.tr("Clipboard")
                onClicked: QuickShareService.shareClipboard()
            }
            ActionButton {
                Layout.fillWidth: true
                label: Translation.tr("Last screenshot")
                onClicked: QuickShareService.shareLastScreenshot()
            }
        }

        // ── Who can see this PC ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [
                    { id: "invisible", label: Translation.tr("Hidden"), glyph: "visibility_off" },
                    { id: "temporarily", label: Translation.tr("10 min"), glyph: "timer" },
                    { id: "visible", label: Translation.tr("Always"), glyph: "visibility" }
                ]
                delegate: RippleButton {
                    id: chip
                    required property var modelData
                    readonly property bool on: QuickShareService.visibility === chip.modelData.id
                    Layout.fillWidth: true
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    colBackground: chip.on ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: chip.on ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSurfaceContainerHighest
                    onClicked: QuickShareService.setVisibility(chip.modelData.id)
                    contentItem: RowLayout {
                        spacing: 6
                        Item { Layout.fillWidth: true }
                        MaterialSymbol {
                            text: chip.modelData.glyph
                            iconSize: 16
                            color: chip.on ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            text: chip.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: chip.on ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
            }
        }
    }

    component CornerButton: RippleButton {
        id: cornerButton
        property string glyph
        property string tip

        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colSurfaceContainerHigh
        colBackgroundHover: Appearance.colors.colSurfaceContainerHighest

        contentItem: Item {
            MaterialSymbol {
                anchors.centerIn: parent
                text: cornerButton.glyph
                iconSize: 18
                color: Appearance.colors.colOnSurface
            }
        }

        StyledToolTip {
            text: cornerButton.tip
        }
    }

    component ActionButton: RippleButton {
        id: action
        property string label
        property bool filled: false

        implicitHeight: 38
        buttonRadius: Appearance.rounding.full
        colBackground: action.filled ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHigh
        colBackgroundHover: action.filled ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighest
        colRipple: action.filled ? Appearance.colors.colPrimaryActive : Appearance.colors.colSurfaceContainerHighestActive

        contentItem: Item {
            StyledText {
                anchors.centerIn: parent
                text: action.label
                font.weight: Font.DemiBold
                color: action.filled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
            }
        }
    }
}
