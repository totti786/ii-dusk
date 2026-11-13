pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Before the room: which server, who you are, which room. Starts from the last values used,
 * then from the user's own ~/.config/syncplay.ini. While a session is starting or logging in
 * the same space shows that instead of the form.
 */
Item {
    id: root

    readonly property var defaults: SyncplayService.defaults
    readonly property bool working: SyncplayService.starting || SyncplayService.linked
    readonly property bool canConnect: !root.working
        && hostField.text.trim().length > 0 && nameField.text.trim().length > 0

    function applyDefaults(): void {
        const cfg = SyncplayService.cfg;
        const d = root.defaults;
        if (hostField.text.length === 0)
            hostField.text = (cfg?.host ?? "") || (d.host ?? "") || "syncplay.pl";
        if (portField.text.length === 0)
            portField.text = String(((cfg?.port ?? 0) || (d.port ?? 0)) || 8999);
        if (nameField.text.length === 0)
            nameField.text = (cfg?.name ?? "") || (d.name ?? "") || Quickshell.env("USER");
        if (roomField.text.length === 0)
            roomField.text = (cfg?.room ?? "") || (d.room ?? "");
    }

    function connectNow(): void {
        if (!root.canConnect)
            return;
        let host = hostField.text.trim();
        let port = parseInt(portField.text);
        // "host:port" typed into the server field is a common habit
        const m = host.match(/^([^:\s]+):(\d{1,5})$/);
        if (m) {
            host = m[1];
            port = parseInt(m[2]);
        }
        if (!(port > 0 && port < 65536))
            port = 8999;
        SyncplayService.start(host, port, nameField.text.trim(), roomField.text.trim(), passwordField.text);
        passwordField.text = "";
    }

    function usePublicServer(entry: string): void {
        const parts = entry.split(":");
        hostField.text = parts[0];
        portField.text = parts.length > 1 ? parts[1] : "8999";
    }

    Component.onCompleted: root.applyDefaults()
    Connections {
        target: SyncplayService
        function onDefaultsLoadedChanged() { root.applyDefaults(); }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - ClockStyle.pagePaddingWide * 2, 460)
        spacing: ClockStyle.gap

        // Starting or logging in: say so, with the way out in the top bar
        ColumnLayout {
            visible: root.working
            Layout.fillWidth: true
            spacing: ClockStyle.gap

            MaterialLoadingIndicator {
                Layout.alignment: Qt.AlignHCenter
                loading: root.working
                implicitSize: 64
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: SyncplayService.starting
                    ? Translation.tr("Starting Syncplay…")
                    : Translation.tr("Connecting to %1…").arg(SyncplayService.host)
                font.pixelSize: ClockStyle.textLarge
                color: ClockStyle.colOnSurface
            }

            StyledText {
                visible: SyncplayService.errorText.length > 0
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: SyncplayService.errorText
                font.pixelSize: ClockStyle.textNormal
                color: ClockStyle.colError
            }
        }

        ColumnLayout {
            visible: !root.working
            Layout.fillWidth: true
            spacing: ClockStyle.gap

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("Watch together")
                font.family: ClockStyle.fontTitle
                font.variableAxes: ClockStyle.axesTitle
                font.pixelSize: ClockStyle.textTitle
                color: ClockStyle.colOnSurface
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: ClockStyle.gapSmall
                text: Translation.tr("Everyone in a room plays the same video in step")
                font.pixelSize: ClockStyle.textNormal
                color: ClockStyle.colSubtext
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                ClockFormField {
                    id: hostField
                    Layout.fillWidth: true
                    symbol: "dns"
                    caption: Translation.tr("Server")
                    placeholder: "syncplay.pl"
                    onAccepted: nameField.focusInput()
                }

                ClockFormField {
                    id: portField
                    Layout.fillWidth: false
                    Layout.preferredWidth: 110
                    symbol: "numbers"
                    shapeKind: MaterialShape.Shape.Cookie9Sided
                    caption: Translation.tr("Port")
                    placeholder: "8999"
                    onAccepted: nameField.focusInput()
                }
            }

            Flow {
                visible: (root.defaults.publicServers ?? []).length > 0
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                Repeater {
                    model: root.defaults.publicServers ?? []

                    ClockChip {
                        required property string modelData
                        focusPolicy: Qt.NoFocus
                        label: modelData
                        selected: modelData === `${hostField.text}:${portField.text}`
                        onClicked: root.usePublicServer(modelData)
                    }
                }
            }

            ClockFormField {
                id: nameField
                symbol: "person"
                shapeKind: MaterialShape.Shape.Cookie12Sided
                caption: Translation.tr("Your name")
                onAccepted: roomField.focusInput()
            }

            ClockFormField {
                id: roomField
                symbol: "meeting_room"
                shapeKind: MaterialShape.Shape.Clover4Leaf
                caption: Translation.tr("Room")
                placeholder: Translation.tr("Anything you and your friends agree on")
                onAccepted: passwordField.focusInput()
            }

            Flow {
                visible: (root.defaults.rooms ?? []).length > 0
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                Repeater {
                    model: root.defaults.rooms ?? []

                    ClockChip {
                        required property string modelData
                        focusPolicy: Qt.NoFocus
                        label: modelData
                        selected: modelData === roomField.text
                        onClicked: roomField.text = modelData
                    }
                }
            }

            ClockFormField {
                id: passwordField
                symbol: "key"
                shapeKind: MaterialShape.Shape.Sunny
                caption: Translation.tr("Server password (if it has one)")
                onAccepted: root.connectNow()
                Component.onCompleted: input.echoMode = TextInput.Password
            }

            StyledText {
                visible: SyncplayService.errorText.length > 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: SyncplayService.errorText
                font.pixelSize: ClockStyle.textNormal
                color: ClockStyle.colError
            }

            ClockButton {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: ClockStyle.gapSmall
                variant: "filled"
                symbol: "login"
                label: Translation.tr("Join room")
                enabled: root.canConnect
                opacity: enabled ? 1 : 0.5
                onClicked: root.connectNow()
            }
        }
    }
}
