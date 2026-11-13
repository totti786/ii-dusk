pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The Lite family's launcher: a search box and a short list of apps, nothing else. It answers
 * the same keys as the full overview (the Super tap, Super+Space style binds), because those
 * are global shortcuts the overview normally owns and this family has no overview.
 * The window exists only while it is open.
 */
Scope {
    id: root

    readonly property bool open: GlobalStates.overviewOpen
    property string query: ""
    property int current: 0
    readonly property var results: {
        const found = AppSearch.fuzzyQuery(root.query);
        return found.slice(0, 8);
    }

    function close(): void {
        GlobalStates.closeOverview();
    }

    function launch(entry: var): void {
        if (!entry)
            return;
        entry.execute();
        root.close();
    }

    onOpenChanged: {
        root.query = "";
        root.current = 0;
    }

    // ── the keys the overview normally owns ──
    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"
        onPressed: GlobalStates.toggleOverview()
    }
    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"
        onPressed: GlobalStates.toggleOverview()
    }
    GlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"
        onPressed: GlobalStates.closeOverview()
    }
    GlobalShortcut {
        name: "searchOnlyToggle"
        description: "Toggles search only mode on press"
        onPressed: GlobalStates.toggleOverview()
    }
    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on overview widget"
        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
            GlobalStates.toggleOverview();
        }
    }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on release"
        property int lastToggle: 0
        onPressed: GlobalStates.superReleaseMightTrigger = true
        onReleased: {
            const now = Date.now();
            if (now - lastToggle < 50)
                return;
            lastToggle = now;
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            GlobalStates.toggleOverview();
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release."
        onPressed: GlobalStates.superReleaseMightTrigger = false
    }

    LazyLoader {
        active: root.open

        PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "quickshell:overview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            // A click outside the box closes it
            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.35)
            }

            Rectangle {
                id: box
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.18
                width: Math.min(560, parent.width - 40)
                height: column.implicitHeight + 24
                radius: 18
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                MouseArea { anchors.fill: parent }  // swallow clicks

                ColumnLayout {
                    id: column
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        MaterialSymbol {
                            text: "search"
                            iconSize: 22
                            color: Appearance.colors.colSubtext
                        }
                        TextInput {
                            id: field
                            Layout.fillWidth: true
                            color: Appearance.colors.colOnLayer0
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.family: Appearance.font.family.main
                            selectionColor: Appearance.colors.colPrimary
                            focus: true
                            clip: true
                            onTextChanged: {
                                root.query = text;
                                root.current = 0;
                            }
                            Component.onCompleted: forceActiveFocus()

                            Keys.onEscapePressed: root.close()
                            Keys.onReturnPressed: root.launch(root.results[root.current])
                            Keys.onEnterPressed: root.launch(root.results[root.current])
                            Keys.onDownPressed: root.current = Math.min(root.results.length - 1, root.current + 1)
                            Keys.onUpPressed: root.current = Math.max(0, root.current - 1)
                            Keys.onTabPressed: root.current = (root.current + 1) % Math.max(1, root.results.length)
                        }
                    }

                    Repeater {
                        model: root.results
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            implicitHeight: 42
                            radius: 12
                            color: root.current === row.index ? Appearance.colors.colSecondaryContainer
                                : hover.containsMouse ? Appearance.colors.colLayer2 : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 12
                                IconImage {
                                    implicitSize: 26
                                    source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                                    asynchronous: true
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: row.modelData.name
                                    color: Appearance.colors.colOnLayer0
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                id: hover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.current = row.index
                                onClicked: root.launch(row.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
