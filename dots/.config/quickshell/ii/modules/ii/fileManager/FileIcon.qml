import QtQuick
import Quickshell
import Quickshell.Widgets

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.clock.components

/**
 * The picture for a file: a thumbnail when there is one (images load straight from disk, video
 * and PDF thumbnails come from the helper's cache), else a Material symbol tinted by kind.
 */
Item {
    id: root

    property var entry: ({})
    property real thumbSize: 128
    property bool showThumb: true
    property string thumb: ""
    property bool starred: false
    /// Theme icon names to try, most specific first (from the icon pack)
    property var iconNames: []

    readonly property string kind: String(entry.kind ?? "file")
    readonly property bool direct: root.kind === "image" && Number(entry.size ?? 0) < 1500000
        && ["image/jpeg", "image/png", "image/webp", "image/gif", "image/bmp"].indexOf(String(entry.mime ?? "")) >= 0
    // The icon pack is recoloured with the wallpaper; the revision flips after each rebuild so the
    // path is looked up again and the (same-named) file is read from disk instead of the image cache
    readonly property int themeRev: TaskbarApps.iconThemeRevision
    readonly property string themed: {
        const _ = root.themeRev;
        for (const n of root.iconNames) {
            const p = Quickshell.iconPath(n, true);
            if (p.length > 0)
                return p;
        }
        return "";
    }
    readonly property string source: {
        if (root.showThumb && root.thumb.length > 0)
            return "file://" + root.thumb;
        if (root.showThumb && root.direct)
            return "file://" + root.entry.path;
        return "";
    }

    readonly property var symbols: ({
        folder: "folder", image: "image", video: "movie", audio: "audio_file", pdf: "picture_as_pdf",
        archive: "folder_zip", code: "code", text: "description", sheet: "table_chart", slides: "slideshow",
        doc: "article", book: "menu_book", font: "text_fields", exec: "terminal", file: "draft"
    })
    readonly property var tints: ({
        folder: ClockStyle.colPrimary, image: ClockStyle.colTertiary, video: "#e0679a", audio: "#e9a23b",
        pdf: "#e5604d", archive: "#b58a4f", code: "#4fb3a9", text: ClockStyle.colOnSurfaceVariant,
        sheet: "#5cb85c", slides: "#e8883a", doc: "#5b8def", book: "#9b72d6", font: ClockStyle.colOnSurfaceVariant,
        exec: "#4fb35c", file: ClockStyle.colOnSurfaceVariant
    })

    implicitWidth: 64
    implicitHeight: 64

    MaterialSymbol {
        anchors.centerIn: parent
        visible: thumbImage.status !== Image.Ready && themedImage.status !== Image.Ready
        text: root.entry.broken ? "link_off" : (root.symbols[root.kind] ?? "draft")
        iconSize: Math.min(root.width, root.height) * 0.78
        fill: root.kind === "folder" ? 1 : 0
        color: root.tints[root.kind] ?? ClockStyle.colOnSurfaceVariant
        opacity: root.entry.hidden ? 0.55 : 1
    }

    Image {
        id: themedImage
        anchors.fill: parent
        anchors.margins: 1
        visible: thumbImage.status !== Image.Ready && status === Image.Ready
        source: root.themed
        // the recoloured file keeps its path: never serve it from the shared pixmap cache
        cache: false
        sourceSize.width: Math.ceil(root.width * 2) + root.themeRev
        sourceSize.height: Math.ceil(root.height * 2) + root.themeRev
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        opacity: root.entry.hidden ? 0.55 : 1
    }

    ClippingRectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: Math.min(12, width * 0.1)
        color: "transparent"
        visible: thumbImage.status === Image.Ready
        Image {
            id: thumbImage
            anchors.fill: parent
            source: root.source
            sourceSize.width: root.thumbSize
            sourceSize.height: root.thumbSize
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            autoTransform: true
        }
    }

    // Starred files carry a small star
    Rectangle {
        visible: root.starred
        anchors.left: parent.left
        anchors.top: parent.top
        width: Math.min(22, root.width * 0.34)
        height: width
        radius: width / 2
        color: ClockStyle.colTertiaryContainer
        MaterialSymbol {
            anchors.centerIn: parent
            text: "star"
            fill: 1
            iconSize: parent.width * 0.72
            color: ClockStyle.colOnTertiaryContainer
        }
    }

    // A link arrow
    Rectangle {
        visible: root.entry.isLink === true
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Math.min(22, root.width * 0.34)
        height: width
        radius: width / 2
        color: ClockStyle.colSurfaceHighest
        MaterialSymbol {
            anchors.centerIn: parent
            text: "arrow_outward"
            iconSize: parent.width * 0.7
            color: ClockStyle.colOnSurface
        }
    }
}
