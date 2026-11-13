pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** Which hosts the latency tests ping. A host of "gateway" is your router, found automatically. */
Flickable {
    WheelScroll {}
    id: root

    property bool compact: false
    // The rows being edited live in a plain array that is changed in place, so typing does not
    // rebuild the fields (and drop focus); `rev` tells the bindings that read it to look again.
    property var edits: []
    property int count: 0
    property int rev: 0
    readonly property bool changed: { root.rev; return JSON.stringify(root.cleaned()) !== JSON.stringify(MonitorService.targets); }

    function cleaned(): var {
        return root.edits.filter(r => r.host.trim() !== "").map(r => ({ name: r.name.trim() || r.host.trim(), host: r.host.trim() }));
    }

    /// Replace all rows; the fields are rebuilt so each shows its new text
    function rebuild(rows: var): void {
        root.count = 0;
        root.edits = rows.map(r => ({ name: r.name, host: r.host }));
        Qt.callLater(() => {
            root.count = root.edits.length;
            root.rev++;
        });
    }

    function load(): void {
        root.rebuild(MonitorService.targets);
    }

    function edit(i: int, key: string, value: string): void {
        root.edits[i][key] = value;
        root.rev++;
    }

    Component.onCompleted: root.load()
    Connections {
        target: MonitorService
        function onTargetsChanged() { root.load(); }
    }

    contentWidth: width
    contentHeight: column.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: column
        width: Math.min(root.width, 680)
        x: (root.width - width) / 2
        spacing: 12

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Translation.tr("These hosts are pinged once a second while the Monitor is open. Use a host name or an address; \"gateway\" means your router (now %1).").arg(MonitorService.gateway !== "" ? MonitorService.gateway : "unknown")
            color: ClockStyle.colSubtext
        }

        Repeater {
            model: root.count
            delegate: RowLayout {
                id: target
                required property int index
                Layout.fillWidth: true
                spacing: 8
                ClockFormField {
                    Layout.preferredWidth: 180
                    symbol: "label"
                    placeholder: Translation.tr("Name")
                    text: root.edits[target.index]?.name ?? ""
                    input.onTextEdited: root.edit(target.index, "name", text)
                }
                ClockFormField {
                    Layout.fillWidth: true
                    symbol: "dns"
                    placeholder: Translation.tr("Host or IP")
                    text: root.edits[target.index]?.host ?? ""
                    input.onTextEdited: root.edit(target.index, "host", text)
                }
                ClockIconButton {
                    symbol: "delete"
                    tooltip: Translation.tr("Remove")
                    visible: root.count > 1
                    onClicked: root.rebuild(root.edits.filter((r, i) => i !== target.index))
                }
            }
        }

        RowLayout {
            spacing: 10
            ClockButton {
                variant: "text"
                symbol: "add"
                label: Translation.tr("Add a target")
                visible: root.count < 6
                onClicked: root.rebuild(root.edits.concat([{ name: "", host: "" }]))
            }
            ClockButton {
                variant: "text"
                symbol: "restart_alt"
                label: Translation.tr("Defaults")
                onClicked: root.rebuild(MonitorService.defaultTargets)
            }
            Item { Layout.fillWidth: true }
            ClockButton {
                variant: "filled"
                symbol: "check"
                label: MonitorService.saving ? Translation.tr("Saving…") : Translation.tr("Save")
                enabled: root.changed && !MonitorService.saving
                onClicked: MonitorService.saveTargets(root.cleaned())
            }
        }

        StyledText {
            visible: MonitorService.saveError !== ""
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: MonitorService.saveError
            color: ClockStyle.colError
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Translation.tr("Saved in %1").arg(MonitorService.configPath)
            color: ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textSmall
        }
    }
}
