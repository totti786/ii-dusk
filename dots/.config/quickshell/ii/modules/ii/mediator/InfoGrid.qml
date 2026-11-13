pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

/// Label over value cells flowing across the page: no card, so it sits on the page itself
Flow {
    id: root

    /// [{ k: "Director", v: "Name" }]; empty values are dropped
    property var rows: []

    visible: root.shown.length > 0
    readonly property var shown: root.rows.filter(r => r && String(r.v ?? "") !== "")
    spacing: 28

    Repeater {
        model: root.shown
        delegate: Column {
            id: cell
            required property var modelData
            spacing: 2
            width: Math.min(Math.max(valueText.implicitWidth, keyText.implicitWidth), 360)
            StyledText {
                id: keyText
                text: cell.modelData.k
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            StyledText {
                id: valueText
                width: parent.width
                wrapMode: Text.Wrap
                text: String(cell.modelData.v)
                color: Appearance.colors.colOnLayer0
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
    }
}
