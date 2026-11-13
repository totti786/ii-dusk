pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "TorrentsFormat.js" as Fmt

/** The speed limits and the qBittorrent service. */
Item {
    id: root

    property bool compact: false
    property real layoutWidth: root.width
    property bool active: true

    readonly property bool up: TorrentsService.state === "up"

    function kib(bytes: real): string {
        return bytes > 0 ? String(Math.round(bytes / 1024)) : "";
    }

    function apply(): void {
        const down = parseInt(downField.text) || 0;
        const upl = parseInt(upField.text) || 0;
        TorrentsService.setLimits(down * 1024, upl * 1024);
    }

    function fill(): void {
        downField.text = root.kib(TorrentsService.downLimit);
        upField.text = root.kib(TorrentsService.upLimit);
    }

    readonly property var p: TorrentsService.prefs

    function load(): void {
        TorrentsService.loadLimits();
        TorrentsService.loadPrefs();
    }

    function num(field: var): int {
        const v = parseInt(field.text);
        return isNaN(v) ? 0 : v;
    }

    // The fields take their values from qBittorrent whenever its settings arrive
    function fillPrefs(): void {
        savePath.text = root.p.save_path ?? "";
        maxDl.text = String(root.p.max_active_downloads ?? "");
        maxUp.text = String(root.p.max_active_uploads ?? "");
        maxAll.text = String(root.p.max_active_torrents ?? "");
        altDown.text = String(root.p.alt_dl_limit ?? "");
        altUp.text = String(root.p.alt_up_limit ?? "");
        port.text = String(root.p.listen_port ?? "");
        maxConn.text = String(root.p.max_connec ?? "");
        ratio.text = String(root.p.max_ratio ?? "");
    }

    onActiveChanged: if (root.active && root.up) root.load()
    onUpChanged: if (root.up) root.load()
    onPChanged: root.fillPrefs()
    Component.onCompleted: if (root.up) root.load()

    Connections {
        target: TorrentsService
        function onDownLimitChanged() { root.fill(); }
        function onUpLimitChanged() { root.fill(); }
    }

    Flickable {
        WheelScroll {}
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: flick.width
            spacing: ClockStyle.paneGap

            ClockHero {
                Layout.fillWidth: true
                compact: root.compact
                symbol: "tune"
                shape: MaterialShape.Shape.SoftBurst
                title: Translation.tr("Keep it from hogging the line")
                text: Translation.tr("Limits apply to all torrents together. Leave a field empty for no limit.")
            }

            ClockPane {
                Layout.fillWidth: true
                title: Translation.tr("Speed limits")
                symbol: "speed"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gap
                    ClockFormField {
                        id: downField
                        Layout.fillWidth: true
                        symbol: "arrow_downward"
                        caption: Translation.tr("Download, KiB/s")
                        placeholder: Translation.tr("No limit")
                        enabled: root.up
                        onAccepted: root.apply()
                    }
                    ClockFormField {
                        id: upField
                        Layout.fillWidth: true
                        symbol: "arrow_upward"
                        caption: Translation.tr("Upload, KiB/s")
                        placeholder: Translation.tr("No limit")
                        enabled: root.up
                        onAccepted: root.apply()
                    }
                }
                ClockButton {
                    Layout.topMargin: ClockStyle.gapSmall
                    variant: "filled"
                    symbol: "check"
                    label: Translation.tr("Apply")
                    enabled: root.up
                    onClicked: root.apply()
                }
            }

            ClockPane {
                Layout.fillWidth: true
                visible: root.up
                title: Translation.tr("Downloads")
                symbol: "folder"
                shape: MaterialShape.Shape.Clover4Leaf

                ClockFormField {
                    id: savePath
                    Layout.fillWidth: true
                    symbol: "folder"
                    caption: Translation.tr("Default save folder")
                    onAccepted: TorrentsService.setPrefs({ "save_path": savePath.text.trim() })
                }
                ClockFormToggle {
                    symbol: "pause_circle"
                    label: Translation.tr("Start new torrents paused")
                    checked: root.p.start_paused_enabled ?? false
                    onToggled: checked => TorrentsService.setPrefs({ "start_paused_enabled": checked })
                }
                ClockButton {
                    variant: "tonal"
                    symbol: "check"
                    label: Translation.tr("Save folder")
                    onClicked: TorrentsService.setPrefs({ "save_path": savePath.text.trim() })
                }
            }

            ClockPane {
                Layout.fillWidth: true
                visible: root.up
                title: Translation.tr("Slow mode")
                symbol: "speed"
                shape: MaterialShape.Shape.SoftBurst

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Alternative limits you can switch on with one button, for when you need the line for something else.")
                    color: ClockStyle.colSubtext
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gap
                    ClockFormField {
                        id: altDown
                        Layout.fillWidth: true
                        symbol: "arrow_downward"
                        caption: Translation.tr("Download, KiB/s")
                        placeholder: Translation.tr("No limit")
                    }
                    ClockFormField {
                        id: altUp
                        Layout.fillWidth: true
                        symbol: "arrow_upward"
                        caption: Translation.tr("Upload, KiB/s")
                        placeholder: Translation.tr("No limit")
                    }
                }
                RowLayout {
                    spacing: ClockStyle.gapSmall
                    ClockButton {
                        variant: "tonal"
                        symbol: "check"
                        label: Translation.tr("Save limits")
                        onClicked: TorrentsService.setPrefs({ "alt_dl_limit": root.num(altDown), "alt_up_limit": root.num(altUp) })
                    }
                    ClockButton {
                        variant: TorrentsService.altSpeed ? "filled" : "tonal"
                        symbol: "speed"
                        label: TorrentsService.altSpeed ? Translation.tr("Turn slow mode off") : Translation.tr("Turn slow mode on")
                        onClicked: TorrentsService.toggleAltSpeed()
                    }
                }
            }

            ClockPane {
                Layout.fillWidth: true
                visible: root.up
                title: Translation.tr("Queue")
                symbol: "format_list_numbered"

                ClockFormToggle {
                    symbol: "format_list_numbered"
                    label: Translation.tr("Limit how many run at once")
                    description: Translation.tr("The rest wait in line, in the order you set")
                    checked: root.p.queueing_enabled ?? false
                    onToggled: checked => TorrentsService.setPrefs({ "queueing_enabled": checked })
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gap
                    ClockFormField { id: maxDl; Layout.fillWidth: true; symbol: "download"; caption: Translation.tr("Downloads at once") }
                    ClockFormField { id: maxUp; Layout.fillWidth: true; symbol: "upload"; caption: Translation.tr("Uploads at once") }
                    ClockFormField { id: maxAll; Layout.fillWidth: true; symbol: "all_inbox"; caption: Translation.tr("Active in all") }
                }
                ClockButton {
                    variant: "tonal"
                    symbol: "check"
                    label: Translation.tr("Save queue limits")
                    onClicked: TorrentsService.setPrefs({ "max_active_downloads": root.num(maxDl), "max_active_uploads": root.num(maxUp), "max_active_torrents": root.num(maxAll) })
                }
            }

            ClockPane {
                Layout.fillWidth: true
                visible: root.up
                title: Translation.tr("Connection")
                symbol: "lan"
                shape: MaterialShape.Shape.Clover4Leaf

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gap
                    ClockFormField { id: port; Layout.fillWidth: true; symbol: "tag"; caption: Translation.tr("Port for incoming connections") }
                    ClockFormField { id: maxConn; Layout.fillWidth: true; symbol: "hub"; caption: Translation.tr("Most connections") }
                }
                ClockFormToggle {
                    symbol: "router"
                    label: Translation.tr("Open the port automatically (UPnP)")
                    checked: root.p.upnp ?? false
                    onToggled: checked => TorrentsService.setPrefs({ "upnp": checked })
                }
                ClockFormToggle {
                    symbol: "share"
                    label: Translation.tr("Find peers without a tracker (DHT)")
                    checked: root.p.dht ?? false
                    onToggled: checked => TorrentsService.setPrefs({ "dht": checked })
                }
                ClockFormToggle {
                    symbol: "swap_horiz"
                    label: Translation.tr("Swap peer lists with peers (PeX)")
                    checked: root.p.pex ?? false
                    onToggled: checked => TorrentsService.setPrefs({ "pex": checked })
                }
                ClockFormToggle {
                    symbol: "wifi_tethering"
                    label: Translation.tr("Find peers on this network (LSD)")
                    checked: root.p.lsd ?? false
                    onToggled: checked => TorrentsService.setPrefs({ "lsd": checked })
                }
                StyledText {
                    Layout.topMargin: ClockStyle.gapSmall
                    text: Translation.tr("Encryption")
                    color: ClockStyle.colOnBackground
                    font.weight: Font.DemiBold
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall
                    Repeater {
                        model: [{ v: 0, l: Translation.tr("Prefer it") }, { v: 1, l: Translation.tr("Require it") }, { v: 2, l: Translation.tr("Off") }]
                        delegate: ClockChip {
                            required property var modelData
                            label: modelData.l
                            selected: (root.p.encryption ?? 0) === modelData.v
                            onClicked: TorrentsService.setPrefs({ "encryption": modelData.v })
                        }
                    }
                }
                ClockButton {
                    Layout.topMargin: ClockStyle.gapSmall
                    variant: "tonal"
                    symbol: "check"
                    label: Translation.tr("Save port and connections")
                    onClicked: TorrentsService.setPrefs({ "listen_port": root.num(port), "max_connec": root.num(maxConn) })
                }
            }

            ClockPane {
                Layout.fillWidth: true
                visible: root.up
                title: Translation.tr("Sharing")
                symbol: "volunteer_activism"

                ClockFormToggle {
                    symbol: "balance"
                    label: Translation.tr("Stop seeding at a ratio")
                    description: Translation.tr("A ratio of 1 means you have uploaded as much as you downloaded")
                    checked: root.p.max_ratio_enabled ?? false
                    onToggled: checked => TorrentsService.setPrefs({ "max_ratio_enabled": checked })
                }
                ClockFormField { id: ratio; Layout.fillWidth: true; symbol: "percent"; caption: Translation.tr("Ratio") }
                ClockButton {
                    variant: "tonal"
                    symbol: "check"
                    label: Translation.tr("Save ratio")
                    onClicked: TorrentsService.setPrefs({ "max_ratio": parseFloat(ratio.text) || 0 })
                }
            }

            ClockPane {
                Layout.fillWidth: true
                title: Translation.tr("qBittorrent")
                symbol: "dns"
                shape: MaterialShape.Shape.Clover4Leaf

                StyledText {
                    Layout.fillWidth: true
                    text: root.up ? Translation.tr("Running at %1").arg(TorrentsService.address)
                        : TorrentsService.state === "denied" ? Translation.tr("Running at %1, but it asks for a password. Turn on \"Bypass authentication for clients on localhost\" in its web interface settings.").arg(TorrentsService.address)
                        : Translation.tr("Not running. The shell looks for it at %1.").arg(TorrentsService.address)
                    color: ClockStyle.colSubtext
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    spacing: ClockStyle.gapSmall
                    ClockButton {
                        visible: TorrentsService.state === "down"
                        variant: "filled"
                        symbol: "play_arrow"
                        label: Translation.tr("Start qBittorrent")
                        onClicked: TorrentsService.startService()
                    }
                    ClockButton {
                        visible: root.up
                        variant: "tonal"
                        danger: true
                        symbol: "stop"
                        label: Translation.tr("Quit qBittorrent")
                        onClicked: TorrentsService.shutdownService()
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: TorrentsService.lastError.length > 0
                    text: TorrentsService.lastError
                    color: ClockStyle.colError
                    font.pixelSize: ClockStyle.textSmall
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
