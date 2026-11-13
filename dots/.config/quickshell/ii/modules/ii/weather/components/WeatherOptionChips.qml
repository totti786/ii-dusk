pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import ".."

/**
 * A wrapping row of mutually exclusive chips. Used for units, range and other compact
 * settings where a popup would be more chrome than choice.
 */
Flow {
    id: root

    property var options: []
    property var value: undefined
    property bool compact: false

    signal selected(var value)

    spacing: 6

    Repeater {
        model: root.options

        WeatherChip {
            required property var modelData
            label: modelData.label
            compact: root.compact
            selected: root.value === modelData.value
            onClicked: root.selected(modelData.value)
        }
    }
}
