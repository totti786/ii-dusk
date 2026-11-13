import QtQuick

import qs.modules.common
import qs.modules.ii.clock.components

/**
 * Renders Anki's sanitised card HTML with Qt's rich-text engine.
 *
 * The bridge keeps the HTML to tags Qt understands and rewrites media paths; links are
 * opened externally, never inside the shell.
 */
Item {
    id: root

    property string html: ""
    property int pixelSize: 28
    property bool centered: true
    property color textColor: ClockStyle.colOnSurface
    property alias textItem: body

    implicitHeight: body.implicitHeight

    Text {
        id: body
        width: root.width
        text: root.html
        textFormat: Text.RichText
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        horizontalAlignment: root.centered ? Text.AlignHCenter : Text.AlignLeft
        color: root.textColor
        linkColor: ClockStyle.colPrimary
        font.family: Appearance.font.family.main
        font.pixelSize: root.pixelSize
        lineHeight: 1.3
        onLinkActivated: link => {
            if (/^(https?|mailto):/i.test(link))
                Qt.openUrlExternally(link);
        }
    }
}
