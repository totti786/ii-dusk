import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Fan control for laptops that have no kernel fan driver: pick the nbfc config for the model,
 * ii-fand turns it into an EC register profile, the registers are read back (password), and
 * only then is it stored. Shown while no fan backend was found.
 */
Rectangle {
    id: root

    readonly property string product: FanControl.caps?.product ?? ""
    readonly property var matches: {
        const q = search.text.trim().toLowerCase();
        if (q.length === 0)
            return [];
        return FanControl.ecConfigs.filter(c => c.name.toLowerCase().includes(q)).slice(0, 8);
    }
    readonly property bool isPath: search.text.trim().startsWith("/")

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 40
    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1

    Component.onCompleted: {
        FanControl.ecScan();
        search.text = root.product;
    }

    ColumnLayout {
        id: col
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 20
        }
        spacing: 12

        StyledText {
            text: Translation.tr("Set up fan control for this laptop")
            font.family: Appearance.font.family.title
            font.variableAxes: Appearance.font.variableAxes.titleRounded
            font.pixelSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("The kernel has no fan driver for %1. If an nbfc config exists for it, ii-fand can drive the fans through the embedded controller. Configs are written for specific models: the registers are read back and shown before anything is enabled.").arg(root.product || Translation.tr("this model"))
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        StyledText {
            Layout.fillWidth: true
            visible: !FanControl.ecReady
            text: Translation.tr("Install or update the thermal service above first.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colError
            wrapMode: Text.WordWrap
        }

        MaterialTextField {
            id: search
            Layout.fillWidth: true
            enabled: FanControl.ecReady
            placeholderText: Translation.tr("Search nbfc configs, or paste a path to an .xml file")
        }

        StyledText {
            Layout.fillWidth: true
            visible: FanControl.ecReady && !root.isPath
            text: FanControl.ecConfigs.length === 0
                ? Translation.tr("No nbfc configs found. Put .xml configs in ~/.local/share/ii-fand/nbfc-configs, or paste a file path above.")
                : root.matches.length === 0
                    ? Translation.tr("No config matches “%1”. Try a shorter name; a similar model's config may use different registers.").arg(search.text.trim())
                    : ""
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        RippleButton {
            Layout.fillWidth: true
            visible: root.isPath
            implicitHeight: 40
            buttonRadius: Appearance.rounding.small
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            onClicked: FanControl.ecPick(search.text.trim())
            contentItem: StyledText {
                leftPadding: 12
                verticalAlignment: Text.AlignVCenter
                text: Translation.tr("Use %1").arg(search.text.trim())
                color: Appearance.colors.colOnLayer2
                elide: Text.ElideMiddle
            }
        }

        Repeater {
            model: root.isPath ? [] : root.matches
            delegate: RippleButton {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 40
                buttonRadius: Appearance.rounding.small
                toggled: FanControl.ecSelected === modelData.path
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colRipple: Appearance.colors.colLayer2Active
                onClicked: FanControl.ecPick(modelData.path)
                contentItem: StyledText {
                    leftPadding: 12
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.name
                    color: parent.parent.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                }
            }
        }

        // ── what ii-fand made of the pick ──
        StyledText {
            Layout.fillWidth: true
            visible: FanControl.ecImportError.length > 0
            text: FanControl.ecImportError
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colError
            wrapMode: Text.WordWrap
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: FanControl.ecImported !== null
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
                wrapMode: Text.WordWrap
                text: {
                    const p = FanControl.ecImported?.profile;
                    if (!p)
                        return "";
                    const hex = n => "0x" + n.toString(16).padStart(2, "0");
                    const lines = p.fans.map(f => `${Translation.tr("Fan")} ${f.label}: ${Translation.tr("register")} ${hex(f.reg)}, 0–${f.steps} ${Translation.tr("steps")}`);
                    p.setup.forEach(w => lines.push(`${Translation.tr("Manual mode")}: ${hex(w.reg)} = ${hex(w.manual)} (${Translation.tr("firmware")} ${hex(w.auto)})`));
                    return lines.join("\n");
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: FanControl.ecChecked
                text: FanControl.ecCheckText
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colPrimary
                wrapMode: Text.WordWrap
            }
            StyledText {
                Layout.fillWidth: true
                visible: FanControl.ecChecked
                text: Translation.tr("These are the live register values. If they look unrelated to your fans (for example a fan register holding a large number), do not enable it.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }
                RippleButton {
                    implicitHeight: 40
                    implicitWidth: readLabel.implicitWidth + 32
                    buttonRadius: height / 2
                    enabled: !FanControl.ecBusy
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    onClicked: FanControl.ecReadRegisters()
                    contentItem: Item {
                        StyledText {
                            id: readLabel
                            anchors.centerIn: parent
                            text: Translation.tr("Read registers")
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
                RippleButton {
                    implicitHeight: 40
                    implicitWidth: enableLabel.implicitWidth + 32
                    buttonRadius: height / 2
                    enabled: FanControl.ecChecked && !FanControl.ecBusy
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    onClicked: FanControl.ecEnable()
                    contentItem: Item {
                        StyledText {
                            id: enableLabel
                            anchors.centerIn: parent
                            text: Translation.tr("Enable")
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: FanControl.lastError.length > 0
            text: FanControl.lastError
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colError
            wrapMode: Text.WordWrap
        }
    }
}
