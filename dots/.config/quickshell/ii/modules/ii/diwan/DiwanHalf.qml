import QtQuick

import qs.modules.common

/**
 * One half-line (a hemistich) of verse. With `justify` its word gaps are opened a little so the
 * line fills its slot the way a printed diwan sets it; a line far shorter than the slot is
 * centred instead of stretched into gaps that read as holes.
 */
Text {
    id: root

    /// The width this half-line is set into
    property real slot: 300
    property real size: 30
    property string family: "Amiri"
    property bool justify: true
    /// One line that never wraps: a half-line a little wider than its slot shrinks to fit
    property bool fit: false

    readonly property int gaps: Math.max(0, root.text.trim().split(/\s+/).length - 1)
    readonly property real spacing: root.justify && root.gaps > 0
        ? Math.max(0, Math.min((root.slot - metrics.advanceWidth) / root.gaps, root.size * 0.65)) : 0

    width: root.slot
    color: Appearance.colors.colOnLayer0
    textFormat: Text.PlainText
    wrapMode: root.fit ? Text.NoWrap : Text.Wrap
    fontSizeMode: root.fit ? Text.HorizontalFit : Text.FixedSize
    minimumPixelSize: root.size * 0.7
    horizontalAlignment: Text.AlignHCenter
    lineHeight: 1.5
    lineHeightMode: Text.ProportionalHeight
    font.family: root.family
    font.pixelSize: root.size
    font.wordSpacing: root.spacing
    font.hintingPreference: Font.PreferNoHinting

    TextMetrics {
        id: metrics
        text: root.text
        font.family: root.family
        font.pixelSize: root.size
    }
}
