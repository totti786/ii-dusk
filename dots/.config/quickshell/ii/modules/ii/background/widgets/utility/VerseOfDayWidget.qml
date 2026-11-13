pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/*
 * Verse of the Day (wide). One bayt from the Diwan reader's daily poem, set like a
 * printed diwan: the sadr on the right and the ajuz on the left with a small
 * ornament between them, in Amiri, under a hairline that fades in from the accent.
 * Beneath, the poet and the poem, and the era and meter as quiet chips. A tap opens
 * the whole poem in the reader. A verse with no second half (free verse) is centred.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "diwan_verse"

    // A strip (the bayt and the poet), a tile (the bayt stacked), the wide card, and a big one
    // that adds the era and meter and a button into the poem.
    supportedSizes: ["2x0.5", "1x1", "2x1", "2x2"]
    defaultSize: "2x1"
    readonly property bool strip: root.sizeClass === "2x0.5"
    readonly property bool tile: root.sizeClass === "1x1"
    readonly property bool tall: root.sizeClass === "2x2"

    readonly property real padding: root.tile ? 18 : 24
    readonly property var daily: DiwanDaily.daily
    readonly property var halves: root.daily?.verse ?? []
    readonly property bool paired: root.halves.length >= 2

    readonly property color textColor: root.cardScheme.textColorOnBg
    readonly property color subtextColor: root.cardScheme.subtextColorOnBg
    readonly property color accentColor: root.cardScheme.accentColor
    readonly property color faint: ColorUtils.applyAlpha(root.textColor, 0.10)
    readonly property string family: "Amiri"

    Component.onCompleted: DiwanDaily.requestData()
    Component.onDestruction: DiwanDaily.releaseData()

    // A faint open book in the corner, behind everything
    MaterialSymbol {
        parent: root.contentItem
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: -18
        anchors.bottomMargin: -26
        text: "auto_stories"
        iconSize: 150
        fill: 1
        color: ColorUtils.applyAlpha(root.accentColor, 0.07)
    }

    // The accent hairline across the top, fading out to both sides
    Rectangle {
        parent: root.contentItem
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        width: parent.width * 0.5
        height: 2
        radius: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.5; color: root.accentColor }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding
        anchors.topMargin: root.strip ? 10 : 18
        anchors.bottomMargin: root.strip ? 10 : (root.tall ? 70 : 18)
        spacing: 0

        // Caption: the occasion on the right, the era on the left
        RowLayout {
            visible: !root.strip
            Layout.fillWidth: true
            layoutDirection: Qt.RightToLeft
            spacing: 8

            MaterialSymbol {
                text: "auto_stories"
                iconSize: Appearance.font.pixelSize.larger
                fill: 1
                color: root.accentColor
            }
            Text {
                text: "بيت اليوم"
                font.family: root.family
                font.pixelSize: 21
                color: root.accentColor
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                visible: (root.daily?.era ?? "") !== "" && !root.tile && !root.tall
                implicitWidth: eraText.implicitWidth + 20
                implicitHeight: 24
                radius: root.pill(height)
                color: root.faint
                Text {
                    id: eraText
                    anchors.centerIn: parent
                    text: root.daily?.era ?? ""
                    font.family: root.family
                    font.pixelSize: 16
                    color: root.subtextColor
                }
            }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 6 }

        // The bayt
        Item {
            id: bayt
            Layout.fillWidth: true
            Layout.preferredHeight: bayt.stacked ? Math.ceil(sadr.implicitHeight * 2 + 2) : 60
            visible: root.halves.length > 0

            readonly property real gap: 52
            readonly property real half: root.paired ? (width - bayt.gap) / 2 : width
            // One size for both halves: the largest at which the longer still fits
            readonly property real wide: Math.max(measureA.implicitWidth, measureB.implicitWidth, 1)
            readonly property real sideSize: Math.max(18, Math.min(36, 36 * bayt.half / bayt.wide))
            // A long bayt would shrink to fine print side by side: the halves then stack, each on its
            // own line at the full width, the sadr to the right and the ajuz to the left
            readonly property bool stacked: root.paired && !root.strip && (root.tile || root.tall || bayt.sideSize < 27)
            readonly property real size: bayt.stacked ? Math.max(18, Math.min(root.tall ? 40 : 27, 36 * bayt.width * 0.94 / bayt.wide))
                : (root.strip ? Math.min(bayt.sideSize, 26) : bayt.sideSize)

            Text { id: measureA; visible: false; text: root.halves[0] ?? ""; font.family: root.family; font.pixelSize: 36 }
            Text { id: measureB; visible: false; text: root.halves[1] ?? ""; font.family: root.family; font.pixelSize: 36 }

            // The sadr, on the right
            Text {
                id: sadr
                anchors.right: parent.right
                y: bayt.stacked ? 0 : (bayt.height - height) / 2
                width: bayt.stacked ? bayt.width : bayt.half
                text: root.halves[0] ?? ""
                horizontalAlignment: root.paired ? Text.AlignRight : Text.AlignHCenter
                font.family: root.family
                font.pixelSize: bayt.size
                color: root.textColor
                elide: Text.ElideLeft
            }

            // The ornament between the halves
            Rectangle {
                visible: root.paired && !bayt.stacked
                anchors.centerIn: parent
                width: 9
                height: 9
                rotation: 45
                color: root.accentColor
            }
            Rectangle {
                visible: root.paired && !bayt.stacked
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: 16
                width: 3
                height: 3
                rotation: 45
                color: ColorUtils.applyAlpha(root.accentColor, 0.6)
            }
            Rectangle {
                visible: root.paired && !bayt.stacked
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: -16
                width: 3
                height: 3
                rotation: 45
                color: ColorUtils.applyAlpha(root.accentColor, 0.6)
            }

            // The ajuz, on the left
            Text {
                visible: root.paired
                anchors.left: parent.left
                y: bayt.stacked ? sadr.implicitHeight + 2 : (bayt.height - height) / 2
                width: bayt.stacked ? bayt.width : bayt.half
                text: root.halves[1] ?? ""
                horizontalAlignment: Text.AlignLeft
                font.family: root.family
                font.pixelSize: bayt.size
                color: root.textColor
                elide: Text.ElideRight
            }
        }

        // Nothing yet: the read is under way, or it failed
        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            visible: root.halves.length === 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: DiwanDaily.error !== "" ? DiwanDaily.error : "جارٍ اختيار بيت اليوم…"
            wrapMode: Text.Wrap
            font.family: root.family
            font.pixelSize: 21
            color: root.subtextColor
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 6 }

        // The era and the meter as chips, where there is room for them
        RowLayout {
            visible: root.tall
            Layout.fillWidth: true
            Layout.bottomMargin: 10
            layoutDirection: Qt.RightToLeft
            spacing: 8
            Repeater {
                model: [root.daily?.era ?? "", (root.daily?.meter ?? "") !== "غير معروف" ? (root.daily?.meter ?? "") : ""].filter(t => t !== "")
                delegate: Rectangle {
                    id: chip
                    required property string modelData
                    implicitWidth: chipText.implicitWidth + 22
                    implicitHeight: 26
                    radius: root.pill(height)
                    color: root.faint
                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: chip.modelData
                        font.family: root.family
                        font.pixelSize: 17
                        color: root.subtextColor
                    }
                }
            }
            Item { Layout.fillWidth: true }
        }

        // A thin rule with the poem under it
        Rectangle {
            visible: !root.strip
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: root.faint
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: root.strip ? 0 : 10
            layoutDirection: Qt.RightToLeft
            spacing: 10

            Text {
                Layout.maximumWidth: parent.width * (root.tile ? 1 : 0.5)
                text: root.daily?.poet ?? ""
                font.family: root.family
                font.pixelSize: 22
                color: root.accentColor
                elide: Text.ElideLeft
            }
            Rectangle {
                visible: (root.daily?.title ?? "") !== "" && !root.tile
                Layout.preferredWidth: 4
                Layout.preferredHeight: 4
                radius: 2
                color: root.subtextColor
            }
            Text {
                Layout.fillWidth: true
                visible: !root.tile
                text: root.daily?.title ?? ""
                horizontalAlignment: Text.AlignRight
                font.family: root.family
                font.pixelSize: 19
                color: root.subtextColor
                elide: Text.ElideLeft
            }
            Text {
                visible: (root.daily?.meter ?? "") !== "" && root.daily.meter !== "غير معروف" && !root.tile && !root.tall && !root.strip
                text: root.daily?.meter ?? ""
                font.family: root.family
                font.pixelSize: 17
                color: root.subtextColor
                opacity: 0.8
            }
        }
    }

    // The big card's way into the whole poem
    WidgetButton {
        visible: root.tall
        x: root.padding
        y: root.designHeight - 18 - 40
        width: root.designWidth - root.padding * 2
        height: 40
        symbol: "menu_book"
        symbolSize: 20
        label: "اقرأ القصيدة"
        labelSize: 16
        colFill: root.accentColor
        colContent: root.cardScheme.onAccentColor
        onClicked: {
            if (root.daily === null)
                return;
            GlobalStates.diwanPendingSlug = root.daily.slug;
            GlobalStates.openDiwanApp();
        }
    }

    // The widget is itself the mouse area that drags it, so a click is read here
    // rather than from a second area on top, which would swallow the presses
    cursorShape: root.editModeActive ? Qt.ArrowCursor : Qt.PointingHandCursor
    // A drag ends in a release too, so a click only counts if the pointer stayed put
    property point pressAt: Qt.point(0, 0)
    Connections {
        target: root
        function onPressed(mouse) { root.pressAt = Qt.point(mouse.x, mouse.y); }
    }
    onClicked: mouse => {
        if (Math.hypot(mouse.x - root.pressAt.x, mouse.y - root.pressAt.y) > 6)
            return;
        if (!root.actionsEnabled || root.editModeActive || root.isDragging || root.daily === null)
            return;
        GlobalStates.diwanPendingSlug = root.daily.slug;
        GlobalStates.openDiwanApp();
    }
}
