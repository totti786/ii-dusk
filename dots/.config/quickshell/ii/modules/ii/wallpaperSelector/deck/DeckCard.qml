import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects

/**
 * One card of the deck picker: the wallpaper, then the scheme it would give the desktop as
 * five paint chips (primary, secondary, tertiary, container, surface), then its name and size.
 * Until the palette arrives the card wears the shell's own colours and the chips are blank.
 *
 * The card layout follows https://github.com/dhrruvsharma/qs-wallpaperpicker (GPL-3.0).
 */
Item {
    id: card

    required property string path
    property string fileName: ""
    property var palette: null // role -> "#rrggbb"
    property var imageSize: null // { w, h }
    property real fileBytes: 0
    property bool current: false // the wallpaper on screen now
    property bool favourite: false
    // A Wallhaven result: its picture is a URL, its colours the five Wallhaven reads from it,
    // and its details come as text (there is no file to look at yet).
    property string thumbUrl: ""
    property var imageColors: []
    property string detailText: ""
    property real front: 0 // 0..1: how much this card is the one in front
    property real u: 1 // pixel unit: scales with the screen

    readonly property real pad: 8 * u
    readonly property real chipHeight: 20 * u
    readonly property real chipGap: 3 * u
    readonly property real thumbHeight: Math.round((width - pad * 2) * 10 / 16)
    readonly property real footerHeight: 44 * u
    // The thumbnail size the card's picture is read at: what the deck generates, and what its
    // backdrop shows until the real file is decoded.
    readonly property string thumbSizeName: thumb.thumbnailSizeName
    readonly property real naturalHeight: pad + thumbHeight + pad + 5 * chipHeight + 4 * chipGap + 4 * u + footerHeight

    width: 212 * u
    height: naturalHeight

    function pick(role, fallback) {
        return card.palette && card.palette[role] ? card.palette[role] : fallback;
    }
    readonly property color surface: pick("surface_container_high", Appearance.m3colors.m3surfaceContainerHigh)
    readonly property color ink: pick("on_surface", Appearance.m3colors.m3onSurface)
    readonly property color muted: pick("on_surface_variant", Appearance.m3colors.m3onSurfaceVariant)
    readonly property color line: pick("outline_variant", Appearance.m3colors.m3outlineVariant)
    readonly property color accent: pick("primary", Appearance.colors.colPrimary)
    readonly property color accentInk: pick("on_primary", Appearance.colors.colOnPrimary)

    // Light or dark ink for a chip of this colour.
    function inkFor(fill) {
        const c = Qt.color(fill);
        return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.6 ? "#1b1b1f" : "#f4f4f6";
    }
    readonly property var chips: (!card.palette && card.imageColors && card.imageColors.length > 0)
        ? card.imageColors.slice(0, 5).map(c => ({ "label": "", "fill": "#" + String(c).replace("#", ""), "ink": card.inkFor("#" + String(c).replace("#", "")) }))
        : [
        { "label": "primary", "fill": pick("primary", ""), "ink": pick("on_primary", "") },
        { "label": "secondary", "fill": pick("secondary", ""), "ink": pick("on_secondary", "") },
        { "label": "tertiary", "fill": pick("tertiary", ""), "ink": pick("on_tertiary", "") },
        { "label": "container", "fill": pick("primary_container", ""), "ink": pick("on_primary_container", "") },
        { "label": "surface", "fill": pick("surface_container_highest", ""), "ink": pick("on_surface", "") }
    ]

    function fileDetail() {
        const ext = card.path.indexOf(".") >= 0 ? card.path.split(".").pop().toUpperCase() : "";
        const parts = [ext];
        if (card.imageSize && card.imageSize.w > 0)
            parts.push(card.imageSize.w + " × " + card.imageSize.h);
        if (card.fileBytes > 0)
            parts.push(card.fileBytes >= 1048576 ? (card.fileBytes / 1048576).toFixed(1) + " MB" : Math.round(card.fileBytes / 1024) + " KB");
        return parts.filter(p => p.length > 0).join("  ·  ");
    }
    readonly property string detail: card.detailText !== "" ? card.detailText : card.fileDetail()

    // Static, cached shadow. This used to animate blur (22 -> 40 px), offset and
    // opacity with the card's `front`, so every frame re-rendered this shader for
    // each of the ~19 cards in the fan. That is the GPU workload that hangs the
    // i915 (GPU HANG in QSGRenderThread). Keep it constant and cached: one render
    // per card, and the deck keeps its soft shadow.
    RectangularShadow {
        anchors.fill: body
        offset.y: 12 * card.u
        blur: 16 * card.u
        radius: body.radius
        color: Qt.rgba(0, 0, 0, 0.5)
        cached: true
    }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: 14 * card.u
        antialiasing: true
        color: card.surface
        border.width: Math.max(1, card.u * (1 + card.front * 0.8))
        border.color: Qt.tint(ColorUtils.transparentize(card.line, 0.15), ColorUtils.transparentize(card.accent, 1 - card.front * 0.85))
        Behavior on color { ColorAnimation { duration: 160 } }

        Rectangle {
            id: thumbBase
            x: card.pad
            y: card.pad
            width: parent.width - card.pad * 2
            height: card.thumbHeight
            radius: 7 * card.u
            color: Appearance.m3colors.m3surfaceContainerLow
            antialiasing: true

            ThumbnailImage {
                id: thumb
                anchors.fill: parent
                visible: card.thumbUrl === ""
                sourcePath: card.thumbUrl === "" ? card.path : ""
                generateThumbnail: card.thumbUrl === ""
                thumbnailService: Wallpapers
                fillMode: Image.PreserveAspectCrop
            }
            Image {
                anchors.fill: parent
                visible: card.thumbUrl !== ""
                source: card.thumbUrl
                sourceSize: Qt.size(Math.ceil(parent.width * 1.5), Math.ceil(parent.height * 1.5))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220 } }
            }
        }

        // Rounds the picture's corners: a frame in the card's own colour whose inside edge is
        // the rounded corner (cheaper than a mask).
        Rectangle {
            x: thumbBase.x - border.width
            y: thumbBase.y - border.width
            width: thumbBase.width + border.width * 2
            height: thumbBase.height + border.width * 2
            radius: thumbBase.radius + border.width
            antialiasing: true
            color: "transparent"
            border.width: 5 * card.u
            border.color: card.surface
        }

        Rectangle {
            visible: card.current
            x: thumbBase.x + 7 * card.u
            y: thumbBase.y + thumbBase.height - height - 7 * card.u
            width: currentRow.implicitWidth + 12 * card.u
            height: 19 * card.u
            radius: height / 2
            color: card.accent
            Row {
                id: currentRow
                anchors.centerIn: parent
                spacing: 3 * card.u
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "check"
                    iconSize: 12 * card.u
                    color: card.accentInk
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("current")
                    font.pixelSize: 10 * card.u
                    font.weight: Font.DemiBold
                    color: card.accentInk
                }
            }
        }

        MaterialSymbol {
            visible: card.favourite
            x: thumbBase.x + thumbBase.width - width - 7 * card.u
            y: thumbBase.y + 7 * card.u
            text: "favorite"
            fill: 1
            iconSize: 16 * card.u
            color: card.accent
        }

        Column {
            id: chipColumn
            x: card.pad
            y: thumbBase.y + thumbBase.height + card.pad
            width: parent.width - card.pad * 2
            spacing: card.chipGap

            Repeater {
                model: card.chips
                delegate: Rectangle {
                    required property var modelData
                    width: chipColumn.width
                    height: card.chipHeight
                    radius: 4 * card.u
                    antialiasing: true
                    color: modelData.fill !== "" ? modelData.fill : ColorUtils.transparentize(card.muted, 0.85)
                    Behavior on color { ColorAnimation { duration: 160 } }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 7 * card.u
                        text: modelData.label.toUpperCase()
                        visible: modelData.fill !== ""
                        font.pixelSize: 9 * card.u
                        font.weight: Font.Bold
                        font.letterSpacing: 0.6
                        color: modelData.ink !== "" ? modelData.ink : card.ink
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 7 * card.u
                        text: modelData.fill !== "" ? String(modelData.fill).toUpperCase() : ""
                        font.pixelSize: 8.5 * card.u
                        color: modelData.ink !== "" ? modelData.ink : card.ink
                        opacity: 0.8
                    }
                }
            }
        }

        Column {
            x: card.pad + 2 * card.u
            y: chipColumn.y + chipColumn.height + 6 * card.u
            width: parent.width - card.pad * 2 - 4 * card.u
            spacing: 1 * card.u
            StyledText {
                width: parent.width
                text: card.fileName
                elide: Text.ElideMiddle
                font.pixelSize: 12 * card.u
                font.weight: Font.DemiBold
                color: card.ink
            }
            StyledText {
                width: parent.width
                text: card.detail
                elide: Text.ElideRight
                font.pixelSize: 9.5 * card.u
                color: card.muted
            }
        }
    }
}
