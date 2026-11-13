pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Sign-in for Discordo Voice: add, replace or repair the account the helper uses.
 *
 * Two ways in, both handled entirely by the helper, which checks the result with Discord before it
 * saves anything: scan a QR code with the Discord phone app, or paste a token from the clipboard.
 * A third option opens Discordo's own sign-in in a terminal. The token is never shown, typed into or
 * held by this window.
 */
ColumnLayout {
    id: root

    readonly property var svc: DiscordoVoiceService
    /// True when the account is being changed rather than the sign-in being missing
    property bool changing: false
    property bool compact: false

    signal cancelRequested()

    readonly property bool refused: root.svc.authState === "invalid"
    readonly property var qr: root.svc.qr
    readonly property string qrState: String(root.qr.state)
    readonly property bool qrShowsCode: root.qrState === "waiting"
    readonly property bool qrRetry: ["declined", "expired", "error", "cancelled"].indexOf(root.qrState) >= 0
    readonly property var problem: root.svc.authProblem

    spacing: ClockStyle.paneGap

    Component.onDestruction: root.svc.cancelQr()

    ClockHero {
        Layout.fillWidth: true
        compact: true
        symbol: root.changing ? "switch_account" : root.refused ? "lock_reset" : "lock_open"
        shape: MaterialShape.Shape.Clover4Leaf
        title: root.changing ? Translation.tr("Change account")
            : root.refused ? Translation.tr("Sign in again")
            : Translation.tr("Sign in to Discordo Voice")
        text: root.changing
            ? Translation.tr("Add another sign-in. It replaces the saved one, which Discordo uses too.")
            : root.refused
                ? Translation.tr("Discord no longer accepts the saved sign-in. Add it again to carry on.")
                : Translation.tr("Voice needs your Discord sign-in. Pick whichever way is easiest.")
        trailing: ClockButton {
            visible: root.changing
            label: Translation.tr("Cancel")
            variant: "text"
            onClicked: root.cancelRequested()
        }
    }

    GridLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        columns: root.compact ? 1 : 2
        columnSpacing: ClockStyle.paneGap
        rowSpacing: ClockStyle.paneGap

        // ── QR code ──────────────────────────────────────────────────────────────────────
        ClockPane {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            title: Translation.tr("Scan with your phone")
            symbol: "qr_code_2"
            shape: MaterialShape.Shape.Cookie9Sided

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 196

                Rectangle {
                    id: codeCard
                    visible: root.qrShowsCode
                    anchors.centerIn: parent
                    width: 188
                    height: 188
                    radius: ClockStyle.radiusNormal
                    // A scanner needs dark on light whatever the theme is
                    color: "#ffffff"

                    Canvas {
                        id: canvas
                        anchors.fill: parent
                        property var matrix: root.qr.matrix
                        onMatrixChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            ctx.fillStyle = "#ffffff";
                            ctx.fillRect(0, 0, width, height);
                            const rows = matrix;
                            const n = rows ? rows.length : 0;
                            if (n === 0)
                                return;
                            const quiet = 2;
                            const cell = Math.max(1, Math.floor(Math.min(width, height) / (n + quiet * 2)));
                            const off = Math.floor((width - cell * n) / 2);
                            ctx.fillStyle = "#000000";
                            for (let y = 0; y < n; y++)
                                for (let x = 0; x < n; x++)
                                    if (rows[y].charAt(x) === "1")
                                        ctx.fillRect(off + x * cell, off + y * cell, cell, cell);
                        }
                    }
                }

                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    visible: root.qrState === "connecting" || root.qrState === "saving"
                    implicitSize: 56
                    color: ClockStyle.colPrimaryContainer
                    shapeColor: ClockStyle.colOnPrimaryContainer
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    visible: root.qrState === "scanned"
                    spacing: ClockStyle.gapSmall

                    DiscordoAvatar {
                        Layout.alignment: Qt.AlignHCenter
                        size: 64
                        source: root.qr.user ? root.qr.user.avatar : ""
                        name: root.qr.user ? root.qr.user.name : ""
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.qr.user ? root.qr.user.name : ""
                        color: ClockStyle.colOnBackground
                        font.family: ClockStyle.fontTitle
                        font.variableAxes: ClockStyle.axesTitle
                        font.pixelSize: ClockStyle.textLarge
                    }
                }

                ClockBadge {
                    anchors.centerIn: parent
                    visible: root.qrState === "idle" || root.qrState === "done" || root.qrRetry
                    size: 72
                    text: root.qrState === "done" ? "check" : root.qrRetry ? "refresh" : "qr_code_2"
                    shape: MaterialShape.Shape.Clover4Leaf
                    color: ClockStyle.colSurfaceHigh
                    colSymbol: ClockStyle.colOnSurfaceVariant
                }
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
                text: {
                    switch (root.qrState) {
                    case "connecting": return Translation.tr("Getting a code from Discord…");
                    case "waiting": return Translation.tr("Open Discord on your phone, go to Settings, then Scan QR Code.");
                    case "scanned": return Translation.tr("Now confirm on your phone.");
                    case "saving": return Translation.tr("Signing in…");
                    case "done": return Translation.tr("Signed in.");
                    case "declined": return Translation.tr("The sign-in was declined on the phone.");
                    case "expired": return Translation.tr("The code expired. Get a new one.");
                    case "cancelled": return Translation.tr("Cancelled.");
                    case "error": return root.qr.message.length > 0 ? root.qr.message : Translation.tr("The sign-in did not work.");
                    default: return Translation.tr("No typing needed. Approve the sign-in on your phone.");
                    }
                }
            }

            ClockButton {
                Layout.alignment: Qt.AlignHCenter
                variant: root.qrShowsCode || root.qrState === "scanned" ? "text" : "filled"
                symbol: root.qrShowsCode || root.qrState === "scanned" ? "close" : root.qrRetry ? "refresh" : "qr_code_2"
                label: root.qrShowsCode || root.qrState === "scanned" ? Translation.tr("Cancel")
                    : root.qrRetry ? Translation.tr("Get a new code") : Translation.tr("Show QR code")
                visible: root.qrState !== "connecting" && root.qrState !== "saving" && root.qrState !== "done"
                enabled: !root.svc.authBusy
                onClicked: root.qrShowsCode || root.qrState === "scanned" ? root.svc.cancelQr() : root.svc.startQr()
            }
        }

        // ── Token from the clipboard ─────────────────────────────────────────────────────
        ClockPane {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            title: Translation.tr("Paste a token")
            symbol: "key"
            shape: MaterialShape.Shape.Clover4Leaf

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
                text: Translation.tr("Copy your Discord token, then press Paste. The helper reads it from the clipboard, checks it with Discord, saves it to the system keyring and clears the clipboard. This window never sees it.")
            }

            ClockButton {
                Layout.alignment: Qt.AlignHCenter
                variant: "filled"
                symbol: "content_paste"
                label: root.svc.authBusy && root.svc.authBusyAction === "paste"
                    ? Translation.tr("Checking…") : Translation.tr("Paste from clipboard")
                enabled: !root.svc.authBusy && !root.svc.qrActive
                onClicked: root.svc.pasteToken()
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.problem !== null && root.problem.action !== "remove"
                implicitHeight: problemRow.implicitHeight + ClockStyle.gap * 2
                radius: ClockStyle.radiusNormal
                color: ClockStyle.colErrorContainer

                RowLayout {
                    id: problemRow
                    anchors {
                        fill: parent
                        margins: ClockStyle.gap
                    }
                    spacing: ClockStyle.gapSmall

                    MaterialSymbol {
                        text: "error_outline"
                        iconSize: ClockStyle.iconNormal
                        fill: 1
                        color: ClockStyle.colOnErrorContainer
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: root.problem ? root.problem.message : ""
                        color: ClockStyle.colOnErrorContainer
                        font.pixelSize: ClockStyle.textSmall
                    }
                }
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: ClockStyle.gapSmall

        MaterialSymbol {
            text: "info"
            iconSize: ClockStyle.iconSmall
            color: ClockStyle.colSubtext
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textSmall
            text: Translation.tr("There is one saved sign-in, shared with the Discordo client.")
        }
        ClockButton {
            variant: "text"
            symbol: "terminal"
            label: Translation.tr("Use the Discordo terminal client")
            onClicked: root.svc.signInInTerminal()
        }
    }
}
