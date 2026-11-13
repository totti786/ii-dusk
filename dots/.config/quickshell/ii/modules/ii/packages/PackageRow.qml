pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "PackagesFormat.js" as Fmt

/**
 * One package in a list: name and version, what it is, which repository it came from, and
 * room on the right for the buttons the page wants. Clicking the row asks for its details.
 */
Rectangle {
    id: root

    required property string name
    property string version: ""
    /// Shown instead of the version when a package is changing: "1.0 -> 1.1"
    property string versionChange: ""
    property string description: ""
    property string repo: ""
    property real size: 0
    property bool explicit: false
    property bool installed: false
    property bool restartAdvised: false
    default property alias actions: actionRow.data

    signal clicked()

    implicitHeight: 64
    radius: ClockStyle.radiusLarge
    color: hover.hovered ? ClockStyle.colSurfaceHighest : ClockStyle.colSurfaceHigh

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: hover
    }
    TapHandler {
        onTapped: root.clicked()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: ClockStyle.gap
        anchors.rightMargin: ClockStyle.gapSmall
        spacing: ClockStyle.gap

        Rectangle {
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            radius: ClockStyle.radiusNormal
            color: root.repo === "aur" ? ClockStyle.colTertiaryContainer : ClockStyle.colSecondaryContainer
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.repo === "aur" ? "deployed_code" : "package_2"
                iconSize: 22
                color: root.repo === "aur" ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnSecondaryContainer
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall
                StyledText {
                    text: root.name
                    color: ClockStyle.colOnBackground
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    Layout.maximumWidth: 360
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.versionChange !== "" ? root.versionChange : root.version
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                    elide: Text.ElideRight
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.description
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
                elide: Text.ElideRight
            }
        }

        StyledText {
            visible: root.restartAdvised
            text: Translation.tr("Restart advised")
            color: ClockStyle.colTertiary
            font.pixelSize: ClockStyle.textSmall
        }
        StyledText {
            visible: root.installed
            text: Translation.tr("Installed")
            color: ClockStyle.colPrimary
            font.pixelSize: ClockStyle.textSmall
        }
        StyledText {
            visible: root.size > 0
            text: Fmt.bytes(root.size)
            color: ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textSmall
            font.family: ClockStyle.fontNumbers
        }
        StyledText {
            visible: root.repo !== ""
            text: root.repo
            color: ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textSmall
        }
        RowLayout {
            id: actionRow
            spacing: ClockStyle.gapTiny
        }
    }
}
